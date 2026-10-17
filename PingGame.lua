local ADDON_NAME, ns = ...

local PingGame = {}
ns.PingGame = PingGame

local Utils    = ns.Utils
local GetTime  = Utils.GetTime
local tinsert  = Utils.tinsert
local tremove  = Utils.tremove
local wipe     = Utils.wipe
local mfloor   = Utils.mfloor
local mmin     = Utils.mmin
local mmax     = Utils.mmax
local ipairs   = Utils.ipairs
local CreateFrame = Utils.CreateFrame

local GetBindingKey = GetBindingKey

local isRunning = false
local isPaused = false
local gameFrame
local activeTargets = {}
local score = 0
local combo = 0
local maxCombo = 0
local hits = 0
local wrongType = 0    -- correct target, wrong ping type
local expired = 0
local gameStartTime = 0
local gameDuration = 30
local gameElapsed = 0
local pauseStartTime = 0
local spawnAccumulator = 0
local targetIDCounter = 0
local difficulty = "Normal"
local health = 100
local MAX_HEALTH = 100

-- Ping action -> binding name mapping
local PING_BINDINGS = {
    attack  = "PINGATTACK",
    assist  = "PINGASSIST",
    warning = "PINGWARNING",
    onmyway = "PINGONMYWAY",
}

-- Target types
local TARGET_ENEMY   = 1  -- requires attack ping
local TARGET_ALLY    = 2  -- requires assist ping
local TARGET_HAZARD  = 3  -- requires warning ping
local TARGET_TYPES   = { TARGET_ENEMY, TARGET_ALLY, TARGET_HAZARD }

PingGame.TARGET_ENEMY  = TARGET_ENEMY
PingGame.TARGET_ALLY   = TARGET_ALLY
PingGame.TARGET_HAZARD = TARGET_HAZARD

-- Which ping action is correct for each target type
local CORRECT_PING = {
    [TARGET_ENEMY]  = "attack",
    [TARGET_ALLY]   = "assist",
    [TARGET_HAZARD] = "warning",
}

PingGame.CORRECT_PING = CORRECT_PING

-- Friendly names for the target-relevant pings, used by the "bind all pings"
-- prompt. onmyway is intentionally excluded: it is not a target ping.
local PING_LABEL = { attack = "Attack", assist = "Assist", warning = "Warning" }

-- Difficulty follows how aim trainers ramp: the entry tier is one large target at
-- a time that waits long and is replaced the moment it is hit; each tier above adds
-- one target on screen and shortens the timeout and the size. A ping asks more than
-- a click (find the target, read its type, press the right modifier and key), so
-- the timeouts sit well above a click trainer's. damage scales every health loss.
local DIFFICULTY_SETTINGS = {
    Easy    = { spawnInterval = 0.6,  targetLifetime = 6.0, maxActive = 1, duration = 30, sizeScale = 1.3,  damage = 0.5 },
    Normal  = { spawnInterval = 1.2,  targetLifetime = 4.5, maxActive = 2, duration = 45, sizeScale = 1.1,  damage = 0.75 },
    Hard    = { spawnInterval = 1.0,  targetLifetime = 3.2, maxActive = 3, duration = 60, sizeScale = 0.95, damage = 1.0 },
    Extreme = { spawnInterval = 0.75, targetLifetime = 2.2, maxActive = 4, duration = 60, sizeScale = 0.82, damage = 1.25 },
}

PingGame.DIFFICULTIES = { "Easy", "Normal", "Hard", "Extreme" }

-- Scoring
local SCORE_HIT         = 100
local SCORE_SPEED_BONUS = 200
local SCORE_WRONG_TYPE  = -50   -- right target, wrong ping type
local SCORE_EXPIRED     = -50

-- Health damage/heal per event (scales with difficulty)
local HEALTH_HIT        = 5     -- heal on correct ping
local HEALTH_WRONG_TYPE = -12   -- wrong ping type
local HEALTH_MISS       = -8    -- ping into empty space
local HEALTH_EXPIRED    = -10   -- target timed out
local HEALTH_COMBO_HEAL = 2     -- bonus heal per combo level (capped)

local function GetSettings()
    return DIFFICULTY_SETTINGS[difficulty]
end

-- A health loss (amount < 0), scaled by the difficulty's damage.
local function Hurt(amount)
    local s = GetSettings()
    health = mmax(0, health + amount * (s and s.damage or 1))
end

-- Build keybind -> ping action reverse lookup
local pingKeybinds = {}  -- key string -> ping action name

local function RefreshPingKeybinds()
    wipe(pingKeybinds)
    for action, binding in pairs(PING_BINDINGS) do
        local key1, key2 = GetBindingKey(binding)
        if key1 then pingKeybinds[key1] = action end
        if key2 then pingKeybinds[key2] = action end
    end
end

function PingGame:GetPingKeybinds()
    return pingKeybinds
end

function PingGame:HasPingKeybinds()
    return next(pingKeybinds) ~= nil
end

-- True only when every target-relevant ping (attack/assist/warning) is bound.
function PingGame:AreAllPingsKeybound()
    for i = 1, #TARGET_TYPES do
        if not GetBindingKey(PING_BINDINGS[CORRECT_PING[TARGET_TYPES[i]]]) then
            return false
        end
    end
    return true
end

-- Display names of any target-relevant pings that are not yet bound.
function PingGame:GetUnboundPingNames()
    local names = {}
    for i = 1, #TARGET_TYPES do
        local action = CORRECT_PING[TARGET_TYPES[i]]
        if not GetBindingKey(PING_BINDINGS[action]) then
            names[#names + 1] = PING_LABEL[action]
        end
    end
    return names
end

function PingGame:Initialize()
    gameFrame = CreateFrame("Frame", "BoundToLearnPingGameFrame", UIParent)
    gameFrame:Hide()
    gameFrame:SetScript("OnUpdate", function(_, elapsed)
        self:OnUpdate(elapsed)
    end)

    ns.eventFrame:HookScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and isRunning then
            self:Pause()
        end
    end)
end

function PingGame:IsRunning()
    return isRunning
end

function PingGame:GetDifficulty()
    return difficulty
end

function PingGame:SetDifficulty(diff)
    if DIFFICULTY_SETTINGS[diff] then
        difficulty = diff
    end
end

function PingGame:Start()
    if isRunning then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start during combat.")
        return
    end

    RefreshPingKeybinds()
    if not self:HasPingKeybinds() then
        BoundToLearn:Print("No ping keybinds found. Bind Attack Ping and Warning Ping in your Key Bindings first.")
        return
    end

    local settings = GetSettings()
    gameDuration = settings.duration

    score = 0
    combo = 0
    maxCombo = 0
    hits = 0
    wrongType = 0
    expired = 0
    health = MAX_HEALTH
    spawnAccumulator = 999  -- immediate first spawn
    targetIDCounter = 0
    gameElapsed = 0
    pauseStartTime = 0
    wipe(activeTargets)

    isRunning = true
    isPaused = false
    gameStartTime = GetTime()

    if ns.PingGameUI then
        ns.PingGameUI:OnGameStart()
    end

    gameFrame:Show()
end

function PingGame:Stop()
    if not isRunning then return end
    isRunning = false
    isPaused = false
    gameFrame:Hide()

    if ns.PingGameUI then
        for i = #activeTargets, 1, -1 do
            ns.PingGameUI:ReleaseTarget(activeTargets[i])
        end
    end
    wipe(activeTargets)

    local totalTargetable = hits + wrongType + expired
    local accuracy = totalTargetable > 0 and mfloor(hits / totalTargetable * 100) or 0

    local results = {
        score = mmax(0, score),
        hits = hits,
        wrongType = wrongType,
        expired = expired,
        maxCombo = maxCombo,
        accuracy = accuracy,
        elapsed = gameElapsed,
        difficulty = difficulty,
        healthDepleted = health <= 0,
    }

    if ns.PingGameUI then
        ns.PingGameUI:OnGameEnd(results)
    end

    if ns.Stats then
        ns.Stats:AddSession({
            timestamp = time(),
            type = "ping",
            score = results.score,
            accuracy = accuracy,
            combo = maxCombo,
            difficulty = difficulty,
            elapsed = mfloor(gameElapsed * 10) / 10,
        })
    end
end

function PingGame:Pause()
    if not isRunning or isPaused then return end
    isPaused = true
    pauseStartTime = GetTime()
    if ns.PingGameUI then ns.PingGameUI:ShowPause() end
end

function PingGame:Resume()
    if not isPaused then return end
    if InCombatLockdown() then
        BoundToLearn:Print("Resume once you are out of combat.")
        return
    end
    isPaused = false
    local pauseDuration = GetTime() - pauseStartTime
    gameStartTime = gameStartTime + pauseDuration
    if ns.PingGameUI then ns.PingGameUI:HidePause() end
end

function PingGame:OnUpdate(elapsed)
    if not isRunning or isPaused then return end

    gameElapsed = GetTime() - gameStartTime

    if gameElapsed >= gameDuration then
        self:Stop()
        return
    end

    local settings = GetSettings()
    local now = GetTime()

    -- Expire old targets
    for i = #activeTargets, 1, -1 do
        local target = activeTargets[i]
        if now >= target.expireTime then
            expired = expired + 1
            score = score + SCORE_EXPIRED
            combo = 0
            Hurt(HEALTH_EXPIRED)
            if ns.PingGameUI then
                ns.PingGameUI:OnTargetExpired(target)
            end
            if ns.PingGameUI then
                ns.PingGameUI:ReleaseTarget(target)
            end
            tremove(activeTargets, i)
        end
    end

    -- Spawn new targets
    spawnAccumulator = spawnAccumulator + elapsed
    -- Time spent full does not bank up: a freed slot refills once, not in a burst.
    if #activeTargets >= settings.maxActive then
        spawnAccumulator = mmin(spawnAccumulator, settings.spawnInterval)
    end
    if spawnAccumulator >= settings.spawnInterval and #activeTargets < settings.maxActive then
        spawnAccumulator = spawnAccumulator - settings.spawnInterval
        self:SpawnTarget(settings)
    end

    -- Check for health depletion
    if health <= 0 then
        self:Stop()
        return
    end

    if ns.PingGameUI then
        ns.PingGameUI:OnUpdate(gameElapsed, gameDuration, score, combo, health / MAX_HEALTH)
    end
end

function PingGame:SpawnTarget(settings)
    local targetType = TARGET_TYPES[math.random(#TARGET_TYPES)]

    targetIDCounter = targetIDCounter + 1
    local target = {
        id = targetIDCounter,
        targetType = targetType,
        spawnTime = GetTime(),
        expireTime = GetTime() + settings.targetLifetime,
        lifetime = settings.targetLifetime,
        sizeScale = settings.sizeScale or 1,
    }

    tinsert(activeTargets, target)

    if ns.PingGameUI then
        ns.PingGameUI:OnTargetSpawned(target)
    end
end

-- Called when player presses a ping key while hovering a target
function PingGame:OnPingAction(targetID, pingAction)
    if not isRunning or isPaused then return end

    for i, target in ipairs(activeTargets) do
        if target.id == targetID then
            local now = GetTime()
            local reactionTime = now - target.spawnTime

            local correctAction = CORRECT_PING[target.targetType]
            local wasHit = pingAction == correctAction
            if wasHit then
                -- Correct ping type
                hits = hits + 1
                local speedBonus = mfloor(SCORE_SPEED_BONUS * mmax(0, 1 - reactionTime / target.lifetime))
                local points = SCORE_HIT + speedBonus
                score = score + points
                combo = combo + 1
                if combo > maxCombo then maxCombo = combo end
                local comboHeal = mmin(combo, 5) * HEALTH_COMBO_HEAL
                health = mmin(MAX_HEALTH, health + HEALTH_HIT + comboHeal)
                if ns.PingGameUI then
                    ns.PingGameUI:OnTargetResult(target, "hit", reactionTime, points, pingAction)
                end
            else
                -- Wrong ping type
                wrongType = wrongType + 1
                score = score + SCORE_WRONG_TYPE
                combo = 0
                Hurt(HEALTH_WRONG_TYPE)
                if ns.PingGameUI then
                    ns.PingGameUI:OnTargetResult(target, "wrong_type", reactionTime, nil, pingAction)
                end
            end

            if ns.PingGameUI then
                ns.PingGameUI:ReleaseTarget(target)
            end
            tremove(activeTargets, i)
            -- Instant respawn on a correct ping keeps a steady number of targets on
            -- screen (aim-trainer style) instead of waiting for the spawn timer.
            local respawnSettings = GetSettings()
            if wasHit and respawnSettings and #activeTargets < respawnSettings.maxActive then
                self:SpawnTarget(respawnSettings)
            end
            return
        end
    end
end

-- Called when player presses a ping key but isn't hovering any target
function PingGame:OnPingMiss(pingAction)
    if not isRunning or isPaused then return end
    combo = 0
    Hurt(HEALTH_MISS)
    if ns.PingGameUI then
        ns.PingGameUI:OnMissClick(pingAction)
    end
end

function PingGame:GetTimeRemaining()
    return mmax(0, gameDuration - gameElapsed)
end
