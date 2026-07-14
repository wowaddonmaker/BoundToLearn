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

-- Real tempo measured from each track's audio, folded into a felt 80-160 range to
-- dodge the half/double-time errors tempo detection makes. Drives note spacing and
-- the difficulty rating. Falls back to a stable id-derived value if unknown.
SongData.REAL_BPM = {
    s1=152, s2=83, s3=152, s4=108, s5=108, s6=96, s7=118, s8=118, s9=152, s10=112,
    s11=152, s12=112, s13=136, s14=129, s15=123, s16=144, s17=136, s18=118, s19=152, s20=152,
    s21=118, s22=103, s23=136, s24=103, s25=86, s26=103, s27=108, s28=112, s29=96, s30=86,
    s31=99, s32=136, s33=123, s34=112, s35=108, s36=108, s37=118, s38=108, s39=81, s40=152,
    s41=129, s42=123, s43=136, s44=129, s45=123, s46=81, s47=89, s48=118, s49=152, s50=89,
    s51=89, s52=136, s53=129, s54=96, s55=86, s56=81, s57=108, s58=96, s59=152, s60=129,
    s61=144, s62=86, s63=152, s64=157, s65=118, s66=123, s67=152, s68=92,
}
function SongData.BPM(song)
    if not song then return 120 end
    return SongData.REAL_BPM[song.key] or (96 + (song.id % 70))
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

-- A 1-10 rating for the carousel meter, per song AND difficulty. Each tier gets its
-- own even band (Easy 1-2, Medium 3-5, Hard 6-8, Extreme 9-10) so the spread between
-- difficulties is uniform, and the track's tempo slides the rating within that band so
-- faster tracks read as harder and every song shows a distinct bar per tier.
local RATING_BASE   = { Easy = 1.5, Medium = 4.0, Hard = 7.0, Extreme = 9.4 }
local RATING_SPREAD = { Easy = 0.9, Medium = 1.8, Hard = 1.8, Extreme = 1.0 }
function SongData.Rating(song, difficulty)
    local base = RATING_BASE[difficulty] or 4.0
    local spread = RATING_SPREAD[difficulty] or 1.4
    local tempo = mmax(0, mmin(1, (SongData.BPM(song) - 90) / 65))   -- 0 (slow) .. 1 (fast)
    local raw = base + (tempo - 0.5) * spread
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

-- Resolves each song to { img, tier } by matching the track's name against the
-- Adventure Guide's instances. Forward-declared so XpacBackground can use the
-- matched instance's real expansion instead of guessing from the song's index.
local resolveSong

function SongData.XpacBackground(song)
    local atlas = SongData.XPAC_BG[resolveSong(song).tier]
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return atlas
    end
    return "ui-ej-midnight"
end

-- Five-axis "groove" profile (each 0-1) for the radar on the song select, using
-- terms that fit a keybind rhythm game rather than DDR's. Varies per song and
-- difficulty so every chart has a distinct shape.
-- Speed: scroll pace. Density: overall notes. Offbeat: syncopation / off-beat
-- emphasis. Bursts: peak subdivision. Stamina: track length / endurance.
SongData.RADAR_LABELS = { "Speed", "Density", "Offbeat", "Bursts", "Stamina" }

-- Per-song groove from the actual baked chart: note rate, plus the share of off-beat
-- (eighth) and burst (sixteenth) subdivisions from the level mix. Distinct per track.
local DIFF_GROOVE_SCALE = { Easy = 0.55, Medium = 0.75, Hard = 0.9, Extreme = 1.0 }
-- Mirrors the game's per-difficulty note fall speed (Easy ~96 -> Extreme ~240): Easy
-- notes crawl, Extreme fly. Hard and Extreme share the fall speed, so Extreme only
-- edges ahead on the extra density it also brings.
local DIFF_SPEED_SCALE = { Easy = 0.40, Medium = 0.72, Hard = 0.92, Extreme = 1.0 }
local function chartGroove(key)
    local chart = ns.SongCharts and ns.SongCharts[key]
    if not (chart and chart.notes and #chart.notes > 0) then return nil end
    local notes, l2, l34 = chart.notes, 0, 0
    local total = #notes
    for i = 1, total do
        local lv = notes[i][3] or 1
        if lv == 2 then l2 = l2 + 1
        elseif lv >= 3 then l34 = l34 + 1 end
    end
    return {
        density = total / mmax(1, chart.duration or 1),
        offbeat = (l2 + l34) / total,     -- everything off the strong beat
        bursts  = l34 / total,            -- sixteenth-note content
    }
end

function SongData.Radar(song, difficulty)
    local function clampAxis(v) return mmax(0.12, mmin(1, v)) end
    -- Speed and Stamina come from the track's real tempo and length. Density, Offbeat
    -- and Bursts come from the track's own chart (so they differ per track), scaled by
    -- the difficulty so a harder chart reads busier.
    local dscale  = DIFF_GROOVE_SCALE[difficulty] or 0.75
    local sscale  = DIFF_SPEED_SCALE[difficulty] or 0.8
    -- Speed is dominated by the difficulty's fall speed, nudged by the track tempo;
    -- Stamina rises with difficulty too (a harder chart sustains more effort). Neither
    -- is the same for Easy and Extreme any more.
    local speed   = sscale * (0.8 + 0.35 * ((SongData.BPM(song) - 90) / 70))
    local stamina = (((song.length or 200) - 120) / 640) * (0.55 + 0.45 * dscale)
    local density, offbeat, bursts
    local g = chartGroove(song.key)
    if g then
        density = (g.density / 3.2) * dscale
        offbeat = g.offbeat * (0.5 + 0.7 * dscale)
        bursts  = g.bursts  * (0.4 + 1.2 * dscale)
    else
        local prof = SongData.DifficultyProfile(difficulty)
        density = (prof.subdiv * prof.fill / 3.2)
        offbeat = (prof.jump / 0.22)
        bursts  = (prof.subdiv / 4)
    end
    return {
        clampAxis(speed), clampAxis(density), clampAxis(offbeat),
        clampAxis(bursts), clampAxis(stamina),
    }
end

-- Tie each song to a themed dungeon/raid via the Adventure Guide so the selected
-- bubble can show that instance's button art. The list is built once, lazily:
-- load the guide, walk every expansion tier's dungeons and raids, and cache the
-- button images. EJ_SelectTier mutates the guide's current tier, so it is saved
-- and restored. All returned button images share the same crop as the live grid.
local instanceList          -- flat { {img=, tier=, lname=, words=}, ... } across all tiers
-- bgImage's art sits in roughly the top-left ~0.80 x 0.74 of its texture (the right
-- edge and bottom are black padding). Sample a wide, short band from the lower-middle
-- of that region for the bubble's ~4.3:1 art, staying clear of the hazy sky up top and
-- the right/bottom padding. Nudge the band if an instance's art still sits off.
local INSTANCE_TEXCOORD = { 0, 0.77, 0.40, 0.72 }

-- Words too generic to tie a song to a specific instance on their own (they
-- recur across many instance names), plus common song-title noise. A match must
-- rest on a distinctive proper noun, not "Halls"/"Citadel"/"Intro".
local NAME_STOP = {
    ["the"] = true, ["of"] = true, ["and"] = true, ["for"] = true, ["a"] = true,
    ["an"] = true, ["to"] = true, ["in"] = true, ["on"] = true,
    mount = true, upper = true, lower = true, halls = true, hall = true,
    temple = true, citadel = true, keep = true, castle = true, fortress = true,
    palace = true, throne = true, vault = true, sanctum = true, chamber = true,
    chambers = true, caverns = true, cavern = true, depths = true, deeps = true,
    grounds = true, ground = true, spire = true, spires = true, peak = true,
    peaks = true, isle = true, ruins = true, tomb = true, crypt = true, pit = true,
    gate = true, gates = true, well = true, city = true, trial = true,
    assault = true, battle = true, siege = true, ["return"] = true, crucible = true,
    sanctuary = true, terrace = true, court = true, garden = true, gardens = true,
    seat = true, hold = true, cove = true, den = true, lair = true, nest = true,
    -- song-title noise
    intro = true, hero = true, theme = true, part = true, main = true, title = true,
    saga = true, remix = true, walk = true, day = true, night = true, ambient = true,
    flyby = true, summit = true, crossing = true, ascent = true, descent = true,
}

-- Distinctive lowercase words (>= 4 chars) from a name, as a set.
local function buildWordSet(str)
    local out = {}
    for w in str:gmatch("%a+") do
        w = w:lower()
        if #w >= 4 and not NAME_STOP[w] then out[w] = true end
    end
    return out
end

local function buildInstanceImages()
    if instanceList then return end
    instanceList = {}
    if C_AddOns and C_AddOns.LoadAddOn then
        C_AddOns.LoadAddOn("Blizzard_EncounterJournal")
    end
    if not (EJ_GetInstanceByIndex and EJ_SelectTier and EJ_GetNumTiers) then return end
    local prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or 1
    for tier = 1, EJ_GetNumTiers() do
        EJ_SelectTier(tier)
        for r = 1, 2 do
            local isRaid = (r == 2)
            local i = 1
            while true do
                -- bgImage (position 4) is the full-size instance background: far
                -- higher resolution than the small button art, so prefer it.
                local instanceID, name, _, bgImage, buttonImage1, loreImage = EJ_GetInstanceByIndex(i, isRaid)
                if not instanceID then break end
                local img = bgImage or buttonImage1 or loreImage
                if img and name then
                    instanceList[#instanceList + 1] = {
                        img = img, tier = tier,
                        lname = name:lower(), words = buildWordSet(name),
                    }
                end
                i = i + 1
            end
        end
    end
    EJ_SelectTier(prevTier)
end

-- Score the song title against every instance name and return (img, tier) of the
-- best match, or nil. A full-name hit ("Black Temple Summit" -> Black Temple)
-- dominates; otherwise distinctive shared words add up ("Sunwell Flyby" ->
-- Sunwell Plateau via "sunwell", "Fall of Ulduar" -> Ulduar). Generic words are
-- filtered by NAME_STOP so "Halls"/"Citadel" alone never decide a match.
local function matchInstance(title)
    if not instanceList then return nil end
    local titleWords = buildWordSet(title)
    local bestImg, bestTier, bestScore = nil, nil, 0
    for _, inst in ipairs(instanceList) do
        local score = 0
        if #inst.lname >= 5 and title:find(inst.lname, 1, true) then
            score = #inst.lname * 3
        end
        for w in pairs(inst.words) do
            if titleWords[w] then score = score + #w end
        end
        if score > bestScore then
            bestScore, bestImg, bestTier = score, inst.img, inst.tier
        end
    end
    if bestScore >= 5 then return bestImg, bestTier end
    return nil
end

-- Iconic raid per expansion tier, used as the backdrop for tracks not named
-- after a specific instance (character themes, zone music, expansion titles).
-- Matched by a distinctive, apostrophe-free substring so the right button art is
-- found regardless of the Adventure Guide's ordering.
local TIER_FLAGSHIP = {
    [1]  = "molten core",
    [2]  = "black temple",
    [3]  = "icecrown",
    [4]  = "dragon soul",
    [5]  = "siege of org",
    [6]  = "hellfire cit",
    [7]  = "antorus",
    [8]  = "alotha",       -- Ny'alotha, the Waking City
    [9]  = "sepulcher",    -- Sepulcher of the First Ones
    [10] = "amirdrassil",
}

local flagshipCache = {}
local function flagshipImage(tier)
    local cached = flagshipCache[tier]
    if cached ~= nil then return cached or nil end
    local key = TIER_FLAGSHIP[tier]
    local img = false
    if key and instanceList then
        for _, inst in ipairs(instanceList) do
            if inst.lname:find(key, 1, true) then
                img = inst.img
                break
            end
        end
    end
    flagshipCache[tier] = img
    return img or nil
end

local songResolveCache = {}
resolveSong = function(song)
    local cached = songResolveCache[song.key]
    if cached then return cached end
    buildInstanceImages()
    local img, tier = matchInstance(song.title:lower())
    if not tier then
        tier = tierForIndex(tonumber(song.key:match("%d+")) or 1)
    end
    -- No name match: fall back to the era's flagship raid so the bubble still
    -- shows fitting art instead of the neutral silver look.
    if not img then
        img = flagshipImage(tier)
    end
    cached = { img = img, tier = tier }
    songResolveCache[song.key] = cached
    return cached
end

-- Returns (fileID, texcoords) for the selected song bubble, or nil when the
-- track is not named after any Adventure Guide instance (the bubble then keeps
-- the neutral silver look rather than showing an unrelated instance).
function SongData.InstanceImage(song)
    local r = resolveSong(song)
    if r.img then return r.img, INSTANCE_TEXCOORD end
    return nil
end

-- A representative music file for an expansion tier: the first track that
-- resolves to that tier. Lets the Ping Trainer play era-appropriate music for
-- the chosen expansion backdrop without a second hand-maintained ID list.
function SongData.TierMusic(tier)
    for i = 1, #SongData.songs do
        local song = SongData.songs[i]
        if resolveSong(song).tier == tier then
            return song.id
        end
    end
    return nil
end
