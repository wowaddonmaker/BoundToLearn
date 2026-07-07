local ADDON_NAME, ns = ...

local Achievements = {}
ns.Achievements = Achievements

local Utils    = ns.Utils
local pairs    = Utils.pairs
local ipairs   = Utils.ipairs
local sformat  = Utils.sformat
local tinsert  = Utils.tinsert
local mfloor   = Utils.mfloor

-- Rank thresholds (per-difficulty, based on best score)
local RANKS = {
    -- Thresholds are on the normalized money-score (best per-difficulty run, capped
    -- at 100k for a flawless run). They read as weighted-accuracy tiers: Bronze ~35%,
    -- Mythic ~95%. Keep in sync with SCORE_CAP in Game.lua.
    { name = "Unranked",  threshold = 0,     color = "888888", rgb = {0.53, 0.53, 0.53} },
    { name = "Bronze",    threshold = 35000, color = "CD7F32", rgb = {0.80, 0.50, 0.20} },
    { name = "Silver",    threshold = 52000, color = "C0C0C0", rgb = {0.75, 0.75, 0.75} },
    { name = "Gold",      threshold = 66000, color = "FFD700", rgb = {1.00, 0.84, 0.00} },
    { name = "Platinum",  threshold = 78000, color = "E5E4E2", rgb = {0.90, 0.89, 0.89} },
    { name = "Diamond",   threshold = 88000, color = "55CCFF", rgb = {0.33, 0.80, 1.00} },
    { name = "Mythic",    threshold = 95000, color = "FF55FF", rgb = {1.00, 0.33, 1.00} },
}
Achievements.RANKS = RANKS

function Achievements:GetRank(score)
    local rank = RANKS[1]
    for i = #RANKS, 1, -1 do
        if score >= RANKS[i].threshold then
            rank = RANKS[i]
            break
        end
    end
    return rank
end

function Achievements:GetNextRank(score)
    for _, r in ipairs(RANKS) do
        if score < r.threshold then
            return r
        end
    end
    return nil
end

function Achievements:GetRankText(score)
    local rank = self:GetRank(score)
    return sformat("|cFF%s%s|r", rank.color, rank.name)
end

-- Streak titles (shown mid-game at combo milestones)
local STREAK_TITLES = {
    { combo = 10,  text = "Warming Up",  color = {0.8, 0.8, 0.8} },
    { combo = 20,  text = "On Fire",     color = {1, 0.6, 0.1} },
    { combo = 30,  text = "Unstoppable", color = {1, 0.84, 0} },
    { combo = 50,  text = "Legendary",   color = {0.6, 0.2, 1} },
    { combo = 75,  text = "Mythic",      color = {1, 0.33, 1} },
    { combo = 100, text = "GODLIKE",     color = {1, 0.1, 0.1} },
}
Achievements.STREAK_TITLES = STREAK_TITLES

function Achievements:GetStreakTitle(combo)
    local title
    for i = #STREAK_TITLES, 1, -1 do
        if combo >= STREAK_TITLES[i].combo then
            title = STREAK_TITLES[i]
            break
        end
    end
    return title
end

-- Achievement definitions
-- Each achievement has: id, name, desc, category, icon (atlas), check function
-- check(db) returns true if unlocked
local ACHIEVEMENT_LIST = {
    -- Accuracy
    { id = "all_perfect",     name = "Perfectionist",    desc = "Finish an Extreme round with every hit rated Perfect",  category = "accuracy", icon = "UI-HUD-MicroMenu-Achievements-Mouseover" },

    -- Combos
    { id = "combo_100",       name = "Untouchable",      desc = "Reach a 100 combo streak",                              category = "combo", icon = "Islands-QuestBangGlow" },
    { id = "combo_200",       name = "Inhuman",          desc = "Reach a 200 combo streak",                              category = "combo", icon = "Islands-QuestBangGlow" },

    -- Score
    { id = "score_25k",       name = "High Roller",      desc = "Score 25,000+ in a single round",                       category = "score", icon = "Coin-Gold" },
    { id = "score_50k",       name = "Score Legend",      desc = "Score 50,000+ in a single round",                       category = "score", icon = "Coin-Gold" },

    -- Lifetime
    { id = "hits_5000",       name = "Seasoned",         desc = "Land 5,000 total hits across all games",                category = "lifetime", icon = "communities-icon-achievement" },
    { id = "hits_25000",      name = "Veteran",          desc = "Land 25,000 total hits across all games",               category = "lifetime", icon = "communities-icon-achievement" },
    { id = "games_50",        name = "Regular",          desc = "Complete 50 rounds",                                    category = "lifetime", icon = "communities-icon-achievement" },
    { id = "games_200",       name = "Dedicated",        desc = "Complete 200 rounds",                                   category = "lifetime", icon = "communities-icon-achievement" },

    -- Ranks
    { id = "rank_diamond",    name = "Diamond Hands",    desc = "Earn Diamond rank on any difficulty",                    category = "rank", icon = "PVPCurrency-Honor-HordeUnit" },
    { id = "rank_mythic",     name = "Mythic Fingers",   desc = "Earn Mythic rank on any difficulty",                     category = "rank", icon = "PVPCurrency-Honor-HordeUnit" },

    -- Mastery
    { id = "beat_extreme",    name = "Extreme Survivor", desc = "Complete an Extreme round with 90%+ accuracy",           category = "mastery", icon = "UI-HUD-MicroMenu-StreamDLGreen-Up" },
    { id = "gold_all_diffs",  name = "Well Rounded",     desc = "Earn Gold rank on all four difficulties",                category = "mastery", icon = "UI-HUD-MicroMenu-StreamDLGreen-Up" },
    { id = "diamond_all",     name = "Diamond Collector", desc = "Earn Diamond rank on all four difficulties",            category = "mastery", icon = "UI-HUD-MicroMenu-StreamDLGreen-Up" },

    -- Endgame
    { id = "score_100k",      name = "Six Figures",      desc = "Score 100,000+ in a single round",                      category = "score", icon = "Coin-Gold" },
    { id = "combo_500",       name = "Metronome",        desc = "Reach a 500 combo streak",                              category = "combo", icon = "Islands-QuestBangGlow" },
    { id = "mythic_all",      name = "Mythic Collector",  desc = "Earn Mythic rank on all four difficulties",             category = "mastery", icon = "UI-HUD-MicroMenu-StreamDLGreen-Up" },
    { id = "flawless_hard",   name = "Flawless",         desc = "Complete a Hard round with zero misses",                 category = "mastery", icon = "UI-HUD-MicroMenu-StreamDLGreen-Up" },
    { id = "flawless_extreme", name = "Untouchable",     desc = "Complete an Extreme round with zero misses",             category = "mastery", icon = "UI-HUD-MicroMenu-StreamDLGreen-Up" },
    { id = "hits_100000",     name = "Lifer",            desc = "Land 100,000 total hits across all games",               category = "lifetime", icon = "communities-icon-achievement" },
    { id = "games_500",       name = "Addicted",         desc = "Complete 500 rounds",                                    category = "lifetime", icon = "communities-icon-achievement" },

    -- Competitive
    { id = "comp_gold",       name = "Contender",        desc = "Earn Gold rank in Competitive mode",                     category = "competitive", icon = "PVPCurrency-Honor-HordeUnit" },
    { id = "comp_diamond",    name = "Champion",         desc = "Earn Diamond rank in Competitive mode",                  category = "competitive", icon = "PVPCurrency-Honor-HordeUnit" },
    { id = "comp_mythic",     name = "Grandmaster",      desc = "Earn Mythic rank in Competitive mode",                   category = "competitive", icon = "PVPCurrency-Honor-HordeUnit" },

    -- Modifiers
    { id = "mod_fake",        name = "Spot the Phony",   desc = "Complete a round with Fake active",                      category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_angled",      name = "Off-Angle",        desc = "Complete a round with Angled active",                    category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_squiggly",    name = "Noodle Arms",      desc = "Complete a round with Squiggly active",                  category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_fade",        name = "Ghost Reader",     desc = "Complete a round with Fade active",                      category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_accelerate",  name = "Terminal Velocity", desc = "Complete a round with Accelerate active",               category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_doubles",     name = "Two-Fisted",       desc = "Complete a round with Doubles active",                   category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_mirror",      name = "Looking Glass",    desc = "Complete a round with Mirror active",                    category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_3",           name = "Triple Threat",    desc = "Complete a round with 3+ modifiers active",              category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
    { id = "mod_all",         name = "Total Chaos",      desc = "Complete a round with all 7 modifiers active",           category = "modifier", icon = "Vehicle-SilvershardMines-Arrow" },
}
Achievements.ACHIEVEMENT_LIST = ACHIEVEMENT_LIST

-- Build lookup
local achievementByID = {}
for _, a in ipairs(ACHIEVEMENT_LIST) do
    achievementByID[a.id] = a
end
Achievements.achievementByID = achievementByID

function Achievements:GetDB()
    return BoundToLearn.db.achievements
end

function Achievements:IsUnlocked(id)
    local db = self:GetDB()
    return db.unlocked[id] ~= nil
end

function Achievements:Unlock(id)
    local db = self:GetDB()
    if db.unlocked[id] then return false end
    db.unlocked[id] = time()
    return true
end

function Achievements:GetUnlockedCount()
    local count = 0
    local db = self:GetDB()
    for _ in pairs(db.unlocked) do
        count = count + 1
    end
    return count, #ACHIEVEMENT_LIST
end

-- Check and unlock achievements based on current state
-- Called after each game round ends
function Achievements:CheckRoundAchievements(results)
    local newUnlocks = {}
    local score = results.score
    local combo = results.maxCombo
    local hits = results.hitCounts
    local totalNotes = (hits.perfect or 0) + (hits.great or 0) + (hits.good or 0) + (hits.miss or 0)
    local misses = hits.miss or 0
    local accuracy = totalNotes > 0 and ((totalNotes - misses) / totalNotes * 100) or 0

    -- All Perfect (Extreme only)
    if results.difficulty == "Extreme" and totalNotes > 0 and misses == 0 and (hits.great or 0) == 0 and (hits.good or 0) == 0 and (hits.perfect or 0) > 0 then
        if self:Unlock("all_perfect") then tinsert(newUnlocks, "all_perfect") end
    end

    -- Combos
    if combo >= 100 then
        if self:Unlock("combo_100") then tinsert(newUnlocks, "combo_100") end
    end
    if combo >= 200 then
        if self:Unlock("combo_200") then tinsert(newUnlocks, "combo_200") end
    end
    if combo >= 500 then
        if self:Unlock("combo_500") then tinsert(newUnlocks, "combo_500") end
    end

    -- Score
    if score >= 25000 then
        if self:Unlock("score_25k") then tinsert(newUnlocks, "score_25k") end
    end
    if score >= 50000 then
        if self:Unlock("score_50k") then tinsert(newUnlocks, "score_50k") end
    end
    if score >= 100000 then
        if self:Unlock("score_100k") then tinsert(newUnlocks, "score_100k") end
    end

    -- Extreme with 90%+ accuracy
    if results.difficulty == "Extreme" and accuracy >= 90 then
        if self:Unlock("beat_extreme") then tinsert(newUnlocks, "beat_extreme") end
    end

    -- Flawless (zero misses)
    if totalNotes > 0 and misses == 0 then
        if results.difficulty == "Hard" then
            if self:Unlock("flawless_hard") then tinsert(newUnlocks, "flawless_hard") end
        end
        if results.difficulty == "Extreme" then
            if self:Unlock("flawless_extreme") then tinsert(newUnlocks, "flawless_extreme") end
        end
    end

    -- Modifier achievements
    -- Required modifiers are already included via Modifiers:GetActive(), but ensure they count
    local mods = results.modifiers or {}
    local modCount = 0
    local MOD_ACHIEV = {
        fake = "mod_fake", angled = "mod_angled", squiggly = "mod_squiggly", fade = "mod_fade",
        accelerate = "mod_accelerate", doubles = "mod_doubles", mirror = "mod_mirror",
    }
    for id in pairs(mods) do
        modCount = modCount + 1
        if MOD_ACHIEV[id] then
            if self:Unlock(MOD_ACHIEV[id]) then tinsert(newUnlocks, MOD_ACHIEV[id]) end
        end
    end
    if modCount >= 3 then
        if self:Unlock("mod_3") then tinsert(newUnlocks, "mod_3") end
    end
    if modCount >= 7 then
        if self:Unlock("mod_all") then tinsert(newUnlocks, "mod_all") end
    end

    -- Rank-based (check after score is saved)
    self:CheckRankAchievements(newUnlocks)

    -- Lifetime (check accumulated stats)
    self:CheckLifetimeAchievements(newUnlocks)

    return newUnlocks
end

function Achievements:CheckRankAchievements(newUnlocks)
    local diffBest = BoundToLearn.db.stats.difficultyBest
    if not diffBest then return end

    local hasDiamond, hasMythic = false, false
    local goldCount, diamondCount, mythicCount = 0, 0, 0
    local diffs = { "Easy", "Medium", "Hard", "Extreme" }

    for _, diff in ipairs(diffs) do
        local best = diffBest[diff]
        if best then
            local rank = self:GetRank(best.highestScore)
            if rank.threshold >= 6000 then goldCount = goldCount + 1 end
            if rank.threshold >= 15000 then
                hasDiamond = true
                diamondCount = diamondCount + 1
            end
            if rank.threshold >= 25000 then
                hasMythic = true
                mythicCount = mythicCount + 1
            end
        end
    end

    if hasDiamond then
        if self:Unlock("rank_diamond") then tinsert(newUnlocks, "rank_diamond") end
    end
    if hasMythic then
        if self:Unlock("rank_mythic") then tinsert(newUnlocks, "rank_mythic") end
    end
    if goldCount >= 4 then
        if self:Unlock("gold_all_diffs") then tinsert(newUnlocks, "gold_all_diffs") end
    end
    if diamondCount >= 4 then
        if self:Unlock("diamond_all") then tinsert(newUnlocks, "diamond_all") end
    end
    if mythicCount >= 4 then
        if self:Unlock("mythic_all") then tinsert(newUnlocks, "mythic_all") end
    end

    -- Competitive rank achievements
    local compBest = diffBest.Competitive
    if compBest then
        local compRank = self:GetRank(compBest.highestScore)
        if compRank.threshold >= 6000 then
            if self:Unlock("comp_gold") then tinsert(newUnlocks, "comp_gold") end
        end
        if compRank.threshold >= 15000 then
            if self:Unlock("comp_diamond") then tinsert(newUnlocks, "comp_diamond") end
        end
        if compRank.threshold >= 25000 then
            if self:Unlock("comp_mythic") then tinsert(newUnlocks, "comp_mythic") end
        end
    end
end

function Achievements:CheckLifetimeAchievements(newUnlocks)
    local stats = BoundToLearn.db.stats
    local totalHits = stats.lifetimeGameHits or 0

    if totalHits >= 5000 then
        if self:Unlock("hits_5000") then tinsert(newUnlocks, "hits_5000") end
    end
    if totalHits >= 25000 then
        if self:Unlock("hits_25000") then tinsert(newUnlocks, "hits_25000") end
    end
    if totalHits >= 100000 then
        if self:Unlock("hits_100000") then tinsert(newUnlocks, "hits_100000") end
    end

    -- Count game sessions
    local gameCount = 0
    for _, s in ipairs(stats.sessions or {}) do
        if s.type == "game" then gameCount = gameCount + 1 end
    end
    if gameCount >= 50 then
        if self:Unlock("games_50") then tinsert(newUnlocks, "games_50") end
    end
    if gameCount >= 200 then
        if self:Unlock("games_200") then tinsert(newUnlocks, "games_200") end
    end
    if gameCount >= 500 then
        if self:Unlock("games_500") then tinsert(newUnlocks, "games_500") end
    end
end
