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
local RED_HERRING_PENALTY = -200
local COMBO_THRESHOLDS = { 5, 15, 30 }

local DIFFICULTY_PRESETS = {
    Easy    = { fallSpeed = 100, fallDistance = 350, maxActiveNotes = 2, spawnInterval = 2.0,
                timingPerfect = 0.12, timingGreat = 0.22, timingGood = 0.35,
                redHerringChance = 0, randomAngles = false },
    Medium  = { fallSpeed = 150, fallDistance = 300, maxActiveNotes = 3, spawnInterval = 1.5,
                timingPerfect = 0.08, timingGreat = 0.15, timingGood = 0.25,
                redHerringChance = 0, randomAngles = false },
    Hard    = { fallSpeed = 200, fallDistance = 280, maxActiveNotes = 4, spawnInterval = 1.2,
                timingPerfect = 0.06, timingGreat = 0.12, timingGood = 0.20,
                redHerringChance = 0.18, randomAngles = false },
    Extreme = { fallSpeed = 240, fallDistance = 260, maxActiveNotes = 5, spawnInterval = 0.9,
                timingPerfect = 0.05, timingGreat = 0.10, timingGood = 0.18,
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

-- Build slots from CompetitiveData spell lists + mock bar buttons from GameUI
function Game:DiscoverCompetitiveSlots(classKey, specIndex)
    wipe(availableSlots)
    wipe(keybindToSlot)

    local CD = ns.CompetitiveData
    if not CD or not CD.classes[classKey] then return end
    local specData = CD.classes[classKey].specs[specIndex]
    if not specData then return end

    local mockBtns = ns.GameUI and ns.GameUI:GetMockBarButtons() or {}
    local bindPrefixes = {
        "ACTIONBUTTON",          -- slots 1-12 (bar 1)
        "MULTIACTIONBAR1BUTTON", -- slots 13-24 (bar 2)
    }

    for i, spellID in ipairs(specData.spells) do
        local barIdx = (i <= 12) and 1 or 2
        local btnIdx = (i <= 12) and i or (i - 12)
        local bindPrefix = bindPrefixes[barIdx]
        local keybind = GetBindingKey(bindPrefix .. btnIdx)

        if keybind then
            local texture = C_Spell.GetSpellTexture(spellID)
            local mockBtn = mockBtns[i]

            if texture and mockBtn then
                local slotInfo = {
                    slot = i,
                    keybind = keybind,
                    texture = texture,
                    button = mockBtn,
                    spellID = spellID,
                    competitive = true,
                }
                tinsert(availableSlots, slotInfo)
                keybindToSlot[keybind] = slotInfo
            end
        end
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
    spawnAccumulator = 0
    gameStartTime = GetTime()
    gameElapsed = 0
    pauseStartTime = 0
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
    if ns.GameUI then
        ns.GameUI:ShowSpecSelector(function(classKey, specIndex)
            self:LaunchCompetitive(classKey, specIndex)
        end)
    end
end

function Game:LaunchCompetitive(classKey, specIndex)
    if isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start game during combat.")
        return
    end

    local db = BoundToLearn.db.game
    db.lastCompClass = classKey
    db.lastCompSpec = specIndex
    currentMode = "competitive"
    gameDuration = db.duration or 60

    -- Create mock bars and discover competitive slots
    if ns.GameUI then
        ns.GameUI:CreateMockBars(classKey, specIndex)
    end
    self:DiscoverCompetitiveSlots(classKey, specIndex)

    if #availableSlots == 0 then
        BoundToLearn:Print("No keybinds found. Make sure you have keybinds set for your main bar and bottom-left bar.")
        if ns.GameUI then ns.GameUI:HideMockBars() end
        return
    end

    ResetGameState()

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

    local CD = ns.CompetitiveData
    local specName = CD.classes[classKey].specs[specIndex].name
    BoundToLearn:Print(sformat("Competitive game started (%s %s). %d keybinds. %ds timer.", CD.classes[classKey].name, specName, #availableSlots, gameDuration))
end

function Game:Stop()
    if not isRunning then return end
    isRunning = false
    isPaused = false
    gameFrame:Hide()
    inputFrame:Hide()
    if ns.GameUI then ns.GameUI:CancelCountdown() end

    for i = #activeNotes, 1, -1 do
        if ns.GameUI then ns.GameUI:ReleaseNote(activeNotes[i]) end
    end
    wipe(activeNotes)

    local duration = gameElapsed
    if duration == 0 then duration = GetTime() - gameStartTime end
    local totalNotes = hitCounts.perfect + hitCounts.great + hitCounts.good + hitCounts.miss

    if ns.Stats and totalNotes > 0 then
        ns.Stats:RecordGameSession({
            score = score,
            maxCombo = maxCombo,
            hitCounts = hitCounts,
            duration = duration,
            mode = currentMode,
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
        })
        if currentMode == "competitive" then
            ns.GameUI:HideMockBars()
        end
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
                    -- Red herrings that pass are silently removed (correct behavior)
                    note.evaluated = true
                    note.evaluatedAt = now
                    note.result = "avoided"
                else
                    self:EvaluateNote(note, "miss")
                end
            else
                local fallTime = settings.fallDistance / settings.fallSpeed
                local progress = 1.0 - (timeToTarget / fallTime)
                progress = mmin(mmax(progress, 0), 1.5)
                if ns.GameUI then
                    ns.GameUI:UpdateNotePosition(note, progress)
                end
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

    local chosen = candidates[math.random(#candidates)]
    local fallTime = settings.fallDistance / settings.fallSpeed

    -- Red herring: show a wrong icon, hitting it docks points
    local isRedHerring = false
    local displayTexture = nil
    if settings.redHerringChance > 0 and #availableSlots >= 2 and math.random() < settings.redHerringChance then
        isRedHerring = true
        local wrongSlot
        repeat
            wrongSlot = availableSlots[math.random(#availableSlots)]
        until wrongSlot.slot ~= chosen.slot
        displayTexture = wrongSlot.texture
    end

    -- Random approach angle for Extreme (limited range, some straight-down)
    local spawnAngle = nil
    if settings.randomAngles and math.random() > 0.3 then
        -- -45 to +45 degrees from vertical: pi/2 is straight up, offset by -pi/4 to +pi/4
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

function Game:EvaluateNote(note, result)
    note.evaluated = true
    note.evaluatedAt = GetTime()
    note.result = result

    hitCounts[result] = hitCounts[result] + 1

    if result == "miss" then
        combo = 0
        multiplier = 1
    else
        combo = combo + 1
        if combo > maxCombo then maxCombo = combo end
        multiplier = 1
        for _, threshold in ipairs(COMBO_THRESHOLDS) do
            if combo >= threshold then multiplier = multiplier + 1 end
        end
    end

    local points = SCORE_VALUES[result] * multiplier

    -- Variable ratio reinforcement: random bonus on streaks
    if combo > 0 and combo % math.random(7, 13) == 0 then
        local bonus = math.random(100, 500)
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
            PlaySound(8554)   -- AuctionWindowClose (short, clean chime)
        elseif result == "great" then
            PlaySound(8459)   -- lootWindowCoinsSound (quick coin clink)
        elseif result == "good" then
            PlaySound(856)    -- igMainMenuOptionCheckboxOn (soft click)
        else
            PlaySound(846)    -- igQuestFailed (low thud)
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
        PlaySound(846)    -- igQuestFailed
    end
end
