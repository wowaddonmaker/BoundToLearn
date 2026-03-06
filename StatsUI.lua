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

local UIParent = UIParent
local GameTooltip = GameTooltip

local statsFrame
local isInitialized = false
local activeTab = "tracker"

local PANEL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local TREND_BAR_COUNT = 20
local TREND_BAR_WIDTH = 8
local TREND_BAR_MAX_HEIGHT = 100
local TREND_BAR_SPACING = 2

function StatsUI:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function StatsUI:CreateFrame()
    if statsFrame then return end

    statsFrame = CreateFrame("Frame", "BoundToLearnStatsFrame", UIParent, "BackdropTemplate")
    statsFrame:SetSize(450, 400)
    statsFrame:SetPoint("CENTER")
    statsFrame:SetFrameStrata("DIALOG")
    statsFrame:SetBackdrop(PANEL_BACKDROP)
    statsFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    statsFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    statsFrame:EnableMouse(true)
    statsFrame:SetMovable(true)
    statsFrame:RegisterForDrag("LeftButton")
    statsFrame:SetClampedToScreen(true)
    statsFrame:SetScript("OnDragStart", statsFrame.StartMoving)
    statsFrame:SetScript("OnDragStop", statsFrame.StopMovingOrSizing)

    local close = CreateFrame("Button", nil, statsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = statsFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFBoundToLearn Stats|r")

    -- Tab buttons
    self:CreateTabs()

    -- Content panels
    self:CreateTrackerPanel()
    self:CreateGamePanel()

    statsFrame:Hide()
end

function StatsUI:CreateTabs()
    local tabs = { "Tracking", "Game" }
    statsFrame.tabs = {}
    for i, label in ipairs(tabs) do
        local tab = CreateFrame("Button", nil, statsFrame)
        tab:SetSize(100, 24)
        tab:SetPoint("TOPLEFT", 15 + (i - 1) * 110, -35)
        tab:SetNormalFontObject("GameFontNormal")
        tab:SetHighlightFontObject("GameFontHighlight")
        tab:SetText(label)
        tab.tabKey = i == 1 and "tracker" or "game"
        tab:SetScript("OnClick", function()
            self:SetTab(tab.tabKey)
        end)

        -- Underline for active tab
        local underline = tab:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 0, -2)
        underline:SetPoint("BOTTOMRIGHT", 0, -2)
        underline:SetHeight(2)
        underline:SetColorTexture(0.33, 0.8, 1, 1)
        underline:Hide()
        tab.underline = underline

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
    for _, tab in ipairs(statsFrame.tabs) do
        tab.underline:SetShown(tab.tabKey == tabKey)
    end
    self:RefreshData()
end

function StatsUI:CreateTrackerPanel()
    local panel = CreateFrame("Frame", nil, statsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("BOTTOMRIGHT", -15, 15)
    statsFrame.trackerPanel = panel

    -- Lifetime stats
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

    y = y - 15

    -- Trend section header
    local trendLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trendLabel:SetPoint("TOPLEFT", 0, y)
    trendLabel:SetText("Recent Sessions")
    trendLabel:SetTextColor(0.33, 0.8, 1)
    y = y - 20

    -- Trend bars: use a container anchored within the panel, bars grow upward
    local barContainer = CreateFrame("Frame", nil, panel)
    barContainer:SetSize(TREND_BAR_COUNT * (TREND_BAR_WIDTH + TREND_BAR_SPACING), TREND_BAR_MAX_HEIGHT)
    barContainer:SetPoint("TOPLEFT", 0, y)
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

        -- Tooltip region
        local hitArea = CreateFrame("Frame", nil, barContainer)
        hitArea:SetSize(TREND_BAR_WIDTH + TREND_BAR_SPACING, TREND_BAR_MAX_HEIGHT)
        hitArea:SetPoint("BOTTOMLEFT", barContainer, "BOTTOMLEFT",
            (i - 1) * (TREND_BAR_WIDTH + TREND_BAR_SPACING), 0)
        hitArea.barIndex = i
        hitArea:SetScript("OnEnter", function(self)
            if self.tipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tipText, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        hitArea:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        hitArea.tipText = nil

        panel.trendBars[i] = { bar = bar, hitArea = hitArea }
    end
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

    y = y - 15

    local trendLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    trendLabel:SetPoint("TOPLEFT", 0, y)
    trendLabel:SetText("Recent Sessions")
    trendLabel:SetTextColor(0.33, 0.8, 1)
    y = y - 20

    local barContainer = CreateFrame("Frame", nil, panel)
    barContainer:SetSize(TREND_BAR_COUNT * (TREND_BAR_WIDTH + TREND_BAR_SPACING), TREND_BAR_MAX_HEIGHT)
    barContainer:SetPoint("TOPLEFT", 0, y)
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
        hitArea:SetScript("OnEnter", function(self)
            if self.tipText then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(self.tipText, 1, 1, 1, 1, true)
                GameTooltip:Show()
            end
        end)
        hitArea:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)
        hitArea.tipText = nil

        panel.trendBars[i] = { bar = bar, hitArea = hitArea }
    end
end

function StatsUI:RefreshData()
    if not statsFrame or not statsFrame:IsShown() then return end

    if activeTab == "tracker" then
        self:RefreshTrackerData()
    else
        self:RefreshGameData()
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

    -- Trend bars
    local sessions = ns.Stats:GetRecentSessions("tracker", TREND_BAR_COUNT)
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
                "Ratio: %.1f%%\nKeybinds: %d | Clicks: %d\nDuration: %d:%02d",
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

    local sessions = ns.Stats:GetRecentSessions("game", TREND_BAR_COUNT)
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
                "Score: %d\nAccuracy: %.1f%%\nCombo: %d\nP:%d G:%d OK:%d M:%d",
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
        self:SetTab(activeTab)
        statsFrame:Show()
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
