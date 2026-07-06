local ADDON_NAME, ns = ...

local StatsUI = {}
ns.StatsUI = StatsUI

local Utils      = ns.Utils
local sformat    = Utils.sformat
local mfloor     = Utils.mfloor
local mmin, mmax = Utils.mmin, Utils.mmax
local ipairs     = Utils.ipairs
local tinsert    = Utils.tinsert
local CreateFrame = Utils.CreateFrame
local PlayUISound = Utils.PlayUISound
local SOUND_TAB   = Utils.SOUND_TAB
local SOUND_CLICK = Utils.SOUND_CLICK

local UIParent = UIParent
local GameTooltip = GameTooltip

local statsFrame
local isInitialized = false
local activeTab = "tracker"

local TREND_BAR_COUNT = 20
local TREND_BAR_WIDTH = 8
local TREND_BAR_MAX_HEIGHT = 100
local TREND_BAR_SPACING = 2

local TIME_RANGES = {
    { label = "All",   seconds = nil },
    { label = "Today", seconds = 86400 },
    { label = "Week",  seconds = 604800 },
    { label = "Month", seconds = 2592000 },
}
local activeTimeRange = 1  -- index into TIME_RANGES

function StatsUI:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function StatsUI:CreateFrame()
    if statsFrame then return end

    statsFrame = CreateFrame("Frame", "BoundToLearnStatsFrame", UIParent)
    statsFrame:SetSize(450, 400)
    statsFrame:SetPoint("CENTER")
    statsFrame:SetFrameStrata("DIALOG")
    ns.Theme.StylePanel(statsFrame)
    statsFrame:EnableMouse(true)
    statsFrame:SetMovable(true)
    statsFrame:RegisterForDrag("LeftButton")
    statsFrame:SetClampedToScreen(true)
    statsFrame:SetScript("OnDragStart", statsFrame.StartMoving)
    statsFrame:SetScript("OnDragStop", statsFrame.StopMovingOrSizing)

    local close = ns.Theme.CreateCloseButton(statsFrame, function() statsFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local title = ns.Theme.CreateTitle(statsFrame, "BoundToLearn Stats", 16)
    title:SetPoint("TOP", 0, -12)

    -- Tab buttons
    self:CreateTabs()

    -- Content panels
    self:CreateTrackerPanel()
    self:CreateGamePanel()
    self:CreateQuizPanel()

    statsFrame:Hide()
end

function StatsUI:CreateTabs()
    local tabDefs = {
        { label = "Tracking", key = "tracker" },
        { label = "Game",     key = "game" },
        { label = "Quiz",     key = "quiz" },
    }
    statsFrame.tabs = {}
    for i, def in ipairs(tabDefs) do
        local tab = ns.Theme.CreateTab(statsFrame, def.label, "GameFontNormal")
        tab:SetSize(100, 24)
        tab:SetPoint("TOPLEFT", 15 + (i - 1) * 110, -35)
        tab.tabKey = def.key
        tab:SetScript("OnClick", function()
            PlayUISound(SOUND_TAB)
            self:SetTab(tab.tabKey)
        end)

        statsFrame.tabs[i] = tab
    end
end

function StatsUI:SetTab(tabKey)
    activeTab = tabKey
    if statsFrame.trackerPanel then
        statsFrame.trackerPanel:SetShown(tabKey == "tracker")
    end
    if statsFrame.gamePanel then
        statsFrame.gamePanel:SetShown(tabKey == "game")
    end
    if statsFrame.quizPanel then
        statsFrame.quizPanel:SetShown(tabKey == "quiz")
    end
    for _, tab in ipairs(statsFrame.tabs) do
        tab:SetActive(tab.tabKey == tabKey)
    end
    self:RefreshData()
end

local Y_AXIS_WIDTH = 30
local CHART_LEFT = Y_AXIS_WIDTH + 4

local function CreateTrendChart(panel, yOffset)
    -- Time range buttons
    local rangeFrame = CreateFrame("Frame", nil, panel)
    rangeFrame:SetHeight(16)
    rangeFrame:SetPoint("TOPLEFT", 0, yOffset)
    rangeFrame:SetPoint("TOPRIGHT", 0, yOffset)

    local trendLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trendLabel:SetPoint("TOPLEFT", rangeFrame, "TOPLEFT", 0, 0)
    trendLabel:SetText("Sessions")
    trendLabel:SetTextColor(ns.Theme.RGB(ns.Theme.C.GOLD))

    panel.rangeBtns = {}
    for i = #TIME_RANGES, 1, -1 do
        local r = TIME_RANGES[i]
        local btn = CreateFrame("Button", nil, rangeFrame)
        btn:SetSize(40, 14)
        btn:SetNormalFontObject("GameFontDisableSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(r.label)
        if i == #TIME_RANGES then
            btn:SetPoint("TOPRIGHT", rangeFrame, "TOPRIGHT", 0, 0)
        else
            btn:SetPoint("RIGHT", panel.rangeBtns[i + 1], "LEFT", -2, 0)
        end
        local idx = i
        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            activeTimeRange = idx
            StatsUI:RefreshData()
        end)
        panel.rangeBtns[i] = btn
    end

    local chartY = yOffset - 20

    -- Y axis labels
    local yLabels = { "100%", "50%", "0%" }
    local yPositions = { 0, 0.5, 1 }
    panel.yAxisLabels = {}
    for i, text in ipairs(yLabels) do
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        lbl:SetPoint("TOPRIGHT", panel, "TOPLEFT", Y_AXIS_WIDTH, chartY - yPositions[i] * TREND_BAR_MAX_HEIGHT + 4)
        lbl:SetText(text)
        lbl:SetJustifyH("RIGHT")
        panel.yAxisLabels[i] = lbl
    end

    -- Grid lines
    for i = 1, 3 do
        local line = panel:CreateTexture(nil, "BACKGROUND")
        line:SetHeight(1)
        line:SetPoint("TOPLEFT", panel, "TOPLEFT", CHART_LEFT, chartY - yPositions[i] * TREND_BAR_MAX_HEIGHT)
        line:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, chartY - yPositions[i] * TREND_BAR_MAX_HEIGHT)
        line:SetColorTexture(ns.Theme.RGB(ns.Theme.C.BORDER, 0.35))
    end

    -- Bar container (shifted right to make room for Y axis)
    local barContainer = CreateFrame("Frame", nil, panel)
    barContainer:SetSize(TREND_BAR_COUNT * (TREND_BAR_WIDTH + TREND_BAR_SPACING), TREND_BAR_MAX_HEIGHT)
    barContainer:SetPoint("TOPLEFT", CHART_LEFT, chartY)
    panel.barContainer = barContainer

    panel.trendBars = {}
    for i = 1, TREND_BAR_COUNT do
        local bar = barContainer:CreateTexture(nil, "ARTWORK")
        bar:SetWidth(TREND_BAR_WIDTH)
        bar:SetPoint("BOTTOMLEFT", barContainer, "BOTTOMLEFT",
            (i - 1) * (TREND_BAR_WIDTH + TREND_BAR_SPACING), 0)
        bar:SetHeight(1)
        bar:SetColorTexture(0.2, 0.8, 0.2, 0.8)
        bar:Hide()

        local hitArea = CreateFrame("Frame", nil, barContainer)
        hitArea:SetSize(TREND_BAR_WIDTH + TREND_BAR_SPACING, TREND_BAR_MAX_HEIGHT)
        hitArea:SetPoint("BOTTOMLEFT", barContainer, "BOTTOMLEFT",
            (i - 1) * (TREND_BAR_WIDTH + TREND_BAR_SPACING), 0)
        ns.Theme.DelayedTooltip(hitArea, function(self)
            if self.tipText then
                GameTooltip:SetText(self.tipText, 1, 1, 1, 1, true)
            end
        end)
        hitArea.tipText = nil

        panel.trendBars[i] = { bar = bar, hitArea = hitArea }
    end

    -- X axis: "Oldest" on left, "Latest" on right
    local xOldest = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    xOldest:SetPoint("TOPLEFT", barContainer, "BOTTOMLEFT", 0, -2)
    xOldest:SetText("Oldest")
    local xLatest = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    xLatest:SetPoint("TOPRIGHT", barContainer, "BOTTOMRIGHT", 0, -2)
    xLatest:SetText("Latest")
end

function StatsUI:CreateTrackerPanel()
    local panel = CreateFrame("Frame", nil, statsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("BOTTOMRIGHT", -15, 15)
    statsFrame.trackerPanel = panel

    local y = 0
    local function AddStat(label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 0, y)
        lbl:SetText(label)
        local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
        val:SetJustifyH("RIGHT")
        y = y - 22
        return val
    end

    panel.lifetimeRatio = AddStat("Lifetime Keybind Ratio")
    panel.lifetimeTotal = AddStat("Total Actions")
    panel.lifetimeKeybinds = AddStat("Total Keybinds")
    panel.lifetimeClicks = AddStat("Total Clicks")
    panel.bestRatio = AddStat("Best Session Ratio")

    y = y - 12
    CreateTrendChart(panel, y)
end

function StatsUI:CreateGamePanel()
    local panel = CreateFrame("Frame", nil, statsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("BOTTOMRIGHT", -15, 15)
    panel:Hide()
    statsFrame.gamePanel = panel

    local y = 0
    local function AddStat(label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 0, y)
        lbl:SetText(label)
        local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
        val:SetJustifyH("RIGHT")
        y = y - 22
        return val
    end

    panel.lifetimeAccuracy = AddStat("Lifetime Accuracy")
    panel.lifetimeNotes = AddStat("Total Notes")
    panel.lifetimeHits = AddStat("Total Hits")
    panel.highScore = AddStat("High Score")
    panel.bestCombo = AddStat("Longest Combo")
    panel.bestAccuracy = AddStat("Best Session Accuracy")

    y = y - 12
    CreateTrendChart(panel, y)
end

function StatsUI:CreateQuizPanel()
    local panel = CreateFrame("Frame", nil, statsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("BOTTOMRIGHT", -15, 15)
    panel:Hide()
    statsFrame.quizPanel = panel

    local y = 0
    local function AddStat(label)
        local lbl = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 0, y)
        lbl:SetText(label)
        local val = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, y)
        val:SetJustifyH("RIGHT")
        y = y - 22
        return val
    end

    panel.fastestTime = AddStat("Fastest Time")
    panel.quizzesCompleted = AddStat("Quizzes Completed")
    panel.abilitiesQuizzed = AddStat("Abilities Quizzed")

    y = y - 12
    local histLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    histLabel:SetPoint("TOPLEFT", 0, y)
    histLabel:SetText("Recent Sessions")
    histLabel:SetTextColor(ns.Theme.RGB(ns.Theme.C.GOLD))
    y = y - 20

    panel.historyRows = {}
    for i = 1, 10 do
        local row = CreateFrame("Frame", nil, panel)
        row:SetHeight(18)
        row:SetPoint("TOPLEFT", 0, y)
        row:SetPoint("TOPRIGHT", 0, y)

        local dateText = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        dateText:SetPoint("LEFT")
        row.dateText = dateText

        local detailText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        detailText:SetPoint("RIGHT")
        detailText:SetJustifyH("RIGHT")
        row.detailText = detailText

        row:Hide()
        panel.historyRows[i] = row
        y = y - 18
    end
end

function StatsUI:RefreshQuizData()
    local panel = statsFrame.quizPanel
    local db = BoundToLearn.db.stats
    local pb = db.personalBest

    if pb.fastestQuiz > 0 then
        local mins = mfloor(pb.fastestQuiz / 60)
        local secs = mfloor(pb.fastestQuiz % 60)
        local tenths = mfloor((pb.fastestQuiz * 10) % 10)
        if mins > 0 then
            panel.fastestTime:SetText(sformat("%d:%02d.%d", mins, secs, tenths))
        else
            panel.fastestTime:SetText(sformat("%d.%ds", secs, tenths))
        end
    else
        panel.fastestTime:SetText("--")
    end

    panel.quizzesCompleted:SetText(sformat("%d", db.lifetimeQuizzes))
    panel.abilitiesQuizzed:SetText(sformat("%d", db.lifetimeQuizAbilities))

    local sessions = ns.Stats:GetRecentSessions("quiz", 10)
    for i, row in ipairs(panel.historyRows) do
        local session = sessions[i]
        if session then
            row.dateText:SetText(date("%m/%d %H:%M", session.timestamp))
            local mins = mfloor(session.elapsed / 60)
            local secs = mfloor(session.elapsed % 60)
            local tenths = mfloor((session.elapsed * 10) % 10)
            local timeStr
            if mins > 0 then
                timeStr = sformat("%d:%02d.%d", mins, secs, tenths)
            else
                timeStr = sformat("%d.%ds", secs, tenths)
            end
            local roundStr = session.rounds == 1 and "perfect" or sformat("%d rounds", session.rounds)
            row.detailText:SetText(sformat("%s  |cFF888888(%s, %d abilities)|r", timeStr, roundStr, session.totalAbilities))
            row:Show()
        else
            row:Hide()
        end
    end
end

local function GetMinTimestamp()
    local range = TIME_RANGES[activeTimeRange]
    if not range.seconds then return nil end
    return time() - range.seconds
end

local function UpdateRangeButtons(panel)
    if not panel.rangeBtns then return end
    for i, btn in ipairs(panel.rangeBtns) do
        if i == activeTimeRange then
            btn:SetNormalFontObject("GameFontNormalSmall")
        else
            btn:SetNormalFontObject("GameFontDisableSmall")
        end
    end
end

local function FormatTimestamp(ts)
    return date("%m/%d %H:%M", ts)
end

function StatsUI:RefreshData()
    if not statsFrame or not statsFrame:IsShown() then return end

    if activeTab == "tracker" then
        self:RefreshTrackerData()
    elseif activeTab == "game" then
        self:RefreshGameData()
    elseif activeTab == "quiz" then
        self:RefreshQuizData()
    end
end

function StatsUI:RefreshTrackerData()
    local panel = statsFrame.trackerPanel
    local db = BoundToLearn.db.stats
    local total = db.lifetimeClicks + db.lifetimeKeybinds

    panel.lifetimeRatio:SetText(sformat("%.1f%%", ns.Stats:GetLifetimeTrackerRatio()))
    panel.lifetimeTotal:SetText(sformat("%d", total))
    panel.lifetimeKeybinds:SetText(sformat("%d", db.lifetimeKeybinds))
    panel.lifetimeClicks:SetText(sformat("%d", db.lifetimeClicks))
    panel.bestRatio:SetText(sformat("%.1f%%", db.personalBest.bestKeybindRatio))

    UpdateRangeButtons(panel)

    local minTs = GetMinTimestamp()
    local sessions = ns.Stats:GetFilteredSessions("tracker", TREND_BAR_COUNT, minTs)
    for i = 1, TREND_BAR_COUNT do
        local entry = panel.trendBars[i]
        local sessionIdx = TREND_BAR_COUNT - i + 1
        local session = sessions[sessionIdx]
        if session then
            local height = mmax(2, (session.ratio / 100) * TREND_BAR_MAX_HEIGHT)
            entry.bar:SetHeight(height)
            local r, g, b = self:GetRatioColor(session.ratio)
            entry.bar:SetColorTexture(r, g, b, 0.8)
            entry.bar:Show()
            entry.hitArea.tipText = sformat(
                "%s\nRatio: %.1f%%\nKeybinds: %d | Clicks: %d\nDuration: %d:%02d",
                FormatTimestamp(session.timestamp),
                session.ratio, session.keybinds, session.clicks,
                mfloor(session.duration / 60), session.duration % 60)
        else
            entry.bar:Hide()
            entry.hitArea.tipText = nil
        end
    end
end

function StatsUI:RefreshGameData()
    local panel = statsFrame.gamePanel
    local db = BoundToLearn.db.stats
    local pb = db.personalBest

    panel.lifetimeAccuracy:SetText(sformat("%.1f%%", ns.Stats:GetLifetimeGameAccuracy()))
    panel.lifetimeNotes:SetText(sformat("%d", db.lifetimeGameNotes))
    panel.lifetimeHits:SetText(sformat("%d", db.lifetimeGameHits))
    panel.highScore:SetText(sformat("%d", pb.highestScore))
    panel.bestCombo:SetText(sformat("%d", pb.longestCombo))
    panel.bestAccuracy:SetText(sformat("%.1f%%", pb.bestAccuracy))

    UpdateRangeButtons(panel)

    local minTs = GetMinTimestamp()
    local sessions = ns.Stats:GetFilteredSessions("game", TREND_BAR_COUNT, minTs)
    for i = 1, TREND_BAR_COUNT do
        local entry = panel.trendBars[i]
        local sessionIdx = TREND_BAR_COUNT - i + 1
        local session = sessions[sessionIdx]
        if session then
            local height = mmax(2, (session.accuracy / 100) * TREND_BAR_MAX_HEIGHT)
            entry.bar:SetHeight(height)
            local r, g, b = self:GetRatioColor(session.accuracy)
            entry.bar:SetColorTexture(r, g, b, 0.8)
            entry.bar:Show()
            entry.hitArea.tipText = sformat(
                "%s\nScore: %d\nAccuracy: %.1f%%\nCombo: %d\nP:%d G:%d OK:%d M:%d",
                FormatTimestamp(session.timestamp),
                session.score, session.accuracy, session.combo,
                session.perfect, session.great, session.good, session.miss)
        else
            entry.bar:Hide()
            entry.hitArea.tipText = nil
        end
    end
end

function StatsUI:GetRatioColor(ratio)
    if ratio >= 90 then return 0.2, 0.8, 0.2 end
    if ratio >= 70 then return 0.8, 0.8, 0.2 end
    return 0.8, 0.2, 0.2
end

function StatsUI:Toggle()
    if not statsFrame then
        self:CreateFrame()
    end
    if statsFrame:IsShown() then
        statsFrame:Hide()
    else
        statsFrame:Show()
        self:SetTab(activeTab)
    end
end

function StatsUI:Show()
    if not statsFrame then self:CreateFrame() end
    self:SetTab(activeTab)
    statsFrame:Show()
end

function StatsUI:Hide()
    if statsFrame then statsFrame:Hide() end
end
