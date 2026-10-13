local ADDON_NAME, ns = ...

local Tracker = {}
ns.Tracker = Tracker

local Utils    = ns.Utils
local GetTime  = Utils.GetTime
local tinsert  = Utils.tinsert
local tremove  = Utils.tremove
local wipe     = Utils.wipe
local mfloor   = Utils.mfloor
local sformat  = Utils.sformat
local sfind    = Utils.sfind
local ipairs   = Utils.ipairs

local hooksecurefunc = hooksecurefunc
local GetActionTexture = GetActionTexture
local GetActionInfo = GetActionInfo
local HasAction = HasAction
local C_Spell = C_Spell
local C_ToyBox = C_ToyBox
local C_Item = C_Item
local CONSUMABLE_CLASS_ID = Enum.ItemClass.Consumable
local GetProfessions = GetProfessions
local GetProfessionInfo = GetProfessionInfo
local C_SpellBook = C_SpellBook
local UnitName = UnitName
local UnitExists = UnitExists
local IsMounted = IsMounted
local HasOverrideActionBar = HasOverrideActionBar
local GetMacroBody = GetMacroBody
-- Pre-pull / passive buff spells (not combat abilities)
local BUFF_SPELLS = {
    [1459]   = true,   -- Arcane Intellect
    [21562]  = true,   -- Power Word: Fortitude
    [6673]   = true,   -- Battle Shout
    [264761] = true,   -- War-Scroll of Battle Shout
    [264764] = true,   -- War-Scroll of Fortitude
    [264760] = true,   -- War-Scroll of Intellect
    [381732] = true,   -- Blessing of the Bronze
    [1126]   = true,   -- Mark of the Wild
    [462854] = true,   -- Skyfury
    [462855] = true,   -- Skyfury (rank 2)
    [116781] = true,   -- Legacy of the White Tiger (Monk)
    [155522] = true,   -- Power of the Grave (DK)
    [203538] = true,   -- Greater Blessing of Kings
    [203539] = true,   -- Greater Blessing of Wisdom
}

-- Spells that create consumables (Conjure Refreshment variants)
local CONSUMABLE_SPELLS = {
    [190336] = true, -- Conjure Refreshment
    [42955]  = true, -- Conjure Refreshment (rank 2)
    [120056] = true, -- Conjure Refreshment (rank 3)
}

-- Profession spell cache (rebuilt each session from player's professions)
local professionSpells = {}

local isTracking = false
local isPaused = false
local hooksInstalled = false
local clickFlagSet = false
local inEncounter = false  -- true during boss encounters (ENCOUNTER_START..END)
local inCombat = false     -- true during combat (REGEN_DISABLED..ENABLED)

local ACTION_LOG_CAP = 50

local spellClickStats = {}

-- Hearthstone spell IDs (base hearthstone + toy variants)
local HEARTHSTONE_SPELLS = {
    [8690]   = true,   -- Hearthstone
    [556]    = true,   -- Astral Recall (Shaman)
    [171253] = true,   -- Garrison Hearthstone
    [312372] = true,   -- Return to Valdrakken
    [391042] = true,   -- Hearth of the Aspects
    [259860] = true,   -- Enchanted Hearthstone
    [278559] = true,   -- The Innkeeper's Daughter
    [231504] = true,   -- Tome of Town Portal
    [286353] = true,   -- Diaphanous Glimmerdust
    [345393] = true,   -- Broker Translocation Matrix
    [363799] = true,   -- Dominated Hearthstone
    [375357] = true,   -- Fire Eater's Hearthstone
    [136508] = true,   -- Dark Portal
    [308742] = true,   -- Eternal Traveler's Hearthstone
    [326064] = true,   -- Night Fae Hearthstone
    [94719]  = true,   -- The Innkeeper's Daughter
    [75136]  = true,   -- Ethereal Portal
    [64488]  = true,   -- The Innkeeper's Daughter
    [474029] = true,   -- Holographic Digitalization Hearthstone
    [466638] = true,   -- Notorious Thread's Hearthstone
}

-- Teleport/portal spell IDs (mage, monk, druid, DK, warlock, etc.)
local TELEPORT_SPELLS = {
    -- Mage teleports
    [3561] = true, [3562] = true, [3563] = true, [3565] = true, [3566] = true, [3567] = true,
    [32271] = true, [32272] = true, [33690] = true, [35715] = true, [49358] = true, [49359] = true,
    [53140] = true, [88342] = true, [88344] = true, [132621] = true, [132627] = true,
    [176242] = true, [176248] = true, [224869] = true, [224871] = true, [281403] = true,
    [281404] = true, [344587] = true, [395277] = true, [446540] = true,
    -- Mage portals
    [10059] = true, [11416] = true, [11417] = true, [11418] = true, [11419] = true, [11420] = true,
    [32266] = true, [32267] = true, [33691] = true, [35717] = true, [49360] = true, [49361] = true,
    [53142] = true, [88345] = true, [88346] = true, [132620] = true, [132626] = true,
    [176244] = true, [176246] = true, [224870] = true, [224872] = true, [281400] = true,
    [281402] = true, [344597] = true, [395289] = true, [446534] = true,
    -- Monk
    [126892] = true, -- Zen Pilgrimage
    [126895] = true, -- Zen Pilgrimage: Return
    -- Druid
    [18960]  = true, -- Teleport: Moonglade
    [193753] = true, -- Dreamwalk
    -- Death Knight
    [50977]  = true, -- Death Gate
    -- Shaman
    [556]    = true, -- Astral Recall (also hearthstone)
}

-- Nudge thresholds
local NUDGE_CLICK_THRESHOLD = 5
local NUDGE_RATIO_THRESHOLD = 0.5
local NUDGE_COOLDOWN = 120
local lastNudgeTime = {}

local sessionData = {
    startTime = 0,
    clicks = 0,
    keybinds = 0,
    actionLog = {},
}

local MAX_STORED_SEGMENTS = 50
local segments = {}     -- completed segments, most recent first
local overallData = { clicks = 0, keybinds = 0 }
local sessionStartTime = 0  -- overall session start (for Stats recording)

local function FinalizeCurrentSegment()
    local total = sessionData.clicks + sessionData.keybinds
    if total == 0 then return end

    -- Accumulate into overall totals
    overallData.clicks = overallData.clicks + sessionData.clicks
    overallData.keybinds = overallData.keybinds + sessionData.keybinds

    -- Only store named combat/encounter segments in history, not idle "Current" periods
    local label = sessionData.label or "Current"
    if label == "Current" then return end

    local seg = {
        label = label,
        startTime = sessionData.startTime,
        endTime = GetTime(),
        clicks = sessionData.clicks,
        keybinds = sessionData.keybinds,
    }
    tinsert(segments, 1, seg)
    while #segments > MAX_STORED_SEGMENTS do
        tremove(segments)
    end
end

-- Cache for toy detection so we don't call C_ToyBox every action
local toyCache = {}

local function BuildProfessionCache()
    wipe(professionSpells)
    local profs = {GetProfessions()}
    for i = 1, 6 do
        if profs[i] then
            local _, _, _, _, numAbilities, spellOffset = GetProfessionInfo(profs[i])
            for j = 1, numAbilities do
                local info = C_SpellBook.GetSpellBookItemInfo(spellOffset + j, Enum.SpellBookSpellBank.Player)
                if info and info.spellID then
                    professionSpells[info.spellID] = true
                end
            end
        end
    end
end

local function IsToyItem(itemID)
    if toyCache[itemID] ~= nil then return toyCache[itemID] end
    local isToy = C_ToyBox.GetToyInfo(itemID) ~= nil
    toyCache[itemID] = isToy
    return isToy
end

local function IsCombatMacro(macroIndex)
    local body = GetMacroBody(macroIndex)
    if not body then return false end
    body = body:lower()
    if sfind(body, "/cast", 1, true) then return true end
    if sfind(body, "/use", 1, true) then return true end
    if sfind(body, "/castsequence", 1, true) then return true end
    if sfind(body, "/cancelaura", 1, true) then return true end
    if sfind(body, "/cancelform", 1, true) then return true end
    if sfind(body, "/startattack", 1, true) then return true end
    if sfind(body, "/stopattack", 1, true) then return true end
    if sfind(body, "/petattack", 1, true) then return true end
    if sfind(body, "/stopcasting", 1, true) then return true end
    return false
end

local function ShouldIgnoreAction(slot)
    local actionType, id = GetActionInfo(slot)
    local filter = BoundToLearn.db.filter
    local blocklist = BoundToLearn.db.tracker.blocklist

    -- User blocklist always applies
    if id and blocklist and blocklist[id] then return true end

    -- Flyout menus and companion (battle pet) summons are always filtered
    if actionType == "companion" or actionType == "flyout" then return true end

    -- Skyriding abilities (mounted + override bar = skyriding vigor)
    if filter.skyriding and IsMounted() and HasOverrideActionBar() then return true end

    -- Mounts
    if actionType == "mount" then return filter.mounts end
    if actionType == "summonmount" then return filter.mounts end

    if actionType == "spell" and id then
        if filter.hearthstones and HEARTHSTONE_SPELLS[id] then return true end
        if filter.teleports and TELEPORT_SPELLS[id] then return true end
        if filter.consumables and CONSUMABLE_SPELLS[id] then return true end
        if filter.professions and professionSpells[id] then return true end
    end

    -- Items: check for toys, consumables
    if actionType == "item" and id then
        if filter.toys and IsToyItem(id) then return true end
        if filter.consumables then
            local classID = select(6, C_Item.GetItemInfoInstant(id))
            if classID == CONSUMABLE_CLASS_ID then return true end
        end
    end

    -- Non-combat macros
    if filter.nonCombatMacros and actionType == "macro" and id and not IsCombatMacro(id) then
        return true
    end

    -- Pre-pull buffs (Arcane Intellect, Fortitude, Mark of the Wild, etc.)
    if filter.buffs and actionType == "spell" and id and BUFF_SPELLS[id] then
        return true
    end

    return false
end

Tracker.ShouldIgnoreAction = ShouldIgnoreAction

local function GetActionIdentifier(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType and id then
        return actionType .. ":" .. id
    end
    return "slot:" .. slot
end

local function GetActionName(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and id and id ~= 0 then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name or ("Spell " .. id)
    elseif actionType == "item" and id and id ~= 0 then
        local name = C_Item.GetItemInfo(id)
        return name or ("Item " .. id)
    elseif actionType == "macro" and id then
        local macroName = GetActionText(slot)
        if not macroName or macroName == "" then
            macroName = GetMacroInfo(id)
        end
        return macroName or ("Macro " .. id)
    end
    return "Action " .. slot
end

local function TrackSpellStats(slot, wasClick)
    local key = GetActionIdentifier(slot)
    if not spellClickStats[key] then
        spellClickStats[key] = {
            clicks = 0,
            keybinds = 0,
            name = GetActionName(slot),
            icon = GetActionTexture(slot),
            slot = slot,
        }
    end
    local stats = spellClickStats[key]
    if wasClick then
        stats.clicks = stats.clicks + 1
    else
        stats.keybinds = stats.keybinds + 1
    end
    return stats
end

local CLICK_QUIPS = {
    "Your clicking has its own Wowhead comments section. Top reply: 'working as intended?'",
    "Someone posted your keybind stats on the guild Discord. The reaction was just question marks.",
    "The Ramkahen just discovered your keybinds buried under three feet of Uldum sand.",
    "Your keybinds have been on standby longer than the Exodar's engines.",
    "Your clicking has been immortalized in a Bard's tale. It's a tragedy.",
    "The Tillers would love your dedication. You've been farming clicks since Mists.",
    "An Innkeeper just offered your keybinds a room. They've been homeless since Cataclysm.",
    "Somewhere between Boralus and Zuldazar, your keybind usage got lost at sea.",
    "Somewhere in Dalaran, a mage is teaching a course on keybind archaeology. You're the case study.",
    "Your keybinds are listed on the Ironforge missing persons board.",
    "The Tuskarr offered your keybinds a fishing spot. They've got nothing else to do.",
    "Gamon has been through less abuse than your left mouse button.",
    "Lor'themar governed Silvermoon alone for years. Still less neglected than your keybinds.",
    "MOTHER ran a diagnostic on your keybind usage. Output: 'INSUFFICIENT DATA.'",
    "Your keybinds got exalted with the 'Never Pressed' faction.",
    "The Sha of Clicking hasn't been discovered yet, but you're the prime suspect.",
    "You treat your keybinds the way Blizzard treats worgen updates.",
    "Brann Bronzebeard keeps finding your unused keybinds in dig sites across Azeroth.",
    "Your mouse has ground more rep than anyone in the Aldor/Scryer war.",
    "Hemet Nesingwary has hunted less elusive things than your keybind usage.",
    "The Lorewalkers documented your keybind history. It was the shortest scroll.",
    "Kil'jaeden spent 10,000 years scheming. Your keybinds have been idle longer.",
    "Millhouse Manastorm has better impulse control than your clicking habit.",
    "Your keybinds have been missing so long they got a memorial in the Valley of Heroes.",
    "The Aspects gave up their power willingly. Your keybinds didn't have a choice.",
    "Gallywix tried to sell your keybind usage data. Refunded everyone due to lack of content.",
    "Your keybinds are on the same respawn timer as the Time-Lost Proto Drake.",
    "Hamuul Runetotem called. Wants to study your keybinds as a new form of hibernation.",
    "Somewhere in the Emerald Dream, a treant is growing from your unused keybinds.",
    "Thrall went through an identity crisis shorter than your keybind drought.",
    "Patch notes: 'Fixed a bug where your keybinds existed but were never used.'",
    "%s's keybind has been waiting longer than a DPS queue.",
    "Fun fact: every time you click, Thrall sheds a single tear.",
    "They say time is money, friend. Keybinds save both.",
    "Your keybinds are gathering so much dust they qualify as archaeology fragments.",
    "%s's keybind has been benched longer than most expansion features.",
    "%s's keybind is lonelier than a healer in a BG.",
    "Your mouse has clocked more overtime than a goblin in Booty Bay.",
    "A click a day keeps the glad mount away.",
    "If your clicks gave you gold, you'd be richer than Gallywix.",
    "Your clicking could generate enough energy to power Gnomeregan.",
    "They should add clicking as a boss mechanic. You'd be mythic-ready.",
    "Blizzard is adding a new achievement: 'Click 10,000 spells.' You're almost there.",
    "If I had a copper for every click, I'd have bought the Brutosaur by now.",
    "According to my calculations, you've clicked enough to mine a Khaz Algar node.",
    "Some say clicking builds character. Those people also keyboard turn.",
    "I renamed your mouse to 'Raid Leader' because it does all the work.",
    "Your keybinds are like Garrisons. Everyone has them, nobody visits.",
    "You click more than a Kobold hoards candles.",
    "Your keybinds are lonelier than Illidan before Legion.",
    "Roses are red, Teldrassil burned, your keybinds are there, yet remain unlearned.",
    "Every time you click a spell, a murloc gets its wings. Wait, that's not right either.",
    "You click like you're paying per keybind. They're free, by the way.",
    "Your click rate is higher than Auction House inflation.",
    "I asked Chromie to check the timeline. You've been clicking in every single one.",
    "Your keybinds are less used than the Dance Studio feature.",
    "That click was registered by both the Horde and Alliance seismographs.",
    "Jaina could've frozen all of Orgrimmar in the time it took you to click that.",
    "Your clicking has been reported to the Azeroth OSHA. On behalf of your mouse.",
    "If you clicked any harder, Deathwing would wake up again.",
    "What's the difference between your keybinds and Mankrik's wife? People actually looked for her.",
    "Your keybind has been on /afk since Wrath.",
    "You're clicking like you're still playing on a Commodore 64 in Molten Core.",
    "Your mouse has taken more hits than the tanks in LFR.",
    "You click like you're trying to unlock a secret Clicking spec. Spoiler: there isn't one.",
    "Vol'jin didn't die for this.",
    "That click was louder than a Kodo stampede through Mulgore.",
    "Your mouse has spent more time in combat than most Gladiators.",
    "Even Nozdormu can't find a timeline where you've used keybinds.",
    "C'Thun saw many things. Your keybind usage was not one of them.",
    "Magni asked me to tell you: 'Champion, the keybinds, they need ya.'",
    "Arthas fell to keybinders. Just putting that out there.",
    "%s's keybind has been missing longer than Turalyon was stuck in the Twisting Nether.",
    "Your clicking is more repetitive than the Maw intro questline.",
    "What did Lor'themar say about your keybinds? 'Selama ashal'anore.' It means 'Justice for those who were never pressed.'",
    "%s's keybind has more abandonment issues than Garrosh.",
    "You've generated enough clicks to power the Vindicaar's Light crystals.",
    "Your mouse just earned the title: 'the Insane.'",
    "Your keybind whispered 'Lok'tar ogar.' That's 'press me or I die' in Orcish.",
    "Elune wept. Not for Teldrassil this time. For your keybinds.",
    "What do your keybinds and Titan relics have in common? Both buried and forgotten.",
    "Yogg-Saron whispers: 'Use... your... keybinds...'",
    "Your mouse just unlocked the hidden achievement: 'Carpal Tunnel Candidate.'",
    "Your keybinds haven't been pressed since the last time Bolvar did something useful.",
    "The Defias Brotherhood plots less than your mouse does to escape your grip.",
    "Clicking that much should count toward the Insane in the Membrane grind.",
    "Your keybinds have less screen time than Med'an.",
    "Your mouse button is more worn down than the path to Ragnaros in Molten Core.",
    "Vol'jin's loa didn't choose you. Probably because of the clicking.",
    "%s's keybind is deader than the WoD garrison mission table.",
}
local lastQuipIndex = 0

local function GetRandomQuip()
    local idx = lastQuipIndex
    while idx == lastQuipIndex do
        idx = math.random(1, #CLICK_QUIPS)
    end
    lastQuipIndex = idx
    return CLICK_QUIPS[idx]
end

local YELLOW = "|cFFFFFF00"
local CLOSE = "|r"

local function CheckNudge(stats, slot)
    local total = stats.clicks + stats.keybinds
    if total < NUDGE_CLICK_THRESHOLD then return end

    local clickRatio = stats.clicks / total
    if clickRatio < NUDGE_RATIO_THRESHOLD then return end

    local key = GetActionIdentifier(slot)
    local now = GetTime()
    if lastNudgeTime[key] and (now - lastNudgeTime[key]) < NUDGE_COOLDOWN then return end
    lastNudgeTime[key] = now

    local quip = GetRandomQuip()
    local name = stats.name
    if not name or name == "" then
        name = GetActionName(slot)
    end
    local coloredName = YELLOW .. name .. CLOSE
    if sfind(quip, "%%s") then
        Utils.Print(sformat(quip, coloredName))
    else
        Utils.Print(sformat("%s (%d%% clicked): %s", coloredName, mfloor(clickRatio * 100), quip))
    end
end

function Tracker:Initialize()
    if not hooksInstalled then
        self:InstallHooks()
        hooksInstalled = true
    end
    -- Ensure blocklist table exists
    if not BoundToLearn.db.tracker.blocklist then
        BoundToLearn.db.tracker.blocklist = {}
    end
    if BoundToLearn.db.tracker.enabled then
        self:StartSession()
    end
end

function Tracker:InstallHooks()
    local function OnPreClick()
        if not isTracking then return end
        clickFlagSet = true
    end

    local function OnPostClick()
        if not isTracking then return end
        clickFlagSet = false
    end

    hooksecurefunc("UseAction", function(slot)
        if not isTracking or isPaused then return end

        local wasClick = clickFlagSet
        clickFlagSet = false

        -- Skip empty action bar slots
        if not HasAction(slot) then return end

        -- Filter non-combat actions
        if ShouldIgnoreAction(slot) then return end

        local texture = GetActionTexture(slot)
        local entry = {
            slot = slot,
            icon = texture,
            wasClick = wasClick,
            time = GetTime(),
        }

        if wasClick then
            sessionData.clicks = sessionData.clicks + 1
        else
            sessionData.keybinds = sessionData.keybinds + 1
        end

        -- Per-spell tracking and nudge check
        local spellStats = TrackSpellStats(slot, wasClick)
        if wasClick then
            CheckNudge(spellStats, slot)
        end

        tinsert(sessionData.actionLog, entry)
        if #sessionData.actionLog > ACTION_LOG_CAP then
            tremove(sessionData.actionLog, 1)
        end

        if ns.TrackerUI then
            ns.TrackerUI:OnActionRecorded(entry)
        end

        if ns.Game and ns.Game:IsRunning() and not wasClick then
            ns.Game:OnKeybindPressed(slot)
        end
    end)

    local buttonPrefixes = {
        "ActionButton",
        "MultiBarBottomLeftButton",
        "MultiBarBottomRightButton",
        "MultiBarRightButton",
        "MultiBarLeftButton",
        "MultiBar5Button",
        "MultiBar6Button",
        "MultiBar7Button",
    }
    for _, prefix in ipairs(buttonPrefixes) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn then
                btn:HookScript("PreClick", OnPreClick)
                btn:HookScript("PostClick", OnPostClick)
            end
        end
    end
end

function Tracker:StartSession()
    isTracking = true
    isPaused = false
    inEncounter = false
    inCombat = false
    BuildProfessionCache()
    wipe(sessionData.actionLog)
    wipe(spellClickStats)
    wipe(lastNudgeTime)
    wipe(segments)
    overallData.clicks = 0
    overallData.keybinds = 0
    sessionData.clicks = 0
    sessionData.keybinds = 0
    sessionData.startTime = GetTime()
    sessionData.label = "Current"
    sessionStartTime = sessionData.startTime

    self:RegisterEncounterEvents()

    if ns.TrackerUI then
        ns.TrackerUI:OnSessionStart()
    end
end

function Tracker:StopSession()
    if not isTracking then return end
    isTracking = false
    inEncounter = false
    inCombat = false

    FinalizeCurrentSegment()

    -- Record combined session to Stats
    local totalClicks = overallData.clicks
    local totalKeybinds = overallData.keybinds
    if (totalClicks + totalKeybinds) > 0 and ns.Stats then
        ns.Stats:RecordTrackerSession({
            startTime = sessionStartTime,
            clicks = totalClicks,
            keybinds = totalKeybinds,
        })
    end

    self:UnregisterEncounterEvents()

    if ns.TrackerUI then
        ns.TrackerUI:OnSessionStop()
    end
end

function Tracker:ResetSession()
    local wasTracking = isTracking
    if wasTracking then
        self:StopSession()
        self:StartSession()
    else
        wipe(sessionData.actionLog)
        wipe(spellClickStats)
        wipe(lastNudgeTime)
        wipe(segments)
        overallData.clicks = 0
        overallData.keybinds = 0
        sessionData.clicks = 0
        sessionData.keybinds = 0
        sessionData.startTime = 0
        sessionData.label = nil
    end
end

function Tracker:IsTracking()
    return isTracking
end

function Tracker:Pause()
    isPaused = true
    if ns.TrackerUI then ns.TrackerUI:OnPauseChanged(true) end
end

function Tracker:Resume()
    isPaused = false
    if ns.TrackerUI then ns.TrackerUI:OnPauseChanged(false) end
end

function Tracker:IsPaused()
    return isPaused
end

function Tracker:TogglePause()
    if isPaused then self:Resume() else self:Pause() end
end

function Tracker:GetSessionData()
    return sessionData
end

function Tracker:GetRatio()
    local total = sessionData.clicks + sessionData.keybinds
    if total == 0 then return 0 end
    return (sessionData.keybinds / total) * 100
end

function Tracker:GetTotal()
    return sessionData.clicks + sessionData.keybinds
end

function Tracker:GetSpellClickStats()
    return spellClickStats
end

-- Blocklist management (for /btl block <spellID> etc.)
function Tracker:AddToBlocklist(id)
    BoundToLearn.db.tracker.blocklist[id] = true
end

function Tracker:RemoveFromBlocklist(id)
    BoundToLearn.db.tracker.blocklist[id] = nil
end

-- Combat and encounter-based segment splitting
local combatFrame = CreateFrame("Frame")

local function GetTargetLabel()
    if UnitExists("target") then
        local name = UnitName("target")
        if name then return name end
    end
    return "Combat"
end

local function StartNewSegment(label)
    FinalizeCurrentSegment()
    wipe(sessionData.actionLog)
    sessionData.clicks = 0
    sessionData.keybinds = 0
    sessionData.startTime = GetTime()
    sessionData.label = label
    if ns.TrackerUI then ns.TrackerUI:OnSegmentChanged() end
end

function Tracker:RegisterEncounterEvents()
    combatFrame:RegisterEvent("ENCOUNTER_START")
    combatFrame:RegisterEvent("ENCOUNTER_END")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
end

function Tracker:UnregisterEncounterEvents()
    combatFrame:UnregisterAllEvents()
end

combatFrame:SetScript("OnEvent", function(self, event, ...)
    if not isTracking then return end

    if event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        if inEncounter then return end
        StartNewSegment(GetTargetLabel())

    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        if inEncounter then return end
        StartNewSegment("Current")

    elseif event == "ENCOUNTER_START" then
        local encounterID, encounterName = ...
        inEncounter = true
        -- Override the combat segment label with the boss name
        sessionData.label = encounterName or ("Encounter " .. (encounterID or "?"))
        if ns.TrackerUI then ns.TrackerUI:OnSegmentChanged() end

    elseif event == "ENCOUNTER_END" then
        local _, encounterName, _, _, success = ...
        inEncounter = false
        if success == 0 then
            sessionData.label = (sessionData.label or encounterName) .. " (Wipe)"
        end
        -- Don't start a new segment here; PLAYER_REGEN_ENABLED will handle it
        -- But if combat already ended (rare), finalize now
        if not inCombat then
            StartNewSegment("Current")
        end
    end
end)

-- Segment navigation API
function Tracker:GetSegments()
    return segments
end

function Tracker:GetSegmentCount()
    return #segments
end

function Tracker:GetSegment(index)
    return segments[index]
end

function Tracker:GetOverallData()
    return {
        clicks = overallData.clicks + sessionData.clicks,
        keybinds = overallData.keybinds + sessionData.keybinds,
    }
end

function Tracker:GetCurrentLabel()
    return sessionData.label or "Current"
end
