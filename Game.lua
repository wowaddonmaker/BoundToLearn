local ADDON_NAME, ns = ...

local Game = {}
ns.Game = Game

local Utils    = ns.Utils
local GetTime  = Utils.GetTime
local tinsert  = Utils.tinsert
local tremove  = Utils.tremove
local wipe     = Utils.wipe
local mabs     = Utils.mabs
local mfloor   = Utils.mfloor
local mmin, mmax = Utils.mmin, Utils.mmax
local ipairs   = Utils.ipairs
local sformat  = Utils.sformat
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
local C_Spell          = C_Spell

local isRunning = false
local isPaused = false
local currentMode = "timed"  -- "timed", "practice", "competitive"

local activeNotes = {}
local availableSlots = {}
local destroyedLanes = {}  -- [slotIndex] = expireTime

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

local SCORE_VALUES = { perfect = 300, great = 200, good = 100, miss = 0 }
local RED_HERRING_PENALTY = -150
local COMBO_THRESHOLDS = { 5, 10, 20, 35 }

-- Focus (health) system
local MAX_FOCUS = 100
local focus = MAX_FOCUS
local focusFailed = false
local FOCUS_DRAIN = { miss = 15, redHerring = 20 }
local FOCUS_RECOVER = { perfect = 8, great = 5, good = 2 }
local FOCUS_DIFF_SCALE = { Easy = 0.6, Medium = 1.0, Hard = 1.2, Extreme = 1.5 }
local lastBooTime = 0
local savedAmbienceVol
local isPlayingGameMusic = false

local DIFFICULTY_MUSIC = {
    Easy    = 53474,   -- Silvermoon city walk (relaxed, warm)
    Medium  = 55957,   -- Grizzly Hills (upbeat, pleasant)
    Hard    = 53755,   -- Karazhan opera (driving, focused)
    Extreme = 53569,   -- L70ETC concert (intense)
}

local DIFFICULTY_PRESETS = {
    Easy    = { fallSpeed = 80, fallDistance = 350, maxActiveNotes = 1, spawnInterval = 2.5,
                timingPerfect = 0.06, timingGreat = 0.20, timingGood = 0.40,
                redHerringChance = 0, randomAngles = false },
    Medium  = { fallSpeed = 150, fallDistance = 300, maxActiveNotes = 3, spawnInterval = 1.5,
                timingPerfect = 0.04, timingGreat = 0.12, timingGood = 0.22,
                redHerringChance = 0, randomAngles = false },
    Hard    = { fallSpeed = 200, fallDistance = 280, maxActiveNotes = 4, spawnInterval = 1.2,
                timingPerfect = 0.03, timingGreat = 0.09, timingGood = 0.18,
                redHerringChance = 0.18, randomAngles = false },
    Extreme = { fallSpeed = 200, fallDistance = 260, maxActiveNotes = 5, spawnInterval = 0.9,
                timingPerfect = 0.025, timingGreat = 0.07, timingGood = 0.15,
                redHerringChance = 0.25, randomAngles = true },
}

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true,
    LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
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
            inputFrame:SetPropagateKeyboardInput(true)
        end
    end)

    ns.eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    ns.eventFrame:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and isRunning then
            self:Pause()
            BoundToLearn:Print("Game paused (combat).")
        end
    end)
end

function Game:GetSettings()
    local db = BoundToLearn.db.game
    local difficulty = db.difficulty
    if difficulty ~= "Custom" and DIFFICULTY_PRESETS[difficulty] then
        return DIFFICULTY_PRESETS[difficulty]
    end
    return {
        fallSpeed = db.fallSpeed,
        fallDistance = db.fallDistance,
        maxActiveNotes = db.maxActiveNotes,
        spawnInterval = db.spawnInterval,
        timingPerfect = db.timingPerfect,
        timingGreat = db.timingGreat,
        timingGood = db.timingGood,
    }
end

function Game:GetMode()
    return currentMode
end

function Game:GetTimeRemaining()
    if gameDuration == 0 then return nil end
    local remaining = gameDuration - gameElapsed
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
    }
    for _, bar in ipairs(barMappings) do
        if bars[bar.key] then
            for i = 1, 12 do
                local slot = bar.startSlot + (i - 1)
                if HasAction(slot) then
                    local keybind = GetBindingKey(bar.bindPrefix .. i)
                    if keybind then
                        local btn = _G[bar.btnPrefix .. i]
                        if btn and btn:IsShown() then
                            local slotInfo = {
                                slot = slot,
                                keybind = keybind,
                                texture = GetActionTexture(slot),
                                button = btn,
                            }
                            tinsert(availableSlots, slotInfo)
                            keybindToSlot[keybind] = slotInfo
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
        local keybind = GetBindingKey("ACTIONBUTTON" .. i)
        local btn = compBtns[i]

        if keybind and btn then
            local slotInfo = {
                slot = i,
                keybind = keybind,
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

local function MuteGameAudio()
    savedAmbienceVol = tonumber(GetCVar("Sound_AmbienceVolume")) or 0.5
    SetCVar("Sound_AmbienceVolume", 0)
end

local function RestoreGameAudio()
    if savedAmbienceVol then SetCVar("Sound_AmbienceVolume", savedAmbienceVol) end
    savedAmbienceVol = nil
    if isPlayingGameMusic then
        StopMusic()
        isPlayingGameMusic = false
    end
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
    spawnAccumulator = 0
    gameStartTime = GetTime()
    gameElapsed = 0
    pauseStartTime = 0
    focus = MAX_FOCUS
    focusFailed = false
    lastBooTime = 0
end

function Game:Start()
    if isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start game during combat.")
        return
    end

    local db = BoundToLearn.db.game
    currentMode = db.mode or "timed"

    if currentMode == "competitive" then
        return self:StartCompetitive()
    end

    self:DiscoverSlots()
    if #availableSlots == 0 then
        BoundToLearn:Print("No keybinds found on your action bars. Bind some keys first.")
        return
    end

    gameDuration = (currentMode == "practice") and 0 or (db.duration or 60)

    ResetGameState()

    if BoundToLearn.db.game.soundEnabled then
        local track = DIFFICULTY_MUSIC[db.difficulty]
        MuteGameAudio()
        if track then
            PlayMusic(track)
            isPlayingGameMusic = true
        end
    end

    if ns.GameUI then
        ns.GameUI:OnGameStart(availableSlots)
    end

    local countdownDuration = 3
    if ns.GameUI then
        ns.GameUI:ShowCountdown(countdownDuration, function()
            gameStartTime = GetTime()
            gameFrame:Show()
            inputFrame:Show()
        end)
    else
        gameFrame:Show()
        inputFrame:Show()
    end

    BoundToLearn:Print(sformat("Game started (%s). %d keybinds in play. Press ESC to stop.", currentMode, #availableSlots))
end

function Game:StartCompetitive()
    if isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start game during combat.")
        return
    end

    local db = BoundToLearn.db.game
    currentMode = "competitive"
    gameDuration = db.duration or 90

    if ns.GameUI then
        ns.GameUI:CreateCompBar()
    end
    self:DiscoverCompetitiveSlots()

    if #availableSlots == 0 then
        BoundToLearn:Print("No keybinds found on keys 1-5. Bind your first 5 action bar slots.")
        if ns.GameUI then ns.GameUI:HideCompBar() end
        return
    end

    ResetGameState()

    if BoundToLearn.db.game.soundEnabled then
        MuteGameAudio()
    end

    if ns.GameUI then
        ns.GameUI:OnGameStart(availableSlots)
    end

    if ns.GameUI then
        ns.GameUI:ShowCountdown(3, function()
            gameStartTime = GetTime()
            gameFrame:Show()
            inputFrame:Show()
        end)
    else
        gameFrame:Show()
        inputFrame:Show()
    end

    BoundToLearn:Print(sformat("Competitive game started. %d lanes. %ds timer.", #availableSlots, gameDuration))
end

function Game:Stop()
    if not isRunning then return end
    isRunning = false
    isPaused = false
    gameFrame:Hide()
    inputFrame:Hide()
    RestoreGameAudio()
    if ns.GameUI then ns.GameUI:CancelCountdown() end

    for i = #activeNotes, 1, -1 do
        if ns.GameUI then ns.GameUI:ReleaseNote(activeNotes[i]) end
    end
    wipe(activeNotes)

    local duration = gameElapsed
    if duration == 0 then duration = GetTime() - gameStartTime end
    local totalNotes = hitCounts.perfect + hitCounts.great + hitCounts.good + hitCounts.miss

    local difficulty = BoundToLearn.db.game.difficulty

    if ns.Stats and totalNotes > 0 then
        ns.Stats:RecordGameSession({
            score = score,
            maxCombo = maxCombo,
            hitCounts = hitCounts,
            duration = duration,
            mode = currentMode,
            difficulty = difficulty,
        })
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

    BoundToLearn:Print(sformat("Game over. Score: %d | Best combo: %d", score, maxCombo))
end

function Game:Pause()
    if currentMode == "competitive" then
        -- Competitive: pausing zeroes your score
        score = 0
        combo = 0
        multiplier = 1
        BoundToLearn:Print("Score reset to 0 (competitive mode).")
        if ns.GameUI then
            ns.GameUI:UpdateScoreDisplay(score, combo, multiplier)
        end
    end

    isPaused = true
    pauseStartTime = GetTime()
    gameFrame:Hide()
    inputFrame:Hide()
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
        ns.GameUI:UpdateTimer(gameDuration - gameElapsed)
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

    spawnAccumulator = spawnAccumulator + elapsed
    if spawnAccumulator >= settings.spawnInterval then
        spawnAccumulator = spawnAccumulator - settings.spawnInterval
        self:SpawnNote(now, settings)
    end

    for i = #activeNotes, 1, -1 do
        local note = activeNotes[i]
        if not note.evaluated then
            local timeToTarget = note.targetTime - now
            if timeToTarget < -settings.timingGood then
                if note.isRedHerring then
                    note.evaluated = true
                    note.evaluatedAt = now
                    note.result = "avoided"
                else
                    self:EvaluateNote(note, "miss")
                end
            end
        end
        -- Only keep updating position for unevaluated notes and misses (fall through)
        if note.noteFrame and (not note.evaluated or note.result == "miss" or note.result == "avoided") then
            local fallTime = settings.fallDistance / settings.fallSpeed
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

function Game:SpawnNote(now, settings)
    local activeCount = 0
    for _, n in ipairs(activeNotes) do
        if not n.evaluated then activeCount = activeCount + 1 end
    end
    if activeCount >= settings.maxActiveNotes then return end
    if #availableSlots == 0 then return end

    local candidates = {}
    for _, slotInfo in ipairs(availableSlots) do
        -- Skip destroyed lanes in competitive
        if destroyedLanes[slotInfo.slot] then
            -- lane offline, skip
        else
            local inUse = false
            for _, n in ipairs(activeNotes) do
                if not n.evaluated and n.slotInfo.slot == slotInfo.slot then
                    inUse = true
                    break
                end
            end
            if not inUse then tinsert(candidates, slotInfo) end
        end
    end
    if #candidates == 0 then return end

    local chosen = candidates[math.random(#candidates)]
    local fallTime = settings.fallDistance / settings.fallSpeed

    -- Red herring: show a wrong icon, hitting it docks points (non-competitive)
    local isRedHerring = false
    local displayTexture = nil
    if currentMode ~= "competitive" and settings.redHerringChance > 0 and #availableSlots >= 2 and math.random() < settings.redHerringChance then
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

    -- Random approach angle for Extreme (limited range, some straight-down)
    local spawnAngle = nil
    if settings.randomAngles and math.random() > 0.3 then
        spawnAngle = math.pi / 2 + (math.random() * math.pi / 2 - math.pi / 4)
    end

    local note = {
        slotInfo = chosen,
        spawnTime = now,
        targetTime = now + fallTime,
        evaluated = false,
        evaluatedAt = nil,
        result = nil,
        noteFrame = nil,
        isRedHerring = isRedHerring,
        displayTexture = displayTexture,
        spawnAngle = spawnAngle,
        isBomb = isBomb,
    }

    tinsert(activeNotes, note)
    if ns.GameUI then ns.GameUI:AcquireNote(note) end
end

function Game:OnKeybindInput(slot)
    if not isRunning or isPaused then return end
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
            if BoundToLearn.db.game.soundEnabled then
                PlaySound(888)  -- combo milestone
            end
        end
    else
        combo = combo + 1
        if combo > maxCombo then maxCombo = combo end
        multiplier = 1
        for _, threshold in ipairs(COMBO_THRESHOLDS) do
            if combo >= threshold then multiplier = multiplier + 1 end
        end
    end

    local points = SCORE_VALUES[result] * multiplier

    -- Bomb hit bonus in competitive
    if note.isBomb and result ~= "miss" then
        points = points + 150
    end

    -- Variable ratio reinforcement: random bonus on streaks
    if combo > 0 and combo % math.random(7, 13) == 0 then
        local bonus = math.random(200, 500)
        points = points + bonus
        if ns.GameUI then ns.GameUI:ShowBonusText(bonus) end
    end

    score = score + points

    if ns.GameUI then
        ns.GameUI:ShowHitResult(note, result, points)
        ns.GameUI:UpdateScoreDisplay(score, combo, multiplier)
    end

    if BoundToLearn.db.game.soundEnabled then
        if result == "perfect" then
            PlaySound(891)   -- igBackPackCoinSelect (coin jingle)
        elseif result == "great" then
            PlaySound(891)   -- igBackPackCoinSelect (coin, same but less flashy context)
        elseif result == "good" then
            PlaySound(1217)  -- igMiniMapOpen (soft ping)
        else
            PlaySound(846)   -- igQuestFailed
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
    score = score + RED_HERRING_PENALTY
    if score < 0 then score = 0 end

    if ns.GameUI then
        ns.GameUI:ShowHitResult(note, "redHerring", RED_HERRING_PENALTY)
        ns.GameUI:UpdateScoreDisplay(score, combo, multiplier)
    end

    if BoundToLearn.db.game.soundEnabled then
        PlaySound(882)  -- igAbilityPageTurn (distinct from miss)
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
