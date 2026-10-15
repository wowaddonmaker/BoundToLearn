local ADDON_NAME, ns = ...

local Leaderboard = {}
ns.Leaderboard = Leaderboard

local Utils   = ns.Utils
local sformat = Utils.sformat
local tinsert = Utils.tinsert
local tremove = Utils.tremove
local pairs   = Utils.pairs
local ipairs  = Utils.ipairs
local mfloor  = Utils.mfloor
local GetTime = Utils.GetTime

local PREFIX = "BtL"
local MAX_ENTRIES = 50
local CHALLENGE_TIMEOUT = 15

local playerName, playerRealm, playerClass
local ownNames = {}
local pendingChallenge = nil  -- { target=name, sent=time } or { from=name, sent=time }
local activeChallenge = nil   -- { opponent=name, difficulty=str, startTime=num }
local partyScores = {}        -- { ["Name-Realm"] = { score, difficulty, combo, accuracy, time } }

function Leaderboard:Initialize()
    C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)

    -- Sender strings carry the realm without spaces. Forever names come as
    -- (first, surname), so every form of our own name is kept for matching.
    playerRealm = GetNormalizedRealmName() or (GetRealmName():gsub("[%s%-']", ""))
    playerName = GetUnitName("player", false) or UnitName("player")
    for _, name in ipairs({ playerName, (UnitName("player")), GetUnitName("player", true) }) do
        ownNames[name] = true
        ownNames[name .. "-" .. playerRealm] = true
    end
    playerClass = select(2, UnitClass("player"))

    local f = CreateFrame("Frame")
    f:RegisterEvent("CHAT_MSG_ADDON")
    f:RegisterEvent("GROUP_ROSTER_UPDATE")
    f:SetScript("OnEvent", function(_, event, ...)
        if event == "CHAT_MSG_ADDON" then
            self:OnAddonMessage(...)
        elseif event == "GROUP_ROSTER_UPDATE" then
            self:CleanPartyScores()
        end
    end)
end

-- Message protocol: fields separated by |
-- SC|difficulty|score|combo|accuracy|mode|class|timestamp  (score broadcast)
-- CH|senderName|senderRealm                                (challenge invite)
-- CA|senderName|senderRealm                                (challenge accept)
-- CD|senderName|senderRealm                                (challenge decline)
-- CS|score|difficulty|combo|accuracy                       (challenge result)

local function Pack(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    return table.concat(parts, "|")
end

local function Unpack(msg)
    local parts = {}
    for part in msg:gmatch("[^|]+") do
        parts[#parts + 1] = part
    end
    return parts
end

local function GetFullName(name, realm)
    if realm and realm ~= "" and realm ~= playerRealm then
        return name .. "-" .. realm
    end
    return name
end

local function Send(msg, channel, target)
    C_ChatInfo.SendAddonMessage(PREFIX, msg, channel, target)
end

-- Broadcasting

function Leaderboard:BroadcastScore(results)
    if not results or results.mode == "practice" then return end
    if results.score <= 0 then return end

    local totalNotes = results.totalNotes or 0
    if totalNotes == 0 then return end
    local accuracy = mfloor(ns.Utils.HitAccuracy(results.hitCounts))

    local msg = Pack("SC",
        results.difficulty or "Medium",
        results.score,
        results.maxCombo,
        accuracy,
        results.mode or "timed",
        playerClass,
        time()
    )

    -- Send to guild
    if IsInGuild() then
        Send(msg, "GUILD")
    end

    -- Send to party/raid
    if IsInGroup() then
        local channel = IsInRaid() and "RAID" or "PARTY"
        Send(msg, channel)
    end

    -- Also send challenge result if in active challenge
    if activeChallenge then
        local csMsg = Pack("CS", results.score, results.difficulty or "Medium",
            results.maxCombo, accuracy)
        if IsInGroup() then
            Send(csMsg, IsInRaid() and "RAID" or "PARTY")
        end
    end
end

-- Receiving

function Leaderboard:OnAddonMessage(prefix, msg, channel, sender)
    if prefix ~= PREFIX then return end

    local parts = Unpack(msg)
    if not parts[1] then return end

    local cmd = parts[1]
    -- Extract sender name/realm from WoW sender format "Name-Realm"
    local sName, sRealm = strsplit("-", sender)
    if not sRealm then sRealm = playerRealm end
    local fullName = GetFullName(sName, sRealm)

    -- Ignore own messages
    if ownNames[sender] or (ownNames[sName] and sRealm == playerRealm) then return end
    Utils.DebugPrint("addon message sender:", sender)

    if cmd == "SC" then
        self:HandleScoreBroadcast(parts, fullName, sName, sRealm)
    elseif cmd == "CH" then
        self:HandleChallengeInvite(parts, fullName, sName)
    elseif cmd == "CA" then
        self:HandleChallengeAccept(parts, fullName, sName)
    elseif cmd == "CD" then
        self:HandleChallengeDecline(parts, fullName, sName)
    elseif cmd == "CS" then
        self:HandleChallengeResult(parts, fullName, sName)
    end
end

function Leaderboard:HandleScoreBroadcast(parts, fullName, sName, sRealm)
    -- SC|difficulty|score|combo|accuracy|mode|class|timestamp
    local difficulty = parts[2]
    local score = tonumber(parts[3]) or 0
    local combo = tonumber(parts[4]) or 0
    local accuracy = tonumber(parts[5]) or 0
    local mode = parts[6] or "timed"
    local class = parts[7] or "WARRIOR"
    local ts = tonumber(parts[8]) or time()

    if score <= 0 then return end

    -- Store in guild leaderboard
    local entry = {
        name = fullName,
        score = score,
        combo = combo,
        accuracy = accuracy,
        mode = mode,
        class = class,
        timestamp = ts,
    }

    self:AddToLeaderboard(difficulty, entry)

    -- Store as party score if in group
    if IsInGroup() then
        partyScores[fullName] = {
            score = score,
            difficulty = difficulty,
            combo = combo,
            accuracy = accuracy,
            class = class,
            time = GetTime(),
        }
    end

    -- Update UI if visible
    if ns.LeaderboardUI then
        ns.LeaderboardUI:Refresh()
    end
end

function Leaderboard:AddToLeaderboard(difficulty, entry)
    local db = BoundToLearn.db.leaderboard
    if not db[difficulty] then
        db[difficulty] = {}
    end

    local board = db[difficulty]

    -- Check for existing entry from same player, keep higher score
    for i, existing in ipairs(board) do
        if existing.name == entry.name then
            if entry.score > existing.score then
                tremove(board, i)
            else
                return -- existing score is higher
            end
            break
        end
    end

    -- Insert sorted by score desc
    local inserted = false
    for i, existing in ipairs(board) do
        if entry.score > existing.score then
            tinsert(board, i, entry)
            inserted = true
            break
        end
    end
    if not inserted then
        tinsert(board, entry)
    end

    -- Cap entries
    while #board > MAX_ENTRIES do
        tremove(board)
    end
end

function Leaderboard:GetLeaderboard(difficulty)
    local db = BoundToLearn.db.leaderboard
    return db[difficulty] or {}
end

function Leaderboard:GetPartyScores()
    return partyScores
end

function Leaderboard:CleanPartyScores()
    -- Remove players no longer in group
    local groupMembers = {}
    if IsInGroup() then
        local num = GetNumGroupMembers()
        for i = 1, num do
            local unit = IsInRaid() and ("raid" .. i) or ("party" .. i)
            -- Both the short and the full form, as either may key a score.
            local short, full = GetUnitName(unit, false), GetUnitName(unit, true)
            if short then groupMembers[short] = true end
            if full then groupMembers[full] = true end
        end
    end

    for name in pairs(partyScores) do
        local shortName = strsplit("-", name)
        if not groupMembers[name] and not groupMembers[shortName] then
            partyScores[name] = nil
        end
    end
end

-- Challenge system

function Leaderboard:SendChallenge(targetName)
    if not IsInGroup() then
        BoundToLearn:Print("You need to be in a group to challenge someone.")
        return
    end

    if activeChallenge then
        BoundToLearn:Print("You already have an active challenge.")
        return
    end

    pendingChallenge = { target = targetName, sent = GetTime() }
    local msg = Pack("CH", playerName, playerRealm)
    Send(msg, IsInRaid() and "RAID" or "PARTY")

    BoundToLearn:Print(sformat("Challenge sent to %s. Waiting for response...", targetName))

    -- Timeout
    C_Timer.After(CHALLENGE_TIMEOUT, function()
        if pendingChallenge and pendingChallenge.target == targetName then
            pendingChallenge = nil
            BoundToLearn:Print("Challenge timed out.")
        end
    end)
end

function Leaderboard:HandleChallengeInvite(parts, fullName, sName)
    if activeChallenge then return end

    pendingChallenge = { from = sName, fullName = fullName, sent = GetTime() }
    BoundToLearn:Print(sformat(
        "|cFFFFCC00%s|r has challenged you. Type |cFFFF8A33/btl accept|r or |cFFFF8A33/btl decline|r.",
        sName))

    -- Auto-timeout
    C_Timer.After(CHALLENGE_TIMEOUT, function()
        if pendingChallenge and pendingChallenge.from == sName then
            pendingChallenge = nil
            BoundToLearn:Print("Challenge from " .. sName .. " expired.")
        end
    end)
end

function Leaderboard:AcceptChallenge()
    if not pendingChallenge or not pendingChallenge.from then
        BoundToLearn:Print("No pending challenge to accept.")
        return
    end

    local opponent = pendingChallenge.from
    pendingChallenge = nil

    local msg = Pack("CA", playerName, playerRealm)
    Send(msg, IsInRaid() and "RAID" or "PARTY")

    local diff = BoundToLearn.db.game.difficulty
    activeChallenge = { opponent = opponent, difficulty = diff, startTime = GetTime() }

    BoundToLearn:Print(sformat("Challenge accepted. Both players: start the game on |cFFFFCC00%s|r difficulty.", diff))

    -- Open game UI in ready state
    BoundToLearn:OpenGame()
end

function Leaderboard:DeclineChallenge()
    if not pendingChallenge or not pendingChallenge.from then
        BoundToLearn:Print("No pending challenge to decline.")
        return
    end

    local msg = Pack("CD", playerName, playerRealm)
    Send(msg, IsInRaid() and "RAID" or "PARTY")

    BoundToLearn:Print("Challenge declined.")
    pendingChallenge = nil
end

function Leaderboard:HandleChallengeAccept(parts, fullName, sName)
    if not pendingChallenge or pendingChallenge.target ~= sName then return end

    pendingChallenge = nil
    local diff = BoundToLearn.db.game.difficulty
    activeChallenge = { opponent = sName, difficulty = diff, startTime = GetTime() }

    BoundToLearn:Print(sformat("|cFF00FF00%s accepted your challenge.|r Both players: start the game on |cFFFFCC00%s|r difficulty.", sName, diff))

    BoundToLearn:OpenGame()
end

function Leaderboard:HandleChallengeDecline(parts, fullName, sName)
    if pendingChallenge and pendingChallenge.target == sName then
        pendingChallenge = nil
        BoundToLearn:Print(sformat("%s declined your challenge.", sName))
    end
end

function Leaderboard:HandleChallengeResult(parts, fullName, sName)
    if not activeChallenge or activeChallenge.opponent ~= sName then return end

    local theirScore = tonumber(parts[2]) or 0
    local theirDiff = parts[3] or "Medium"
    local theirCombo = tonumber(parts[4]) or 0
    local theirAccuracy = tonumber(parts[5]) or 0

    -- Store for display in summary
    activeChallenge.opponentResult = {
        score = theirScore,
        difficulty = theirDiff,
        combo = theirCombo,
        accuracy = theirAccuracy,
    }

    BoundToLearn:Print(sformat(
        "|cFFFFCC00Challenge result:|r %s scored |cFFFFCC00%d|r on %s (combo: %d, accuracy: %d%%).",
        sName, theirScore, theirDiff, theirCombo, theirAccuracy))
end

function Leaderboard:OnGameEnd(results)
    -- Broadcast to guild/party
    self:BroadcastScore(results)

    -- Resolve challenge
    if activeChallenge then
        if activeChallenge.opponentResult then
            local theirs = activeChallenge.opponentResult.score
            local ours = results.score
            if ours > theirs then
                BoundToLearn:Print(sformat("|cFF00FF00You won the challenge!|r %d vs %d.", ours, theirs))
            elseif theirs > ours then
                BoundToLearn:Print(sformat("|cFFFF4444You lost the challenge.|r %d vs %d.", ours, theirs))
            else
                BoundToLearn:Print(sformat("|cFFFFCC00It's a tie!|r %d vs %d.", ours, theirs))
            end
        end
        activeChallenge = nil
    end
end

function Leaderboard:HasActiveChallenge()
    return activeChallenge ~= nil
end

function Leaderboard:GetActiveChallenge()
    return activeChallenge
end

function Leaderboard:GetPendingChallenge()
    return pendingChallenge
end

-- Add own score to leaderboard too
function Leaderboard:AddOwnScore(results)
    if not results or results.mode == "practice" then return end
    if results.score <= 0 then return end

    local totalNotes = results.totalNotes or 0
    if totalNotes == 0 then return end
    local accuracy = mfloor(ns.Utils.HitAccuracy(results.hitCounts))

    local entry = {
        name = playerName,
        score = results.score,
        combo = results.maxCombo,
        accuracy = accuracy,
        mode = results.mode or "timed",
        class = playerClass,
        timestamp = time(),
    }

    self:AddToLeaderboard(results.difficulty or "Medium", entry)
end
