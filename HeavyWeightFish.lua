--[[
    ★ PPINGYYY AUTO FISH ★  v2
    Auto Cast + Cast Delay + Anchor Bar (minigame) + Auto Skill + Economy & Selling + Anti-AFK + Money Stats + Discord Webhook + Taoist/Maoshan ESP + "4896 Polar Bear" intro

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
    Skills     : cooldown-aware Auto Skill (Character.Skills[...].Value = cooldown, UsingSkill = casting)
    ESP        : Taoist / Maoshan merchants (cloned into Workspace by the server), tracer + found alert
    Performance: black screen (3D rendering off), low graphics, no particles, mute, FPS cap  (RightShift = black screen)
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
    BarSway = 20,             -- Anchor Bar: how far the bar swings left/right around the centre, in % of the track (0 = fixed)
    BarSwaySpeed = 4,         -- jumps per second
    AnchorBar = true,         -- keep the bar centred + send fish progression + boss bar / hp bar helpers
    AutoSlam = true,          -- answer / press the Slam (Perfect) prompt
    AutoCharge = true,        -- answer / press the Charge prompt
    -- skills
    AutoSkill = false,
    SkillRoles = { Z = "Attack", X = "Attack", C = "Attack", V = "Attack" },  -- per slot: "Attack" / "Heal" / "Off"
    HealEnabled = false,      -- use the Heal-role slots when your HP is low
    HealBelow = 50,           -- percent of max HP
    HoldOnInvincible = true,  -- do not spend attack skills while the boss is invincible (~3 s after it restores its HP)
    FpsCap = 30,              -- used by "Limit FPS"
    BossAlert = true,         -- notify when the server announces secret bosses
    SkillMode = "Remote",     -- "Remote" = UseSkill remotes during the minigame, "Keys" = press Z/X/C/V
    -- economy
    AutoSell = false,
    SellInterval = 30,        -- seconds between automatic sells
    AutoFavourite = false,    -- protect the chosen fish from being sold
    FavouriteFishName = "Colossal Tigerfish",
    MaterialFarming = false,  -- protect the craft-material fish from being sold
    -- utilities
    AntiAFK = true,
    IdleMotion = false,       -- every N minutes: a small camera sweep (+ a jump when nothing is being fished)
    IdleMotionMin = 30,
    LeaveGameAFK = false,     -- if the game puts you in its own AFK mode (after 60s w/o keyboard/click), switch it off again
    WebhookEnabled = false,
    WebhookUrl = "",
    WebhookInterval = 15,     -- minutes between webhook reports (normal mode)
    WebhookLive = true,       -- live mode: ONE message that is edited in place
    LiveInterval = 30,        -- seconds between live edits
    ESP_Taoist = false,
    ESP_Maoshan = false,
    ESP_Tracer = false,
    ESP_Notify = true,
}

local DELAY_MIN, DELAY_MAX, DELAY_STEP = 0.5, 5.0, 0.1
local SELL_MIN, SELL_MAX = 10, 300
local SKILL_INTERVAL = 0.12   -- how often the skill scheduler looks for a ready skill
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
local KEY_CODE_OF = { Z = Enum.KeyCode.Z, X = Enum.KeyCode.X, C = Enum.KeyCode.C, V = Enum.KeyCode.V }
local SKILL_RETRY = 0.7        -- never re-send the same skill key sooner than this (server needs time to start the cooldown)

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
local skillCursor = 0
local bossAlertText = "-"
local gameAfkText, gameAfkTime = "", -100
local bossNotify = function() end   -- replaced once the sounds exist
local skillFired = { Z = 0, X = 0, C = 0, V = 0 }
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

-- Skills --------------------------------------------------------------------------------------
-- Confirmed in the place file: Character.Skills holds 4 NumberValues; each has the attribute "Key" (Z/X/C/V),
--   .Value            = remaining cooldown in seconds (<= 0 means ready)
--   :GetAttribute("UsingSkill") > 0  = this slot is locked because a skill is being cast
-- Data[UserId].FishingRodInventory[<rod>].Skill[<key>].Value = name of the equipped skill ("" = empty slot)
local function skillSlots(char)
    local out = {}
    local folder = char and char:FindFirstChild("Skills")
    if not folder then return out end
    for _, c in ipairs(folder:GetChildren()) do
        if c:IsA("NumberValue") then
            local key = c:GetAttribute("Key")
            if type(key) == "string" then out[key] = c end
        end
    end
    return out
end

local function slotSkillName(pData, key)
    local ok, name = pcall(function()
        local rod = pData.FishingRod.Value
        local inv = pData.FishingRodInventory:FindFirstChild(rod)
        local sk = inv and inv:FindFirstChild("Skill")
        local s = sk and sk:FindFirstChild(key)
        return s and s.Value
    end)
    if ok and type(name) == "string" and name ~= "" then return name end
    return nil
end

-- Fight state, confirmed from the remote log of real boss fights:
--   Workspace.Fishes[FishID] is a NumberValue whose .Value counts the damage dealt so far (boss HP left = MaxHealth - Value)
--   attributes: Boss, FishName, MaxHealth, HasPhaseLeft, PhaseInvincible
--   child  <UserId>_PlayerHealth  = your HP (max = its MaxHP attribute, otherwise Data.BaseHP)
local function readCombat(pData)
    local id = lp:GetAttribute("FishID")
    local fishes = workspace:FindFirstChild("Fishes")
    if not id or not fishes then return nil end
    local f = fishes:FindFirstChild(tostring(id))
    if not f then return nil end
    local c = {
        boss = f:GetAttribute("Boss") == true, name = f:GetAttribute("FishName"), fmax = f:GetAttribute("MaxHealth"),
        invincible = f:GetAttribute("PhaseInvincible") == true, phaseLeft = f:GetAttribute("HasPhaseLeft") == true,
    }
    pcall(function() c.fdmg = f.Value end)
    local ph = f:FindFirstChild(tostring(lp.UserId) .. "_PlayerHealth")
    if ph then
        c.hp = ph.Value
        local mx = ph:GetAttribute("MaxHP")
        if not mx and pData then
            local b = pData:FindFirstChild("BaseHP")
            mx = b and b.Value
        end
        c.hpMax = mx
        if type(mx) == "number" and mx > 0 then c.hpFrac = c.hp / mx end
    end
    return c
end

-- returns the next key that can be used right now (round-robin over the Attack slots; Heal slots only when HP is low)
local KEY_INDEX = { Z = 1, X = 2, C = 3, V = 4 }
local function pickSkill(char, pData, now, ctx)
    if char:GetAttribute("SkillLocked") == true then return nil end
    local slots = skillSlots(char)
    for _, v in pairs(slots) do
        local using = v:GetAttribute("UsingSkill")
        if type(using) == "number" and using > 0 then return nil end   -- a skill is being cast
    end
    local function ready(key)
        local v = slots[key]
        return Config.SkillRoles[key] ~= "Off" and v ~= nil and v.Value <= 0 and (now - skillFired[key] >= SKILL_RETRY)
            and (not pData or slotSkillName(pData, key) ~= nil)
    end
    -- 1) heal when HP is low (never while the "can't heal" curse is active: the game sets the character attribute Poisoned)
    if Config.HealEnabled and ctx and ctx.hpFrac and ctx.hpFrac * 100 < Config.HealBelow
        and char:GetAttribute("Poisoned") ~= true and char:GetAttribute("NoHeal") ~= true then
        for _, key in ipairs(SKILL_KEYS) do
            if Config.SkillRoles[key] == "Heal" and ready(key) then return key, KEY_INDEX[key] end
        end
    end
    -- 2) attack
    if Config.HoldOnInvincible and ctx and ctx.invincible then return nil end
    local n = #SKILL_KEYS
    for i = 1, n do
        local idx = ((skillCursor + i - 1) % n) + 1
        local key = SKILL_KEYS[idx]
        if Config.SkillRoles[key] == "Attack" and ready(key) then return key, idx end
    end
    return nil
end

local function pressKey(code)
    if keyBusy or not VIM then return end
    keyBusy = true
    task.spawn(function()
        pcall(function()
            VIM:SendKeyEvent(true, code, false, game)
            task.wait(0.05)
            VIM:SendKeyEvent(false, code, false, game)
        end)
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
-- where the Anchor Bar sits right now: centre, plus a slow left/right swing (kept inside the game's 0.1-0.9 safe zone)
-- the bar JUMPS instantly to the other side every so often (like quick clicks), it does not glide
local barJump = { x = 0.5, nextAt = 0, side = 1 }
function ui.barX()
    local amp = math.clamp(Config.BarSway or 0, 0, 35) / 100
    if amp <= 0 then return 0.5 end
    local now = tick()
    if now >= barJump.nextAt then
        local rate = math.clamp(Config.BarSwaySpeed or 4, 0.5, 15)
        barJump.side = -barJump.side
        barJump.x = 0.5 + barJump.side * amp * (0.4 + 0.6 * math.random())
        barJump.nextAt = now + (1 / rate) * (0.7 + 0.6 * math.random())
    end
    return math.clamp(barJump.x, 0.15, 0.85)
end
local uiReady = false
local settingsDirtyAt = nil
local session = { startTime = tick(), startCash = nil, startFish = nil }
local afk = { pings = 0, last = tick() }
local webhookBusy = false
local live = { id = "", busy = false, last = 0, backoff = 0 }   -- live webhook message state
local lastWebhookTime = tick()   -- when the last report was sent / when the timer was (re)started
local webhookStatus = "Idle"
local lastStatsTime = 0

-- settings that survive a re-execute (webhook url + interval + anti-afk) -------------
local function saveSettings()
    if not writefile then return end
    pcall(function()
        writefile(SETTINGS_FILE, HttpService:JSONEncode({
            WebhookUrl = Config.WebhookUrl, WebhookInterval = Config.WebhookInterval, AntiAFK = Config.AntiAFK,
            WebhookLive = Config.WebhookLive, LiveInterval = Config.LiveInterval,
            LiveMsgId = live.id, LiveMsgUrl = Config.WebhookUrl,
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
                if type(data.WebhookLive) == "boolean" then Config.WebhookLive = data.WebhookLive end
                if type(data.LiveInterval) == "number" then Config.LiveInterval = math.clamp(math.floor(data.LiveInterval), 10, 300) end
                -- keep editing the same Discord message after a re-execute (only if it is still the same webhook)
                if type(data.LiveMsgId) == "string" and data.LiveMsgUrl == Config.WebhookUrl then live.id = data.LiveMsgId end
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
-- "Idle motion": a visible bit of activity every N minutes (camera sweep, and a jump when it is safe).
-- It only changes what a person looking at your character sees; it does not make the script safer to use.
afk.lastMotion = tick()
afk.motionBusy = false
afk.motion = function()
    if afk.motionBusy then return end
    afk.motionBusy = true
    task.spawn(function()
        pcall(function()
            local char = lp.Character
            local cam = workspace.CurrentCamera
            if cam then
                local steps, total = 36, math.rad(24)
                for i = 1, steps do
                    if not running then break end
                    local dir = (i <= steps / 2) and 1 or -1    -- sweep right, then back
                    cam.CFrame = cam.CFrame * CFrame.Angles(0, dir * total / (steps / 2), 0)
                    RunService.RenderStepped:Wait()
                end
            end
            -- jump only when no line is in the water and no fight is running (moving could cancel the cast)
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum and running and char:GetAttribute("Fishing") ~= true and char:GetAttribute("Minigame") ~= true
                and hum:GetState() ~= Enum.HumanoidStateType.Seated then
                hum.Jump = true
            end
        end)
        afk.motionBusy = false
    end)
end

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
    -- Data[UserId].Level.{Level, Experience, MaxExperience}; the weather is the Workspace attribute "Weather"
    local lvl, exp, maxExp = nil, nil, nil
    local lf = pData:FindFirstChild("Level")
    if lf then
        local a, b, c = lf:FindFirstChild("Level"), lf:FindFirstChild("Experience"), lf:FindFirstChild("MaxExperience")
        lvl = a and tonumber(a.Value)
        exp = b and tonumber(b.Value)
        maxExp = c and tonumber(c.Value)
    end
    local weather = workspace:GetAttribute("Weather")
    return {
        cash = num("Cash"), fish = num("FishCaught"), rod = str("FishingRod"), bait = str("EquippedBait"),
        level = lvl, exp = exp, maxExp = maxExp, weather = (weather ~= nil) and tostring(weather) or "?",
    }
end

local function resetSession()
    session.startTime = tick()
    session.startCash = nil
    session.startFish = nil
end

local function levelText(st)
    if not st.level then return "?" end
    local txt = "Lv " .. commas(st.level)
    if st.exp and st.maxExp and st.maxExp > 0 then
        txt = txt .. "  (" .. math.floor(st.exp / st.maxExp * 100) .. "%)"
    end
    return txt
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
    local desc
    if reason == "live" then
        desc = "🔴 **LIVE**  •  updated <t:" .. os.time() .. ":R>  •  every " .. Config.LiveInterval .. "s"
    elseif reason == "test" then
        desc = "Test report"
    else
        desc = "Scheduled report (every " .. Config.WebhookInterval .. " min)"
    end
    local fields = {
        { name = "👤 Player", value = lp.DisplayName .. " (@" .. lp.Name .. ")", inline = true },
        { name = "⭐ Level", value = levelText(st), inline = true },
        { name = "🌦️ Weather", value = st.weather or "?", inline = true },
        { name = "💰 Cash", value = "$" .. commas(st.cash or 0), inline = true },
        { name = "📈 Net Cash (session)", value = signedMoney(netCash), inline = true },
        { name = "⏱️ Cash / hour", value = signedMoney(perHour(netCash, elapsed)), inline = true },
        { name = "🐟 Fish Caught", value = commas(st.fish or 0), inline = true },
        { name = "🎣 Fish (session)", value = "+" .. commas(fishGain) .. "  (" .. commas(perHour(fishGain, elapsed)) .. "/h)", inline = true },
        { name = "🪝 Rod", value = st.rod, inline = true },
        { name = "🪱 Bait", value = st.bait, inline = true },
        { name = "🕒 Session Time", value = fmtTime(elapsed), inline = true },
    }
    -- current fight (only while one is running)
    local fight = readCombat(getData())
    if fight then
        local bossHp = "?"
        if fight.fmax and fight.fdmg and fight.fmax > 0 then
            bossHp = math.floor(math.max(0, fight.fmax - fight.fdmg) / fight.fmax * 100 + 0.5) .. "%"
        end
        local myHp = fight.hpFrac and (math.floor(fight.hpFrac * 100 + 0.5) .. "%") or "?"
        fields[#fields + 1] = {
            name = fight.boss and "👹 Boss Fight" or "🎣 Fighting",
            value = tostring(fight.name or "?") .. "\nBoss HP " .. bossHp .. "  •  My HP " .. myHp, inline = false,
        }
    end
    return {
        username = "4896 Polar Bear",
        embeds = { {
            title = (reason == "live") and "📡 Live Money Stats" or "📊 Money Stats Report",
            description = desc,
            color = (reason == "live") and 65430 or 57855,
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

-- Live webhook: the first call POSTs a message (?wait=true returns it, so we learn its id), every later call
-- PATCHes that same message, so the channel always shows ONE card that keeps updating.
local function liveUpdate()
    if live.busy then return end
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
    live.busy = true
    live.last = tick()
    local payload = buildPayload(st, "live")
    task.spawn(function()
        local function call(method, u, body)
            local ok, resp = pcall(function()
                return req({
                    Url = u, Method = method, Headers = { ["Content-Type"] = "application/json" },
                    Body = HttpService:JSONEncode(body),
                })
            end)
            if ok and type(resp) == "table" then return resp end
            return nil, tostring(resp)
        end
        local function codeOf(resp) return resp.StatusCode or resp.status_code end
        local function bodyOf(resp)
            local ok, data = pcall(function() return HttpService:JSONDecode(resp.Body or resp.body or "{}") end)
            return ok and type(data) == "table" and data or {}
        end

        local base = (string.gsub(url, "%?.*$", ""))
        local resp, err
        if live.id ~= "" then
            resp, err = call("PATCH", base .. "/messages/" .. live.id, { embeds = payload.embeds })
            if resp then
                local code = codeOf(resp)
                if type(code) == "number" and code >= 200 and code < 300 then
                    webhookStatus = "Live updated " .. os.date("%H:%M:%S")
                elseif code == 404 then
                    live.id = ""          -- the message was deleted: post a new one on the next tick
                    live.last = 0
                    webhookStatus = "Live message deleted - creating a new one"
                elseif code == 429 then
                    local wait = tonumber(bodyOf(resp).retry_after) or 5
                    live.backoff = tick() + wait + 1
                    webhookStatus = "Rate limited, retry in " .. math.ceil(wait) .. "s"
                else
                    webhookStatus = "Live edit failed: HTTP " .. tostring(code)
                end
            else
                webhookStatus = "Live edit failed: " .. tostring(err)
            end
        else
            local joiner = string.find(url, "?", 1, true) and "&" or "?"
            resp, err = call("POST", url .. joiner .. "wait=true", payload)
            if resp then
                local code = codeOf(resp)
                if type(code) == "number" and code >= 200 and code < 300 then
                    local id = bodyOf(resp).id
                    if id then
                        live.id = tostring(id)
                        markDirty()
                        webhookStatus = "Live message created " .. os.date("%H:%M:%S")
                    else
                        webhookStatus = "Sent, but no message id came back (editing impossible)"
                    end
                elseif code == 429 then
                    local wait = tonumber(bodyOf(resp).retry_after) or 5
                    live.backoff = tick() + wait + 1
                    webhookStatus = "Rate limited, retry in " .. math.ceil(wait) .. "s"
                else
                    webhookStatus = "Live post failed: HTTP " .. tostring(code)
                end
            else
                webhookStatus = "Live post failed: " .. tostring(err)
            end
        end
        live.busy = false
    end)
end

---------------------------------------------------------------------
-- ESP: Taoist / Grand Angler / Maoshan NPCs (Workspace.NPC)
---------------------------------------------------------------------
-- Game logic (confirmed from the place file): Taoist and Maoshan are Merchant NPCs. Their templates sit in
-- ReplicatedStorage.Merchant.{Taoist, Maoshan} (Model + Humanoid) and the SERVER clones them into the world,
-- so they are NOT fixed children of Workspace.NPC. "Blind Grand Angler" is a fixed NPC in Workspace.NPC.Function.
-- We therefore watch the whole Workspace for Models that have a Humanoid and a matching name.
local Workspace = game:GetService("Workspace")
local ESP_SCAN_INTERVAL = 1.0      -- re-scan Workspace.NPC (NPCs can stream in / spawn later)
local ESP_LABEL_INTERVAL = 0.15    -- distance label refresh
local ESP_KINDS = {
    Taoist  = { color = Color3.fromRGB(255, 160, 40), icon = "📜", cfg = "ESP_Taoist" },
    Maoshan = { color = Color3.fromRGB(170, 120, 255), icon = "✨", cfg = "ESP_Maoshan" },
}
local espFolder = Instance.new("Folder")
espFolder.Name = "PPAutoFishESP"
espFolder.Parent = Workspace
local espTracked = {}   -- [npcInstance] = { gui, label, hl, part, kind, name }
local espLastScan, espLastLabel = 0, 0
local espFound = { Taoist = 0, Maoshan = 0 }
local espAnnounced = { Taoist = false, Maoshan = false }
local espTracerHolder = nil      -- full-screen Frame created together with the GUI
local espNotify = function() end -- replaced once the sounds exist

local function espKindOf(name)
    local n = string.lower(name)
    if string.find(n, "taoist", 1, true) or string.find(n, "grand angler", 1, true) then return "Taoist" end
    if string.find(n, "maoshan", 1, true) then return "Maoshan" end
    return nil
end

local function espAnchorPart(inst)
    if inst:IsA("BasePart") then return inst end
    if inst:IsA("Model") then
        if inst.PrimaryPart then return inst.PrimaryPart end
        local hrp = inst:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp end
    end
    return inst:FindFirstChildWhichIsA("BasePart", true)
end

local function espRemove(inst)
    local d = espTracked[inst]
    if not d then return end
    espTracked[inst] = nil
    pcall(function() d.gui:Destroy() end)
    pcall(function() if d.hl then d.hl:Destroy() end end)
    pcall(function() if d.line then d.line:Destroy() end end)
end

local function espAdd(inst, kind)
    if espTracked[inst] then return end
    local part = espAnchorPart(inst)
    if not part then return end
    local info = ESP_KINDS[kind]

    local bb = Instance.new("BillboardGui")
    bb.Name = "ESP_" .. inst.Name
    bb.Size = UDim2.new(0, 170, 0, 24)
    bb.StudsOffset = Vector3.new(0, 3, 0)
    bb.AlwaysOnTop = true
    bb.Adornee = part
    bb.Enabled = false
    bb.Parent = espFolder
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, 0, 1, 0)
    f.BackgroundColor3 = Color3.fromRGB(15, 15, 17)
    f.BackgroundTransparency = 0.2
    f.BorderSizePixel = 0
    f.Parent = bb
    local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 4); c.Parent = f
    local s = Instance.new("UIStroke"); s.Color = info.color; s.Thickness = 1; s.Parent = f
    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Font = Enum.Font.GothamBold
    lbl.TextSize = 11
    lbl.TextColor3 = info.color
    lbl.Text = info.icon .. " " .. inst.Name
    lbl.Parent = f

    local hl = nil
    if inst:IsA("Model") then
        local okHl = pcall(function()
            hl = Instance.new("Highlight")
            hl.Adornee = inst
            hl.FillColor = info.color
            hl.OutlineColor = info.color
            hl.FillTransparency = 0.6
            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
            hl.Enabled = false
            hl.Parent = espFolder
        end)
        if not okHl then hl = nil end
    end
    espTracked[inst] = { gui = bb, label = lbl, hl = hl, part = part, kind = kind, name = inst.Name }
end

local espCandidates = {}   -- [model] = kind (Models with Humanoid + matching name, anywhere in Workspace)

local function espConsider(inst)
    if not inst or not inst.Parent or espCandidates[inst] then return end
    if not inst:IsA("Model") then return end
    local kind = espKindOf(inst.Name)
    if not kind then return end
    if not inst:FindFirstChildOfClass("Humanoid") then return end
    if Players:GetPlayerFromCharacter(inst) then return end
    espCandidates[inst] = kind
end

-- new objects: the server streams / clones them in, children arrive after the model, so check again shortly after
conns[#conns + 1] = Workspace.DescendantAdded:Connect(function(d)
    if not running then return end
    if d:IsA("Model") then
        task.delay(0.6, function() if running then espConsider(d) end end)
    elseif d:IsA("Humanoid") then
        local m = d.Parent
        if m then task.delay(0.2, function() if running then espConsider(m) end end) end
    end
end)

-- one-time initial scan of what already exists (chunked so it never freezes the game)
task.spawn(function()
    local n = 0
    for _, d in ipairs(Workspace:GetDescendants()) do
        if not running then return end
        if d:IsA("Model") then espConsider(d) end
        n = n + 1
        if n % 1500 == 0 then task.wait() end
    end
end)

local function espStep(now)
    -- 1) periodic bookkeeping
    if now - espLastScan >= ESP_SCAN_INTERVAL then
        espLastScan = now
        local anyOn = Config.ESP_Taoist or Config.ESP_Maoshan
        espFound.Taoist, espFound.Maoshan = 0, 0
        for inst, kind in pairs(espCandidates) do
            if not inst.Parent or not inst:IsDescendantOf(Workspace) then
                espCandidates[inst] = nil
                espRemove(inst)
            else
                espFound[kind] = espFound[kind] + 1
                if anyOn then espAdd(inst, kind) end
            end
        end
        for inst, d in pairs(espTracked) do
            if not inst.Parent or not d.part.Parent then espRemove(inst) end
        end
        -- announce once when a merchant appears (and again after it left and came back)
        for kind, count in pairs(espFound) do
            if count > 0 and not espAnnounced[kind] then
                espAnnounced[kind] = true
                if Config.ESP_Notify then pcall(espNotify, kind) end
            elseif count == 0 then
                espAnnounced[kind] = false
            end
        end
    end

    -- tracer lines (every frame, a handful of Frames at most)
    local camT = Workspace.CurrentCamera
    for inst, d in pairs(espTracked) do
        local want = Config.ESP_Tracer and Config[ESP_KINDS[d.kind].cfg] and espTracerHolder and camT
        if want then
            if not d.line then
                d.line = Instance.new("Frame")
                d.line.AnchorPoint = Vector2.new(0.5, 0.5)
                d.line.BorderSizePixel = 0
                d.line.BackgroundColor3 = ESP_KINDS[d.kind].color
                d.line.BackgroundTransparency = 0.25
                d.line.Visible = false
                d.line.Parent = espTracerHolder
            end
            local pos = camT:WorldToViewportPoint(d.part.Position)
            if pos.Z > 0 then
                local vp = camT.ViewportSize
                local origin = Vector2.new(vp.X / 2, vp.Y)
                local target = Vector2.new(pos.X, pos.Y)
                local diff = target - origin
                d.line.Size = UDim2.fromOffset(diff.Magnitude, 2)
                d.line.Position = UDim2.fromOffset((origin.X + target.X) / 2, (origin.Y + target.Y) / 2)
                d.line.Rotation = math.deg(math.atan2(diff.Y, diff.X))
                d.line.Visible = true
            else
                d.line.Visible = false
            end
        elseif d.line then
            d.line.Visible = false
        end
    end

    -- 2) visibility + distance label
    if now - espLastLabel >= ESP_LABEL_INTERVAL then
        espLastLabel = now
        local cam = Workspace.CurrentCamera
        local camPos = cam and cam.CFrame.Position
        for inst, d in pairs(espTracked) do
            local on = Config[ESP_KINDS[d.kind].cfg] and true or false
            d.gui.Enabled = on
            if d.hl then d.hl.Enabled = on end
            if on and camPos then
                local dist = math.floor((camPos - d.part.Position).Magnitude)
                d.label.Text = ESP_KINDS[d.kind].icon .. " " .. d.name .. " [" .. dist .. "m]"
            end
        end
    end
end

-- runs every frame next to the cast engine (separate pcall, so one can't break the other)
local lastBossUi = 0
-- the server announces secret bosses through the chat remote, e.g. "Secret bosses have spawned at <island> | Boss Power: 82"
task.spawn(function()
    local ev = RS:WaitForChild("Events", 20)
    local r = ev and ev:WaitForChild("NotifyRobloxChat", 20)
    if not r or not running then return end
    conns[#conns + 1] = r.OnClientEvent:Connect(function(msg)
        if type(msg) ~= "string" then return end
        local low = string.lower(msg)
        if string.find(low, "secret boss", 1, true) then
            bossAlertText = string.sub(msg, 1, 70)
            if Config.BossAlert and running then pcall(bossNotify, msg) end
        elseif string.find(low, "taoist", 1, true) or string.find(low, "maoshan", 1, true) then
            -- the server announces the merchants too (e.g. "Taoist has left!")
            bossAlertText = string.sub(msg, 1, 70)
            if Config.ESP_Notify and running and not string.find(low, "left", 1, true) then
                pcall(bossNotify, msg, "Merchant announcement")
            end
        end
    end)
end)

-- Performance saver ------------------------------------------------------------------------
-- Everything here is reversible: the original values are remembered and restored when a switch is turned off
-- (or when the script is closed).
local perf = { black = false, lowgfx = false, nofx = false, mute = false, fps = false, tick = nil }
do
    local Lighting = game:GetService("Lighting")
    local saved = setmetatable({}, { __mode = "k" })   -- [instance] = { property = original value }
    local g = {}                                        -- single saved values (quality level, volume, fps cap)
    local fxConn, fxToken = nil, 0
    local overlay, hudLabel = nil, nil
    local lastReapply, lastHud = 0, 0

    local function setProp(inst, prop, value)
        pcall(function()
            local s = saved[inst]
            if not s then s = {}; saved[inst] = s end
            if s[prop] == nil then s[prop] = inst[prop] end
            inst[prop] = value
        end)
    end
    local function restoreProps(filter)
        for inst, props in pairs(saved) do
            if filter(inst) then
                for prop, v in pairs(props) do pcall(function() inst[prop] = v end) end
                saved[inst] = nil
            end
        end
    end

    -- low graphics -----------------------------------------------------------------------
    local function lowGfx(on)
        if on then
            pcall(function()
                local r = settings().Rendering
                if g.quality == nil then g.quality = r.QualityLevel end
                r.QualityLevel = Enum.QualityLevel.Level01
            end)
            setProp(Lighting, "GlobalShadows", false)
            for _, e in ipairs(Lighting:GetChildren()) do
                if e:IsA("PostEffect") then
                    setProp(e, "Enabled", false)
                elseif e:IsA("Atmosphere") then
                    setProp(e, "Density", 0)
                    setProp(e, "Haze", 0)
                end
            end
            local terrain = Workspace:FindFirstChildOfClass("Terrain")
            if terrain then
                setProp(terrain, "Decoration", false)
                setProp(terrain, "WaterWaveSize", 0)
                setProp(terrain, "WaterWaveSpeed", 0)
                setProp(terrain, "WaterReflectance", 0)
            end
        else
            restoreProps(function(i)
                return i == Lighting or i:IsA("PostEffect") or i:IsA("Atmosphere") or i:IsA("Terrain")
            end)
            if g.quality ~= nil then
                pcall(function() settings().Rendering.QualityLevel = g.quality end)
                g.quality = nil
            end
        end
    end

    -- particles / beams / trails / lights -------------------------------------------------
    local FX = {
        ParticleEmitter = true, Beam = true, Trail = true, Smoke = true, Fire = true, Sparkles = true,
        PointLight = true, SpotLight = true, SurfaceLight = true,
    }
    local function killFx(d)
        if FX[d.ClassName] and not d:IsDescendantOf(espFolder) then setProp(d, "Enabled", false) end
    end
    local function noFx(on)
        fxToken = fxToken + 1
        if fxConn then fxConn:Disconnect(); fxConn = nil end
        if on then
            local token = fxToken
            fxConn = Workspace.DescendantAdded:Connect(killFx)
            task.spawn(function()   -- chunked so the game never freezes
                local n = 0
                for _, d in ipairs(Workspace:GetDescendants()) do
                    if token ~= fxToken or not running then return end
                    killFx(d)
                    n = n + 1
                    if n % 2000 == 0 then task.wait() end
                end
            end)
        else
            restoreProps(function(i) return FX[i.ClassName] == true end)
        end
    end

    -- audio ---------------------------------------------------------------------------------
    local function mute(on)
        return pcall(function()
            local gs = UserSettings():GetService("UserGameSettings")
            if on then
                if g.volume == nil then g.volume = gs.MasterVolume end
                gs.MasterVolume = 0
            elseif g.volume ~= nil then
                gs.MasterVolume = g.volume
                g.volume = nil
            end
        end)
    end

    -- fps cap (executor function) ---------------------------------------------------------
    local function fpsCap(on, n)
        if not setfpscap then return false end
        if g.fps == nil then
            local cur = nil
            if getfpscap then pcall(function() cur = getfpscap() end) end
            g.fps = (type(cur) == "number" and cur > 0) and cur or 60
        end
        return pcall(function() setfpscap(on and n or g.fps) end)
    end

    -- black screen ---------------------------------------------------------------------------
    local function attach(gui)
        for _, getter in ipairs({ function() return gethui and gethui() end, function() return game:GetService("CoreGui") end }) do
            local ok, parent = pcall(getter)
            if ok and parent then
                local ok2 = pcall(function() gui.Parent = parent end)
                if ok2 and gui.Parent == parent then return end
            end
        end
        gui.Parent = lp:WaitForChild("PlayerGui")
    end
    local function black(on)
        if on then
            if not overlay then
                overlay = Instance.new("ScreenGui")
                overlay.Name = "PPINGYYY_BlackScreen"
                overlay.ResetOnSpawn = false
                overlay.IgnoreGuiInset = true
                overlay.DisplayOrder = 5      -- above the game UI, below this script's window (DisplayOrder 10)
                overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                attach(overlay)
                local f = Instance.new("Frame")
                f.Size = UDim2.new(1, 0, 1, 0)
                f.BackgroundColor3 = Color3.new(0, 0, 0)
                f.BorderSizePixel = 0
                f.Active = true               -- swallows clicks so nothing in the game is hit by accident
                f.Parent = overlay
                hudLabel = Instance.new("TextLabel")
                hudLabel.AnchorPoint = Vector2.new(0.5, 1)
                hudLabel.Position = UDim2.new(0.5, 0, 1, -40)
                hudLabel.Size = UDim2.new(0, 520, 0, 150)
                hudLabel.BackgroundTransparency = 1
                hudLabel.TextColor3 = Color3.fromRGB(0, 200, 120)
                hudLabel.Font = Enum.Font.GothamBold
                hudLabel.TextSize = 16
                hudLabel.TextWrapped = true
                hudLabel.Text = "BLACK SCREEN MODE"
                hudLabel.Parent = f
            end
            overlay.Enabled = true
            pcall(function() RunService:Set3dRenderingEnabled(false) end)
        else
            if overlay then overlay.Enabled = false end
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
        end
    end

    -- public API ---------------------------------------------------------------------------
    function perf.setBlack(on) perf.black = on and true or false; black(perf.black) end
    function perf.setLowGfx(on) perf.lowgfx = on and true or false; lowGfx(perf.lowgfx) end
    function perf.setNoFx(on) perf.nofx = on and true or false; noFx(perf.nofx) end
    function perf.setMute(on) perf.mute = on and true or false; return mute(perf.mute) end
    function perf.setFps(on) perf.fps = on and true or false; return fpsCap(perf.fps, Config.FpsCap) end
    function perf.restoreAll()
        pcall(black, false)
        pcall(lowGfx, false)
        pcall(noFx, false)
        pcall(mute, false)
        if perf.fps then pcall(fpsCap, false, 0) end
        perf.black, perf.lowgfx, perf.nofx, perf.mute, perf.fps = false, false, false, false, false
        pcall(function() if overlay then overlay:Destroy() end end)
        overlay = nil
    end
    function perf.summary()
        local on = {}
        if perf.black then on[#on + 1] = "black" end
        if perf.lowgfx then on[#on + 1] = "low-gfx" end
        if perf.nofx then on[#on + 1] = "no-fx" end
        if perf.mute then on[#on + 1] = "mute" end
        if perf.fps then on[#on + 1] = "fps " .. Config.FpsCap end
        return #on > 0 and table.concat(on, ", ") or "all off"
    end
    function perf.tick(now)
        -- the game may switch effects back on (weather, UI blur ...): re-apply now and then
        if perf.lowgfx and now - lastReapply >= 5 then
            lastReapply = now
            pcall(lowGfx, true)
        end
        if perf.black and hudLabel and now - lastHud >= 1 then
            lastHud = now
            local txt = "BLACK SCREEN MODE   (RightShift = exit)"
            local st = readStats()
            if st and st.cash then
                local elapsed, net, fishGain = sessionNumbers(st, now)
                txt = txt .. "\n\n$" .. commas(st.cash) .. "    net " .. signedMoney(net) .. "    " ..
                    signedMoney(perHour(net, elapsed)) .. "/h\nfish +" .. commas(fishGain) .. "    " .. fmtTime(elapsed)
            end
            hudLabel.Text = txt .. "\n" .. tostring(statusText)
        end
    end
end

-- the game's own AFK mode: Events.AFK sends a countdown text every second ("Rejoin in 900s ...")
task.spawn(function()
    local ev = RS:WaitForChild("Events", 20)
    local r = ev and ev:WaitForChild("AFK", 20)
    if not r or not running then return end
    conns[#conns + 1] = r.OnClientEvent:Connect(function(txt)
        if type(txt) == "string" then
            gameAfkText = txt
            gameAfkTime = tick()
        end
    end)
end)

local function updateBossUi(now)
    if not ui.boss or now - lastBossUi < 0.4 then return end
    lastBossUi = now
    local B = ui.boss
    local char = lp.Character
    local c = readCombat(getData())
    if not c then
        B.fight("no fight")
        B.bhp("-"); B.myhp("-"); B.phase("-")
    else
        B.fight((c.boss and "BOSS  " or "") .. tostring(c.name or "?"))
        if c.fmax and c.fdmg then
            local left = math.max(0, c.fmax - c.fdmg)
            B.bhp(commas(left) .. " / " .. commas(c.fmax) .. "  (" .. math.floor(left / c.fmax * 100 + 0.5) .. "%)")
        else
            B.bhp("?")
        end
        if c.hp and c.hpMax then
            B.myhp(commas(c.hp) .. " / " .. commas(c.hpMax) .. "  (" .. math.floor((c.hpFrac or 0) * 100 + 0.5) .. "%)")
        else
            B.myhp(c.hp and commas(c.hp) or "?")
        end
        B.phase(c.invincible and "INVINCIBLE" or (c.phaseLeft and "more phases left" or "-"))
    end
    local flags = {}
    if char then
        for _, a in ipairs({ "Weakened", "Poisoned", "NoHeal", "Burned", "Bleeding", "Confused" }) do
            if char:GetAttribute(a) == true then flags[#flags + 1] = a end
        end
    end
    B.debuff(#flags > 0 and table.concat(flags, ", ") or "none")
    B.alert(bossAlertText)
end

local lastSkillUi = 0
local function updateSkillUi(now)
    if not ui.skill or now - lastSkillUi < 0.4 then return end
    lastSkillUi = now
    local char = lp.Character
    local slots = char and skillSlots(char) or {}
    local pData = getData()
    for _, key in ipairs(SKILL_KEYS) do
        local name = pData and slotSkillName(pData, key)
        local v = slots[key]
        local txt
        if not name then
            txt = "empty slot"
        elseif not v then
            txt = name
        else
            local using = v:GetAttribute("UsingSkill")
            if type(using) == "number" and using > 0 then
                txt = name .. "  [casting]"
            elseif v.Value > 0 then
                txt = name .. "  [" .. math.ceil(v.Value) .. "s]"
            else
                txt = name .. "  [READY]"
            end
        end
        txt = txt .. "  (" .. string.lower(Config.SkillRoles[key]) .. ")"
        ui.skill[key](txt)
    end
end

local afkFixLast = 0
local function utilityStep()
    local now = tick()
    pcall(espStep, now)
    pcall(updateSkillUi, now)
    pcall(updateBossUi, now)
    pcall(perf.tick, now)

    -- the game has its own AFK mode (ClientModule.AFK): 60s without key/click input -> client fires Events.AFK
    -- and Data[UserId].AFK becomes true. VirtualUser does not produce UserInputService events, so Anti-AFK alone
    -- does not stop it. This optional toggle fires Events.AFK again to leave that mode.
    if Config.LeaveGameAFK and now - afkFixLast >= 5 then
        afkFixLast = now
        local pData = getData()
        local v = pData and pData:FindFirstChild("AFK")
        if v and v.Value == true and not lp:GetAttribute("ReadyToAFK") then
            local evs = RS:FindFirstChild("Events")
            local r = evs and evs:FindFirstChild("AFK")
            if r then pcall(function() r:FireServer() end) end
        end
    end

    -- idle motion
    if Config.IdleMotion and now - afk.lastMotion >= Config.IdleMotionMin * 60 then
        afk.lastMotion = now
        afk.motion()
    end

    -- anti-afk keep-alive
    if Config.AntiAFK and (now - afk.last >= AFK_KEEPALIVE) then afkPing() end

    -- debounced settings save
    if settingsDirtyAt and now - settingsDirtyAt >= 1.5 then
        settingsDirtyAt = nil
        saveSettings()
    end

    -- webhook timer
    if Config.WebhookEnabled then
        if Config.WebhookLive then
            if not live.busy and now >= live.backoff and now - live.last >= Config.LiveInterval then liveUpdate() end
        elseif not webhookBusy and (now - lastWebhookTime >= Config.WebhookInterval * 60) then
            sendWebhook("timer")
        end
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
        S.level(levelText(st))
        S.weather(st.weather or "?")
    end

    if ui.esp then
        ui.esp.taoist(espFound.Taoist > 0 and ("found x" .. espFound.Taoist) or "not spawned right now")
        ui.esp.maoshan(espFound.Maoshan > 0 and ("found x" .. espFound.Maoshan) or "not spawned right now")
    end
    if ui.perf then ui.perf(perf.summary()) end
    if ui.afk then
        local txt = Config.AntiAFK and ("ON - last ping " .. fmtAgo(now - afk.last) .. " (" .. afk.pings .. ")") or "OFF"
        if now - gameAfkTime < 3 then
            txt = txt .. "  |  GAME AFK MODE: " .. string.gsub(gameAfkText, " %(Press again to stop afk%)", "")
        end
        ui.afk(txt)
    end
    if ui.hook then
        if Config.WebhookEnabled then
            if Config.WebhookLive then
                local left = math.max(0, Config.LiveInterval - (now - live.last))
                ui.hook.next(live.busy and "updating..." or (math.ceil(left) .. "s  (live)"))
            else
                local left = Config.WebhookInterval * 60 - (now - lastWebhookTime)
                ui.hook.next(fmtTime(math.max(0, left)))
            end
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
    if Config.AutoSkill and isMinigame and (now - lastSkillTime >= SKILL_INTERVAL) then
        lastSkillTime = now
        local key, idx = pickSkill(char, pData, now, readCombat(pData))
        if key then
            skillFired[key] = now
            skillCursor = idx
            if Config.SkillMode == "Remote" then
                local useSkill = Events:FindFirstChild("UseSkill")
                if useSkill then pcall(function() useSkill:FireServer(key) end) end
            else
                pressKey(KEY_CODE_OF[key])
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
                        local x = ui.barX()
                        bar:TweenPosition(UDim2.new(x, 0, 0.5, 0), Enum.EasingDirection.InOut, Enum.EasingStyle.Linear, 0, true)
                        bar.Position = UDim2.new(x, 0, 0.5, 0)
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
    if bar then
        -- the game counts progress while Bar.Position.X.Scale is inside (0.1, 0.9) and fails it at <= 0 / >= 1,
        -- so a swing of at most +-35% around the centre (0.15 .. 0.85) always stays inside the safe zone
        bar.Position = UDim2.new(ui.barX(), 0, 0.5, 0)
    end

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
local COL_CARD = Color3.fromRGB(21, 24, 33)
local COL_ROW = Color3.fromRGB(30, 34, 46)
local COL_STROKE = Color3.fromRGB(44, 50, 66)
local COL_GREEN = Color3.fromRGB(0, 255, 150)
local COL_ON = Color3.fromRGB(0, 190, 105)
local COL_OFF = Color3.fromRGB(66, 70, 88)
local COL_RED = Color3.fromRGB(200, 60, 60)
local COL_TEXT2 = Color3.fromRGB(140, 148, 165)
local COL_TABON = Color3.fromRGB(0, 62, 42)

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

local sg = new("ScreenGui", {
    Name = "PPINGYYY_AutoFish", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true, DisplayOrder = 10,
})
attachGui(sg)
espTracerHolder = new("Frame", { Name = "Tracers", Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, Active = false }, sg)

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

bossNotify = function(msg, title)
    play(skillSound)
    pcall(function()
        StarterGui:SetCore("SendNotification", { Title = title or "Secret boss!", Text = msg, Duration = 10 })
    end)
end

espNotify = function(kind)
    play(skillSound)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = kind .. " found!", Text = "A " .. kind .. " merchant is in this server.", Duration = 8,
        })
    end)
end

local FULL_SIZE = UDim2.new(0, 390, 0, 590)
local MIN_SIZE = UDim2.new(0, 390, 0, 46)

local Main = new("Frame", {
    Size = FULL_SIZE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true,
}, sg)
corner(Main, 12)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(19, 22, 31), Color3.fromRGB(10, 11, 15)), Rotation = 90 }, Main)
new("UIStroke", { Color = COL_GREEN, Thickness = 1.5, Transparency = 0.2 }, Main)

local TitleBar = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, Main)
new("TextLabel", {
    Size = UDim2.new(1, -90, 0, 22), Position = UDim2.new(0, 14, 0, 6), BackgroundTransparency = 1,
    Text = "★ PPINGYYY AUTO FISH", TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 15,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)
new("TextLabel", {
    Size = UDim2.new(1, -90, 0, 14), Position = UDim2.new(0, 14, 0, 27), BackgroundTransparency = 1,
    Text = "4896 Polar Bear  •  Heavyweight Fishing", TextColor3 = COL_TEXT2, Font = Enum.Font.Gotham, TextSize = 10,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)

local CloseBtn = new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -38, 0, 10), Text = "✕", Font = Enum.Font.GothamBold,
    TextSize = 12, BackgroundColor3 = COL_RED, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true,
}, TitleBar)
corner(CloseBtn, 6)

local MinBtn = new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -70, 0, 10), Text = "—", Font = Enum.Font.GothamBold,
    TextSize = 12, BackgroundColor3 = Color3.fromRGB(40, 90, 190), TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = true,
}, TitleBar)
corner(MinBtn, 6)

-- content area: tab bar + one scrolling page per tab ---------------------------------------
local Content = new("Frame", {
    Size = UDim2.new(1, 0, 1, -160), Position = UDim2.new(0, 0, 0, 46), BackgroundTransparency = 1,
}, Main)
local TabBar = new("Frame", { Size = UDim2.new(1, -20, 0, 32), Position = UDim2.new(0, 10, 0, 2), BackgroundTransparency = 1 }, Content)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, TabBar)
local Pages = new("Frame", { Size = UDim2.new(1, 0, 1, -38), Position = UDim2.new(0, 0, 0, 38), BackgroundTransparency = 1 }, Content)

local pages, tabButtons = {}, {}
local Body = nil     -- the container the widget helpers below put their controls into (a card)
local Page = nil     -- the page that new cards are added to

local orderCounter = 0
local function nextOrder()
    orderCounter = orderCounter + 1
    return orderCounter
end

local function selectTab(name)
    for n, pg in pairs(pages) do pg.Visible = (n == name) end
    for n, tb in pairs(tabButtons) do
        local on = (n == name)
        TweenService:Create(tb.btn, TweenInfo.new(0.15), {
            BackgroundColor3 = on and COL_TABON or COL_ROW, TextColor3 = on and COL_GREEN or COL_TEXT2,
        }):Play()
        tb.line.Visible = on
    end
end

local function addTab(name, label, order)
    local btn = new("TextButton", {
        Size = UDim2.new(0.2, -3.2, 1, 0), LayoutOrder = order, Text = label, Font = Enum.Font.GothamBold, TextSize = 10,
        BackgroundColor3 = COL_ROW, TextColor3 = COL_TEXT2, BorderSizePixel = 0, AutoButtonColor = false,
    }, TabBar)
    corner(btn, 7)
    local line = new("Frame", {
        Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -4), BackgroundColor3 = COL_GREEN,
        BorderSizePixel = 0, Visible = false,
    }, btn)
    corner(line, 1)
    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = COL_GREEN, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
    }, Pages)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 10) }, page)
    new("UIPadding", {
        PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 10),
    }, page)
    pages[name] = page
    tabButtons[name] = { btn = btn, line = line }
    btn.MouseButton1Click:Connect(function()
        play(clickSound)
        selectTab(name)
    end)
end

addTab("Fish", "🎣 Fish", 1)
addTab("Skill", "⚡ Skill", 2)
addTab("Sell", "💰 Sell", 3)
addTab("Stats", "📊 Stats", 4)
addTab("Misc", "⚙ Misc", 5)

local function setPage(name)
    Page = pages[name]
    Body = Page
end

-- a titled card; every widget created afterwards goes into it
local function section(text)
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = COL_CARD,
        BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, Page)
    corner(card, 10)
    new("UIStroke", { Color = COL_STROKE, Thickness = 1 }, card)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, card)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 10), PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
    }, card)
    local head = new("Frame", { Size = UDim2.new(1, 0, 0, 20), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, card)
    local bar = new("Frame", {
        Size = UDim2.new(0, 3, 0, 14), Position = UDim2.new(0, 0, 0.5, -7), BackgroundColor3 = COL_GREEN, BorderSizePixel = 0,
    }, head)
    corner(bar, 2)
    new("TextLabel", {
        Size = UDim2.new(1, -10, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = text,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left,
    }, head)
    Body = card
    return card
end

-- switch row: label on the left, pill switch on the right
local function toggleButton(label, h, initial, onChange)
    local state = initial and true or false
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, math.max(h, 30)), LayoutOrder = nextOrder(), BackgroundColor3 = COL_ROW,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false,
    }, Body)
    corner(row, 7)
    new("TextLabel", {
        Size = UDim2.new(1, -62, 1, 0), Position = UDim2.new(0, 10, 0, 0), BackgroundTransparency = 1, Text = label,
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 11, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local pill = new("Frame", {
        Size = UDim2.new(0, 38, 0, 20), Position = UDim2.new(1, -48, 0.5, -10), BackgroundColor3 = COL_OFF, BorderSizePixel = 0,
    }, row)
    corner(pill, 10)
    local knob = new("Frame", {
        Size = UDim2.new(0, 16, 0, 16), Position = UDim2.new(0, 2, 0.5, -8), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    }, pill)
    corner(knob, 8)
    local function refresh(animate)
        local pos = state and UDim2.new(1, -18, 0.5, -8) or UDim2.new(0, 2, 0.5, -8)
        local col = state and COL_ON or COL_OFF
        if animate then
            TweenService:Create(knob, TweenInfo.new(0.12), { Position = pos }):Play()
            TweenService:Create(pill, TweenInfo.new(0.12), { BackgroundColor3 = col }):Play()
        else
            knob.Position = pos
            pill.BackgroundColor3 = col
        end
    end
    refresh(false)
    row.MouseButton1Click:Connect(function()
        state = not state
        refresh(true)
        onChange(state)
    end)
    return row, function(v)
        state = v and true or false
        refresh(true)
    end
end

local function actionButton(text, h, onClick)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, math.max(h, 28)), LayoutOrder = nextOrder(), Font = Enum.Font.GothamBold, TextSize = 11,
        Text = text, BackgroundColor3 = Color3.fromRGB(24, 40, 48), TextColor3 = COL_GREEN, BorderSizePixel = 0,
    }, Body)
    corner(btn, 7)
    new("UIStroke", { Color = Color3.fromRGB(0, 110, 75), Thickness = 1 }, btn)
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

-- generic info card (label on the left, value on the right) -------------
local function infoCard(rows, labelFrac)
    labelFrac = labelFrac or 0.45
    local card = new("Frame", {
        Size = UDim2.new(1, 0, 0, #rows * 22 + 8), BackgroundColor3 = COL_ROW, BorderSizePixel = 0, LayoutOrder = nextOrder(),
    }, Body)
    corner(card, 6)
    local setters = {}
    for i, r in ipairs(rows) do
        local y = 4 + (i - 1) * 22
        new("TextLabel", {
            Size = UDim2.new(labelFrac, -8, 0, 22), Position = UDim2.new(0, 8, 0, y), BackgroundTransparency = 1, Text = r[2],
            TextColor3 = Color3.fromRGB(150, 150, 150), Font = Enum.Font.Gotham, TextSize = 11,
            TextXAlignment = Enum.TextXAlignment.Left,
        }, card)
        local v = new("TextLabel", {
            Size = UDim2.new(1 - labelFrac, -8, 0, 22), Position = UDim2.new(labelFrac, 0, 0, y), BackgroundTransparency = 1, Text = "-",
            TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Right,
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
        setters[r[1]] = function(text) v.Text = text end
    end
    return setters
end

-- tab: Fish ----------------------------------------------------------
setPage("Fish")
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
makeSlider("Bar Jump Range (left/right)", "%", 0, 35, 1, 5, 0, Config.BarSway, function(v)
    Config.BarSway = v
end)
makeSlider("Bar Jump Speed", "/s", 1, 12, 1, 1, 0, Config.BarSwaySpeed, function(v)
    Config.BarSwaySpeed = v
end)
toggleButton("Auto Slam / Crits", 28, Config.AutoSlam, function(v)
    play(clickSound)
    Config.AutoSlam = v
end)
toggleButton("Auto Charge Durability", 28, Config.AutoCharge, function(v)
    play(clickSound)
    Config.AutoCharge = v
end)

-- tab: Skill ---------------------------------------------------------
setPage("Skill")
do
-- ⚡ Auto Skill ------------------------------------------------------
section("⚡ AUTO SKILL")
toggleButton("AUTO SKILL (uses every ready skill)", 32, Config.AutoSkill, function(v)
    play(skillSound)
    Config.AutoSkill = v
end)
local ModeBtn = actionButton("", 28, function() end)
ModeBtn.TextSize = 10
local function refreshMode()
    if Config.SkillMode == "Remote" then
        ModeBtn.Text = "Mode: Remote (UseSkill)  [click to change]"
    else
        ModeBtn.Text = "Mode: Keys Z/X/C/V  [click to change]"
    end
end
refreshMode()
ModeBtn.MouseButton1Click:Connect(function()
    play(clickSound)
    Config.SkillMode = (Config.SkillMode == "Remote") and "Keys" or "Remote"
    refreshMode()
end)

-- role of every slot: Attack -> Heal -> Off
local ROLE_NEXT = { Attack = "Heal", Heal = "Off", Off = "Attack" }
local ROLE_COLOR = { Attack = Color3.fromRGB(190, 70, 60), Heal = Color3.fromRGB(0, 150, 110), Off = COL_OFF }
local keyRow = new("Frame", { Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1, LayoutOrder = nextOrder() }, Body)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, keyRow)
for i, key in ipairs(SKILL_KEYS) do
    local kb = new("TextButton", {
        Size = UDim2.new(0.25, -4.5, 1, 0), LayoutOrder = i, Font = Enum.Font.GothamBold, TextSize = 10,
        BorderSizePixel = 0, TextColor3 = Color3.new(1, 1, 1), AutoButtonColor = false,
    }, keyRow)
    corner(kb, 7)
    local function refreshKey()
        local role = Config.SkillRoles[key]
        kb.Text = key .. "\n" .. string.upper(role)
        kb.BackgroundColor3 = ROLE_COLOR[role]
    end
    refreshKey()
    kb.MouseButton1Click:Connect(function()
        play(clickSound)
        Config.SkillRoles[key] = ROLE_NEXT[Config.SkillRoles[key]]
        refreshKey()
    end)
end

-- live slot status
do
    local e = infoCard({ { "Z", "Key Z" }, { "X", "Key X" }, { "C", "Key C" }, { "V", "Key V" } }, 0.2)
    ui.skill = e
end

-- boss / combat -------------------------------------------------------
section("⚔ BOSS & COMBAT")
toggleButton("Use Heal slots when HP is low", 30, Config.HealEnabled, function(v)
    play(clickSound)
    Config.HealEnabled = v
end)
makeSlider("Heal below", "%", 10, 90, 5, 5, 0, Config.HealBelow, function(v)
    Config.HealBelow = v
end)
toggleButton("Hold attacks while boss is invincible (~3s)", 30, Config.HoldOnInvincible, function(v)
    play(clickSound)
    Config.HoldOnInvincible = v
end)
toggleButton("Alert when secret bosses spawn", 30, Config.BossAlert, function(v)
    play(clickSound)
    Config.BossAlert = v
end)
do
    ui.boss = infoCard({
        { "fight", "Fight" }, { "bhp", "Boss HP" }, { "myhp", "My HP" }, { "phase", "Phase" },
        { "debuff", "Debuffs" }, { "alert", "Last alert" },
    }, 0.3)
end

end

-- tab: Sell ----------------------------------------------------------
setPage("Sell")
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

-- tab: Stats ---------------------------------------------------------
setPage("Stats")
do
-- 📊 Money Stats --------------------------------------------------------
section("📊 MONEY STATS")
ui.stats = infoCard({
    { "level", "Level" }, { "weather", "Weather" },
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
        if txt ~= Config.WebhookUrl then live.id = "" end   -- another webhook = another live message
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
    live.last = 0
    if v and not validWebhook(Config.WebhookUrl) then webhookStatus = "Set a valid webhook URL first" end
end)
toggleButton("Live mode (edits ONE message, no spam)", 30, Config.WebhookLive, function(v)
    play(clickSound)
    Config.WebhookLive = v
    live.last = 0
    markDirty()
end)
makeSlider("Live update every", "s", 10, 120, 5, 5, 0, Config.LiveInterval, function(v)
    Config.LiveInterval = v
    markDirty()
end)
makeSlider("Report Every (normal mode)", "min", WEBHOOK_MIN, WEBHOOK_MAX, 1, 5, 0, Config.WebhookInterval, function(v)
    Config.WebhookInterval = v
    lastWebhookTime = tick()  -- changing the interval restarts the countdown
    markDirty()
end)
actionButton("📨 Send Test Report Now", 28, function()
    play(sellSound)
    if Config.WebhookLive then
        live.last = 0
        live.backoff = 0
        liveUpdate()
    else
        sendWebhook("test")
    end
end)
actionButton("🆕 Start a fresh live message", 26, function()
    play(clickSound)
    live.id = ""
    live.last = 0
    markDirty()
    webhookStatus = "Next update creates a new message"
end)
ui.hook = infoCard({ { "next", "Next update" }, { "status", "Last result" } }, 0.28)
uiReady = true

end

-- tab: Misc ----------------------------------------------------------
setPage("Misc")
-- 🛡️ Anti AFK ----------------------------------------------------------
section("🛡️ ANTI AFK")
toggleButton("Anti-AFK (prevents the 20 min idle kick)", 28, Config.AntiAFK, function(v)
    play(clickSound)
    Config.AntiAFK = v
    markDirty()
end)
toggleButton("Leave game AFK mode automatically (else it rejoins you after 15 min)", 34, Config.LeaveGameAFK, function(v)
    play(clickSound)
    Config.LeaveGameAFK = v
end)
toggleButton("Idle motion (camera sweep + jump)", 30, Config.IdleMotion, function(v)
    play(clickSound)
    Config.IdleMotion = v
    afk.lastMotion = tick()
end)
makeSlider("Idle motion every", "min", 5, 60, 5, 5, 0, Config.IdleMotionMin, function(v)
    Config.IdleMotionMin = v
    afk.lastMotion = tick()
end)
actionButton("▶ Do it once now", 26, function()
    play(clickSound)
    afk.motion()
end)
ui.afk = infoCard({ { "afk", "Status" } }, 0.17).afk

-- 🔮 ESP ------------------------------------------------------------
section("🔮 ESP")
toggleButton("Taoist ESP (Taoist / Grand Angler)", 28, Config.ESP_Taoist, function(v)
    play(clickSound)
    Config.ESP_Taoist = v
    espLastScan = 0
end)
toggleButton("Maoshan ESP", 28, Config.ESP_Maoshan, function(v)
    play(clickSound)
    Config.ESP_Maoshan = v
    espLastScan = 0
end)
toggleButton("Tracer line to the NPC", 28, Config.ESP_Tracer, function(v)
    play(clickSound)
    Config.ESP_Tracer = v
end)
toggleButton("Alert when one appears", 28, Config.ESP_Notify, function(v)
    play(clickSound)
    Config.ESP_Notify = v
end)
do
    local e = infoCard({ { "taoist", "Taoist" }, { "maoshan", "Maoshan" } })
    ui.esp = { taoist = e.taoist, maoshan = e.maoshan }
end

selectTab("Fish")

-- 🚀 Performance --------------------------------------------------------
section("🚀 PERFORMANCE SAVER")
do
    local _, setBlackVisual = toggleButton("Black screen (turns 3D rendering off)  [RightShift]", 34, false, function(v)
        play(clickSound)
        perf.setBlack(v)
    end)
    ui.setBlack = setBlackVisual
end
toggleButton("Low graphics (shadows, effects, water)", 30, false, function(v)
    play(clickSound)
    perf.setLowGfx(v)
end)
toggleButton("Disable particles / beams / lights", 30, false, function(v)
    play(clickSound)
    perf.setNoFx(v)
end)
toggleButton("Mute game audio", 30, false, function(v)
    play(clickSound)
    perf.setMute(v)
end)
toggleButton("Limit FPS" .. (setfpscap and "" or "  (not supported by this executor)"), 30, false, function(v)
    play(clickSound)
    perf.setFps(v)
end)
makeSlider("FPS cap", "fps", 5, 60, 5, 5, 0, Config.FpsCap, function(v)
    Config.FpsCap = v
    if perf.fps then perf.setFps(true) end
end)
do
    local e = infoCard({ { "state", "Active" } }, 0.2)
    ui.perf = e.state
end

-- status (always visible at the bottom) ------------------------------
local StatusBox = new("Frame", {
    Size = UDim2.new(1, -20, 0, 66), Position = UDim2.new(0, 10, 1, -106), BackgroundColor3 = COL_CARD, BorderSizePixel = 0,
}, Main)
corner(StatusBox, 10)
new("UIStroke", { Color = COL_STROKE, Thickness = 1 }, StatusBox)
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
-- a "move" handle along the bottom of the expanded window (the title bar drags too)
local MoveBtn = new("TextButton", {
    Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -32), Text = "✥  Hold & drag here to move window",
    Font = Enum.Font.GothamBold, TextSize = 11, BackgroundColor3 = COL_CARD, TextColor3 = COL_TEXT2,
    AutoButtonColor = false,
}, Main)
corner(MoveBtn, 8)
new("UIStroke", { Color = COL_STROKE, Thickness = 1 }, MoveBtn)
do
    local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
    for _, handle in ipairs({ TitleBar, MoveBtn }) do
    handle.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPos = Main.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then dragging = false end
            end)
        end
    end)
    handle.InputChanged:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
            dragInput = input
        end
    end)
    end
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
        Content.Visible = false
        StatusBox.Visible = false
        MoveBtn.Visible = false
        TweenService:Create(Main, TweenInfo.new(0.2), { Size = MIN_SIZE }):Play()
        MinBtn.Text = "+"
    else
        TweenService:Create(Main, TweenInfo.new(0.2), { Size = FULL_SIZE }):Play()
        task.delay(0.2, function()
            if running and not minimized then
                Content.Visible = true
                StatusBox.Visible = true
                MoveBtn.Visible = true
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
    Config.ESP_Taoist, Config.ESP_Maoshan = false, false
    pcall(function() espFolder:Destroy() end)
    pcall(perf.restoreAll)
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
    elseif input.KeyCode == Enum.KeyCode.RightShift then
        perf.setBlack(not perf.black)
        if ui.setBlack then ui.setBlack(perf.black) end
    end
end)

---------------------------------------------------------------------
-- Intro animation: "4896 Polar Bear"
-- (set getgenv().PP_ShowIntro = false before running to disable it; click / tap skips it)
---------------------------------------------------------------------
do  -- (scoped: keeps the number of top-level locals low)
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
            Main.Size = UDim2.new(0, 390, 0, 0)
            Main.Visible = true
            TweenService:Create(Main, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = FULL_SIZE }):Play()
        end
    end)
end

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
    if perf.black then pcall(anchorRenderStep) end
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
print("★ [PPINGYYY] 4896 Polar Bear - Auto Fish v7 loaded (Auto Cast + Anchor Bar + Skill + Boss logic + Economy + Anti-AFK + Stats + Webhook + ESP + Performance)")
