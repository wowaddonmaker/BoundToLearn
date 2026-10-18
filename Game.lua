local ADDON_NAME, ns = ...

local Game = {}
ns.Game = Game

local Utils    = ns.Utils
local sformat  = Utils.sformat
local GetTime  = Utils.GetTime
local tinsert  = Utils.tinsert
local tremove  = Utils.tremove
local tsort    = Utils.tsort
local wipe     = Utils.wipe
local mabs     = Utils.mabs
local mfloor   = Utils.mfloor
local mmin, mmax = Utils.mmin, Utils.mmax
local ipairs   = Utils.ipairs
local pairs    = Utils.pairs

local CreateFrame      = Utils.CreateFrame
local HasAction        = HasAction
local GetActionTexture = GetActionTexture
local GetBindingKey    = GetBindingKey
local InCombatLockdown = InCombatLockdown
local IsShiftKeyDown   = IsShiftKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsAltKeyDown     = IsAltKeyDown
local UIParent         = UIParent

local isRunning = false
local isPaused = false
local currentMode = "timed"  -- "timed", "practice", "competitive"

local activeNotes = {}
local availableSlots = {}
local destroyedLanes = {}  -- [slotIndex] = expireTime
local barExtents = {}      -- [barKey] = { l, r, b, t } screen px of each included bar

-- Reverse lookup: keybind string -> slotInfo
local keybindToSlot = {}

local score = 0
local combo = 0
local maxCombo = 0
local multiplier = 1
local hitCounts = { perfect = 0, great = 0, good = 0, miss = 0, redHerring = 0 }

local spawnAccumulator = 0
local gameStartTime = 0
local gameDuration = 0       -- 0 = unlimited (practice)
local gameElapsed = 0        -- tracks actual play time (excludes pauses)
local pauseStartTime = 0
local mirrorFlipped = false
local nextMirrorFlip = 0
local gameModifiers = {}

-- DDR-style "money score": a flawless run of ANY track lands at SCORE_CAP,
-- regardless of length. A note is worth SCORE_CAP / noteBudget, scaled by how
-- cleanly it was hit. The old per-note point values ran to hundreds of thousands
-- and scaled with track length, which maxed every rank on the first decent game.
local SCORE_CAP = 10000
local JUDGE_WEIGHT = { perfect = 1.0, great = 0.75, good = 0.45, miss = 0 }
local COMBO_THRESHOLDS = { 5, 10, 20, 35 }

-- Bomb fuse and fake-note laugh. Forever lacks the two sound kits but ships
-- their files, so it plays those directly.
local FUSE_FILES = { 2066602, 2066603 }
local LAUGH_FILES = { 541902, 541940, 541894, 541985 }
local function PlayFuseSound()
    if Utils.IS_FOREVER then
        return PlaySoundFile(FUSE_FILES[math.random(#FUSE_FILES)], "SFX")
    end
    return PlaySound(268433, "SFX", false)
end
local function PlayLaughSound()
    if Utils.IS_FOREVER then
        PlaySoundFile(LAUGH_FILES[math.random(#LAUGH_FILES)], "SFX")
    else
        PlaySound(23330)
    end
end

-- Focus (health) system
local MAX_FOCUS = 100
local focus = MAX_FOCUS
local focusFailed = false
local FOCUS_DRAIN = { miss = 17, redHerring = 22 }
local FOCUS_RECOVER = { perfect = 6, great = 4, good = 2 }
local FOCUS_DIFF_SCALE = { Easy = 0.6, Medium = 1.0, Hard = 1.2, Extreme = 1.5 }
local lastBooTime = 0
local savedAmbienceVol, savedMusicVol
local isPlayingGameMusic = false

local DIFFICULTY_MUSIC = {
    Easy    = 53474,   -- Silvermoon city walk (relaxed, warm)
    Medium  = 55957,   -- Grizzly Hills (upbeat, pleasant)
    Hard    = 53199,   -- Ulduar Algalon (intense, epic)
    Extreme = 53569,   -- L70ETC concert (intense)
}

local DIFFICULTY_PRESETS = {
    Easy    = { fallSpeed = 96, fallDistance = 350, maxActiveNotes = 1, spawnInterval = 2.1,
                timingPerfect = 0.06, timingGreat = 0.20, timingGood = 0.40,
                redHerringChance = 0, randomAngles = false, doublesChance = 0 },
    Medium  = { fallSpeed = 180, fallDistance = 300, maxActiveNotes = 3, spawnInterval = 1.25,
                timingPerfect = 0.04, timingGreat = 0.12, timingGood = 0.22,
                redHerringChance = 0, randomAngles = false, doublesChance = 0 },
    Hard    = { fallSpeed = 240, fallDistance = 280, maxActiveNotes = 4, spawnInterval = 1.0,
                timingPerfect = 0.03, timingGreat = 0.09, timingGood = 0.18,
                redHerringChance = 0, randomAngles = false, doublesChance = 0 },
    Extreme = { fallSpeed = 240, fallDistance = 260, maxActiveNotes = 5, spawnInterval = 0.75,
                timingPerfect = 0.025, timingGreat = 0.07, timingGood = 0.15,
                redHerringChance = 0, randomAngles = false, doublesChance = 0 },
}

-- Note spacing is paced to each song's real tempo: spawn interval = one beat times
-- this many beats-per-note, so a faster track plays faster and lower difficulties
-- leave more beats between notes. The presets' fixed spawnInterval is only a
-- fallback for a song with no known BPM.
local BEATS_PER_NOTE = { Easy = 3, Medium = 2, Hard = 1.4, Extreme = 1 }

-- Real audio charts (ns.SongCharts, read through SongData.ChartNotes): each note is a
-- time, a register 1-5 and a level 1-4, one per 16th slot so the stream is monophonic (never two binds at once). Difficulty
-- keeps notes up to its level; the active bind pool grows with difficulty so lower
-- levels stay hittable. Rapid consecutive notes are kept to modifier-compatible
-- binds so a fast run never demands releasing one modifier to press another.
local ACTIVE_BINDS     = { Easy = 5, Medium = 9, Hard = 14, Extreme = 99 }
-- How many times the active bind-set sweeps the whole layout over one song. The set
-- (size ACTIVE_BINDS) stays a coordinated group moment-to-moment but drifts across
-- every bind this many times, so no bind is ever left out of a track.
local BIND_COVERAGE    = 2
-- Target notes per second per difficulty. The level-1 pulse is always kept; higher
-- tiers layer on up to this, so density ramps smoothly instead of jumping at Medium.
local TARGET_DENSITY   = { Easy = 1.0, Medium = 1.6, Hard = 2.2, Extreme = 2.8 }
local RAPID_GAP = 0.22
-- Extra screen-pixel lift of the shared note start line above the topmost bar, so
-- notes (and the health bar sitting on the line) start higher for more reaction time.
local START_LINE_LIFT = 180
-- Room kept above the start line for the health bar that sits on it (UI units:
-- its 6 px lift, 34 px height and a margin), so the bar never leaves the screen.
local LINE_TOP_ROOM = 56

local function bindMods(keybind)
    local m = ""
    if keybind:find("SHIFT-", 1, true) then m = m .. "S" end
    if keybind:find("CTRL-", 1, true) then m = m .. "C" end
    if keybind:find("ALT-", 1, true) then m = m .. "A" end
    return m
end
local function modCompatible(a, b) return a == "" or b == "" or a == b end
local function byEase(a, b)
    if #a.mods ~= #b.mods then return #a.mods < #b.mods end
    return a.slot < b.slot
end

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
}

-- All action bar binding prefixes to neutralize during gameplay
local ALL_BAR_PREFIXES = {
    "ACTIONBUTTON",
    "MULTIACTIONBAR1BUTTON",
    "MULTIACTIONBAR2BUTTON",
    "MULTIACTIONBAR3BUTTON",
    "MULTIACTIONBAR4BUTTON",
    "MULTIACTIONBAR5BUTTON",
    "MULTIACTIONBAR6BUTTON",
    "MULTIACTIONBAR7BUTTON",
}

local gameFrame
local inputFrame

function Game:Initialize()
    gameFrame = CreateFrame("Frame", "BoundToLearnGameFrame", UIParent)
    gameFrame:Hide()
    gameFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)

    inputFrame = CreateFrame("Frame", "BoundToLearnGameInput", UIParent)
    inputFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    inputFrame:SetAllPoints()
    inputFrame:EnableKeyboard(true)
    inputFrame:Hide()

    inputFrame:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_KEYS[key] then
            inputFrame:SetPropagateKeyboardInput(true)
            return
        end

        if key == "ESCAPE" then
            inputFrame:SetPropagateKeyboardInput(false)
            self:Stop()
            return
        end

        local fullKey = ""
        if IsAltKeyDown() then fullKey = fullKey .. "ALT-" end
        if IsControlKeyDown() then fullKey = fullKey .. "CTRL-" end
        if IsShiftKeyDown() then fullKey = fullKey .. "SHIFT-" end
        fullKey = fullKey .. key

        local slotInfo = keybindToSlot[fullKey]
        if slotInfo then
            inputFrame:SetPropagateKeyboardInput(false)
            self:OnKeybindInput(slotInfo.slot)
        else
            -- Swallow every other key while the game is running so stray binds
            -- (game menu, bags, character pane, spellbook, map, etc.) can't pop a
            -- window mid-song. ESC still stops the game; modifiers still pass, and
            -- the input frame is hidden on pause/stop so normal keys return then.
            inputFrame:SetPropagateKeyboardInput(false)
        end
    end)

    ns.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    ns.eventFrame:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and isRunning then
            if currentMode == "practice" then
                self:Pause()   -- Practice is lenient: combat just pauses.
            else
                -- Scored runs cannot be paused; entering combat ends the run.
                BoundToLearn:Print("Entered combat. Run ended.")
                self:Stop()
            end
        end
    end)
end

-- A mouse-bound note is pressed through Utils.CatchMouseBinds, not OnKeyDown.
local function OnMouseBind(key)
    if not isRunning or isPaused then return end
    local slotInfo = keybindToSlot[key]
    if slotInfo then Game:OnKeybindInput(slotInfo.slot) end
end

function Game:BlockActionBars()
    -- Keyboard binds go to a nonexistent action so they do nothing; mouse
    -- binds go to our catch, which scores them.
    local mouseKeys = {}
    for _, prefix in ipairs(ALL_BAR_PREFIXES) do
        for i = 1, 12 do
            local key1, key2 = GetBindingKey(prefix .. i)
            for _, key in ipairs({ key1, key2 }) do
                if Utils.IsMouseBind(key) then
                    mouseKeys[#mouseKeys + 1] = key
                else
                    SetOverrideBinding(inputFrame, true, key, "BTLNOOP")
                end
            end
        end
    end
    Utils.CatchMouseBinds(mouseKeys, OnMouseBind)
    -- Block ping keybind
    local pingKey1, pingKey2 = GetBindingKey("PING")
    if pingKey1 then SetOverrideBinding(inputFrame, true, pingKey1, "BTLNOOP") end
    if pingKey2 then SetOverrideBinding(inputFrame, true, pingKey2, "BTLNOOP") end
end

function Game:UnblockActionBars()
    ClearOverrideBindings(inputFrame)
    Utils.ReleaseMouseBinds()
end

function Game:GetSettings()
    local db = BoundToLearn.db.game
    local difficulty = db.difficulty
    local settings
    if difficulty ~= "Custom" and DIFFICULTY_PRESETS[difficulty] then
        -- Copy so we don't mutate the preset
        local preset = DIFFICULTY_PRESETS[difficulty]
        settings = {
            fallSpeed = preset.fallSpeed,
            fallDistance = preset.fallDistance,
            maxActiveNotes = preset.maxActiveNotes,
            spawnInterval = preset.spawnInterval,
            timingPerfect = preset.timingPerfect,
            timingGreat = preset.timingGreat,
            timingGood = preset.timingGood,
            redHerringChance = preset.redHerringChance,
            randomAngles = preset.randomAngles,
        }
    else
        settings = {
            fallSpeed = db.fallSpeed,
            fallDistance = db.fallDistance,
            maxActiveNotes = db.maxActiveNotes,
            spawnInterval = db.spawnInterval,
            timingPerfect = db.timingPerfect,
            timingGreat = db.timingGreat,
            timingGood = db.timingGood,
        }
    end
    -- Pace note spacing to the song's real tempo so it feels tied to the music.
    -- Lanes stay random across every bind (see SpawnNote). Custom keeps its slider.
    if difficulty ~= "Custom" then
        local bpm = ns.SongData.BPM(ns.SongData.Get(db.songKey))
        if bpm and bpm > 0 then
            settings.spawnInterval = mmax(0.34, mmin(2.6, (60 / bpm) * (BEATS_PER_NOTE[difficulty] or 1)))
        end
    end
    -- Competitive has 15 lanes; scale note cap to keep similar density
    if currentMode == "competitive" then
        settings.maxActiveNotes = settings.maxActiveNotes * 3
    end
    return settings
end

function Game:GetMode()
    return currentMode
end

function Game:GetTimeRemaining()
    if gameDuration == 0 then return nil end
    local remaining = gameDuration - mmax(0, gameElapsed)
    return mmax(0, remaining)
end

function Game:DiscoverSlots()
    wipe(availableSlots)
    wipe(keybindToSlot)
    local bars = BoundToLearn.db.game.bars
    local barMappings = {
        { key = "main",        bindPrefix = "ACTIONBUTTON",           btnPrefix = "ActionButton",              startSlot = 1 },
        { key = "bottomLeft",  bindPrefix = "MULTIACTIONBAR1BUTTON",  btnPrefix = "MultiBarBottomLeftButton",  startSlot = 61 },
        { key = "bottomRight", bindPrefix = "MULTIACTIONBAR2BUTTON",  btnPrefix = "MultiBarBottomRightButton", startSlot = 49 },
        { key = "right",       bindPrefix = "MULTIACTIONBAR3BUTTON",  btnPrefix = "MultiBarRightButton",       startSlot = 25 },
        { key = "left",        bindPrefix = "MULTIACTIONBAR4BUTTON",  btnPrefix = "MultiBarLeftButton",        startSlot = 37 },
        { key = "bar6",        bindPrefix = "MULTIACTIONBAR5BUTTON",  btnPrefix = "MultiBar5Button",           startSlot = 145 },
        { key = "bar7",        bindPrefix = "MULTIACTIONBAR6BUTTON",  btnPrefix = "MultiBar6Button",           startSlot = 157 },
        { key = "bar8",        bindPrefix = "MULTIACTIONBAR7BUTTON",  btnPrefix = "MultiBar7Button",           startSlot = 169 },
    }
    local seenTextures = {}
    wipe(barExtents)
    for _, bar in ipairs(barMappings) do
        if bars[bar.key] then
            for i = 1, 12 do
                local slot = bar.startSlot + (i - 1)
                local btn = _G[bar.btnPrefix .. i]
                if btn and btn:IsShown() then
                    -- The whole bar counts, bound or not: the HUD spans it.
                    local left = btn:GetLeft()
                    if left then
                        local scale = btn:GetEffectiveScale()
                        local e = barExtents[bar.key]
                        if not e then
                            e = { l = math.huge, r = -math.huge, b = math.huge, t = -math.huge }
                            barExtents[bar.key] = e
                        end
                        e.l, e.r = mmin(e.l, left * scale), mmax(e.r, btn:GetRight() * scale)
                        e.b, e.t = mmin(e.b, btn:GetBottom() * scale), mmax(e.t, btn:GetTop() * scale)
                    end
                    -- Read the button's CURRENT action, not the raw page slot.
                    -- Druid forms (and stance/bonus bars) remap the main bar,
                    -- so GetActionTexture(slot) returns a hidden other-form
                    -- icon. btn.action is what the player actually sees now.
                    local action = btn.action or slot
                    if HasAction(action) then
                        local keybind, keybind2 = GetBindingKey(bar.bindPrefix .. i)
                        if keybind then
                            local texture = GetActionTexture(action)
                            -- Skip duplicate textures (same ability on 2 bars)
                            if texture and not seenTextures[texture] then
                                seenTextures[texture] = true
                                local slotInfo = {
                                    slot = slot,
                                    keybind = keybind,
                                    mods = bindMods(keybind),
                                    texture = texture,
                                    button = btn,
                                }
                                tinsert(availableSlots, slotInfo)
                                keybindToSlot[keybind] = slotInfo
                                -- Either bind of the button hits its notes.
                                if keybind2 then keybindToSlot[keybind2] = slotInfo end
                            end
                        end
                    end
                end
            end
        end
    end
end

function Game:DiscoverCompetitiveSlots()
    wipe(availableSlots)
    wipe(keybindToSlot)
    wipe(destroyedLanes)

    local CD = ns.CompetitiveData
    if not CD then return end

    local compBtns = ns.GameUI and ns.GameUI:GetCompBarButtons() or {}

    for i, slotDef in ipairs(CD.slots) do
        local btn = compBtns[i]
        if btn then
            local rowDef = CD.rows[slotDef.row]
            local keybind = rowDef.modifier .. tostring(slotDef.col)

            local slotInfo = {
                slot = i,
                keybind = keybind,
                mods = bindMods(keybind),
                texture = slotDef.texture,
                button = btn,
                competitive = true,
                laneIndex = i,
            }
            tinsert(availableSlots, slotInfo)
            keybindToSlot[keybind] = slotInfo
        end
    end
end

local gameMusicTarget

local function MuteGameAudio()
    savedAmbienceVol = tonumber(GetCVar("Sound_AmbienceVolume")) or 0.5
    SetCVar("Sound_AmbienceVolume", 0)
    -- Silence the music channel too: the round's track starts on it unheard during
    -- the countdown (StartGameMusicMuted). Persisted so a crash before GO still
    -- restores it on next load.
    savedMusicVol = tonumber(GetCVar("Sound_MusicVolume")) or 0.4
    BoundToLearn.db.pendingMusicRestore = savedMusicVol
    SetCVar("Sound_MusicVolume", 0)
end

-- Start the round's track on the muted channel, so its lead-in plays unheard during
-- the countdown (the client cannot seek into a track). The target volume is
-- persisted so a crash before GO still restores it on next load (Core clears
-- pendingMusicRestore once applied).
local function StartGameMusicMuted(track)
    local target = savedMusicVol or tonumber(GetCVar("Sound_MusicVolume")) or 0.4
    if target < 0.05 then target = 0.4 end
    gameMusicTarget = target
    BoundToLearn.db.pendingMusicRestore = target
    SetCVar("Sound_MusicVolume", 0)
    PlayMusic(track)
    isPlayingGameMusic = true
end

-- GO: the track is past its lead-in and comes in at full volume at once.
local function UnmuteGameMusic()
    if isPlayingGameMusic and gameMusicTarget then
        SetCVar("Sound_MusicVolume", gameMusicTarget)
    end
end

local function RestoreGameAudio()
    if savedAmbienceVol then SetCVar("Sound_AmbienceVolume", savedAmbienceVol) end
    savedAmbienceVol = nil
    if isPlayingGameMusic then
        isPlayingGameMusic = false
        -- Do not stop the track: the round-over screen keeps it playing. Just
        -- make sure the volume is back at the player's level and clear the guard.
        SetCVar("Sound_MusicVolume", savedMusicVol or gameMusicTarget or 0.4)
    elseif savedMusicVol then
        -- Cancelled before the music started (e.g. during the countdown); un-mute.
        SetCVar("Sound_MusicVolume", savedMusicVol)
    end
    BoundToLearn.db.pendingMusicRestore = nil
    savedMusicVol = nil
end

local function ResetGameState()
    isRunning = true
    isPaused = false
    score = 0
    combo = 0
    maxCombo = 0
    multiplier = 1
    wipe(hitCounts)
    hitCounts.perfect = 0
    hitCounts.great = 0
    hitCounts.good = 0
    hitCounts.miss = 0
    hitCounts.redHerring = 0
    wipe(activeNotes)
    wipe(destroyedLanes)
    spawnAccumulator = 999  -- trigger immediate first spawn
    gameStartTime = GetTime()
    gameElapsed = 0
    pauseStartTime = 0
    focus = MAX_FOCUS
    focusFailed = false
    lastBooTime = 0
    mirrorFlipped = false
    nextMirrorFlip = 0
    gameModifiers = ns.Modifiers and ns.Modifiers:GetActive() or {}
end

function Game:Start()
    if isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start game during combat.")
        return
    end
    -- Skyriding/dragonriding swaps the main action bar for the mount ability bar
    -- (a bonus bar), which breaks keybind discovery. A grounded normal mount
    -- leaves the bonus bar at 0, so only skyriding is blocked.
    if IsMounted() and (GetBonusBarOffset and GetBonusBarOffset() or 0) > 0 then
        BoundToLearn:Print("Dismount first. Skyriding swaps your action bars, which breaks keybind tracking.")
        return
    end

    local db = BoundToLearn.db.game
    currentMode = db.mode or "timed"
    self:SeedChart(db.songKey, db.difficulty)

    if currentMode == "competitive" then
        return self:StartCompetitive()
    end

    self:DiscoverSlots()
    if #availableSlots == 0 then
        BoundToLearn:Print("No keybinds found on your action bars. Bind some keys first.")
        return
    end

    gameDuration = (currentMode == "practice") and 0 or ns.SongData.PlayLength(ns.SongData.Get(db.songKey))

    ResetGameState()
    self:BuildChart(db.songKey, db.difficulty)
    self:SetScoreBudget()
    self:BlockActionBars()

    if BoundToLearn.db.game.soundEnabled then
        MuteGameAudio()
    end

    if ns.GameUI then
        ns.GameUI:OnGameStart(availableSlots)
        self:PlaceNoteLine()   -- put the start line + health bar in place before the countdown
    end

    self:CountIn(db.songKey, db.difficulty)

    -- Game started silently; UI shows everything needed
end

-- Many tracks open on a quiet lead-in (Fire Festival: 4 s, 15 dB under the rest).
-- The track starts muted during the countdown, timed so its lead-in (measured per
-- track, SongData.LeadIn) is over by GO, and comes in at full volume on GO. A lead-in
-- over 3 s runs the countdown longer, up to MAX_COUNTDOWN; past that, GO lands
-- MAX_COUNTDOWN into the track. The first falling note also starts on GO (PrepChart
-- picks and times it from goOffset, the track's position at GO), so nothing falls
-- during the countdown and nothing pops in partway down.
local MAX_COUNTDOWN = 5
local roundToken = 0
function Game:CountIn(songKey, difficulty)
    roundToken = roundToken + 1
    local token = roundToken
    local function Live() return isRunning and token == roundToken end
    self.goOffset = 0
    if not ns.GameUI then
        gameStartTime = GetTime()
        gameFrame:Show()
        inputFrame:Show()
        return
    end

    local track
    if BoundToLearn.db.game.soundEnabled then
        local song = ns.SongData and ns.SongData.Get(songKey)
        track = (song and song.id) or DIFFICULTY_MUSIC[difficulty]
    end
    local leadIn = track and mmin(ns.SongData.LeadIn(songKey), MAX_COUNTDOWN) or 0
    local countdown = mmax(3, mmin(MAX_COUNTDOWN, math.ceil(leadIn)))

    local musicAt
    local function StartMusic()
        if musicAt or not track then return end
        StartGameMusicMuted(track)
        musicAt = GetTime()
    end
    if leadIn > 0 then
        C_Timer.After(countdown - leadIn, function()
            if Live() then StartMusic() end
        end)
    end
    ns.GameUI:ShowCountdown(countdown, function()
        if not Live() then return end
        StartMusic()   -- a track with no lead-in starts here, on GO
        local now = GetTime()
        self.goOffset = musicAt and (now - musicAt) or 0
        gameStartTime = now - self.goOffset
        UnmuteGameMusic()
        gameFrame:Show()
        inputFrame:Show()
    end)
end

function Game:StartCompetitive()
    if isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start game during combat.")
        return
    end

    local db = BoundToLearn.db.game
    currentMode = "competitive"
    gameDuration = ns.SongData.PlayLength(ns.SongData.Get(db.songKey))

    if ns.GameUI then
        ns.GameUI:CreateCompBar()
    end
    self:DiscoverCompetitiveSlots()

    if #availableSlots == 0 then
        BoundToLearn:Print("No competitive slots available. Check your keybinds.")
        if ns.GameUI then ns.GameUI:HideCompBar() end
        return
    end

    ResetGameState()
    self:SetScoreBudget()
    self:BlockActionBars()

    if BoundToLearn.db.game.soundEnabled then
        MuteGameAudio()
    end

    if ns.GameUI then
        ns.GameUI:OnGameStart(availableSlots)
        self:PlaceNoteLine()   -- put the start line + health bar in place before the countdown
    end

    self:CountIn(db.songKey, db.difficulty)
end

function Game:Stop()
    if not isRunning then return end
    isRunning = false
    isPaused = false
    gameFrame:Hide()
    inputFrame:Hide()
    self:UnblockActionBars()
    RestoreGameAudio()
    if ns.GameUI then
        ns.GameUI:CancelCountdown()
        if mirrorFlipped then
            mirrorFlipped = false
            ns.GameUI:SetMirrorFlipped(false)
        end
    end

    for i = #activeNotes, 1, -1 do
        local note = activeNotes[i]
        if note.bombSoundHandle then
            StopSound(note.bombSoundHandle, 0)
            note.bombSoundHandle = nil
        end
        if ns.GameUI then ns.GameUI:ReleaseNote(note) end
    end
    wipe(activeNotes)

    local duration = mmax(0, gameElapsed)
    if duration == 0 then duration = mmax(0, GetTime() - gameStartTime) end
    local totalNotes = hitCounts.perfect + hitCounts.great + hitCounts.good + hitCounts.miss

    local difficulty = BoundToLearn.db.game.difficulty

    if ns.Stats and totalNotes > 0 and currentMode ~= "practice" then
        ns.Stats:RecordGameSession({
            score = score,
            maxCombo = maxCombo,
            hitCounts = hitCounts,
            duration = duration,
            mode = currentMode,
            difficulty = difficulty,
        })
    end

    if ns.GameUI and totalNotes > 0 and currentMode ~= "practice" then
        local songAcc = ns.Utils.HitAccuracy(hitCounts)
        ns.GameUI:RecordSongScore(score, songAcc, maxCombo)
        local key = BoundToLearn.db.game.songKey
        local song = ns.SongData and ns.SongData.Get(key)
        local songLen = song and ns.SongData.PlayLength(song) or 0
        if songLen > 0 then
            ns.GameUI:RecordSongProgress(key, mmin(1, duration / songLen))
        end
    end

    if ns.GameUI then
        ns.GameUI:OnGameEnd({
            score = score,
            maxCombo = maxCombo,
            hitCounts = hitCounts,
            duration = duration,
            totalNotes = totalNotes,
            mode = currentMode,
            difficulty = difficulty,
            focusFailed = focusFailed,
            chartTotal = self.chartNotes and #self.chartNotes or 0,
            notesShown = self.chartNotes and mmin(self.chartCursor - 1, #self.chartNotes) or 0,
        })
        if currentMode == "competitive" then
            ns.GameUI:HideCompBar()
        end
    end

    -- Broadcast to leaderboard
    if ns.Leaderboard and totalNotes > 0 then
        local results = {
            score = score,
            maxCombo = maxCombo,
            hitCounts = hitCounts,
            duration = duration,
            totalNotes = totalNotes,
            mode = currentMode,
            difficulty = difficulty,
        }
        ns.Leaderboard:AddOwnScore(results)
        ns.Leaderboard:OnGameEnd(results)
    end

    -- Check achievements (non-practice only)
    if ns.Achievements and totalNotes > 0 and currentMode ~= "practice" then
        local newUnlocks = ns.Achievements:CheckRoundAchievements({
            score = score,
            maxCombo = maxCombo,
            hitCounts = hitCounts,
            difficulty = difficulty,
            modifiers = gameModifiers,
            mode = currentMode,
        })
        if #newUnlocks > 0 and ns.GameUI then
            ns.GameUI:ShowAchievementUnlocks(newUnlocks)
        end
    end

    -- Game over silently; summary UI shows results
end

function Game:Pause()
    if currentMode == "competitive" then
        -- Competitive: pausing zeroes your score
        score = 0
        combo = 0
        multiplier = 1
        -- Score reset handled silently; UI updates
        if ns.GameUI then
            ns.GameUI:UpdateScoreDisplay(score, combo, multiplier)
        end
    end

    isPaused = true
    pauseStartTime = GetTime()
    gameFrame:Hide()
    inputFrame:Hide()
    -- Combat pauses practice: the abilities must work in that fight.
    self:UnblockActionBars()
    if ns.GameUI then
        ns.GameUI:CancelCountdown()
        ns.GameUI:OnGamePause()
    end
end

function Game:Resume()
    if not isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot resume game during combat.")
        return
    end
    isPaused = false
    self:BlockActionBars()

    local function DoResume()
        local now = GetTime()
        local pauseDuration = now - pauseStartTime
        -- Shift all active note timings forward by the pause duration
        for _, note in ipairs(activeNotes) do
            if not note.evaluated then
                note.spawnTime = note.spawnTime + pauseDuration
                note.targetTime = note.targetTime + pauseDuration
            end
        end
        gameStartTime = now - gameElapsed
        UnmuteGameMusic()   -- a pause during the countdown left the track muted
        gameFrame:Show()
        inputFrame:Show()
    end

    if ns.GameUI then
        ns.GameUI:OnGameResume()
        ns.GameUI:ShowCountdown(3, DoResume)
    else
        DoResume()
    end
end

function Game:IsPaused()
    return isPaused
end

function Game:IsRunning()
    return isRunning
end

function Game:GetFocus()
    return focus, MAX_FOCUS
end

function Game:DidFocusFail()
    return focusFailed
end

function Game:OnFocusDepleted()
    if not isRunning or focusFailed then return end
    focusFailed = true
    if BoundToLearn.db.game.soundEnabled then
        PlaySound(847)  -- igQuestLogAbandonQuest (focus depleted)
    end
    self:Stop()
end

function Game:OnUpdate(elapsed)
    if not isRunning or isPaused then return end

    local now = GetTime()
    gameElapsed = now - gameStartTime

    -- Check timer (timed and competitive modes)
    if gameDuration > 0 and gameElapsed >= gameDuration then
        self:Stop()
        return
    end

    local settings = self:GetSettings()

    -- Update timer display
    if gameDuration > 0 and ns.GameUI then
        ns.GameUI:UpdateTimer(gameDuration - mmax(0, gameElapsed))
    end

    -- Restore destroyed lanes
    if currentMode == "competitive" then
        for laneIdx, expireTime in pairs(destroyedLanes) do
            if now >= expireTime then
                destroyedLanes[laneIdx] = nil
                if ns.GameUI then ns.GameUI:RestoreLane(laneIdx) end
            end
        end
    end

    -- Mirror modifier: flip lane positions periodically
    local activeMods = ns.Modifiers and ns.Modifiers:GetActive() or {}
    if activeMods.mirror and now >= nextMirrorFlip then
        mirrorFlipped = not mirrorFlipped
        nextMirrorFlip = now + 8 + math.random() * 6  -- flip every 8-14 seconds
        if ns.GameUI then ns.GameUI:SetMirrorFlipped(mirrorFlipped) end
    end

    if self.chartNotes then
        -- Chart-driven: every note falls from one shared start line at a constant
        -- speed, so notes bound for lower bars have farther to fall and take longer.
        -- Per-note fall times (and the sort into spawn order) are set up once the
        -- buttons have laid out, in PrepChart. Each note still reaches its button at
        -- gameStartTime + cn.t (on the beat).
        if not self.chartPrepped then self.chartPrepped = self:PrepChart(settings) end
        if self.chartPrepped then
            local notes = self.chartNotes
            while self.chartCursor <= #notes do
                local cn = notes[self.chartCursor]
                if gameElapsed < cn.spawnT then break end
                self:SpawnNote(now, settings, cn.slotInfo, gameStartTime + cn.t, cn.fallTime)
                self.chartCursor = self.chartCursor + 1
            end
        end
    else
        spawnAccumulator = spawnAccumulator + elapsed
        if spawnAccumulator >= settings.spawnInterval then
            spawnAccumulator = spawnAccumulator % settings.spawnInterval
            self:SpawnNote(now, settings)
            -- Doubles: modifier only, not available in competitive (modifier keys conflict)
            if currentMode ~= "competitive" and activeMods.doubles and math.random() < 0.20 then
                self:SpawnNote(now, settings)
            end
        end
    end

    -- Bombs detonate at ~20% overlap (80% of full distance between centers)
    local bombDetonateThreshold = 48 * 0.8 / settings.fallSpeed

    for i = #activeNotes, 1, -1 do
        local note = activeNotes[i]
        if not note then break end
        if not note.evaluated then
            local timeToTarget = note.targetTime - now
            local missThreshold = (note.isBomb and bombDetonateThreshold) or -settings.timingGood
            if timeToTarget < missThreshold then
                if note.isRedHerring then
                    note.evaluated = true
                    note.evaluatedAt = now
                    note.result = "avoided"
                else
                    self:EvaluateNote(note, "miss")
                    if not isRunning then return end
                end
            end
        end
        -- Only keep updating position for unevaluated notes and misses (fall through)
        if note.noteFrame and (not note.evaluated or note.result == "miss" or note.result == "avoided") then
            local fallTime = note.fallTime or (settings.fallDistance / settings.fallSpeed)
            local timeToTarget = note.targetTime - now
            local progress = 1.0 - (timeToTarget / fallTime)
            progress = mmax(progress, 0)
            if ns.GameUI then
                ns.GameUI:UpdateNotePosition(note, progress)
            end
        end
        if note.evaluated and (now - note.evaluatedAt) > 0.6 then
            if ns.GameUI then ns.GameUI:ReleaseNote(note) end
            tremove(activeNotes, i)
        end
    end
end

-- Load the baked onset chart for this track+difficulty into self.chartNotes. The
-- level-1 pulse is always kept (steady backbone, no dead spots); higher tiers (weak
-- beats, eighths, sixteenths) layer on in priority order up to the difficulty's
-- notes-per-second target, evenly subsampling the tier that crosses it so density
-- ramps smoothly. Returns true, or leaves chartNotes nil (false) when no chart
-- exists so OnUpdate falls back to the procedural spawner.
local buildBuckets = { {}, {}, {}, {} }
function Game:BuildChart(key, diff)
    self.chartNotes = nil
    self.chartCursor = 1
    self.chartPrepped = nil
    local chart = ns.SongCharts and key and ns.SongCharts[key]
    if not (chart and chart.notes and #chart.notes > 0) then return false end
    if #availableSlots == 0 then return false end
    local cutoff = gameDuration > 0 and gameDuration or 1e9
    for lvl = 1, 4 do wipe(buildBuckets[lvl]) end
    local lastT = 0
    for ms, _, lvl in ns.SongData.ChartNotes(chart) do
        local t = tonumber(ms) / 1000
        if t <= cutoff then
            local bucket = buildBuckets[tonumber(lvl)]
            bucket[#bucket + 1] = t
            if t > lastT then lastT = t end
        end
    end
    local roundLen = (gameDuration > 0 and gameDuration) or lastT
    if roundLen <= 0 then return false end
    local target = (TARGET_DENSITY[diff] or 2.0) * roundLen
    -- The pulse always plays; layer higher tiers on up to the target.
    local chosen = {}
    local pulse = buildBuckets[1]
    for j = 1, #pulse do chosen[#chosen + 1] = pulse[j] end
    for lvl = 2, 4 do
        local bucket = buildBuckets[lvl]
        local n = #bucket
        local room = target - #chosen
        if n > 0 and room > 0 then
            if n <= room then
                for j = 1, n do chosen[#chosen + 1] = bucket[j] end
            else
                local keep = mfloor(room)
                if keep > 0 then
                    local stride = n / keep
                    for j = 1, keep do
                        chosen[#chosen + 1] = bucket[mmin(n, mfloor((j - 0.5) * stride) + 1)]
                    end
                end
                break
            end
        end
    end
    if #chosen == 0 then return false end
    tsort(chosen)
    local notes = {}
    for i = 1, #chosen do notes[i] = { t = chosen[i] } end
    self:AssignChartBinds(notes, diff)
    self.chartNotes = notes
    self.chartCursor = 1
    return true
end

-- Set up the shared-start-line fall. Every note falls from one screen line (the
-- topmost bar's button + the configured drop) at a constant speed, so a note bound for
-- a lower bar has farther to go and takes proportionally longer. Computes each note's
-- fall time and the moment it must appear at the line, sorts them into that appear
-- order (a later beat on a far bar can appear before an earlier beat on a near one),
-- and hands the line to the UI. Runs once live button positions exist; false = retry.
local function bySpawnT(a, b) return a.spawnT < b.spawnT end

-- Screen-pixel Y of the shared start line: topmost bar's button + the drop + the lift.
-- nil if the buttons have not laid out yet.
function Game:ComputeNoteLine(settings)
    local topY
    for i = 1, #availableSlots do
        local btn = availableSlots[i].button
        if btn then
            local _, cy = btn:GetCenter()
            if cy then
                local sy = cy * btn:GetEffectiveScale()
                if not topY or sy > topY then topY = sy end
            end
        end
    end
    if not topY then return nil end
    -- A side bar reaches high up the screen; the line stops below the top
    -- instead, and notes for the highest buttons get a shorter fall.
    local ceiling = (UIParent:GetTop() - LINE_TOP_ROOM) * UIParent:GetEffectiveScale()
    return mmin(topY + settings.fallDistance + START_LINE_LIFT, ceiling)
end

-- Screen-pixel span (left, right) of the included horizontal bars, from the
-- leftmost to the rightmost button. With only vertical bars, every bar counts.
function Game:ComputeNoteSpan()
    local left, right
    for pass = 1, 2 do
        for _, e in pairs(barExtents) do
            if pass == 2 or (e.r - e.l) >= (e.t - e.b) then
                left = left and mmin(left, e.l) or e.l
                right = right and mmax(right, e.r) or e.r
            end
        end
        if left then break end
    end
    return left, right
end

-- Place the start line + health bar up front (at game start) so neither jumps into
-- place when the first notes spawn.
function Game:PlaceNoteLine()
    local lineY = self:ComputeNoteLine(self:GetSettings())
    if lineY and ns.GameUI then
        ns.GameUI.noteHighwayTop = lineY
        ns.GameUI:PlaceHealthBarAtLine(lineY, self:ComputeNoteSpan())
    end
end

function Game:PrepChart(settings)
    local lineY = ns.GameUI and ns.GameUI.noteHighwayTop
    if not lineY then
        lineY = self:ComputeNoteLine(settings)
        if not lineY then return false end
        if ns.GameUI then
            ns.GameUI.noteHighwayTop = lineY
            ns.GameUI:PlaceHealthBarAtLine(lineY, self:ComputeNoteSpan())
        end
    end
    local fallSpeed = settings.fallSpeed
    local defaultFT = settings.fallDistance / fallSpeed
    local notes = self.chartNotes
    for i = 1, #notes do
        local cn = notes[i]
        local btn = cn.slotInfo and cn.slotInfo.button
        local ft
        if btn then
            local _, cy = btn:GetCenter()
            if cy then ft = mmax(0.2, (lineY - cy * btn:GetEffectiveScale()) / fallSpeed) end
        end
        cn.fallTime = ft or defaultFT
        cn.spawnT = cn.t - cn.fallTime
    end
    if self:SeparateColumns(notes, settings, lineY) then
        for i = 1, #notes do
            local cn = notes[i]
            local btn = cn.slotInfo and cn.slotInfo.button
            local cy
            if btn then cy = select(2, btn:GetCenter()) end
            if cy then
                cn.fallTime = mmax(0.2, (lineY - cy * btn:GetEffectiveScale()) / fallSpeed)
                cn.spawnT = cn.t - cn.fallTime
            end
        end
    end
    -- The highway starts on GO, `go` seconds into the track (its lead-in, see
    -- CountIn), and the first note starts falling right then: the note whose beat
    -- sits nearest one fall time after GO, timed from GO to its beat. Over every
    -- chart its speed is within 10% of the rest on a typical track and 38% at worst.
    -- Any other note due sooner than its fall time after GO could only pop in partway
    -- down, so it is left out, and the score budget follows the notes that are left.
    local go = self.goOffset or 0
    local first, firstOff
    for i = 1, #notes do
        local cn = notes[i]
        if cn.t > go then
            local off = math.abs(math.log(cn.fallTime / (cn.t - go)))
            if not firstOff or off < firstOff then first, firstOff = cn, off end
        end
    end
    if first then
        first.fallTime = first.t - go
        first.spawnT = go
    end
    local kept = 0
    for i = 1, #notes do
        if notes[i].spawnT >= go then
            kept = kept + 1
            notes[kept] = notes[i]
        end
    end
    for i = #notes, kept + 1, -1 do notes[i] = nil end
    self:SetScoreBudget()
    tsort(notes, bySpawnT)
    self.chartCursor = 1
    return true
end

-- Map each chart note onto one of the player's binds. The trainer's job is to
-- exercise the WHOLE layout, so for each note an "active set" of ACTIVE_BINDS[diff]
-- binds (spread across the ease spectrum) is drawn from, and that set's offset drifts
-- across every bind BIND_COVERAGE times over the song. Any short stretch stays a
-- coordinated group; across a full track every bind rotates into play. Consecutive
-- notes never reuse a bind, and notes closer than RAPID_GAP stay on modifier-
-- compatible binds so a fast run is always physically playable.
local assignEase, assignPool = {}, {}
function Game:AssignChartBinds(notes, diff)
    local nSlots = #availableSlots
    wipe(assignEase)
    for i = 1, nSlots do assignEase[i] = availableSlots[i] end
    tsort(assignEase, byEase)                       -- easy (no-modifier) binds first
    local W = mmin(nSlots, ACTIVE_BINDS[diff] or nSlots)
    local total = mmax(1, #notes)
    local prev
    for i = 1, #notes do
        local note = notes[i]
        -- W binds spread across the ease spectrum, offset by a drift that sweeps the
        -- whole layout BIND_COVERAGE times over the song so nothing is left out.
        local drift = ((i - 1) / total) * BIND_COVERAGE
        wipe(assignPool)
        for j = 1, W do
            local frac = (j - 0.5) / W + drift
            assignPool[j] = assignEase[(mfloor(frac * nSlots) % nSlots) + 1]
        end
        local nP = #assignPool
        local rapid = prev and (note.t - prev.t) < RAPID_GAP
        local chosen
        for _ = 1, nP * 3 do
            local cand = assignPool[self:ChartRandInt(nP)]
            local ok = not prev or cand.slot ~= prev.slotInfo.slot
            if ok and rapid then
                ok = modCompatible(cand.mods or "", prev.slotInfo.mods or "")
            end
            if ok then chosen = cand break end
        end
        note.slotInfo = chosen or assignPool[self:ChartRandInt(nP)]
        prev = note
    end
end

-- Two notes in one screen column (bars stacked so their buttons line up) fall
-- the same path at the same speed. Started closer than a note's height apart,
-- one covers the other all the way down. Such a note moves to the nearest bind
-- by ease whose column is clear at that moment, keeping the no-repeat and
-- rapid-run modifier rules. Deterministic for a given bar layout. Returns
-- whether a note moved (its fall time then changes with its button) and how
-- many notes started inside another; countOnly counts without moving.
local COLUMN_MARGIN = 6   -- screen px of clear air between two notes in one column
local columnOrder, columnRank, columnGeo = {}, {}, {}
local function byChartTime(a, b) return a.t < b.t end
function Game:SeparateColumns(notes, settings, lineY, countOnly)
    local speed = settings.fallSpeed
    local noteW = ((ns.GameUI and ns.GameUI.NOTE_SIZE) or 40) * UIParent:GetEffectiveScale()
    local minGap = (noteW + COLUMN_MARGIN) / speed
    wipe(columnGeo)
    local maxFT = 0
    for i = 1, #availableSlots do
        local s = availableSlots[i]
        local btn = s.button
        local cx, cy
        if btn then cx, cy = btn:GetCenter() end
        if cx and cy then
            local bs = btn:GetEffectiveScale()
            local ft = mmax(0.2, (lineY - cy * bs) / speed)
            columnGeo[s.slot] = { x = cx * bs, ft = ft }
            if ft > maxFT then maxFT = ft end
        end
    end
    wipe(assignEase)
    for i = 1, #availableSlots do assignEase[i] = availableSlots[i] end
    tsort(assignEase, byEase)
    wipe(columnRank)
    for i = 1, #assignEase do columnRank[assignEase[i].slot] = i end
    wipe(columnOrder)
    for i = 1, #notes do columnOrder[i] = notes[i] end
    tsort(columnOrder, byChartTime)

    local moved, clashes = false, 0
    for i = 1, #columnOrder do
        local n = columnOrder[i]
        -- Clear: no earlier note in the same column starts within minGap of it.
        local function clear(slotInfo)
            local g = columnGeo[slotInfo.slot]
            if not g then return true end
            local start = n.t - g.ft
            for k = i - 1, 1, -1 do
                local o = columnOrder[k]
                if n.t - o.t > maxFT + minGap then break end
                local og = columnGeo[o.slotInfo.slot]
                if og and mabs(og.x - g.x) < noteW and mabs((o.t - og.ft) - start) < minGap then
                    return false
                end
            end
            return true
        end
        if n.slotInfo and not clear(n.slotInfo) then
            clashes = clashes + 1
        end
        if not countOnly and n.slotInfo and not clear(n.slotInfo) then
            local prev, nxt = columnOrder[i - 1], columnOrder[i + 1]
            local function fits(cand)
                if not columnGeo[cand.slot] then return false end
                for _, nb in ipairs({ prev, nxt }) do
                    if nb and nb.slotInfo then
                        if cand.slot == nb.slotInfo.slot then return false end
                        if mabs(n.t - nb.t) < RAPID_GAP and not modCompatible(cand.mods or "", nb.slotInfo.mods or "") then
                            return false
                        end
                    end
                end
                return clear(cand)
            end
            local r0 = columnRank[n.slotInfo.slot] or 1
            for d = 1, #assignEase do
                local cand = assignEase[r0 - d]
                if not (cand and fits(cand)) then cand = assignEase[r0 + d] end
                if cand and fits(cand) then
                    n.slotInfo = cand
                    moved = true
                    break
                end
            end
        end
    end
    return moved, clashes
end

-- Probe (/btl chartcheck): builds every track's chart on every difficulty
-- against the live bars (no round starts, nothing shows) and counts notes that
-- start inside another note in one screen column, before and after
-- SeparateColumns. Printed, and saved in BoundToLearnDB.chartReport.
function Game:ChartCheck()
    if self:IsRunning() then
        Utils.Print("Chart check runs between rounds.")
        return
    end
    self:DiscoverSlots()
    local lines = {}
    if #availableSlots == 0 then
        lines[1] = "Chart check: no bars picked for the game."
    else
        local savedDuration, before = gameDuration, {}
        local songs = ns.SongData.songs
        for _, diff in ipairs({ "Easy", "Medium", "Hard", "Extreme" }) do
            local preset = DIFFICULTY_PRESETS[diff]
            local lineY = self:ComputeNoteLine(preset)
            local charts, total, was, left, movedNotes, worst = 0, 0, 0, 0, 0, {}
            for _, song in ipairs(lineY and songs or {}) do
                self:SeedChart(song.key, diff)
                gameDuration = ns.SongData.PlayLength(song)
                if self:BuildChart(song.key, diff) then
                    local notes = self.chartNotes
                    for i = 1, #notes do before[i] = notes[i].slotInfo end
                    local _, b = self:SeparateColumns(notes, preset, lineY, true)
                    self:SeparateColumns(notes, preset, lineY)
                    local _, a = self:SeparateColumns(notes, preset, lineY, true)
                    for i = 1, #notes do
                        if notes[i].slotInfo ~= before[i] then movedNotes = movedNotes + 1 end
                    end
                    charts, total, was, left = charts + 1, total + #notes, was + b, left + a
                    if a > 0 then worst[#worst + 1] = sformat("%s %d", song.key, a) end
                    if song.key == BoundToLearn.db.game.songKey then
                        lines[#lines + 1] = sformat("%s on %s (last played): %d of %d notes overlapped, %d after",
                            song.title, diff, b, #notes, a)
                    end
                end
            end
            lines[#lines + 1] = sformat("%s: %d charts, %d notes; overlapping in one column %d before, %d after; %d notes moved%s",
                diff, charts, total, was, left, movedNotes,
                #worst > 0 and (". Still overlapping: " .. table.concat(worst, ", ")) or "")
        end
        gameDuration = savedDuration
        self.chartNotes, self.chartCursor, self.chartPrepped = nil, 1, nil
        lines[#lines + 1] = sformat("Layout: %d binds on the picked bars.", #availableSlots)
    end
    BoundToLearnDB.chartReport = lines
    for _, line in ipairs(lines) do Utils.Print(line) end
end

-- Money-score calibration: a flawless run should land at SCORE_CAP. Spread the cap
-- across the notes a run will actually judge: the chart's note count when a chart
-- is loaded, else a density estimate from the round length and spawn interval.
function Game:SetScoreBudget()
    local budget
    if self.chartNotes and #self.chartNotes > 0 then
        budget = #self.chartNotes
    else
        local dur = gameDuration > 0 and gameDuration or 90
        local interval = self:GetSettings().spawnInterval or 1.2
        budget = mmax(1, mfloor(dur / interval))
    end
    self.scoreNoteBudget = budget
    self.scorePerNote = SCORE_CAP / mmax(1, budget)
end

-- Deterministic per-song, per-difficulty note pathing. Seeding from the song
-- key + difficulty means a given chart draws the same lane sequence every play,
-- so scores are comparable and a run is worth boasting about. Park-Miller keeps
-- the global math.random (used for score-bonus reinforcement) untouched.
local CHART_PRIME = 2147483647
function Game:SeedChart(key, diff)
    local str = (key or "?") .. ":" .. (diff or "Medium")
    local h = 7
    for i = 1, #str do h = (h * 31 + str:byte(i)) % CHART_PRIME end
    if h < 1 then h = h + 1 end
    self.chartState = h
end

function Game:ChartRandInt(n)
    if not self.chartState or n <= 1 then return 1 end
    self.chartState = (16807 * self.chartState) % CHART_PRIME
    return 1 + (self.chartState % n)
end

function Game:SpawnNote(now, settings, forcedSlot, forcedTargetTime, forcedFallTime)
    local activeCount = 0
    for _, n in ipairs(activeNotes) do
        if not n.evaluated then activeCount = activeCount + 1 end
    end
    if activeCount >= settings.maxActiveNotes then return end
    if #availableSlots == 0 then return end

    local chosen
    if forcedSlot then
        -- Chart note: use its lane. Skip if that lane already holds a live note.
        for _, n in ipairs(activeNotes) do
            if not n.evaluated and n.slotInfo.slot == forcedSlot.slot then return end
        end
        chosen = forcedSlot
    else
        local candidates = {}
        for _, slotInfo in ipairs(availableSlots) do
            local inUse = false
            for _, n in ipairs(activeNotes) do
                if not n.evaluated and n.slotInfo.slot == slotInfo.slot then
                    inUse = true
                    break
                end
            end
            if not inUse then tinsert(candidates, slotInfo) end
        end
        if #candidates == 0 then return end
        chosen = candidates[self:ChartRandInt(#candidates)]
    end
    local fallTime = settings.fallDistance / settings.fallSpeed

    local mods = ns.Modifiers and ns.Modifiers:GetActive() or {}

    -- Red herring: show a wrong icon, hitting it docks points (non-competitive)
    local isRedHerring = false
    local displayTexture = nil
    local fakeChance = settings.redHerringChance
    if fakeChance == 0 and mods.fake then fakeChance = 0.18 end
    if currentMode ~= "competitive" and fakeChance > 0 and #availableSlots >= 2 and math.random() < fakeChance then
        isRedHerring = true
        local wrongSlot
        repeat
            wrongSlot = availableSlots[math.random(#availableSlots)]
        until wrongSlot.slot ~= chosen.slot
        displayTexture = wrongSlot.texture
    end

    -- Bomb notes (competitive only): must hit or lane gets destroyed
    local isBomb = false
    if currentMode == "competitive" then
        local CD = ns.CompetitiveData
        local difficulty = BoundToLearn.db.game.difficulty
        local bombChance = CD.bombChance[difficulty] or 0
        if bombChance > 0 and math.random() < bombChance then
            isBomb = true
        end
    end

    -- Angled: optional modifier, or the always-random-angles game setting
    local spawnAngle = nil
    if (mods.angled or settings.randomAngles) and math.random() > 0.3 then
        spawnAngle = math.pi / 2 + (math.random() * math.pi / 2 - math.pi / 4)
    end

    -- Squiggly: random phase offset so notes don't sync
    local squigglyPhase = nil
    if mods.squiggly then
        squigglyPhase = math.random() * math.pi * 2
    end

    local note = {
        slotInfo = chosen,
        spawnTime = now,
        targetTime = forcedTargetTime or (now + fallTime),
        fallTime = forcedFallTime or fallTime,
        evaluated = false,
        evaluatedAt = nil,
        result = nil,
        noteFrame = nil,
        isRedHerring = isRedHerring,
        displayTexture = displayTexture,
        spawnAngle = spawnAngle,
        squigglyPhase = squigglyPhase,
        isBomb = isBomb,
        modifiers = mods,
    }

    tinsert(activeNotes, note)
    if ns.GameUI then ns.GameUI:AcquireNote(note) end

    if isBomb and BoundToLearn.db.game.soundEnabled then
        local willPlay, handle = PlayFuseSound()
        if willPlay then note.bombSoundHandle = handle end
    end
end

function Game:OnKeybindInput(slot)
    if not isRunning or isPaused then return end
    if destroyedLanes[slot] then return end
    local now = GetTime()
    local settings = self:GetSettings()

    local bestNote, bestDelta
    for _, note in ipairs(activeNotes) do
        if not note.evaluated and note.slotInfo.slot == slot then
            local delta = mabs(now - note.targetTime)
            if not bestDelta or delta < bestDelta then
                bestNote = note
                bestDelta = delta
            end
        end
    end

    if not bestNote then return end

    -- Hitting a red herring is always a penalty
    if bestNote.isRedHerring then
        self:EvaluateRedHerring(bestNote)
        return
    end

    -- Bombs can be shot down at any time during their fall
    if bestNote.isBomb then
        self:EvaluateNote(bestNote, "perfect")
        return
    end

    local result
    if bestDelta <= settings.timingPerfect then
        result = "perfect"
    elseif bestDelta <= settings.timingGreat then
        result = "great"
    elseif bestDelta <= settings.timingGood then
        result = "good"
    else
        result = "miss"
    end

    self:EvaluateNote(bestNote, result)
end

function Game:OnKeybindPressed(slot)
    self:OnKeybindInput(slot)
end

local function HasFocusSystem()
    return currentMode ~= "practice"
end

local function GetFocusDrainScale()
    local diff = BoundToLearn.db.game.difficulty
    return FOCUS_DIFF_SCALE[diff] or 1.0
end

local function UpdateFocus(delta)
    if not HasFocusSystem() then return end
    local prev = focus
    focus = mmin(MAX_FOCUS, mmax(0, focus + delta))
    if focus ~= prev and ns.GameUI then
        ns.GameUI:UpdateFocusBar(focus, MAX_FOCUS)
    end
end

local function PlayBooSound(focusPct)
    if not BoundToLearn.db.game.soundEnabled then return end
    local now = GetTime()
    local interval
    if focusPct <= 15 then
        interval = 3
    elseif focusPct <= 35 then
        interval = 6
    elseif focusPct <= 60 then
        interval = 10
    else
        return
    end
    if now - lastBooTime < interval then return end
    lastBooTime = now
    PlaySound(846)  -- igQuestFailed (boo)
end

function Game:EvaluateNote(note, result)
    note.evaluated = true
    note.evaluatedAt = GetTime()
    note.result = result

    hitCounts[result] = hitCounts[result] + 1

    if result == "miss" then
        combo = 0
        multiplier = 1

        -- Bomb miss in competitive: destroy the lane
        if note.isBomb and currentMode == "competitive" then
            local CD = ns.CompetitiveData
            local laneIdx = note.slotInfo.slot
            destroyedLanes[laneIdx] = GetTime() + (CD.laneDestroyDuration or 10)
            if ns.GameUI then ns.GameUI:DestroyLane(laneIdx, CD.laneDestroyDuration) end
        end
    else
        combo = combo + 1
        if combo > maxCombo then maxCombo = combo end
        multiplier = 1
        for _, threshold in ipairs(COMBO_THRESHOLDS) do
            if combo >= threshold then multiplier = multiplier + 1 end
        end
    end

    -- Base money-score: each note is worth its slice of SCORE_CAP, scaled by the
    -- judgment. The combo multiplier no longer inflates the base (that is what let
    -- scores run away); combo still drives the streak titles and its own best.
    local perNote = self.scorePerNote or (SCORE_CAP / 300)
    local points = mfloor(perNote * (JUDGE_WEIGHT[result] or 0))

    -- Bomb hit bonus in competitive
    if note.isBomb and result ~= "miss" then
        points = points + mfloor(perNote * 0.5)
    end

    -- Variable ratio reinforcement: an unpredictable sparkle bonus on streaks. Kept
    -- small and length-independent so a flawless run still lands near SCORE_CAP.
    if result ~= "miss" and combo > 0 and combo % math.random(7, 13) == 0 then
        local bonus = mfloor(perNote * 0.5)
        points = points + bonus
        if ns.GameUI then ns.GameUI:ShowBonusText(bonus) end
    end

    score = score + points

    if ns.GameUI then
        ns.GameUI:ShowHitResult(note, result, points)
        ns.GameUI:UpdateScoreDisplay(score, combo, multiplier)
    end

    if BoundToLearn.db.game.soundEnabled then
        -- Only misses get a sound. Per-hit tones on every perfect/great/good played
        -- constantly and read as noise over the music, so hits are silent.
        if note.isBomb and result == "miss" then
            PlaySound(44191)  -- bomb explosion
        elseif note.isBomb then
            PlaySound(888)    -- bomb shot down
        elseif result == "miss" then
            PlaySound(846)    -- igQuestFailed
        end
    end

    -- Stop bomb fuse sound; hit bombs stay visible until projectile arrives
    if note.isBomb then
        if note.bombSoundHandle then
            StopSound(note.bombSoundHandle, 0)
            note.bombSoundHandle = nil
        end
        if result == "miss" then
            if ns.GameUI then ns.GameUI:ReleaseNote(note) end
        end
    end

    -- Focus system
    if result == "miss" then
        UpdateFocus(-FOCUS_DRAIN.miss * GetFocusDrainScale())
    else
        UpdateFocus(FOCUS_RECOVER[result] or 0)
    end
    if HasFocusSystem() then
        local pct = (focus / MAX_FOCUS) * 100
        PlayBooSound(pct)
        if focus <= 0 then
            self:OnFocusDepleted()
            return
        end
    end
end

function Game:EvaluateRedHerring(note)
    note.evaluated = true
    note.evaluatedAt = GetTime()
    note.result = "redHerring"

    hitCounts.redHerring = hitCounts.redHerring + 1
    combo = 0
    multiplier = 1
    local penalty = -mfloor(self.scorePerNote or (SCORE_CAP / 300))
    score = score + penalty
    if score < 0 then score = 0 end

    if ns.GameUI then
        ns.GameUI:ShowHitResult(note, "redHerring", penalty)
        ns.GameUI:UpdateScoreDisplay(score, combo, multiplier)
    end

    if BoundToLearn.db.game.soundEnabled then
        PlayLaughSound()
    end

    UpdateFocus(-FOCUS_DRAIN.redHerring * GetFocusDrainScale())
    if HasFocusSystem() then
        local pct = (focus / MAX_FOCUS) * 100
        PlayBooSound(pct)
        if focus <= 0 then
            self:OnFocusDepleted()
        end
    end
end
