local ADDON_NAME, ns = ...

local SpellData = {}
ns.SpellData = SpellData

-- CC/interrupt spell classifications per class.
-- Sourced from LibPlayerSpells-1.0 (AdiAddons). Excludes snares and taunts.
-- Categories: "interrupt", "stun", "disorient", "incapacitate", "root", "silence", "fear", "knockback"

local CLASS_SPELLS = {
    DEATHKNIGHT = {
        [47528]  = "interrupt",    -- Mind Freeze
        [207167] = "disorient",    -- Blinding Sleet
        [91807]  = "root",         -- Shambling Rush
        [204085] = "root",         -- Deathchill
        [91797]  = "stun",         -- Monstrous Blow
        [91800]  = "stun",         -- Gnaw
        [108194] = "stun",         -- Asphyxiate (Unholy)
        [221562] = "stun",         -- Asphyxiate (Blood)
        [287254] = "stun",         -- Dead of Winter
        [207165] = "stun",         -- Abomination's Might
        [210141] = "stun",         -- Zombie Explosion
        [108199] = "knockback",    -- Gorefiend's Grasp
    },
    DEMONHUNTER = {
        [183752] = "interrupt",    -- Disrupt
        [204490] = "silence",      -- Sigil of Silence
        [179057] = "stun",         -- Chaos Nova
        [200166] = "stun",         -- Metamorphosis
        [205630] = "stun",         -- Illidan's Grasp
        [208618] = "stun",         -- Illidan's Grasp (thrown)
        [211881] = "stun",         -- Fel Eruption
        [213491] = "stun",         -- Demonic Trample
        [207685] = "disorient",    -- Sigil of Misery
        [217832] = "incapacitate", -- Imprison
        [221527] = "incapacitate", -- Imprison (honor)
    },
    DRUID = {
        [78675]  = "interrupt",    -- Solar Beam
        [106839] = "interrupt",    -- Skull Bash
        [5211]   = "stun",         -- Mighty Bash
        [163505] = "stun",         -- Rake
        [202244] = "stun",         -- Overrun
        [203123] = "stun",         -- Maim
        [339]    = "root",         -- Entangling Roots
        [45334]  = "root",         -- Immobilized
        [102359] = "root",         -- Mass Entanglement
        [235963] = "root",         -- Entangling Roots (Feral honor)
        [33786]  = "disorient",    -- Cyclone
        [99]     = "incapacitate", -- Incapacitating Roar
        [2637]   = "incapacitate", -- Hibernate
    },
    EVOKER = {
        [351338] = "interrupt",    -- Quell
        [355689] = "root",         -- Landslide
    },
    HUNTER = {
        [147362] = "interrupt",    -- Counter Shot
        [187707] = "interrupt",    -- Muzzle
        [24394]  = "stun",         -- Intimidation
        [3355]   = "incapacitate", -- Freezing Trap
        [203337] = "incapacitate", -- Freezing Trap (Survival honor)
        [213691] = "incapacitate", -- Scatter Shot
        [117526] = "root",         -- Binding Shot
        [162480] = "root",         -- Steel Trap
        [190927] = "root",         -- Harpoon
        [212638] = "root",         -- Tracker's Net
        [236776] = "knockback",    -- Hi-Explosive Trap
    },
    MAGE = {
        [2139]   = "interrupt",    -- Counterspell
        [122]    = "root",         -- Frost Nova
        [33395]  = "root",         -- Freeze
        [157997] = "root",         -- Ice Nova
        [228600] = "root",         -- Glacial Spike
        [31661]  = "disorient",    -- Dragon's Breath
        [82691]  = "incapacitate", -- Ring of Frost
        [118]    = "incapacitate", -- Polymorph
        [28271]  = "incapacitate", -- Polymorph (Turtle)
        [28272]  = "incapacitate", -- Polymorph (Pig)
        [61305]  = "incapacitate", -- Polymorph (Black Cat)
        [61721]  = "incapacitate", -- Polymorph (Rabbit)
        [61780]  = "incapacitate", -- Polymorph (Turkey)
        [126819] = "incapacitate", -- Polymorph (Porcupine)
        [161353] = "incapacitate", -- Polymorph (Polar Bear)
        [161354] = "incapacitate", -- Polymorph (Monkey)
        [161355] = "incapacitate", -- Polymorph (Penguin)
        [161372] = "incapacitate", -- Polymorph (Peacock)
        [277787] = "incapacitate", -- Polymorph (Direhorn)
        [277792] = "incapacitate", -- Polymorph (Bumblebee)
        [157980] = "knockback",    -- Supernova
        [157981] = "knockback",    -- Blast Wave
    },
    MONK = {
        [116705] = "interrupt",    -- Spear Hand Strike
        [119381] = "stun",         -- Leg Sweep
        [202346] = "stun",         -- Double Barrel
        [115078] = "incapacitate", -- Paralysis
        [116706] = "root",         -- Disable
        [324382] = "root",         -- Clash
        [198909] = "disorient",    -- Song of Chi-Ji
        [202274] = "disorient",    -- Incendiary Brew
    },
    PALADIN = {
        [96231]  = "interrupt",    -- Rebuke
        [31935]  = "interrupt",    -- Avenger's Shield
        [853]    = "stun",         -- Hammer of Justice
        [205290] = "stun",         -- Wake of Ashes
        [20066]  = "incapacitate", -- Repentance
        [105421] = "disorient",    -- Blinding Light
    },
    PRIEST = {
        [15487]  = "interrupt",    -- Silence
        [8122]   = "disorient",    -- Psychic Scream
        [226943] = "disorient",    -- Mind Bomb
        [605]    = "disorient",    -- Mind Control
        [64044]  = "stun",         -- Psychic Horror
        [200200] = "stun",         -- Holy Word: Chastise (stun)
        [200196] = "incapacitate", -- Holy Word: Chastise
        [9484]   = "incapacitate", -- Shackle Undead
    },
    ROGUE = {
        [1766]   = "interrupt",    -- Kick
        [408]    = "stun",         -- Kidney Shot
        [1833]   = "stun",         -- Cheap Shot
        [1776]   = "incapacitate", -- Gouge
        [6770]   = "incapacitate", -- Sap
        [2094]   = "disorient",    -- Blind
    },
    SHAMAN = {
        [57994]  = "interrupt",    -- Wind Shear
        [118345] = "stun",         -- Pulverize
        [118905] = "stun",         -- Static Charge
        [204437] = "stun",         -- Lightning Lasso
        [204399] = "stun",         -- Earthfury
        [64695]  = "root",         -- Earthgrab
        [51514]  = "incapacitate", -- Hex
        [197214] = "incapacitate", -- Sundering
        [51490]  = "knockback",    -- Thunderstorm
    },
    WARLOCK = {
        [19647]  = "interrupt",    -- Spell Lock
        [119910] = "interrupt",    -- Spell Lock (Command Demon)
        [132409] = "interrupt",    -- Spell Lock (Command Demon)
        [212619] = "interrupt",    -- Call Felhunter
        [22703]  = "stun",         -- Infernal Awakening
        [30283]  = "stun",         -- Shadowfury
        [89766]  = "stun",         -- Axe Toss
        [213688] = "stun",         -- Fel Cleave
        [233582] = "root",         -- Entrenched in Flame
        [6358]   = "disorient",    -- Seduction
        [261589] = "disorient",    -- Seduction (talent)
        [6789]   = "incapacitate", -- Mortal Coil
        [710]    = "incapacitate", -- Banish
        [118699] = "fear",         -- Fear
    },
    WARRIOR = {
        [6552]   = "interrupt",    -- Pummel
        [5246]   = "disorient",    -- Intimidating Shout
        [316593] = "disorient",    -- Intimidating Shout (primary)
        [316595] = "disorient",    -- Intimidating Shout (secondary)
        [105771] = "root",         -- Charge
        [199042] = "root",         -- Thunderstruck
        [132168] = "stun",         -- Shockwave
        [132169] = "stun",         -- Storm Bolt
        [199085] = "stun",         -- Warpath
        [206572] = "knockback",    -- Dragon Charge
    },
}

-- Flattened lookup for the current player's class: spellID → category
local playerSpells = {}
local FindBaseSpellByID = FindBaseSpellByID

function SpellData:Initialize()
    local _, className = UnitClass("player")
    local classData = CLASS_SPELLS[className]
    if classData then
        for spellID, category in pairs(classData) do
            playerSpells[spellID] = category
        end
    end
end

local function Lookup(spellID)
    local cat = playerSpells[spellID]
    if cat then return cat end
    -- Action bar may use an override ID; check the base spell
    if FindBaseSpellByID then
        local baseID = FindBaseSpellByID(spellID)
        if baseID and baseID ~= spellID then
            return playerSpells[baseID]
        end
    end
    return nil
end

function SpellData:GetSpellCategory(spellID)
    return Lookup(spellID)
end

function SpellData:IsInterrupt(spellID)
    return Lookup(spellID) == "interrupt"
end

function SpellData:IsCC(spellID)
    local cat = Lookup(spellID)
    return cat and cat ~= "interrupt"
end

function SpellData:IsCCOrInterrupt(spellID)
    return Lookup(spellID) ~= nil
end
