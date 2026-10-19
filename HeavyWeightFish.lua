--[[
    ★ PPINGYYY AUTO FISH ★
    Auto Cast + Cast Delay + Auto Skill (new UI, same style as the old hub)

    Game logic used (taken from the working fishing script):
      Character attributes : Type ("Fishing Rod"), Fishing, Minigame, CDForTheNextThrow, Swimming
      PlayerGui            : MainGui.Fishing (Visible while the reel minigame is open)
      ReplicatedStorage    : Events.Fishing        -> FireServer(root.CFrame)   (cast)
                             Events.ToggleHotbar   -> InvokeServer(slot)        (equip rod)
                             Events.UseSkill / Events.TriggerMinigameSkill -> FireServer("Z"/"X"/"C"/"V")
                             Data[UserId].Hotbar / Inventory / InventoryLimit
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
    AutoCast = false,
    CastDelay = 1.0,          -- seconds to wait after a catch / when idle before casting
    StopWhenFull = true,      -- stop casting when the inventory is full
    AutoSkill = false,
    SkillMode = "Remote",     -- "Remote" = UseSkill remotes during the minigame, "Keys" = press Z/X/C/V
}

local DELAY_MIN, DELAY_MAX, DELAY_STEP = 0.5, 5.0, 0.1
local SKILL_INTERVAL = 0.15   -- remote skill interval (same as the working script)
local KEY_INTERVAL = 0.5      -- key press interval (same as the old Auto Skills Engine)
local RECAST_TIMEOUT = 15     -- line in the water this long with no bite -> cast again
local EQUIP_INTERVAL = 1.5
local MIN_RECAST_GAP = 1.0    -- never send two casts closer than this
local SKILL_KEYS = { "Z", "X", "C", "V" }
local KEY_CODES = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C, Enum.KeyCode.V }

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

local function yn(v) return v and "yes" or "no" end

---------------------------------------------------------------------
-- Engine (one Heartbeat connection: auto cast + delay + auto skill)
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
    -- Auto Cast
    ----------------------------------------------------------------
    if isMinigame then
        idleSince = nil
        statusText = "Reeling (minigame)"
        return
    end

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
                tryEquipRod(Events, getData(), now)
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
    if Config.StopWhenFull and inventoryFull(getData()) then
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
local deleteSound = makeSound("154157386")
local function play(s) pcall(function() s:Play() end) end

local FULL_SIZE = UDim2.new(0, 340, 0, 366)
local MIN_SIZE = UDim2.new(0, 340, 0, 40)

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

local Body = new("Frame", { Size = UDim2.new(1, 0, 1, -40), Position = UDim2.new(0, 0, 0, 40), BackgroundTransparency = 1 }, Main)

local function section(text, y)
    return new("TextLabel", {
        Size = UDim2.new(0, 320, 0, 16), Position = UDim2.new(0, 10, 0, y), BackgroundTransparency = 1,
        Text = text, TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, Body)
end

local function toggleButton(label, y, h, initial, onChange)
    local state = initial
    local btn = new("TextButton", {
        Size = UDim2.new(0, 320, 0, h), Position = UDim2.new(0, 10, 0, y), Font = Enum.Font.GothamBold,
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

-- 🎣 Auto Cast ------------------------------------------------------
section("🎣 AUTO CAST", 6)
toggleButton("Auto Cast Rod", 26, 32, Config.AutoCast, function(v)
    play(castSound)
    Config.AutoCast = v
    equipAttempts = 0
    idleSince = nil
end)

local DelayBox = new("Frame", { Size = UDim2.new(0, 320, 0, 52), Position = UDim2.new(0, 10, 0, 64), BackgroundColor3 = COL_ROW, BorderSizePixel = 0 }, Body)
corner(DelayBox, 6)

local DelayLabel = new("TextLabel", {
    Size = UDim2.new(1, -20, 0, 18), Position = UDim2.new(0, 10, 0, 4), BackgroundTransparency = 1,
    Text = "", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 11,
    TextXAlignment = Enum.TextXAlignment.Left,
}, DelayBox)

local function stepButton(text, x)
    local b = new("TextButton", {
        Size = UDim2.new(0, 26, 0, 22), Position = UDim2.new(0, x, 0, 26), Text = text, Font = Enum.Font.GothamBold,
        TextSize = 14, BackgroundColor3 = Color3.fromRGB(40, 40, 45), TextColor3 = COL_GREEN, BorderSizePixel = 0,
    }, DelayBox)
    corner(b, 5)
    return b
end
local MinusBtn = stepButton("-", 10)
local PlusBtn = stepButton("+", 320 - 36)

local Hit = new("Frame", { Size = UDim2.new(0, 320 - 92, 0, 24), Position = UDim2.new(0, 46, 0, 25), BackgroundTransparency = 1 }, DelayBox)
local Track = new("Frame", {
    Size = UDim2.new(1, 0, 0, 6), Position = UDim2.new(0, 0, 0.5, -3), BackgroundColor3 = Color3.fromRGB(45, 45, 50), BorderSizePixel = 0,
}, Hit)
corner(Track, 3)
local Fill = new("Frame", { Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = COL_GREEN, BorderSizePixel = 0 }, Track)
corner(Fill, 3)
local Knob = new("Frame", {
    Size = UDim2.new(0, 14, 0, 14), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0, 0, 0.5, 0),
    BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 2,
}, Track)
corner(Knob, 7)

local function setDelay(v)
    v = math.floor(v / DELAY_STEP + 0.5) * DELAY_STEP
    v = math.clamp(v, DELAY_MIN, DELAY_MAX)
    v = math.floor(v * 10 + 0.5) / 10
    Config.CastDelay = v
    DelayLabel.Text = string.format("Cast Delay: %.1f s   (%.1f - %.1f)", v, DELAY_MIN, DELAY_MAX)
    local p = (v - DELAY_MIN) / (DELAY_MAX - DELAY_MIN)
    Fill.Size = UDim2.new(p, 0, 1, 0)
    Knob.Position = UDim2.new(p, 0, 0.5, 0)
end
setDelay(Config.CastDelay)

local sliding = false
local function updateFromX(x)
    local rel = math.clamp((x - Hit.AbsolutePosition.X) / math.max(Hit.AbsoluteSize.X, 1), 0, 1)
    setDelay(DELAY_MIN + (DELAY_MAX - DELAY_MIN) * rel)
end
local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
Hit.InputBegan:Connect(function(input)
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
MinusBtn.MouseButton1Click:Connect(function() play(clickSound); setDelay(Config.CastDelay - DELAY_STEP) end)
PlusBtn.MouseButton1Click:Connect(function() play(clickSound); setDelay(Config.CastDelay + DELAY_STEP) end)

toggleButton("Stop When Inventory Full", 124, 28, Config.StopWhenFull, function(v)
    play(clickSound)
    Config.StopWhenFull = v
end)

-- ⚡ Auto Skill ------------------------------------------------------
section("⚡ AUTO SKILL", 162)
toggleButton("AUTO SKILL", 182, 32, Config.AutoSkill, function(v)
    play(skillSound)
    Config.AutoSkill = v
end)

local ModeBtn = new("TextButton", {
    Size = UDim2.new(0, 320, 0, 28), Position = UDim2.new(0, 10, 0, 220), Font = Enum.Font.GothamBold, TextSize = 10,
    BackgroundColor3 = Color3.fromRGB(20, 30, 40), TextColor3 = COL_GREEN, BorderSizePixel = 0,
}, Body)
corner(ModeBtn, 6)
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

-- status ------------------------------------------------------------
local StatusBox = new("Frame", { Size = UDim2.new(0, 320, 0, 66), Position = UDim2.new(0, 10, 0, 256), BackgroundColor3 = COL_ROW, BorderSizePixel = 0 }, Body)
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
        TweenService:Create(Main, TweenInfo.new(0.2), { Size = MIN_SIZE }):Play()
        MinBtn.Text = "+"
    else
        TweenService:Create(Main, TweenInfo.new(0.2), { Size = FULL_SIZE }):Play()
        task.delay(0.2, function() if running and not minimized then Body.Visible = true end end)
        MinBtn.Text = "—"
    end
end)

local function unload()
    if not running then return end
    running = false
    Config.AutoCast = false
    Config.AutoSkill = false
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
        StatusLabel.Text = "Status: " .. statusText
        DetailLabel.Text = detailText
    end
end)

pcall(function()
    StarterGui:SetCore("SendNotification", {
        Title = "★ PPINGYYY AUTO FISH ★",
        Text = "Loaded! RightControl = hide / show",
        Duration = 4,
    })
end)
print("★ [PPINGYYY] Auto Fish loaded (Auto Cast + Cast Delay + Auto Skill)")