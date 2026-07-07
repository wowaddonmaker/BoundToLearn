local ADDON_NAME, ns = ...

local Stats = {}
ns.Stats = Stats

local Utils   = ns.Utils
local tinsert = Utils.tinsert
local tremove = Utils.tremove
local mfloor  = Utils.mfloor
local ipairs  = Utils.ipairs
local GetTime = Utils.GetTime

local MAX_SESSIONS = 100

function Stats:Initialize()
    -- Nothing to do on init; DB is already merged by Core
end

function Stats:RecordTrackerSession(sessionData)
    local duration = GetTime() - sessionData.startTime
    if duration < 10 then return end

    local total = sessionData.clicks + sessionData.keybinds
    if total == 0 then return end
    local ratio = (sessionData.keybinds / total) * 100

    local summary = {
        timestamp = time(),
        duration = mfloor(duration),
        type = "tracker",
        clicks = sessionData.clicks,
        keybinds = sessionData.keybinds,
        ratio = mfloor(ratio * 10) / 10,
    }
    self:AddSession(summary)

    local db = BoundToLearn.db.stats
    db.lifetimeClicks = db.lifetimeClicks + sessionData.clicks
    db.lifetimeKeybinds = db.lifetimeKeybinds + sessionData.keybinds

    if ratio > db.personalBest.bestKeybindRatio then
        db.personalBest.bestKeybindRatio = mfloor(ratio * 10) / 10
    end
end

function Stats:RecordGameSession(gameData)
    local totalNotes = gameData.hitCounts.perfect + gameData.hitCounts.great
                     + gameData.hitCounts.good + gameData.hitCounts.miss
    if totalNotes == 0 then return end

    local accuracy = ((totalNotes - gameData.hitCounts.miss) / totalNotes) * 100

    local summary = {
        timestamp = time(),
        duration = mfloor(gameData.duration),
        type = "game",
        score = gameData.score,
        combo = gameData.maxCombo,
        perfect = gameData.hitCounts.perfect,
        great = gameData.hitCounts.great,
        good = gameData.hitCounts.good,
        miss = gameData.hitCounts.miss,
        accuracy = mfloor(accuracy * 10) / 10,
    }
    self:AddSession(summary)

    local db = BoundToLearn.db.stats
    db.lifetimeGameNotes = db.lifetimeGameNotes + totalNotes
    db.lifetimeGameHits = db.lifetimeGameHits + (totalNotes - gameData.hitCounts.miss)

    local pb = db.personalBest
    if summary.score > pb.highestScore then
        pb.highestScore = summary.score
    end
    if summary.combo > pb.longestCombo then
        pb.longestCombo = summary.combo
    end
    if accuracy > pb.bestAccuracy then
        pb.bestAccuracy = mfloor(accuracy * 10) / 10
    end

    -- Per-difficulty bests
    local diff = gameData.difficulty
    if diff and db.difficultyBest then
        if not db.difficultyBest[diff] then
            db.difficultyBest[diff] = { highestScore = 0, longestCombo = 0 }
        end
        local db2 = db.difficultyBest[diff]
        if summary.score > db2.highestScore then
            db2.highestScore = summary.score
        end
        if summary.combo > db2.longestCombo then
            db2.longestCombo = summary.combo
        end

        -- Track competitive bests separately for competitive achievements
        if gameData.mode == "competitive" then
            if not db.difficultyBest.Competitive then
                db.difficultyBest.Competitive = { highestScore = 0, longestCombo = 0 }
            end
            local compDB = db.difficultyBest.Competitive
            if summary.score > compDB.highestScore then
                compDB.highestScore = summary.score
            end
            if summary.combo > compDB.longestCombo then
                compDB.longestCombo = summary.combo
            end
        end
    end

end

function Stats:RecordQuizSession(quizData)
    local summary = {
        timestamp = time(),
        type = "quiz",
        elapsed = mfloor(quizData.elapsed * 10) / 10,
        totalAbilities = quizData.totalAbilities,
        rounds = quizData.rounds,
        wrongAnswers = quizData.wrongAnswers or 0,
    }
    self:AddSession(summary)

    local db = BoundToLearn.db.stats
    db.lifetimeQuizzes = db.lifetimeQuizzes + 1
    db.lifetimeQuizAbilities = db.lifetimeQuizAbilities + quizData.totalAbilities

    local pb = db.personalBest
    if pb.fastestQuiz == 0 or quizData.elapsed < pb.fastestQuiz then
        pb.fastestQuiz = mfloor(quizData.elapsed * 10) / 10
    end
end

function Stats:AddSession(summary)
    local sessions = BoundToLearn.db.stats.sessions
    tinsert(sessions, summary)
    while #sessions > MAX_SESSIONS do
        tremove(sessions, 1)
    end
end

function Stats:GetRecentSessions(sessionType, count)
    local result = {}
    local sessions = BoundToLearn.db.stats.sessions
    for i = #sessions, 1, -1 do
        if sessions[i].type == sessionType then
            tinsert(result, sessions[i])
            if #result >= count then break end
        end
    end
    return result
end

function Stats:GetFilteredSessions(sessionType, count, minTimestamp)
    local result = {}
    local sessions = BoundToLearn.db.stats.sessions
    for i = #sessions, 1, -1 do
        local s = sessions[i]
        if s.type == sessionType and (not minTimestamp or s.timestamp >= minTimestamp) then
            tinsert(result, s)
            if #result >= count then break end
        end
    end
    return result
end

function Stats:GetLifetimeTrackerRatio()
    local db = BoundToLearn.db.stats
    local total = db.lifetimeClicks + db.lifetimeKeybinds
    if total == 0 then return 0 end
    return (db.lifetimeKeybinds / total) * 100
end

function Stats:GetLifetimeGameAccuracy()
    local db = BoundToLearn.db.stats
    if db.lifetimeGameNotes == 0 then return 0 end
    return (db.lifetimeGameHits / db.lifetimeGameNotes) * 100
end
