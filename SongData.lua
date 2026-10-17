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

-- Forever's own soundtrack (its re-recorded classic themes and the music of
-- its new zones), the longest take of each. Forever only; "f" keys keep their
-- scores apart from the shared tracks.
local FOREVER_SONGS = {
    { key = "f1", title = [[Bolder'ok]], artist = [[Blizzard Entertainment]], id = 8158694, length = 64 },
    { key = "f2", title = [[Cradle of Tranquility]], artist = [[Blizzard Entertainment]], id = 8173703, length = 71 },
    { key = "f3", title = [[Dae'gun]], artist = [[Blizzard Entertainment]], id = 8198465, length = 66 },
    { key = "f4", title = [[Eastwind Shore]], artist = [[Blizzard Entertainment]], id = 8158706, length = 100 },
    { key = "f5", title = [[Elderwild]], artist = [[Blizzard Entertainment]], id = 8197333, length = 72 },
    { key = "f6", title = [[Farholde Keep]], artist = [[Blizzard Entertainment]], id = 8158710, length = 82 },
    { key = "f7", title = [[Felblood Scar]], artist = [[Blizzard Entertainment]], id = 8269358, length = 63 },
    { key = "f8", title = [[Gustberry Lowlands]], artist = [[Blizzard Entertainment]], id = 8158740, length = 76 },
    { key = "f9", title = [[Mount Hyjal]], artist = [[Blizzard Entertainment]], id = 8158674, length = 61 },
    { key = "f10", title = [[Malorne's Retreat]], artist = [[Blizzard Entertainment]], id = 8190628, length = 64 },
    { key = "f11", title = [[Mourning's Rest]], artist = [[Blizzard Entertainment]], id = 8158680, length = 67 },
    { key = "f12", title = [[Riverglades]], artist = [[Blizzard Entertainment]], id = 8173717, length = 68 },
    { key = "f13", title = [[Rog'mar Outpost]], artist = [[Blizzard Entertainment]], id = 8158722, length = 66 },
    { key = "f14", title = [[Shadowgale Forest]], artist = [[Blizzard Entertainment]], id = 8246682, length = 73 },
    { key = "f15", title = [[Shen'dar]], artist = [[Blizzard Entertainment]], id = 8158746, length = 72 },
    { key = "f16", title = [[Shrine of Akir]], artist = [[Blizzard Entertainment]], id = 8246690, length = 64 },
    { key = "f17", title = [[Shrine of Aviana]], artist = [[Blizzard Entertainment]], id = 8282397, length = 90 },
    { key = "f18", title = [[Summit of Eternity]], artist = [[Blizzard Entertainment]], id = 8282581, length = 51 },
    { key = "f19", title = [[Sunnyglade]], artist = [[Blizzard Entertainment]], id = 8173719, length = 79 },
    { key = "f20", title = [[Tainted Foothills]], artist = [[Blizzard Entertainment]], id = 8269360, length = 76 },
    { key = "f21", title = [[Thendal Village]], artist = [[Blizzard Entertainment]], id = 8158756, length = 76 },
    { key = "f22", title = [[Twilight's Shroud]], artist = [[Blizzard Entertainment]], id = 8269366, length = 69 },
    { key = "f23", title = [[Valanaar]], artist = [[Blizzard Entertainment]], id = 8175596, length = 54 },
    { key = "f24", title = [[Wheeler's Grange]], artist = [[Blizzard Entertainment]], id = 8158732, length = 80 },
    { key = "f25", title = [[Darkmoon Faire]], artist = [[Blizzard Entertainment]], id = 8181339, length = 131 },
    { key = "f26", title = [[Dungeon Boss]], artist = [[Blizzard Entertainment]], id = 8280857, length = 66 },
    { key = "f27", title = [[Dungeon Horror]], artist = [[Blizzard Entertainment]], id = 8280853, length = 84 },
    { key = "f28", title = [[Stormwind]], artist = [[Blizzard Entertainment]], id = 8180878, length = 87 },
    { key = "f29", title = [[Orgrimmar]], artist = [[Blizzard Entertainment]], id = 8181033, length = 69 },
    { key = "f30", title = [[Ironforge]], artist = [[Blizzard Entertainment]], id = 8180965, length = 118 },
    { key = "f31", title = [[Thunder Bluff]], artist = [[Blizzard Entertainment]], id = 8181001, length = 120 },
    { key = "f32", title = [[Undercity]], artist = [[Blizzard Entertainment]], id = 8181005, length = 87 },
    { key = "f33", title = [[Darnassus]], artist = [[Blizzard Entertainment]], id = 8180752, length = 85 },
    { key = "f34", title = [[Stranglethorn Vale]], artist = [[Blizzard Entertainment]], id = 8200680, length = 102 },
    { key = "f35", title = [[Zul'Gurub Voodoo]], artist = [[Blizzard Entertainment]], id = 8181341, length = 85 },
    { key = "f36", title = [[Naxxramas]], artist = [[Blizzard Entertainment]], id = 8180911, length = 102 },
}

-- Tracks the Forever client does not ship; dropped from its song list.
local FOREVER_MISSING = {
    s5 = true, s6 = true, s10 = true, s11 = true, s12 = true, s14 = true,
    s17 = true, s18 = true, s19 = true, s20 = true, s21 = true, s22 = true,
    s23 = true, s26 = true, s27 = true, s28 = true, s29 = true, s30 = true,
    s31 = true, s33 = true, s34 = true, s35 = true, s36 = true, s37 = true,
    s40 = true, s41 = true, s42 = true, s43 = true, s44 = true, s45 = true,
    s56 = true, s57 = true, s58 = true, s59 = true, s60 = true, s66 = true,
}
local allSongs = SongData.songs

-- Dev probe (/btl songcheck): asks the client which tracks it can play.
-- Returns the unplayable keys, and those where the Forever lists disagree
-- (a shared track marked missing that plays, or a Forever track that does not).
function SongData.CheckTracks()
    local unplayable, disagree = {}, {}
    local function check(song, expectMissing)
        local willPlay, handle = PlaySoundFile(song.id, "Master")
        if willPlay then
            StopSound(handle)
        else
            unplayable[#unplayable + 1] = song.key
        end
        if (not willPlay) ~= expectMissing then
            disagree[#disagree + 1] = song.key
        end
    end
    for i = 1, #allSongs do
        check(allSongs[i], FOREVER_MISSING[allSongs[i].key] or false)
    end
    local total = #allSongs
    if Utils.IS_FOREVER then
        for i = 1, #FOREVER_SONGS do check(FOREVER_SONGS[i], false) end
        total = total + #FOREVER_SONGS
    end
    return unplayable, disagree, total
end

-- Each track's entry in the issue forms' "Which track?" dropdown: its title, with
-- the client named where two tracks share a title. Both clients' tracks, sorted;
-- tools/issue_forms.lua writes the dropdown from this list.
local issueLabel, issueTracks = {}, {}
do
    local count = {}
    local function each(fn)
        for i = 1, #allSongs do fn(allSongs[i]) end
        for i = 1, #FOREVER_SONGS do fn(FOREVER_SONGS[i]) end
    end
    each(function(song) count[song.title] = (count[song.title] or 0) + 1 end)
    each(function(song)
        local label = song.title
        if count[song.title] > 1 then
            label = label .. ((song.key:sub(1, 1) == "f" and " (WoW Forever)")
                or (FOREVER_MISSING[song.key] and " (Retail)") or " (both clients)")
        end
        issueLabel[song.key] = label
        issueTracks[#issueTracks + 1] = label
    end)
    table.sort(issueTracks)
end
function SongData.IssueLabel(key) return issueLabel[key] end
function SongData.IssueTracks() return issueTracks end

-- Forever: its own soundtrack first, then the shared tracks it ships.
if Utils.IS_FOREVER then
    local kept = {}
    for i = 1, #FOREVER_SONGS do kept[#kept + 1] = FOREVER_SONGS[i] end
    for i = 1, #SongData.songs do
        local song = SongData.songs[i]
        if not FOREVER_MISSING[song.key] then kept[#kept + 1] = song end
    end
    SongData.songs = kept
end

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

-- Seconds from a track's start to its full sound, measured from the audio by
-- tools/measure_intros.py (first moment the loudness comes within 6 dB of the
-- track's typical level and stays there). The Icon Game plays this part muted
-- during the countdown, so GO lands on the real music. Tracks not listed start
-- at full sound.
SongData.LEAD_IN = {
    s1 = 3.4,
    s2 = 1.8,
    s3 = 12.9,
    s4 = 0.4,
    s5 = 0.4,
    s7 = 1.1,
    s9 = 0.6,
    s11 = 1.4,
    s12 = 1.4,
    s13 = 1.1,
    s14 = 8.6,
    s15 = 4.1,
    s16 = 0.4,
    s17 = 3.8,
    s18 = 1.3,
    s20 = 6.4,
    s21 = 0.6,
    s22 = 6.0,
    s23 = 0.5,
    s24 = 0.6,
    s25 = 4.9,
    s27 = 1.4,
    s28 = 0.5,
    s29 = 1.0,
    s31 = 7.9,
    s32 = 8.3,
    s33 = 6.4,
    s34 = 1.3,
    s35 = 8.6,
    s36 = 2.6,
    s37 = 0.6,
    s38 = 4.5,
    s39 = 0.3,
    s40 = 1.6,
    s41 = 2.3,
    s42 = 20.1,
    s43 = 17.9,
    s45 = 7.9,
    s46 = 1.9,
    s47 = 1.9,
    s48 = 3.9,
    s49 = 2.8,
    s50 = 1.9,
    s51 = 1.1,
    s52 = 9.3,
    s53 = 7.4,
    s54 = 8.7,
    s55 = 1.6,
    s57 = 3.1,
    s59 = 0.8,
    s60 = 3.7,
    s62 = 0.9,
    s63 = 3.1,
    s64 = 0.6,
    s65 = 0.4,
    s66 = 8.5,
    s68 = 1.1,
    f1 = 3.7,
    f2 = 4.2,
    f3 = 4.4,
    f4 = 2.1,
    f5 = 5.3,
    f6 = 2.3,
    f7 = 2.3,
    f8 = 4.5,
    f9 = 1.0,
    f10 = 4.0,
    f11 = 0.7,
    f12 = 4.7,
    f13 = 4.0,
    f14 = 1.3,
    f15 = 1.3,
    f16 = 1.2,
    f17 = 0.3,
    f18 = 2.5,
    f19 = 2.9,
    f20 = 1.3,
    f21 = 3.3,
    f22 = 4.8,
    f23 = 1.8,
    f24 = 6.2,
    f26 = 1.5,
    f27 = 7.0,
    f28 = 2.4,
    f29 = 7.1,
    f30 = 1.5,
    f32 = 2.0,
    f33 = 2.8,
    f34 = 9.0,
    f35 = 8.6,
    f36 = 15.4,
}

function SongData.LeadIn(key)
    return SongData.LEAD_IN[key] or 0
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
    f1=96, f2=86, f3=118, f4=118, f5=81, f6=118, f7=103, f8=129, f9=112, f10=96,
    f11=86, f12=81, f13=118, f14=123, f15=152, f16=129, f17=86, f18=123, f19=99, f20=86,
    f21=152, f22=129, f23=99, f24=152, f25=118, f26=129, f27=144, f28=144, f29=140, f30=123,
    f31=92, f32=152, f33=96, f34=152, f35=123, f36=108,
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

-- Forever has no Midnight backdrop; its neutral art is the Classic one.
SongData.DEFAULT_BG = Utils.IS_FOREVER and "ui-ej-classic" or "ui-ej-midnight"

function SongData.XpacBackground(song)
    local atlas = SongData.XPAC_BG[resolveSong(song).tier]
    if atlas and C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(atlas) then
        return atlas
    end
    return SongData.DEFAULT_BG
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
    -- Forever has the guide's functions but no tiers (tier 0 is refused).
    local numTiers = EJ_GetNumTiers()
    if numTiers < 1 then return end
    local prevTier = EJ_GetCurrentTier and EJ_GetCurrentTier() or 1
    if prevTier < 1 then prevTier = 1 end
    for tier = 1, numTiers do
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

-- Forever has no Adventure Guide data. Its client still ships the art, so
-- each song carries what retail resolves: { background file, tier, crop }.
local FOREVER_ART = {
    s3 = { 4423751, 9 }, s4 = { 2177522, 8 }, s7 = { 1718200, 7 }, s8 = { 1718200, 7 },
    s9 = { 1041969, 6 }, s13 = { 652217, 5 }, s15 = { 904980, 5 }, s16 = { 904980, 5 },
    s24 = { 571738, 4 }, s25 = { 571738, 4 }, s32 = { 1396457, 3 }, s46 = { 1718200, 7 },
    s52 = { 608159, 2 }, s53 = { 608159, 2 }, s54 = { 608159, 2 }, s55 = { 1396453, 2 },
    s61 = { 1396453, 2 }, s62 = { 1396460, 1 },
    -- Forever's own Dalaran painting (not on retail)
    s38 = { 7963775, 3, { 0.345, 0.895, 0.374, 0.586 } },
    s39 = { 7963775, 3, { 0.025, 0.475, 0.493, 0.667 } },
}
-- Art picked by hand where the guide has nothing that fits (cities, zones,
-- Forever's new places): { file, tier, crop }. Loading screens carry a crop
-- cut to the bubble's shape; guide backgrounds use INSTANCE_TEXCOORD. Wins
-- over the guide match on both clients (the f tracks exist only on Forever).
local TRACK_ART = {
    f1 = { 1013075, 1, { 0.075, 0.925, 0.427, 0.673 } }, -- Bolder'ok
    f2 = { 1476725, 1, { 0.100, 0.900, 0.395, 0.705 } }, -- Cradle of Tranquility
    f3 = { 1411843, 1 },                            -- Dae'gun
    f4 = { 7963776, 1, { 0.025, 0.575, 0.344, 0.556 } }, -- Eastwind Shore
    f5 = { 131847, 1, { 0.025, 0.575, 0.470, 0.630 } }, -- Elderwild
    f6 = { 522342, 1 },                             -- Farholde Keep
    f7 = { 522337, 1 },                             -- Felblood Scar
    f8 = { 7950679, 1, { 0.010, 0.430, 0.539, 0.701 } }, -- Gustberry Lowlands
    f9 = { 131847, 1, { 0.150, 0.950, 0.304, 0.536 } }, -- Mount Hyjal
    f10 = { 5409260, 1 },                           -- Malorne's Retreat
    f11 = { 7963782, 1, { 0.075, 0.925, 0.336, 0.664 } }, -- Mourning's Rest
    f12 = { 7963776, 1, { 0.320, 0.920, 0.504, 0.736 } }, -- Riverglades
    f13 = { 7963777, 1, { 0.075, 0.925, 0.386, 0.714 } }, -- Rog'mar Outpost
    f14 = { 7950679, 1, { 0.000, 0.240, 0.554, 0.646 } }, -- Shadowgale Forest
    f15 = { 7950679, 1, { 0.410, 0.830, 0.539, 0.701 } }, -- Shen'dar
    f16 = { 7950679, 1, { 0.340, 0.600, 0.450, 0.550 } }, -- Shrine of Akir
    f17 = { 5344997, 1, { 0.025, 0.875, 0.336, 0.664 } }, -- Shrine of Aviana
    f18 = { 571741, 1 },                            -- Summit of Eternity
    f19 = { 131882, 1, { 0.100, 0.900, 0.484, 0.716 } }, -- Sunnyglade
    f20 = { 571739, 1 },                            -- Tainted Foothills
    f21 = { 7950679, 1, { 0.610, 0.990, 0.477, 0.623 } }, -- Thendal Village
    f22 = { 571740, 1 },                            -- Twilight's Shroud
    f23 = { 7950679, 1, { 0.075, 0.925, 0.336, 0.664 } }, -- Valanaar
    f24 = { 7963776, 1, { 0.275, 0.825, 0.194, 0.406 } }, -- Wheeler's Grange
    f25 = { 534166, 1, { 0.075, 0.925, 0.427, 0.673 } }, -- Darkmoon Faire
    f26 = { 608157, 1 },                            -- Dungeon Boss
    f27 = { 608176, 1 },                            -- Dungeon Horror
    f28 = { 1099378, 1, { 0.075, 0.925, 0.327, 0.573 } }, -- Stormwind
    f29 = { 236064, 1, { 0.075, 0.925, 0.427, 0.673 } }, -- Orgrimmar
    f30 = { 7963781, 1, { 0.075, 0.925, 0.336, 0.664 } }, -- Ironforge
    f31 = { 7963779, 1, { 0.075, 0.925, 0.336, 0.664 } }, -- Thunder Bluff
    f32 = { 131867, 1, { 0.075, 0.925, 0.427, 0.673 } }, -- Undercity
    f33 = { 1417745, 1, { 0.200, 0.900, 0.365, 0.635 } }, -- Darnassus
    f34 = { 131886, 1, { 0.075, 0.925, 0.427, 0.673 } }, -- Stranglethorn Vale
    f35 = { 522348, 1 },                            -- Zul'Gurub Voodoo
    f36 = { 1396461, 1 },                           -- Naxxramas
    s47 = { 131830, 3, { 0.200, 0.700, 0.528, 0.672 } }, -- Thrall's Escape
    s48 = { 522337, 3 },                            -- Fire Festival
    s49 = { 131830, 3, { 0.345, 0.895, 0.320, 0.480 } }, -- Brazen's Flight
    s50 = { 131830, 3, { 0.435, 0.885, 0.455, 0.585 } }, -- Durnholde Keep
    s51 = { 608180, 3 },                            -- Escape from Durnholde
    s63 = { 5344997, 1, { 0.470, 0.970, 0.353, 0.547 } }, -- Enchanted Forest
    s64 = { 131867, 1, { 0.050, 0.750, 0.619, 0.821 } }, -- Spooky
    s65 = { 1099378, 1, { 0.425, 0.975, 0.340, 0.500 } }, -- Stormwind Intro
    s67 = { 131820, 1, { 0.025, 0.975, 0.262, 0.538 } }, -- Battle
    s68 = { 131883, 1, { 0.025, 0.975, 0.362, 0.638 } }, -- PvP
}

-- Retail tracks the guide finds nothing for fell back to their era's main
-- raid, five pictures across 34 tracks. Each now shows the place its music
-- comes from: { file, crop }, the crop cut to the bubble's shape (a nil crop
-- is a guide background, cut with INSTANCE_TEXCOORD). Retail only: Forever
-- keeps FOREVER_ART for the ones it plays.
local RETAIL_ART = {
    s10 = { 1035009, { 0.080, 0.920, 0.400, 0.721 } }, -- Draenor, the warlords
    s11 = { 1060205, { 0.050, 0.900, 0.400, 0.643 } }, -- The Everbloom, Gorgrond
    s12 = { 1032622, { 0.100, 0.950, 0.400, 0.643 } }, -- Blackrock Foundry
    s14 = { 574578, { 0.075, 0.925, 0.350, 0.593 } },  -- The Wandering Isle
    s15 = { 633149, { 0.075, 0.925, 0.330, 0.573 } },  -- Jade Forest temple
    s16 = { 651994, { 0.180, 0.980, 0.280, 0.586 } },  -- Pandaria
    s20 = { 1375896, { 0.050, 0.950, 0.300, 0.644 } }, -- Peak of Serenity
    s21 = { 633150, { 0.075, 0.925, 0.400, 0.643 } },  -- Mogu'shan Palace
    s22 = { 774865, { 0.050, 0.900, 0.300, 0.543 } },  -- Lion's Landing
    s23 = { 651536, { 0.050, 0.950, 0.380, 0.637 } },  -- Theramore
    s24 = { 534812, { 0.075, 0.925, 0.260, 0.503 } },  -- Deathwing
    s25 = { 2529512, { 0.050, 0.950, 0.280, 0.624 } }, -- Darkshore
    s26 = { 512032, { 0.075, 0.925, 0.420, 0.663 } },  -- The Maelstrom (Lost Isles)
    s27 = { 1417745, { 0.200, 0.900, 0.365, 0.632 } }, -- Night elf grove
    s28 = { 1099378, { 0.050, 0.900, 0.420, 0.663 } }, -- Alliance town
    s29 = { 424078, { 0.075, 0.925, 0.380, 0.623 } },  -- Deepholm
    s31 = { 514085, { 0.075, 0.925, 0.300, 0.543 } },  -- Firelands
    s32 = { 343003, { 0.100, 0.900, 0.240, 0.546 } },  -- Northrend, Arthas
    s33 = { 608167 },                                  -- Halls of Stone
    s35 = { 608165 },                                  -- Halls of Lightning
    s38 = { 1496467, { 0.050, 0.950, 0.360, 0.704 } }, -- Dalaran, Violet Hold
    s39 = { 236058, { 0.050, 0.900, 0.560, 0.803 } },  -- Dalaran prison portals
    s40 = { 236060, { 0.075, 0.925, 0.290, 0.533 } },  -- Acherus over New Avalon
    s41 = { 1382383, { 0.050, 0.950, 0.300, 0.644 } }, -- Ebon Hold
    s42 = { 131836, { 0.075, 0.925, 0.360, 0.603 } },  -- Drak'Tharon Keep
    s43 = { 236061, { 0.075, 0.925, 0.400, 0.643 } },  -- Gundrak, beside Grizzly Hills
    s44 = { 311102, { 0.075, 0.925, 0.380, 0.623 } },  -- Argent coliseum
    s45 = { 318964, { 0.075, 0.925, 0.310, 0.553 } },  -- Icecrown Citadel
    s55 = { 131874, { 0.050, 0.900, 0.340, 0.583 } },  -- Quel'Danas at sunset
    s56 = { 131826, { 0.075, 0.925, 0.260, 0.503 } },  -- Black Temple, Illidan
    s57 = { 343004, { 0.150, 0.950, 0.240, 0.546 } },  -- Outland, Illidan and Kael'thas
    s59 = { 131873, { 0.075, 0.925, 0.280, 0.523 } },  -- Sunwell, Kil'jaeden
    s60 = { 7439363, { 0.050, 0.950, 0.400, 0.744 } }, -- Magisters' Terrace library
    s61 = { 534166, { 0.075, 0.925, 0.300, 0.543 } },  -- Darkmoon Faire
}

local songResolveCache = {}
resolveSong = function(song)
    local cached = songResolveCache[song.key]
    if cached then return cached end
    local picked = TRACK_ART[song.key]
    if picked then
        cached = { img = picked[1], tier = picked[2], tc = picked[3] }
        songResolveCache[song.key] = cached
        return cached
    end
    if Utils.IS_FOREVER then
        local art = FOREVER_ART[song.key]
        cached = {
            img = art and art[1],
            tier = art and art[2] or tierForIndex(tonumber(song.key:match("%d+")) or 1),
            tc = art and art[3],
        }
        songResolveCache[song.key] = cached
        return cached
    end
    buildInstanceImages()
    local img, tier = matchInstance(song.title:lower())
    if not tier then
        tier = tierForIndex(tonumber(song.key:match("%d+")) or 1)
    end
    local placed = RETAIL_ART[song.key]
    if placed then
        cached = { img = placed[1], tier = tier, tc = placed[2] }
        songResolveCache[song.key] = cached
        return cached
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
    if r.img then return r.img, r.tc or INSTANCE_TEXCOORD end
    return nil
end

-- Dev check (/btl songcheck): one picture (same file and crop) on more than
-- ART_REPEAT_MAX tracks, as "file: key key ...". A placeholder handed to a whole
-- group of tracks shows up here.
local ART_REPEAT_MAX = 3
function SongData.ArtRepeats()
    local groups, order = {}, {}
    for i = 1, #SongData.songs do
        local song = SongData.songs[i]
        local img, tc = SongData.InstanceImage(song)
        if img then
            local id = tostring(img) .. "@" .. table.concat(tc, ",")
            local g = groups[id]
            if not g then
                g = { img = img }
                groups[id] = g
                order[#order + 1] = id
            end
            g[#g + 1] = song.key
        end
    end
    local out = {}
    for _, id in ipairs(order) do
        local g = groups[id]
        if #g > ART_REPEAT_MAX then
            out[#out + 1] = string.format("%s: %s", tostring(g.img), table.concat(g, " "))
        end
    end
    return out
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
