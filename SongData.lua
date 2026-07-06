local ADDON_NAME, ns = ...

-- Song library for the rhythm game. Each song references a real in-game music
-- track by its FileDataID (played on the Music channel via PlayMusic). A song's
-- gameplay tempo is derived from its id, so every track feels distinct and its
-- per-difficulty rating differs. The note pathing itself is made deterministic
-- per song+difficulty inside Game.lua (seeded lane selection), so a chart plays
-- the same every time and scores are worth boasting about.

local Utils = ns.Utils
local mfloor, mmax, mmin = Utils.mfloor, Utils.mmax, Utils.mmin

local SongData = {}
ns.SongData = SongData

SongData.songs = {
    { key = "s1", title = [[The War Within]], artist = [[Main Title]], id = 6075186, length = 976 },
    { key = "s2", title = [[The War Soul Saga]], artist = [[Adam Burgess]], id = 6037118, length = 339 },
    { key = "s3", title = [[Through the Roof of the World]], artist = [[Main Title]], id = 3850553, length = 684 },
    { key = "s4", title = [[Battle for Azeroth]], artist = [[Blizzard Entertainment]], id = 2146580, length = 677 },
    { key = "s5", title = [[Jaina Intro]], artist = [[Blizzard Entertainment]], id = 2204149, length = 109 },
    { key = "s6", title = [[Ashvane Company]], artist = [[David Arkenstone]], id = 2143489, length = 125 },
    { key = "s7", title = [[Legion]], artist = [[Blizzard Entertainment]], id = 1496267, length = 650 },
    { key = "s8", title = [[Anduin]], artist = [[Neal Acree]], id = 1417250, length = 122 },
    { key = "s9", title = [[Warlords of Draenor]], artist = [[Blizzard Entertainment]], id = 1042428, length = 726 },
    { key = "s10", title = [[Stormlords on the March I]], artist = [[Eimear Noone]], id = 1067075, length = 88 },
    { key = "s11", title = [[Stormlords on the March II]], artist = [[Eimear Noone]], id = 1067076, length = 46 },
    { key = "s12", title = [[Stormlords on the March III]], artist = [[Eimear Noone]], id = 1067077, length = 101 },
    { key = "s13", title = [[Mists of Pandaria]], artist = [[Blizzard Entertainment]], id = 625753, length = 480 },
    { key = "s14", title = [[Gecko]], artist = [[Neal Acree]], id = 574908, length = 135 },
    { key = "s15", title = [[Balloon Ride]], artist = [[Sam Cardon]], id = 642176, length = 168 },
    { key = "s16", title = [[Title of Liulang]], artist = [[Russell Brower]], id = 642577, length = 170 },
    { key = "s17", title = [[Serpent Riders Race]], artist = [[Russell Brower]], id = 653741, length = 238 },
    { key = "s18", title = [[Ginsu Valor]], artist = [[Sam Cardon]], id = 642268, length = 172 },
    { key = "s19", title = [[Shado-Pan Walk]], artist = [[Russell Brower]], id = 644930, length = 65 },
    { key = "s20", title = [[Way of the Monk]], artist = [[Neal Acree]], id = 642243, length = 157 },
    { key = "s21", title = [[Positive Chi]], artist = [[Jeremy Soule]], id = 642261, length = 94 },
    { key = "s22", title = [[Jaina Homeland March]], artist = [[Jason Hayes]], id = 772747, length = 103 },
    { key = "s23", title = [[Jaina Homeland Calm]], artist = [[Jason Hayes]], id = 772746, length = 41 },
    { key = "s24", title = [[Cataclysm]], artist = [[Blizzard Entertainment]], id = 441737, length = 725 },
    { key = "s25", title = [[Night Elves]], artist = [[Neal Acree]], id = 441705, length = 160 },
    { key = "s26", title = [[Rescue]], artist = [[Derek Duke]], id = 443303, length = 37 },
    { key = "s27", title = [[Darnassus Intro]], artist = [[Neal Acree]], id = 441574, length = 48 },
    { key = "s28", title = [[Stormwind Variation]], artist = [[Neal Acree]], id = 441767, length = 66 },
    { key = "s29", title = [[Aftermath]], artist = [[David Arkenstone]], id = 441521, length = 125 },
    { key = "s30", title = [[Druids of the Flame]], artist = [[Russell Brower]], id = 528352, length = 91 },
    { key = "s31", title = [[Thrall and Aggra]], artist = [[Blizzard Entertainment]], id = 528174, length = 72 },
    { key = "s32", title = [[Wrath of the Lich King]], artist = [[Blizzard Entertainment]], id = 53222, length = 544 },
    { key = "s33", title = [[Iron Dwarf March]], artist = [[Blizzard Entertainment]], id = 229903, length = 69 },
    { key = "s34", title = [[Storm Peaks]], artist = [[Blizzard Entertainment]], id = 229956, length = 82 },
    { key = "s35", title = [[Iron Dwarf Day]], artist = [[Blizzard Entertainment]], id = 229894, length = 97 },
    { key = "s36", title = [[Storm Peaks Twilight]], artist = [[Blizzard Entertainment]], id = 229958, length = 82 },
    { key = "s37", title = [[Culling of Stratholme]], artist = [[Blizzard Entertainment]], id = 229969, length = 99 },
    { key = "s38", title = [[Dalaran]], artist = [[Russell Brower]], id = 229800, length = 67 },
    { key = "s39", title = [[Dalaran Intro]], artist = [[Russell Brower]], id = 229804, length = 68 },
    { key = "s40", title = [[Ebon Hold]], artist = [[Russell Brower]], id = 229831, length = 82 },
    { key = "s41", title = [[Assault]], artist = [[Russell Brower]], id = 229825, length = 69 },
    { key = "s42", title = [[Grizzly Hills]], artist = [[Russell Brower]], id = 229834, length = 284 },
    { key = "s43", title = [[Grizzly Hills Hero]], artist = [[Russell Brower]], id = 229835, length = 149 },
    { key = "s44", title = [[Argent Joust]], artist = [[David Arkenstone]], id = 303111, length = 123 },
    { key = "s45", title = [[Invincible]], artist = [[Russell Brower]], id = 1100052, length = 197 },
    { key = "s46", title = [[The Burning Legion]], artist = [[Blizzard Entertainment]], id = 53220, length = 226 },
    { key = "s47", title = [[Thrall's Escape]], artist = [[Russell Brower]], id = 53425, length = 45 },
    { key = "s48", title = [[Fire Festival]], artist = [[David Arkenstone]], id = 53255, length = 68 },
    { key = "s49", title = [[Brazen's Flight]], artist = [[Russell Brower]], id = 53379, length = 93 },
    { key = "s50", title = [[Durnholde Keep]], artist = [[Russell Brower]], id = 53394, length = 70 },
    { key = "s51", title = [[Escape from Durnholde]], artist = [[Russell Brower]], id = 53401, length = 112 },
    { key = "s52", title = [[Hillsbrad]], artist = [[Jason Hayes]], id = 53403, length = 56 },
    { key = "s53", title = [[Hyjal (Call to Arms) I]], artist = [[Jason Hayes]], id = 53404, length = 66 },
    { key = "s54", title = [[Hyjal (Call to Arms) II]], artist = [[Jason Hayes]], id = 53405, length = 70 },
    { key = "s55", title = [[Lament of the Highborne]], artist = [[Russell Brower and Derek Duke]], id = 53221, length = 171 },
    { key = "s56", title = [[Black Temple Summit]], artist = [[Russell Brower]], id = 53347, length = 41 },
    { key = "s57", title = [[Black Temple Gates]], artist = [[Russell Brower]], id = 53309, length = 74 },
    { key = "s58", title = [[Sunwell Flyby]], artist = [[Russell Brower]], id = 53733, length = 57 },
    { key = "s59", title = [[Shorel'aran]], artist = [[Blizzard Entertainment]], id = 53731, length = 87 },
    { key = "s60", title = [[Silvermoon]], artist = [[Russell Brower]], id = 53713, length = 97 },
    { key = "s61", title = [[Power of the Horde]], artist = [[Tenth Level Tauren Chieftain]], id = 53438, length = 282 },
    { key = "s62", title = [[Vanilla Main Title]], artist = [[Jason Hayes]], id = 53223, length = 161 },
    { key = "s63", title = [[Enchanted Forest]], artist = [[Jason Hayes]], id = 53453, length = 49 },
    { key = "s64", title = [[Spooky]], artist = [[Jason Hayes]], id = 53252, length = 25 },
    { key = "s65", title = [[Stormwind Intro]], artist = [[Jason Hayes]], id = 53211, length = 66 },
    { key = "s66", title = [[Zul'Gurub Voodoo]], artist = [[Derek Duke]], id = 53254, length = 84 },
    { key = "s67", title = [[Battle]], artist = [[Blizzard Entertainment]], id = 53225, length = 48 },
    { key = "s68", title = [[PvP]], artist = [[Derek Duke]], id = 53686, length = 40 },
}

SongData.byKey = {}
for i = 1, #SongData.songs do
    SongData.byKey[SongData.songs[i].key] = SongData.songs[i]
end

function SongData.Get(key)
    return SongData.byKey[key] or SongData.songs[1]
end

-- DDR-style cut length. Most tracks play as ~1:55 edits; long epic/boss themes
-- (the full track runs 7+ minutes) get a ~3:15 cut. Short tracks keep their real
-- length. This is both the displayed duration and the round length, so the full
-- 7-16 minute soundtrack cuts never appear.
local NORMAL_CUT, BOSS_CUT, BOSS_THRESHOLD = 115, 195, 420
function SongData.PlayLength(song)
    if not song then return NORMAL_CUT end
    local full = song.length or NORMAL_CUT
    local cut = (full >= BOSS_THRESHOLD) and BOSS_CUT or NORMAL_CUT
    return mmin(full, cut)
end

-- Gameplay tempo derived from the FileDataID: stable per song, spread across a
-- lively range so tracks differ. Not the audio's true BPM; it drives note
-- spacing and the difficulty rating.
function SongData.BPM(song)
    return 96 + (song.id % 70)   -- 96..165
end

-- How finely each difficulty divides the beat, how densely notes fill it, and
-- how often simultaneous notes appear. A rising challenge curve.
local DIFFICULTY = {
    Easy    = { subdiv = 1, fill = 0.55, jump = 0.00 },
    Medium  = { subdiv = 2, fill = 0.60, jump = 0.00 },
    Hard    = { subdiv = 2, fill = 0.80, jump = 0.12 },
    Extreme = { subdiv = 4, fill = 0.72, jump = 0.22 },
}

function SongData.DifficultyProfile(difficulty)
    return DIFFICULTY[difficulty] or DIFFICULTY.Medium
end

-- A 1-10 rating for the carousel meter, per song AND difficulty: it blends the
-- difficulty profile with the song's tempo, so faster tracks read as harder and
-- every song shows a distinct bar per tier.
function SongData.Rating(song, difficulty)
    local prof = SongData.DifficultyProfile(difficulty)
    local density = prof.subdiv * prof.fill * (1 + prof.jump)   -- ~0.55 .. 3.5
    local tempo = (SongData.BPM(song) - 96) / 70                -- 0 .. 1
    local raw = density * (1.7 + tempo * 1.3)
    return mmax(1, mmin(10, mfloor(raw + 0.5)))
end

-- Per-expansion Adventure Guide (Encounter Journal) instance-select backdrops,
-- indexed by tier. These are Blizzard's EJ_TIER_DATA background atlases; a name
-- that does not resolve on the client is skipped at use time (falls back).
-- Confirmed live atlas: the Encounter Journal instance-select background is
-- "ui-ej-midnight" on 12.0. Older-expansion variants follow the same "ui-ej-*"
-- pattern; any that do not resolve fall back to the confirmed midnight art.
SongData.XPAC_BG = {
    [1]  = "ui-ej-classic",
    [2]  = "ui-ej-burningcrusade",
    [3]  = "ui-ej-wrathofthelichking",
    [4]  = "ui-ej-cataclysm",
    [5]  = "ui-ej-mistsofpandaria",
    [6]  = "ui-ej-warlordsofdraenor",
    [7]  = "ui-ej-legion",
    [8]  = "ui-ej-battleforazeroth",
    [9]  = "ui-ej-shadowlands",
    [10] = "ui-ej-dragonflight",
    [11] = "ui-ej-midnight",
}

-- The extracted library is grouped newest-to-oldest, so an index range maps to
-- an expansion tier well enough to give each track an era-appropriate backdrop.
local function tierForIndex(n)
    if n <= 2 then return 11
    elseif n == 3 then return 9
    elseif n <= 6 then return 8
    elseif n <= 8 then return 7
    elseif n <= 12 then return 6
    elseif n <= 23 then return 5
    elseif n <= 31 then return 4
    elseif n <= 54 then return 3
    elseif n <= 61 then return 2
    end
    return 1
end

function SongData.XpacBackground(song)
    local n = tonumber(song.key:match("%d+")) or 1
    local atlas = SongData.XPAC_BG[tierForIndex(n)]
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return atlas
    end
    return "ui-ej-midnight"
end

-- Five-axis "groove" profile (each 0-1) for the radar on the song select, using
-- terms that fit a keybind rhythm game rather than DDR's. Varies per song and
-- difficulty so every chart has a distinct shape.
-- Speed: scroll tempo. Density: overall notes. Chords: multi-key hits.
-- Bursts: peak subdivision. Stamina: track length / endurance.
SongData.RADAR_LABELS = { "Speed", "Density", "Chords", "Bursts", "Stamina" }

function SongData.Radar(song, difficulty)
    local prof = SongData.DifficultyProfile(difficulty)
    local function clampAxis(v) return mmax(0.12, mmin(1, v)) end
    local speed   = ((SongData.BPM(song) - 96) / 70)
    local density = (prof.subdiv * prof.fill / 3.2)
    local chords  = (prof.jump / 0.22)
    local bursts  = (prof.subdiv / 4)
    local stamina = (((song.length or 200) - 120) / 640)
    return {
        clampAxis(speed), clampAxis(density), clampAxis(chords),
        clampAxis(bursts), clampAxis(stamina),
    }
end

-- Tie each song to a themed dungeon/raid via the Adventure Guide so the selected
-- bubble can show that instance's button art. The list is built once, lazily:
-- load the guide, walk every expansion tier's dungeons and raids, and cache the
-- button images. EJ_SelectTier mutates the guide's current tier, so it is saved
-- and restored. All returned button images share the same crop as the live grid.
local instanceImagesByTier
local INSTANCE_TEXCOORD = { 0, 0.68359, 0, 0.74219 }

local function buildInstanceImages()
    if instanceImagesByTier then return end
    instanceImagesByTier = {}
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
    if not (EJ_GetInstanceByIndex and EJ_SelectTier and EJ_GetNumTiers) then return end
    local prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or 1
    for tier = 1, EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        local list = {}
        for r = 1, 2 do
            local isRaid = (r == 2)
            local i = 1
            while true do
                local instanceID, _, _, _, buttonImage1, buttonImage2 = EJ_GetInstanceByIndex(i, isRaid)
                if not instanceID then break end
                local img = buttonImage1 or buttonImage2
                if img then list[#list + 1] = img end
                i = i + 1
            end
        end
        instanceImagesByTier[tier] = list
    end
    EJ_SelectTier(prevTier)
end

-- Returns (fileID, texcoords) for the selected song bubble, or nil if the guide
-- data is unavailable. Deterministic per song, themed to the song's expansion.
function SongData.InstanceImage(song)
    buildInstanceImages()
    if not instanceImagesByTier then return nil end
    local n = tonumber(song.key:match("%d+")) or 1
    local list = instanceImagesByTier[tierForIndex(n)]
    if not list or #list == 0 then
        for _, l in pairs(instanceImagesByTier) do
            if #l > 0 then list = l break end
        end
    end
    if not list or #list == 0 then return nil end
    return list[((n - 1) % #list) + 1], INSTANCE_TEXCOORD
end
