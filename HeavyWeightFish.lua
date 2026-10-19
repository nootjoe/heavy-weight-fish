--[[
    ★ PPINGYYY AUTO FISH ★  v2
    Auto Cast + Cast Delay + Anchor Bar (minigame) + Auto Skill + Economy & Selling

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

local sg = new("ScreenGui", { Name = "PPINGYYY_AutoFish", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling })
do
    local parented = false
    local getters = {
        function() return gethui and gethui() end,
        function() return game:GetService("CoreGui") end,
    }
    for _, getter in ipairs(getters) do
        local ok, p = pcall(getter)
        if ok and p then
            local ok2 = pcall(function() sg.Parent = p end)
            if ok2 and sg.Parent == p then parented = true break end
        end
    end
    if not parented then sg.Parent = lp:WaitForChild("PlayerGui") end
end

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

local function unload()
    if not running then return end
    running = false
    Config.AutoCast = false
    Config.AutoSkill = false
    Config.AutoSell = false
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
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
print("★ [PPINGYYY] Auto Fish v2 loaded (Auto Cast + Delay + Anchor Bar + Auto Skill + Economy)")
