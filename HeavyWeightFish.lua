--[[
    ★ PPINGYYY AUTO FISH ★  v2
    Auto Cast + Cast Delay + Anchor Bar (minigame) + Auto Skill + Economy & Selling + Anti-AFK + Money Stats + Discord Webhook + "4896 Polar Bear" intro

    Game logic used (taken from the working fishing script):
      Character attributes : Type ("Fishing Rod"), Fishing, Minigame, CDForTheNextThrow, Swimming
      PlayerGui            : MainGui.Fishing (Visible while the reel minigame is open)
                             .BarFrame.Bar / .PerfectButton / .Charge / .BossFightBar / .HPPlayer.ProgressionBar
      ReplicatedStorage    : Events.Fishing            -> FireServer(root.CFrame)       (cast)
                             Events.ToggleHotbar       -> InvokeServer(slot)            (equip rod)
                             Events.UpdateFishProgression -> FireServer()               (anchor bar progress)
                             Events.Slam / Events.Charge  -> FireServer("Perfect") / FireServer(100)
                                                         + OnClientEvent(replyRemote) -> replyRemote:FireServer(...)
                             Events.UseSkill / Events.TriggerMinigameSkill -> FireServer("Z"/"X"/"C"/"V")
                             Events.SellFish           -> FireServer("All")
                             Events.FavoriteItem       -> FireServer(item)
                             Data[UserId].Hotbar / Inventory (items have .Favorite) / InventoryLimit
    Anti-AFK   : Player.Idled + VirtualUser (click) so Roblox does not kick you after 20 min idle
    Money stats: Data[UserId].Cash / FishCaught / FishingRod / EquippedBait
    Webhook    : executor request() -> Discord webhook (embed), interval slider 1-120 min
    RightControl hides / shows the window.
]]

if not game:IsLoaded() then game.Loaded:Wait() end

local env = (getgenv and getgenv()) or _G
if env.PPAutoFishUnload then pcall(env.PPAutoFishUnload) end -- remove the previous copy (no double loops)

---------------------------------------------------------------------
-- Services
---------------------------------------------------------------------
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")
local HttpService = game:GetService("HttpService")
local lp = Players.LocalPlayer

local VIM = nil
pcall(function() VIM = game:GetService("VirtualInputManager") end)

---------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------
local Config = {
    -- auto cast
    AutoCast = false,
    CastDelay = 1.0,          -- seconds to wait after a catch / when idle before casting
    StopWhenFull = true,      -- stop casting when the inventory is full
    -- minigame
    AnchorBar = true,         -- keep the bar centred + send fish progression + boss bar / hp bar helpers
    AutoSlam = true,          -- answer / press the Slam (Perfect) prompt
    AutoCharge = true,        -- answer / press the Charge prompt
    -- skills
    AutoSkill = false,
    SkillMode = "Remote",     -- "Remote" = UseSkill remotes during the minigame, "Keys" = press Z/X/C/V
    -- economy
    AutoSell = false,
    SellInterval = 30,        -- seconds between automatic sells
    AutoFavourite = false,    -- protect the chosen fish from being sold
    FavouriteFishName = "Colossal Tigerfish",
    MaterialFarming = false,  -- protect the craft-material fish from being sold
    -- utilities
    AntiAFK = true,
    WebhookEnabled = false,
    WebhookUrl = "",
    WebhookInterval = 15,     -- minutes between webhook reports
}

local DELAY_MIN, DELAY_MAX, DELAY_STEP = 0.5, 5.0, 0.1
local SELL_MIN, SELL_MAX = 10, 300
local SKILL_INTERVAL = 0.15   -- remote skill interval (same as the working script)
local KEY_INTERVAL = 0.5      -- key press interval (same as the old Auto Skills Engine)
local RECAST_TIMEOUT = 15     -- line in the water this long with no bite -> cast again
local EQUIP_INTERVAL = 1.5
local MIN_RECAST_GAP = 1.0    -- never send two casts closer than this
local PROGRESS_INTERVAL = 0.08 -- UpdateFishProgression rate (same as the working script)
local BUTTON_INTERVAL = 0.15   -- Slam / Charge button presses
local PROTECT_INTERVAL = 1.5   -- how often the favourite protection runs
local FAV_RETRY = 3.0          -- never re-send FavoriteItem for the same item sooner than this
local FULL_SELL_GAP = 5.0      -- sell at most every 5s while the inventory is full
local NANA_CFRAME = CFrame.new(-203.5, 7.3, 107.1)
local SKILL_KEYS = { "Z", "X", "C", "V" }
local KEY_CODES = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V }

local FISH_LIST = {
    "Colossal Tigerfish", "Heavenpiercer Turtle", "Golden Guardian Fish", "Crimson Electric Eel",
    "Frost Kingfish", "Ascended Perch", "Primordial Kunfish Overlord", "Warbringer Shark",
    "Mountain Fish", "Tiger Mirefish", "Mirage Lanternfish", "Octoparasitic Fish",
}

local CRAFT_FISH = {
    ["Mountain Fish"] = true, ["Catfish"] = true, ["Crimson Catfish"] = true, ["Scarlet Fish"] = true,
    ["Elder Scarlet Fish"] = true, ["Octoparasitic Fish"] = true, ["Tiger Mirefish"] = true,
    ["Mirage Lanternfish"] = true, ["Golden Guardian Fish"] = true, ["Frost Kingfish"] = true,
    ["Frost Queenfish"] = true, ["Rainbow Dragonfish"] = true, ["Sanguine Fish"] = true,
}

---------------------------------------------------------------------
-- Runtime state
---------------------------------------------------------------------
local running = true
local conns = {}

local idleSince = nil
local lastCastTime = 0
local lastEquipTime = 0
local equipBusy = false
local equipAttempts = 0
local fishingStartTime = 0
local wasFishing = false
local lastSkillTime = 0
local lastKeyTime = 0
local keyBusy = false
local lastProgressTime = 0
local lastSlamTime = 0
local lastChargeTime = 0
local lastSellTime = 0
local lastProtectTime = 0
local sellBusy = false
local sellNote = ""
local sellNoteTime = 0
local favRequested = setmetatable({}, { __mode = "k" })
local hooked = {}
local lastErr = nil
local lastUiTime = 0

local statusText = "Starting..."
local detailText = ""

---------------------------------------------------------------------
-- Game helpers
---------------------------------------------------------------------
local function getData()
    local d = RS:FindFirstChild("Data")
    return d and d:FindFirstChild(tostring(lp.UserId))
end

local function findRodSlot(pData)
    local hb = pData and pData:FindFirstChild("Hotbar")
    if hb then
        for _, item in ipairs(hb:GetChildren()) do
            local vName = item:FindFirstChild("ValueName")
            if vName then
                local n = string.lower(tostring(vName.Value))
                if string.find(n, "rod", 1, true) and not string.find(n, "inventory", 1, true) then
                    return item.Name
                end
            end
        end
    end
    return "1"
end

local function inventoryFull(pData)
    if not pData then return false end
    local limit = pData:FindFirstChild("InventoryLimit")
    if not limit then return false end
    local count = 0
    local inv = pData:FindFirstChild("Inventory")
    if inv then count = count + #inv:GetChildren() end
    local hb = pData:FindFirstChild("Hotbar")
    if hb then
        for _, item in ipairs(hb:GetChildren()) do
            local q = item:FindFirstChild("Quantity")
            if q then count = count + q.Value else count = count + 1 end
        end
    end
    return count >= limit.Value
end

local function tryEquipRod(Events, pData, now)
    if equipBusy then return end
    local toggle = Events:FindFirstChild("ToggleHotbar")
    if not toggle then return end
    equipBusy = true
    lastEquipTime = now
    equipAttempts = equipAttempts + 1
    local slot = findRodSlot(pData)
    task.spawn(function()
        pcall(function() toggle:InvokeServer(slot) end)
        equipBusy = false
    end)
end

local function pressKeys()
    if keyBusy or not VIM then return end
    keyBusy = true
    task.spawn(function()
        for _, code in ipairs(KEY_CODES) do
            if not running or not Config.AutoSkill or Config.SkillMode ~= "Keys" then break end
            pcall(function()
                VIM:SendKeyEvent(true, code, false, game)
                task.wait(0.05)
                VIM:SendKeyEvent(false, code, false, game)
            end)
        end
        keyBusy = false
    end)
end

-- Economy: mark the protected fish as favourite (returns how many requests were sent)
local function protectFish(pData, now)
    if not (Config.AutoFavourite or Config.MaterialFarming) then return 0 end
    local Events = RS:FindFirstChild("Events")
    local favRemote = Events and Events:FindFirstChild("FavoriteItem")
    local inv = pData and pData:FindFirstChild("Inventory")
    if not favRemote or not inv then return 0 end
    local sent = 0
    for _, item in ipairs(inv:GetChildren()) do
        local fav = item:FindFirstChild("Favorite")
        local isFav = (fav ~= nil and fav.Value == true)
        if not isFav then
            local name = item.Name
            local want = (Config.MaterialFarming and CRAFT_FISH[name]) or (Config.AutoFavourite and name == Config.FavouriteFishName)
            if want then
                local last = favRequested[item]
                if last == nil or now - last >= FAV_RETRY then
                    favRequested[item] = now
                    pcall(function() favRemote:FireServer(item) end)
                    sent = sent + 1
                end
            end
        end
    end
    return sent
end

-- Economy: protect first, give the server a moment, then sell everything that is not favourited
local function doSell(reason)
    if sellBusy then return end
    local Events = RS:FindFirstChild("Events")
    local sellRemote = Events and Events:FindFirstChild("SellFish")
    if not sellRemote then return end
    sellBusy = true
    lastSellTime = tick()
    task.spawn(function()
        pcall(function()
            local sent = protectFish(getData(), tick())
            if sent > 0 then task.wait(0.4) end
            sellRemote:FireServer("All")
            sellNote = "Sold fish (" .. reason .. ")"
            sellNoteTime = tick()
        end)
        lastSellTime = tick()
        sellBusy = false
    end)
end

local function sellNow()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    root.CFrame = NANA_CFRAME
    task.spawn(function()
        task.wait(0.3)
        doSell("Nana")
    end)
end

-- Minigame: the server sends a reply-remote with Slam / Charge, answer it
local function hookRemotes(Events)
    local slam = Events:FindFirstChild("Slam")
    if slam and not hooked.Slam then
        local ok, c = pcall(function()
            return slam.OnClientEvent:Connect(function(obj)
                if running and Config.AutoSlam and typeof(obj) == "Instance" then
                    pcall(function() obj:FireServer("Perfect") end)
                end
            end)
        end)
        if ok and c then hooked.Slam = true; conns[#conns + 1] = c end
    end
    local charge = Events:FindFirstChild("Charge")
    if charge and not hooked.Charge then
        local ok, c = pcall(function()
            return charge.OnClientEvent:Connect(function(obj)
                if running and Config.AutoCharge and typeof(obj) == "Instance" then
                    pcall(function() obj:FireServer(100) end)
                end
            end)
        end)
        if ok and c then hooked.Charge = true; conns[#conns + 1] = c end
    end
end

local function yn(v) return v and "yes" or "no" end

---------------------------------------------------------------------
-- Anti-AFK / Money Stats / Discord Webhook (helpers)
---------------------------------------------------------------------
local WEBHOOK_MIN, WEBHOOK_MAX = 1, 120   -- minutes
local AFK_KEEPALIVE = 600                 -- extra anti-afk ping every 10 min (Roblox kicks idle players after 20 min)
local SETTINGS_FILE = "PPINGYYY_AutoFish.json"
local WEBHOOK_PREFIXES = {
    "https://discord.com/api/webhooks/", "https://discordapp.com/api/webhooks/",
    "https://ptb.discord.com/api/webhooks/", "https://canary.discord.com/api/webhooks/",
}

local ui = {}            -- UI setters, filled when the UI is built
local uiReady = false
local settingsDirtyAt = nil
local session = { startTime = tick(), startCash = nil, startFish = nil }
local afk = { pings = 0, last = tick() }
local webhookBusy = false
local lastWebhookTime = tick()   -- when the last report was sent / when the timer was (re)started
local webhookStatus = "Idle"
local lastStatsTime = 0

-- settings that survive a re-execute (webhook url + interval + anti-afk) -------------
local function saveSettings()
    if not writefile then return end
    pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode({
            WebhookUrl = Config.WebhookUrl, WebhookInterval = Config.WebhookInterval, AntiAFK = Config.AntiAFK,
        }))
    end)
end

local function markDirty()
    if uiReady then settingsDirtyAt = tick() end
end

local function loadSettings()
    if not (isfile and readfile) then return end
    pcall(function()
        if isfile(SETTINGS_FILE) then
            local data = HttpService:JSONDecode(readfile(SETTINGS_FILE))
            if type(data) == "table" then
                if type(data.WebhookUrl) == "string" then Config.WebhookUrl = data.WebhookUrl end
                if type(data.WebhookInterval) == "number" then
                    Config.WebhookInterval = math.clamp(math.floor(data.WebhookInterval), WEBHOOK_MIN, WEBHOOK_MAX)
                end
                if type(data.AntiAFK) == "boolean" then Config.AntiAFK = data.AntiAFK end
            end
        end
    end)
end
loadSettings()

-- formatting ------------------------------------------------------------------------
local function commas(n)
    local s = string.format("%.0f", math.abs(n))
    local k
    while true do
        s, k = string.gsub(s, "^(%d+)(%d%d%d)", "%1,%2")
        if k == 0 then break end
    end
    if n < 0 and s ~= "0" then s = "-" .. s end
    return s
end

local function signedMoney(n)
    if n >= 0 then return "+$" .. commas(n) end
    return "-$" .. commas(math.abs(n))
end

local function fmtTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%02d:%02d:%02d", math.floor(sec / 3600), math.floor((sec % 3600) / 60), sec % 60)
end

local function fmtAgo(sec)
    sec = math.max(0, math.floor(sec))
    if sec < 60 then return sec .. "s ago" end
    return math.floor(sec / 60) .. "m ago"
end

local function perHour(delta, elapsed)
    if elapsed < 10 then return 0 end
    return delta / (elapsed / 3600)
end

-- Anti-AFK ----------------------------------------------------------------------------
-- Roblox fires Player.Idled after ~20 minutes without input and then kicks the player.
-- VirtualUser lets us fake a click so the idle timer is reset.
local function afkPing()
    local ok = pcall(function()
        local vu = game:GetService("VirtualUser")
        vu:CaptureController()
        vu:ClickButton2(Vector2.new(0, 0))
    end)
    if ok then
        afk.pings = afk.pings + 1
        afk.last = tick()
    end
    return ok
end

conns[#conns + 1] = lp.Idled:Connect(function()
    if running and Config.AntiAFK then afkPing() end
end)

-- Money stats (Data[UserId].Cash / FishCaught / FishingRod / EquippedBait) ---------------
local function readStats()
    local pData = getData()
    if not pData then return nil end
    local function num(name)
        local v = pData:FindFirstChild(name)
        return v and tonumber(v.Value) or nil
    end
    local function str(name)
        local v = pData:FindFirstChild(name)
        local s = v and tostring(v.Value) or ""
        if s == "" then s = "None" end
        return s
    end
    return { cash = num("Cash"), fish = num("FishCaught"), rod = str("FishingRod"), bait = str("EquippedBait") }
end

local function resetSession()
    session.startTime = tick()
    session.startCash = nil
    session.startFish = nil
end

local function sessionNumbers(st, now)
    local elapsed = now - session.startTime
    local netCash = (st.cash and session.startCash) and (st.cash - session.startCash) or 0
    local fishGain = (st.fish and session.startFish) and (st.fish - session.startFish) or 0
    return elapsed, netCash, fishGain
end

-- Discord webhook -----------------------------------------------------------------------
local function validWebhook(url)
    if type(url) ~= "string" or string.find(url, "%s") then return false end
    for _, pre in ipairs(WEBHOOK_PREFIXES) do
        if string.sub(url, 1, #pre) == pre and #url > #pre + 10 then return true end
    end
    return false
end

local function getHttpRequest()
    local getters = {
        function() return request end,
        function() return http_request end,
        function() return syn and syn.request end,
        function() return http and http.request end,
        function() return fluxus and fluxus.request end,
    }
    for _, g in ipairs(getters) do
        local ok, fn = pcall(g)
        if ok and type(fn) == "function" then return fn end
    end
    return nil
end

local function buildPayload(st, reason)
    local now = tick()
    local elapsed, netCash, fishGain = sessionNumbers(st, now)
    local desc = (reason == "test") and "Test report" or ("Scheduled report (every " .. Config.WebhookInterval .. " min)")
    local fields = {
        { name = "👤 Player", value = lp.DisplayName .. " (@" .. lp.Name .. ")", inline = true },
        { name = "💰 Cash", value = "$" .. commas(st.cash or 0), inline = true },
        { name = "📈 Net Cash (session)", value = signedMoney(netCash), inline = true },
        { name = "⏱️ Cash / hour", value = signedMoney(perHour(netCash, elapsed)), inline = true },
        { name = "🐟 Fish Caught", value = commas(st.fish or 0), inline = true },
        { name = "🎣 Fish (session)", value = "+" .. commas(fishGain) .. "  (" .. commas(perHour(fishGain, elapsed)) .. "/h)", inline = true },
        { name = "🪝 Rod", value = st.rod, inline = true },
        { name = "🪱 Bait", value = st.bait, inline = true },
        { name = "🕒 Session Time", value = fmtTime(elapsed), inline = true },
    }
    return {
        username = "4896 Polar Bear",
        embeds = { {
            title = "📊 Money Stats Report",
            description = desc,
            color = 57855,
            fields = fields,
            footer = { text = "4896 Polar Bear • Auto Fish" },
            timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
        } },
    }
end

local function sendWebhook(reason)
    if webhookBusy then return end
    local url = Config.WebhookUrl
    if not validWebhook(url) then
        webhookStatus = "Invalid webhook URL"
        return
    end
    local req = getHttpRequest()
    if not req then
        webhookStatus = "Executor has no request() function"
        return
    end
    local st = readStats()
    if not st then
        webhookStatus = "No player data found"
        return
    end
    webhookBusy = true
    lastWebhookTime = tick()
    webhookStatus = "Sending..."
    task.spawn(function()
        local ok, resp = pcall(function()
            return req({
                Url = url, Method = "POST", Headers = { ["Content-Type"] = "application/json" },
                Body = HttpService:JSONEncode(buildPayload(st, reason)),
            })
        end)
        if ok and type(resp) == "table" then
            local code = resp.StatusCode or resp.status_code
            local good = (type(code) == "number" and code >= 200 and code < 300) or (code == nil and resp.Success == true)
            if good then
                webhookStatus = "Sent OK (" .. os.date("%H:%M:%S") .. ")"
            else
                webhookStatus = "Failed: HTTP " .. tostring(code)
            end
        else
            webhookStatus = "Failed: " .. tostring(resp)
        end
        webhookBusy = false
    end)
end

-- runs every frame next to the cast engine (separate pcall, so one can't break the other)
local function utilityStep()
    local now = tick()

    -- anti-afk keep-alive
    if Config.AntiAFK and (now - afk.last >= AFK_KEEPALIVE) then afkPing() end

    -- debounced settings save
    if settingsDirtyAt and now - settingsDirtyAt >= 1.5 then
        settingsDirtyAt = nil
        saveSettings()
    end

    -- webhook timer
    if Config.WebhookEnabled and not webhookBusy and (now - lastWebhookTime >= Config.WebhookInterval * 60) then
        sendWebhook("timer")
    end

    -- once per second: refresh the stats panel
    if now - lastStatsTime < 1 then return end
    lastStatsTime = now
    if not ui.stats then return end

    local S = ui.stats
    local st = readStats()
    if not st or not st.cash then
        S.cash("waiting for data...")
    else
        if session.startCash == nil then
            session.startCash = st.cash
            session.startFish = st.fish
            session.startTime = now
        end
        local elapsed, netCash, fishGain = sessionNumbers(st, now)
        S.cash("$" .. commas(st.cash))
        S.net(signedMoney(netCash))
        S.cph(signedMoney(perHour(netCash, elapsed)))
        S.fish(commas(st.fish or 0))
        S.fsess("+" .. commas(fishGain))
        S.fph(commas(perHour(fishGain, elapsed)) .. " / h")
        S.time(fmtTime(elapsed))
        S.rod(st.rod)
        S.bait(st.bait)
    end

    if ui.afk then
        if Config.AntiAFK then
            ui.afk("ON - last ping " .. fmtAgo(now - afk.last) .. " (" .. afk.pings .. ")")
        else
            ui.afk("OFF")
        end
    end
    if ui.hook then
        if Config.WebhookEnabled then
            local left = Config.WebhookInterval * 60 - (now - lastWebhookTime)
            ui.hook.next(fmtTime(math.max(0, left)))
        else
            ui.hook.next("Off")
        end
        ui.hook.status(webhookStatus)
    end
end

---------------------------------------------------------------------
-- Engine (one Heartbeat connection)
---------------------------------------------------------------------
local function engineStep()
    local now = tick()
    local char = lp.Character
    local root = char and char:FindFirstChild("HumanoidRootPart")
    if not char or not root then
        statusText = "Waiting for character..."
        detailText = ""
        return
    end

    local Events = RS:FindFirstChild("Events")
    if not Events then
        statusText = "ReplicatedStorage.Events not found (wrong game?)"
        detailText = ""
        return
    end
    hookRemotes(Events)

    local pData = getData()
    local pg = lp:FindFirstChild("PlayerGui")
    local fUI = pg and pg:FindFirstChild("MainGui") and pg.MainGui:FindFirstChild("Fishing")
    local uiVisible = (fUI ~= nil and fUI:IsA("GuiObject") and fUI.Visible) == true

    local rodType = char:GetAttribute("Type")
    local isFishing = char:GetAttribute("Fishing") == true
    local isMinigame = (char:GetAttribute("Minigame") == true) or uiVisible
    local isCD = char:GetAttribute("CDForTheNextThrow") == true
    local isSwimming = char:GetAttribute("Swimming") == true
    local hasRod = (rodType == "Fishing Rod")

    detailText = "Rod: " .. tostring(rodType) .. " | Fishing: " .. yn(isFishing) ..
        " | Minigame: " .. yn(isMinigame) .. " | CD: " .. yn(isCD)

    ----------------------------------------------------------------
    -- Auto Skill
    ----------------------------------------------------------------
    if Config.AutoSkill then
        if Config.SkillMode == "Remote" then
            if isMinigame and (now - lastSkillTime >= SKILL_INTERVAL) then
                lastSkillTime = now
                local useSkill = Events:FindFirstChild("UseSkill")
                local miniSkill = Events:FindFirstChild("TriggerMinigameSkill")
                for _, sk in ipairs(SKILL_KEYS) do
                    if useSkill then pcall(function() useSkill:FireServer(sk) end) end
                    if miniSkill then pcall(function() miniSkill:FireServer(sk) end) end
                end
            end
        else
            if (now - lastKeyTime >= KEY_INTERVAL) and not keyBusy then
                lastKeyTime = now
                pressKeys()
            end
        end
    end

    ----------------------------------------------------------------
    -- Economy & Selling (runs always - does not depend on Auto Cast)
    ----------------------------------------------------------------
    if (Config.AutoFavourite or Config.MaterialFarming) and (now - lastProtectTime >= PROTECT_INTERVAL) then
        lastProtectTime = now
        protectFish(pData, now)
    end
    if Config.AutoSell and not sellBusy then
        if now - lastSellTime >= Config.SellInterval then
            doSell("timer")
        elseif now - lastSellTime >= FULL_SELL_GAP and inventoryFull(pData) then
            doSell("inventory full")
        end
    end

    ----------------------------------------------------------------
    -- Track the cast timers
    ----------------------------------------------------------------
    if isFishing and not wasFishing then
        fishingStartTime = now
    elseif not isFishing then
        fishingStartTime = 0
    end
    wasFishing = isFishing

    if hasRod then equipAttempts = 0 end

    ----------------------------------------------------------------
    -- Minigame (Anchor Bar / Slam / Charge)
    ----------------------------------------------------------------
    if isMinigame then
        idleSince = nil
        statusText = "Reeling (minigame)"
        if uiVisible then
            if Config.AnchorBar then
                local barFrame = fUI:FindFirstChild("BarFrame")
                local bar = barFrame and barFrame:FindFirstChild("Bar")
                if bar then
                    pcall(function()
                        bar:TweenPosition(UDim2.new(0.5, 0, 0.5, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Linear, 0, true)
                        bar.Position = UDim2.new(0.5, 0, 0.5, 0)
                    end)
                end
                if now - lastProgressTime >= PROGRESS_INTERVAL then
                    lastProgressTime = now
                    local prog = Events:FindFirstChild("UpdateFishProgression")
                    if prog then pcall(function() prog:FireServer() end) end
                end
            end
            if Config.AutoSlam and (now - lastSlamTime >= BUTTON_INTERVAL) then
                local pb = fUI:FindFirstChild("PerfectButton")
                local slam = Events:FindFirstChild("Slam")
                if pb and pb.Visible and slam then
                    lastSlamTime = now
                    pcall(function() slam:FireServer() end)
                    pcall(function() slam:FireServer("Perfect") end)
                end
            end
            if Config.AutoCharge and (now - lastChargeTime >= BUTTON_INTERVAL) then
                local cb = fUI:FindFirstChild("Charge")
                local charge = Events:FindFirstChild("Charge")
                if cb and cb.Visible and charge then
                    lastChargeTime = now
                    pcall(function() charge:FireServer() end)
                    pcall(function() charge:FireServer(100) end)
                end
            end
        end
        return
    end

    ----------------------------------------------------------------
    -- Auto Cast
    ----------------------------------------------------------------
    if isFishing then
        idleSince = nil
        if Config.AutoCast and fishingStartTime > 0 and (now - fishingStartTime >= RECAST_TIMEOUT) then
            fishingStartTime = now
            local fishing = Events:FindFirstChild("Fishing")
            if fishing then pcall(function() fishing:FireServer(root.CFrame) end) end
            statusText = "No bite for " .. RECAST_TIMEOUT .. "s - recast"
        else
            statusText = "Waiting for a bite..."
        end
        return
    end

    -- idle: no line out, no minigame
    if idleSince == nil then idleSince = now end

    if not Config.AutoCast then
        statusText = "Auto Cast OFF"
        return
    end

    if not hasRod then
        if equipAttempts >= 4 then
            statusText = "Rod not detected (Type=" .. tostring(rodType) .. ") - hold your rod, then toggle Auto Cast"
        else
            statusText = "Equipping rod..."
            if now - lastEquipTime >= EQUIP_INTERVAL then
                tryEquipRod(Events, pData, now)
            end
        end
        return
    end

    if isSwimming then
        statusText = "Swimming - can't cast"
        return
    end
    if isCD then
        statusText = "Throw cooldown..."
        return
    end
    if Config.StopWhenFull and inventoryFull(pData) then
        statusText = "Inventory full - sell your fish"
        return
    end

    local fishing = Events:FindFirstChild("Fishing")
    if not fishing then
        statusText = "Events.Fishing not found"
        return
    end

    local waited = now - idleSince
    if waited < Config.CastDelay then
        statusText = string.format("Cast delay %.1f / %.1fs", waited, Config.CastDelay)
        return
    end
    if now - lastCastTime < math.max(MIN_RECAST_GAP, Config.CastDelay) then
        statusText = "Cast sent, waiting for the game..."
        return
    end

    pcall(function() fishing:FireServer(root.CFrame) end)
    lastCastTime = now
    statusText = "Casting!"
end

-- per-frame part of the Anchor Bar (keeps the bar centred before the game redraws it)
local function anchorRenderStep()
    if not running or not Config.AnchorBar then return end
    local pg = lp:FindFirstChild("PlayerGui")
    local mg = pg and pg:FindFirstChild("MainGui")
    local fUI = mg and mg:FindFirstChild("Fishing")
    if not (fUI and fUI:IsA("GuiObject") and fUI.Visible) then return end

    local barFrame = fUI:FindFirstChild("BarFrame")
    local bar = barFrame and barFrame:FindFirstChild("Bar")
    if bar then bar.Position = UDim2.new(0.5, 0, 0.5, 0) end

    local bossBar = fUI:FindFirstChild("BossFightBar")
    if bossBar and bossBar.Visible and bossBar:FindFirstChild("Bar") and bossBar:FindFirstChild("Hitbox") then
        bossBar.Bar.Position = bossBar.Hitbox.Position
    end

    local hp = fUI:FindFirstChild("HPPlayer")
    local pBar = hp and hp:FindFirstChild("ProgressionBar")
    if pBar and pBar:FindFirstChild("Bar") then
        pBar.Bar.Size = UDim2.new(1, 0, 1, 0)
    end

    local cutscene = mg and mg:FindFirstChild("Cutscene")
    if cutscene and cutscene:FindFirstChild("Hurt") then
        cutscene.Hurt.ImageTransparency = 1
    end
    local impact = pg and pg:FindFirstChild("Impact")
    local impactCut = impact and impact:FindFirstChild("Cutscene")
    if impactCut and impactCut:FindFirstChild("Hurt") then
        impactCut.Hurt.ImageTransparency = 1
    end
end

---------------------------------------------------------------------
-- UI
---------------------------------------------------------------------
local COL_BG = Color3.fromRGB(15, 15, 17)
local COL_ROW = Color3.fromRGB(20, 20, 25)
local COL_GREEN = Color3.fromRGB(0, 255, 150)
local COL_ON = Color3.fromRGB(0, 150, 80)
local COL_OFF = Color3.fromRGB(150, 0, 0)

local function new(class, props, parent)
    local inst = Instance.new(class)
    for k, v in pairs(props) do inst[k] = v end
    if parent then inst.Parent = parent end
    return inst
end

local function corner(inst, r)
    return new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, inst)
end

-- remove leftovers of an older copy
pcall(function()
    for _, root in ipairs({ game:GetService("CoreGui"), lp:FindFirstChild("PlayerGui") }) do
        if root then
            local old = root:FindFirstChild("PPINGYYY_AutoFish")
            if old then old:Destroy() end
        end
    end
end)

local function attachGui(gui)
    local getters = {
        function() return gethui and gethui() end,
        function() return game:GetService("CoreGui") end,
    }
    for _, getter in ipairs(getters) do
        local ok, p = pcall(getter)
        if ok and p then
            local ok2 = pcall(function() gui.Parent = p end)
            if ok2 and gui.Parent == p then return end
        end
    end
    gui.Parent = lp:WaitForChild("PlayerGui")
end

local sg = new("ScreenGui", { Name = "PPINGYYY_AutoFish", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
attachGui(sg)

local function makeSound(id)
    local s = new("Sound", { Volume = 1 }, sg)
    pcall(function() s.SoundId = "rbxassetid://" .. id end)
    return s
end
local clickSound = makeSound("139719503904449")
local castSound = makeSound("119135010875996")
local skillSound = makeSound("72321534878838")
local sellSound = makeSound("90531793028786")
local deleteSound = makeSound("154157386")
local function play(s) pcall(function() s:Play() end) end

local FULL_SIZE = UDim2.new(0, 360, 0, 480)
local MIN_SIZE = UDim2.new(0, 360, 0, 40)

local Main = new("Frame", {
    Size = FULL_SIZE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = COL_BG, BorderSizePixel = 0, ClipsDescendants = true,
}, sg)
corner(Main, 10)
new("UIStroke", { Color = COL_GREEN, Thickness = 1.5 }, Main)

local TitleBar = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, Main)
new("TextLabel", {
    Size = UDim2.new(1, -80, 1, 0), Position = UDim2.new(0, 12, 0, 0), BackgroundTransparency = 1,
    Text = "★ PPINGYYY AUTO FISH ★", TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)

local CloseBtn = new("TextButton", {
    Size = UDim2.new(0, 25, 0, 25), Position = UDim2.new(1, -35, 0, 8), Text = "X", Font = Enum.Font.GothamBold,
    TextSize = 12, BackgroundColor3 = COL_OFF, TextColor3 = Color3.new(1, 1, 1),
}, TitleBar)
corner(CloseBtn, 5)

local MinBtn = new("TextButton", {
    Size = UDim2.new(0, 25, 0, 25), Position = UDim2.new(1, -65, 0, 8), Text = "—", Font = Enum.Font.GothamBold,
    TextSize = 12, BackgroundColor3 = Color3.fromRGB(0, 100, 200), TextColor3 = Color3.new(1, 1, 1),
}, TitleBar)
corner(MinBtn, 5)

-- scrolling body (all the controls) ----------------------------------
local Body = new("ScrollingFrame", {
    Size = UDim2.new(1, 0, 1, -122), Position = UDim2.new(0, 0, 0, 40), BackgroundTransparency = 1,
    BorderSizePixel = 0, ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0),
    AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y,
}, Main)
new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, Body)
new("UIPadding", {
    PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 8),
}, Body)

local orderCounter = 0
local function nextOrder()
    orderCounter = orderCounter + 1
    return orderCounter
end

local function section(text)
    return new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, LayoutOrder = nextOrder(),
        Text = text, TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, Body)
end

local function toggleButton(label, h, initial, onChange)
    local state = initial
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, h), LayoutOrder = nextOrder(), Font = Enum.Font.GothamBold,
        TextSize = 11, TextColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, Body)
    corner(btn, 6)
    local function refresh()
        btn.Text = label .. ": " .. (state and "ON" or "OFF")
        btn.BackgroundColor3 = state and COL_ON or COL_OFF
    end
    refresh()
    btn.MouseButton1Click:Connect(function()
        state = not state
        refresh()
        onChange(state)
    end)
    return btn
end

local function actionButton(text, h, onClick)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, h), LayoutOrder = nextOrder(), Font = Enum.Font.GothamBold, TextSize = 11,
        Text = text, BackgroundColor3 = Color3.fromRGB(20, 30, 40), TextColor3 = COL_GREEN, BorderSizePixel = 0,
    }, Body)
    corner(btn, 6)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- slider with - / + buttons. Returns a setter.
local function makeSlider(title, unit, vmin, vmax, snap, btnStep, decimals, initial, onChange)
    local box = new("Frame", { Size = UDim2.new(1, 0, 0, 52), BackgroundColor3 = COL_ROW, BorderSizePixel = 0, LayoutOrder = nextOrder() }, Body)
    corner(box, 6)

    local label = new("TextLabel", {
        Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 4), BackgroundTransparency = 1,
        Text = "", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, box)

    local function stepBtn(text, pos)
        local b = new("TextButton", {
            Size = UDim2.new(0, 26, 0, 22), Position = pos, Text = text, Font = Enum.Font.GothamBold,
            TextSize = 14, BackgroundColor3 = Color3.fromRGB(40, 40, 45), TextColor3 = COL_GREEN, BorderSizePixel = 0,
        }, box)
        corner(b, 5)
        return b
    end
    local minus = stepBtn("-", UDim2.new(0, 10, 0, 26))
    local plus = stepBtn("+", UDim2.new(1, -36, 0, 26))

    local hit = new("Frame", { Size = UDim2.new(1, -92, 0, 24), Position = UDim2.new(0, 46, 0, 25), BackgroundTransparency = 1 }, box)
    local track = new("Frame", {
        Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0.5, -3), BackgroundColor3 = Color3.fromRGB(45, 45, 50), BorderSizePixel = 0,
    }, hit)
    corner(track, 3)
    local fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL_GREEN, BorderSizePixel = 0 }, track)
    corner(fill, 3)
    local knob = new("Frame", {
        Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
        BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2,
    }, track)
    corner(knob, 7)

    local fmt = "%s: %." .. decimals .. "f %s   (%." .. decimals .. "f - %." .. decimals .. "f)"
    local scale = 10 ^ decimals
    local function setValue(v)
        v = math.floor(v / snap + 0.5) * snap
        v = math.clamp(v, vmin, vmax)
        v = math.floor(v * scale + 0.5) / scale
        label.Text = string.format(fmt, title, v, unit, vmin, vmax)
        local p = (v - vmin) / (vmax - vmin)
        fill.Size = UDim2.new(p, 0, 1, 0)
        knob.Position = UDim2.new(p, 0, 0.5, 0)
        onChange(v)
        return v
    end
    local current = setValue(initial)

    local sliding = false
    local function updateFromX(x)
        local rel = math.clamp((x - hit.AbsolutePosition.X) / math.max(hit.AbsoluteSize.X, 1), 0, 1)
        current = setValue(vmin + (vmax - vmin) * rel)
    end
    hit.InputBegan:Connect(function(input)
        if isPointer(input) then
            sliding = true
            play(clickSound)
            updateFromX(input.Position.X)
        end
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if sliding and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            updateFromX(input.Position.X)
        end
    end)
    conns[#conns + 1] = UserInputService.InputEnded:Connect(function(input)
        if isPointer(input) then sliding = false end
    end)
    minus.MouseButton1Click:Connect(function() play(clickSound); current = setValue(current - btnStep) end)
    plus.MouseButton1Click:Connect(function() play(clickSound); current = setValue(current + btnStep) end)
    return setValue
end

-- dropdown (button + inline list)
local function makeDropdown(title, options, initial, onPick)
    local selected = initial
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(),
    }, Body)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, holder)

    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Font = Enum.Font.GothamBold, TextSize = 10,
        BackgroundColor3 = COL_ROW, TextColor3 = COL_GREEN, BorderSizePixel = 0,
    }, holder)
    corner(btn, 6)

    local list = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 110), LayoutOrder = 2, BackgroundColor3 = COL_ROW, BorderSizePixel = 0,
        ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y, Visible = false,
    }, holder)
    corner(list, 6)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, list)

    local optionButtons = {}
    local function refresh()
        btn.Text = title .. ": " .. tostring(selected) .. (list.Visible and "  ^" or "  v")
        for name, b in pairs(optionButtons) do
            b.TextColor3 = (name == selected) and COL_GREEN or Color3.new(1, 1, 1)
            b.BackgroundColor3 = (name == selected) and Color3.fromRGB(0, 70, 45) or COL_ROW
        end
    end
    for i, name in ipairs(options) do
        local ob = new("TextButton", {
            Size = UDim2.new(1, -4, 0, 22), LayoutOrder = i, Text = name, Font = Enum.Font.Gotham, TextSize = 10,
            BackgroundColor3 = COL_ROW, TextColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
        }, list)
        corner(ob, 4)
        optionButtons[name] = ob
        ob.MouseButton1Click:Connect(function()
            play(clickSound)
            selected = name
            list.Visible = false
            refresh()
            onPick(name)
        end)
    end
    btn.MouseButton1Click:Connect(function()
        play(clickSound)
        list.Visible = not list.Visible
        refresh()
    end)
    refresh()
end

-- 🎣 Auto Cast ------------------------------------------------------
section("🎣 AUTO CAST")
toggleButton("Auto Cast Rod", 32, Config.AutoCast, function(v)
    play(castSound)
    Config.AutoCast = v
    equipAttempts = 0
    idleSince = nil
end)
makeSlider("Cast Delay", "s", DELAY_MIN, DELAY_MAX, DELAY_STEP, DELAY_STEP, 1, Config.CastDelay, function(v)
    Config.CastDelay = v
end)
toggleButton("Stop When Inventory Full", 28, Config.StopWhenFull, function(v)
    play(clickSound)
    Config.StopWhenFull = v
end)

-- 🚀 Minigame ---------------------------------------------------------
section("🚀 MINIGAME")
toggleButton("Anchor Bar (Minigame)", 32, Config.AnchorBar, function(v)
    play(clickSound)
    Config.AnchorBar = v
end)
toggleButton("Auto Slam / Crits", 28, Config.AutoSlam, function(v)
    play(clickSound)
    Config.AutoSlam = v
end)
toggleButton("Auto Charge Durability", 28, Config.AutoCharge, function(v)
    play(clickSound)
    Config.AutoCharge = v
end)

-- ⚡ Auto Skill ------------------------------------------------------
section("⚡ AUTO SKILL")
toggleButton("AUTO SKILL", 32, Config.AutoSkill, function(v)
    play(skillSound)
    Config.AutoSkill = v
end)
local ModeBtn = actionButton("", 28, function() end)
ModeBtn.TextSize = 10
local function refreshMode()
    if Config.SkillMode == "Remote" then
        ModeBtn.Text = "Mode: Remote (UseSkill, only while reeling)  [click to change]"
    else
        ModeBtn.Text = "Mode: Keys Z/X/C/V (always)  [click to change]"
    end
end
refreshMode()
ModeBtn.MouseButton1Click:Connect(function()
    play(clickSound)
    Config.SkillMode = (Config.SkillMode == "Remote") and "Keys" or "Remote"
    refreshMode()
end)

-- 💰 Economy & Selling -----------------------------------------------
section("💰 ECONOMY & SELLING")
toggleButton("Auto Sell Fish", 32, Config.AutoSell, function(v)
    play(sellSound)
    Config.AutoSell = v
end)
makeSlider("Sell Interval", "s", SELL_MIN, SELL_MAX, 1, 5, 0, Config.SellInterval, function(v)
    Config.SellInterval = v
end)
actionButton("💰 Sell Now & Teleport to Nana", 30, function()
    play(sellSound)
    sellNow()
end)
toggleButton("Auto Favourite Fish (protect from selling)", 28, Config.AutoFavourite, function(v)
    play(clickSound)
    Config.AutoFavourite = v
end)
makeDropdown("Favourite Target", FISH_LIST, Config.FavouriteFishName, function(name)
    Config.FavouriteFishName = name
end)
toggleButton("Material Farming (protect craft fish)", 28, Config.MaterialFarming, function(v)
    play(clickSound)
    Config.MaterialFarming = v
end)

-- generic info card (label on the left, value on the right) -------------
local function infoCard(rows)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, #rows * 22 + 8), BackgroundColor3 = COL_ROW, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, Body)
    corner(card, 6)
    local setters = {}
    for i, r in ipairs(rows) do
        local y = 4 + (i - 1) * 22
        new("TextLabel", {
            Size = UDim2.new(0.45, -8, 0, 22), Position = UDim2.new(0, 8, 0, y), BackgroundTransparency = 1, Text = r[2],
            TextColor3 = Color3.fromRGB(150, 150, 150), Font = Enum.Font.Gotham, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, card)
        local v = new("TextLabel", {
            Size = UDim2.new(0.55, -8, 0, 22), Position = UDim2.new(0.45, 0, 0, y), BackgroundTransparency = 1, Text = "-",
            TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
        setters[r[1]] = function(text) v.Text = text end
    end
    return setters
end

-- 🛡️ Anti AFK ----------------------------------------------------------
section("🛡️ ANTI AFK")
toggleButton("Anti-AFK (prevents the 20 min idle kick)", 28, Config.AntiAFK, function(v)
    play(clickSound)
    Config.AntiAFK = v
    markDirty()
end)
ui.afk = infoCard({ { "afk", "Status" } }).afk

-- 📊 Money Stats --------------------------------------------------------
section("📊 MONEY STATS")
ui.stats = infoCard({
    { "cash", "Current Cash" }, { "net", "Net Cash (session)" }, { "cph", "Cash / hour" },
    { "fish", "Total Fish Caught" }, { "fsess", "Fish (session)" }, { "fph", "Fish / hour" },
    { "time", "Session Time" }, { "rod", "Equipped Rod" }, { "bait", "Equipped Bait" },
})
actionButton("🔄 Reset Session", 26, function()
    play(clickSound)
    resetSession()
end)

-- 🔔 Discord Webhook ------------------------------------------------------
section("🔔 DISCORD WEBHOOK")

local urlBox = new("TextBox", {
    Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(), BackgroundColor3 = COL_ROW, BorderSizePixel = 0, Text = "",
    PlaceholderText = "Paste your Discord webhook URL here", PlaceholderColor3 = Color3.fromRGB(120, 120, 120),
    TextColor3 = COL_GREEN, Font = Enum.Font.Gotham, TextSize = 10, ClearTextOnFocus = false,
    TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd,
}, Body)
corner(urlBox, 6)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, urlBox)
local function maskedUrl(url)
    if url == "" then return "" end
    return "https://discord.com/api/webhooks/…" .. string.sub(url, -4)
end
urlBox.Text = maskedUrl(Config.WebhookUrl)
urlBox.Focused:Connect(function() urlBox.Text = Config.WebhookUrl end)
urlBox.FocusLost:Connect(function()
    local txt = (string.gsub(urlBox.Text, "^%s+", ""))
    txt = (string.gsub(txt, "%s+$", ""))
    if txt == "" then
        Config.WebhookUrl = ""
        webhookStatus = "URL cleared"
        markDirty()
    elseif not string.find(txt, "…", 1, true) then
        Config.WebhookUrl = txt
        webhookStatus = validWebhook(txt) and "URL saved" or "Not a Discord webhook URL"
        markDirty()
    end
    urlBox.Text = maskedUrl(Config.WebhookUrl)
end)

toggleButton("Webhook Reports", 32, Config.WebhookEnabled, function(v)
    play(clickSound)
    Config.WebhookEnabled = v
    lastWebhookTime = tick()
    if v and not validWebhook(Config.WebhookUrl) then webhookStatus = "Set a valid webhook URL first" end
end)
makeSlider("Report Every", "min", WEBHOOK_MIN, WEBHOOK_MAX, 1, 5, 0, Config.WebhookInterval, function(v)
    Config.WebhookInterval = v
    lastWebhookTime = tick()  -- changing the interval restarts the countdown
    markDirty()
end)
actionButton("📨 Send Test Report Now", 28, function()
    play(sellSound)
    sendWebhook("test")
end)
ui.hook = infoCard({ { "next", "Next report in" }, { "status", "Last result" } })
uiReady = true

-- status (always visible at the bottom) ------------------------------
local StatusBox = new("Frame", {
    Size = UDim2.new(1, -20, 0, 66), Position = UDim2.new(0, 10, 1, -76), BackgroundColor3 = COL_ROW, BorderSizePixel = 0,
}, Main)
corner(StatusBox, 6)
local StatusLabel = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 34), Position = UDim2.new(0, 8, 0, 4), BackgroundTransparency = 1, Text = "Status: ...",
    TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 11, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, StatusBox)
local DetailLabel = new("TextLabel", {
    Size = UDim2.new(1, -16, 0, 26), Position = UDim2.new(0, 8, 0, 38), BackgroundTransparency = 1, Text = "",
    TextColor3 = Color3.fromRGB(150, 150, 150), Font = Enum.Font.Gotham, TextSize = 10, TextWrapped = true,
    TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
}, StatusBox)

-- dragging ----------------------------------------------------------
do
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    TitleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    TitleBar.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
        if dragging and input == dragInput then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

-- minimize / close / hide key ----------------------------------------
local minimized = false
MinBtn.MouseButton1Click:Connect(function()
    play(clickSound)
    minimized = not minimized
    if minimized then
        Body.Visible = false
        StatusBox.Visible = false
        TweenService:Create(Main, TweenInfo.new(0.2), { Size = MIN_SIZE }):Play()
        MinBtn.Text = "+"
    else
        TweenService:Create(Main, TweenInfo.new(0.2), { Size = FULL_SIZE }):Play()
        task.delay(0.2, function()
            if running and not minimized then
                Body.Visible = true
                StatusBox.Visible = true
            end
        end)
        MinBtn.Text = "—"
    end
end)

local cleanupIntro = nil

local function unload()
    if not running then return end
    running = false
    Config.AutoCast = false
    Config.AutoSkill = false
    Config.AutoSell = false
    Config.WebhookEnabled = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    if cleanupIntro then pcall(cleanupIntro) end
    pcall(function() sg:Destroy() end)
    if env.PPAutoFishUnload == unload then env.PPAutoFishUnload = nil end
end
env.PPAutoFishUnload = unload

CloseBtn.MouseButton1Click:Connect(function()
    play(deleteSound)
    unload()
end)

conns[#conns + 1] = UserInputService.InputBegan:Connect(function(input, processed)
    if processed then return end
    if input.KeyCode == Enum.KeyCode.RightControl then
        sg.Enabled = not sg.Enabled
    end
end)

---------------------------------------------------------------------
-- Intro animation: "4896 Polar Bear"
-- (set getgenv().PP_ShowIntro = false before running to disable it; click / tap skips it)
---------------------------------------------------------------------
local INTRO_TEXT = "4896 Polar Bear"
local SHOW_INTRO = (env.PP_ShowIntro ~= false)
local introGui, introBlur = nil, nil
local introConns = {}

cleanupIntro = function()
    for _, c in ipairs(introConns) do pcall(function() c:Disconnect() end) end
    introConns = {}
    if introGui then
        pcall(function() introGui:Destroy() end)
        introGui = nil
    end
    if introBlur then
        pcall(function() introBlur:Destroy() end)
        introBlur = nil
    end
end

local function playIntro()
    local cam = workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    local titleSize = math.clamp(math.floor(vp.X / 12), 30, 76)
    local titleH = titleSize + 14
    local ICE = Color3.fromRGB(0, 225, 255)
    local SNOW = Color3.fromRGB(235, 248, 255)
    local skip = false

    local gui = new("ScreenGui", {
        Name = "PPINGYYY_Intro", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1000,
        ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
    })
    attachGui(gui)
    introGui = gui

    local function sleep(t)
        local e = tick() + t
        while running and not skip and tick() < e do task.wait(0.03) end
    end

    -- dark icy background -------------------------------------------------
    local bg = new("Frame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1,
        BorderSizePixel = 0, ZIndex = 1,
    }, gui)
    new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(3, 8, 20), Color3.fromRGB(8, 40, 75)) }, bg)
    TweenService:Create(bg, TweenInfo.new(0.45), { BackgroundTransparency = 0.05 }):Play()

    -- everything else lives in one CanvasGroup so it can fade out in one tween
    local content = new("CanvasGroup", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 2 }, gui)

    local skipBtn = new("TextButton", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Text = "", ZIndex = 100, AutoButtonColor = false,
    }, gui)
    skipBtn.MouseButton1Click:Connect(function() skip = true end)
    new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.new(0, 300, 0, 16),
        BackgroundTransparency = 1, Text = "tap / click to skip", TextColor3 = SNOW, TextTransparency = 0.6,
        Font = Enum.Font.Gotham, TextSize = 11, ZIndex = 3,
    }, content)

    -- blur the game behind ---------------------------------------------------
    pcall(function()
        local blur = Instance.new("BlurEffect")
        blur.Size = 0
        blur.Parent = game:GetService("Lighting")
        introBlur = blur
        TweenService:Create(blur, TweenInfo.new(0.5), { Size = 22 }):Play()
    end)

    -- falling snow -------------------------------------------------------------
    local flakes = {}
    for i = 1, 45 do
        local s = math.random(3, 8)
        local f = new("Frame", {
            Size = UDim2.new(0, s, 0, s), BackgroundColor3 = SNOW, BackgroundTransparency = math.random(25, 70) / 100,
            BorderSizePixel = 0, ZIndex = 2,
        }, content)
        corner(f, s)
        flakes[i] = {
            f = f, x = math.random(), y = math.random(), speed = 0.05 + math.random() * 0.12,
            sway = math.random() * 6.28, amp = 0.01 + math.random() * 0.02,
        }
    end
    local snowStart = tick()
    introConns[#introConns + 1] = RunService.RenderStepped:Connect(function(dt)
        local t = tick() - snowStart
        for _, fl in ipairs(flakes) do
            fl.y = fl.y + fl.speed * dt
            if fl.y > 1.05 then
                fl.y = -0.05
                fl.x = math.random()
            end
            fl.f.Position = UDim2.new(fl.x + math.sin(t * 1.2 + fl.sway) * fl.amp, 0, fl.y, 0)
        end
    end)

    -- title: every letter rises out of a mask ---------------------------------
    local title = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, 0), Size = UDim2.new(1, 0, 0, titleH),
        BackgroundTransparency = 1, ClipsDescendants = true, ZIndex = 5,
    }, content)
    local titleScale = new("UIScale", { Scale = 0.92 }, title)
    local row = new("Frame", { Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1 }, title)
    new("UIListLayout", {
        FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
        VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2),
    }, row)

    local letters = {}
    local count = 0
    for i = 1, #INTRO_TEXT do
        local ch = string.sub(INTRO_TEXT, i, i)
        local w
        if ch == " " then
            w = math.floor(titleSize * 0.38)
        else
            local ok, sz = pcall(function()
                return game:GetService("TextService"):GetTextSize(ch, titleSize, Enum.Font.GothamBlack, Vector2.new(1000, 1000))
            end)
            w = ((ok and sz) and sz.X or math.floor(titleSize * 0.7)) + 2
        end
        local slot = new("Frame", { Size = UDim2.new(0, w, 1, 0), BackgroundTransparency = 1, LayoutOrder = i }, row)
        if ch ~= " " then
            local lbl = new("TextLabel", {
                Size = UDim2.new(1, 0, 1, 0), Position = UDim2.new(0, 0, 1.1, 0), BackgroundTransparency = 1, Text = ch,
                Font = Enum.Font.GothamBlack, TextSize = titleSize, TextColor3 = (i <= 4) and ICE or Color3.new(1, 1, 1),
                TextTransparency = 1,
            }, slot)
            local stroke = new("UIStroke", { Color = ICE, Thickness = 2, Transparency = 1 }, lbl)
            count = count + 1
            letters[count] = { lbl = lbl, stroke = stroke }
        end
    end
    for idx, l in ipairs(letters) do
        task.delay(0.35 + idx * 0.07, function()
            if not running then return end
            TweenService:Create(l.lbl, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
                Position = UDim2.new(0, 0, 0, 0), TextTransparency = 0,
            }):Play()
            TweenService:Create(l.stroke, TweenInfo.new(0.55), { Transparency = 0.45 }):Play()
        end)
    end
    TweenService:Create(titleScale, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()

    -- shine sweeping across the finished title ----------------------------------
    local shine = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, -titleSize, 0.5, 0),
        Size = UDim2.new(0, math.floor(titleSize * 0.9), 3, 0), Rotation = 18, BackgroundColor3 = Color3.new(1, 1, 1),
        BorderSizePixel = 0, ZIndex = 20,
    }, title)
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1),
        }),
    }, shine)
    task.delay(2.0, function()
        if not running then return end
        TweenService:Create(shine, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
            Position = UDim2.new(0, vp.X + titleSize, 0.5, 0),
        }):Play()
    end)

    -- accent line + subtitle ------------------------------------------------------
    local lineY = math.floor(titleH / 2) + 14
    local line = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.45, lineY), Size = UDim2.new(0, 0, 0, 2),
        BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 5,
    }, content)
    new("UIGradient", {
        Transparency = NumberSequence.new({
            NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0),
            NumberSequenceKeypoint.new(0.75, 0), NumberSequenceKeypoint.new(1, 1),
        }),
    }, line)
    task.delay(1.5, function()
        if not running then return end
        TweenService:Create(line, TweenInfo.new(0.8, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
            Size = UDim2.new(0, math.floor(vp.X * 0.42), 0, 2),
        }):Play()
    end)
    local sub = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.45, lineY + 12), Size = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1, Text = "❄  A U T O   F I S H  ❄", Font = Enum.Font.GothamBold, TextSize = 15,
        TextColor3 = ICE, TextTransparency = 1, ZIndex = 5,
    }, content)
    task.delay(1.9, function()
        if not running then return end
        TweenService:Create(sub, TweenInfo.new(0.6), { TextTransparency = 0.1 }):Play()
    end)

    -- loading bar ------------------------------------------------------------------
    local barW = math.clamp(math.floor(vp.X * 0.5), 200, 420)
    local barBg = new("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.82, 0), Size = UDim2.new(0, barW, 0, 5),
        BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 5,
    }, content)
    corner(barBg, 3)
    local barFill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = ICE, BorderSizePixel = 0, ZIndex = 6 }, barBg)
    corner(barFill, 3)
    new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(0, 140, 255), Color3.fromRGB(150, 255, 255)) }, barFill)
    local pct = new("TextLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0.82, -10), Size = UDim2.new(0, barW, 0, 16),
        BackgroundTransparency = 1, Text = "LOADING  0%", Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = SNOW, TextTransparency = 1, ZIndex = 5,
    }, content)
    TweenService:Create(barBg, TweenInfo.new(0.5), { BackgroundTransparency = 0.85 }):Play()
    TweenService:Create(pct, TweenInfo.new(0.5), { TextTransparency = 0.2 }):Play()

    local loadStart = tick() + 0.5
    local loadTime = 2.8
    while running and not skip do
        local p = math.clamp((tick() - loadStart) / loadTime, 0, 1)
        barFill.Size = UDim2.new(p, 0, 1, 0)
        pct.Text = string.format("LOADING  %d%%", math.floor(p * 100))
        if p >= 1 then break end
        task.wait(0.03)
    end
    if not running then return end

    -- outro: title zooms through the screen while everything fades --------------------
    barFill.Size = UDim2.new(1, 0, 1, 0)
    pct.Text = "READY  100%"
    sleep(0.3)
    TweenService:Create(titleScale, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.In), { Scale = 1.4 }):Play()
    TweenService:Create(content, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { GroupTransparency = 1 }):Play()
    TweenService:Create(bg, TweenInfo.new(0.7), { BackgroundTransparency = 1 }):Play()
    if introBlur then TweenService:Create(introBlur, TweenInfo.new(0.7), { Size = 0 }):Play() end
    local e = tick() + 0.75
    while running and tick() < e do task.wait(0.03) end
end

if SHOW_INTRO then
    Main.Visible = false
    task.spawn(function()
        local ok, err = pcall(playIntro)
        if not ok then warn("[PPINGYYY AutoFish] intro error: " .. tostring(err)) end
        cleanupIntro()
        if running then
            Main.Size = UDim2.new(0, 360, 0, 0)
            Main.Visible = true
            TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = FULL_SIZE }):Play()
        end
    end)
end

---------------------------------------------------------------------
-- Start the engine
---------------------------------------------------------------------
conns[#conns + 1] = RunService.Heartbeat:Connect(function()
    if not running then return end
    local ok, err = pcall(engineStep)
    if not ok then
        statusText = "Script error (see console F9)"
        if err ~= lastErr then
            lastErr = err
            warn("[PPINGYYY AutoFish] " .. tostring(err))
        end
    end
    pcall(utilityStep)
    local now = tick()
    if now - lastUiTime >= 0.2 then
        lastUiTime = now
        local text = "Status: " .. statusText
        if now - sellNoteTime < 4 and sellNote ~= "" then
            text = text .. "  |  " .. sellNote
        end
        StatusLabel.Text = text
        DetailLabel.Text = detailText
    end
end)

conns[#conns + 1] = RunService.RenderStepped:Connect(function()
    pcall(anchorRenderStep)
end)

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "★ PPINGYYY AUTO FISH ★",
        Text = "Loaded! RightControl = hide / show",
        Duration = 4,
    })
end)
print("★ [PPINGYYY] 4896 Polar Bear - Auto Fish v3 loaded (Auto Cast + Anchor Bar + Skill + Economy + Anti-AFK + Stats + Webhook)")
