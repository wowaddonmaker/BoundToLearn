local ADDON_NAME, ns = ...

local SpellData = {}
ns.SpellData = SpellData

-- Spell classifications per class.
-- CC/interrupt sourced from LibPlayerSpells-1.0 (AdiAddons). Excludes snares and taunts.
-- Defensive and offensive cooldown lists cover common abilities across specs.
--
-- CC sub-categories: "stun", "disorient", "incapacitate", "root", "silence", "fear", "knockback"
-- Broad roles: "interrupt", "defensive", "offensive_cd"

local CLASS_SPELLS = {
    DEATHKNIGHT = {
        -- Interrupt
        [47528]  = "interrupt",    -- Mind Freeze
        -- CC
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
        -- Defensive
        [48707]  = "defensive",    -- Anti-Magic Shell
        [48792]  = "defensive",    -- Icebound Fortitude
        [55233]  = "defensive",    -- Vampiric Blood
        [49028]  = "defensive",    -- Dancing Rune Weapon
        [49039]  = "defensive",    -- Lichborne
        [194679] = "defensive",    -- Rune Tap
        [81256]  = "defensive",    -- Dancing Rune Weapon (Blood)
        [219809] = "defensive",    -- Tombstone
        -- Offensive
        [51271]  = "offensive_cd", -- Pillar of Frost
        [47568]  = "offensive_cd", -- Empower Rune Weapon
        [207289] = "offensive_cd", -- Unholy Assault
        [49206]  = "offensive_cd", -- Summon Gargoyle
        [42650]  = "offensive_cd", -- Army of the Dead
        [315443] = "offensive_cd", -- Abomination Limb
        [152279] = "offensive_cd", -- Breath of Sindragosa
        [279302] = "offensive_cd", -- Frostwyrm's Fury
    },
    DEMONHUNTER = {
        -- Interrupt
        [183752] = "interrupt",    -- Disrupt
        -- CC
        [204490] = "silence",      -- Sigil of Silence
        [179057] = "stun",         -- Chaos Nova
        [200166] = "stun",         -- Metamorphosis (Veng)
        [205630] = "stun",         -- Illidan's Grasp
        [208618] = "stun",         -- Illidan's Grasp (thrown)
        [211881] = "stun",         -- Fel Eruption
        [213491] = "stun",         -- Demonic Trample
        [207685] = "disorient",    -- Sigil of Misery
        [217832] = "incapacitate", -- Imprison
        [221527] = "incapacitate", -- Imprison (honor)
        -- Defensive
        [198589] = "defensive",    -- Blur
        [196718] = "defensive",    -- Darkness
        [196555] = "defensive",    -- Netherwalk
        [187827] = "defensive",    -- Metamorphosis (Veng defensive)
        [203720] = "defensive",    -- Demon Spikes
        [204021] = "defensive",    -- Fiery Brand
        [263648] = "defensive",    -- Soul Barrier
        -- Offensive
        [191427] = "offensive_cd", -- Metamorphosis (Havoc)
        [258925] = "offensive_cd", -- Fel Barrage
        [323639] = "offensive_cd", -- The Hunt
        [390163] = "offensive_cd", -- Elysian Decree
    },
    DRUID = {
        -- Interrupt
        [78675]  = "interrupt",    -- Solar Beam
        [106839] = "interrupt",    -- Skull Bash
        -- CC
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
        -- Defensive
        [22812]  = "defensive",    -- Barkskin
        [61336]  = "defensive",    -- Survival Instincts
        [102342] = "defensive",    -- Ironbark
        [22842]  = "defensive",    -- Frenzied Regeneration
        [108238] = "defensive",    -- Renewal
        -- Offensive
        [194223] = "offensive_cd", -- Celestial Alignment
        [102560] = "offensive_cd", -- Incarnation: Chosen of Elune
        [106951] = "offensive_cd", -- Berserk
        [102543] = "offensive_cd", -- Incarnation: King of the Jungle
        [102558] = "offensive_cd", -- Incarnation: Guardian of Ursoc
        [391528] = "offensive_cd", -- Convoke the Spirits
        [323764] = "offensive_cd", -- Convoke the Spirits (alt)
    },
    EVOKER = {
        -- Interrupt
        [351338] = "interrupt",    -- Quell
        -- CC
        [355689] = "root",         -- Landslide
        -- Defensive
        [363916] = "defensive",    -- Obsidian Scales
        [374348] = "defensive",    -- Renewing Blaze
        [374227] = "defensive",    -- Zephyr
        [370960] = "defensive",    -- Emerald Communion
        -- Offensive
        [375087] = "offensive_cd", -- Dragonrage
        [357210] = "offensive_cd", -- Deep Breath
        [370553] = "offensive_cd", -- Tip the Scales
    },
    HUNTER = {
        -- Interrupt
        [147362] = "interrupt",    -- Counter Shot
        [187707] = "interrupt",    -- Muzzle
        -- CC
        [24394]  = "stun",         -- Intimidation
        [3355]   = "incapacitate", -- Freezing Trap
        [203337] = "incapacitate", -- Freezing Trap (Survival honor)
        [213691] = "incapacitate", -- Scatter Shot
        [117526] = "root",         -- Binding Shot
        [162480] = "root",         -- Steel Trap
        [190927] = "root",         -- Harpoon
        [212638] = "root",         -- Tracker's Net
        [236776] = "knockback",    -- Hi-Explosive Trap
        -- Defensive
        [109304] = "defensive",    -- Exhilaration
        [186265] = "defensive",    -- Aspect of the Turtle
        [264735] = "defensive",    -- Survival of the Fittest
        [388035] = "defensive",    -- Fortitude of the Bear
        [53480]  = "defensive",    -- Roar of Sacrifice
        -- Offensive
        [19574]  = "offensive_cd", -- Bestial Wrath
        [193530] = "offensive_cd", -- Aspect of the Wild
        [360952] = "offensive_cd", -- Coordinated Assault
        [288613] = "offensive_cd", -- Trueshot
        [201430] = "offensive_cd", -- Stampede
        [259489] = "offensive_cd", -- Kill Command (Survival, resets)
    },
    MAGE = {
        -- Interrupt
        [2139]   = "interrupt",    -- Counterspell
        -- CC
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
        -- Defensive
        [45438]  = "defensive",    -- Ice Block
        [342245] = "defensive",    -- Alter Time
        [55342]  = "defensive",    -- Mirror Image
        [235313] = "defensive",    -- Blazing Barrier
        [11426]  = "defensive",    -- Ice Barrier
        [235450] = "defensive",    -- Prismatic Barrier
        [110960] = "defensive",    -- Greater Invisibility
        -- Offensive
        [190319] = "offensive_cd", -- Combustion
        [12472]  = "offensive_cd", -- Icy Veins
        [365350] = "offensive_cd", -- Arcane Surge
        [205025] = "offensive_cd", -- Presence of Mind
        [153626] = "offensive_cd", -- Arcane Orb
    },
    MONK = {
        -- Interrupt
        [116705] = "interrupt",    -- Spear Hand Strike
        -- CC
        [119381] = "stun",         -- Leg Sweep
        [202346] = "stun",         -- Double Barrel
        [115078] = "incapacitate", -- Paralysis
        [116706] = "root",         -- Disable
        [324382] = "root",         -- Clash
        [198909] = "disorient",    -- Song of Chi-Ji
        [202274] = "disorient",    -- Incendiary Brew
        -- Defensive
        [115203] = "defensive",    -- Fortifying Brew
        [115176] = "defensive",    -- Zen Meditation
        [122278] = "defensive",    -- Dampen Harm
        [122783] = "defensive",    -- Diffuse Magic
        [125174] = "defensive",    -- Touch of Karma
        [116849] = "defensive",    -- Life Cocoon
        -- Offensive
        [137639] = "offensive_cd", -- Storm, Earth, and Fire
        [123904] = "offensive_cd", -- Invoke Xuen
        [152173] = "offensive_cd", -- Serenity
        [116680] = "offensive_cd", -- Thunder Focus Tea
        [325197] = "offensive_cd", -- Invoke Chi-Ji
        [322118] = "offensive_cd", -- Invoke Yu'lon
    },
    PALADIN = {
        -- Interrupt
        [96231]  = "interrupt",    -- Rebuke
        [31935]  = "interrupt",    -- Avenger's Shield
        -- CC
        [853]    = "stun",         -- Hammer of Justice
        [205290] = "stun",         -- Wake of Ashes
        [20066]  = "incapacitate", -- Repentance
        [105421] = "disorient",    -- Blinding Light
        -- Defensive
        [642]    = "defensive",    -- Divine Shield
        [633]    = "defensive",    -- Lay on Hands
        [1022]   = "defensive",    -- Blessing of Protection
        [184662] = "defensive",    -- Shield of Vengeance
        [31850]  = "defensive",    -- Ardent Defender
        [86659]  = "defensive",    -- Guardian of Ancient Kings
        [498]    = "defensive",    -- Divine Protection
        [6940]   = "defensive",    -- Blessing of Sacrifice
        -- Offensive
        [31884]  = "offensive_cd", -- Avenging Wrath
        [231895] = "offensive_cd", -- Crusade
        [105809] = "offensive_cd", -- Holy Avenger
        [343721] = "offensive_cd", -- Final Reckoning
        [343527] = "offensive_cd", -- Execution Sentence
        [216331] = "offensive_cd", -- Avenging Crusader
    },
    PRIEST = {
        -- Interrupt
        [15487]  = "interrupt",    -- Silence
        -- CC
        [8122]   = "disorient",    -- Psychic Scream
        [226943] = "disorient",    -- Mind Bomb
        [605]    = "disorient",    -- Mind Control
        [64044]  = "stun",         -- Psychic Horror
        [200200] = "stun",         -- Holy Word: Chastise (stun)
        [200196] = "incapacitate", -- Holy Word: Chastise
        [9484]   = "incapacitate", -- Shackle Undead
        -- Defensive
        [19236]  = "defensive",    -- Desperate Prayer
        [586]    = "defensive",    -- Fade
        [47585]  = "defensive",    -- Dispersion
        [33206]  = "defensive",    -- Pain Suppression
        [47788]  = "defensive",    -- Guardian Spirit
        [62618]  = "defensive",    -- Power Word: Barrier
        [271466] = "defensive",    -- Luminous Barrier
        -- Offensive
        [10060]  = "offensive_cd", -- Power Infusion
        [34433]  = "offensive_cd", -- Shadowfiend
        [200174] = "offensive_cd", -- Mindbender
        [228260] = "offensive_cd", -- Void Eruption
        [391109] = "offensive_cd", -- Dark Ascension
        [194249] = "offensive_cd", -- Voidform
    },
    ROGUE = {
        -- Interrupt
        [1766]   = "interrupt",    -- Kick
        -- CC
        [408]    = "stun",         -- Kidney Shot
        [1833]   = "stun",         -- Cheap Shot
        [1776]   = "incapacitate", -- Gouge
        [6770]   = "incapacitate", -- Sap
        [2094]   = "disorient",    -- Blind
        -- Defensive
        [5277]   = "defensive",    -- Evasion
        [31224]  = "defensive",    -- Cloak of Shadows
        [1856]   = "defensive",    -- Vanish
        [185311] = "defensive",    -- Crimson Vial
        [1966]   = "defensive",    -- Feint
        -- Offensive
        [13750]  = "offensive_cd", -- Adrenaline Rush
        [185313] = "offensive_cd", -- Shadow Dance
        [121471] = "offensive_cd", -- Shadow Blades
        [51690]  = "offensive_cd", -- Killing Spree
        [212283] = "offensive_cd", -- Symbols of Death
        [360194] = "offensive_cd", -- Deathmark
        [381802] = "offensive_cd", -- Flagellation
    },
    SHAMAN = {
        -- Interrupt
        [57994]  = "interrupt",    -- Wind Shear
        -- CC
        [118345] = "stun",         -- Pulverize
        [118905] = "stun",         -- Static Charge
        [204437] = "stun",         -- Lightning Lasso
        [204399] = "stun",         -- Earthfury
        [64695]  = "root",         -- Earthgrab
        [51514]  = "incapacitate", -- Hex
        [197214] = "incapacitate", -- Sundering
        [51490]  = "knockback",    -- Thunderstorm
        -- Defensive
        [108271] = "defensive",    -- Astral Shift
        [98008]  = "defensive",    -- Spirit Link Totem
        [108280] = "defensive",    -- Healing Tide Totem
        [325174] = "defensive",    -- Spirit Walk
        [409293] = "defensive",    -- Earth Wall Totem
        -- Offensive
        [114051] = "offensive_cd", -- Ascendance
        [191634] = "offensive_cd", -- Stormkeeper
        [384352] = "offensive_cd", -- Doom Winds
        [51533]  = "offensive_cd", -- Feral Spirit
        [198067] = "offensive_cd", -- Fire Elemental
        [192249] = "offensive_cd", -- Storm Elemental
    },
    WARLOCK = {
        -- Interrupt
        [19647]  = "interrupt",    -- Spell Lock
        [119910] = "interrupt",    -- Spell Lock (Command Demon)
        [132409] = "interrupt",    -- Spell Lock (Command Demon)
        [212619] = "interrupt",    -- Call Felhunter
        -- CC
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
        -- Defensive
        [104773] = "defensive",    -- Unending Resolve
        [108416] = "defensive",    -- Dark Pact
        [386997] = "defensive",    -- Soul Harvest
        -- Offensive
        [1122]   = "offensive_cd", -- Summon Infernal
        [205180] = "offensive_cd", -- Summon Darkglare
        [113858] = "offensive_cd", -- Dark Soul: Instability
        [267217] = "offensive_cd", -- Nether Portal
        [386997] = "offensive_cd", -- Soul Rot
        [442726] = "offensive_cd", -- Malevolence
    },
    WARRIOR = {
        -- Interrupt
        [6552]   = "interrupt",    -- Pummel
        -- CC
        [5246]   = "disorient",    -- Intimidating Shout
        [316593] = "disorient",    -- Intimidating Shout (primary)
        [316595] = "disorient",    -- Intimidating Shout (secondary)
        [105771] = "root",         -- Charge
        [199042] = "root",         -- Thunderstruck
        [132168] = "stun",         -- Shockwave
        [132169] = "stun",         -- Storm Bolt
        [199085] = "stun",         -- Warpath
        [206572] = "knockback",    -- Dragon Charge
        -- Defensive
        [871]    = "defensive",    -- Shield Wall
        [118038] = "defensive",    -- Die by the Sword
        [184364] = "defensive",    -- Enraged Regeneration
        [97462]  = "defensive",    -- Rallying Cry
        [23920]  = "defensive",    -- Spell Reflection
        [12975]  = "defensive",    -- Last Stand
        [190456] = "defensive",    -- Ignore Pain
        -- Offensive
        [1719]   = "offensive_cd", -- Recklessness
        [107574] = "offensive_cd", -- Avatar
        [227847] = "offensive_cd", -- Bladestorm
        [228920] = "offensive_cd", -- Ravager
        [384318] = "offensive_cd", -- Thunderous Roar
        [385059] = "offensive_cd", -- Odyn's Fury
    },
}

-- Maps CC sub-categories to the broad "cc" role for grouping analysis
local CC_CATEGORIES = {
    stun = true, disorient = true, incapacitate = true,
    root = true, silence = true, fear = true, knockback = true,
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
    return cat and cat ~= "interrupt" and not (cat == "defensive" or cat == "offensive_cd")
end

function SpellData:IsCCOrInterrupt(spellID)
    local cat = Lookup(spellID)
    return cat == "interrupt" or (cat and CC_CATEGORIES[cat])
end

-- Returns the broad role for grouping: "interrupt", "cc", "defensive", "offensive_cd", or nil
function SpellData:GetSpellRole(spellID)
    local cat = Lookup(spellID)
    if not cat then return nil end
    if cat == "interrupt" then return "interrupt" end
    if cat == "defensive" then return "defensive" end
    if cat == "offensive_cd" then return "offensive_cd" end
    if CC_CATEGORIES[cat] then return "cc" end
    return nil
end
