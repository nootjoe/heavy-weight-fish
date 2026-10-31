--[[
    ★ PPINGYYY AUTO FISH ★  v8 (collapsible UI + Quest tab)
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
    Human break: random pauses of Auto Cast, a few steps around the fishing spot, back + face the sea, cast again
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
    AutoTicketQuest = false,  -- Quest tab: accept / turn in the Ticket Quest and fish at the farm spot meanwhile
    TicketDifficulty = "Hard",
    QuestFarm = true,
    QuestTravel = "Boat",     -- "Boat" (default) or "Teleport"
    AutoRhythm = true,        -- play the boss rhythm minigame (A / S / D notes) automatically
    RhythmMiss = 1,           -- deliberate mistakes per rhythm game (0 = perfect)
    QuestDelay = 1.2,         -- seconds between the clicks inside NPC dialogues (quest / boat), a little random on top
    AutoBuyBait = false,      -- when the equipped bait runs out: walk to the bait seller, buy more, come back
    BuyBaitName = "Auto",     -- "Auto" = the bait that ran out (or the cheapest one for sale) or an exact bait name
    BuyBaitAmount = 400,      -- stock to buy up to (hard maximum 400)
    BuyBaitBelow = 0,         -- buy when the equipped bait count is at or below this
    BaitTravel = "Walk",      -- "Walk" (walks, teleports when too far / stuck) or "Teleport"
    QuestBait = "Auto",       -- bait to equip for "use bait" quests: "Off", "Auto" (cheapest you own) or a bait name
    QuestFarmPos = { 1362, 9, 268 },   -- Battlefield fishing spot (cast position seen in the log: 1362.21, 9.28, 267.87)
    QuestFarmLook = nil,               -- { x, z } facing of the farm spot (set by "Save my current position")
    QuestFarmPosEasy = nil,            -- second spot (easy / quick island) for "use N bait / skill" quests; nil = not set
    QuestFarmLookEasy = nil,
    QuestFarmPosIdle = nil,            -- third spot: where to fish while the quest is on cooldown or the daily limit is reached
    QuestFarmLookIdle = nil,
    IdleSpotOn = true,                 -- use the idle spot (when it is set) during cooldown / daily limit
    SkillIdle = { "", "", "" },        -- skills for the idle spot
    SkillLoadout = false,              -- equip a set of up to 3 skills for each fishing spot (see the Skill loadout section)
    SkillEasy = { "", "", "" },        -- skills used at the EASY farm spot ("" = empty)
    SkillHard = { "", "", "" },        -- skills used at the HARD farm spot
    EasyMinAmount = 30,                -- a plain "do it N times" quest with N at or above this goes to the easy spot
    QuestSplitFarm = true,             -- use the easy spot for the big, simple "use ..." quests (when it is set)
    BoatName = "Auto", -- "Auto" = the fastest boat you own; or type an exact boat name
    BlackFps = 20,            -- FPS cap used automatically while the black screen is on
    BlackHideUi = true,       -- black screen also switches the game's own UI + Roblox core UI off (less to draw)
    BlackHud = false,         -- show the small money/status text on the black screen (false = completely black)
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
    IdleMotion = false,       -- "human break": stop casting now and then, walk a few steps, come back, face the sea
    BreakMin = 5,             -- minutes between breaks: earliest ...
    BreakMax = 15,            -- ... and latest (the real delay is random and sometimes falls outside this range)
    BreakWalk = 8,            -- studs: how far from the fishing spot a break may wander
    FaceSea = true,           -- before every cast: stand on the saved spot and look in the saved (sea) direction
    LeaveGameAFK = true,      -- if the game puts you in its own AFK mode (after 60s w/o keyboard/click), switch it off again
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

-- =====================================================================================================================
-- HELP WINDOW CONTENT  -  EDIT THIS.  The "?" button in the title bar opens a small separate window with these sections
-- (tap a title to open / close it). Add, remove or reorder entries freely; `text` can be long, use \n for new lines.
-- =====================================================================================================================
ui.helpSections = {
    { title = "Getting started",        text = "(write your explanation here)" },
    { title = "Auto fish",              text = "(write your explanation here)" },
    { title = "Auto skill / rhythm",    text = "(write your explanation here)" },
    { title = "Ticket quest",           text = "(write your explanation here)" },
    { title = "Farm spots (hard / easy / idle)", text = "(write your explanation here)" },
    { title = "Skill loadout",          text = "(write your explanation here)" },
    { title = "Auto buy bait",          text = "(write your explanation here)" },
    { title = "Boat travel / reset",    text = "(write your explanation here)" },
    { title = "Performance / black screen", text = "(write your explanation here)" },
    { title = "Problems / FAQ",         text = "(write your explanation here)" },
}
-- where the Anchor Bar sits right now: centre, plus a slow left/right swing (kept inside the game's 0.1-0.9 safe zone)
-- Mimics what the bar does when a real player clicks (measured from a remote log): the bar slides left on its own
-- (~0.8 per second), and each click pushes it right by ~0.1 over 2-3 frames, so it saw-tooths around the centre.
local barJump = { x = 0.5, last = 0, kick = 0, trigger = 0.45, lazy = false }
function ui.barX()
    local amp = math.clamp(Config.BarSway or 0, 0, 35) / 100
    if amp <= 0 then return 0.5 end
    local now = tick()
    local dt = math.clamp(now - barJump.last, 0, 0.1)
    if barJump.last == 0 then dt = 0 end
    barJump.last = now
    local b = barJump
    local drift = math.clamp(Config.BarSwaySpeed or 4, 0.5, 15) * 0.2          -- bar units per second (default 0.8)
    if b.kick > 0 then
        local step = math.min(b.kick, 2.1 * dt)                                 -- ~0.035 per frame at 60 fps
        b.x = b.x + step
        b.kick = b.kick - step
    else
        b.x = b.x - drift * dt
        if b.x <= b.trigger then                                                -- "click": push right by about 0.1
            b.kick = 0.08 + 0.04 * math.random()
            local low = 0.5 - amp * 0.25
            b.lazy = math.random() < 0.12                                       -- now and then wait longer, like a human
            b.trigger = low - 0.02 + 0.04 * math.random() - (b.lazy and amp * 0.8 * math.random() or 0)
        end
    end
    b.x = math.clamp(b.x, 0.15, 0.85)
    -- pull slowly back to the centre if it wandered off
    if b.x > 0.5 + amp * 0.9 then b.x = b.x - 0.01 end
    return b.x
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
            LiveMsgId = live.id, LiveMsgUrl = Config.WebhookUrl, RhythmMethod = Config.RhythmMethod, TalkMethod = Config.TalkMethod,
            AutoBuyBait = Config.AutoBuyBait, BuyBaitName = Config.BuyBaitName, BuyBaitAmount = Config.BuyBaitAmount,
            BuyBaitBelow = Config.BuyBaitBelow, BaitTravel = Config.BaitTravel,
            QuestFarmPos = Config.QuestFarmPos, QuestFarmLook = Config.QuestFarmLook, QuestFarmPosEasy = Config.QuestFarmPosEasy,
            QuestFarmLookEasy = Config.QuestFarmLookEasy, QuestSplitFarm = Config.QuestSplitFarm, EasyMinAmount = Config.EasyMinAmount,
            SkillLoadout = Config.SkillLoadout, SkillEasy = Config.SkillEasy, SkillHard = Config.SkillHard,
            SkillIdle = Config.SkillIdle, QuestFarmPosIdle = Config.QuestFarmPosIdle, QuestFarmLookIdle = Config.QuestFarmLookIdle, IdleSpotOn = Config.IdleSpotOn,
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
                if type(data.RhythmMethod) == "number" then Config.RhythmMethod = data.RhythmMethod end
                if type(data.TalkMethod) == "number" then Config.TalkMethod = data.TalkMethod end
                if type(data.AutoBuyBait) == "boolean" then Config.AutoBuyBait = data.AutoBuyBait end
                if type(data.BuyBaitName) == "string" then Config.BuyBaitName = data.BuyBaitName end
                if type(data.BuyBaitAmount) == "number" then Config.BuyBaitAmount = math.clamp(math.floor(data.BuyBaitAmount), 1, 400) end
                if type(data.BuyBaitBelow) == "number" then Config.BuyBaitBelow = math.clamp(math.floor(data.BuyBaitBelow), 0, 399) end
                if data.BaitTravel == "Walk" or data.BaitTravel == "Teleport" then Config.BaitTravel = data.BaitTravel end
                local function isPos(v) return type(v) == "table" and #v == 3 and type(v[1]) == "number" and type(v[2]) == "number" and type(v[3]) == "number" end
                local function isLook(v) return type(v) == "table" and type(v[1]) == "number" and type(v[2]) == "number" end
                if isPos(data.QuestFarmPos) then Config.QuestFarmPos = data.QuestFarmPos end
                if isLook(data.QuestFarmLook) then Config.QuestFarmLook = data.QuestFarmLook end
                if isPos(data.QuestFarmPosEasy) then Config.QuestFarmPosEasy = data.QuestFarmPosEasy end
                if isLook(data.QuestFarmLookEasy) then Config.QuestFarmLookEasy = data.QuestFarmLookEasy end
                if type(data.QuestSplitFarm) == "boolean" then Config.QuestSplitFarm = data.QuestSplitFarm end
                local function isNames(v) if type(v) ~= "table" then return false end for i = 1, 3 do if type(v[i]) ~= "string" then return false end end return true end
                if type(data.SkillLoadout) == "boolean" then Config.SkillLoadout = data.SkillLoadout end
                if isNames(data.SkillEasy) then Config.SkillEasy = { data.SkillEasy[1], data.SkillEasy[2], data.SkillEasy[3] } end
                if isNames(data.SkillIdle) then Config.SkillIdle = { data.SkillIdle[1], data.SkillIdle[2], data.SkillIdle[3] } end
                if isPos(data.QuestFarmPosIdle) then Config.QuestFarmPosIdle = data.QuestFarmPosIdle end
                if isLook(data.QuestFarmLookIdle) then Config.QuestFarmLookIdle = data.QuestFarmLookIdle end
                if type(data.IdleSpotOn) == "boolean" then Config.IdleSpotOn = data.IdleSpotOn end
                if isNames(data.SkillHard) then Config.SkillHard = { data.SkillHard[1], data.SkillHard[2], data.SkillHard[3] } end
                if type(data.EasyMinAmount) == "number" then Config.EasyMinAmount = math.clamp(math.floor(data.EasyMinAmount), 1, 500) end
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
-- (the old camera-sweep "idle motion" was replaced by the walking "human break", see hm below)
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

-- The game's own AFK timer (ClientModule.AFK) is only reset by REAL input events (key / click / touch, not mouse
-- movement) and fires Events.AFK after 60 s. VirtualUser does not produce such events, so the quest loop (which only
-- uses remotes) went "AFK" every minute - and the server can pull you out of the boat seat when that happens.
-- A harmless key (LeftAlt: not Space = jump/exit boat, not Ctrl = sprint, not R) every 20-30 s keeps the timer at 0.
do
    task.spawn(function()
        while running do
            task.wait(20 + math.random() * 10)
            if running and Config.LeaveGameAFK and VIM then
                pcall(function()
                    VIM:SendKeyEvent(true, Enum.KeyCode.LeftAlt, false, game)
                    task.wait(0.05)
                    VIM:SendKeyEvent(false, Enum.KeyCode.LeftAlt, false, game)
                end)
            end
        end
    end)
end

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
    -- only models whose NAME matches count: the game spawns thousands of skill-effect models per hour and
    -- scheduling a task for each one is wasted CPU/memory
    if d:IsA("Model") then
        if espKindOf(d.Name) then
            task.delay(0.6, function() if running then espConsider(d) end end)
        end
    elseif d:IsA("Humanoid") then
        local m = d.Parent
        if m and espKindOf(m.Name) then task.delay(0.2, function() if running then espConsider(m) end end) end
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
    local lastReapply, lastHud, lastUi = 0, 0, 0

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

    local function refreshFps()
        if not setfpscap then return false end
        local want = nil
        if perf.black then want = Config.BlackFps end
        if perf.fps then want = want and math.min(want, Config.FpsCap) or Config.FpsCap end
        return fpsCap(want ~= nil, want)
    end

    -- the game's own UI + Roblox core UI: not drawing them saves CPU/GPU (scripts keep running, Visible values are untouched)
    local function hideUi(on)
        if on then
            local pg = lp:FindFirstChild("PlayerGui")
            if pg and Config.BlackHideUi then
                for _, gui in ipairs(pg:GetChildren()) do
                    if gui:IsA("ScreenGui") and gui ~= overlay and gui.Name ~= "PPINGYYY_AutoFish" then
                        setProp(gui, "Enabled", false)
                    end
                end
                if not g.core then
                    g.core = true
                    pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, false) end)
                end
            end
        else
            restoreProps(function(i) return i:IsA("ScreenGui") end)
            if g.core then
                g.core = nil
                pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.All, true) end)
            end
        end
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
                overlay.DisplayOrder = 2147483647   -- on top of everything, so the screen is completely black
                overlay.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
                attach(overlay)
                local f = Instance.new("Frame")
                f.Size = UDim2.new(1, 0, 1, 0)
                f.BackgroundColor3 = Color3.new(0, 0, 0)
                f.BorderSizePixel = 0
                f.BackgroundTransparency = 0
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
                hudLabel.Text = ""
                hudLabel.Visible = false
                hudLabel.Parent = f
            end
            overlay.Enabled = true
            pcall(function() RunService:Set3dRenderingEnabled(false) end)
            hideUi(true)
        else
            if overlay then overlay.Enabled = false end
            pcall(function() RunService:Set3dRenderingEnabled(true) end)
            hideUi(false)
        end
    end

    -- public API ---------------------------------------------------------------------------
    function perf.setBlack(on) perf.black = on and true or false; black(perf.black); refreshFps() end
    function perf.setLowGfx(on) perf.lowgfx = on and true or false; lowGfx(perf.lowgfx) end
    function perf.setNoFx(on) perf.nofx = on and true or false; noFx(perf.nofx) end
    function perf.setMute(on) perf.mute = on and true or false; return mute(perf.mute) end
    function perf.setFps(on) perf.fps = on and true or false; return refreshFps() end
    function perf.refreshFps() return refreshFps() end
    function perf.restoreAll()
        perf.black, perf.lowgfx, perf.nofx, perf.mute, perf.fps = false, false, false, false, false
        pcall(black, false)
        pcall(lowGfx, false)
        pcall(noFx, false)
        pcall(mute, false)
        if g.fps ~= nil then pcall(fpsCap, false, 0) end
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
        if perf.black and Config.BlackHideUi and now - lastUi >= 5 then
            lastUi = now
            pcall(hideUi, true)      -- the game may re-enable its UI (new ScreenGuis, respawn ...)
        end
        if hudLabel and hudLabel.Visible ~= (perf.black and Config.BlackHud) then
            hudLabel.Visible = perf.black and Config.BlackHud
        end
        if perf.black and Config.BlackHud and hudLabel and now - lastHud >= 1 then
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
-- Human break + sea facing
---------------------------------------------------------------------
local hm = {
    spot = nil,          -- { pos = Vector3, look = unit flat Vector3 }: where every cast is thrown from
    pendingCast = nil,   -- { t = tick(), cf = CFrame }: cast sent, waiting for Fishing = true
    fails = 0,           -- casts in a row that did not start fishing
    needFace = false,    -- a cast failed: re-face the spot before the next one
    busy = false,        -- a walk / realign routine is running -> the engine must not cast
    text = "",
    nextAt = 0,          -- when the next break is due
    token = 0,           -- changes whenever a routine starts, so an old routine stops itself
}

do
    local CAST_VERIFY = 3.0     -- Fishing must turn true this many seconds after a cast (log: ~0.5 s)
    local ALIGN_DIST = 3.0      -- farther than this from the spot (studs) -> walk back before casting
    local ALIGN_ANGLE = 6       -- degrees of yaw tolerance
    local TELEPORT_BACK = 30    -- farther than this (e.g. after "Sell Now & Teleport") -> snap back, do not walk

    local function flat(v)
        local f = Vector3.new(v.X, 0, v.Z)
        if f.Magnitude < 1e-3 then return nil end
        return f.Unit
    end

    local function flatDist(a, b)
        return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
    end

    local function rotated(v, deg)
        return CFrame.Angles(0, math.rad(deg), 0):VectorToWorldSpace(v)
    end

    function hm.makeSpot(cf)
        local look = flat(cf.LookVector)
        if not look then return nil end
        return { pos = cf.Position, look = look }
    end

    function hm.resetSpot()
        hm.spot = nil
        hm.pendingCast = nil
        hm.fails = 0
        hm.needFace = false
    end

    function hm.setSpotHere()
        local char = lp.Character
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if root then
            hm.spot = hm.makeSpot(root.CFrame)
            hm.fails = 0
            hm.needFace = false
        end
        return hm.spot ~= nil
    end

    -- irregular schedule: mostly somewhere between Min and Max, now and then clearly sooner or later
    function hm.schedule(now)
        local lo = math.max(1, Config.BreakMin)
        local hi = math.max(lo, Config.BreakMax)
        local roll = math.random()
        local mins
        if roll < 0.15 then
            mins = lo * (0.5 + 0.5 * math.random())
        elseif roll > 0.88 then
            mins = hi * (1 + 0.5 * math.random())
        else
            mins = lo + (hi - lo) * math.random()
        end
        hm.nextAt = now + mins * 60
    end

    -- true + char/hum/root while it is still fine to keep walking
    local function stillOk(token)
        if not running or hm.token ~= token then return false end
        local char = lp.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local root = char and char:FindFirstChild("HumanoidRootPart")
        if not (hum and root) or hum.Health <= 0 then return false end
        if char:GetAttribute("Fishing") == true or char:GetAttribute("Minigame") == true then return false end
        if char:GetAttribute("Swimming") == true then return false end
        return true, char, hum, root
    end

    local function newParams(char)
        local p = RaycastParams.new()
        p.FilterType = Enum.RaycastFilterType.Exclude
        p.FilterDescendantsInstances = { char }
        p.IgnoreWater = false
        return p
    end

    local function groundAt(params, p)
        return workspace:Raycast(Vector3.new(p.X, p.Y + 2, p.Z), Vector3.new(0, -14, 0), params)
    end

    -- a target is fine when: nothing solid in the way, dry ground under it, about the same height as the spot
    local function targetOk(char, from, to, spot)
        local params = newParams(char)
        local wall = workspace:Raycast(from + Vector3.new(0, 1.5, 0), Vector3.new(to.X - from.X, 0, to.Z - from.Z), params)
        if wall and wall.Material ~= Enum.Material.Water then return false end
        local g1 = groundAt(params, to)
        if not g1 or g1.Material == Enum.Material.Water then return false end
        local g0 = groundAt(params, spot.pos)
        if g0 and math.abs(g1.Position.Y - g0.Position.Y) > 2 then return false end
        return true
    end

    -- random spot around the fishing spot, never in the casting direction (0 deg = toward the sea)
    local function pickTarget(char, from, spot)
        local maxWalk = math.max(4, Config.BreakWalk)
        for _ = 1, 8 do
            local ang = 100 + math.random() * 160
            local dist = 3 + math.random() * (maxWalk - 3)
            local to = spot.pos + rotated(spot.look, ang) * dist
            if targetOk(char, from, to, spot) then return to end
        end
        return nil
    end

    local function walkTo(token, target, timeout)
        local ok, char, hum, root = stillOk(token)
        if not ok then return false end
        local done = false
        local conn = hum.MoveToFinished:Connect(function() done = true end)
        hum:MoveTo(target)
        local t0 = tick()
        local lastPos, lastMove = root.Position, tick()
        local alive = true
        while not done do
            task.wait(0.1)
            ok, char, hum, root = stillOk(token)
            if not ok then
                alive = false
                break
            end
            if tick() - t0 > timeout then break end
            if flatDist(root.Position, target) < 1.2 then break end
            if (root.Position - lastPos).Magnitude > 0.4 then
                lastPos = root.Position
                lastMove = tick()
            elseif tick() - lastMove > 1.5 then
                break          -- stuck against something: give up this leg
            end
        end
        conn:Disconnect()
        local reached = false
        pcall(function()
            local c = lp.Character
            local h = c and c:FindFirstChildOfClass("Humanoid")
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if h and r then
                reached = flatDist(r.Position, target) < 3
                h:MoveTo(r.Position)   -- stop where we are
            end
        end)
        return alive, reached
    end

    -- long way / obstacles: follow a Roblox path (jumps over things like a player would), no teleport
    local function walkPath(token, target, timeout)
        local t0 = tick()
        local ok, char, hum, root = stillOk(token)
        if not ok then return false, false end
        local path = game:GetService("PathfindingService"):CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true })
        local okP = pcall(function() path:ComputeAsync(root.Position, target) end)
        if not okP or path.Status ~= Enum.PathStatus.Success then
            return walkTo(token, target, timeout)      -- no path: just try straight
        end
        local wps = path:GetWaypoints()
        for i = 2, #wps do
            if tick() - t0 > timeout then break end
            local wp = wps[i]
            local ok2, _, h2 = stillOk(token)
            if not ok2 then return false, false end
            if wp.Action == Enum.PathWaypointAction.Jump then h2.Jump = true end
            local alive = walkTo(token, wp.Position, 5)
            if not alive then return false, false end
            if math.random() < 0.04 then task.wait(0.2 + math.random() * 0.6) end   -- tiny hesitation
        end
        local ok3, _, _, r3 = stillOk(token)
        local reached = ok3 and flatDist(r3.Position, target) < 3
        return ok3, reached
    end

    -- a human never walks a ruler-straight line: bend the way through 1-2 random side points,
    -- sometimes stop for a moment on the way
    local function wanderTo(token, to, spot)
        local ok, char, hum, root = stillOk(token)
        if not ok then return false end
        local from = root.Position
        local d = flatDist(from, to)
        if d > 6 then
            local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Unit
            local side = Vector3.new(-dir.Z, 0, dir.X)
            local pts = math.random() < 0.4 and 2 or 1
            for k = 1, pts do
                local f = (k / (pts + 1)) * (0.8 + math.random() * 0.4)
                local mid = from + dir * (d * f) + side * ((math.random() < 0.5 and -1 or 1) * (1 + math.random() * 3))
                if targetOk(char, root.Position, mid, spot) then
                    local alive = walkTo(token, mid, 4)
                    if not alive then return false end
                    if math.random() < 0.25 then task.wait(0.3 + math.random() * 1.0) end
                end
            end
        end
        local alive = walkTo(token, to, 5)
        return alive
    end

    -- smooth turn to look in `look` (flat unit vector)
    local function faceSpot(token, look)
        local ok, char, hum, root = stillOk(token)
        if not ok then return end
        local startRot = root.CFrame.Rotation
        local goalRot = CFrame.lookAt(Vector3.zero, look).Rotation
        local duration = 0.25 + math.random() * 0.2
        local t0 = tick()
        while true do
            local a = math.clamp((tick() - t0) / duration, 0, 1)
            local s = a * a * (3 - 2 * a)
            root.CFrame = CFrame.new(root.Position) * startRot:Lerp(goalRot, s)
            if a >= 1 then break end
            RunService.Heartbeat:Wait()
            ok, char, hum, root = stillOk(token)
            if not ok then return end
        end
        root.AssemblyAngularVelocity = Vector3.zero
    end

    -- is a new cast allowed from here? (on the spot, looking the saved way, last cast did not fail)
    function hm.needAlign(root)
        local s = hm.spot
        if not s then return false end
        if hm.needFace then return true end
        if flatDist(root.Position, s.pos) > ALIGN_DIST then return true end
        local look = flat(root.CFrame.LookVector)
        if not look then return true end
        return look:Dot(s.look) < math.cos(math.rad(ALIGN_ANGLE))
    end

    -- which way is the open sea? Look at 24 directions from `pos`: water (terrain water, or ground at / below sea level)
    -- under the points 10..55 studs ahead scores, dry land ahead or a wall right in front costs. `prefer` (unit flat
    -- vector) only breaks ties. Returns a unit flat vector, or nil when no direction looks like open water.
    function hm.seaLook(pos, prefer)
        local char = lp.Character
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local skip = { char }
        local boats = workspace:FindFirstChild("Boat")
        if boats then skip[#skip + 1] = boats end
        params.FilterDescendantsInstances = skip
        params.IgnoreWater = false
        local level = 0
        pcall(function() level = tonumber(game:GetService("ReplicatedStorage").SeaLevel.Value) or 0 end)
        local best, bestScore = nil, -1e9
        for i = 0, 23 do
            local ang = i / 24 * math.pi * 2
            local look = Vector3.new(-math.sin(ang), 0, -math.cos(ang))
            local score = 0
            for _, d in ipairs({ 10, 18, 28, 40, 55 }) do
                local q = pos + look * d
                local hit = workspace:Raycast(Vector3.new(q.X, pos.Y + 40, q.Z), Vector3.new(0, -140, 0), params)
                if hit then
                    if hit.Material == Enum.Material.Water or hit.Position.Y <= level + 1.5 then
                        score = score + 1
                    elseif hit.Position.Y > pos.Y - 3 then
                        score = score - 2
                    end
                end
            end
            local wall = workspace:Raycast(pos + Vector3.new(0, 1.5, 0), look * 8, params)
            if wall and wall.Material ~= Enum.Material.Water then score = score - 3 end
            if prefer then score = score + 0.5 * look:Dot(prefer) end
            if score > bestScore then best, bestScore = look, score end
        end
        if best and bestScore >= 3 then return best end
        return nil
    end

    -- go back to the spot (walk, or snap when very far) and face the sea
    function hm.align(why)
        if hm.busy or not hm.spot then return end
        -- two casts in a row did not reach the water: the saved direction is wrong (cast hits the ground) -> look for the sea
        if hm.fails >= 2 and not hm.reseaAt or (hm.fails >= 2 and tick() - hm.reseaAt > 4) then
            hm.reseaAt = tick()
            local okS, nl = pcall(hm.seaLook, hm.spot.pos, nil)
            if okS and nl then
                -- a failed direction is a bad candidate: if the finder insists on the same one, turn 90 degrees
                if nl:Dot(hm.spot.look) > 0.95 then nl = rotated(nl, 90) end
                hm.spot.look = nl
                hm.fails = 0
            end
        end
        local spot = hm.spot
        hm.busy = true
        hm.text = why or "Facing the sea..."
        hm.token = hm.token + 1
        local token = hm.token
        task.spawn(function()
            local okRun, err = pcall(function()
                local ok, char, hum, root = stillOk(token)
                if not ok then return end
                local d = flatDist(root.Position, spot.pos)
                if d > ALIGN_DIST then
                    -- always walk back (path-finding for long ways); teleport only after 3 failed walks in a row
                    local alive, reached = walkPath(token, spot.pos, 12 + d / 4)
                    if not alive then return end
                    if reached then
                        hm.walkFails = 0
                    else
                        hm.walkFails = (hm.walkFails or 0) + 1
                        if hm.walkFails >= 3 then
                            hm.walkFails = 0
                            if d > TELEPORT_BACK then
                                root.CFrame = CFrame.lookAt(spot.pos, spot.pos + spot.look)
                                task.wait(0.4)
                            else
                                -- cannot get back (blocked) and it is close: accept where we stand as the new spot
                                -- instead of looping forever without casting
                                local sp = hm.makeSpot(CFrame.new(root.Position) * (root.CFrame - root.CFrame.Position))
                                if sp then sp.look = spot.look; hm.spot = sp; spot = sp end
                            end
                        end
                    end
                end
                if not stillOk(token) then return end
                task.wait(0.1 + math.random() * 0.3)
                faceSpot(token, spot.look)
                hm.needFace = false
            end)
            if not okRun then lastErr = err end
            hm.busy = false
        end)
    end

    -- the break itself
    function hm.startBreak()
        if hm.busy then return end
        if not hm.spot then hm.setSpotHere() end   -- no verified cast yet: use where we stand now
        local spot = hm.spot
        if not spot then
            hm.schedule(tick())
            return
        end
        hm.busy = true
        hm.text = "Break: stretching legs..."
        hm.token = hm.token + 1
        local token = hm.token
        task.spawn(function()
            local okRun, err = pcall(function()
                local legs = math.random(2, 5)
                for i = 1, legs do
                    local ok, char, hum, root = stillOk(token)
                    if not ok then return end
                    local to = pickTarget(char, root.Position, spot)
                    if not to then break end
                    hm.text = string.format("Break: walking (%d/%d)", i, legs)
                    if not wanderTo(token, to, spot) then return end
                    task.wait(0.3 + math.random() * 1.8)
                    if math.random() < 0.3 then          -- look around: turn to a random direction
                        local a = math.random() * math.pi * 2
                        faceSpot(token, Vector3.new(math.cos(a), 0, math.sin(a)))
                        task.wait(0.3 + math.random() * 1.2)
                    end
                    if math.random() < 0.15 then
                        local ok2, _, hum2 = stillOk(token)
                        if ok2 then hum2.Jump = true end
                        task.wait(0.6)
                    end
                end
                hm.text = "Break: back to the fishing spot"
                task.wait(0.3 + math.random() * 0.8)
                local alive, reached = walkPath(token, spot.pos, 20)   -- walk all the way back, no teleport
                if not alive then return end
                task.wait(0.2 + math.random() * 0.6)
                faceSpot(token, spot.look)
                hm.needFace = false
            end)
            if not okRun then lastErr = err end
            hm.busy = false
            hm.schedule(tick())
        end)
    end

    -- called every frame from the engine: did the last cast really start fishing?
    function hm.verify(now, isFishing)
        local p = hm.pendingCast
        if not p then return end
        if isFishing then
            hm.pendingCast = nil
            hm.fails = 0
            hm.needFace = false
            if not hm.spot then hm.spot = hm.makeSpot(p.cf) end   -- first good cast = the fishing spot
        elseif now - p.t >= CAST_VERIFY then
            hm.pendingCast = nil
            hm.fails = hm.fails + 1
            hm.needFace = true
        end
    end
end
hm.schedule(tick())

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
    if ui.questBusy then statusText = "Quest: travelling / talking to NPC"; detailText = ""; return end

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
    hm.verify(now, isFishing)

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
        if Config.AutoCast and fishingStartTime > 0 and (now - fishingStartTime >= RECAST_TIMEOUT)
            and char:GetAttribute("Retractable") == true then
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
    if hm.busy then
        statusText = hm.text
        return
    end
    if Config.IdleMotion and now >= hm.nextAt then
        hm.startBreak()
        statusText = hm.text
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

    if Config.FaceSea and hm.needAlign(root) then
        hm.align("Facing the sea...")
        statusText = hm.text
        return
    end

    local castCF = root.CFrame
    pcall(function() fishing:FireServer(castCF) end)
    hm.pendingCast = { t = now, cf = castCF }
    lastCastTime = now
    if hm.fails >= 3 then
        statusText = "Casting (last " .. hm.fails .. " casts failed - face the sea, then press Set fishing spot)"
    else
        statusText = "Casting!"
    end
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
local COL_CARD = Color3.fromRGB(20, 23, 31)
local COL_ROW = Color3.fromRGB(30, 34, 46)
local COL_STROKE = Color3.fromRGB(44, 50, 66)
local COL_GREEN = Color3.fromRGB(0, 255, 150)
local COL_ON = Color3.fromRGB(0, 190, 105)
local COL_OFF = Color3.fromRGB(66, 70, 88)
local COL_RED = Color3.fromRGB(200, 60, 60)
local COL_TEXT2 = Color3.fromRGB(140, 148, 165)
local COL_TABON = Color3.fromRGB(30, 34, 46)
local COL_TABOFF = Color3.fromRGB(14, 16, 22)

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

-- window size follows the screen: full size on a PC monitor, shrinks on a phone / small window
function ui.fitSize()
    local cam = workspace.CurrentCamera
    local vp = (cam and cam.ViewportSize) or Vector2.new(1280, 720)
    local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
    local w = math.clamp(vp.X - 24, 290, 390)
    local h = math.clamp(vp.Y - (mobile and 30 or 60), 250, 590)
    return UDim2.new(0, w, 0, h), UDim2.new(0, w, 0, 46), mobile, h
end
local FULL_SIZE, MIN_SIZE = ui.fitSize()

local Main = new("Frame", {
    Size = FULL_SIZE, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
    BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ClipsDescendants = true,
}, sg)
corner(Main, 12)
new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(19, 22, 31), Color3.fromRGB(10, 11, 15)), Rotation = 90 }, Main)
new("UIStroke", { Color = COL_STROKE, Thickness = 1 }, Main)

local TitleBar = new("Frame", { Size = UDim2.new(1, 0, 0, 46), BackgroundTransparency = 1 }, Main)
new("TextLabel", {
    Size = UDim2.new(1, -122, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1,
    Text = "PPINGYYY  Auto Fish", TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14,
    TextXAlignment = Enum.TextXAlignment.Left,
}, TitleBar)

local CloseBtn = new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -38, 0, 10), Text = "✕", Font = Enum.Font.GothamBold,
    TextSize = 12, BackgroundColor3 = COL_ROW, TextColor3 = COL_TEXT2, AutoButtonColor = true,
}, TitleBar)
corner(CloseBtn, 6)

local MinBtn = new("TextButton", {
    Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -70, 0, 10), Text = "—", Font = Enum.Font.GothamBold,
    TextSize = 12, BackgroundColor3 = COL_ROW, TextColor3 = COL_TEXT2, AutoButtonColor = true,
}, TitleBar)
corner(MinBtn, 6)

do
    local HelpBtn = new("TextButton", {
        Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -102, 0, 10), Text = "?", Font = Enum.Font.GothamBold,
        TextSize = 13, BackgroundColor3 = COL_ROW, TextColor3 = COL_GREEN, AutoButtonColor = true,
    }, TitleBar)
    corner(HelpBtn, 6)
    HelpBtn.MouseButton1Click:Connect(function()
        play(clickSound)
        if ui.toggleHelp then ui.toggleHelp() end
    end)
end

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
            BackgroundColor3 = on and COL_TABON or COL_TABOFF, TextColor3 = on and COL_GREEN or COL_TEXT2,
        }):Play()
        tb.line.Visible = on
    end
end

local function addTab(name, label, order)
    local btn = new("TextButton", {
        Size = UDim2.new(1 / 6, -3.4, 1, 0), LayoutOrder = order, Text = label, Font = Enum.Font.GothamBold, TextSize = 11,
        BackgroundColor3 = COL_TABOFF, TextColor3 = COL_TEXT2, BorderSizePixel = 0, AutoButtonColor = false,
    }, TabBar)
    corner(btn, 7)
    local line = new("Frame", {
        Size = UDim2.new(1, -16, 0, 2), Position = UDim2.new(0, 8, 1, -4), BackgroundColor3 = COL_GREEN,
        BorderSizePixel = 0, Visible = false, BackgroundTransparency = 1,
    }, btn)
    corner(line, 1)
    local page = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 1, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 3,
        ScrollBarImageColor3 = COL_GREEN, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        ScrollingDirection = Enum.ScrollingDirection.Y, Visible = false,
    }, Pages)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 8) }, page)
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

addTab("Fish", "Fish", 1)
addTab("Skill", "Skill", 2)
addTab("Sell", "Sell", 3)
addTab("Stats", "Stats", 4)
addTab("Quest", "Quest", 5)
addTab("Misc", "Misc", 6)

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
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, card)
    new("UIPadding", {
        PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8), PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8),
    }, card)
    text = string.gsub(text, "^[^%w]+", "")     -- plain title, no emoji
    new("TextLabel", {
        Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Text = string.upper(text), LayoutOrder = nextOrder(),
        TextColor3 = COL_TEXT2, Font = Enum.Font.GothamBold, TextSize = 10, TextXAlignment = Enum.TextXAlignment.Left,
    }, card)
    Body = card
    return card
end

-- switch row: label on the left, pill switch on the right
local function toggleButton(label, h, initial, onChange)
    local state = initial and true or false
    local row = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 30), LayoutOrder = nextOrder(), BackgroundTransparency = 1,
        BorderSizePixel = 0, Text = "", AutoButtonColor = false,
    }, Body)
    new("TextLabel", {
        Size = UDim2.new(1, -62, 1, 0), Position = UDim2.new(0, 2, 0, 0), BackgroundTransparency = 1, Text = label,
        TextColor3 = Color3.fromRGB(230, 233, 240), Font = Enum.Font.Gotham, TextSize = 12, TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, row)
    local pill = new("Frame", {
        Size = UDim2.new(0, 38, 0, 20), Position = UDim2.new(1, -40, 0.5, -10), BackgroundColor3 = COL_OFF, BorderSizePixel = 0,
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
    text = string.gsub(text, "^[^%w]+", "")
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 28), LayoutOrder = nextOrder(), Font = Enum.Font.GothamMedium, TextSize = 11,
        Text = text, BackgroundColor3 = COL_ROW, TextColor3 = COL_GREEN, BorderSizePixel = 0,
    }, Body)
    corner(btn, 7)
    btn.MouseButton1Click:Connect(onClick)
    return btn
end

local function isPointer(input)
    return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

-- slider with - / + buttons. Returns a setter.
local function makeSlider(title, unit, vmin, vmax, snap, btnStep, decimals, initial, onChange)
    local box = new("Frame", { Size = UDim2.new(1, 0, 0, 50), BackgroundTransparency = 1, BorderSizePixel = 0, LayoutOrder = nextOrder() }, Body)

    new("TextLabel", {
        Size = UDim2.new(0.62, 0, 0, 18), Position = UDim2.new(0, 2, 0, 2), BackgroundTransparency = 1,
        Text = title, TextColor3 = Color3.fromRGB(230, 233, 240), Font = Enum.Font.Gotham, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, box)
    local label = new("TextLabel", {
        Size = UDim2.new(0.38, 0, 0, 18), Position = UDim2.new(0.62, -2, 0, 2), BackgroundTransparency = 1,
        Text = "", TextColor3 = COL_GREEN, Font = Enum.Font.GothamBold, TextSize = 12,
        TextXAlignment = Enum.TextXAlignment.Right,
    }, box)

    local function stepBtn(text, pos)
        local b = new("TextButton", {
            Size = UDim2.new(0, 26, 0, 22), Position = pos, Text = text, Font = Enum.Font.GothamBold,
            TextSize = 14, BackgroundColor3 = COL_ROW, TextColor3 = COL_GREEN, BorderSizePixel = 0,
        }, box)
        corner(b, 5)
        return b
    end
    local minus = stepBtn("-", UDim2.new(0, 2, 0, 24))
    local plus = stepBtn("+", UDim2.new(1, -28, 0, 24))

    local hit = new("Frame", { Size = UDim2.new(1, -86, 0, 24), Position = UDim2.new(0, 43, 0, 23), BackgroundTransparency = 1 }, box)
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

    local fmt = "%." .. decimals .. "f %s"
    local scale = 10 ^ decimals
    local function setValue(v)
        v = math.floor(v / snap + 0.5) * snap
        v = math.clamp(v, vmin, vmax)
        v = math.floor(v * scale + 0.5) / scale
        label.Text = string.format(fmt, v, unit)
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
        Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Font = Enum.Font.GothamMedium, TextSize = 11,
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
        btn.Text = title .. ":  " .. tostring(selected) .. (list.Visible and "   ▴" or "   ▾")
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

-- dropdown with a search box (for long lists, e.g. your skills): getOptions() is read each time it is opened, "" = none
local function makeSearchPicker(title, getOptions, getValue, onPick)
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(),
    }, Body)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, holder)
    local btn = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, Font = Enum.Font.GothamMedium, TextSize = 11,
        BackgroundColor3 = COL_ROW, TextColor3 = COL_GREEN, BorderSizePixel = 0,
    }, holder)
    corner(btn, 6)
    local panel = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Visible = false,
    }, holder)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, panel)
    local box = new("TextBox", {
        Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 1, BackgroundColor3 = COL_ROW, BorderSizePixel = 0, Text = "",
        PlaceholderText = "type to search...", PlaceholderColor3 = Color3.fromRGB(120, 120, 120),
        TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.Gotham, TextSize = 11, ClearTextOnFocus = false,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, panel)
    corner(box, 6)
    new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, box)
    local list = new("ScrollingFrame", {
        Size = UDim2.new(1, 0, 0, 130), LayoutOrder = 2, BackgroundColor3 = COL_ROW, BorderSizePixel = 0,
        ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
    }, panel)
    corner(list, 6)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, list)
    local function refreshTitle()
        local v = getValue()
        btn.Text = title .. ":  " .. ((v ~= nil and v ~= "") and v or "none") .. (panel.Visible and "   ▴" or "   ▾")
    end
    local function rebuild()
        for _, c in ipairs(list:GetChildren()) do
            if c:IsA("TextButton") then c:Destroy() end
        end
        local q = string.lower(box.Text or "")
        local cur = getValue()
        local opts = { "" }
        for _, o in ipairs(getOptions()) do opts[#opts + 1] = o end
        local n = 0
        for _, name in ipairs(opts) do
            if q == "" or name == "" or string.find(string.lower(name), q, 1, true) then
                n = n + 1
                local ob = new("TextButton", {
                    Size = UDim2.new(1, -4, 0, 22), LayoutOrder = n, Text = (name == "") and "(none)" or name, Font = Enum.Font.Gotham,
                    TextSize = 10, BackgroundColor3 = (name == cur) and Color3.fromRGB(0, 70, 45) or COL_ROW,
                    TextColor3 = (name == cur) and COL_GREEN or Color3.new(1, 1, 1), BorderSizePixel = 0,
                }, list)
                corner(ob, 4)
                ob.MouseButton1Click:Connect(function()
                    play(clickSound)
                    panel.Visible = false
                    onPick(name)
                    refreshTitle()
                end)
            end
        end
    end
    box:GetPropertyChangedSignal("Text"):Connect(rebuild)
    btn.MouseButton1Click:Connect(function()
        play(clickSound)
        panel.Visible = not panel.Visible
        if panel.Visible then box.Text = ""; rebuild() end
        refreshTitle()
    end)
    refreshTitle()
    return refreshTitle
end

-- a panel whose rows are rebuilt on demand: setRows({ { text = "...", color = Color3, on = function() end }, ... })
function ui.makeRowsPanel()
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(),
    }, Body)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 3) }, holder)
    return function(rows)
        for _, c in ipairs(holder:GetChildren()) do
            if c:IsA("TextButton") or c:IsA("TextLabel") then c:Destroy() end
        end
        if #rows == 0 then
            new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, BackgroundTransparency = 1, Text = "(no skills equipped right now)",
                TextColor3 = Color3.fromRGB(150, 150, 150), Font = Enum.Font.Gotham, TextSize = 10,
            }, holder)
        end
        for i, r in ipairs(rows) do
            local b = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 26), LayoutOrder = i, Text = r.text, Font = Enum.Font.GothamMedium, TextSize = 11,
                BackgroundColor3 = COL_ROW, TextColor3 = r.color or Color3.new(1, 1, 1), BorderSizePixel = 0,
            }, holder)
            corner(b, 6)
            b.MouseButton1Click:Connect(function() play(clickSound); r.on() end)
        end
    end
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

-- collapsible group of sub-options: ui.sub("Options") ... widgets ... ui.endSub()
-- (closed by default; the header is a small arrow button that sits under the feature's main switch)
function ui.sub(title)
    local parentBody = Body
    local holder = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder(),
    }, parentBody)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 5) }, holder)
    local header = new("TextButton", {
        Size = UDim2.new(1, 0, 0, 22), LayoutOrder = 1, Text = "", BackgroundTransparency = 1,
        BorderSizePixel = 0, AutoButtonColor = false,
    }, holder)
    corner(header, 6)
    local label = new("TextLabel", {
        Size = UDim2.new(1, -12, 1, 0), Position = UDim2.new(0, 2, 0, 0), BackgroundTransparency = 1,
        Text = "▸  " .. title, TextColor3 = COL_TEXT2, Font = Enum.Font.GothamMedium, TextSize = 11,
        TextXAlignment = Enum.TextXAlignment.Left,
    }, header)
    local inner = new("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 2, Visible = false,
    }, holder)
    new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 6) }, inner)
    new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingTop = UDim.new(0, 2), PaddingBottom = UDim.new(0, 4) }, inner)
    header.MouseButton1Click:Connect(function()
        play(clickSound)
        inner.Visible = not inner.Visible
        label.Text = (inner.Visible and "▾  " or "▸  ") .. title
        label.TextColor3 = inner.Visible and COL_GREEN or COL_TEXT2
    end)
    ui.subParent = parentBody
    Body = inner
end
function ui.endSub()
    if ui.subParent then
        Body = ui.subParent
        ui.subParent = nil
    end
end

-- tab: Fish ----------------------------------------------------------
setPage("Fish")
-- 🎣 Auto Cast ------------------------------------------------------
section("Auto cast")
toggleButton("Auto cast", 32, Config.AutoCast, function(v)
    play(castSound)
    Config.AutoCast = v
    equipAttempts = 0
    idleSince = nil
    hm.resetSpot()              -- stand facing the sea when you switch it on: the first good cast saves the spot
    hm.schedule(tick())
end)
ui.sub("Options")
makeSlider("Cast Delay", "s", DELAY_MIN, DELAY_MAX, DELAY_STEP, DELAY_STEP, 1, Config.CastDelay, function(v)
    Config.CastDelay = v
end)
toggleButton("Stop when inventory is full", 28, Config.StopWhenFull, function(v)
    play(clickSound)
    Config.StopWhenFull = v
end)
toggleButton("Face the sea before each cast", 30, Config.FaceSea, function(v)
    play(clickSound)
    Config.FaceSea = v
end)
actionButton("Set fishing spot here", 28, function()
    play(clickSound)
    hm.setSpotHere()
end)
ui.endSub()

-- 🚀 Minigame ---------------------------------------------------------
section("Minigame")
toggleButton("Anchor bar", 32, Config.AnchorBar, function(v)
    play(clickSound)
    Config.AnchorBar = v
end)
ui.sub("Options")
makeSlider("Bar jump range", "%", 0, 35, 1, 5, 0, Config.BarSway, function(v)
    Config.BarSway = v
end)
makeSlider("Bar jump speed", "/s", 1, 12, 1, 1, 0, Config.BarSwaySpeed, function(v)
    Config.BarSwaySpeed = v
end)
ui.endSub()
toggleButton("Auto slam / crits", 28, Config.AutoSlam, function(v)
    play(clickSound)
    Config.AutoSlam = v
end)
toggleButton("Auto charge durability", 28, Config.AutoCharge, function(v)
    play(clickSound)
    Config.AutoCharge = v
end)

-- tab: Skill ---------------------------------------------------------
setPage("Skill")
do
-- ⚡ Auto Skill ------------------------------------------------------
section("Auto skill")
toggleButton("Auto skill", 32, Config.AutoSkill, function(v)
    play(skillSound)
    Config.AutoSkill = v
end)
ui.sub("Keys and mode")
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

ui.endSub()

-- live slot status
do
    local e = infoCard({ { "Z", "Key Z" }, { "X", "Key X" }, { "C", "Key C" }, { "V", "Key V" } }, 0.2)
    ui.skill = e
end

-- boss / combat -------------------------------------------------------
section("Boss and combat")
toggleButton("Heal when HP is low", 30, Config.HealEnabled, function(v)
    play(clickSound)
    Config.HealEnabled = v
end)
ui.sub("Options")
makeSlider("Heal below", "%", 10, 90, 5, 5, 0, Config.HealBelow, function(v)
    Config.HealBelow = v
end)
ui.endSub()
toggleButton("Pause attacks while boss is invincible", 30, Config.HoldOnInvincible, function(v)
    play(clickSound)
    Config.HoldOnInvincible = v
end)
toggleButton("Alert on secret boss", 30, Config.BossAlert, function(v)
    play(clickSound)
    Config.BossAlert = v
end)
toggleButton("Auto rhythm game (boss phase 2)", 30, Config.AutoRhythm, function(v)
    play(clickSound)
    Config.AutoRhythm = v
end)
ui.sub("Options")
makeSlider("Mistakes per game", "", 0, 3, 1, 1, 0, Config.RhythmMiss, function(v)
    Config.RhythmMiss = v
end)
ui.endSub()
-- Rhythm minigame (boss phase 2). What the game does (ClientModule.Fishing, Events.RhythmStart): notes fall down three lanes
-- A / S / D (MainGui.Fishing.Rhythm.ProgressionA/S/D, a falling frame named "Note_FX"); a click on the lane button (or the
-- key) calls TryHit: the note closest to the hit line within 0.22 is "hit" (Events.RhythmHit:FireServer("hit")), no note
-- in range = "miss"; a note that falls past = "miss"; RED notes (hard mode) are traps - hitting one counts as a miss.
-- We press the lane button when a note reaches the line (a little early / late at random), skip the red notes, and let
-- a few chosen notes fall past on purpose so the run does not look perfect.
;(function()
    local LANES = { "A", "S", "D" }
    local st = { on = false, count = 0, miss = {}, seen = setmetatable({}, { __mode = "k" }), lastPress = {}, m = 1, fail = {}, good = {}, reported = false }
    local function pickMisses()
        st.miss = {}
        local n = math.floor(Config.RhythmMiss or 0)
        local tries = 0
        while n > 0 and tries < 50 do
            tries = tries + 1
            local idx = math.random(12, 160)        -- which note of the run gets dropped
            if not st.miss[idx] then st.miss[idx] = true; n = n - 1 end
        end
    end
    -- Ways to "press" a lane, from the cleanest to the most basic. Weak executors (Xeno, ...) often have firesignal /
    -- getconnections as stubs that return without error but do nothing, so a press is VERIFIED: when the game accepts a
    -- hit it destroys the note (TryHit -> gui:Destroy()). A method that keeps failing is replaced by the next one, and the
    -- one that works is remembered for the rest of the session.
    local function log(msg)
        print("[PPINGYYY rhythm] " .. tostring(msg))
        pcall(function() if ui.qlog then ui.qlog("rhythm: " .. tostring(msg)) end end)
    end
    local function clickAt(btn, withInset)
        return (pcall(function()
            local vim = game:GetService("VirtualInputManager")
            local p, sz = btn.AbsolutePosition, btn.AbsoluteSize
            local off = Vector2.new(0, 0)
            if withInset then off = game:GetService("GuiService"):GetGuiInset() end
            local x, y = p.X + sz.X / 2 + off.X, p.Y + sz.Y / 2 + off.Y
            vim:SendMouseButtonEvent(x, y, 0, true, game, 0)
            task.wait(0.03)
            vim:SendMouseButtonEvent(x, y, 0, false, game, 0)
        end))
    end
    local METHODS = {
        { "firesignal", function(btn)
            if not firesignal then return false end
            return (pcall(firesignal, btn.MouseButton1Click))
        end },
        { "getconnections", function(btn)
            if not getconnections then return false end
            local done = false
            local ok = pcall(function()
                for _, c in ipairs(getconnections(btn.MouseButton1Click)) do
                    pcall(function() c:Fire() end)
                    done = true
                end
            end)
            return ok and done
        end },
        { "key press", function(btn, lane)
            return (pcall(function()
                local vim = game:GetService("VirtualInputManager")
                vim:SendKeyEvent(true, Enum.KeyCode[lane], false, game)
                task.wait(0.03)
                vim:SendKeyEvent(false, Enum.KeyCode[lane], false, game)
            end))
        end },
        { "mouse click", function(btn) return clickAt(btn, true) end },
        { "mouse click (no inset)", function(btn) return clickAt(btn, false) end },
    }
    if Config.RhythmMethod and METHODS[Config.RhythmMethod] then st.m = Config.RhythmMethod end   -- the one that worked last time
    local function press(rhythm, lane, m)
        local fr = rhythm:FindFirstChild("Progression" .. lane)
        local btn = fr and fr:FindFirstChild("Button")
        local meth = METHODS[m]
        if not (btn and meth) then return false end
        return meth[2](btn, lane)
    end
    local function isTrap(note)
        local c = note.BackgroundColor3
        return c.R > 0.9 and c.G < 0.3 and c.B < 0.3
    end
    task.spawn(function()
        local ev = RS:WaitForChild("Events", 30)
        local rs = ev and ev:WaitForChild("RhythmStart", 30)
        local stop = ev and ev:WaitForChild("RhythmStop", 30)
        if rs then
            conns[#conns + 1] = rs.OnClientEvent:Connect(function()
                if not st.reported then
                    st.reported = true
                    local okV = pcall(function() return game:GetService("VirtualInputManager") end)
                    log(string.format("executor: firesignal=%s getconnections=%s VirtualInputManager=%s", tostring(firesignal ~= nil), tostring(getconnections ~= nil), tostring(okV)))
                end
                st.on = true
                st.count = 0
                st.seen = setmetatable({}, { __mode = "k" })
                pickMisses()
            end)
        end
        if stop then
            conns[#conns + 1] = stop.OnClientEvent:Connect(function() st.on = false end)
        end
    end)
    conns[#conns + 1] = RunService.Heartbeat:Connect(function()
        if not (running and st.on and Config.AutoRhythm) then return end
        local gui = lp:FindFirstChild("PlayerGui")
        local main = gui and gui:FindFirstChild("MainGui")
        local fishing = main and main:FindFirstChild("Fishing")
        local rhythm = fishing and fishing:FindFirstChild("Rhythm")
        if not rhythm then return end
        if not rhythm.Visible then
            if tick() - (st.lastSeen or 0) > 8 then st.on = false end    -- the game window is gone: game over
            return
        end
        st.lastSeen = tick()
        local now = tick()
        for _, lane in ipairs(LANES) do
            local fr = rhythm:FindFirstChild("Progression" .. lane)
            if fr then
                local bar = fr:FindFirstChild("BarFrame")
                local line = bar and bar.Position.Y.Scale or 0.85
                for _, note in ipairs(fr:GetChildren()) do
                    if note.Name == "Note_FX" and note:IsA("GuiObject") then
                        local s = st.seen[note]
                        if not s then
                            st.count = st.count + 1
                            s = {
                                skip = st.miss[st.count] == true or isTrap(note),
                                -- hit a little before / after the line (fractions of the screen; 0.05 is about 60 ms)
                                off = (math.random() < 0.06) and (0.01 + math.random() * 0.03) or (-0.13 + math.random() * 0.12),
                                done = false,
                            }
                            st.seen[note] = s
                        end
                        if not s.skip and not s.done then
                            local y = note.Position.Y.Scale
                            if y >= line + s.off and now - (st.lastPress[lane] or 0) > 0.06 then
                                s.done = true
                                st.lastPress[lane] = now
                                local m = st.m
                                local y0 = note.Position.Y.Scale
                                task.spawn(function()
                                    press(rhythm, lane, m)
                                    task.wait(0.1)
                                    if note.Parent == nil then
                                        -- gone: the game took it (a hit)... unless it was so low that it could have fallen past the
                                        -- line on its own in these 0.1 s (a miss also removes the note): then it proves nothing
                                        if y0 <= line + 0.10 then
                                            st.fail[m] = 0
                                            if not st.good[m] then
                                                st.good[m] = true
                                                log("input method that works: " .. METHODS[m][1])
                                                if Config.RhythmMethod ~= m then
                                                    Config.RhythmMethod = m                  -- remembered for the next run
                                                    pcall(markDirty)
                                                end
                                            end
                                        end
                                    else                                       -- still there: the press did nothing
                                        st.fail[m] = (st.fail[m] or 0) + 1
                                        local limit = st.good[m] and 6 or 2    -- a method that worked before gets more patience
                                        if st.fail[m] >= limit and st.m == m then
                                            st.m = m % #METHODS + 1
                                            st.fail[m] = 0
                                            log("'" .. METHODS[m][1] .. "' does nothing here -> trying '" .. METHODS[st.m][1] .. "'")
                                        end
                                        if running and st.on and note.Parent and note.Position.Y.Scale < line + 0.17 then
                                            s.done = false                     -- still inside the hit window: press again
                                        end
                                    end
                                end)
                            end
                        end
                    end
                end
            end
        end
    end)
end)()
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
section("Selling")
toggleButton("Auto sell", 32, Config.AutoSell, function(v)
    play(sellSound)
    Config.AutoSell = v
end)
ui.sub("Options")
makeSlider("Sell interval", "s", SELL_MIN, SELL_MAX, 1, 5, 0, Config.SellInterval, function(v)
    Config.SellInterval = v
end)
actionButton("Sell now (teleports to Nana)", 30, function()
    play(sellSound)
    sellNow()
end)
ui.endSub()
toggleButton("Auto favourite fish", 28, Config.AutoFavourite, function(v)
    play(clickSound)
    Config.AutoFavourite = v
end)
ui.sub("Options")
makeDropdown("Target fish", FISH_LIST, Config.FavouriteFishName, function(name)
    Config.FavouriteFishName = name
end)
ui.endSub()
toggleButton("Material farming", 28, Config.MaterialFarming, function(v)
    play(clickSound)
    Config.MaterialFarming = v
end)

-- tab: Stats ---------------------------------------------------------
setPage("Stats")
do
-- 📊 Money Stats --------------------------------------------------------
section("Money stats")
ui.stats = infoCard({
    { "level", "Level" }, { "weather", "Weather" },
    { "cash", "Current Cash" }, { "net", "Net Cash (session)" }, { "cph", "Cash / hour" },
    { "fish", "Total Fish Caught" }, { "fsess", "Fish (session)" }, { "fph", "Fish / hour" },
    { "time", "Session Time" }, { "rod", "Equipped Rod" }, { "bait", "Equipped Bait" },
})
actionButton("Reset session", 26, function()
    play(clickSound)
    resetSession()
end)

-- 🔔 Discord Webhook ------------------------------------------------------
section("Discord webhook")

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

toggleButton("Webhook reports", 32, Config.WebhookEnabled, function(v)
    play(clickSound)
    Config.WebhookEnabled = v
    lastWebhookTime = tick()
    live.last = 0
    if v and not validWebhook(Config.WebhookUrl) then webhookStatus = "Set a valid webhook URL first" end
end)
ui.sub("Options")
toggleButton("Live mode (edit one message)", 30, Config.WebhookLive, function(v)
    play(clickSound)
    Config.WebhookLive = v
    live.last = 0
    markDirty()
end)
makeSlider("Live update", "s", 10, 120, 5, 5, 0, Config.LiveInterval, function(v)
    Config.LiveInterval = v
    markDirty()
end)
makeSlider("Report every", "min", WEBHOOK_MIN, WEBHOOK_MAX, 1, 5, 0, Config.WebhookInterval, function(v)
    Config.WebhookInterval = v
    lastWebhookTime = tick()  -- changing the interval restarts the countdown
    markDirty()
end)
actionButton("Send test report", 28, function()
    play(sellSound)
    if Config.WebhookLive then
        live.last = 0
        live.backoff = 0
        liveUpdate()
    else
        sendWebhook("test")
    end
end)
actionButton("Start a new live message", 26, function()
    play(clickSound)
    live.id = ""
    live.last = 0
    markDirty()
    webhookStatus = "Next update creates a new message"
end)
ui.endSub()
ui.hook = infoCard({ { "next", "Next update" }, { "status", "Last result" } }, 0.28)
uiReady = true

end

-- tab: Misc ----------------------------------------------------------
setPage("Misc")
-- 🛡️ Anti AFK ----------------------------------------------------------
section("Anti-AFK")
toggleButton("Anti-AFK", 28, Config.AntiAFK, function(v)
    play(clickSound)
    Config.AntiAFK = v
    markDirty()
end)
toggleButton("Leave game AFK mode automatically", 34, Config.LeaveGameAFK, function(v)
    play(clickSound)
    Config.LeaveGameAFK = v
end)
toggleButton("Human break", 34, Config.IdleMotion, function(v)
    play(clickSound)
    Config.IdleMotion = v
    hm.schedule(tick())
end)
ui.sub("Options")
makeSlider("Earliest break", "min", 2, 30, 1, 1, 0, Config.BreakMin, function(v)
    Config.BreakMin = v
    if Config.BreakMax < v then Config.BreakMax = v end
end)
makeSlider("Latest break", "min", 2, 45, 1, 1, 0, Config.BreakMax, function(v)
    Config.BreakMax = math.max(v, Config.BreakMin)
end)
makeSlider("Walk radius", "studs", 4, 12, 1, 1, 0, Config.BreakWalk, function(v)
    Config.BreakWalk = v
end)
actionButton("Take a break now", 26, function()
    play(clickSound)
    hm.nextAt = 0
end)
ui.endSub()
ui.afk = infoCard({ { "afk", "Status" } }, 0.17).afk

-- 🔮 ESP ------------------------------------------------------------
section("ESP")
toggleButton("Taoist ESP", 28, Config.ESP_Taoist, function(v)
    play(clickSound)
    Config.ESP_Taoist = v
    espLastScan = 0
end)
toggleButton("Maoshan ESP", 28, Config.ESP_Maoshan, function(v)
    play(clickSound)
    Config.ESP_Maoshan = v
    espLastScan = 0
end)
ui.sub("Options")
toggleButton("Tracer line", 28, Config.ESP_Tracer, function(v)
    play(clickSound)
    Config.ESP_Tracer = v
end)
toggleButton("Alert when found", 28, Config.ESP_Notify, function(v)
    play(clickSound)
    Config.ESP_Notify = v
end)
ui.endSub()
do
    local e = infoCard({ { "taoist", "Taoist" }, { "maoshan", "Maoshan" } })
    ui.esp = { taoist = e.taoist, maoshan = e.maoshan }
end

-- tab: Quest ---------------------------------------------------------
-- Ticket Quest automation. Everything below was derived from a real log of doing the quest by hand:
--   talk to NPC  -> server sends StartDialogue(npcName, npcModel, {text, {{label, type, flag}, ...}}, args)
--   pick option  -> client sends ChooseDialogueOption(npcName, optionIndex, optionType, args)
--   "Quest" -> (turn in if finished / "come back in m:ss" if on cooldown / accept menu) -> "HardAcceptQuest" / "EasyAcceptQuest"
--   boat         -> SpawnBoat NPC option "BoatShop" -> server VisibleUI("BoatShop","LocationN") -> Spawn(boatName,"LocationN")
-- The quest data lives in Data[UserId].Quest.Main["Hard Ticket Quest"] ("description,amount,type,target"), cooldown in
-- Data[UserId].TicketQuestCooldown (server time).
setPage("Quest")
;(function()
    -- trace of what the quest automation did: console + file PPINGYYY_QuestLog.txt (send that file when something goes wrong)
    local qBuf, qT0, qLastWrite, qDirty = {}, tick(), 0, false
    local function qlog(msg)
        msg = string.format("[%7.1f] %s", tick() - qT0, tostring(msg))
        print("[PPINGYYY quest] " .. msg)
        qBuf[#qBuf + 1] = msg
        if #qBuf > 400 then table.remove(qBuf, 1) end
        qDirty = true
    end
    ui.qlog = qlog          -- the rhythm bot (another block) writes its diagnostics into the same log file
    local function qflush(force)
        if not qDirty or not writefile then return end
        if not force and tick() - qLastWrite < 3 then return end
        qLastWrite, qDirty = tick(), false
        pcall(writefile, "PPINGYYY_QuestLog.txt", table.concat(qBuf, "\n"))
    end
    task.spawn(function()
        while running do
            task.wait(3)
            qflush(false)
        end
    end)
    local qsData = { status = "Idle", dlg = nil, dlgAt = 0, shop = nil, busy = false, lastTalk = 0, boatNote = "" }
    -- every assignment to qs.status is logged (the proxy is empty, so all writes go through __newindex)
    local qs = setmetatable({}, {
        __index = qsData,
        __newindex = function(_, k, v)
            if k == "status" and v ~= qsData.status then qlog("status: " .. tostring(v)) end
            qsData[k] = v
        end,
    })
    local TICKET_NPC = "Ticket Quest Giver"
    local QUEST_NAMES = { "Hard Ticket Quest", "Easy Ticket Quest" }
    -- boat waypoints (x, z), taken from the positions logged while sailing by hand
    local ROUTE_TO_FARM = { Vector2.new(-360, 182), Vector2.new(61, 399), Vector2.new(395, 229), Vector2.new(755, 143), Vector2.new(1155, 185), Vector2.new(1341, 216) }
    local ROUTE_TO_QUEST = { Vector2.new(1311, 362), Vector2.new(953, 75), Vector2.new(830, 553), Vector2.new(564, 313), Vector2.new(146, 167) }

    local function myRoot() local c = lp.Character; return c and c:FindFirstChild("HumanoidRootPart") end
    local function myHum() local c = lp.Character; return c and c:FindFirstChildOfClass("Humanoid") end
    local function dist(pos) local r = myRoot(); return r and (r.Position - pos).Magnitude or math.huge end
    -- two fishing spots: "hard" (the original one, e.g. big fish) and "easy" (a quick island for the simple "use N bait /
    -- skill" quests). qs.farmKind says which one the current quest wants; without an easy spot everything uses the hard one.
    -- a third one, "idle", is used while the quest is on cooldown or the daily quest limit is reached
    local function farmKindNow()
        local k = qs.farmKind
        if k == "easy" and Config.QuestFarmPosEasy then return "easy" end
        if k == "idle" and Config.QuestFarmPosIdle and Config.IdleSpotOn then return "idle" end
        return "hard"
    end
    local function farmIsEasy() return farmKindNow() == "easy" end
    local function farmPos()
        local k = farmKindNow()
        local p = (k == "easy" and Config.QuestFarmPosEasy) or (k == "idle" and Config.QuestFarmPosIdle) or Config.QuestFarmPos
        return Vector3.new(p[1], p[2], p[3])
    end
    local function farmLook()
        local k = farmKindNow()
        return (k == "easy" and Config.QuestFarmLookEasy) or (k == "idle" and Config.QuestFarmLookIdle) or Config.QuestFarmLook
    end
    local function waitFor(cond, timeout)
        local t0 = tick()
        while tick() - t0 < timeout and running and not qs.cancel do
            if cond() then return true end
            task.wait(0.1)
        end
        return cond()
    end
    local function tp(pos, look)
        local r = myRoot()
        qlog(string.format("TELEPORT to (%d,%d,%d)", pos.X, pos.Y, pos.Z))
        if r then
            pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
            local at = pos + Vector3.new(0, 3, 0)
            if look then
                r.CFrame = CFrame.lookAt(at, at + Vector3.new(look[1], 0, look[2]))
            else
                r.CFrame = CFrame.new(at) * (r.CFrame - r.CFrame.Position)   -- keep the way we were facing
            end
        end
    end
    -- turn the character towards the open water (the saved direction can point at the ground)
    local function faceSea()
        local r = myRoot()
        if not (r and hm and hm.seaLook) then return end
        pcall(function()
            local fl = farmLook()
            local pref = fl and Vector3.new(fl[1], 0, fl[2]) or nil
            local look = hm.seaLook(r.Position, pref)
            if look then r.CFrame = CFrame.lookAt(r.Position, r.Position + look) end
        end)
    end
    -- the Human-break system remembers WHERE every cast is thrown from; tell it about the farm spot (or forget it)
    local function respot(keep)
        if not hm then return end
        pcall(function() if keep then hm.setSpotHere() else hm.resetSpot() end end)
    end
    -- human-like pause between UI clicks (dialogue options, shop)
    local function uiPause(mult)
        task.wait((Config.QuestDelay or 1.2) * (mult or 1) * (0.8 + math.random() * 0.5))
    end
    -- in the water? (the game sets the Swimming attribute; the humanoid state is the backup)
    local function swimming()
        local c, h = lp.Character, myHum()
        if qs.sailing then return false end
        if c and c:GetAttribute("Swimming") == true then return true end
        return h ~= nil and h:GetState() == Enum.HumanoidStateType.Swimming
    end
    -- climb out: look for dry ground around us (nearest ring first, the spot closest to `toward` wins), swim + jump
    -- towards it, and hop onto it if the water will not let go after a few seconds
    local function rescueWater(toward)
        if qs.sailing then return false end      -- a jump while seated fires the game's BoatExitSeat: never while on the boat
        local r, h = myRoot(), myHum()
        if not (r and h) then return false end
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        local skip = { lp.Character }
        local boats = Workspace:FindFirstChild("Boat")
        if boats then skip[#skip + 1] = boats end
        params.FilterDescendantsInstances = skip
        params.IgnoreWater = false
        local best = nil
        for _, rad in ipairs({ 12, 22, 36, 55, 80, 120, 170 }) do
            for a = 0, 15 do
                local ang = a / 16 * math.pi * 2
                local x, z = r.Position.X + math.cos(ang) * rad, r.Position.Z + math.sin(ang) * rad
                local hit = Workspace:Raycast(Vector3.new(x, r.Position.Y + 60, z), Vector3.new(0, -160, 0), params)
                -- only shore we can really climb onto: not a roof / cliff (that was the "jumps way too high" bug)
                local reach = math.max(r.Position.Y, 2) + 6
                if hit and hit.Material ~= Enum.Material.Water and hit.Position.Y <= reach and hit.Position.Y > -8 then
                    local d = (toward and (hit.Position - toward).Magnitude or rad) + hit.Position.Y * 2   -- lower ledge wins
                    if not best or d < best.d then best = { pos = hit.Position, d = d } end
                end
            end
            if best then break end
        end
        if not best then
            qlog(string.format("water: swimming at (%d,%.1f,%d) and no shore found within 170 studs", r.Position.X, r.Position.Y, r.Position.Z))
            return false
        end
        if tick() - (qs.lastWaterLog or 0) > 20 then
            qs.lastWaterLog = tick()
            qlog(string.format("water: swimming at (%d,%.1f,%d), shore at (%d,%.1f,%d)", r.Position.X, r.Position.Y, r.Position.Z, best.pos.X, best.pos.Y, best.pos.Z))
        end
        qs.status = "in the water - swimming to the shore"
        local t0, lastJump = tick(), 0
        while running and tick() - t0 < 9 and swimming() do
            pcall(function() h:MoveTo(best.pos) end)
            if tick() - lastJump > 0.9 then lastJump = tick(); pcall(function() h.Jump = true end) end
            task.wait(0.15)
        end
        if swimming() then tp(best.pos - Vector3.new(0, 1.5, 0)) end      -- still in the water: put us on the shore
        task.wait(0.3)
        return true
    end
    -- get off the boat: the game's own way is the BoatExitSeat remote (it fires on Jump); retry until we are free
    -- sea route planner ---------------------------------------------------------------------------------------------
    -- A* over a 50-stud grid of open water. free(x, z) says whether a cell is open sea, clear(ax, az, bx, bz) whether a
    -- straight line is, both come from raycasts. Returns { {x, z}, ... } (start .. goal) or nil.
    local function seaAStar(free, clear, ax, az, bx, bz, weak)
        local CELL = 50
        local x0, z0 = math.min(ax, bx) - 450, math.min(az, bz) - 450
        local W = math.ceil((math.abs(ax - bx) + 900) / CELL)
        local H = math.ceil((math.abs(az - bz) + 900) / CELL)
        local function cellOf(x, z)
            return math.clamp(math.floor((x - x0) / CELL), 0, W - 1), math.clamp(math.floor((z - z0) / CELL), 0, H - 1)
        end
        local function centre(i, j) return x0 + (i + 0.5) * CELL, z0 + (j + 0.5) * CELL end
        local si, sj = cellOf(ax, az)
        local gi, gj = cellOf(bx, bz)
        local cache = {}
        local function ok(i, j)
            if i < 0 or j < 0 or i >= W or j >= H then return false end
            if (i == si and j == sj) or (i == gi and j == gj) then return true end
            local k = i + j * W
            -- shore side: the start / goal sit right next to land, so near them a single water check is enough
            if weak and (math.abs(i - si) + math.abs(j - sj) <= 3 or math.abs(i - gi) + math.abs(j - gj) <= 3) then
                local cx, cz = centre(i, j)
                return weak(cx, cz)
            end
            local v = cache[k]
            if v == nil then
                local cx, cz = centre(i, j)
                v = free(cx, cz) and true or false
                cache[k] = v
            end
            return v
        end
        local sk, gk = si + sj * W, gi + gj * W
        local g, from, closed, open = { [sk] = 0 }, {}, {}, { sk }
        local function hcost(k)
            local i, j = k % W, math.floor(k / W)
            return math.sqrt((i - gi) ^ 2 + (j - gj) ^ 2)
        end
        local steps = 0
        local found = false
        while #open > 0 and steps < 6000 do
            steps = steps + 1
            local bi, bf = 1, math.huge
            for n = 1, #open do
                local f = g[open[n]] + hcost(open[n])
                if f < bf then bi, bf = n, f end
            end
            local k = open[bi]
            open[bi] = open[#open]
            open[#open] = nil
            if not closed[k] then
                closed[k] = true
                if k == gk then found = true; break end
                local i, j = k % W, math.floor(k / W)
                for di = -1, 1 do
                    for dj = -1, 1 do
                        if di ~= 0 or dj ~= 0 then
                            local ni, nj = i + di, j + dj
                            local diag = (di ~= 0 and dj ~= 0)
                            if ok(ni, nj) and (not diag or (ok(i + di, j) and ok(i, j + dj))) then
                                local nk = ni + nj * W
                                local ng = g[k] + (diag and 1.414 or 1)
                                if not closed[nk] and (g[nk] == nil or ng < g[nk]) then
                                    g[nk] = ng
                                    from[nk] = k
                                    open[#open + 1] = nk
                                end
                            end
                        end
                    end
                end
            end
        end
        if not found then return nil end
        local cells, k = {}, gk
        while k do
            table.insert(cells, 1, k)
            k = from[k]
        end
        local pts = {}
        for n, key in ipairs(cells) do
            local i, j = key % W, math.floor(key / W)
            local cx, cz = centre(i, j)
            pts[n] = { cx, cz }
        end
        pts[1] = { ax, az }
        pts[#pts] = { bx, bz }
        -- string pulling: skip every point we can reach in a straight clear line
        local out, a = { pts[1] }, 1
        while a < #pts do
            local b = #pts
            while b > a + 1 and not clear(pts[a][1], pts[a][2], pts[b][1], pts[b][2]) do b = b - 1 end
            out[#out + 1] = pts[b]
            a = b
        end
        return out
    end

    -- is the water around (x, z) open? (raycast from high above: terrain water / anything at sea level = open sea)
    local seaParams = nil
    local function seaLevel()
        local v = 0
        pcall(function() v = tonumber(RS.SeaLevel.Value) or 0 end)
        return v
    end
    local function isWater(x, z)
        if not seaParams then
            seaParams = RaycastParams.new()
            seaParams.FilterType = Enum.RaycastFilterType.Exclude
            seaParams.IgnoreWater = false
        end
        local skip = { lp.Character }
        local boats = Workspace:FindFirstChild("Boat")
        if boats then skip[#skip + 1] = boats end
        seaParams.FilterDescendantsInstances = skip
        local lvl = seaLevel()
        local hit = Workspace:Raycast(Vector3.new(x, lvl + 150, z), Vector3.new(0, -400, 0), seaParams)
        if not hit then return true end                 -- nothing loaded there: assume open sea
        return hit.Material == Enum.Material.Water or hit.Position.Y <= lvl + 1.5
    end
    local planCalls = 0
    local function seaFree(x, z)
        planCalls = planCalls + 1
        if planCalls % 120 == 0 then task.wait() end
        return isWater(x, z) and isWater(x + 30, z) and isWater(x - 30, z) and isWater(x, z + 30) and isWater(x, z - 30)
    end
    local function seaClear(ax, az, bx, bz)
        local d = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
        local n = math.max(1, math.ceil(d / 25))
        local nx, nz = -(bz - az) / math.max(d, 1), (bx - ax) / math.max(d, 1)
        for i = 0, n do
            local x, z = ax + (bx - ax) * i / n, az + (bz - az) * i / n
            if not (isWater(x, z) and isWater(x + nx * 18, z + nz * 18) and isWater(x - nx * 18, z - nz * 18)) then return false end
        end
        return true
    end
    -- keep the known-good hand-made route when nothing is in the way, else plan a way around the land
    -- `landing` (optional Vector2): open water right next to where we want to go ashore, so the walk afterwards is short.
    -- It replaces the end of the fixed route as the goal; if nothing can be planned the old fixed route is used.
    local function chooseRoute(startPos, static, landing)
        local pts = { Vector2.new(startPos.X, startPos.Z) }
        for _, q in ipairs(static) do pts[#pts + 1] = q end
        if landing then pts[#pts + 1] = landing end
        local clearAll = true
        for i = 1, #pts - 1 do
            if not seaClear(pts[i].X, pts[i].Y, pts[i + 1].X, pts[i + 1].Y) then clearAll = false; break end
        end
        if clearAll then
            if not landing then return static, "static route clear" end
            local withLanding = {}
            for _, q in ipairs(static) do withLanding[#withLanding + 1] = q end
            withLanding[#withLanding + 1] = landing
            return withLanding, "static route + landing clear"
        end
        local goal = landing or static[#static]
        planCalls = 0
        local planned = seaAStar(seaFree, seaClear, startPos.X, startPos.Z, goal.X, goal.Y, isWater)
        local note0 = ""
        if not planned then
            -- the goal itself may sit on / behind land: look for open water around it and plan to that instead
            for _, r in ipairs({ 80, 160, 260, 380 }) do
                for k = 0, 11 do
                    local ang = k * math.pi / 6
                    local gx, gz = goal.X + math.cos(ang) * r, goal.Y + math.sin(ang) * r
                    if seaFree(gx, gz) then
                        planCalls = 0
                        planned = seaAStar(seaFree, seaClear, startPos.X, startPos.Z, gx, gz, isWater)
                        if planned then note0 = " (goal moved " .. r .. " studs to open water)"; break end
                    end
                end
                if planned then break end
            end
        end
        if not planned then return static, "no sea route found - using the fixed route" end
        local out = {}
        for i = 2, #planned do out[#out + 1] = Vector2.new(planned[i][1], planned[i][2]) end
        return out, "planned " .. #out .. " waypoints around the land" .. note0
    end

    -- the boat shop window stays open after Spawn (it covers the screen) -> close it like the X button does
    local function closeShop(name)
        pcall(function()
            local gui = lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("MainGui")
            local menu = gui and gui:FindFirstChild("Menu")
            local shop = menu and menu:FindFirstChild(name or "BoatShop")
            if not shop then return end
            local c = shop:FindFirstChild("Close")
            if c and firesignal then pcall(firesignal, c.MouseButton1Click) end
            task.wait(0.3)
            if shop.Visible then shop.Visible = false end
            local black = menu:FindFirstChild("Black")
            if black then
                local other = false
                for _, f in ipairs(menu:GetChildren()) do
                    if f:IsA("Frame") and f.Visible and f ~= black and f.Name ~= "Info" then other = true end
                end
                if not other then black.Visible = false end
            end
        end)
    end
    local function leaveBoat(seat)
        local Ev = RS:FindFirstChild("Events")
        for _ = 1, 6 do
            local h = myHum()
            if not h or h.SeatPart ~= seat then return true end
            local exitR = Ev and Ev:FindFirstChild("BoatExitSeat")
            if exitR then pcall(function() exitR:FireServer() end) end
            pcall(function() h.Jump = true; h:ChangeState(Enum.HumanoidStateType.Jumping) end)
            task.wait(0.8)
        end
        local h = myHum()
        return h == nil or h.SeatPart ~= seat
    end
    -- an obstacle right in front: probe it with horizontal rays at rising heights. The first free probe tells how
    -- tall it is. Low (a step, a crate, a kerb) -> one normal jump. Too tall -> do not jump, use a path around it.
    local function obstacleHeight(toward)
        local r, h = myRoot(), myHum()
        if not (r and h) then return nil end
        local d = Vector3.new(toward.X - r.Position.X, 0, toward.Z - r.Position.Z)
        if d.Magnitude < 1 then return nil end
        d = d.Unit
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        local feet = r.Position.Y - (h.HipHeight + r.Size.Y / 2)
        for _, hgt in ipairs({ 0.6, 1.8, 3.0, 4.2, 5.4, 6.6, 7.8, 9.0 }) do
            local hit = Workspace:Raycast(Vector3.new(r.Position.X, feet + hgt, r.Position.Z), d * 3.5, params)
            if not hit then return hgt end            -- free here: the obstacle is lower than this probe
        end
        return 99                                      -- blocked all the way up: a wall
    end
    -- walk a Roblox path (goes around things, jumps only where the path says so)
    -- `radius` = the agent radius used for the navmesh (a smaller one fits through narrow gaps). When a waypoint cannot be
    -- reached within 3 s (something blocks the way) the path is computed again from where we stand (up to 3 plans).
    local function pathTo(pos, timeout, radius)
        local r, h = myRoot(), myHum()
        if not (r and h) then return false end
        local PS = game:GetService("PathfindingService")
        local t0 = tick()
        for _ = 1, 3 do
            if not running or tick() - t0 > timeout then break end
            local rNow = myRoot()
            if not rNow then break end
            local path = PS:CreatePath({ AgentRadius = radius or 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
            local okP = pcall(function() path:ComputeAsync(rNow.Position, pos) end)
            if not okP or path.Status ~= Enum.PathStatus.Success then break end
            local blocked = false
            for i, wp in ipairs(path:GetWaypoints()) do
                if not running or tick() - t0 > timeout then break end
                if i > 1 then
                    if wp.Action == Enum.PathWaypointAction.Jump then pcall(function() h.Jump = true end) end
                    pcall(function() h:MoveTo(wp.Position) end)
                    local t1, reached = tick(), false
                    while running and tick() - t1 < 3 and tick() - t0 < timeout do
                        local rr = myRoot()
                        if rr and Vector3.new(rr.Position.X - wp.Position.X, 0, rr.Position.Z - wp.Position.Z).Magnitude < 3 then reached = true; break end
                        if swimming() then return false end
                        task.wait(0.1)
                    end
                    if not reached then blocked = true; break end      -- stuck on this waypoint: plan again from here
                end
            end
            if not blocked then break end
        end
        return dist(pos) < 12
    end

    -- reactive steering (like the whiskers of the boat): when something solid is right in front and it is too tall to
    -- jump, walk to the side that is free instead of pushing into it. Returns true when it issued a sidestep.
    local avoidSide, avoidUntil = 0, 0      -- which hand the obstacle is on (+1 / -1), kept for a while
    local function avoidStep(goal)
        local r, h = myRoot(), myHum()
        if not (r and h) then return false end
        local flat = Vector3.new(goal.X - r.Position.X, 0, goal.Z - r.Position.Z)
        if flat.Magnitude < 4 then avoidSide = 0; return false end
        local fwd = flat.Unit
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances = { lp.Character }
        params.IgnoreWater = true
        pcall(function() params.RespectCanCollide = true end)
        local feet = r.Position.Y - (h.HipHeight + r.Size.Y / 2)
        local o = Vector3.new(r.Position.X, feet + 2.5, r.Position.Z)
        local function free(dir, len)
            local hit = Workspace:Raycast(o, dir * len, params)
            return hit and (hit.Position - o).Magnitude or len
        end
        local front = Workspace:Raycast(o, fwd * 6, params)
        if not front then avoidSide = 0; return false end            -- the way ahead is open: stop following the obstacle
        if avoidSide == 0 then
            local oh = obstacleHeight(goal)
            if oh and oh < 5 then return false end                    -- low enough to jump: the stuck logic does that
        end
        -- follow the obstacle like a hand on the wall: the walking direction is "into the wall" turned by about 90 degrees.
        -- Using the wall's own normal (not the direction to the goal) keeps the same side while the goal's bearing changes.
        local n = Vector3.new(front.Normal.X, 0, front.Normal.Z)
        local into = (n.Magnitude > 0.1) and -n.Unit or fwd
        local function along(side, a) return CFrame.Angles(0, side * a, 0) * into end
        local now = tick()
        if avoidSide == 0 or now > avoidUntil then
            -- pick the side that leads towards the goal, or else the one with more room, and stay on it
            local function score(side)
                local d = along(side, 1.6)
                return (d.X * fwd.X + d.Z * fwd.Z) * 8 + math.min(free(d, 14), 14) * 0.3
            end
            avoidSide = (score(1) >= score(-1)) and 1 or -1
            avoidUntil = now + 15
        end
        for _, a in ipairs({ 1.6, 1.9, 1.3, 2.3 }) do                -- along the wall, a little away from it if needed
            local dir = along(avoidSide, a)
            if free(dir, 6) >= 5 then
                pcall(function() h:MoveTo(r.Position + dir * 9) end)
                return true
            end
        end
        avoidSide = -avoidSide                                       -- boxed in on this side (a corner): try the other one
        avoidUntil = now + 15
        return false
    end

    -- last resort before a teleport: short hops (about 16 studs) along the way, each one onto real ground (raycast down),
    -- never through a wall and never into the water, with a pause like a lag spike - not one big jump
    local function hopTo(pos, timeout)
        local t0, hopSide = tick(), 1
        while running and tick() - t0 < timeout do
            local r, h = myRoot(), myHum()
            if not (r and h) then return false end
            local flat = Vector3.new(pos.X - r.Position.X, 0, pos.Z - r.Position.Z)
            if flat.Magnitude < 8 then return true end
            local fwd = flat.Unit
            local step = math.min(flat.Magnitude, 16)
            local params = RaycastParams.new()
            params.FilterType = Enum.RaycastFilterType.Exclude
            params.FilterDescendantsInstances = { lp.Character }
            params.IgnoreWater = false
            pcall(function() params.RespectCanCollide = true end)
            local feet = r.Position.Y - (h.HipHeight + r.Size.Y / 2)
            local moved = false
            local angles = { 0, 0.5 * hopSide, -0.5 * hopSide, 1.0 * hopSide, -1.0 * hopSide, 1.57 * hopSide, -1.57 * hopSide }
            for _, a in ipairs(angles) do
                local dir = CFrame.Angles(0, a, 0) * fwd
                local wall = Workspace:Raycast(r.Position, dir * (step + 2), params)
                if not wall then
                    local tx, tz = r.Position.X + dir.X * step, r.Position.Z + dir.Z * step
                    local down = Workspace:Raycast(Vector3.new(tx, feet + 30, tz), Vector3.new(0, -70, 0), params)
                    if down and down.Material ~= Enum.Material.Water and math.abs(down.Position.Y - feet) < 10 then
                        local at = down.Position + Vector3.new(0, h.HipHeight + r.Size.Y / 2 + 0.5, 0)
                        pcall(function()
                            r.AssemblyLinearVelocity = Vector3.zero
                            r.CFrame = CFrame.lookAt(at, at + Vector3.new(dir.X, 0, dir.Z))
                        end)
                        moved = true
                        if a ~= 0 then hopSide = (a > 0) and 1 or -1 end   -- keep going round the same side
                        break
                    end
                end
            end
            if not moved then return false end
            task.wait(0.35 + math.random() * 0.3)
        end
        return dist(pos) < 12
    end
    -- a higher jump while we walk (default jump cannot clear kerbs / crates); restored afterwards
    local jumpSaved = nil
    -- `want` = jump height in studs (default 8: clears a 5-6 stud crate; the old fixed boost was 13 = "jumps way too high").
    -- It is only raised above that when an obstacle probe says the thing in front is taller (see walkTo), never above 11.
    local function jumpBoost(on, want)
        local h = myHum()
        if not h then jumpSaved = nil; return end
        if on then
            want = math.clamp(want or 8, 7, 11)
            if not jumpSaved then jumpSaved = { jp = h.JumpPower, jh = h.JumpHeight } end
            if h.UseJumpPower then
                h.JumpPower = math.max(jumpSaved.jp, math.sqrt(2 * 196.2 * want))
            else
                h.JumpHeight = math.max(jumpSaved.jh, want)
            end
        elseif jumpSaved then
            if h.UseJumpPower then h.JumpPower = jumpSaved.jp else h.JumpHeight = jumpSaved.jh end
            jumpSaved = nil
        end
    end
    local function walkTo(pos, timeout)
        local h = myHum()
        if not h then return false end
        pcall(jumpBoost, true)
        -- far away: follow a path from the start (goes around things) instead of bumping into them
        if dist(pos) > 30 then
            local okp, res = pcall(pathTo, pos, math.min(timeout * 0.7, 45), 2)
            if not (okp and res) and dist(pos) > 14 then pcall(pathTo, pos, 20, 1) end   -- slimmer agent: fits narrower gaps
        end
        local t0, lastMove, lastAvoid, wasAvoiding = tick(), 0, 0, false
        local lastPos, lastAt, stuck = nil, tick(), 0
        while tick() - t0 < timeout and running and not qs.cancel do
            if dist(pos) < 8 then return true end
            if swimming() then rescueWater(pos) end
            if tick() - lastAvoid > 0.4 then
                lastAvoid = tick()
                local okA, avoided = pcall(avoidStep, pos)
                if okA and avoided then
                    -- following an obstacle sideways IS progress: do not re-aim at the goal, do not count it as "stuck"
                    wasAvoiding = true
                    lastMove = tick()
                    stuck = 0
                    local rr = myRoot()
                    if rr then lastPos, lastAt = rr.Position, tick() end
                elseif okA and wasAvoiding then
                    wasAvoiding = false
                    lastMove = 0                                         -- the way is open again: aim at the goal right away
                end
            end
            if tick() - lastMove > 1.5 then lastMove = tick(); pcall(function() h:MoveTo(pos) end) end
            -- no progress for ~1 s while still far: an obstacle
            local r = myRoot()
            if r then
                if not lastPos then lastPos = r.Position end
                if tick() - lastAt >= 1 then
                    if (r.Position - lastPos).Magnitude < 1.2 and dist(pos) > 10 then
                        stuck = stuck + 1
                        local oh = obstacleHeight(pos)
                        if stuck == 1 and oh and oh <= 9.0 then
                            pcall(jumpBoost, true, oh + 2)                     -- just high enough for this obstacle (+2 studs)
                            pcall(function() h.Jump = true end)               -- one normal jump onto the step
                        elseif stuck <= 3 then
                            if not pathTo(pos, 15, ({ 2, 1.5, 1 })[stuck] or 1) then
                                -- no path: sidestep sideways a little, then try again
                                local rr = myRoot()
                                if rr then
                                    local dir = Vector3.new(pos.X - rr.Position.X, 0, pos.Z - rr.Position.Z).Unit
                                    local side = Vector3.new(-dir.Z, 0, dir.X) * ((stuck % 2 == 0) and 8 or -8)
                                    pcall(function() h:MoveTo(rr.Position + side + dir * 4) end)
                                    task.wait(1.2)
                                end
                            end
                        else
                            return false                                      -- really stuck: caller teleports as the last resort
                        end
                    else
                        stuck = 0
                    end
                    lastPos, lastAt = r.Position, tick()
                end
            end
            task.wait(0.2)
        end
        return dist(pos) < 14
    end
    local walkToInner = walkTo
    walkTo = function(pos, timeout)
        local ok, res = pcall(walkToInner, pos, timeout)
        pcall(jumpBoost, false)
        if not (ok and res) and running and dist(pos) >= 14 and not swimming() then
            qlog("walk blocked at " .. string.format("%d studs", dist(pos)) .. " -> short hops")
            local okH, resH = pcall(hopTo, pos, 25)
            if okH and resH then return true end
        end
        return ok and res or false
    end

    -- bait: "Use bait N times" quests need a bait equipped; pick the one the player chose (or the cheapest owned) ---
    local function baitList()
        local out = {}
        local data = getData()
        local bf = data and data:FindFirstChild("Bait")
        if not bf then return out end
        for _, v in ipairs(bf:GetChildren()) do
            local okV, val = pcall(function() return v.Value end)
            local n = okV and tonumber(val) or nil
            if not okV or n == nil or n > 0 then
                local price = 0
                pcall(function() price = require(RS.Info.Bait[v.Name]).Price or 0 end)
                out[#out + 1] = { name = v.Name, count = n or 1, price = price }
            end
        end
        table.sort(out, function(a, b)
            if a.price ~= b.price then return a.price < b.price end
            return a.name < b.name
        end)
        return out
    end
    local function ensureBait()
        local choice = Config.QuestBait
        if choice == "Off" then return end
        if tick() - (qs.lastBait or 0) < 5 then return end
        local data = getData()
        local eq = data and data:FindFirstChild("EquippedBait")
        if not eq then return end
        local list = baitList()
        local pick = nil
        if choice ~= "Auto" then
            for _, b in ipairs(list) do if b.name == choice then pick = b; break end end
        end
        pick = pick or list[1]                     -- chosen bait is used up (or Auto): cheapest bait that is left
        if not pick then qs.status = "no bait in the backpack"; return end
        if eq.Value == pick.name then return end
        qs.lastBait = tick()
        local ev = RS:FindFirstChild("Events")
        local r = ev and ev:FindFirstChild("EquipBait")
        if r then pcall(function() r:InvokeServer(pick.name) end) end
    end

    -- ticket quest state ------------------------------------------------------------------
    local function readTicket()
        local out = { active = false, done = false, cooldown = 0, objs = {} }
        local data = getData()
        if not data then return out end
        local cd = data:FindFirstChild("TicketQuestCooldown")
        if cd then out.cooldown = math.max(0, (tonumber(cd.Value) or 0) - Workspace:GetServerTimeNow()) end
        local quest = data:FindFirstChild("Quest")
        local main = quest and quest:FindFirstChild("Main")
        if not main then return out end
        for _, name in ipairs(QUEST_NAMES) do
            local q = main:FindFirstChild(name)
            if q then
                out.active, out.name, out.done = true, name, true
                local objF = q:FindFirstChild("Objective")
                local n = 1
                while objF do
                    local ov = objF:FindFirstChild(tostring(n))
                    if not ov then break end
                    local parts = string.split(tostring(ov.Value), ",")
                    local o = { desc = tostring(ov.Value), amount = 1, kind = "?", target = "" }
                    for i = 2, #parts do
                        if tonumber(parts[i]) and parts[i + 1] and string.match(parts[i + 1], "^%a+$") then
                            o.desc = table.concat(parts, ",", 1, i - 1)
                            o.amount = tonumber(parts[i])
                            o.kind = parts[i + 1]
                            o.target = table.concat(parts, ",", i + 2)
                            break
                        end
                    end
                    local pv = q:FindFirstChild(tostring(n))
                    o.progress = pv and tonumber(pv.Value) or 0
                    if o.progress < o.amount then out.done = false end
                    out.objs[#out.objs + 1] = o
                    n = n + 1
                end
                if #out.objs == 0 then out.done = false end
                break
            end
        end
        return out
    end

    -- dialogue --------------------------------------------------------------------------------
    task.spawn(function()
        local ev = RS:WaitForChild("Events", 30)
        local sd = ev and ev:WaitForChild("StartDialogue", 30)
        local vu = ev and ev:WaitForChild("VisibleUI", 30)
        if sd then
            conns[#conns + 1] = sd.OnClientEvent:Connect(function(npcName, model, body, args)
                qs.dlg = { npc = npcName, model = model, opts = (type(body) == "table" and body[2]) or {}, args = args,
                           text = (type(body) == "table" and type(body[1]) == "string") and body[1] or nil }
                qs.dlgAt = tick()
            end)
        end
        if vu then
            conns[#conns + 1] = vu.OnClientEvent:Connect(function(name, loc)
                qs.ui, qs.uiAt = name, tick()
                if name == "BoatShop" then qs.shop = { loc = loc, at = tick() } end
            end)
        end
    end)

    local function ticketChooser(opts)
        local want = (Config.TicketDifficulty == "Hard") and "HardAcceptQuest" or "EasyAcceptQuest"
        for i, o in ipairs(opts) do if o[2] == want then return i, o[2] end end
        for i, o in ipairs(opts) do if o[2] == "Quest" then return i, o[2] end end
        return nil
    end

    -- Ways to trigger an NPC's ProximityPrompt. fireproximityprompt is an executor function (missing or a do-nothing stub
    -- on weak executors); InputHoldBegin/End are plain Roblox calls (the game's own prompt script uses them) and the key
    -- press is the same as a player holding E. Attempts rotate through them; the one that opens the dialogue is remembered.
    local TALK_METHODS = {
        { "fireproximityprompt", function(prompt)
            if not fireproximityprompt then return false end
            return (pcall(fireproximityprompt, prompt))
        end },
        { "InputHoldBegin/End", function(prompt)
            return (pcall(function()
                prompt:InputHoldBegin()
                task.wait((prompt.HoldDuration or 0) + 0.1)
                prompt:InputHoldEnd()
            end))
        end },
        { "key press", function(prompt)
            return (pcall(function()
                local vim = game:GetService("VirtualInputManager")
                local key = prompt.KeyboardKeyCode
                if not key or key == Enum.KeyCode.Unknown then key = Enum.KeyCode.E end
                vim:SendKeyEvent(true, key, false, game)
                task.wait((prompt.HoldDuration or 0) + 0.15)
                vim:SendKeyEvent(false, key, false, game)
            end))
        end },
    }
    local talkM = (TALK_METHODS[tonumber(Config.TalkMethod) or 0] and tonumber(Config.TalkMethod)) or 1
    local function talk(model, npcName, chooser, maxSteps, anyUI)
        local prompt = nil
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("ProximityPrompt") then prompt = d; break end
        end
        if not prompt then return false, "NPC has no ProximityPrompt" end
        pcall(function() prompt.RequiresLineOfSight = false end)
        local function promptPos()
            local par, p = prompt.Parent, nil
            pcall(function()
                if par:IsA("BasePart") then p = par.Position elseif par:IsA("Attachment") then p = par.WorldPosition end
            end)
            return p or (model:IsA("Model") and model:GetPivot().Position) or nil
        end
        local opened, uiOnly = false, false
        for attempt = 1, 3 do
            -- get inside the prompt's own activation distance first (the NPC position used by the caller can be several studs off)
            local pp = promptPos()
            local mad = 10
            pcall(function() mad = prompt.MaxActivationDistance end)
            if pp and dist(pp) > math.max(3, mad - 3) then
                local r = myRoot()
                local away = r and Vector3.new(r.Position.X - pp.X, 0, r.Position.Z - pp.Z) or Vector3.new(1, 0, 0)
                away = (away.Magnitude > 0.1) and away.Unit or Vector3.new(1, 0, 0)
                local near = pp + away * 3
                if attempt == 1 then walkTo(near, 20) end
                if dist(pp) > math.max(3, mad - 3) then tp(near); task.wait(0.8) end
            end
            local t0 = qs.dlgAt
            local u0 = qs.uiAt or 0
            local m = talkM
            pcall(TALK_METHODS[m][2], prompt)
            if waitFor(function()
                return (qs.dlgAt > t0 and qs.dlg and (npcName == nil or qs.dlg.npc == npcName)) or (anyUI and (qs.uiAt or 0) > u0)
            end, 4) then
                opened = true
                if not (qs.dlgAt > t0) then uiOnly = true end
                if Config.TalkMethod ~= m then
                    Config.TalkMethod = m                      -- remembered for the next run
                    pcall(markDirty)
                    qlog("talk: '" .. TALK_METHODS[m][1] .. "' opens the dialogue")
                end
                break
            end
            qlog("talk attempt " .. attempt .. " failed with '" .. TALK_METHODS[m][1] .. "' (dist " .. string.format("%.1f", pp and dist(pp) or -1) .. ", range " .. tostring(mad) .. ")")
            talkM = m % #TALK_METHODS + 1                      -- the next attempt uses the next method
        end
        if not opened then return false, "no dialogue opened (too far away?)" end
        if uiOnly then return true, "ui opened: " .. tostring(qs.ui) end
        uiPause(1.3)                                   -- read the dialogue before clicking
        local ev = RS:FindFirstChild("Events") and RS.Events:FindFirstChild("ChooseDialogueOption")
        if not ev then return false, "ChooseDialogueOption missing" end
        for _ = 1, maxSteps or 4 do
            local d = qs.dlg
            local idx, typ = chooser(d.opts)
            if not idx then return true, "dialogue finished" end
            local before = qs.dlgAt
            uiPause()
            pcall(function() ev:FireServer(npcName or d.npc, idx, typ, d.args) end)
            if typ == "BoatShop" then return true, "boat shop" end
            if not waitFor(function() return qs.dlgAt > before end, 3) then return true, "no follow-up" end
        end
        return true, "ok"
    end

    local function ticketNpc()
        local npcF = Workspace:FindFirstChild("NPC")
        local fnF = npcF and npcF:FindFirstChild("Function")
        return fnF and fnF:FindFirstChild(TICKET_NPC)
    end
    local function npcPos(model)
        local r = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart)
        return r and r.Position
    end

    -- boat --------------------------------------------------------------------------------------
    local function sail(spawnNpc, route, exitPos, landing)
        local npcF = Workspace:FindFirstChild("NPC")
        local sbF = npcF and npcF:FindFirstChild("SpawnBoat")
        local npc = sbF and sbF:FindFirstChild(spawnNpc)
        local pos = npcPos(npc)
        if not pos then return false, "boat NPC not found" end
        if dist(pos) > 8 and not walkTo(pos + Vector3.new(3, 0, 3), 45) then
            qlog(string.format("boat: could not walk to the boat NPC (%d studs away, swimming=%s) -> teleport next to it", dist(pos), tostring(swimming())))
            tp(pos + Vector3.new(3, 0, 3)); task.wait(1)
        end
        qs.shop = nil
        local ok, why = talk(npc, "SpawnBoat", function(opts)
            for i, o in ipairs(opts) do if o[2] == "BoatShop" then return i, o[2] end end
            return nil
        end, 1)
        if not ok then return false, why end
        if not waitFor(function() return qs.shop ~= nil end, 5) then return false, "boat shop did not open" end
        local Events = RS:FindFirstChild("Events")
        -- the shop UI fires ReplicatedStorage.Remotes.BoatShop.Spawn(boatName, "LocationN")  (not Events.Spawn)
        local remF = RS:FindFirstChild("Remotes")
        local shopF = remF and remF:FindFirstChild("BoatShop")
        local spawnR = (shopF and shopF:FindFirstChild("Spawn")) or (Events and Events:FindFirstChild("Spawn"))
        if not spawnR then return false, "Spawn remote missing" end
        local loc = qs.shop.loc
        uiPause()
        local boatName = Config.BoatName
        if boatName == nil or boatName == "" or boatName == "Auto" or boatName == "White Heaven Kunfish" then   -- the old saved default counts as Auto
            local best, bestSpeed = nil, -1
            pcall(function()
                local data = getData()
                local owned = data and data:FindFirstChild("Boats")
                local info = RS:FindFirstChild("Info") and RS.Info:FindFirstChild("Boats")
                if not (owned and info) then return end
                for _, v in ipairs(owned:GetChildren()) do
                    if v.Value == true and info:FindFirstChild(v.Name) then
                        local m = require(info[v.Name])
                        local sp = tonumber(tostring(m.Description or ""):match("(%d+)%s*[Ss]peed")) or 0
                        if sp > bestSpeed then best, bestSpeed = v.Name, sp end
                    end
                end
            end)
            boatName = best or "Boat"
            qlog("boat: using " .. boatName .. " (" .. bestSpeed .. " speed)")
        end
        Config.BoatNameUsed = boatName
        pcall(function() spawnR:FireServer(boatName, loc) end)
        task.delay(1.2, closeShop)
        local boat = nil
        if not waitFor(function()
            local bF = Workspace:FindFirstChild("Boat")
            local lF = bF and bF:FindFirstChild(tostring(loc))
            boat = lF and lF:FindFirstChild("Boat_" .. lp.UserId)
            return boat ~= nil and boat:FindFirstChild("VehicleSeat") ~= nil and boat:FindFirstChild("Root") ~= nil
        end, 12) then return false, "boat did not appear (is '" .. tostring(Config.BoatNameUsed) .. "' your boat?)" end
        local seat, h = boat.VehicleSeat, myHum()
        if not h then return false, "no humanoid" end
        task.wait(1.0)   -- the boat drops onto the water first: let it settle before sitting
        waitFor(function()                                    -- ... wait until it stops moving
            local v = 99
            pcall(function() v = seat.AssemblyLinearVelocity.Magnitude end)
            return v < 4
        end, 3)
        local seated = false
        for try = 1, 7 do
            do   -- diagnostics for every attempt (why can the character not sit?)
                local rr = myRoot()
                local occ, dis, vel = "?", "?", 0
                pcall(function() occ = tostring(seat.Occupant) end)
                pcall(function() dis = tostring(seat.Disabled) end)
                pcall(function() vel = seat.AssemblyLinearVelocity.Magnitude end)
                qlog(string.format("sit attempt %d: seat (%d,%.1f,%d) vel %.1f occupant %s disabled %s | me %s from the seat, state %s",
                    try, seat.Position.X, seat.Position.Y, seat.Position.Z, vel, occ, dis,
                    rr and string.format("%d studs", (rr.Position - seat.Position).Magnitude) or "?", tostring(h:GetState())))
            end
            if try > 1 then task.wait(0.6 * try) end            -- big boats (Omega) take longer to settle on the water
            local r = myRoot()
            if try >= 3 then                                    -- stuck in Freefall / Swimming: reset the humanoid state first
                pcall(function() h.Sit = false; h:ChangeState(Enum.HumanoidStateType.Running) end)
                task.wait(0.3)
            end
            if r then
                pcall(function() r.AssemblyLinearVelocity = Vector3.zero end)
                r.CFrame = seat.CFrame * CFrame.new(0, (try >= 4) and 3.5 or 2, 0)
            end
            pcall(function() seat:Sit(h) end)
            if waitFor(function() return h.SeatPart == seat end, 2) then
                task.wait(0.8)
                if h.SeatPart == seat then seated = true; break end   -- still sitting after a moment = really seated
            end
        end
        if not seated then leaveBoat(seat); return false, "could not sit in the boat" end
        local root = boat.Root
        local bv = root:WaitForChild("BodyVelocity", 6)
        local ao = root:WaitForChild("AlignOrientation", 6)
        if not (bv and ao) then leaveBoat(seat); return false, "boat has no BodyVelocity/AlignOrientation" end
        local cfg = boat:FindFirstChild("Configuration")
        local ms = cfg and cfg:FindFirstChild("MaxSpeed")
        local speed = ((ms and ms.Value) or 60) * 0.95
        local wp, state = 1, nil
        qs.sailing = true
        local jumpConn
        pcall(function()
            jumpConn = game:GetService("UserInputService").JumpRequest:Connect(function()
                qlog("JumpRequest while on the boat (something made the character jump)")
            end)
        end)
        do
            qs.boatNote = "planning the route"
            local okR, newRoute, note = pcall(chooseRoute, seat.Position, route, landing)
            if okR and newRoute and #newRoute > 0 then route = newRoute end
            qlog("boat route: " .. tostring(okR and note or newRoute) .. "  (start " .. string.format("%d,%d,%d", seat.Position.X, seat.Position.Y, seat.Position.Z) .. ", " .. #route .. " waypoints)")
            qs.boatNote = ""
        end
        local conn
        local unseatAt, resit, backing, braking = nil, 0, false, false
        -- diagnostics for "the boat object was removed": the waypoints, where / how fast the boat was at the last frame,
        -- how long the trip had run, and whether the game's AFK flag changed in the meantime
        local tSail, lastPos, lastVel = tick(), seat.Position, 0
        do
            local wps = {}
            for i, q in ipairs(route) do wps[#wps + 1] = i .. "=(" .. math.floor(q.X) .. "," .. math.floor(q.Y) .. ")" end
            qlog("route points: " .. table.concat(wps, " "))
        end
        local afkConn
        pcall(function()
            local dv = getData()
            local av = dv and dv:FindFirstChild("AFK")
            if av then
                qlog("game AFK flag at trip start: " .. tostring(av.Value))
                afkConn = av.Changed:Connect(function(v) qlog(string.format("game AFK flag -> %s (%.1fs into the trip)", tostring(v), tick() - tSail)) end)
            end
        end)
        -- the game's own boat script rewrites BodyVelocity / AlignOrientation every Heartbeat from the (zero) throttle,
        -- which cancelled ours. PreSimulation runs right BEFORE physics, i.e. after theirs, so our values are the ones used.
        conn = (RunService.PreSimulation or RunService.Stepped):Connect(function()
            if not running or not seat.Parent then
                if running then
                    local sp0 = lastPos
                    pcall(function() sp0 = seat.Position end)
                    qlog(string.format("boat object was removed (seat.Parent = nil) at waypoint %d; boat parent: %s; %.1fs into the trip; last pos %d,%d,%d; speed %d; I was seated: %s",
                        wp, tostring(boat.Parent), tick() - tSail, sp0.X, sp0.Y, sp0.Z, lastVel, tostring(h.SeatPart == seat)))
                end
                state = state or "left the boat"; conn:Disconnect(); return
            end
            if h.SeatPart ~= seat then
                -- The game's boat module (ClientModule.Boat) stops its drive loop for good the first frame the seat's
                -- Occupant is not us and reports the exit to the server (EnteredBoat:FireServer), which removes the boat.
                -- Sitting down again cannot bring the drive loop back, so this is the end of the trip.
                local hs = ""
                pcall(function() hs = tostring(h:GetState()) .. " hp=" .. math.floor(h.Health) .. " occ=" .. tostring(seat.Occupant) .. " v=" .. math.floor(seat.AssemblyLinearVelocity.Magnitude) .. " gameAFK=" .. tostring(tick() - (gameAfkTime or -100) < 5) end)
                qlog("unseated at waypoint " .. wp .. " (" .. hs .. ") -> trip over")
                state = state or "unseated (the boat stops driving once you leave the seat)"
                conn:Disconnect()
                return
            end
            unseatAt = nil
            local p, target = seat.Position, route[wp]
            local d = Vector3.new(target.X - p.X, 0, target.Y - p.Z)
            if d.Magnitude < ((wp >= #route and landing) and 40 or (wp >= #route - 2 and 50 or 70)) then   -- the landing point: get closer to the shore
                wp = wp + 1
                if wp > #route then state = "arrived"; bv.Velocity = Vector3.zero; conn:Disconnect(); return end
                target = route[wp]
                d = Vector3.new(target.X - p.X, 0, target.Y - p.Z)
            end
            -- steering is NOT done here any more: writing BodyVelocity / AlignOrientation ourselves only made the boat
            -- go straight ahead. The game's own boat script steers from seat.SteerFloat (see the render-step below).
        end)
        -- also hold the throttle the way a player does (W), so the game's own boat script wants to move forward too
        pcall(function()
            RunService:BindToRenderStep("PPY_BoatThrottle", Enum.RenderPriority.Last.Value + 10, function()
                pcall(function()
                    local target = route[math.min(wp, #route)]
                    local p, look = seat.Position, seat.CFrame.LookVector
                    local want = math.atan2(-(target.X - p.X), -(target.Y - p.Z))   -- yaw whose look vector points at the waypoint (Vector2: .Y is z)
                    local cur = math.atan2(-look.X, -look.Z)
                    local err = (want - cur + math.pi) % (2 * math.pi) - math.pi     -- -pi..pi, > 0 = waypoint is to the left
                    -- the game turns RIGHT for a positive steer (yaw -= steer * ...), so steer = -err
                    local steer = math.clamp(-err * 1.6, -1, 1)
                    if math.abs(err) < 0.04 then steer = 0 end
                    -- whiskers: land 70 studs ahead on one side -> lean away; land dead ahead -> slow down
                    local fl = Vector3.new(look.X, 0, look.Z).Unit
                    local function probe(a, dist)
                        local c, sn = math.cos(a), math.sin(a)
                        local dx, dz = fl.X * c - fl.Z * sn, fl.X * sn + fl.Z * c
                        return isWater(p.X + dx * dist, p.Z + dz * dist)
                    end
                    local slow = false
                    if not probe(0, 90) then slow = true end
                    local wr, wl = probe(0.5, 70), probe(-0.5, 70)   -- +0.5 rad turns toward +X = right when facing -Z
                    if not wl and wr then steer = math.max(steer, 0.7) elseif not wr and wl then steer = math.min(steer, -0.7) elseif not wl and not wr then slow = true end
                    seat.SteerFloat = steer
                    seat.ThrottleFloat = (slow or math.abs(err) > 1.0) and 0.5 or 1
                    -- speed governor: a boat doing 125 cannot make a 90 degree turn between waypoints 50 studs apart (it swings
                    -- wide into the coast, steer flips +-1 every second). Near the end of the route and before sharp turns the
                    -- throttle is driven by the MEASURED speed (does not depend on partial throttle being supported).
                    -- vel = speed ALONG the bow (signed): a boat that has stopped and starts rolling backwards must never be
                    -- braked again (the magnitude alone made it reverse for good)
                    local vel = 0
                    pcall(function() vel = seat.AssemblyLinearVelocity:Dot(look) end)
                    local dw = math.sqrt((target.X - p.X) ^ 2 + (target.Y - p.Z) ^ 2)
                    local cap = nil
                    if wp >= #route - 2 and dw < 300 then cap = 55 end                    -- the last three waypoints sit next to the shore
                    if dw < 170 and math.abs(err) > 0.5 then cap = math.min(cap or 999, 70) end
                    if wp >= #route and dw < 110 then cap = 40 end
                    if cap then
                        if vel > cap * 1.6 then seat.ThrottleFloat = -0.5      -- short reverse thrust brakes (only while still going fast forward)
                        elseif vel > cap then seat.ThrottleFloat = 0            -- coast
                        else seat.ThrottleFloat = 1 end
                    end
                    if backing then seat.SteerFloat = 0; seat.ThrottleFloat = -1 end
                    if braking then seat.SteerFloat = 0; seat.ThrottleFloat = (vel > 15) and -0.6 or 0 end
                end)
            end)
        end)
        local t0, lastP, lastT = tick(), seat.Position, tick()
        local slowSecs = 0
        local firstCheck = true
        local replans = 0
        while state == nil and running and tick() - t0 < 300 do
            task.wait(1)
            if qs.cancel then state = "cancelled"; break end
            local sp = (seat.Position - lastP).Magnitude / math.max(0.1, tick() - lastT)
            qs.boatNote = string.format("sailing %d/%d  %.0f studs/s", wp, #route, sp)
            lastPos, lastVel = seat.Position, sp
            -- aground near the destination (the boat stops moving at the shore): that IS the landing - get out and walk,
            -- do not wait for the game to remove the boat
            if sp < 15 and not backing and tick() - tSail > 6 then
                slowSecs = slowSecs + 1
            else
                slowSecs = 0
            end
            if slowSecs >= 3 then
                local fin = route[#route]
                local dFin = math.sqrt((fin.X - seat.Position.X) ^ 2 + (fin.Y - seat.Position.Z) ^ 2)
                local landNear = false
                for k = 0, 7 do
                    local a = k / 8 * math.pi * 2
                    local okW, w = pcall(isWater, seat.Position.X + math.cos(a) * 45, seat.Position.Z + math.sin(a) * 45)
                    if okW and w == false then landNear = true; break end
                end
                if landNear and (dFin < 300 or (exitPos and dist(exitPos) < 350)) then
                    qlog(string.format("boat aground at the shore (%d studs from the end point) -> getting out and walking", dFin))
                    state = "grounded"
                end
                slowSecs = 0
            end
            if tick() - tSail < 25 then
                local tg = route[math.min(wp, #route)]
                qlog(string.format("  t+%.0fs wp %d/%d pos %d,%d,%d speed %d, %d studs to the waypoint, throttle %s steer %s",
                    tick() - tSail, wp, #route, seat.Position.X, seat.Position.Y, seat.Position.Z, sp,
                    math.sqrt((tg.X - seat.Position.X) ^ 2 + (tg.Y - seat.Position.Z) ^ 2), tostring(seat.Throttle), tostring(seat.Steer)))
            end
            -- console trace every 2 s, so a failed trip can be diagnosed from the executor console
            qs.boatTick = (qs.boatTick or 0) + 1
            if qs.boatTick % 2 == 0 then
                local v = 0
                pcall(function() v = seat.AssemblyLinearVelocity.Magnitude end)
                print(string.format("[PPINGYYY boat] wp %d/%d pos(%d,%d,%d) speed %d throttle %s bv %d anchored %s owner %s",
                    wp, #route, seat.Position.X, seat.Position.Y, seat.Position.Z, v, tostring(seat.ThrottleFloat),
                    bv.Velocity.Magnitude, tostring(root.Anchored), tostring(pcall(function() return root:GetNetworkOwner() end))))
            end
            if tick() - lastT >= (firstCheck and 12 or 8) then
                if (seat.Position - lastP).Magnitude < 12 then
                    if replans < 2 then
                        -- aground / blocked: reverse a moment, then plan a new way from where we are
                        replans = replans + 1
                        qlog("boat stuck at " .. string.format("%d,%d,%d", seat.Position.X, seat.Position.Y, seat.Position.Z) .. " -> backing off + replanning #" .. replans)
                        backing = true
                        task.wait(2.5)
                        backing = false
                        local okR, newRoute, note = pcall(chooseRoute, seat.Position, { route[#route] })
                        if okR and newRoute and #newRoute > 0 then route = newRoute; wp = 1 end
                        qlog("replan: " .. tostring(okR and note or newRoute) .. " (" .. #route .. " waypoints)")
                    else
                        state = "stuck (boat not moving)"
                    end
                end
                firstCheck = false
                lastP, lastT = seat.Position, tick()
            end
        end
        qs.sailing = false
        pcall(function() if jumpConn then jumpConn:Disconnect() end end)
        pcall(function() if afkConn then afkConn:Disconnect() end end)
                qlog("boat trip ended: " .. tostring(state or (running and "timeout" or "stopped")) .. "  waypoint " .. wp .. "/" .. #route)
        qflush(true)
        -- stop the boat before getting out (it used to keep driving at 100+ studs/s and throw us into the water)
        if (state == "arrived" or state == "grounded") and seat.Parent then
            qs.boatNote = "stopping the boat"
            braking = true
            waitFor(function()
                local v = 99
                pcall(function() v = seat.AssemblyLinearVelocity:Dot(seat.CFrame.LookVector) end)
                return v < 12 or not seat.Parent or h.SeatPart ~= seat
            end, 5)
            braking = false
        end
        pcall(function() RunService:UnbindFromRenderStep("PPY_BoatThrottle") end)
        pcall(function() seat.ThrottleFloat = 0; seat.SteerFloat = 0 end)
        pcall(function() conn:Disconnect() end)
        qs.boatNote = ""
        qs.boatNote = "leaving the boat"
        leaveBoat(seat)
        qs.boatNote = ""
        task.wait(0.5)
        if swimming() then rescueWater(exitPos) end
        if state ~= "arrived" and state ~= "grounded" then return false, "boat trip " .. tostring(state or "timed out") end
        if exitPos then
            -- walk the rest (swim to the shore first when needed); two tries, a teleport only when both failed
            for attempt = 1, 2 do
                if dist(exitPos) < 14 then break end
                if swimming() then rescueWater(exitPos) end
                walkTo(exitPos, math.max(40, dist(exitPos) / 7 + 25))
            end
            if dist(exitPos) > 25 then
                qlog("could not walk the last " .. math.floor(dist(exitPos)) .. " studs -> teleport (last resort)")
                tp(exitPos)
            end
        end
        return true, state
    end

    -- (boat trips are retried once below when the boat would not appear / could not be boarded)
    -- safety net around sail(): whatever goes wrong inside, the throttle callback is unbound and the sailing flag is
    -- cleared (a stale PPY_BoatThrottle binding would make the next trip silently steer the old boat)
    ui.rawSail = sail
    sail = function(...)
        local res = table.pack(pcall(ui.rawSail, ...))
        qs.sailing = false
        if not res[1] then
            pcall(function() RunService:UnbindFromRenderStep("PPY_BoatThrottle") end)
            qlog("sail() error: " .. tostring(res[2]))
            return false, "boat error: " .. tostring(res[2])
        end
        return res[2], res[3]
    end

    -- one more try with a fresh boat when it could not be boarded (a teleport across the sea is the last resort, not the first)
    local function sailRetry(...)
        local args = table.pack(...)
        local ok, why = sail(table.unpack(args, 1, args.n))
        if not ok and running and not qs.cancel and (tostring(why):find("could not sit", 1, true) or tostring(why):find("did not appear", 1, true)) then
            qlog("boat: '" .. tostring(why) .. "' - trying once more with a new boat")
            task.wait(4)
            ok, why = sail(table.unpack(args, 1, args.n))
        end
        return ok, why
    end
    -- travel (teleport or boat, with teleport as the fallback) -----------------------------------
    -- go on foot when the way there is dry land (checked along the straight line), teleport only when that is not
    -- possible or failed. A walk is slower but does not look like a jump across the map.
    -- is there a walkable route to `pos`? (the navmesh says so, no walking yet)
    local function pathExists(pos)
        local r = myRoot()
        if not r then return false end
        local ok, res = pcall(function()
            local path = game:GetService("PathfindingService"):CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 6 })
            path:ComputeAsync(r.Position, pos)
            return path.Status == Enum.PathStatus.Success
        end)
        return ok and res == true
    end
    local function gentleGo(pos, look)
        local d = dist(pos)
        if d < 14 then return end
        local r = myRoot()
        local dry = d <= 450 and r ~= nil
        if dry and pathExists(pos) then
            -- the navmesh knows a way: no need to guess from the straight line
        elseif dry then
            for k = 1, 9 do
                local f = k / 10
                local okW, w = pcall(isWater, r.Position.X + (pos.X - r.Position.X) * f, r.Position.Z + (pos.Z - r.Position.Z) * f)
                if okW and w then dry = false; break end
            end
        end
        if dry then
            qlog(string.format("walking the last %d studs instead of teleporting", d))
            if swimming() then rescueWater(pos) end
            walkTo(pos, d / 7 + 25)
            if dist(pos) >= 14 and swimming() then rescueWater(pos); walkTo(pos, 30) end
        end
        if dist(pos) >= 14 then tp(pos, look); task.wait(1) end
    end
    -- open water as close to `target` as possible (rings around it, nearest ring first; on a ring the spot closest to the
    -- boat wins). Needs a real water hit with 18 studs of clear water around it; where the terrain is not loaded
    -- (no hit at all) the answer is "unknown", never "water", so it returns nil and the fixed route end is used.
    local function findLanding(target)
        pcall(isWater, 0, 0)                      -- makes sure seaParams exists
        if not seaParams then return nil end
        local lvl = seaLevel()
        local function strictWater(x, z)
            local hit = Workspace:Raycast(Vector3.new(x, lvl + 150, z), Vector3.new(0, -400, 0), seaParams)
            return hit ~= nil and (hit.Material == Enum.Material.Water or hit.Position.Y <= lvl + 1.5)
        end
        local r0 = myRoot()
        for _, rad in ipairs({ 40, 60, 85, 115, 150, 200, 260 }) do
            local best, bd = nil, math.huge
            for k = 0, 23 do
                local a = k / 24 * math.pi * 2
                local x, z = target.X + math.cos(a) * rad, target.Z + math.sin(a) * rad
                if strictWater(x, z) and strictWater(x + 18, z) and strictWater(x - 18, z) and strictWater(x, z + 18) and strictWater(x, z - 18) then
                    local d = r0 and ((x - r0.Position.X) ^ 2 + (z - r0.Position.Z) ^ 2) or 0
                    if d < bd then best, bd = Vector2.new(x, z), d end
                end
            end
            if best then return best, rad end
        end
        return nil
    end
    -- the closest boat-summon NPC (every island has its own, in a different place)
    local function nearestBoatNpc()
        local npcF = Workspace:FindFirstChild("NPC")
        local sbF = npcF and npcF:FindFirstChild("SpawnBoat")
        if not sbF then return nil end
        local best, bd = nil, math.huge
        for _, m in ipairs(sbF:GetChildren()) do
            local mp = npcPos(m)
            local d = mp and dist(mp) or math.huge
            if d < bd then best, bd = m.Name, d end
        end
        return best, bd
    end
    local DEFAULT_FARM = Vector3.new(1362, 9, 268)
    -- are we away from the farm spot? Far away (> 80): yes. Close but not on it (16..80) and the way is walkable: yes, go to
    -- the exact spot (the saved spot has a facing and a cast position); checked at most once every 90 s so that a spot we
    -- cannot quite reach does not make us walk back and forth.
    local function needFarmMove()
        local d = dist(farmPos())
        if d > 80 then return true end
        if d <= 16 then return false end
        if tick() - (qs.lastFine or 0) < 90 then return false end
        qs.lastFine = tick()
        return pathExists(farmPos())
    end
    local function goFarm()
        local fp = farmPos()
        local d0 = dist(fp)
        if d0 <= 16 then return end
        if d0 < 80 and not pathExists(fp) then return end
        local walkable = dist(fp) <= 450 and pathExists(fp)       -- close and on the same land: walk, no boat
        if walkable then qlog(string.format("farm spot is %d studs away and walkable - no boat", dist(fp))) end
        if Config.QuestTravel == "Boat" and not walkable then
            local near, nd = nearestBoatNpc()
            local ok, why = nil, nil
            if near == "Chu Xin 1" and (fp - DEFAULT_FARM).Magnitude < 250 then
                ok, why = sailRetry("Chu Xin 1", ROUTE_TO_FARM, fp)                 -- the known route quest island -> battlefield
            elseif near and nd < 700 then
                local landing = nil
                pcall(function() landing = findLanding(fp) end)
                qlog(string.format("boat: %s -> farm spot (%d,%d), boat NPC '%s' %d studs away", farmKindNow(), fp.X, fp.Z, near, nd))
                ok, why = sailRetry(near, { Vector2.new(fp.X, fp.Z) }, fp, landing)
            end
            if ok ~= nil then
                qs.boatResult = (ok and "OK" or "FAILED: ") .. (ok and "" or tostring(why)) .. " (to farm)"
                if ok then task.wait(0.3); faceSea(); respot(true); return end
                qs.status = "boat failed (" .. tostring(why) .. ") -> walking / teleport"
            end
        end
        gentleGo(fp, farmLook())
        task.wait(0.3)
        faceSea()
        respot(true)
    end
    local function goNpc()
        local npc = ticketNpc()
        local np = npcPos(npc)
        if not np then qs.status = "Ticket NPC not found"; return false end
        respot(false)
        if dist(np) < 12 then return true end
        local near, nd = nil, math.huge
        local walkable = dist(np) <= 450 and pathExists(np + Vector3.new(5, 0, 5))
        if walkable then qlog(string.format("quest NPC is %d studs away and walkable - no boat", dist(np))) end
        if Config.QuestTravel == "Boat" and not walkable then near, nd = nearestBoatNpc() end
        if near and nd < 700 then
            local landing, lrad = nil, nil
            pcall(function() landing, lrad = findLanding(np) end)
            qlog(landing and string.format("landing spot %d,%d (%d studs from the NPC)", landing.X, landing.Y, lrad) or "no landing spot found (terrain not loaded?) - using the fixed route end")
            -- known route from the battlefield island; any other island: planned (A*) route to the landing spot
            local route = (near == "Chu Xin 9") and ROUTE_TO_QUEST or { Vector2.new(np.X, np.Z) }
            local ok, why = sailRetry(near, route, np + Vector3.new(5, 0, 5), landing)
            qs.boatResult = (ok and "OK" or "FAILED: ") .. (ok and "" or tostring(why)) .. " (to NPC)"
            if ok and dist(np) < 14 then return true end
            if not ok then qs.status = "boat failed (" .. tostring(why) .. ") -> teleport" end
        end
        gentleGo(np + Vector3.new(5, 0, 5))
        task.wait(0.5)
        return true
    end

    -- auto bait: when the equipped bait runs out, go to the nearest bait seller ("Ba Chang" in Workspace.NPC.BuyBait),
    -- buy up to BuyBaitAmount (max 400), equip it and go back where we were --------------------------------
    local BAIT_SELLERS = {
        Vector3.new(-132.2, 8.7, -41.6), Vector3.new(-1217.5, 7.5, -166.1), Vector3.new(1445.8, 10.7, -1389.2),
        Vector3.new(-2643.2, 6.9, -1257.2), Vector3.new(-2403.8, 10.0, -254.9), Vector3.new(-1381.6, 9.2, -1490.6),
        Vector3.new(-28.1, 9.2, -1329.6), Vector3.new(106.2, 7.2, 1180.8), Vector3.new(-1242.7, 8.2, 1209.8),
        Vector3.new(1285.0, 8.2, 1516.8), Vector3.new(1521.9, 47.5, -66.4),
    }
    local BAIT_MAX = 400
    local function baitCount(name)
        local data = getData()
        local bf = data and data:FindFirstChild("Bait")
        local v = bf and name and bf:FindFirstChild(name)
        if not v then return 0 end
        local ok, n = pcall(function() return v.Value end)
        return ok and tonumber(n) or 0
    end
    local function equippedBait()
        local data = getData()
        local eq = data and data:FindFirstChild("EquippedBait")
        local ok, v = pcall(function() return eq and eq.Value end)
        return (ok and v) and tostring(v) or ""
    end
    local function buyableBaits()
        local out = {}
        local f = RS:FindFirstChild("Info") and RS.Info:FindFirstChild("Bait")
        if f then
            for _, m in ipairs(f:GetChildren()) do
                local price = 0
                pcall(function() price = require(m).Price or 0 end)
                if price > 0 then out[#out + 1] = { name = m.Name, price = price } end
            end
        end
        table.sort(out, function(a, b) if a.price ~= b.price then return a.price < b.price end return a.name < b.name end)
        return out
    end
    local function wantedBait()
        local c = Config.BuyBaitName
        local list = buyableBaits()
        if c ~= "Auto" then return c end
        local last = qs.lastBaitName
        for _, b in ipairs(list) do if b.name == last then return last end end
        for _, b in ipairs(list) do if b.name == equippedBait() then return b.name end end
        return list[1] and list[1].name
    end
    -- true when the bait we fish with is used up (never true while the player data is not loaded yet)
    local function needBait()
        local data = getData()
        if not (data and data:FindFirstChild("Bait") and data:FindFirstChild("EquippedBait")) then return false end
        local eq = equippedBait()
        local below = math.clamp(tonumber(Config.BuyBaitBelow) or 0, 0, BAIT_MAX - 1)
        if eq ~= "" and eq ~= "None" and data.Bait:FindFirstChild(eq) then
            qs.lastBaitName = eq
            return baitCount(eq) <= below
        end
        local total = 0
        for _, v in ipairs(data.Bait:GetChildren()) do total = total + baitCount(v.Name) end
        return total <= below
    end
    local function findSeller()
        local r = myRoot()
        local best, bd = nil, math.huge
        for _, p in ipairs(BAIT_SELLERS) do
            local d = r and (r.Position - p).Magnitude or 0
            if d < bd then best, bd = p, d end
        end
        local model = nil
        local npcF = Workspace:FindFirstChild("NPC")
        local bf = npcF and npcF:FindFirstChild("BuyBait")
        if bf and best then
            local md = 80
            for _, m in ipairs(bf:GetChildren()) do
                local mp = npcPos(m)
                if mp and (mp - best).Magnitude < md then model, md = m, (mp - best).Magnitude end
            end
        end
        return model, (model and npcPos(model)) or best
    end
    local function goTo(pos, label)
        local d = dist(pos)
        if d < 8 then return end
        if Config.BaitTravel == "Walk" and d <= 700 then
            if walkTo(pos, d / 8 + 25) then return end
            qlog("bait: walking to " .. label .. " failed -> teleport")
        end
        tp(pos)
        task.wait(1.2)
    end
    -- press the dialogue's own close / bye button (the game's UI code then ends the dialogue properly)
    local function pressDialogueClose()
        pcall(function()
            local gui = lp:FindFirstChild("PlayerGui") and lp.PlayerGui:FindFirstChild("MainGui")
            local menu = gui and gui:FindFirstChild("Menu")
            local dlg = menu and menu:FindFirstChild("Dialogue")
            if not (dlg and dlg.Visible) then return end
            for _, d in ipairs(dlg:GetDescendants()) do
                if d:IsA("TextButton") and d.Visible then
                    local t = tostring(d.Text):lower()
                    for _, w in ipairs({ "close", "bye", "leave", "goodbye", "exit", "cancel" }) do
                        if t:find(w, 1, true) then
                            if firesignal then pcall(firesignal, d.MouseButton1Click) end
                            return
                        end
                    end
                end
            end
        end)
    end
    local function closeBaitUi()
        closeShop("BaitShop")
        pressDialogueClose()
    end
    local function baitChooser(opts)
        for i, o in ipairs(opts) do
            local txt = (tostring(o[1]) .. " " .. tostring(o[2])):lower()
            if txt:find("bait", 1, true) or txt:find("shop", 1, true) or txt:find("buy", 1, true) then return i, o[2] end
        end
        return nil
    end
    local function buyBait()
        local name = wantedBait()
        if not name then qs.status = "auto bait: no bait for sale found"; qs.baitHold = tick() + 120; return false end
        local r0 = myRoot()
        if not r0 then return false end
        local home, look = r0.Position, r0.CFrame.LookVector
        local goal = math.clamp(math.floor(tonumber(Config.BuyBaitAmount) or BAIT_MAX), 1, BAIT_MAX)
        local have = baitCount(name)
        if have >= goal then qs.baitHold = tick() + 60; return true end
        local model, sp = findSeller()
        if not sp then qs.status = "auto bait: bait seller not found"; qs.baitHold = tick() + 120; return false end
        qs.status = "out of bait - going to the bait seller to buy " .. name
        qlog(string.format("bait: %s is used up (%d left) -> buying up to %d at (%d,%d,%d), %d studs away", name, have, goal, sp.X, sp.Y, sp.Z, dist(sp)))
        respot(false)
        goTo(sp + Vector3.new(3, 0, 3), "the seller")
        task.wait(0.8)
        if not model then                              -- the NPC streams in once we are close
            for _ = 1, 8 do
                model = (findSeller())
                if model then break end
                task.wait(0.5)
            end
        end
        local bought = 0
        local rem = RS:FindFirstChild("Events") and RS.Events:FindFirstChild("BuyBait")
        if not rem then qs.status = "auto bait: BuyBait remote missing"; qs.baitHold = tick() + 120 end
        for round = 1, 2 do
            if not rem then break end
            if model then
                local ok, why = talk(model, nil, baitChooser, 3, true)
                qlog("bait: talk -> " .. tostring(ok) .. " " .. tostring(why))
                task.wait(0.6)
            else
                qlog("bait: seller model not loaded - buying without opening the dialogue")
            end
            local amount = goal - have
            for try = 1, 6 do
                pcall(function() rem:FireServer(name, amount) end)
                if waitFor(function() return baitCount(name) > have end, 3) then
                    bought = baitCount(name) - have
                    break
                end
                amount = math.max(1, math.floor(amount / 2))     -- too expensive? try a smaller amount
            end
            if bought > 0 then break end
        end
        closeBaitUi()
        if bought > 0 then
            qlog(string.format("bait: bought %d x %s (now %d)", bought, name, baitCount(name)))
            local eq = equippedBait()
            if eq ~= name and (baitCount(eq) <= (tonumber(Config.BuyBaitBelow) or 0) or Config.BuyBaitName ~= "Auto") then
                local ev = RS:FindFirstChild("Events")
                local r = ev and ev:FindFirstChild("EquipBait")
                if r then pcall(function() r:InvokeServer(name) end) end
            end
            qs.status = string.format("bought %d x %s", bought, name)
            qs.baitHold = tick() + 10
        else
            qs.status = "auto bait: could not buy " .. name .. " (not enough money? shop not open?)"
            qlog("bait: purchase failed, next try in 3 min")
            qs.baitHold = tick() + 180
        end
        -- back to where we were
        goTo(home, "the fishing spot")
        task.wait(0.4)
        pcall(function()
            local r = myRoot()
            if r and (r.Position - home).Magnitude < 15 then r.CFrame = CFrame.lookAt(r.Position, r.Position + Vector3.new(look.X, 0, look.Z)) end
        end)
        respot(true)
        return bought > 0
    end

    -- which fishing spot does this quest want? the big simple "use N bait / skill ..." quests -> easy spot (when set),
    -- everything else (catch fish of a size / kind ...) -> the hard spot
    local function classifyQuest(t)
        if not (Config.QuestSplitFarm and Config.QuestFarmPosEasy) then return "hard" end
        if not (t and t.active and #t.objs > 0) then return nil end
        local minAmt = tonumber(Config.EasyMinAmount) or 30
        for _, o in ipairs(t.objs) do
            local txt = (tostring(o.desc) .. " " .. tostring(o.kind) .. " " .. tostring(o.target)):lower()
            -- "use N bait / skill", "cast N times": always simple
            local simple = txt:find("use", 1, true) or txt:find("bait", 1, true) or txt:find("skill", 1, true) or txt:find("cast", 1, true)
            -- a size / weight / rarity condition makes a fish quest a hard one ("10 fish of 1.5m", "mythic fish" ...)
            local picky = txt:find("%d%s*m%f[%A]") or txt:find("%d%s*kg") or txt:find("size", 1, true) or txt:find("weight", 1, true)
                or txt:find("length", 1, true) or txt:find("heavy", 1, true) or txt:find("giant", 1, true) or txt:find("big", 1, true)
                or txt:find("large", 1, true) or txt:find("rare", 1, true) or txt:find("legend", 1, true) or txt:find("mythic", 1, true)
                or txt:find("secret", 1, true) or txt:find("exotic", 1, true)
            -- a big plain count ("Fish 100 times") is simple even when the quest itself is of the Hard difficulty
            local bulk = (tonumber(o.amount) or 0) >= minAmt and not picky
            if not (simple or bulk) then return "hard" end
        end
        return "easy"
    end
    local function applyFarmKind(t)
        local k
        if not (t and t.active) and (qs.dailyLimit or (t and (t.cooldown or 0) > 0)) and Config.IdleSpotOn and Config.QuestFarmPosIdle then
            k = "idle"                                   -- cooldown / daily limit: the saved idle spot
        else
            k = classifyQuest(t)
        end
        local o = t and t.objs and t.objs[1]
        local sig = o and (tostring(t.name) .. "|" .. tostring(o.desc) .. "|" .. tostring(o.amount)) or nil
        if sig and sig ~= qs.lastQuestSig then
            qs.lastQuestSig = sig
            qlog(string.format("quest objective: '%s' amount %s kind '%s' target '%s' -> %s farm spot", tostring(o.desc), tostring(o.amount), tostring(o.kind), tostring(o.target), tostring(k)))
        end
        if not k and not (t and t.active) and Config.QuestSplitFarm and Config.QuestFarmPosEasy and not (Config.IdleSpotOn and Config.QuestFarmPosIdle) then
            -- no quest running (cooldown): fish at the spot nearest to the ticket NPC, so the next hand-in is a short trip
            local np = npcPos(ticketNpc())
            if np then
                local e, h = Config.QuestFarmPosEasy, Config.QuestFarmPos
                local de = (Vector3.new(e[1], e[2], e[3]) - np).Magnitude
                local dh = (Vector3.new(h[1], h[2], h[3]) - np).Magnitude
                k = (de < dh) and "easy" or "hard"
            end
        end
        if k and k ~= qs.farmKind then qs.farmKind = k end
    end
    -- skill loadout: up to 3 skills for each fishing spot. Skills owned = Data.Skill children; the rod's slots live in
    -- Data.FishingRodInventory[<rod>].Skill[Z/X/C/V]; Events.EquipSkill:InvokeServer(name) toggles one skill.
    local function ownedSkills()
        local out = {}
        local d = getData()
        local f = d and d:FindFirstChild("Skill")
        if f then for _, c in ipairs(f:GetChildren()) do out[#out + 1] = c.Name end end
        table.sort(out)
        return out
    end
    local function equippedSkills()
        local out = {}
        pcall(function()
            local d = getData()
            local inv = d.FishingRodInventory:FindFirstChild(d.FishingRod.Value)
            local sk = inv and inv:FindFirstChild("Skill")
            if sk then for _, c in ipairs(sk:GetChildren()) do if type(c.Value) == "string" and c.Value ~= "" then out[#out + 1] = c.Value end end end
        end)
        return out
    end
    local function hasSkill(name) for _, n in ipairs(equippedSkills()) do if n == name then return true end end return false end
    local function applyLoadout(kind)
        local list = (kind == "easy" and Config.SkillEasy) or (kind == "idle" and Config.SkillIdle) or Config.SkillHard
        local want, set = {}, {}
        for i = 1, 3 do local n = list and list[i]; if type(n) == "string" and n ~= "" and not set[n] then want[#want + 1] = n; set[n] = true end end
        if #want == 0 then return true end
        local ev = RS:FindFirstChild("Events")
        local r = ev and ev:FindFirstChild("EquipSkill")
        if not r then qlog("skills: EquipSkill remote missing"); return false end
        local owned = {}
        for _, n in ipairs(ownedSkills()) do owned[n] = true end
        for _, n in ipairs(equippedSkills()) do                      -- free the slots of skills that are not wanted
            if not set[n] then
                pcall(function() r:InvokeServer(n) end)
                waitFor(function() return not hasSkill(n) end, 3)
                task.wait(0.3)
            end
        end
        local missing = {}
        for _, n in ipairs(want) do
            if not hasSkill(n) then
                if not owned[n] then missing[#missing + 1] = n
                else
                    pcall(function() r:InvokeServer(n) end)
                    if not waitFor(function() return hasSkill(n) end, 3) then missing[#missing + 1] = n end
                    task.wait(0.3)
                end
            end
        end
        qlog(string.format("skills (%s spot): wanted %s -> equipped %s%s", kind, table.concat(want, ", "), table.concat(equippedSkills(), ", "),
            #missing > 0 and ("  (could not equip: " .. table.concat(missing, ", ") .. ")") or ""))
        return #missing == 0
    end
    -- one visit to the Ticket NPC: turn in a finished quest and, when the cooldown allows it, take the NEXT
    -- quest right away (same visit), and only then go back to the farm spot
    local function visit()
        if not goNpc() then return end
        local v0 = tick()
        for round = 1, 3 do
            local ok, why = talk(ticketNpc(), TICKET_NPC, ticketChooser, 4)
            qs.status = ok and ("talked to NPC: " .. tostring(why)) or ("talk failed: " .. tostring(why))
            if not ok then break end
            task.wait(1.5)
            -- "That's all the quests I've got for today! Come back tomorrow for more." = the daily limit
            local txt = (qs.dlg and qs.dlg.text and qs.dlgAt >= v0) and string.lower(qs.dlg.text) or ""
            if txt:find("come back tomorrow", 1, true) or txt:find("all the quests", 1, true) then
                qs.dailyLimit = true
                qlog("daily quest limit reached: '" .. tostring(qs.dlg.text) .. "'")
                break
            end
            local t = readTicket()
            if t.active or t.cooldown > 0 then break end   -- accepted a quest, or the cooldown is running
            -- turned in, nothing accepted yet: talk once more to take the next quest
        end
        local t = readTicket()
        if t.active then qs.dailyLimit = false end
        if not t.active and t.cooldown <= 0 then
            if qs.dailyLimit then
                qs.holdUntil = tick() + 3600   -- daily limit: ask again in an hour, fish meanwhile
                qs.status = "daily quest limit reached - fishing at the idle spot, asking again in 1 h"
            else
                qs.holdUntil = tick() + 300     -- could not accept: do not spam the NPC, farm for 5 min
                qs.status = "no quest accepted - retry in 5 min"
            end
        end
        task.wait(1)
        applyFarmKind(readTicket())
        if Config.QuestFarm and needFarmMove() then goFarm() end
    end

    -- one decision step ----------------------------------------------------------------------------
    local function step()
        local char = lp.Character
        if not char then return end
        if char:GetAttribute("Minigame") == true then qs.status = "waiting (fish on the line)"; return end
        if swimming() then
            ui.questBusy = true
            rescueWater(Config.QuestFarm and farmPos() or nil)
            ui.questBusy = false
            return
        end
        if Config.AutoBuyBait and tick() >= (qs.baitHold or 0) and needBait() then
            ui.questBusy = true
            qs.lastTalk = tick()
            local okB, errB = pcall(buyBait)
            if not okB then
                qs.status = "auto bait error: " .. tostring(errB)
                qlog("bait error: " .. tostring(errB))
                qs.baitHold = tick() + 120
            end
            ui.questBusy = false
            return
        end
        if not Config.AutoTicketQuest then qs.status = "auto bait: watching the bait stock"; return end
        local t = readTicket()
        applyFarmKind(t)
        if Config.SkillLoadout and dist(farmPos()) < 80 then
            local kind = farmKindNow()
            if qs.loadoutKind ~= kind and tick() >= (qs.loadoutRetry or 0) then
                ui.questBusy = true
                qs.status = "equipping the " .. kind .. " skill loadout"
                local okL, resL = pcall(applyLoadout, kind)
                ui.questBusy = false
                qs.loadoutKind = kind
                if not (okL and resL) then qs.loadoutRetry = tick() + 120; qs.loadoutKind = nil end
            end
        end
        if t.active and not t.done and t.objs[1] and t.objs[1].kind == "UseBait" then pcall(ensureBait) end
        if t.active and not t.done then
            qs.status = "working on the quest"
            if Config.QuestFarm and needFarmMove() then
                ui.questBusy = true
                goFarm()
                ui.questBusy = false
            end
        elseif ((t.active and t.done) or t.cooldown <= 0) and tick() >= (qs.holdUntil or 0) then
            if tick() - qs.lastTalk < 25 then qs.status = "waiting (talked just now)"; return end
            qs.status = t.active and "turning in the quest" or ("accepting a " .. Config.TicketDifficulty .. " quest")
            ui.questBusy = true
            qs.lastTalk = tick()
            visit()
            qs.lastTalk = tick()
            ui.questBusy = false
        else
            qs.status = "cooldown - fishing at the farm spot"
            if Config.QuestFarm and needFarmMove() then
                ui.questBusy = true
                goFarm()
                ui.questBusy = false
            end
        end
    end

    -- stop whatever the automation is doing and give the game its UI / character back (used when the quest toggle is
    -- switched off and by the "Reset" button): no leftover boat steering, no shop / dark overlay left open, normal jump
    local function resetQuestState(why)
        qs.cancel = true
        local t0 = tick()
        while qs.busy and tick() - t0 < 6 do task.wait(0.2) end      -- the running action sees the flag and stops
        qs.cancel = false
        pcall(function() RunService:UnbindFromRenderStep("PPY_BoatThrottle") end)
        qs.sailing = false
        pcall(jumpBoost, false)
        pcall(function()
            local h = myHum()
            local seat = h and h.SeatPart
            if seat and seat:IsA("VehicleSeat") then
                seat.ThrottleFloat = 0; seat.SteerFloat = 0
                leaveBoat(seat)                          -- sitting in a boat nobody drives: get out the game's way
            end
        end)
        pcall(closeShop, "BoatShop")
        pcall(closeShop, "BaitShop")
        pcall(pressDialogueClose)
        ui.questBusy = false
        qs.shop, qs.dlg = nil, nil
        qs.status = "stopped - boat / UI state reset" .. (why and (" (" .. why .. ")") or "")
        qlog("reset: " .. tostring(why or "manual"))
    end
    local function guarded(fn)
        if qs.busy then qs.status = "busy with another action - wait a moment and press again"; return end
        qs.busy = true
        task.spawn(function()
            local ok, err = pcall(fn)
            if not ok then qs.status = "error: " .. tostring(err) end
            qs.sailing = false
            ui.questBusy = false
            qs.busy = false
        end)
    end

    -- UI ----------------------------------------------------------------------------------------------
    section("Ticket quest")
    local info = infoCard({
        { "state", "State" }, { "quest", "Quest" }, { "obj", "Task" }, { "prog", "Progress" }, { "cd", "Cooldown" }, { "pos", "Farm spot / distance" }, { "boat", "Last boat trip" },
    }, 0.38)
    toggleButton("Auto ticket quest", 34, Config.AutoTicketQuest, function(v)
        play(clickSound)
        Config.AutoTicketQuest = v
        if not v and not Config.AutoBuyBait then task.spawn(function() pcall(resetQuestState, "quest turned off") end) end
    end)
    ui.sub("Options")
    toggleButton("Fish at the farm spot meanwhile", 30, Config.QuestFarm, function(v)
        play(clickSound)
        Config.QuestFarm = v
    end)
    makeDropdown("Difficulty", { "Hard", "Easy" }, Config.TicketDifficulty, function(v) Config.TicketDifficulty = v end)
    makeDropdown("Travel", { "Teleport", "Boat" }, Config.QuestTravel, function(v) Config.QuestTravel = v end)
    do
        -- bait for "use bait" quests: tap to cycle Off / Auto / each bait you own right now
        local baitBtn
        local function baitText()
            return "Bait for use-bait quests:  " .. tostring(Config.QuestBait)
        end
        baitBtn = actionButton(baitText(), 28, function()
            play(clickSound)
            local opts = { "Off", "Auto" }
            for _, b in ipairs(baitList()) do opts[#opts + 1] = b.name end
            local idx = 1
            for i, o in ipairs(opts) do if o == Config.QuestBait then idx = i end end
            Config.QuestBait = opts[idx % #opts + 1]
            baitBtn.Text = baitText()
        end)
    end
    ui.endSub()
    ui.sub("Skill loadout per spot (3 skills each)")
    toggleButton("Equip the skills below at each spot", 30, Config.SkillLoadout, function(v)
        play(clickSound)
        Config.SkillLoadout = v
        qs.loadoutKind = nil
        pcall(markDirty)
    end)
    do
        -- 1) the skills you are using right now: tap a row to cycle through OFF / EASY / HARD / IDLE and their combinations
        local setRows = ui.makeRowsPanel()
        local pickerRefresh = {}
        local LISTS = { E = "SkillEasy", H = "SkillHard", I = "SkillIdle" }
        local ORDER = { "E", "H", "I" }
        local LABEL = { E = "EASY", H = "HARD", I = "IDLE" }
        local function inList(t, n) for i = 1, 3 do if t[i] == n then return i end end end
        local function putIn(t, n)
            if inList(t, n) then return true end
            for i = 1, 3 do if t[i] == "" then t[i] = n; return true end end
            return false
        end
        local function takeOut(t, n) local i = inList(t, n); if i then t[i] = "" end end
        local function roleOf(n)
            local code = ""
            for _, c in ipairs(ORDER) do if inList(Config[LISTS[c]], n) then code = code .. c end end
            return code
        end
        local function setRole(n, code)
            local old = {}
            for _, c in ipairs(ORDER) do old[c] = { table.unpack(Config[LISTS[c]]) } end
            for _, c in ipairs(ORDER) do takeOut(Config[LISTS[c]], n) end
            local ok = true
            for c in string.gmatch(code, ".") do if not putIn(Config[LISTS[c]], n) then ok = false end end
            if not ok then                                           -- one of the lists is full (3): undo
                for _, c in ipairs(ORDER) do for i = 1, 3 do Config[LISTS[c]][i] = old[c][i] end end
                return false
            end
            return true
        end
        local CYCLE = { "", "E", "H", "I", "EH", "EI", "HI", "EHI" }
        local function nextRole(code)
            for i, c in ipairs(CYCLE) do if c == code then return CYCLE[i % #CYCLE + 1] end end
            return "E"
        end
        local function roleText(code)
            if code == "" then return "OFF" end
            local o = {}
            for c in string.gmatch(code, ".") do o[#o + 1] = LABEL[c] end
            return table.concat(o, " + ")
        end
        local COLORS = { E = Color3.fromRGB(90, 200, 120), H = Color3.fromRGB(240, 170, 70), I = Color3.fromRGB(120, 170, 255) }
        local lastSig = nil
        local function rebuild(force)
            local names, seen = {}, {}
            for _, n in ipairs(equippedSkills()) do if not seen[n] then seen[n] = true; names[#names + 1] = n end end
            for _, t in ipairs({ Config.SkillEasy, Config.SkillHard, Config.SkillIdle }) do
                for i = 1, 3 do local n = t[i]; if n ~= "" and not seen[n] then seen[n] = true; names[#names + 1] = n end end
            end
            local sig = table.concat(names, ",") .. "|" .. table.concat(Config.SkillEasy, ",") .. "|" .. table.concat(Config.SkillHard, ",") .. "|" .. table.concat(Config.SkillIdle, ",")
            if not force and sig == lastSig then return end
            lastSig = sig
            local rows = {}
            for _, n in ipairs(names) do
                local role = roleOf(n)
                rows[#rows + 1] = {
                    text = n .. (hasSkill(n) and "" or "  (not equipped)") .. "   ->   " .. roleText(role),
                    color = (role ~= "" and COLORS[string.sub(role, 1, 1)]) or Color3.fromRGB(150, 150, 150),
                    on = function()
                        local r = nextRole(roleOf(n))
                        for _ = 1, #CYCLE do                          -- skip roles whose list is full
                            if setRole(n, r) then break end
                            r = nextRole(r)
                        end
                        qs.loadoutKind = nil
                        pcall(markDirty)
                        rebuild(true)
                        for _, f in ipairs(pickerRefresh) do pcall(f) end
                    end,
                }
            end
            setRows(rows)
        end
        ui.refreshSkillRows = rebuild
        rebuild(true)
        -- 2) add skills you are not wearing now: searchable list of everything you own
        local function skillBtn(label, tbl, i)
            pickerRefresh[#pickerRefresh + 1] = makeSearchPicker(label .. " " .. i, ownedSkills, function() return tbl[i] end, function(v)
                if v ~= "" then takeOut(tbl, v) end
                tbl[i] = v
                qs.loadoutKind = nil
                pcall(markDirty)
                rebuild(true)
            end)
        end
        for i = 1, 3 do skillBtn("EASY spot skill", Config.SkillEasy, i) end
        for i = 1, 3 do skillBtn("HARD spot skill", Config.SkillHard, i) end
        for i = 1, 3 do skillBtn("IDLE spot skill", Config.SkillIdle, i) end
    end
    actionButton("Equip the loadout for the current spot now", 28, function()
        play(clickSound)
        guarded(function() ui.questBusy = true; applyLoadout(farmKindNow()) end)
    end)
    ui.endSub()
    ui.sub("Options (more)")
    actionButton("Reset boat / UI (use if the boat shop acts up)", 28, function()
        play(clickSound)
        task.spawn(function() pcall(resetQuestState, "manual") end)
    end)
    makeSlider("Dialogue click delay", "s", 0.5, 3, 0.1, 0.1, 1, Config.QuestDelay, function(v) Config.QuestDelay = v end)
    toggleButton("Easy spot for simple / big-count quests", 30, Config.QuestSplitFarm, function(v)
        play(clickSound)
        Config.QuestSplitFarm = v
        pcall(markDirty)
    end)
    makeSlider("Easy spot when the count is at least", "x", 10, 500, 10, 10, 0, Config.EasyMinAmount or 30, function(v) Config.EasyMinAmount = v; pcall(markDirty) end)
    actionButton("Save this position as HARD farm spot (fish size etc.)", 30, function()
        play(clickSound)
        local r = myRoot()
        if r then
            Config.QuestFarmPos = { math.floor(r.Position.X), math.floor(r.Position.Y), math.floor(r.Position.Z) }
            local lv = r.CFrame.LookVector
            Config.QuestFarmLook = { lv.X, lv.Z }
            pcall(markDirty)
        end
    end)
    actionButton("Save this position as EASY farm spot (use bait / skill)", 30, function()
        play(clickSound)
        local r = myRoot()
        if r then
            Config.QuestFarmPosEasy = { math.floor(r.Position.X), math.floor(r.Position.Y), math.floor(r.Position.Z) }
            local lv = r.CFrame.LookVector
            Config.QuestFarmLookEasy = { lv.X, lv.Z }
            pcall(markDirty)
        end
    end)
    toggleButton("Idle spot during cooldown / daily limit", 30, Config.IdleSpotOn, function(v)
        play(clickSound)
        Config.IdleSpotOn = v
        pcall(markDirty)
    end)
    actionButton("Save this position as IDLE farm spot (cooldown / limit)", 30, function()
        play(clickSound)
        local r = myRoot()
        if r then
            Config.QuestFarmPosIdle = { math.floor(r.Position.X), math.floor(r.Position.Y), math.floor(r.Position.Z) }
            local lv = r.CFrame.LookVector
            Config.QuestFarmLookIdle = { lv.X, lv.Z }
            pcall(markDirty)
        end
    end)
    actionButton("Go to IDLE farm spot", 28, function()
        play(clickSound)
        guarded(function()
            ui.questBusy = true
            if not Config.QuestFarmPosIdle then qs.status = "idle farm spot not set yet"; return end
            qs.farmKind = "idle"
            local d = dist(farmPos())
            if d <= 16 then qs.status = string.format("already at the IDLE farm spot (%d studs away)", d); return end
            qs.status = string.format("going to the IDLE farm spot (%d studs)", d)
            goFarm()
        end)
    end)
    actionButton("Go to HARD farm spot", 28, function()
        play(clickSound)
        guarded(function()
            ui.questBusy = true
            qs.farmKind = "hard"
            local d = dist(farmPos())
            if d <= 16 then qs.status = string.format("already at the HARD farm spot (%d studs away)", d); return end
            qs.status = string.format("going to the HARD farm spot (%d studs)", d)
            goFarm()
        end)
    end)
    actionButton("Go to EASY farm spot", 28, function()
        play(clickSound)
        guarded(function()
            ui.questBusy = true
            if not Config.QuestFarmPosEasy then qs.status = "easy farm spot not set yet"; return end
            qs.farmKind = "easy"
            local d = dist(farmPos())
            if d <= 16 then qs.status = string.format("already at the EASY farm spot (%d studs away)", d); return end
            qs.status = string.format("going to the EASY farm spot (%d studs)", d)
            goFarm()
        end)
    end)
    actionButton("Go to NPC and talk", 28, function()
        play(clickSound)
        guarded(function()
            ui.questBusy = true
            qs.lastTalk = tick()
            qs.holdUntil = 0
            visit()
        end)
    end)
    ui.endSub()
    ui.sub("Auto buy bait")
    toggleButton("Auto buy bait when it runs out", 34, Config.AutoBuyBait, function(v)
        play(clickSound)
        Config.AutoBuyBait = v
        pcall(markDirty)
    end)
    do
        local names = { "Auto" }
        pcall(function() for _, b in ipairs(buyableBaits()) do names[#names + 1] = b.name end end)
        makeDropdown("Bait to buy", names, Config.BuyBaitName, function(v) Config.BuyBaitName = v; pcall(markDirty) end)
    end
    makeSlider("Buy up to (max 400)", "pcs", 10, 400, 10, 10, 0, Config.BuyBaitAmount, function(v) Config.BuyBaitAmount = math.min(BAIT_MAX, v); pcall(markDirty) end)
    makeSlider("Buy when bait is at or below", "pcs", 0, 50, 1, 1, 0, Config.BuyBaitBelow, function(v) Config.BuyBaitBelow = v; pcall(markDirty) end)
    makeDropdown("Bait travel", { "Walk", "Teleport" }, Config.BaitTravel, function(v) Config.BaitTravel = v; pcall(markDirty) end)
    actionButton("Buy bait now", 28, function()
        play(clickSound)
        guarded(function()
            ui.questBusy = true
            qs.baitHold = 0
            buyBait()
        end)
    end)
    ui.endSub()

    local function fmtCd(s)
        s = math.floor(s)
        return string.format("%d:%02d", math.floor(s / 60), s % 60)
    end
    task.spawn(function()
        while running do
            task.wait(1.5)
            pcall(function()
                local t = readTicket()
                local o = t.objs[1]
                info.state(qs.status .. (qs.boatNote ~= "" and (" [" .. qs.boatNote .. "]") or ""))
                info.quest(t.active and t.name or "none")
                info.obj(o and (o.desc .. (o.target ~= "" and (" [" .. o.kind .. ": " .. o.target .. "]") or (" [" .. o.kind .. "]"))) or "-")
                info.prog(o and (math.floor(o.progress) .. " / " .. o.amount .. (t.done and "  DONE" or "")) or "-")
                info.cd(t.cooldown > 0 and fmtCd(t.cooldown) or "ready")
                local d = dist(farmPos())
                info.pos(string.upper(farmKindNow()) .. "  " .. (d == math.huge and "-" or (math.floor(d) .. " studs")))
                info.boat(qs.boatResult or "-")
                if ui.refreshSkillRows then pcall(ui.refreshSkillRows, false) end
                if (Config.AutoTicketQuest or Config.AutoBuyBait) and not qs.busy then guarded(step) end
            end)
        end
    end)
end)()

selectTab("Fish")

-- 🚀 Performance --------------------------------------------------------
section("Performance")
do
    local _, setBlackVisual = toggleButton("Black screen (turns 3D rendering off)  [RightShift]", 34, false, function(v)
        play(clickSound)
        perf.setBlack(v)
    end)
    ui.setBlack = setBlackVisual
end
ui.sub("Options")
toggleButton("Hide game UI too", 30, Config.BlackHideUi, function(v)
    play(clickSound)
    Config.BlackHideUi = v
end)
toggleButton("Show status text (off = pure black)", 30, Config.BlackHud, function(v)
    play(clickSound)
    Config.BlackHud = v
end)
makeSlider("Black screen FPS", "fps", 5, 60, 5, 5, 0, Config.BlackFps, function(v)
    Config.BlackFps = v
    perf.refreshFps()
end)
ui.endSub()
perf.vis = {}
do
    local _, v1 = toggleButton("Low graphics (shadows, effects, water)", 30, false, function(v)
        play(clickSound)
        perf.setLowGfx(v)
    end)
    local _, v2 = toggleButton("Disable particles / beams / lights", 30, false, function(v)
        play(clickSound)
        perf.setNoFx(v)
    end)
    local _, v3 = toggleButton("Mute game audio", 30, false, function(v)
        play(clickSound)
        perf.setMute(v)
    end)
    local _, v4 = toggleButton("Limit FPS" .. (setfpscap and "" or "  (not supported by this executor)"), 30, false, function(v)
        play(clickSound)
        perf.setFps(v)
    end)
    perf.vis = { lowgfx = v1, nofx = v2, mute = v3, fps = v4 }
end
actionButton("Max saver (everything on)", 34, function()
    play(clickSound)
    perf.setBlack(true); if ui.setBlack then ui.setBlack(true) end
    perf.setLowGfx(true); perf.setNoFx(true); perf.setMute(true); perf.setFps(true)
    for _, k in ipairs({ "lowgfx", "nofx", "mute", "fps" }) do
        if perf.vis[k] then pcall(perf.vis[k], true) end
    end
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
    Size = UDim2.new(1, -20, 0, 24), Position = UDim2.new(0, 10, 1, -32), Text = "Drag here to move",
    Font = Enum.Font.Gotham, TextSize = 10, BackgroundColor3 = COL_CARD, TextColor3 = COL_TEXT2,
    AutoButtonColor = false,
}, Main)
corner(MoveBtn, 8)
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

-- help window: a separate small ScreenGui, closed with its own X (or the ? button) ------------------------------
do
    local helpGui = nil
    local function buildHelp()
        helpGui = new("ScreenGui", {
            Name = "PPINGYYY_Help", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, IgnoreGuiInset = true, DisplayOrder = 11,
        })
        attachGui(helpGui)
        ui.helpGui = helpGui
        local win = new("Frame", {
            Size = UDim2.new(0, 340, 0, 400), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0),
            BackgroundColor3 = Color3.fromRGB(16, 18, 26), BorderSizePixel = 0, Active = true,
        }, helpGui)
        corner(win, 12)
        new("UIStroke", { Color = COL_STROKE, Thickness = 1 }, win)
        local bar = new("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1 }, win)
        new("TextLabel", {
            Size = UDim2.new(1, -52, 1, 0), Position = UDim2.new(0, 14, 0, 0), BackgroundTransparency = 1, Text = "How to use",
            TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Left,
        }, bar)
        local x = new("TextButton", {
            Size = UDim2.new(0, 26, 0, 26), Position = UDim2.new(1, -36, 0, 7), Text = "✕", Font = Enum.Font.GothamBold,
            TextSize = 12, BackgroundColor3 = COL_ROW, TextColor3 = COL_TEXT2, AutoButtonColor = true,
        }, bar)
        corner(x, 6)
        x.MouseButton1Click:Connect(function() play(clickSound); helpGui.Enabled = false end)
        local list = new("ScrollingFrame", {
            Size = UDim2.new(1, -16, 1, -48), Position = UDim2.new(0, 8, 0, 42), BackgroundTransparency = 1, BorderSizePixel = 0,
            ScrollBarThickness = 3, CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
        }, win)
        new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 4) }, list)
        for i, sec in ipairs(ui.helpSections or {}) do
            local holder = new("Frame", {
                Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = i,
            }, list)
            new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder, Padding = UDim.new(0, 2) }, holder)
            local head = new("TextButton", {
                Size = UDim2.new(1, 0, 0, 28), LayoutOrder = 1, Font = Enum.Font.GothamMedium, TextSize = 12, BackgroundColor3 = COL_ROW,
                TextColor3 = COL_GREEN, BorderSizePixel = 0, TextXAlignment = Enum.TextXAlignment.Left,
            }, holder)
            corner(head, 6)
            new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 8) }, head)
            local body = new("TextLabel", {
                Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, BackgroundColor3 = COL_CARD,
                BorderSizePixel = 0, Text = tostring(sec.text or ""), TextColor3 = Color3.fromRGB(210, 214, 224), Font = Enum.Font.Gotham,
                TextSize = 11, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
                Visible = false, RichText = true,
            }, holder)
            corner(body, 6)
            new("UIPadding", {
                PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10), PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
            }, body)
            local function refresh() head.Text = (body.Visible and "▾  " or "▸  ") .. tostring(sec.title or "") end
            head.MouseButton1Click:Connect(function() play(clickSound); body.Visible = not body.Visible; refresh() end)
            refresh()
        end
        -- drag by the title bar
        local dragging, dragInput, dragStart, startPos = false, nil, nil, nil
        bar.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging, dragStart, startPos = true, input.Position, win.Position
                input.Changed:Connect(function() if input.UserInputState == Enum.UserInputState.End then dragging = false end end)
            end
        end)
        bar.InputChanged:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then dragInput = input end
        end)
        conns[#conns + 1] = UserInputService.InputChanged:Connect(function(input)
            if dragging and input == dragInput then
                local d = input.Position - dragStart
                win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
    end
    function ui.toggleHelp()
        if not helpGui or not helpGui.Parent then
            local ok, err = pcall(buildHelp)
            if not ok then warn("[PPINGYYY] help window failed: " .. tostring(err)); return end
            helpGui.Enabled = true
            return
        end
        helpGui.Enabled = not helpGui.Enabled
    end
end

-- minimize / close / hide key ----------------------------------------
local minimized = false
do
    local function applyFit()
        local full, min, mobile, h = ui.fitSize()
        FULL_SIZE, MIN_SIZE = full, min
        local compact = h < 430            -- short screen (phone in landscape, small window): drop the extras
        ui.compact = compact
        Content.Size = UDim2.new(1, 0, 1, compact and -100 or -160)
        StatusBox.Size = UDim2.new(1, -20, 0, compact and 38 or 66)
        StatusBox.Position = UDim2.new(0, 10, 1, compact and -46 or -106)
        StatusLabel.Size = UDim2.new(1, -16, 0, compact and 30 or 34)
        DetailLabel.Visible = not compact
        MoveBtn.Visible = (not compact) and not minimized
        Main.Size = minimized and MIN_SIZE or FULL_SIZE
    end
    applyFit()
    local function hook()
        local cam = workspace.CurrentCamera
        if cam then conns[#conns + 1] = cam:GetPropertyChangedSignal("ViewportSize"):Connect(applyFit) end
    end
    hook()
    conns[#conns + 1] = workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function() hook(); applyFit() end)
end
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
                MoveBtn.Visible = not ui.compact
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
    pcall(function() if ui.helpGui then ui.helpGui:Destroy() end end)
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
