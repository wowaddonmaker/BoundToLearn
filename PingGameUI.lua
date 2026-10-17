local ADDON_NAME, ns = ...

local PingGameUI = {}
ns.PingGameUI = PingGameUI

local Utils   = ns.Utils
local sformat = Utils.sformat
local mfloor  = Utils.mfloor
local mmax    = Utils.mmax
local mmin    = Utils.mmin
local ipairs  = Utils.ipairs
local pairs   = Utils.pairs
local wipe    = Utils.wipe
local GetTime = Utils.GetTime
local CreateFrame  = Utils.CreateFrame
local PlayUISound  = Utils.PlayUISound
local SOUND_CLICK  = Utils.SOUND_CLICK

local GetBindingKey = GetBindingKey

local TARGET_ENEMY  = 1
local TARGET_ALLY   = 2
local TARGET_HAZARD = 3

local ALLY_SPAWN_ANIMS = { 77, 225 }  -- shy, cower

local GAME_WIDTH  = 600
local GAME_HEIGHT = 400
local TARGET_SIZE = 44
local SPAWN_MARGIN = 40
local MODEL_RETRY = 0.35     -- seconds before a blank 3D target asks for its creature again
local MODEL_GIVE_UP = 0.9    -- seconds before a still-blank 3D target shows its portrait

-- Target visuals
local TARGET_COLORS = {
    [TARGET_ENEMY]  = { 0.9, 0.2, 0.2 },
    [TARGET_ALLY]   = { 0.2, 0.75, 0.3 },
    [TARGET_HAZARD] = { 1.0, 0.75, 0.1 },
}

-- Fallback if atlases don't exist
local TARGET_LABELS = {
    [TARGET_ENEMY]  = "ATK",
    [TARGET_ALLY]   = "ALLY",
    [TARGET_HAZARD] = "WARN",
}

-- Ping action name -> textureKit suffix (for ground pins on miss)
local PING_ACTION_KITS = {
    attack  = "Attack",
    assist  = "Assist",
    warning = "Warning",
    onmyway = "OnMyWay",
}

local DIFF_COLORS = {
    Easy   = { 0.30, 0.85, 0.30 },
    Normal = { 1.00, 0.82, 0.00 },
    Hard   = { 1.00, 0.50, 0.10 },
    Extreme = { 0.90, 0.15, 0.15 },
}

-- Race IDs per faction for portrait icons (used by C_CreatureInfo)
local ALLIANCE_RACE_IDS = { 1, 3, 4, 7, 11, 22 }  -- Human, Dwarf, NightElf, Gnome, Draenei, Worgen
local HORDE_RACE_IDS   = { 2, 5, 6, 8, 10, 9 }    -- Orc, Undead, Tauren, Troll, BloodElf, Goblin

-- NPC IDs for 3D models (well-known city NPCs that always exist)
local ALLIANCE_NPC_IDS = {
    68,     -- Stormwind City Guard (Human)
    5595,   -- Ironforge Guard (Dwarf)
    4262,   -- Darnassus Sentinel (Night Elf)
    5564,   -- Gnomeregan Commando (Gnome)
    44914,  -- Gilnean Survivor (Worgen)
}
local HORDE_NPC_IDS = {
    3296,   -- Orgrimmar Grunt (Orc)
    7980,   -- Deathguard Lundmark (Undead)
    3084,   -- Bluffwatcher (Tauren)
    5953,   -- Sen'jin Guardian (Troll)
    16227,  -- Silvermoon City Guardian (Blood Elf)
}
local playerFaction

-- Backgrounds: texture, music FileDataID, unlock requirement, display name
-- Music IDs from wowhead zone music database
-- Arena backgrounds, one per expansion, using the Adventure Guide backdrop art
-- shared with the song select (SongData.XPAC_BG). Music is resolved per
-- expansion at play time. Classic and TBC are always available; later
-- expansions unlock at score/combo milestones so the picker doubles as a
-- progression track. Names come from Blizzard's localized EXPANSION_NAME* keys.
local BACKGROUNDS = {
    { id = "classic",      tier = 1,  nameKey = "EXPANSION_NAME0" },
    { id = "tbc",          tier = 2,  nameKey = "EXPANSION_NAME1" },
    { id = "wrath",        tier = 3,  nameKey = "EXPANSION_NAME2", unlock = { type = "score", value = 1500,  label = "Score 1500+" } },
    { id = "cataclysm",    tier = 4,  nameKey = "EXPANSION_NAME3", unlock = { type = "combo", value = 12,    label = "12+ combo" } },
    { id = "pandaria",     tier = 5,  nameKey = "EXPANSION_NAME4", unlock = { type = "score", value = 3000,  label = "Score 3000+" } },
    { id = "draenor",      tier = 6,  nameKey = "EXPANSION_NAME5", unlock = { type = "combo", value = 20,    label = "20+ combo" } },
    { id = "legion",       tier = 7,  nameKey = "EXPANSION_NAME6", unlock = { type = "score", value = 5000,  label = "Score 5000+" } },
    { id = "bfa",          tier = 8,  nameKey = "EXPANSION_NAME7", unlock = { type = "combo", value = 30,    label = "30+ combo" } },
    { id = "shadowlands",  tier = 9,  nameKey = "EXPANSION_NAME8", unlock = { type = "score", value = 8000,  label = "Score 8000+" } },
    { id = "dragonflight", tier = 10, nameKey = "EXPANSION_NAME9", unlock = { type = "score", value = 12000, label = "Score 12000+" } },
    { id = "midnight",     tier = 11, nameKey = "EXPANSION_NAME11", nameFallback = "Midnight", unlock = { type = "combo", value = 45, label = "45+ combo" } },
}
-- Forever has no Midnight backdrop art.
if Utils.IS_FOREVER then BACKGROUNDS[#BACKGROUNDS] = nil end
for i = 1, #BACKGROUNDS do
    local bg = BACKGROUNDS[i]
    bg.name = _G[bg.nameKey] or bg.nameFallback or bg.nameKey
    bg.atlas = ns.SongData.XPAC_BG[bg.tier]
end

-- Real WoW ping sound IDs (from wowhead sound database)
local PING_SOUNDS = {
    attack  = 233593,   -- 10.1.7_UI_PingSystem_Attack
    assist  = 233592,   -- 10.1.7_UI_PingSystem_Assist
    warning = 233595,   -- 10.1.7_UI_PingSystem_WarningDanger
    onmyway = 233594,   -- 10.1.7_UI_PingSystem_OnMyWay
}


-- Hazard icon textures (environmental dangers - fire, void zones, traps)
local HAZARD_ICONS = {
    "Interface\\Icons\\Spell_Fire_SelfDestruct",
    "Interface\\Icons\\Spell_Fire_FelImmolation",
    "Interface\\Icons\\Ability_Mage_LivingBomb",
    "Interface\\Icons\\Spell_Shadow_RainOfFire",
}

local mainFrame
local gameArea
local hudFrame
local startFrame
local resultsFrame
local pauseOverlay
local scoreText, timerText, comboText
local targetPool = {}
local activeTargetFrames = {}  -- targetID -> frame
local floatingPool = {}
local groundPinPool = {}
-- Feedback still on screen. Their fades run on OnUpdate, which stops while the
-- arena is hidden, so a round's end clears them (ClearRoundEffects) instead of
-- leaving them to resume in the next round.
local liveFloating, liveGroundPins = {}, {}
local hoveredTargetID = nil
local debugHitbox = false
local isInitialized = false

local PlaySound = PlaySound
local PlayMusic = PlayMusic
local StopMusic = StopMusic

local function GetPingTrainerDB()
    return BoundToLearn.db and BoundToLearn.db.pingTrainer
end

local function IsBackgroundUnlocked(bgID)
    local pt = GetPingTrainerDB()
    return pt and pt.unlockedBGs and pt.unlockedBGs[bgID]
end

local function UnlockBackground(bgID)
    local pt = GetPingTrainerDB()
    if not pt then return end
    if not pt.unlockedBGs then pt.unlockedBGs = {} end
    if pt.unlockedBGs[bgID] then return false end
    pt.unlockedBGs[bgID] = true
    return true
end

local function GetSelectedBackground()
    local pt = GetPingTrainerDB()
    if not pt then return BACKGROUNDS[1] end

    if pt.randomBG then
        local unlocked = {}
        for i = 1, #BACKGROUNDS do
            if IsBackgroundUnlocked(BACKGROUNDS[i].id) then
                unlocked[#unlocked + 1] = BACKGROUNDS[i]
            end
        end
        if #unlocked > 0 then
            return unlocked[math.random(#unlocked)]
        end
    end

    local selectedID = pt.background or "classic"
    for i = 1, #BACKGROUNDS do
        if BACKGROUNDS[i].id == selectedID then
            return BACKGROUNDS[i]
        end
    end
    return BACKGROUNDS[1]
end

-- Backgrounds are Adventure Guide atlases now, so route through SetAtlas; keep a
-- texture path branch in case a future entry uses a raw file.
-- The Adventure Guide backdrops carry a decorative header band across the top
-- (stone tiling + a gold streak). Crop it out and keep the scenic body, then let
-- that stretch to fill the arena.
local GetAtlasInfo = C_Texture and C_Texture.GetAtlasInfo
local BG_CROP_TOP = 0.27
local BG_CROP_BOTTOM = 0.03
local function ApplyBackground(tex, bg)
    if bg and bg.atlas then
        tex:SetAtlas(bg.atlas)
        local info = GetAtlasInfo and GetAtlasInfo(bg.atlas)
        if info then
            local h = info.bottomTexCoord - info.topTexCoord
            tex:SetTexCoord(info.leftTexCoord, info.rightTexCoord,
                info.topTexCoord + h * BG_CROP_TOP, info.bottomTexCoord - h * BG_CROP_BOTTOM)
        end
    elseif bg and bg.texture then
        tex:SetTexture(bg.texture)
    end
end

local function IsMusicMuted()
    local pt = GetPingTrainerDB()
    return pt and pt.muteMusic
end

local function IsPingSoundMuted()
    local pt = GetPingTrainerDB()
    return pt and pt.mutePingSounds
end

local function StartBackgroundMusic(bg)
    if not bg or IsMusicMuted() then return end
    local musicID = bg.musicID or (bg.tier and ns.SongData.TierMusic and ns.SongData.TierMusic(bg.tier))
    -- PlayMusic replaces the current zone music on the Music channel.
    -- We don't need to touch the volume - PlayMusic overrides zone music directly.
    if musicID then PlayMusic(musicID) end
end

local function StopBackgroundMusic()
    StopMusic()
end

local function PlayPingSound(pingAction)
    if IsPingSoundMuted() then return end
    local soundID = PING_SOUNDS[pingAction]
    if soundID then
        PlaySound(soundID, "SFX")
    end
end

local function CheckUnlocks(results)
    local newUnlocks = {}
    for i = 1, #BACKGROUNDS do
        local bg = BACKGROUNDS[i]
        if bg.unlock and not IsBackgroundUnlocked(bg.id) then
            local u = bg.unlock
            local earned = false
            if u.type == "score" and results.score >= u.value then
                earned = true
            elseif u.type == "combo" and results.maxCombo >= u.value then
                earned = true
            elseif u.type == "accuracy" and results.accuracy >= u.value then
                earned = true
            end
            if earned and UnlockBackground(bg.id) then
                newUnlocks[#newUnlocks + 1] = bg
            end
        end
    end
    return newUnlocks
end

local function ToggleMuteMusic(v)
    local pt = GetPingTrainerDB()
    if pt then pt.muteMusic = v end
    if v then StopBackgroundMusic()
    else
        local bg = GetSelectedBackground()
        if ns.PingGame and ns.PingGame:IsRunning() then StartBackgroundMusic(bg) end
    end
end

local function ToggleMutePingSounds(v)
    local pt = GetPingTrainerDB()
    if pt then pt.mutePingSounds = v end
end

local function AcquireFloating()
    local frame = tremove(floatingPool)
    if frame then
        frame:Show()
        return frame
    end

    frame = CreateFrame("Frame", nil, gameArea)
    frame:SetSize(100, 20)
    frame:SetFrameLevel(gameArea:GetFrameLevel() + 15)

    local text = frame:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    text:SetPoint("CENTER")
    frame.text = text

    frame:Show()
    return frame
end

local function ReleaseFloating(frame)
    liveFloating[frame] = nil
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetScript("OnUpdate", nil)
    frame:SetAlpha(1)
    tinsert(floatingPool, frame)
end

local function ShowFloatingText(x, y, msg, r, g, b)
    local frame = AcquireFloating()
    liveFloating[frame] = true
    frame:SetPoint("CENTER", gameArea, "BOTTOMLEFT", x, y)
    frame.text:SetText(msg)
    frame.text:SetTextColor(r, g, b)
    frame:SetAlpha(1)

    local elapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local progress = elapsed / 0.8
        if progress >= 1 then
            ReleaseFloating(self)
            return
        end
        self:SetPoint("CENTER", gameArea, "BOTTOMLEFT", x, y + progress * 40)
        self:SetAlpha(1 - progress * progress)
    end)
end

local GROUND_PIN_SIZE = 40
local GROUND_PIN_STEM = 70
local GROUND_PIN_DURATION = 1.2

local function AcquireGroundPin()
    local frame = tremove(groundPinPool)
    if frame then
        frame:Show()
        return frame
    end

    frame = CreateFrame("Frame", nil, gameArea)
    frame:SetSize(GROUND_PIN_SIZE, GROUND_PIN_SIZE + GROUND_PIN_STEM)
    frame:SetFrameLevel(gameArea:GetFrameLevel() + 12)
    local stem = frame:CreateTexture(nil, "BACKGROUND")
    stem:SetPoint("BOTTOM")
    stem:SetSize(6, GROUND_PIN_STEM)
    frame.stem = stem
    local bg = frame:CreateTexture(nil, "ARTWORK")
    bg:SetSize(GROUND_PIN_SIZE, GROUND_PIN_SIZE)
    bg:SetPoint("TOP")
    frame.bg = bg
    local stroke = frame:CreateTexture(nil, "ARTWORK", nil, 2)
    stroke:SetSize(GROUND_PIN_SIZE, GROUND_PIN_SIZE)
    stroke:SetPoint("CENTER", bg)
    frame.stroke = stroke
    local icon = frame:CreateTexture(nil, "OVERLAY")
    icon:SetSize(GROUND_PIN_SIZE * 0.6, GROUND_PIN_SIZE * 0.6)
    icon:SetPoint("CENTER", bg)
    frame.icon = icon
    frame:Show()
    return frame
end

local function ReleaseGroundPin(frame)
    liveGroundPins[frame] = nil
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetScript("OnUpdate", nil)
    frame:SetAlpha(1)
    tinsert(groundPinPool, frame)
end

local function ShowGroundPin(x, y, kit)
    local pin = AcquireGroundPin()
    liveGroundPins[pin] = true
    pin:SetPoint("BOTTOM", gameArea, "BOTTOMLEFT", x, y)
    pin.bg:SetAtlas("Ping_GroundMarker_BG_" .. kit)
    pin.stroke:SetAtlas("Ping_GroundMarker_Stroke_" .. kit)
    pin.stem:SetAtlas("Ping_GroundMarker_Pin_" .. kit)
    pin.icon:SetAtlas("Ping_Marker_Icon_" .. kit)
    pin:SetAlpha(1)

    local elapsed = 0
    pin:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        if elapsed > GROUND_PIN_DURATION then
            ReleaseGroundPin(self)
            return
        end
        -- Fade out in last 40%
        local fadeStart = GROUND_PIN_DURATION * 0.6
        if elapsed > fadeStart then
            self:SetAlpha(1 - (elapsed - fadeStart) / (GROUND_PIN_DURATION - fadeStart))
        end
    end)
end

local function ClearRoundEffects()
    for frame in pairs(liveFloating) do ReleaseFloating(frame) end
    for frame in pairs(liveGroundPins) do ReleaseGroundPin(frame) end
end

local function AcquireTarget()
    local frame = tremove(targetPool)
    if frame then
        frame:Show()
        return frame
    end

    frame = CreateFrame("Button", nil, gameArea)
    frame:SetSize(TARGET_SIZE, TARGET_SIZE)
    frame:EnableMouse(true)
    frame:RegisterForClicks()  -- no click handling, just hover detection

    -- Circular background
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetTexture("Interface\\COMMON\\Indicator-Gray")
    bg:SetVertexColor(0.2, 0.2, 0.2, 0.8)
    frame.bg = bg

    -- Ring highlight (shows on hover)
    local ring = frame:CreateTexture(nil, "BORDER")
    ring:SetSize(TARGET_SIZE + 8, TARGET_SIZE + 8)
    ring:SetPoint("CENTER")
    ring:SetTexture("Interface\\COMMON\\Indicator-Yellow")
    ring:SetAlpha(0.5)
    frame.ring = ring

    -- Icon (portrait/atlas)
    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetSize(TARGET_SIZE - 8, TARGET_SIZE - 8)
    icon:SetPoint("CENTER")
    frame.icon = icon

    -- 3D model for full-body rendering
    local model = CreateFrame("PlayerModel", nil, frame)
    model:SetSize(TARGET_SIZE * 2.25, TARGET_SIZE * 3.4)
    model:SetPoint("BOTTOM", 0, -10)
    model:SetFrameLevel(frame:GetFrameLevel() + 1)
    model:EnableMouse(false)
    model:Hide()
    frame.model = model

    -- Invisible hit frame over model area (regular Frame = full-rect mouse detection)
    local modelHit = CreateFrame("Frame", nil, frame)
    modelHit:SetPoint("BOTTOMLEFT", model, "BOTTOMLEFT")
    modelHit:SetPoint("BOTTOMRIGHT", model, "BOTTOMRIGHT")
    modelHit:SetHeight(model:GetHeight() * 0.6)
    modelHit:SetFrameLevel(model:GetFrameLevel() + 1)
    modelHit:EnableMouse(true)
    modelHit:SetScript("OnEnter", function()
        local onEnter = frame:GetScript("OnEnter")
        if onEnter then onEnter(frame) end
    end)
    modelHit:SetScript("OnLeave", function()
        local onLeave = frame:GetScript("OnLeave")
        if onLeave then onLeave(frame) end
    end)
    modelHit:Hide()
    frame.modelHit = modelHit

    -- Debug hitbox overlay (green = model hit area)
    local dbgHit = modelHit:CreateTexture(nil, "OVERLAY", nil, 7)
    dbgHit:SetAllPoints()
    dbgHit:SetColorTexture(0, 1, 0, 0.15)
    dbgHit:Hide()
    frame.dbgHit = dbgHit

    -- Unit ping marker (appears on ping - icon above head, no stem)
    local UNIT_PIN_SIZE = 48
    local unitPin = CreateFrame("Frame", nil, frame)
    unitPin:SetSize(UNIT_PIN_SIZE, UNIT_PIN_SIZE)
    unitPin:SetPoint("BOTTOM", frame, "TOP", 0, 4)  -- default for portrait/blob mode
    unitPin:SetFrameLevel(frame:GetFrameLevel() + 10)
    local unitPinBG = unitPin:CreateTexture(nil, "ARTWORK")
    unitPinBG:SetAllPoints()
    unitPin.bg = unitPinBG
    local unitPinIcon = unitPin:CreateTexture(nil, "OVERLAY")
    unitPinIcon:SetSize(UNIT_PIN_SIZE * 0.6, UNIT_PIN_SIZE * 0.6)
    unitPinIcon:SetPoint("CENTER", unitPinBG)
    unitPin.icon = unitPinIcon
    unitPin:Hide()
    frame.unitPin = unitPin

    -- Fallback label if atlas doesn't exist
    local label = frame:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    label:SetPoint("CENTER")
    frame.label = label

    -- Timer bar at bottom
    local timerBG = frame:CreateTexture(nil, "ARTWORK", nil, 1)
    timerBG:SetPoint("BOTTOM")
    timerBG:SetSize(TARGET_SIZE - 4, 3)
    timerBG:SetColorTexture(0.2, 0.2, 0.2, 0.6)
    frame.timerBG = timerBG

    local timerBar = frame:CreateTexture(nil, "OVERLAY")
    timerBar:SetPoint("BOTTOMLEFT", 2, 0)
    timerBar:SetHeight(3)
    timerBar:SetColorTexture(1, 1, 1, 0.8)
    frame.timerBar = timerBar

    -- Hover detection
    frame:SetScript("OnEnter", function(self)
        if self.targetID then
            hoveredTargetID = self.targetID
            self.ring:SetAlpha(1)
            -- Bright glow to show it's hovered
            self.bg:SetVertexColor(self.baseColor[1] * 0.5, self.baseColor[2] * 0.5, self.baseColor[3] * 0.5, 0.95)
        end
    end)
    frame:SetScript("OnLeave", function(self)
        if hoveredTargetID == self.targetID then
            hoveredTargetID = nil
        end
        self.ring:SetAlpha(0.5)
        if self.baseColor then
            self.bg:SetVertexColor(self.baseColor[1] * 0.3, self.baseColor[2] * 0.3, self.baseColor[3] * 0.3, 0.9)
        end
    end)

    frame:Show()
    return frame
end

local function ReleaseTarget(frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame:SetScript("OnUpdate", nil)
    frame:SetAlpha(1)
    frame:SetSize(TARGET_SIZE, TARGET_SIZE)
    frame.ring:SetSize(TARGET_SIZE + 8, TARGET_SIZE + 8)
    frame.bg:Show()
    frame.ring:Show()
    frame.icon:Hide()
    frame.model:Hide()
    frame.modelHit:Hide()
    frame.dbgHit:Hide()
    frame.unitPin:Hide()
    frame.label:SetText("")
    frame.targetID = nil
    frame.baseColor = nil
    if hoveredTargetID == frame.targetID then
        hoveredTargetID = nil
    end
    tinsert(targetPool, frame)
end

function PingGameUI:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function PingGameUI:Toggle()
    local PG = ns.PingGame
    if not PG then return end

    if PG:IsRunning() then
        PG:Stop()
        return
    end

    if mainFrame and mainFrame:IsShown() then
        mainFrame:Hide()
        return
    end

    if not mainFrame then
        self:CreateUI()
    end
    self:ShowStartScreen()
    mainFrame:Show()
end

function PingGameUI:CreateUI()
    mainFrame = CreateFrame("Frame", "BoundToLearnPingGame", UIParent)
    mainFrame:SetSize(GAME_WIDTH + 20, GAME_HEIGHT + 90)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("HIGH")
    ns.Theme.StylePanel(mainFrame)
    -- The picked expansion's backdrop behind the start screen (the round has its
    -- own in the arena), dimmed so the labels and panels stay readable.
    local backdrop = mainFrame:CreateTexture(nil, "ARTWORK")
    backdrop:SetPoint("TOPLEFT", 7, -7)
    backdrop:SetPoint("BOTTOMRIGHT", -7, 7)
    backdrop:SetAlpha(0.85)
    backdrop:SetVertexColor(0.7, 0.7, 0.72)
    mainFrame.backdropTex = backdrop
    mainFrame:SetMovable(true)
    mainFrame:EnableMouse(true)
    mainFrame:RegisterForDrag("LeftButton")
    mainFrame:SetScript("OnDragStart", function(self)
        if IsShiftKeyDown() then
            self:StartMoving()
        end
    end)
    mainFrame:SetScript("OnDragStop", mainFrame.StopMovingOrSizing)
    -- A ping bound anywhere (this window or the client's Key Bindings) updates
    -- the key list and the Start button while the window is open.
    mainFrame:RegisterEvent("UPDATE_BINDINGS")
    mainFrame:SetScript("OnEvent", function(self, event)
        if event == "UPDATE_BINDINGS" and self:IsShown() and startFrame and startFrame:IsShown() then
            PingGameUI:UpdateKeybindDisplay()
            PingGameUI:UpdateStartButton()
        end
    end)
    mainFrame:Hide()
    mainFrame:SetScript("OnHide", function()
        -- Closing the window ends a round still in play (or paused).
        local PG = ns.PingGame
        if PG and PG:IsRunning() then PG:Stop() end
        StopBackgroundMusic()
    end)

    Utils.CloseOnEscape(mainFrame)

    -- Title
    local title = ns.Theme.CreateTitle(mainFrame, "Ping Trainer", 20)
    title:SetPoint("TOP", 0, -11)   -- below the window's border band (11)

    -- Drag hint at upper right
    local dragHint = mainFrame:CreateFontString(nil, "OVERLAY")
    dragHint:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    dragHint:SetPoint("TOPRIGHT", -28, -12)
    dragHint:SetTextColor(0.55, 0.55, 0.55)
    dragHint:SetText("Shift+drag to move")

    -- Close button
    local closeBtn = ns.Theme.CreateCloseButton(mainFrame, function()
        local PG = ns.PingGame
        if PG and PG:IsRunning() then PG:Stop() end
        mainFrame:Hide()
    end)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- HUD
    hudFrame = CreateFrame("Frame", nil, mainFrame)
    hudFrame:SetSize(GAME_WIDTH, 20)
    hudFrame:SetPoint("TOP", 0, -32)
    hudFrame:Hide()

    scoreText = hudFrame:CreateFontString(nil, "OVERLAY")
    scoreText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    scoreText:SetPoint("LEFT", 10, 0)
    scoreText:SetTextColor(ns.Theme.RGB(ns.Theme.C.GOLD))

    timerText = hudFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    timerText:SetPoint("CENTER")
    timerText:SetTextColor(0.8, 0.8, 0.8)

    comboText = hudFrame:CreateFontString(nil, "OVERLAY")
    comboText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    comboText:SetPoint("RIGHT", -60, 0)
    comboText:SetTextColor(ns.Theme.RGB(ns.Theme.C.ACCENT))

    -- Sound toggle helpers for HUD
    local function CreateSoundToggle(parent, label, getState, setState, xOff, tooltip)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(36, 14)
        btn:SetPoint("RIGHT", xOff, 0)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        fs:SetAllPoints()
        btn.label = fs
        btn.getState = getState
        btn.setState = setState
        btn.baseName = label
        local function Refresh()
            local muted = getState()
            fs:SetText(muted and ("|cFF666666" .. label .. "|r") or ("|cFF88CC88" .. label .. "|r"))
        end
        btn:SetScript("OnClick", function()
            setState(not getState())
            Refresh()
        end)
        if tooltip then
            btn:SetScript("OnEnter", function(self)
                self.hovering = true
                C_Timer.After(0.4, function()
                    if not self.hovering then return end
                    GameTooltip:SetOwner(self, "ANCHOR_TOP")
                    GameTooltip:AddLine(label)
                    GameTooltip:AddLine(tooltip, 0.8, 0.8, 0.8, true)
                    GameTooltip:Show()
                end)
            end)
            btn:SetScript("OnLeave", function(self)
                self.hovering = false
                GameTooltip:Hide()
            end)
        end
        btn.Refresh = Refresh
        Refresh()
        return btn
    end

    local hudMusicBtn = CreateSoundToggle(hudFrame, "Music", IsMusicMuted, ToggleMuteMusic, -130,
        "Background music while you play.")
    local hudPingBtn = CreateSoundToggle(hudFrame, "SFX", IsPingSoundMuted, ToggleMutePingSounds, -90,
        "Sound effects: the ping and alert sounds during play. Music is a separate toggle.")
    hudFrame.musicBtn = hudMusicBtn
    hudFrame.pingBtn = hudPingBtn

    local stopBtn = CreateFrame("Button", nil, hudFrame)
    stopBtn:SetSize(44, 18)
    stopBtn:SetPoint("RIGHT", -6, 0)
    stopBtn:SetNormalFontObject("GameFontNormalSmall")
    stopBtn:SetText("|cFFCC3333Stop|r")
    stopBtn:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    stopBtn:SetScript("OnClick", function()
        local PG = ns.PingGame
        if PG and PG:IsRunning() then
            C_Timer.After(0, function() PG:Stop() end)
        end
    end)
    stopBtn:SetScript("OnEnter", function(self)
        self:SetText("|cFFFF5555Stop|r")
    end)
    stopBtn:SetScript("OnLeave", function(self)
        self:SetText("|cFFCC3333Stop|r")
    end)

    -- Game area with background
    gameArea = CreateFrame("Frame", nil, mainFrame, "BackdropTemplate")
    gameArea._btlNoLayoutCheck = true   -- targets spawn anywhere, over each other
    gameArea:SetSize(GAME_WIDTH, GAME_HEIGHT)
    gameArea:SetPoint("TOP", 0, -54)
    gameArea:SetBackdrop({
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    gameArea:SetBackdropBorderColor(ns.Theme.RGB(ns.Theme.C.BORDER, 0.7))

    -- Arena-style background texture
    local bgTex = gameArea:CreateTexture(nil, "BACKGROUND")
    bgTex:SetAllPoints()
    ApplyBackground(bgTex, GetSelectedBackground())
    bgTex:SetVertexColor(0.8, 0.8, 0.8, 1)
    gameArea.bgTex = bgTex

    -- Subtle overlay to keep targets readable
    local overlay = gameArea:CreateTexture(nil, "BACKGROUND", nil, 1)
    overlay:SetAllPoints()
    overlay:SetColorTexture(0, 0, 0, 0.05)

    -- Keybind input frame (captures ping keys during gameplay)
    local inputFrame = CreateFrame("Frame", nil, gameArea)
    inputFrame:SetAllPoints()
    inputFrame:EnableKeyboard(true)
    inputFrame:SetPropagateKeyboardInput(true)
    inputFrame:Hide()
    gameArea.inputFrame = inputFrame

    inputFrame:SetScript("OnKeyDown", function(_, key)
        if key == "ESCAPE" then
            inputFrame:SetPropagateKeyboardInput(false)
            local PG = ns.PingGame
            if PG and PG:IsRunning() then
                C_Timer.After(0, function() PG:Stop() end)
            end
            return
        end

        -- Build full key with modifiers
        local fullKey = ""
        if IsAltKeyDown() then fullKey = fullKey .. "ALT-" end
        if IsControlKeyDown() then fullKey = fullKey .. "CTRL-" end
        if IsShiftKeyDown() then fullKey = fullKey .. "SHIFT-" end
        fullKey = fullKey .. key

        local PG = ns.PingGame
        if not PG then
            inputFrame:SetPropagateKeyboardInput(true)
            return
        end

        local pingKeybinds = PG:GetPingKeybinds()
        local pingAction = pingKeybinds[fullKey]

        if pingAction then
            inputFrame:SetPropagateKeyboardInput(false)
            if hoveredTargetID then
                PG:OnPingAction(hoveredTargetID, pingAction)
            else
                PG:OnPingMiss(pingAction)
            end
        else
            inputFrame:SetPropagateKeyboardInput(true)
        end
    end)

    -- Pause overlay
    pauseOverlay = CreateFrame("Frame", nil, gameArea)
    pauseOverlay:SetAllPoints()
    pauseOverlay:SetFrameLevel(gameArea:GetFrameLevel() + 20)
    pauseOverlay:EnableMouse(true)
    pauseOverlay:Hide()

    local pauseBG = pauseOverlay:CreateTexture(nil, "BACKGROUND")
    pauseBG:SetAllPoints()
    pauseBG:SetColorTexture(0, 0, 0, 0.7)

    local pauseLabel = pauseOverlay:CreateFontString(nil, "OVERLAY")
    pauseLabel:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    pauseLabel:SetPoint("CENTER", 0, 10)
    pauseLabel:SetText("|cFFFFD700Paused|r")

    local resumeBtn = ns.Theme.CreateButton(pauseOverlay, "Resume", 100, 24)
    resumeBtn:SetPoint("CENTER", 0, -20)
    resumeBtn:SetScript("OnClick", function()
        local PG = ns.PingGame
        if PG then PG:Resume() end
    end)

    -- Health bar (between game area bottom and window bottom)
    local healthFrame = CreateFrame("Frame", nil, mainFrame)
    healthFrame:SetSize(GAME_WIDTH - 40, 14)
    healthFrame:SetPoint("TOP", gameArea, "BOTTOM", 0, -6)
    healthFrame:Hide()

    local healthBG = healthFrame:CreateTexture(nil, "BACKGROUND")
    healthBG:SetAllPoints()
    healthBG:SetColorTexture(0.15, 0.15, 0.15, 0.8)

    local healthBar = healthFrame:CreateTexture(nil, "ARTWORK")
    healthBar:SetPoint("TOPLEFT", 1, -1)
    healthBar:SetPoint("BOTTOMLEFT", 1, 1)
    healthBar:SetWidth(healthFrame:GetWidth() - 2)
    healthBar:SetColorTexture(0.2, 0.8, 0.2, 0.9)
    healthFrame.bar = healthBar

    -- Thin border lines around health bar
    local borderTop = healthFrame:CreateTexture(nil, "OVERLAY")
    borderTop:SetHeight(1)
    borderTop:SetPoint("TOPLEFT")
    borderTop:SetPoint("TOPRIGHT")
    borderTop:SetColorTexture(0.4, 0.4, 0.4, 0.7)
    local borderBot = healthFrame:CreateTexture(nil, "OVERLAY")
    borderBot:SetHeight(1)
    borderBot:SetPoint("BOTTOMLEFT")
    borderBot:SetPoint("BOTTOMRIGHT")
    borderBot:SetColorTexture(0.4, 0.4, 0.4, 0.7)

    local healthText = healthFrame:CreateFontString(nil, "OVERLAY")
    healthText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    healthText:SetPoint("CENTER")
    healthText:SetTextColor(0.9, 0.9, 0.9)
    healthFrame.text = healthText

    mainFrame.healthFrame = healthFrame

    self:CreateStartScreen()
    self:CreateResultsScreen()
end

function PingGameUI:CreateStartScreen()
    startFrame = CreateFrame("Frame", nil, mainFrame)
    startFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -36)
    startFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 14)

    -- ===== Top: 3 showcase models side by side =====
    local SHOWCASE_H = 200
    local showcaseRow = CreateFrame("Frame", nil, startFrame)
    showcaseRow:SetPoint("TOPLEFT", 0, 0)
    showcaseRow:SetPoint("TOPRIGHT", 0, 0)
    showcaseRow:SetHeight(SHOWCASE_H)

    local SHOWCASE = {
        { npcID = 3296,  anim = 26,  facing = 0.3,  kit = "Attack",  label = "Attack",  color = {1, 0.27, 0.27}, targetType = TARGET_ENEMY },
        { npcID = 68,    anim = 225, facing = -0.2, kit = "Assist",  label = "Assist",  color = {0.27, 0.8, 0.27}, targetType = TARGET_ALLY },
        { npcID = 5953,  anim = 4,   facing = 0.15, kit = "Warning", label = "Warning", color = {1, 0.8, 0}, targetType = TARGET_HAZARD },
    }

    startFrame.showcaseCells = {}
    local showcaseWidth = GAME_WIDTH - 20
    local cellWidth = mfloor(showcaseWidth / 3)
    for i, sc in ipairs(SHOWCASE) do
        local cellCenter = (i - 1) * cellWidth + cellWidth / 2

        local modelFrame = CreateFrame("PlayerModel", nil, showcaseRow)
        modelFrame:SetSize(90, 130)
        modelFrame:SetPoint("BOTTOM", showcaseRow, "BOTTOMLEFT", cellCenter, 34)
        modelFrame:EnableMouse(false)
        modelFrame:SetPortraitZoom(0)
        modelFrame:SetCamDistanceScale(1.5)
        modelFrame:SetPosition(0, 0, -0.5)
        modelFrame:SetCreature(sc.npcID)
        local capturedFacing, capturedAnim = sc.facing, sc.anim
        modelFrame:SetScript("OnModelLoaded", function(self)
            self:SetFacing(capturedFacing)
            self:SetAnimation(capturedAnim)
            self:SetScript("OnModelLoaded", nil)
        end)

        -- Portraits style: a race/hazard icon in the same spot as the model.
        local portraitIcon = showcaseRow:CreateTexture(nil, "ARTWORK")
        portraitIcon:SetSize(74, 74)
        portraitIcon:SetPoint("CENTER", modelFrame, "CENTER", 0, 8)
        portraitIcon:Hide()

        -- Blobs style: a soft colored circle with a short label.
        local blob = showcaseRow:CreateTexture(nil, "ARTWORK")
        blob:SetTexture("Interface\\COMMON\\Indicator-Gray")
        blob:SetSize(66, 66)
        blob:SetPoint("CENTER", modelFrame, "CENTER", 0, 8)
        blob:SetVertexColor(sc.color[1], sc.color[2], sc.color[3], 0.95)
        blob:Hide()
        local blobLabel = showcaseRow:CreateFontString(nil, "OVERLAY")
        blobLabel:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        blobLabel:SetPoint("CENTER", blob, "CENTER", 0, 0)
        blobLabel:SetText(TARGET_LABELS[sc.targetType])
        blobLabel:SetTextColor(1, 1, 1)
        blobLabel:Hide()

        local pingIcon = showcaseRow:CreateTexture(nil, "OVERLAY")
        pingIcon:SetSize(36, 36)
        pingIcon:SetPoint("BOTTOM", modelFrame, "TOP", 0, -18)
        pingIcon:SetAtlas("Ping_Marker_Icon_" .. sc.kit)

        local barBG = showcaseRow:CreateTexture(nil, "ARTWORK", nil, 1)
        barBG:SetSize(60, 3)
        barBG:SetPoint("TOP", modelFrame, "BOTTOM", 0, -2)
        barBG:SetColorTexture(0.2, 0.2, 0.2, 0.6)

        local barFill = showcaseRow:CreateTexture(nil, "OVERLAY")
        barFill:SetSize(58, 3)
        barFill:SetPoint("LEFT", barBG, "LEFT", 1, 0)
        barFill:SetColorTexture(sc.color[1], sc.color[2], sc.color[3], 0.8)

        local typeLabel = showcaseRow:CreateFontString(nil, "OVERLAY")
        typeLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        typeLabel:SetPoint("TOP", barBG, "BOTTOM", 0, -3)
        typeLabel:SetTextColor(sc.color[1], sc.color[2], sc.color[3])
        typeLabel:SetText(sc.label)

        startFrame.showcaseCells[i] = {
            model = modelFrame, portrait = portraitIcon, blob = blob, blobLabel = blobLabel,
            targetType = sc.targetType, npcID = sc.npcID, facing = sc.facing, anim = sc.anim,
        }
    end

    -- ===== Middle section =====
    local midY = -SHOWCASE_H - 26

    -- Left side: brief description in bordered box
    local panelY = midY - 30
    local descBox = CreateFrame("Frame", nil, startFrame)
    descBox:SetSize(155, 86)
    descBox:SetPoint("TOPLEFT", 10, panelY)
    ns.Theme.StyleCard(descBox)

    local descTitle = descBox:CreateFontString(nil, "OVERLAY")
    descTitle:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    descTitle:SetPoint("BOTTOM", descBox, "TOP", 0, 2)
    descTitle:SetTextColor(1, 0.82, 0)
    descTitle:SetText("How to Play")

    local descText = descBox:CreateFontString(nil, "OVERLAY")
    descText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    descText:SetPoint("TOPLEFT", 8, -8)
    descText:SetPoint("BOTTOMRIGHT", -8, 8)
    descText:SetJustifyH("LEFT")
    descText:SetJustifyV("TOP")
    descText:SetSpacing(3)
    descText:SetTextColor(0.8, 0.8, 0.8)
    descText:SetText("Hover a target and press\nthe matching ping key.\nBuild combos for bonus\npoints. Train your aim\nand reaction time.")

    -- Center: Difficulty buttons
    startFrame.diffBtns = {}
    local diffs = ns.PingGame and ns.PingGame.DIFFICULTIES or { "Easy", "Normal", "Hard", "Extreme" }
    local diffCount = #diffs
    local diffBtnW = 60
    local diffGap = 7
    local diffTotalW = diffCount * diffBtnW + (diffCount - 1) * diffGap
    local diffStartX = (GAME_WIDTH - diffTotalW) / 2

    for i, name in ipairs(diffs) do
        local btn = CreateFrame("Button", nil, startFrame)
        btn:SetSize(diffBtnW, 22)
        btn:SetPoint("TOPLEFT", diffStartX + (i - 1) * (diffBtnW + diffGap), midY)
        ns.Theme.StyleCard(btn)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(name)
        btn.diffName = name
        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            if ns.PingGame then ns.PingGame:SetDifficulty(name) end
            self:UpdateDiffButtons()
        end)
        startFrame.diffBtns[i] = btn
    end

    -- Right side: Settings in bordered box (stacked sections)
    local settingsBox = CreateFrame("Frame", nil, startFrame)
    settingsBox:SetSize(175, 130)
    settingsBox:SetPoint("TOPRIGHT", -10, panelY)
    ns.Theme.StyleCard(settingsBox)

    local settingsTitle = settingsBox:CreateFontString(nil, "OVERLAY")
    settingsTitle:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    settingsTitle:SetPoint("BOTTOM", settingsBox, "TOP", 0, 2)
    settingsTitle:SetTextColor(1, 0.82, 0)
    settingsTitle:SetText("Settings")

    local boxW = 175
    local optBtnW = 55
    local secY = -6
    local divInset = 6

    local function CreateSectionDivider(yOff)
        local div = settingsBox:CreateTexture(nil, "ARTWORK")
        div:SetHeight(1)
        div:SetPoint("TOPLEFT", divInset, yOff)
        div:SetPoint("TOPRIGHT", -divInset, yOff)
        div:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    end

    -- Section 1: Style (centered header, options below)
    local styleHeader = settingsBox:CreateFontString(nil, "OVERLAY")
    styleHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    styleHeader:SetPoint("TOP", 0, secY)
    styleHeader:SetTextColor(1, 0.82, 0)
    styleHeader:SetText("Style")
    CreateSectionDivider(secY - 13)

    local STYLE_DEFS = {
        { id = "portraits", label = "Portraits" },
        { id = "3d",        label = "3D Models" },
        { id = "blobs",     label = "Blobs" },
    }
    local styleOptW = 3 * optBtnW
    local styleStartX = (boxW - styleOptW) / 2
    startFrame.styleBtns = {}
    for i, def in ipairs(STYLE_DEFS) do
        local btn = CreateFrame("Button", nil, settingsBox)
        btn:SetSize(optBtnW, 14)
        btn:SetPoint("TOPLEFT", styleStartX + (i - 1) * optBtnW, secY - 14)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(def.label)
        btn.styleID = def.id
        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            if BoundToLearn.db and BoundToLearn.db.pingTrainer then
                BoundToLearn.db.pingTrainer.targetStyle = def.id
            end
            PingGameUI:UpdateStyleButtons()
        end)
        startFrame.styleBtns[i] = btn
    end

    -- Section 2: Music (centered header, On/Off below)
    local secY2 = secY - 36
    local musicHeader = settingsBox:CreateFontString(nil, "OVERLAY")
    musicHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    musicHeader:SetPoint("TOP", 0, secY2)
    musicHeader:SetTextColor(1, 0.82, 0)
    musicHeader:SetText("Music")
    CreateSectionDivider(secY2 - 13)

    local toggleW = 2 * optBtnW
    local toggleStartX = (boxW - toggleW) / 2

    local function CreateToggleOption(parent, xOff, yOff, label, isActive, onClick)
        local btn = CreateFrame("Button", nil, parent)
        btn:SetSize(optBtnW, 14)
        btn:SetPoint("TOPLEFT", xOff, yOff)
        local fs = btn:CreateFontString(nil, "OVERLAY")
        fs:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        fs:SetAllPoints()
        btn.label = fs
        btn.optLabel = label
        btn.isActiveFunc = isActive
        btn.onClick = onClick
        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            onClick()
            PingGameUI:UpdateSoundButtons()
        end)
        return btn
    end

    local musicOnBtn = CreateToggleOption(settingsBox, toggleStartX, secY2 - 14, "On",
        function() return not IsMusicMuted() end,
        function() if IsMusicMuted() then ToggleMuteMusic(false) end end)
    local musicOffBtn = CreateToggleOption(settingsBox, toggleStartX + optBtnW, secY2 - 14, "Off",
        function() return IsMusicMuted() end,
        function() if not IsMusicMuted() then ToggleMuteMusic(true) end end)

    -- Section 3: Ping SFX (centered header, On/Off below). Named "Ping SFX"
    -- rather than "Sound" so it is not confused with the Music toggle above.
    local secY3 = secY2 - 36
    local soundHeader = settingsBox:CreateFontString(nil, "OVERLAY")
    soundHeader:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    soundHeader:SetPoint("TOP", 0, secY3)
    soundHeader:SetTextColor(1, 0.82, 0)
    soundHeader:SetText("Ping SFX")
    CreateSectionDivider(secY3 - 13)

    local sfxOnBtn = CreateToggleOption(settingsBox, toggleStartX, secY3 - 14, "On",
        function() return not IsPingSoundMuted() end,
        function() if IsPingSoundMuted() then ToggleMutePingSounds(false) end end)
    local sfxOffBtn = CreateToggleOption(settingsBox, toggleStartX + optBtnW, secY3 - 14, "Off",
        function() return IsPingSoundMuted() end,
        function() if not IsPingSoundMuted() then ToggleMutePingSounds(true) end end)

    startFrame.soundToggleBtns = { musicOnBtn, musicOffBtn, sfxOnBtn, sfxOffBtn }

    -- ===== Start button (centered, above bottom section) =====
    local startBtn = ns.Theme.CreateAccentButton(startFrame, "Start", 180, 42)
    startBtn:SetPoint("BOTTOM", 0, 110)
    startBtn:SetNormalFontObject("GameFontNormalLarge")
    startBtn:SetHighlightFontObject("GameFontHighlightLarge")
    startBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        if ns.PingGame then ns.PingGame:Start() end
    end)
    startFrame.startBtn = startBtn
    -- Disabled until all three pings are bound; the tooltip names what's missing.
    startBtn:SetMotionScriptsWhileDisabled(true)
    startBtn:HookScript("OnEnter", function(self)
        if self:IsEnabled() then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Bind your pings first")
        local missing = ns.PingGame and ns.PingGame:GetUnboundPingNames()
        if missing and #missing > 0 then
            local list = missing[1]
            for i = 2, #missing do list = list .. ", " .. missing[i] end
            GameTooltip:AddLine("Not bound: " .. list, 1, 0.82, 0, true)
        end
        GameTooltip:AddLine("Set your Attack, Assist, and Warning pings in Key Bindings.", 0.8, 0.8, 0.8, true)
        GameTooltip:Show()
    end)
    startBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)

    -- ===== Map dropdown below start button =====
    local mapLabel = startFrame:CreateFontString(nil, "OVERLAY")
    mapLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    mapLabel:SetPoint("BOTTOM", startBtn, "BOTTOM", -100, -24)
    mapLabel:SetText("|cFFFFD700Expansion|r")

    local mapBtn = CreateFrame("Button", nil, startFrame)
    mapBtn:SetSize(165, 20)
    mapBtn:SetPoint("LEFT", mapLabel, "RIGHT", 6, 0)
    ns.Theme.StyleCard(mapBtn)

    local mapBtnText = mapBtn:CreateFontString(nil, "OVERLAY")
    mapBtnText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    mapBtnText:SetPoint("LEFT", 6, 0)
    mapBtnText:SetTextColor(0.85, 0.85, 0.85)
    mapBtn.text = mapBtnText

    local mapArrow = mapBtn:CreateFontString(nil, "OVERLAY")
    mapArrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    mapArrow:SetPoint("RIGHT", -6, 0)
    mapArrow:SetTextColor(0.6, 0.6, 0.6)
    mapArrow:SetText("v")

    -- Dropdown opens upward (above the button) to avoid clipping bottom
    local mapDropdown = CreateFrame("Frame", nil, mapBtn)
    mapDropdown:SetPoint("BOTTOMLEFT", mapBtn, "TOPLEFT", 0, 2)
    mapDropdown:SetWidth(205)
    local dropdownRowH = 18
    local dropdownRows = #BACKGROUNDS + 1
    mapDropdown:SetHeight(dropdownRows * dropdownRowH + 6)
    ns.Theme.StyleCard(mapDropdown, ns.Theme.C.PANEL_DARK)
    mapDropdown:SetFrameLevel(mapBtn:GetFrameLevel() + 10)
    mapDropdown:Hide()

    startFrame.bgBtns = {}
    for i, bg in ipairs(BACKGROUNDS) do
        local row = CreateFrame("Button", nil, mapDropdown)
        row:SetHeight(dropdownRowH)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * dropdownRowH)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * dropdownRowH)

        local nameFS = row:CreateFontString(nil, "OVERLAY")
        nameFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        nameFS:SetPoint("LEFT", 4, 0)
        row.nameFS = nameFS

        local lockFS = row:CreateFontString(nil, "OVERLAY")
        lockFS:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        lockFS:SetPoint("RIGHT", -4, 0)
        row.lockFS = lockFS

        local rowHL = row:CreateTexture(nil, "BACKGROUND")
        rowHL:SetAllPoints()
        rowHL:SetColorTexture(1, 1, 1, 0.08)
        rowHL:Hide()
        row.highlight = rowHL

        row.bgID = bg.id
        row.bgIndex = i
        row:SetScript("OnClick", function()
            if not IsBackgroundUnlocked(bg.id) then return end
            PlayUISound(SOUND_CLICK)
            local pt = GetPingTrainerDB()
            if pt then
                pt.background = bg.id
                pt.randomBG = false
            end
            mapDropdown:Hide()
            PingGameUI:UpdateBackgroundButtons()
        end)
        row:SetScript("OnEnter", function(self)
            if IsBackgroundUnlocked(bg.id) then self.highlight:Show() end
        end)
        row:SetScript("OnLeave", function(self)
            self.highlight:Hide()
        end)
        startFrame.bgBtns[i] = row
    end

    -- Random toggle row
    local randomRow = CreateFrame("Button", nil, mapDropdown)
    randomRow:SetHeight(dropdownRowH)
    randomRow:SetPoint("TOPLEFT", 3, -3 - #BACKGROUNDS * dropdownRowH)
    randomRow:SetPoint("TOPRIGHT", -3, -3 - #BACKGROUNDS * dropdownRowH)

    local randomHL = randomRow:CreateTexture(nil, "BACKGROUND")
    randomHL:SetAllPoints()
    randomHL:SetColorTexture(1, 1, 1, 0.08)
    randomHL:Hide()

    local randomFS = randomRow:CreateFontString(nil, "OVERLAY")
    randomFS:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
    randomFS:SetPoint("LEFT", 4, 0)
    startFrame.randomBGBtn = randomRow
    randomRow.label = randomFS
    randomRow:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        local pt = GetPingTrainerDB()
        if pt then pt.randomBG = not pt.randomBG end
        mapDropdown:Hide()
        PingGameUI:UpdateBackgroundButtons()
    end)
    randomRow:SetScript("OnEnter", function() randomHL:Show() end)
    randomRow:SetScript("OnLeave", function() randomHL:Hide() end)

    mapBtn:SetScript("OnClick", function()
        if mapDropdown:IsShown() then
            mapDropdown:Hide()
        else
            PingGameUI:UpdateBackgroundButtons()
            mapDropdown:Show()
        end
    end)
    mapBtn:SetScript("OnEnter", function(self)
        ns.Theme.SetFillColor(self, ns.Theme.C.BTN_HOVER)
    end)
    mapBtn:SetScript("OnLeave", function(self)
        ns.Theme.SetFillColor(self, ns.Theme.C.SECTION_FILL)
    end)

    startFrame.mapBtn = mapBtn
    startFrame.mapDropdown = mapDropdown

    -- ===== Bottom: Horizontal keybind bar =====
    local bindBar = CreateFrame("Frame", nil, startFrame)
    bindBar:SetHeight(30)
    bindBar:SetPoint("BOTTOMLEFT", 0, 12)
    bindBar:SetPoint("BOTTOMRIGHT", 0, 12)

    -- Thin divider above keybinds
    local bindDiv = bindBar:CreateTexture(nil, "ARTWORK")
    bindDiv:SetHeight(1)
    bindDiv:SetPoint("TOPLEFT", 20, 0)
    bindDiv:SetPoint("TOPRIGHT", -20, 0)
    bindDiv:SetColorTexture(0.35, 0.35, 0.35, 0.4)

    local PING_BIND_DEFS = {
        { label = "Attack",  binding = "PINGATTACK",  color = { 1, 0.27, 0.27 } },
        { label = "Assist",  binding = "PINGASSIST",  color = { 0.27, 0.8, 0.27 } },
        { label = "Warning", binding = "PINGWARNING", color = { 1, 0.8, 0 } },
    }

    startFrame.keybindBtns = {}
    local bindingInProgress = nil
    local bindCount = #PING_BIND_DEFS
    local bindCellW = mfloor((GAME_WIDTH - 20) / bindCount)

    for i, def in ipairs(PING_BIND_DEFS) do
        local cellCenter = (i - 1) * bindCellW + bindCellW / 2

        local label = bindBar:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        label:SetPoint("BOTTOM", bindBar, "BOTTOMLEFT", cellCenter - 40, 4)
        label:SetTextColor(def.color[1], def.color[2], def.color[3])
        label:SetText(def.label)

        local bindBtn = CreateFrame("Button", nil, bindBar)
        bindBtn:SetSize(80, 18)
        bindBtn:SetPoint("LEFT", label, "RIGHT", 4, 0)
        ns.Theme.StyleCard(bindBtn)

        local keyText = bindBtn:CreateFontString(nil, "OVERLAY")
        keyText:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        keyText:SetPoint("CENTER")
        keyText:SetTextColor(0.85, 0.85, 0.85)
        bindBtn.keyText = keyText
        bindBtn.bindingName = def.binding
        bindBtn.defColor = def.color

        bindBtn:SetScript("OnClick", function(self)
            if bindingInProgress and bindingInProgress ~= self then
                bindingInProgress.keyText:SetText(GetBindingKey(bindingInProgress.bindingName) or "unbound")
                bindingInProgress.keyText:SetTextColor(0.85, 0.85, 0.85)
                ns.Theme.SetFillColor(bindingInProgress, ns.Theme.C.SECTION_FILL)
            end
            bindingInProgress = self
            self.keyText:SetText("|cFFFFD700Press a key...|r")
            ns.Theme.SetFill(self, 0.4, 0.32, 0.1, 0.9)
            self:EnableKeyboard(true)
        end)

        bindBtn:SetScript("OnKeyDown", function(self, key)
            if not bindingInProgress or bindingInProgress ~= self then
                self:SetPropagateKeyboardInput(true)
                return
            end
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                self:EnableKeyboard(false)
                self.keyText:SetText(GetBindingKey(self.bindingName) or "|cFF666666unbound|r")
                self.keyText:SetTextColor(0.85, 0.85, 0.85)
                ns.Theme.SetFillColor(self, ns.Theme.C.SECTION_FILL)
                bindingInProgress = nil
                return
            end
            if key == "LSHIFT" or key == "RSHIFT" or key == "LCTRL" or key == "RCTRL" or key == "LALT" or key == "RALT" then
                self:SetPropagateKeyboardInput(true)
                return
            end
            self:SetPropagateKeyboardInput(false)
            local fullKey = ""
            if IsAltKeyDown() then fullKey = fullKey .. "ALT-" end
            if IsControlKeyDown() then fullKey = fullKey .. "CTRL-" end
            if IsShiftKeyDown() then fullKey = fullKey .. "SHIFT-" end
            fullKey = fullKey .. key
            if SetBinding(fullKey, self.bindingName) then
                SaveBindings(GetCurrentBindingSet())
            end
            self:EnableKeyboard(false)
            ns.Theme.SetFillColor(self, ns.Theme.C.SECTION_FILL)
            bindingInProgress = nil
            if ns.PingGame and ns.PingGame.HasPingKeybinds then
                ns.PingGame:Initialize()
            end
            -- Show what the client now holds (not the key pressed), and let
            -- Start light up as soon as the last ping is bound.
            PingGameUI:UpdateKeybindDisplay()
            PingGameUI:UpdateStartButton()
        end)

        bindBtn:SetScript("OnEnter", function(self)
            if bindingInProgress ~= self then
                ns.Theme.SetFillColor(self, ns.Theme.C.BTN_HOVER)
            end
        end)
        bindBtn:SetScript("OnLeave", function(self)
            if bindingInProgress ~= self then
                ns.Theme.SetFillColor(self, ns.Theme.C.SECTION_FILL)
            end
        end)

        startFrame.keybindBtns[i] = bindBtn
    end

    local function CancelBinding()
        if bindingInProgress then
            bindingInProgress:EnableKeyboard(false)
            bindingInProgress.keyText:SetText(GetBindingKey(bindingInProgress.bindingName) or "|cFF666666unbound|r")
            bindingInProgress.keyText:SetTextColor(0.85, 0.85, 0.85)
            ns.Theme.SetFillColor(bindingInProgress, ns.Theme.C.SECTION_FILL)
            bindingInProgress = nil
        end
    end
    startFrame:SetScript("OnHide", function()
        CancelBinding()
        if mapDropdown then mapDropdown:Hide() end
    end)
    -- A key capture cannot be released in a fight; drop it at the pull.
    startFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    startFrame:SetScript("OnEvent", CancelBinding)

    startFrame:Hide()
end

function PingGameUI:CreateResultsScreen()
    resultsFrame = CreateFrame("Frame", nil, mainFrame)
    resultsFrame:SetPoint("TOPLEFT", mainFrame, "TOPLEFT", 10, -48)
    resultsFrame:SetPoint("BOTTOMRIGHT", mainFrame, "BOTTOMRIGHT", -10, 10)
    resultsFrame:Hide()

    local scoreLabel = resultsFrame:CreateFontString(nil, "OVERLAY")
    scoreLabel:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
    scoreLabel:SetPoint("TOP", 0, -20)
    resultsFrame.scoreLabel = scoreLabel

    local statsText = resultsFrame:CreateFontString(nil, "OVERLAY")
    statsText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    statsText:SetPoint("TOP", scoreLabel, "BOTTOM", 0, -16)
    statsText:SetWidth(GAME_WIDTH - 60)
    statsText:SetJustifyH("CENTER")
    statsText:SetSpacing(4)
    resultsFrame.statsText = statsText

    local gradeLabel = resultsFrame:CreateFontString(nil, "OVERLAY")
    gradeLabel:SetFont("Fonts\\FRIZQT__.TTF", 36, "OUTLINE")
    gradeLabel:SetPoint("TOP", statsText, "BOTTOM", 0, -16)
    resultsFrame.gradeLabel = gradeLabel

    local retryBtn = ns.Theme.CreateAccentButton(resultsFrame, "Play Again", 100, 24)
    retryBtn:SetPoint("BOTTOM", 60, 20)
    retryBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        if ns.PingGame then ns.PingGame:Start() end
    end)

    local backBtn = ns.Theme.CreateButton(resultsFrame, "Back", 80, 24)
    backBtn:SetPoint("BOTTOM", -60, 20)
    backBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        self:ShowStartScreen()
    end)
end

-- The window backdrop follows the Expansion pick. With Random on, one pick is
-- kept per visit (force = a new visit) so it does not change on every click.
function PingGameUI:UpdateStartBackdrop(force)
    local tex = mainFrame and mainFrame.backdropTex
    if not tex then return end
    local pt = GetPingTrainerDB()
    if pt and pt.randomBG and tex.bgID and not force then return end
    local bg = GetSelectedBackground()
    ApplyBackground(tex, bg)
    tex.bgID = bg and bg.id
end

function PingGameUI:UpdateBackgroundButtons()
    self:UpdateStartBackdrop()
    if not startFrame or not startFrame.bgBtns then return end
    local pt = GetPingTrainerDB()
    local selectedID = pt and pt.background or "classic"
    local isRandom = pt and pt.randomBG
    local selectedName = BACKGROUNDS[1].name

    for i, btn in ipairs(startFrame.bgBtns) do
        local bg = BACKGROUNDS[i]
        local unlocked = IsBackgroundUnlocked(bg.id)
        local selected = (not isRandom) and (bg.id == selectedID)

        if selected then selectedName = bg.name end

        if unlocked then
            btn.nameFS:SetText(bg.name)
            btn.lockFS:SetText("")
            if selected then
                btn.nameFS:SetTextColor(0.33, 0.8, 1)
            else
                btn.nameFS:SetTextColor(0.75, 0.75, 0.75)
            end
        else
            btn.nameFS:SetText("|cFF555555" .. bg.name .. "|r")
            btn.lockFS:SetText("|cFF666666" .. bg.unlock.label .. "|r")
        end
    end

    if startFrame.randomBGBtn then
        if isRandom then
            startFrame.randomBGBtn.label:SetText("Random: |cFF88CC88On|r")
        else
            startFrame.randomBGBtn.label:SetText("Random: |cFF666666Off|r")
        end
    end

    -- Update the map dropdown button text
    if startFrame.mapBtn and startFrame.mapBtn.text then
        if isRandom then
            startFrame.mapBtn.text:SetText("Random")
        else
            startFrame.mapBtn.text:SetText(selectedName)
        end
    end
end

function PingGameUI:UpdateKeybindDisplay()
    if not startFrame or not startFrame.keybindBtns then return end
    for _, btn in ipairs(startFrame.keybindBtns) do
        local key = GetBindingKey(btn.bindingName)
        if key then
            btn.keyText:SetText(key)
            btn.keyText:SetTextColor(0.9, 0.9, 0.9)
        else
            btn.keyText:SetText("|cFF666666unbound|r")
        end
    end
end

function PingGameUI:ToggleDebugHitbox()
    debugHitbox = not debugHitbox
    BoundToLearn:Print("Hitbox debug: " .. (debugHitbox and "ON" or "OFF"))
    -- Update existing active targets
    for _, frame in pairs(activeTargetFrames) do
        frame.dbgHit:SetShown(debugHitbox and frame.modelHit:IsShown())
    end
end

function PingGameUI:GetTargetStyle()
    local db = BoundToLearn.db
    return db and db.pingTrainer and db.pingTrainer.targetStyle or "portraits"
end

function PingGameUI:UpdateStyleButtons()
    if not startFrame or not startFrame.styleBtns then return end
    local current = self:GetTargetStyle()
    for _, btn in ipairs(startFrame.styleBtns) do
        if btn.styleID == current then
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:GetFontString():SetTextColor(0.33, 0.8, 1)
        else
            btn:SetNormalFontObject("GameFontDisableSmall")
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
    end
    self:RefreshShowcase()
end

function PingGameUI:UpdateDiffButtons()
    if not startFrame or not startFrame.diffBtns then return end
    local PG = ns.PingGame
    local current = PG and PG:GetDifficulty() or "Normal"
    for _, btn in ipairs(startFrame.diffBtns) do
        local c = DIFF_COLORS[btn.diffName]
        if btn.diffName == current then
            btn:SetNormalFontObject("GameFontNormalSmall")
            if c then
                btn:GetFontString():SetTextColor(c[1], c[2], c[3])
                ns.Theme.SetFill(btn, c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 0.9)
            end
        else
            btn:SetNormalFontObject("GameFontDisableSmall")
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
            ns.Theme.SetFill(btn, 0.14, 0.13, 0.12, 0.85)
        end
    end
end

function PingGameUI:UpdateSoundButtons()
    if not startFrame or not startFrame.soundToggleBtns then return end
    for _, btn in ipairs(startFrame.soundToggleBtns) do
        local active = btn.isActiveFunc()
        if active then
            btn.label:SetText("|cFF88CC88" .. btn.optLabel .. "|r")
        else
            btn.label:SetText("|cFF666666" .. btn.optLabel .. "|r")
        end
    end
end

-- Returns atlas name for a random race icon from the given faction
local function GetRandomRaceAtlas(isEnemy)
    if not playerFaction then
        playerFaction = UnitFactionGroup("player")
    end
    local raceIDs
    if isEnemy then
        raceIDs = (playerFaction == "Alliance") and HORDE_RACE_IDS or ALLIANCE_RACE_IDS
    else
        raceIDs = (playerFaction == "Alliance") and ALLIANCE_RACE_IDS or HORDE_RACE_IDS
    end
    local raceID = raceIDs[math.random(#raceIDs)]
    local raceInfo = C_CreatureInfo.GetRaceInfo(raceID)
    if not raceInfo then return nil end
    local gender = (math.random(2) == 1) and "male" or "female"
    return sformat("raceicon128-%s-%s", raceInfo.clientFileString, gender)
end

-- A target's portrait (race icon, or a hazard icon) with its colored ring:
-- the portrait style, and the stand-in when a 3D model does not load.
local function ShowTargetPortrait(frame, targetType)
    if targetType == TARGET_HAZARD then
        frame.icon:SetTexture(HAZARD_ICONS[math.random(#HAZARD_ICONS)])
    else
        local atlas = GetRandomRaceAtlas(targetType == TARGET_ENEMY)
        if not atlas then return end
        frame.icon:SetAtlas(atlas)
    end
    frame.icon:SetTexCoord(0, 1, 0, 1)
    frame.icon:Show()
    frame.ring:Show()
end

-- Every target NPC asked for once while the start screen is up, so a round's
-- models come from the client's cache instead of a first, blank, ask.
local warmModel
function PingGameUI:WarmTargetModels()
    if not mainFrame then return end
    if not warmModel then
        warmModel = CreateFrame("PlayerModel", nil, mainFrame)
        warmModel:SetSize(1, 1)
        warmModel:SetPoint("BOTTOMLEFT")
        warmModel:SetAlpha(0)
    end
    warmModel:Show()
    local ids = {}
    for _, list in ipairs({ ALLIANCE_NPC_IDS, HORDE_NPC_IDS }) do
        for _, id in ipairs(list) do ids[#ids + 1] = id end
    end
    for i, id in ipairs(ids) do
        C_Timer.After(i * 0.1, function()
            if warmModel:IsVisible() then warmModel:SetCreature(id) end
        end)
    end
end

-- Probe (/btl modelcheck): asks for each target NPC on its own, records
-- whether and when its model loaded (first ask or the retry) and its model
-- file. Printed, and saved in BoundToLearnDB.modelReport.
function PingGameUI:ModelCheck()
    local ids = {}
    for _, list in ipairs({ ALLIANCE_NPC_IDS, HORDE_NPC_IDS }) do
        for _, id in ipairs(list) do ids[#ids + 1] = id end
    end
    local probe = CreateFrame("PlayerModel", nil, UIParent)
    probe:SetSize(64, 64)
    probe:SetPoint("BOTTOMLEFT")
    probe:SetAlpha(0.01)
    probe:Show()
    local lines = {}
    Utils.Print(sformat("Model check: %d NPCs, about %d seconds.", #ids, #ids * 2))
    local i = 0
    local function nextOne()
        i = i + 1
        local id = ids[i]
        if not id then
            probe:Hide()
            lines[#lines + 1] = sformat("Model check done on %s.", Utils.IS_FOREVER and "Forever" or "retail")
            BoundToLearnDB.modelReport = lines
            for _, line in ipairs(lines) do Utils.Print(line) end
            return
        end
        local start, loadedAt, ask = GetTime(), nil, 1
        probe:ClearModel()
        probe:SetScript("OnModelLoaded", function()
            if not loadedAt then loadedAt = sformat("%.2fs on ask %d", GetTime() - start, ask) end
        end)
        probe:SetCreature(id)
        C_Timer.After(0.6, function()
            if not loadedAt then ask = 2; probe:SetCreature(id) end
        end)
        C_Timer.After(2, function()
            local file = probe.GetModelFileID and probe:GetModelFileID()
            lines[#lines + 1] = sformat("%d: %s, model file %s", id, loadedAt and ("loaded after " .. loadedAt) or "never loaded", tostring(file))
            nextOne()
        end)
    end
    nextOne()
end

-- Reflect the chosen icon style in the three start-screen previews, live.
function PingGameUI:RefreshShowcase()
    if not startFrame or not startFrame.showcaseCells then return end
    local style = self:GetTargetStyle()
    for _, cell in ipairs(startFrame.showcaseCells) do
        if style == "3d" then
            cell.portrait:Hide(); cell.blob:Hide(); cell.blobLabel:Hide()
            -- A PlayerModel can render blank after a hide/show cycle, so re-feed the
            -- creature whenever it transitions back to visible.
            if not cell.model:IsShown() then
                cell.model:Show()
                cell.model:SetCreature(cell.npcID)
                local facing, anim = cell.facing, cell.anim
                cell.model:SetScript("OnModelLoaded", function(m)
                    m:SetFacing(facing)
                    m:SetAnimation(anim)
                    m:SetScript("OnModelLoaded", nil)
                end)
            end
        elseif style == "blobs" then
            cell.model:Hide(); cell.portrait:Hide(); cell.blob:Show(); cell.blobLabel:Show()
        else
            cell.model:Hide(); cell.blob:Hide(); cell.blobLabel:Hide()
            if not cell.portraitSet then
                if cell.targetType == TARGET_HAZARD then
                    cell.portrait:SetTexture(HAZARD_ICONS[math.random(#HAZARD_ICONS)])
                    cell.portrait:SetTexCoord(0, 1, 0, 1)
                    cell.portraitSet = true
                else
                    local atlas = GetRandomRaceAtlas(cell.targetType == TARGET_ENEMY)
                    if atlas then
                        cell.portrait:SetAtlas(atlas)
                        cell.portrait:SetTexCoord(0, 1, 0, 1)
                        cell.portraitSet = true
                    end
                end
            end
            if cell.portraitSet then
                cell.portrait:Show()
            else
                cell.blob:Show(); cell.blobLabel:Show()
            end
        end
    end
end

-- Gray the Start button until every ping is bound (checked each time the start
-- screen shows, so binding a ping and reopening re-enables it).
function PingGameUI:UpdateStartButton()
    if not startFrame or not startFrame.startBtn then return end
    startFrame.startBtn:SetEnabled(ns.PingGame ~= nil and ns.PingGame:AreAllPingsKeybound())
end

function PingGameUI:ShowStartScreen()
    if not mainFrame then self:CreateUI() end
    if gameArea then gameArea:Hide() end
    if hudFrame then hudFrame:Hide() end
    if resultsFrame then resultsFrame:Hide() end
    self:UpdateDiffButtons()
    self:UpdateStyleButtons()
    self:UpdateKeybindDisplay()
    self:UpdateStartBackdrop(true)
    self:WarmTargetModels()
    self:UpdateBackgroundButtons()
    self:UpdateSoundButtons()
    self:UpdateStartButton()
    startFrame:Show()
    mainFrame:Show()
end

function PingGameUI:OnGameStart()
    if not mainFrame then self:CreateUI() end
    startFrame:Hide()
    resultsFrame:Hide()

    -- Select and apply background + music
    local bg = GetSelectedBackground()
    ApplyBackground(gameArea.bgTex, bg)
    StartBackgroundMusic(bg)

    gameArea:Show()
    gameArea.inputFrame:Show()
    hudFrame:Show()
    if mainFrame.healthFrame then
        mainFrame.healthFrame:Show()
    end
    if hudFrame.musicBtn then hudFrame.musicBtn.Refresh() end
    if hudFrame.pingBtn then hudFrame.pingBtn.Refresh() end
    mainFrame:Show()
    hoveredTargetID = nil

    scoreText:SetText("0")
    timerText:SetText("")
    comboText:SetText("")
    -- Release any frames left over from the previous round so old pings do not
    -- linger on the map before the new round spawns anything.
    for _, frame in pairs(activeTargetFrames) do
        ReleaseTarget(frame)
    end
    wipe(activeTargetFrames)
    ClearRoundEffects()
end

function PingGameUI:OnGameEnd(results)
    gameArea.inputFrame:Hide()
    gameArea:Hide()
    hudFrame:Hide()
    if mainFrame.healthFrame then mainFrame.healthFrame:Hide() end
    hoveredTargetID = nil
    StopBackgroundMusic()
    ClearRoundEffects()

    -- Check for newly unlocked backgrounds
    local newUnlocks = CheckUnlocks(results)
    for i = 1, #newUnlocks do
        local bg = newUnlocks[i]
        local msg = sformat("|cFFFF8A33New background unlocked:|r |cFFFFD700%s|r", bg.name)
        DEFAULT_CHAT_FRAME:AddMessage("|cFFFF8A33[BoundToLearn]|r " .. msg)
    end

    resultsFrame.scoreLabel:SetText(sformat("|cFFFFD700%d|r", results.score))

    local lines = {
        sformat("Correct pings: |cFF44CC44%d|r    Wrong type: |cFFFF8844%d|r    Expired: |cFFCC6644%d|r    Missed: |cFFCC6644%d|r",
            results.hits, results.wrongType, results.expired, results.strayPings or 0),
        sformat("Best combo: |cFFFF8A33%d|r    Accuracy: |cFFFFD700%d%%|r    Time: %ds",
            results.maxCombo, results.accuracy, mfloor(results.elapsed)),
    }
    -- Records are per difficulty.
    local diffName = results.difficulty or "?"
    if results.newBest then
        lines[#lines + 1] = sformat("|cFF44CC44New best on %s!|r", diffName)
            .. (results.prevBest and sformat("  (was %d)", results.prevBest.score) or "")
    elseif results.prevBest then
        lines[#lines + 1] = sformat("Best on %s: |cFFFFD700%d|r (%s)", diffName, results.prevBest.score,
            results.prevBest.grade or "?")
    end
    resultsFrame.statsText:SetText(table.concat(lines, "\n"))
    resultsFrame.statsText:SetTextColor(0.75, 0.75, 0.75)

    -- Grade from accuracy, F for a round that ran out of health (PingGame GradeFor).
    local GRADE_COLORS = { S = "FF55FF", A = "44CC44", B = "CCCC44", C = "CC8844", D = "CC6644", F = "884444" }
    local grade = results.grade or "D"
    resultsFrame.gradeLabel:SetText(sformat("|cFF%s%s|r", GRADE_COLORS[grade] or "CCCCCC", grade))

    resultsFrame:Show()
end

function PingGameUI:UpdateHealthBar(healthPct)
    if not mainFrame or not mainFrame.healthFrame then return end
    local hf = mainFrame.healthFrame
    local maxW = hf:GetWidth() - 2
    local pct = mmax(0, mmin(1, healthPct))
    hf.bar:SetWidth(mmax(1, maxW * pct))

    -- Color: green -> yellow -> red
    local r, g
    if pct > 0.5 then
        r = (1 - pct) * 2
        g = 0.8
    else
        r = 0.9
        g = pct * 1.6
    end
    hf.bar:SetColorTexture(r, g, 0.15, 0.9)
    hf.text:SetText(sformat("%d%%", mfloor(pct * 100)))
end

function PingGameUI:OnUpdate(elapsed, duration, currentScore, currentCombo, healthPct)
    local remaining = mmax(0, duration - elapsed)
    local mins = mfloor(remaining / 60)
    local secs = mfloor(remaining % 60)
    timerText:SetText(sformat("%d:%02d", mins, secs))

    scoreText:SetText(sformat("%d", mmax(0, currentScore)))
    comboText:SetText(currentCombo > 1 and sformat("x%d", currentCombo) or "")

    if healthPct then
        self:UpdateHealthBar(healthPct)
    end

    -- Update target timer bars
    local now = GetTime()
    for _, frame in pairs(activeTargetFrames) do
        if frame.targetData then
            local t = frame.targetData
            local pct = mmax(0, (t.expireTime - now) / t.lifetime)
            local barW = frame.timerBG:GetWidth() - 2
            frame.timerBar:SetWidth(mmax(1, barW * pct))

            if pct < 0.3 then
                local pulse = 0.5 + 0.5 * math.sin(now * 8)
                frame:SetAlpha(0.5 + 0.5 * pulse)
            end
        end
    end
end

function PingGameUI:OnTargetSpawned(target)
    local frame = AcquireTarget()
    local sizeScale = target.sizeScale or 1
    frame.sizeScale = sizeScale
    frame.icon:SetSize((TARGET_SIZE - 8) * sizeScale, (TARGET_SIZE - 8) * sizeScale)
    frame.model:SetSize(TARGET_SIZE * 2.25 * sizeScale, TARGET_SIZE * 3.4 * sizeScale)

    -- Compute spawn bounds based on target style
    -- Model extends from button center: ~50px left/right, ~32px below, ~118px above
    local style = self:GetTargetStyle()
    local marginL, marginR, marginB, marginT
    if style == "3d" then
        local halfModelW = (TARGET_SIZE * 2.25 * sizeScale) / 2
        local modelH = TARGET_SIZE * 3.4 * sizeScale
        local halfBtn = TARGET_SIZE * sizeScale / 2
        marginL = halfModelW
        marginR = halfModelW
        -- The timer bar hangs 18 below the target (4 tall): keep it 4 above
        -- the arena floor, clear of the round's health bar under the arena.
        marginB = halfBtn + 18 + 4
        marginT = modelH - halfBtn - 10
    else
        marginL = SPAWN_MARGIN
        marginR = SPAWN_MARGIN
        marginB = SPAWN_MARGIN
        marginT = SPAWN_MARGIN
    end

    local xMin = marginL
    local xMax = GAME_WIDTH - marginR
    local yMin = marginB
    local yMax = GAME_HEIGHT - marginT

    local x = xMin + math.random() * (xMax - xMin)
    local y = yMin + math.random() * (yMax - yMin)

    -- Avoid overlap with existing targets (larger spacing for 3D models)
    local minDist = (style == "3d") and (TARGET_SIZE * 2.5) or (TARGET_SIZE + 10)
    local attempts = 0
    while attempts < 10 do
        local tooClose = false
        for _, existingFrame in pairs(activeTargetFrames) do
            if existingFrame.posX and existingFrame.posY then
                local dx = x - existingFrame.posX
                local dy = y - existingFrame.posY
                if dx * dx + dy * dy < minDist * minDist then
                    tooClose = true
                    break
                end
            end
        end
        if not tooClose then break end
        x = xMin + math.random() * (xMax - xMin)
        y = yMin + math.random() * (yMax - yMin)
        attempts = attempts + 1
    end

    frame:SetPoint("CENTER", gameArea, "BOTTOMLEFT", x, y)
    frame.posX = x
    frame.posY = y
    frame.targetData = target
    frame.targetID = target.id

    local c = TARGET_COLORS[target.targetType]
    frame.baseColor = c
    frame.ring:SetVertexColor(c[1], c[2], c[3], 1)
    frame.ring:SetAlpha(0.5)
    frame.bg:SetVertexColor(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.9)
    frame.timerBar:SetVertexColor(c[1], c[2], c[3])

    -- Set target visuals based on style setting
    frame.icon:Hide()
    frame.model:Hide()

    -- Reposition timer bar for 3D mode (below the model)
    frame.timerBG:ClearAllPoints()
    frame.timerBar:ClearAllPoints()
    if style == "3d" then
        frame.timerBG:SetPoint("BOTTOM", frame, "BOTTOM", 0, -18)
        frame.timerBG:SetSize(TARGET_SIZE + 10, 4)
        frame.timerBar:SetPoint("BOTTOMLEFT", frame.timerBG, "BOTTOMLEFT", 1, 0)
        frame.timerBar:SetHeight(4)
    else
        frame.timerBG:SetPoint("BOTTOM")
        frame.timerBG:SetSize(TARGET_SIZE - 4, 3)
        frame.timerBar:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 2, 0)
        frame.timerBar:SetHeight(3)
    end
    frame.label:SetText("")

    -- Show/hide circle background and ring based on style
    if style == "3d" then
        frame.bg:Hide()
        frame.ring:Hide()
    elseif style == "blobs" then
        frame.bg:SetVertexColor(c[1] * 0.3, c[2] * 0.3, c[3] * 0.3, 0.9)
        frame.bg:Show()
        frame.ring:Show()
    else
        -- Portraits: ring for color coding, no blob
        frame.bg:Hide()
        frame.ring:Show()
    end

    if style == "blobs" then
        -- Simple colored blobs with text label
        frame.label:SetText(TARGET_LABELS[target.targetType])
        frame.label:SetTextColor(c[1], c[2], c[3])
    elseif style == "3d" then
        -- 3D models for all target types with distinct animations
        if not playerFaction then playerFaction = UnitFactionGroup("player") end
        local enemyNPCs = (playerFaction == "Alliance") and HORDE_NPC_IDS or ALLIANCE_NPC_IDS
        local allyNPCs  = (playerFaction == "Alliance") and ALLIANCE_NPC_IDS or HORDE_NPC_IDS

        local npcIDs
        local targetType = target.targetType
        if targetType == TARGET_ENEMY then
            npcIDs = enemyNPCs
        elseif targetType == TARGET_HAZARD then
            npcIDs = enemyNPCs
        else
            npcIDs = allyNPCs
        end

        local npcID = npcIDs[math.random(#npcIDs)]
        local facing = (math.random() - 0.5) * 1.05  -- -30 to +30 degrees
        -- Show before feeding the creature: SetCreature on a hidden model (fresh from
        -- the pool) can render blank on first appearance, matching the showcase re-feed.
        frame.model:Show()
        frame.model:ClearModel()
        frame.model:SetPortraitZoom(0)
        frame.model:SetCamDistanceScale(1.4)
        frame.model:SetPosition(0, 0, -0.5)
        frame.model:SetCreature(npcID)
        -- A creature the client has not cached comes back blank on the first
        -- ask, and one its server lacks never loads: ask once more, then show
        -- the target's portrait so it is never invisible.
        local thisTarget = target.id
        frame.modelPending = true
        C_Timer.After(MODEL_RETRY, function()
            if frame.targetID == thisTarget and frame.modelPending then frame.model:SetCreature(npcID) end
        end)
        C_Timer.After(MODEL_GIVE_UP, function()
            if frame.targetID == thisTarget and frame.modelPending then
                frame.modelPending = false
                frame.model:Hide()
                ShowTargetPortrait(frame, targetType)
            end
        end)
        -- Defer animation and facing until model loads
        frame.model:SetScript("OnModelLoaded", function(self)
            frame.modelPending = false
            self:SetFacing(facing)
            if targetType == TARGET_ENEMY then
                -- Try combat stance - guards are melee so 26 (ReadyUnarmed) should work
                -- If NPC doesn't support it, WoW falls back to 0 (idle)
                -- Use FreezeAnimation to lock a single attack frame instead
                self:SetAnimation(26)   -- ReadyUnarmed
            elseif targetType == TARGET_HAZARD then
                self:SetAnimation(4)    -- walking
            elseif targetType == TARGET_ALLY then
                self:SetAnimation(ALLY_SPAWN_ANIMS[math.random(#ALLY_SPAWN_ANIMS)])
            else
                self:SetAnimation(0)    -- idle
            end
            self:SetScript("OnModelLoaded", nil)
        end)
        frame.modelHit:Show()
    else
        -- Portraits (default): race icon atlas for enemy/ally, hazard icon for hazards
        if target.targetType == TARGET_HAZARD then
            local hazardIcon = HAZARD_ICONS[math.random(#HAZARD_ICONS)]
            frame.icon:SetTexture(hazardIcon)
            frame.icon:SetTexCoord(0, 1, 0, 1)
            frame.icon:Show()
        else
            local raceAtlas = GetRandomRaceAtlas(target.targetType == TARGET_ENEMY)
            if raceAtlas then
                frame.icon:SetAtlas(raceAtlas)
                frame.icon:SetTexCoord(0, 1, 0, 1)
                frame.icon:Show()
            else
                frame.label:SetText(TARGET_LABELS[target.targetType])
                frame.label:SetTextColor(c[1], c[2], c[3])
            end
        end
    end

    frame.dbgHit:SetShown(debugHitbox and frame.modelHit:IsShown())

    frame:SetFrameLevel(gameArea:GetFrameLevel() + 5)
    frame:SetAlpha(0)

    -- Pop-in animation
    local spawnElapsed = 0
    frame:SetScript("OnUpdate", function(self, dt)
        spawnElapsed = spawnElapsed + dt
        local sc = self.sizeScale or 1
        if spawnElapsed < 0.15 then
            local p = spawnElapsed / 0.15
            self:SetAlpha(p)
            local scale = (0.5 + 0.5 * p) * sc
            self:SetSize(TARGET_SIZE * scale, TARGET_SIZE * scale)
            self.ring:SetSize((TARGET_SIZE + 8) * scale, (TARGET_SIZE + 8) * scale)
        else
            self:SetAlpha(1)
            self:SetSize(TARGET_SIZE * sc, TARGET_SIZE * sc)
            self.ring:SetSize((TARGET_SIZE + 8) * sc, (TARGET_SIZE + 8) * sc)
            self:SetScript("OnUpdate", nil)
        end
    end)

    activeTargetFrames[target.id] = frame
end

function PingGameUI:OnTargetResult(target, result, reactionTime, points, pingAction)
    local frame = activeTargetFrames[target.id]
    if not frame then return end

    PlayPingSound(pingAction)

    local x = frame.posX or GAME_WIDTH / 2
    local y = frame.posY or GAME_HEIGHT / 2

    -- Show unit ping marker above the target and delay release so it's visible
    local kit = PING_ACTION_KITS[pingAction]
    if kit then
        local pin = frame.unitPin
        pin:ClearAllPoints()
        if frame.model:IsShown() then
            pin:SetPoint("BOTTOM", frame.model, "TOP", 0, -50)
        else
            pin:SetPoint("BOTTOM", frame, "TOP", 0, 4)
        end
        pin.bg:SetAtlas("Ping_UnitMarker_BG_" .. kit)
        pin.icon:SetAtlas("Ping_Marker_Icon_" .. kit)
        pin:Show()
        frame.dyingUntil = GetTime() + 0.6
    end

    if result == "hit" then
        local ms = mfloor(reactionTime * 1000)
        ShowFloatingText(x, y + 20, sformat("+%d", points), 0.3, 1, 0.3)
        ShowFloatingText(x, y - 5, sformat("%dms", ms), 0.7, 0.7, 0.7)
        if frame.model:IsShown() then
            if target.targetType == TARGET_ENEMY then
                frame.model:SetAnimation(1)   -- death
            elseif target.targetType == TARGET_ALLY then
                frame.model:SetAnimation(74)  -- applause/cheer
            end
        end
    elseif result == "wrong_type" then
        ShowFloatingText(x, y + 10, "Wrong ping!", 1, 0.6, 0.2)
    end
end

function PingGameUI:OnTargetExpired(target)
    local frame = activeTargetFrames[target.id]
    if not frame then return end
    ShowFloatingText(frame.posX or GAME_WIDTH / 2, (frame.posY or GAME_HEIGHT / 2) + 10, "Expired", 0.6, 0.4, 0.2)
end

function PingGameUI:OnMissClick(pingAction)
    if not gameArea then return end
    PlayPingSound(pingAction)
    local kit = PING_ACTION_KITS[pingAction]
    if kit then
        local cursorX, cursorY = GetCursorPosition()
        local scale = gameArea:GetEffectiveScale()
        local areaLeft, areaBottom = gameArea:GetLeft(), gameArea:GetBottom()
        local relX = cursorX / scale - areaLeft
        local relY = cursorY / scale - areaBottom
        ShowGroundPin(relX, relY, kit)
        ShowFloatingText(relX, relY + GROUND_PIN_SIZE + GROUND_PIN_STEM + 10, "Miss", 0.6, 0.4, 0.4)
    end
end

function PingGameUI:ReleaseTarget(target)
    local frame = activeTargetFrames[target.id]
    if not frame then return end

    if frame.dyingUntil and GetTime() < frame.dyingUntil then
        local targetID = target.id
        C_Timer.After(frame.dyingUntil - GetTime(), function()
            if activeTargetFrames[targetID] == frame then
                if hoveredTargetID == targetID then
                    hoveredTargetID = nil
                end
                frame.dyingUntil = nil
                ReleaseTarget(frame)
                activeTargetFrames[targetID] = nil
            end
        end)
        return
    end

    if hoveredTargetID == target.id then
        hoveredTargetID = nil
    end
    frame.dyingUntil = nil
    ReleaseTarget(frame)
    activeTargetFrames[target.id] = nil
end

-- The key catcher goes with the pause: combat pauses the round, and a
-- catcher left up in a fight can swallow every key.
function PingGameUI:ShowPause()
    if pauseOverlay then pauseOverlay:Show() end
    if gameArea then gameArea.inputFrame:Hide() end
end

function PingGameUI:HidePause()
    if pauseOverlay then pauseOverlay:Hide() end
    if gameArea then gameArea.inputFrame:Show() end
end
