local ADDON_NAME, ns = ...

local CD = {}
ns.CompetitiveData = CD

-- 5 universal competitive slots with iconic, color-distinct WoW spell icons.
-- Keybinds come from ACTIONBUTTON1-5 (the player's existing bar 1 keys).
CD.slots = {
    { name = "Fire",   texture = 135812, color = { 1.0, 0.3, 0.1 } },  -- Spell_Fire_FlameBolt
    { name = "Frost",  texture = 135846, color = { 0.2, 0.6, 1.0 } },  -- Spell_Frost_FrostBolt02
    { name = "Nature", texture = 136081, color = { 0.2, 0.9, 0.3 } },  -- Spell_Nature_Rejuvenation
    { name = "Holy",   texture = 135920, color = { 1.0, 0.85, 0.2 } }, -- Spell_Holy_HolyBolt
    { name = "Shadow", texture = 136197, color = { 0.6, 0.3, 0.9 } },  -- Spell_Shadow_ShadowBolt
}

-- Bomb spawn chance per difficulty (competitive only)
CD.bombChance = {
    Easy    = 0,
    Medium  = 0.08,
    Hard    = 0.15,
    Extreme = 0.22,
}

-- How long a destroyed lane stays offline (seconds)
CD.laneDestroyDuration = 10
