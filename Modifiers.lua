local ADDON_NAME, ns = ...

local Modifiers = {}
ns.Modifiers = Modifiers

local Utils   = ns.Utils
local pairs   = Utils.pairs
local ipairs  = Utils.ipairs

local MODIFIER_LIST = {
    {
        id = "angled",
        name = "Angled",
        desc = "Notes approach from random angles.",
        unlockHint = "Beat Medium difficulty",
        check = function()
            local db = BoundToLearn.db.stats.difficultyBest
            return db and db.Medium and db.Medium.highestScore > 0
        end,
    },
    {
        id = "squiggly",
        name = "Squiggly",
        desc = "Notes wave back and forth as they fall.",
        unlockHint = "Reach a 20 combo",
        check = function()
            return BoundToLearn.db.stats.personalBest.longestCombo >= 20
        end,
    },
    {
        id = "fade",
        name = "Fade",
        desc = "Notes fade out as they approach the hit zone.",
        unlockHint = "Earn Bronze rank on Hard",
        check = function()
            local db = BoundToLearn.db.stats.difficultyBest
            return db and db.Hard and db.Hard.highestScore >= 1000
        end,
    },
    {
        id = "accelerate",
        name = "Accelerate",
        desc = "Notes speed up as they fall.",
        unlockHint = "Earn Silver rank on Hard",
        check = function()
            local db = BoundToLearn.db.stats.difficultyBest
            return db and db.Hard and db.Hard.highestScore >= 3000
        end,
    },
    {
        id = "doubles",
        name = "Doubles",
        desc = "Two notes can land at the same time, requiring simultaneous keypresses.",
        descExtra = "Not available in Competitive mode (modifier keys conflict).",
        unlockHint = "Earn Gold rank on Medium",
        check = function()
            local db = BoundToLearn.db.stats.difficultyBest
            return db and db.Medium and db.Medium.highestScore >= 6000
        end,
    },
    {
        id = "mirror",
        name = "Mirror",
        desc = "Lane order randomly flips during the round.",
        unlockHint = "Earn Bronze rank on Extreme",
        check = function()
            local db = BoundToLearn.db.stats.difficultyBest
            return db and db.Extreme and db.Extreme.highestScore >= 1000
        end,
    },
}

Modifiers.MODIFIER_LIST = MODIFIER_LIST

local modifierByID = {}
for _, m in ipairs(MODIFIER_LIST) do
    modifierByID[m.id] = m
end

function Modifiers:Get(id)
    return modifierByID[id]
end

function Modifiers:IsUnlocked(id)
    local m = modifierByID[id]
    if not m then return false end
    if m.check then return m.check() end
    return false
end

function Modifiers:IsActive(id)
    local active = self:GetActive()
    return active[id] or false
end

-- Returns a set of active modifier IDs: { angled = true, fade = true }
function Modifiers:GetActive()
    local saved = BoundToLearn.db.game.modifiers or {}
    local active = {}
    for id, enabled in pairs(saved) do
        if enabled and self:IsUnlocked(id) then
            active[id] = true
        end
    end
    return active
end

function Modifiers:GetActiveCount()
    local count = 0
    for _ in pairs(self:GetActive()) do
        count = count + 1
    end
    return count
end

function Modifiers:Toggle(id)
    local saved = BoundToLearn.db.game.modifiers
    if not saved then
        saved = {}
        BoundToLearn.db.game.modifiers = saved
    end
    saved[id] = not saved[id]
end
