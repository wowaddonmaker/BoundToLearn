local ADDON_NAME, ns = ...

local CD = {}
ns.CompetitiveData = CD

CD.COLS = 5

CD.rows = {
    { modifier = "",       label = nil },
    { modifier = "SHIFT-", label = "Shift" },
    { modifier = "CTRL-",  label = "Ctrl" },
}

-- 15 competitive slots: 3 rows x 5 columns with distinct spell icons.
-- Row 1 = keys 1-5, Row 2 = Shift+1-5, Row 3 = Ctrl+1-5.
CD.slots = {
    -- Row 1: Base (1-5)
    { name = "Fire",      texture = 135812, color = { 1.0, 0.3, 0.1 },  row = 1, col = 1 },  -- Spell_Fire_FlameBolt
    { name = "Frost",     texture = 135846, color = { 0.2, 0.6, 1.0 },  row = 1, col = 2 },  -- Spell_Frost_FrostBolt02
    { name = "Nature",    texture = 136081, color = { 0.2, 0.9, 0.3 },  row = 1, col = 3 },  -- Spell_Nature_Rejuvenation
    { name = "Holy",      texture = 135920, color = { 1.0, 0.85, 0.2 }, row = 1, col = 4 },  -- Spell_Holy_HolyBolt
    { name = "Shadow",    texture = 136197, color = { 0.6, 0.3, 0.9 },  row = 1, col = 5 },  -- Spell_Shadow_ShadowBolt
    -- Row 2: Shift (S1-S5)
    { name = "Arcane",    texture = 135735, color = { 0.7, 0.4, 1.0 },  row = 2, col = 1 },  -- Spell_Arcane_Blast
    { name = "Storm",     texture = 136048, color = { 0.5, 0.8, 1.0 },  row = 2, col = 2 },  -- Spell_Nature_Lightning
    { name = "Pyro",      texture = 135808, color = { 1.0, 0.5, 0.0 },  row = 2, col = 3 },  -- Spell_Fire_Fireball02
    { name = "Life",      texture = 136041, color = { 0.3, 1.0, 0.5 },  row = 2, col = 4 },  -- Spell_Nature_HealingTouch
    { name = "Death",     texture = 136145, color = { 0.0, 0.7, 0.3 },  row = 2, col = 5 },  -- Spell_Shadow_DeathCoil
    -- Row 3: Ctrl (C1-C5)
    { name = "Star",      texture = 135753, color = { 0.9, 0.8, 0.3 },  row = 3, col = 1 },  -- Spell_Arcane_StarFire
    { name = "Chain",     texture = 136015, color = { 0.3, 0.5, 1.0 },  row = 3, col = 2 },  -- Spell_Nature_ChainLightning
    { name = "Judgment",  texture = 135959, color = { 1.0, 0.7, 0.2 },  row = 3, col = 3 },  -- Spell_Holy_Excorcism_02
    { name = "Decay",     texture = 136144, color = { 0.5, 0.2, 0.5 },  row = 3, col = 4 },  -- Spell_Shadow_DeathAndDecay
    { name = "Lava",      texture = 135830, color = { 0.9, 0.2, 0.2 },  row = 3, col = 5 },  -- Spell_Fire_Immolation
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
