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
local pairs    = Utils.pairs
local ipairs   = Utils.ipairs

local hooksecurefunc = hooksecurefunc
local GetActionTexture = GetActionTexture
local GetActionInfo = GetActionInfo
local HasAction = HasAction
local InCombatLockdown = InCombatLockdown
local C_Spell = C_Spell
local C_MountJournal = C_MountJournal
local C_ToyBox = C_ToyBox

local isTracking = false
local hooksInstalled = false
local clickFlagSet = false

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
    [281404] = true, [344587] = true, [344597] = true, [395277] = true, [395289] = true,
    [446540] = true, [446534] = true,
    -- Mage portals
    [10059] = true, [11416] = true, [11417] = true, [11418] = true, [11419] = true, [11420] = true,
    [32266] = true, [32267] = true, [33691] = true, [35717] = true, [49360] = true, [49361] = true,
    [53142] = true, [88345] = true, [88346] = true, [132620] = true, [132626] = true,
    [176244] = true, [176246] = true, [224870] = true, [224872] = true, [281400] = true,
    [281402] = true, [344597] = true, [395289] = true,
    [446534] = true, [446540] = true,
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
local NUDGE_CLICK_THRESHOLD = 10
local NUDGE_RATIO_THRESHOLD = 0.6
local NUDGE_COOLDOWN = 300
local lastNudgeTime = {}

local sessionData = {
    startTime = 0,
    clicks = 0,
    keybinds = 0,
    actionLog = {},
}

-- Cache for toy detection so we don't call C_ToyBox every action
local toyCache = {}

local function IsToyItem(itemID)
    if toyCache[itemID] ~= nil then return toyCache[itemID] end
    local isToy = C_ToyBox.GetToyInfo(itemID) ~= nil
    toyCache[itemID] = isToy
    return isToy
end

local function ShouldIgnoreAction(slot)
    local actionType, id = GetActionInfo(slot)
    local filter = BoundToLearn.db.tracker.filter
    local blocklist = BoundToLearn.db.tracker.blocklist

    -- User blocklist always applies
    if id and blocklist and blocklist[id] then return true end

    -- Flyout menus and companion (battle pet) summons are always filtered
    if actionType == "companion" or actionType == "flyout" then return true end

    -- Mounts
    if actionType == "mount" then return filter.mounts end
    if actionType == "summonmount" then return filter.mounts end

    if actionType == "spell" and id then
        if filter.hearthstones and HEARTHSTONE_SPELLS[id] then return true end
        if filter.teleports and TELEPORT_SPELLS[id] then return true end
    end

    -- Items: check for toys and hearthstone items
    if actionType == "item" and id then
        if filter.toys and IsToyItem(id) then return true end
    end

    return false
end

local function GetActionIdentifier(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType and id then
        return actionType .. ":" .. id
    end
    return "slot:" .. slot
end

local function GetActionName(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and id then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name or ("Spell " .. id)
    elseif actionType == "item" and id then
        local name = C_Item.GetItemInfo(id)
        return name or ("Item " .. id)
    elseif actionType == "macro" then
        local name = GetMacroInfo(id)
        return name or ("Macro " .. id)
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
    "Your mouse button called. It wants a vacation.",
    "That keybind is feeling lonely.",
    "Your mouse is filing a workers' comp claim.",
    "Fun fact: keybinds are faster AND your mouse will thank you.",
    "Click, click, click... your keyboard is right there, you know.",
    "Your mouse: 'Why must I suffer?'",
    "Legend has it there's a keybind for that.",
    "Click detected. Keyboard gathering dust.",
    "Your mouse is starting a union.",
    "Hot take: keys on a keyboard can also be pressed.",
    "Your mouse is writing a memoir: 'A Life of Clicks.'",
    "Pro tip: keybinds make you look cooler. Scientifically proven.",
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

local function CheckNudge(stats, slot)
    local total = stats.clicks + stats.keybinds
    if total < NUDGE_CLICK_THRESHOLD then return end

    local clickRatio = stats.clicks / total
    if clickRatio < NUDGE_RATIO_THRESHOLD then return end

    local key = GetActionIdentifier(slot)
    local now = GetTime()
    if lastNudgeTime[key] and (now - lastNudgeTime[key]) < NUDGE_COOLDOWN then return end
    lastNudgeTime[key] = now

    Utils.Print(sformat("|cFFFFFF00%s|r (%d%% clicked): %s",
        stats.name, mfloor(clickRatio * 100), GetRandomQuip()))
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
        if not isTracking then return end

        local wasClick = clickFlagSet
        clickFlagSet = false

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
    wipe(sessionData.actionLog)
    wipe(spellClickStats)
    wipe(lastNudgeTime)
    sessionData.clicks = 0
    sessionData.keybinds = 0
    sessionData.startTime = GetTime()

    if ns.TrackerUI then
        ns.TrackerUI:OnSessionStart()
    end
end

function Tracker:StopSession()
    if not isTracking then return end
    isTracking = false

    local total = sessionData.clicks + sessionData.keybinds
    if total > 0 and ns.Stats then
        ns.Stats:RecordTrackerSession(sessionData)
    end

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
        sessionData.clicks = 0
        sessionData.keybinds = 0
        sessionData.startTime = 0
    end
end

function Tracker:IsTracking()
    return isTracking
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
