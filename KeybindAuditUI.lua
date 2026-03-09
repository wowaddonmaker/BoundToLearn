local ADDON_NAME, ns = ...

local KeybindAuditUI = {}
ns.KeybindAuditUI = KeybindAuditUI

local Utils      = ns.Utils
local sformat    = Utils.sformat
local mfloor     = Utils.mfloor
local mmin, mmax = Utils.mmin, Utils.mmax
local ipairs     = Utils.ipairs
local pairs      = Utils.pairs
local tinsert    = Utils.tinsert
local wipe       = Utils.wipe
local CreateFrame = Utils.CreateFrame
local PlayUISound = Utils.PlayUISound
local SOUND_CLICK = Utils.SOUND_CLICK

local UIParent = UIParent

local PANEL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local BAR_FRAME_MAP = {
    { key = "main",        label = "Action Bar 1",  prefix = "ActionButton",               barFrame = "MainMenuBar" },
    { key = "bottomLeft",  label = "Action Bar 2",  prefix = "MultiBarBottomLeftButton",   barFrame = "MultiBarBottomLeft" },
    { key = "bottomRight", label = "Action Bar 3",  prefix = "MultiBarBottomRightButton",  barFrame = "MultiBarBottomRight" },
    { key = "right",       label = "Action Bar 4",  prefix = "MultiBarRightButton",        barFrame = "MultiBarRight" },
    { key = "left",        label = "Action Bar 5",  prefix = "MultiBarLeftButton",         barFrame = "MultiBarLeft" },
    { key = "bar6",        label = "Action Bar 6",  prefix = "MultiBar5Button",            barFrame = "MultiBar5" },
    { key = "bar7",        label = "Action Bar 7",  prefix = "MultiBar6Button",            barFrame = "MultiBar6" },
    { key = "bar8",        label = "Action Bar 8",  prefix = "MultiBar7Button",            barFrame = "MultiBar7" },
}

local ISSUE_ROW_HEIGHT = 36
local SEVERITY_COLORS = {
    high   = { 0.8, 0.2, 0.2 },
    medium = { 0.8, 0.6, 0.2 },
    low    = { 0.6, 0.6, 0.3 },
}

local auditFrame, dimmer
local setupPage, resultsPage, methodologyPage, categoryDetailPage
local barOverlays = {}
local barToggles = {}
local lastResults

local gradeText, scoreText, summaryText
local categoryBars = {}
local barSummaryLabels = {}
local issueRows = {}
local issueContainer, issueScrollChild

local function GetBarColor(score)
    if score >= 90 then return 0.2, 0.8, 0.2 end
    if score >= 70 then return 0.8, 0.8, 0.2 end
    if score >= 50 then return 0.8, 0.6, 0.2 end
    return 0.6, 0.3, 0.3
end

local function GetDb()
    return BoundToLearn.db.audit
end

local function LoadBarToggles()
    local db = GetDb()
    if not db.barsInitialized then
        -- First use: default to only bars whose first button is visible
        for _, barDef in ipairs(BAR_FRAME_MAP) do
            local btn1 = _G[barDef.prefix .. "1"]
            db.bars[barDef.key] = btn1 and btn1:IsVisible() or false
        end
        db.barsInitialized = true
    end
    for _, barDef in ipairs(BAR_FRAME_MAP) do
        barToggles[barDef.key] = db.bars[barDef.key]
    end
end

local function SaveBarToggles()
    local db = GetDb()
    for key, val in pairs(barToggles) do
        db.bars[key] = val
    end
end

local function UpdateBarOverlay(overlay, included)
    if included then
        overlay.bg:SetColorTexture(0.1, 0.6, 0.1, 0.25)
        overlay.border:SetColorTexture(0.2, 0.8, 0.2, 0.8)
        overlay.label:SetTextColor(0.3, 1.0, 0.3)
        overlay.status:SetText("Included")
        overlay.status:SetTextColor(0.3, 0.9, 0.3)
    else
        overlay.bg:SetColorTexture(0.4, 0.1, 0.1, 0.25)
        overlay.border:SetColorTexture(0.6, 0.2, 0.2, 0.6)
        overlay.label:SetTextColor(0.8, 0.4, 0.4)
        overlay.status:SetText("Excluded")
        overlay.status:SetTextColor(0.8, 0.4, 0.4)
    end
end

local function FindLastVisibleButton(prefix)
    for i = 12, 1, -1 do
        local btn = _G[prefix .. i]
        if btn and btn:IsVisible() then return btn end
    end
    return nil
end

local function PositionOverlay(overlay, barDef)
    overlay:ClearAllPoints()
    local btn1 = _G[barDef.prefix .. "1"]
    local lastBtn = FindLastVisibleButton(barDef.prefix)
    if btn1 and lastBtn then
        overlay:SetPoint("TOPLEFT", btn1, "TOPLEFT", -6, 6)
        overlay:SetPoint("BOTTOMRIGHT", lastBtn, "BOTTOMRIGHT", 6, -6)
    end
end

local function CreateBarOverlay(barDef)
    local btn1 = _G[barDef.prefix .. "1"]
    if not btn1 then return nil end

    local overlay = CreateFrame("Button", nil, UIParent)
    overlay:SetFrameStrata("FULLSCREEN_DIALOG")
    overlay:SetFrameLevel(10)

    local bg = overlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0.1, 0.6, 0.1, 0.25)
    overlay.bg = bg

    local border = overlay:CreateTexture(nil, "BORDER")
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetPoint("TOPRIGHT", 0, 0)
    border:SetHeight(2)
    border:SetColorTexture(0.2, 0.8, 0.2, 0.8)
    overlay.border = border

    local label = overlay:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    label:SetPoint("CENTER", 0, 8)
    label:SetText(barDef.label)
    overlay.label = label

    local hint = overlay:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetPoint("CENTER", 0, -8)
    hint:SetText("Click to toggle")
    hint:SetTextColor(0.7, 0.7, 0.7)

    local status = overlay:CreateFontString(nil, "OVERLAY")
    status:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    status:SetPoint("CENTER", 0, -20)
    overlay.status = status

    overlay.barKey = barDef.key
    overlay:SetScript("OnClick", function(self)
        PlayUISound(SOUND_CLICK)
        barToggles[self.barKey] = not barToggles[self.barKey]
        UpdateBarOverlay(self, barToggles[self.barKey])
        SaveBarToggles()
        -- Sync setup page checkboxes
        if setupPage and setupPage.barCheckboxes then
            local cb = setupPage.barCheckboxes[self.barKey]
            if cb then cb:SetChecked(barToggles[self.barKey]) end
        end
    end)

    overlay:Hide()
    return overlay
end

local function CreateScoreBar(parent, label, yOffset, categoryIndex)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(240, 18)
    row:SetPoint("TOPLEFT", 20, yOffset)

    local highlight = row:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAllPoints()
    highlight:SetColorTexture(1, 1, 1, 0.08)

    local lbl = row:CreateFontString(nil, "OVERLAY")
    lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    lbl:SetPoint("LEFT", 0, 0)
    lbl:SetWidth(95)
    lbl:SetJustifyH("LEFT")
    lbl:SetTextColor(0.8, 0.8, 0.8)
    lbl:SetText(label)
    row.label = lbl

    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("LEFT", 100, 0)
    bg:SetSize(110, 12)
    bg:SetColorTexture(0.15, 0.15, 0.15, 1)
    row.bg = bg

    local fill = row:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", 100, 0)
    fill:SetSize(110, 12)
    fill:SetColorTexture(0.2, 0.8, 0.2, 1)
    row.fill = fill

    local val = row:CreateFontString(nil, "OVERLAY")
    val:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    val:SetPoint("LEFT", 218, 0)
    val:SetTextColor(0.9, 0.9, 0.9)
    row.value = val

    row:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        KeybindAuditUI:ShowCategoryDetail(categoryIndex)
    end)

    return row
end

local function SetScoreBar(bar, score)
    local clamped = mmax(0, mmin(100, score))
    bar.fill:SetWidth(mmax(1, 110 * clamped / 100))
    local r, g, b = GetBarColor(score)
    bar.fill:SetColorTexture(r, g, b, 1)
    bar.value:SetText(tostring(mfloor(score)))
end

local function CreateIssueRow(parent, index)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(250, ISSUE_ROW_HEIGHT)
    row:SetPoint("TOPLEFT", 0, -(index - 1) * ISSUE_ROW_HEIGHT)

    local strip = row:CreateTexture(nil, "ARTWORK")
    strip:SetSize(3, ISSUE_ROW_HEIGHT - 4)
    strip:SetPoint("LEFT", 0, 0)
    strip:SetColorTexture(0.8, 0.6, 0.2, 1)
    row.strip = strip

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(20, 20)
    icon:SetPoint("LEFT", 8, 0)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    row.icon = icon

    local text = row:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    text:SetPoint("TOPLEFT", 34, -3)
    text:SetWidth(210)
    text:SetJustifyH("LEFT")
    text:SetTextColor(0.9, 0.9, 0.9)
    row.text = text

    local detail = row:CreateFontString(nil, "OVERLAY")
    detail:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    detail:SetPoint("TOPLEFT", 34, -17)
    detail:SetWidth(210)
    detail:SetJustifyH("LEFT")
    detail:SetTextColor(0.6, 0.6, 0.6)
    row.detail = detail

    row:Hide()
    return row
end

local function CreateCheckbox(parent, label, yOffset, onClick)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 20, yOffset)
    cb:SetSize(26, 26)

    local text = cb:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    text:SetPoint("LEFT", cb, "RIGHT", 4, 0)
    text:SetTextColor(0.8, 0.8, 0.8)
    text:SetText(label)
    cb.label = text

    cb:SetScript("OnClick", function(self)
        PlayUISound(SOUND_CLICK)
        if onClick then onClick(self:GetChecked()) end
    end)

    return cb
end

function KeybindAuditUI:CreateFrame()
    if auditFrame then return end

    -- Dimmer
    dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetAllPoints(UIParent)
    dimmer:SetFrameStrata("FULLSCREEN")
    dimmer:EnableMouse(false)
    local dimBg = dimmer:CreateTexture(nil, "BACKGROUND")
    dimBg:SetAllPoints()
    dimBg:SetColorTexture(0, 0, 0, 0.6)
    dimmer:Hide()

    -- Bar overlays
    for _, barDef in ipairs(BAR_FRAME_MAP) do
        barOverlays[barDef.key] = CreateBarOverlay(barDef)
    end

    -- Main frame
    auditFrame = CreateFrame("Frame", "BoundToLearnAuditFrame", UIParent, "BackdropTemplate")
    auditFrame:SetSize(580, 480)
    auditFrame:SetPoint("CENTER")
    auditFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    auditFrame:SetFrameLevel(20)
    auditFrame:SetBackdrop(PANEL_BACKDROP)
    auditFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    auditFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    auditFrame:EnableMouse(true)
    auditFrame:SetMovable(true)
    auditFrame:RegisterForDrag("LeftButton")
    auditFrame:SetClampedToScreen(true)
    auditFrame:SetScript("OnDragStart", auditFrame.StartMoving)
    auditFrame:SetScript("OnDragStop", auditFrame.StopMovingOrSizing)
    auditFrame:SetScript("OnHide", function()
        self:HideBarOverlays()
    end)
    tinsert(UISpecialFrames, "BoundToLearnAuditFrame")

    local close = CreateFrame("Button", nil, auditFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Title
    local title = auditFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFKeybind Audit|r")

    local accent = auditFrame:CreateTexture(nil, "ARTWORK")
    accent:SetSize(550, 2)
    accent:SetPoint("TOP", 0, -34)
    accent:SetColorTexture(0.33, 0.80, 1.0, 0.6)

    -- Methodology tab on the accent line
    local methTab = CreateFrame("Button", nil, auditFrame)
    methTab:SetSize(80, 16)
    methTab:SetPoint("TOPRIGHT", accent, "BOTTOMRIGHT", 0, 0)
    local methTabBg = methTab:CreateTexture(nil, "BACKGROUND")
    methTabBg:SetAllPoints()
    methTabBg:SetColorTexture(0.33, 0.80, 1.0, 0.15)
    local methTabText = methTab:CreateFontString(nil, "OVERLAY")
    methTabText:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    methTabText:SetPoint("CENTER", 0, 0)
    methTabText:SetText("Methodology")
    methTabText:SetTextColor(0.33, 0.80, 1.0)
    methTab:SetScript("OnEnter", function(self)
        methTabBg:SetColorTexture(0.33, 0.80, 1.0, 0.3)
    end)
    methTab:SetScript("OnLeave", function(self)
        methTabBg:SetColorTexture(0.33, 0.80, 1.0, 0.15)
    end)
    methTab:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        KeybindAuditUI:ToggleMethodology()
    end)
    auditFrame.methTab = methTab

    self:CreateSetupPage()
    self:CreateResultsPage()
    self:CreateMethodologyPage()
    self:CreateCategoryDetailPage()

    resultsPage:Hide()
    methodologyPage:Hide()
    categoryDetailPage:Hide()
    auditFrame:Hide()
end

function KeybindAuditUI:CreateSetupPage()
    setupPage = CreateFrame("Frame", nil, auditFrame)
    setupPage:SetAllPoints()

    local desc = setupPage:CreateFontString(nil, "OVERLAY")
    desc:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    desc:SetPoint("TOPLEFT", 25, -56)
    desc:SetWidth(530)
    desc:SetJustifyH("LEFT")
    desc:SetTextColor(0.6, 0.6, 0.6)
    desc:SetText("Select which bars to include by clicking them on screen, or use the checkboxes below.")

    -- Bar checkboxes (two columns of 4)
    local barCheckY = -82
    local barCheckboxes = {}
    local BARS_PER_COL = 4
    for i, barDef in ipairs(BAR_FRAME_MAP) do
        local col = (i - 1) < BARS_PER_COL and 0 or 1
        local row = (i - 1) % BARS_PER_COL
        local cb = CreateCheckbox(setupPage, barDef.label, barCheckY - row * 28, function(checked)
            barToggles[barDef.key] = checked
            SaveBarToggles()
            local overlay = barOverlays[barDef.key]
            if overlay and overlay:IsShown() then
                UpdateBarOverlay(overlay, checked)
            end
        end)
        if col == 1 then
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", 160, barCheckY - row * 28)
        end
        barCheckboxes[barDef.key] = cb
    end
    setupPage.barCheckboxes = barCheckboxes

    -- Right column options
    local optX = 330

    local mmoMouseCb = CreateFrame("CheckButton", nil, setupPage, "UICheckButtonTemplate")
    mmoMouseCb:SetPoint("TOPLEFT", optX, -82)
    mmoMouseCb:SetSize(26, 26)
    local mmoLabel = mmoMouseCb:CreateFontString(nil, "OVERLAY")
    mmoLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    mmoLabel:SetPoint("LEFT", mmoMouseCb, "RIGHT", 4, 0)
    mmoLabel:SetTextColor(0.8, 0.8, 0.8)
    mmoLabel:SetText("I use an MMO mouse (12-button)")
    mmoMouseCb:SetScript("OnClick", function(self)
        PlayUISound(SOUND_CLICK)
        GetDb().mmoMouse = self:GetChecked()
    end)
    setupPage.mmoMouseCb = mmoMouseCb

    local mmoHint = setupPage:CreateFontString(nil, "OVERLAY")
    mmoHint:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    mmoHint:SetPoint("TOPLEFT", optX + 30, -108)
    mmoHint:SetWidth(200)
    mmoHint:SetJustifyH("LEFT")
    mmoHint:SetTextColor(0.55, 0.55, 0.55)
    mmoHint:SetText("Number keys won't be penalized as distant since they're on your thumb.")

    local skipCombatCb = CreateFrame("CheckButton", nil, setupPage, "UICheckButtonTemplate")
    skipCombatCb:SetPoint("TOPLEFT", optX, -138)
    skipCombatCb:SetSize(26, 26)
    local skipCombatLabel = skipCombatCb:CreateFontString(nil, "OVERLAY")
    skipCombatLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    skipCombatLabel:SetPoint("LEFT", skipCombatCb, "RIGHT", 4, 0)
    skipCombatLabel:SetTextColor(0.8, 0.8, 0.8)
    skipCombatLabel:SetText("Skip non-combat macros")
    skipCombatCb:SetScript("OnClick", function(self)
        PlayUISound(SOUND_CLICK)
        GetDb().skipNonCombat = self:GetChecked()
    end)
    setupPage.skipCombatCb = skipCombatCb

    local skipCombatHint = setupPage:CreateFontString(nil, "OVERLAY")
    skipCombatHint:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    skipCombatHint:SetPoint("TOPLEFT", optX + 30, -164)
    skipCombatHint:SetWidth(200)
    skipCombatHint:SetJustifyH("LEFT")
    skipCombatHint:SetTextColor(0.55, 0.55, 0.55)
    skipCombatHint:SetText("Ignores macros without /cast, /use, or other combat commands.")

    local skipBarsCb = CreateFrame("CheckButton", nil, setupPage, "UICheckButtonTemplate")
    skipBarsCb:SetPoint("TOPLEFT", optX, -198)
    skipBarsCb:SetSize(26, 26)
    local skipBarsLabel = skipBarsCb:CreateFontString(nil, "OVERLAY")
    skipBarsLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    skipBarsLabel:SetPoint("LEFT", skipBarsCb, "RIGHT", 4, 0)
    skipBarsLabel:SetTextColor(0.8, 0.8, 0.8)
    skipBarsLabel:SetText("Skip this setup next time")
    skipBarsCb:SetScript("OnClick", function(self)
        PlayUISound(SOUND_CLICK)
        GetDb().skipBarSelection = self:GetChecked()
    end)
    setupPage.skipBarsCb = skipBarsCb

    local skipBarsHint = setupPage:CreateFontString(nil, "OVERLAY")
    skipBarsHint:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    skipBarsHint:SetPoint("TOPLEFT", optX + 30, -224)
    skipBarsHint:SetWidth(200)
    skipBarsHint:SetJustifyH("LEFT")
    skipBarsHint:SetTextColor(0.55, 0.55, 0.55)
    skipBarsHint:SetText("Next time you open the audit, click Settings (bottom-left) to change these options.")

    -- Run Audit button
    local runBtn = CreateFrame("Button", nil, setupPage, "UIPanelButtonTemplate")
    runBtn:SetSize(140, 30)
    runBtn:SetPoint("BOTTOM", 0, 20)
    runBtn:SetText("Start Audit")
    runBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        SaveBarToggles()
        KeybindAuditUI:ShowResults()
    end)
end

function KeybindAuditUI:CreateResultsPage()
    resultsPage = CreateFrame("Frame", nil, auditFrame)
    resultsPage:SetAllPoints()

    -- Left column header
    gradeText = resultsPage:CreateFontString(nil, "OVERLAY")
    gradeText:SetFont("Fonts\\FRIZQT__.TTF", 38, "OUTLINE")
    gradeText:SetPoint("TOP", resultsPage, "TOPLEFT", 140, -48)

    scoreText = resultsPage:CreateFontString(nil, "OVERLAY")
    scoreText:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    scoreText:SetPoint("TOP", gradeText, "BOTTOM", 0, -4)
    scoreText:SetTextColor(0.8, 0.8, 0.8)

    summaryText = resultsPage:CreateFontString(nil, "OVERLAY")
    summaryText:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    summaryText:SetPoint("TOP", scoreText, "BOTTOM", 0, -6)
    summaryText:SetTextColor(0.7, 0.7, 0.7)
    summaryText:SetWidth(250)

    -- Score bars (clickable for detail drill-down)
    local barY = -148
    local categories = { "Coverage", "Reachability", "Modifier Usage", "Anti-patterns" }
    for i, cat in ipairs(categories) do
        categoryBars[i] = CreateScoreBar(resultsPage, cat, barY - (i - 1) * 22, i)
    end

    -- Divider
    local div = resultsPage:CreateTexture(nil, "ARTWORK")
    div:SetSize(250, 1)
    div:SetPoint("TOPLEFT", 15, -244)
    div:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- Per-bar summary
    local barSumY = -252
    for i = 1, 8 do
        local lbl = resultsPage:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
        lbl:SetPoint("TOPLEFT", 20, barSumY - (i - 1) * 16)
        lbl:SetWidth(250)
        lbl:SetJustifyH("LEFT")
        lbl:Hide()
        barSummaryLabels[i] = lbl
    end

    -- Skipped macros note
    local skippedLabel = resultsPage:CreateFontString(nil, "OVERLAY")
    skippedLabel:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    skippedLabel:SetPoint("BOTTOMLEFT", 20, 42)
    skippedLabel:SetWidth(250)
    skippedLabel:SetJustifyH("LEFT")
    skippedLabel:SetTextColor(0.5, 0.5, 0.5)
    skippedLabel:Hide()
    resultsPage.skippedLabel = skippedLabel

    -- Right column: Recommendations
    local rightX = 290

    -- Vertical divider
    local vDiv = resultsPage:CreateTexture(nil, "ARTWORK")
    vDiv:SetSize(1, 1)
    vDiv:SetPoint("TOPLEFT", rightX - 10, -42)
    vDiv:SetPoint("BOTTOMLEFT", rightX - 10, 40)
    vDiv:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    local recHeader = resultsPage:CreateFontString(nil, "OVERLAY")
    recHeader:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    recHeader:SetPoint("TOPLEFT", rightX, -44)
    recHeader:SetTextColor(0.9, 0.9, 0.9)
    recHeader:SetText("Recommendations")

    issueContainer = CreateFrame("ScrollFrame", "BoundToLearnAuditScroll", resultsPage, "UIPanelScrollFrameTemplate")
    issueContainer:SetPoint("TOPLEFT", rightX, -64)
    issueContainer:SetPoint("BOTTOMRIGHT", -15, 44)

    issueScrollChild = CreateFrame("Frame", nil, issueContainer)
    issueScrollChild:SetSize(250, 1)
    issueContainer:SetScrollChild(issueScrollChild)

    for i = 1, 20 do
        issueRows[i] = CreateIssueRow(issueScrollChild, i)
    end

    -- No issues message
    local noIssues = resultsPage:CreateFontString(nil, "OVERLAY")
    noIssues:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    noIssues:SetPoint("TOP", issueContainer, "TOP", 0, -40)
    noIssues:SetTextColor(0.4, 0.7, 0.4)
    noIssues:SetText("No issues found. Nice work.")
    noIssues:Hide()
    resultsPage.noIssues = noIssues

    -- Settings button (bottom left)
    local settingsBtn = CreateFrame("Button", nil, resultsPage, "UIPanelButtonTemplate")
    settingsBtn:SetSize(80, 24)
    settingsBtn:SetPoint("BOTTOMLEFT", 15, 12)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        KeybindAuditUI:ShowSetup()
    end)

    -- Refresh button (bottom right)
    local refreshBtn = CreateFrame("Button", nil, resultsPage, "UIPanelButtonTemplate")
    refreshBtn:SetSize(80, 24)
    refreshBtn:SetPoint("BOTTOMRIGHT", -15, 12)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        KeybindAuditUI:RefreshResults()
    end)
end

function KeybindAuditUI:CreateMethodologyPage()
    methodologyPage = CreateFrame("Frame", nil, auditFrame)
    methodologyPage:SetAllPoints()

    local scrollFrame = CreateFrame("ScrollFrame", nil, methodologyPage, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 44)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(520)
    scrollFrame:SetScrollChild(content)

    local text = content:CreateFontString(nil, "OVERLAY")
    text:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetWidth(520)
    text:SetJustifyH("LEFT")
    text:SetTextColor(0.75, 0.75, 0.75)
    text:SetText(
        "|cFF55CCFFOverview|r\n"
        .. "The audit scans your action bars and scores your keybind setup on a 0-100 scale "
        .. "across four categories.\n\n"
        .. "|cFF55CCFFCoverage (40%)|r\n"
        .. "Percentage of filled action bar slots that have a keybind assigned. "
        .. "Every ability on your bars should be reachable without clicking.\n\n"
        .. "|cFF55CCFFReachability (30%)|r\n"
        .. "How close your keybinds are to your movement keys. Each bound slot is scored:\n"
        .. "  |cFF66DD66Prime keys (100)|r: 1-5, Q, E, R, F, G, Z, X, C, V, T, B, `, Tab, mouse buttons\n"
        .. "  |cFFDDDD44Acceptable (60)|r: 6, Y, H, N, and other unlisted keys\n"
        .. "  |cFFDD8844Poor (20)|r: 7-0, -, =, F1-F12\n"
        .. "Modifier combos (Shift-Q, Ctrl-3) inherit their base key's tier.\n\n"
        .. "|cFF55CCFFModifier Usage (15%)|r\n"
        .. "Rewards using Shift, Ctrl, and Alt combos to expand your keybind space "
        .. "without moving your hand. Scored by the ratio of modified binds to total binds.\n\n"
        .. "|cFF55CCFFAnti-patterns (15%)|r\n"
        .. "Starts at 100 and deducts for common issues:\n"
        .. "  Keyboard turning (A/D bound to turn): -40\n"
        .. "  Each unbound ability: -5 (max -40)\n"
        .. "  Each poor-tier keybind: -3 (max -20)\n\n"
        .. "|cFF55CCFFGrading|r\n"
        .. "A+ (95+)  A (90+)  A- (85+)  B+ (80+)  B (75+)  B- (70+)\n"
        .. "C+ (65+)  C (60+)  D (50+)  F (below 50)\n\n"
        .. "|cFF55CCFFMMO Mouse|r\n"
        .. "When enabled, number row keys (6-0, -, =) are treated as prime keys "
        .. "since they map to your thumb grid."
    )
    content:SetHeight(text:GetStringHeight() + 10)

    local backBtn = CreateFrame("Button", nil, methodologyPage, "UIPanelButtonTemplate")
    backBtn:SetSize(80, 24)
    backBtn:SetPoint("BOTTOMLEFT", 15, 12)
    backBtn:SetText("Back")
    backBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        KeybindAuditUI:ToggleMethodology()
    end)
end

function KeybindAuditUI:ToggleMethodology()
    if methodologyPage:IsShown() then
        methodologyPage:Hide()
        if methodologyPage.returnToResults then
            resultsPage:Show()
        else
            setupPage:Show()
            self:ShowBarOverlays()
        end
    else
        methodologyPage.returnToResults = resultsPage:IsShown() or categoryDetailPage:IsShown()
        methodologyPage:Show()
        setupPage:Hide()
        resultsPage:Hide()
        categoryDetailPage:Hide()
        self:HideBarOverlays()
    end
end

local TIER_COLORS = {
    prime      = "|cFF66DD66",
    acceptable = "|cFFDDDD44",
    poor       = "|cFFDD8844",
}

local function BuildCoverageDetail(results)
    local lines = {}
    tinsert(lines, sformat("|cFF55CCFFScore: %d / 100|r", results.scores.coverage))
    tinsert(lines, sformat("\n%d of %d filled slots have keybinds assigned.", results.totalBound, results.totalFilled))
    tinsert(lines, "\n\n|cFF55CCFFPer-bar breakdown:|r")
    for _, barDef in ipairs(results.barOrder) do
        local barData = results.bars[barDef.key]
        if barData and not barData.excluded and barData.filledCount > 0 then
            local ratio = barData.boundCount / barData.filledCount * 100
            local r, g, b = GetBarColor(ratio)
            tinsert(lines, sformat("  %s: |cFF%02x%02x%02x%d / %d bound|r",
                barData.label, r * 255, g * 255, b * 255, barData.boundCount, barData.filledCount))
        end
    end
    local unbound = {}
    for _, slot in ipairs(results.allSlots) do
        if not slot.keybind then tinsert(unbound, slot) end
    end
    if #unbound > 0 then
        tinsert(lines, "\n\n|cFF55CCFFUnbound abilities:|r")
        for _, slot in ipairs(unbound) do
            tinsert(lines, sformat("  |cFFDD8844%s|r on %s, slot %d", slot.actionName, slot.barLabel, slot.barIndex))
        end
    end
    tinsert(lines, "\n\n|cFF666666Coverage measures how many of your action bar abilities have keybinds. Every ability you use in combat should be reachable via keyboard.|r")
    return table.concat(lines, "\n")
end

local function BuildReachabilityDetail(results)
    local lines = {}
    tinsert(lines, sformat("|cFF55CCFFScore: %d / 100|r", results.scores.reachability))
    local primeCount, acceptCount, poorCount = 0, 0, 0
    for _, slot in ipairs(results.allSlots) do
        if slot.keybind then
            if slot.tier == "prime" then primeCount = primeCount + 1
            elseif slot.tier == "poor" then poorCount = poorCount + 1
            else acceptCount = acceptCount + 1 end
        end
    end
    tinsert(lines, sformat("\nAverage reachability across %d bound slots.", results.totalBound))
    tinsert(lines, sformat("\n  %sPrime: %d|r (100 pts each)", TIER_COLORS.prime, primeCount))
    tinsert(lines, sformat("  %sAcceptable: %d|r (60 pts each)", TIER_COLORS.acceptable, acceptCount))
    tinsert(lines, sformat("  %sPoor: %d|r (20 pts each)", TIER_COLORS.poor, poorCount))
    tinsert(lines, "\n\n|cFF55CCFFBound slots:|r")
    for _, slot in ipairs(results.allSlots) do
        if slot.keybind then
            local tc = TIER_COLORS[slot.tier] or TIER_COLORS.acceptable
            tinsert(lines, sformat("  %s%s|r - %s (%s)", tc, slot.keybind, slot.actionName, slot.tier))
        end
    end
    tinsert(lines, "\n\n|cFF666666Reachability scores how close your keybinds are to WASD. Prime keys (1-5, Q, E, R, F, etc.) score 100, acceptable keys score 60, and distant keys (7-0, F1-F12) score 20.|r")
    return table.concat(lines, "\n")
end

local function BuildModifierDetail(results)
    local lines = {}
    tinsert(lines, sformat("|cFF55CCFFScore: %d / 100|r", results.scores.modifiers))
    local modCount = 0
    for _, slot in ipairs(results.allSlots) do
        if slot.keybind and slot.hasModifier then modCount = modCount + 1 end
    end
    local ratio = results.totalBound > 0 and (modCount / results.totalBound * 100) or 0
    tinsert(lines, sformat("\n%d of %d keybinds use modifiers (%.0f%%).", modCount, results.totalBound, ratio))
    tinsert(lines, "\n\n|cFF55CCFFScoring tiers:|r")
    tinsert(lines, "  51%+ modified: 100 pts")
    tinsert(lines, "  31-50%: 80 pts")
    tinsert(lines, "  16-30%: 60 pts")
    tinsert(lines, "  1-15%: 40 pts")
    tinsert(lines, "  0%: 20 pts")
    if modCount > 0 then
        tinsert(lines, "\n\n|cFF55CCFFModified keybinds:|r")
        for _, slot in ipairs(results.allSlots) do
            if slot.keybind and slot.hasModifier then
                tinsert(lines, sformat("  |cFF66DD66%s|r - %s", slot.keybind, slot.actionName))
            end
        end
    end
    tinsert(lines, "\n\n|cFF666666Using Shift, Ctrl, and Alt combos triples your available keybinds without moving your hand. More modifiers means more abilities within easy reach.|r")
    return table.concat(lines, "\n")
end

local function BuildAntiPatternDetail(results)
    local lines = {}
    tinsert(lines, sformat("|cFF55CCFFScore: %d / 100|r", results.scores.antiPatterns))
    tinsert(lines, "\nStarts at 100, with deductions for common issues:")
    local deductions = {}
    if results.keyboardTurning then
        tinsert(deductions, "  |cFFDD4444-40|r Keyboard turning detected (A/D bound to turn)")
    end
    local unboundCount = results.totalFilled - results.totalBound
    if unboundCount > 0 then
        local penalty = mmin(unboundCount * 5, 40)
        tinsert(deductions, sformat("  |cFFDD8844-%d|r %d unbound abilities (5 each, max 40)", penalty, unboundCount))
    end
    local poorCount = 0
    for _, slot in ipairs(results.allSlots) do
        if slot.keybind and slot.tier == "poor" then poorCount = poorCount + 1 end
    end
    if poorCount > 0 then
        local penalty = mmin(poorCount * 3, 20)
        tinsert(deductions, sformat("  |cFFDD8844-%d|r %d poor-tier keybinds (3 each, max 20)", penalty, poorCount))
    end
    if #deductions > 0 then
        tinsert(lines, "\n|cFF55CCFFDeductions:|r")
        for _, d in ipairs(deductions) do tinsert(lines, d) end
    else
        tinsert(lines, "\n|cFF66DD66No deductions. Clean setup.|r")
    end
    tinsert(lines, "\n\n|cFF666666Anti-patterns checks for habits that limit your effectiveness: keyboard turning, unbound abilities, and distant key choices.|r")
    return table.concat(lines, "\n")
end

local CATEGORY_BUILDERS = { BuildCoverageDetail, BuildReachabilityDetail, BuildModifierDetail, BuildAntiPatternDetail }
local CATEGORY_NAMES = { "Coverage", "Reachability", "Modifier Usage", "Anti-patterns" }

function KeybindAuditUI:CreateCategoryDetailPage()
    categoryDetailPage = CreateFrame("Frame", nil, auditFrame)
    categoryDetailPage:SetAllPoints()

    local titleText = categoryDetailPage:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    titleText:SetPoint("TOP", 0, -48)
    titleText:SetTextColor(0.33, 0.80, 1.0)
    categoryDetailPage.titleText = titleText

    local scrollFrame = CreateFrame("ScrollFrame", nil, categoryDetailPage, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 20, -72)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 44)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(510)
    scrollFrame:SetScrollChild(content)

    local bodyText = content:CreateFontString(nil, "OVERLAY")
    bodyText:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    bodyText:SetPoint("TOPLEFT", 0, 0)
    bodyText:SetWidth(510)
    bodyText:SetJustifyH("LEFT")
    bodyText:SetTextColor(0.75, 0.75, 0.75)
    categoryDetailPage.bodyText = bodyText
    categoryDetailPage.content = content

    local backBtn = CreateFrame("Button", nil, categoryDetailPage, "UIPanelButtonTemplate")
    backBtn:SetSize(100, 24)
    backBtn:SetPoint("BOTTOMLEFT", 15, 12)
    backBtn:SetText("Scorecard")
    backBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        categoryDetailPage:Hide()
        resultsPage:Show()
    end)

    local settingsBtn = CreateFrame("Button", nil, categoryDetailPage, "UIPanelButtonTemplate")
    settingsBtn:SetSize(80, 24)
    settingsBtn:SetPoint("BOTTOMRIGHT", -15, 12)
    settingsBtn:SetText("Settings")
    settingsBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        KeybindAuditUI:ShowSetup()
    end)

    categoryDetailPage:Hide()
end

function KeybindAuditUI:ShowCategoryDetail(index)
    if not lastResults then return end
    local builder = CATEGORY_BUILDERS[index]
    if not builder then return end

    categoryDetailPage.titleText:SetText(CATEGORY_NAMES[index])
    local body = builder(lastResults)
    categoryDetailPage.bodyText:SetText(body)
    categoryDetailPage.content:SetHeight(categoryDetailPage.bodyText:GetStringHeight() + 10)

    resultsPage:Hide()
    setupPage:Hide()
    methodologyPage:Hide()
    categoryDetailPage:Show()
end

function KeybindAuditUI:ShowBarOverlays()
    LoadBarToggles()
    dimmer:Show()
    for _, barDef in ipairs(BAR_FRAME_MAP) do
        local overlay = barOverlays[barDef.key]
        if overlay then
            local btn1 = _G[barDef.prefix .. "1"]
            if btn1 and btn1:IsVisible() then
                PositionOverlay(overlay, barDef)
                local label = ns.KeybindAudit.ResolveBarLabel(barDef.prefix, barDef.label)
                overlay.label:SetText(label)
                UpdateBarOverlay(overlay, barToggles[barDef.key])
                overlay:Show()
            else
                overlay:Hide()
            end
        end
    end
end

function KeybindAuditUI:HideBarOverlays()
    if dimmer then dimmer:Hide() end
    for _, overlay in pairs(barOverlays) do
        if overlay then overlay:Hide() end
    end
end

function KeybindAuditUI:ShowSetup()
    LoadBarToggles()
    local db = GetDb()

    for _, barDef in ipairs(BAR_FRAME_MAP) do
        local cb = setupPage.barCheckboxes[barDef.key]
        if cb then
            cb:SetChecked(barToggles[barDef.key])
            local label = ns.KeybindAudit.ResolveBarLabel(barDef.prefix, barDef.label)
            cb.label:SetText(label)
        end
    end
    setupPage.mmoMouseCb:SetChecked(db.mmoMouse)
    setupPage.skipCombatCb:SetChecked(db.skipNonCombat)
    setupPage.skipBarsCb:SetChecked(db.skipBarSelection)

    methodologyPage:Hide()
    categoryDetailPage:Hide()
    resultsPage:Hide()
    setupPage:Show()
    self:ShowBarOverlays()
    auditFrame:SetSize(580, 340)
end

function KeybindAuditUI:ShowResults()
    self:HideBarOverlays()
    methodologyPage:Hide()
    categoryDetailPage:Hide()
    setupPage:Hide()
    auditFrame:SetSize(580, 530)
    resultsPage:Show()
    self:RefreshResults()
end

function KeybindAuditUI:RefreshResults()
    local audit = ns.KeybindAudit
    if not audit then return end

    local db = GetDb()
    local results = audit:Scan({
        barFilter = db.bars,
        skipNonCombat = db.skipNonCombat,
        mmoMouse = db.mmoMouse,
    })
    if not results then return end

    local gc = results.gradeColor
    gradeText:SetText(results.grade)
    gradeText:SetTextColor(gc[1], gc[2], gc[3])

    scoreText:SetText(sformat("%d / 100", results.scores.overall))
    summaryText:SetText(results.summary)

    SetScoreBar(categoryBars[1], results.scores.coverage)
    SetScoreBar(categoryBars[2], results.scores.reachability)
    SetScoreBar(categoryBars[3], results.scores.modifiers)
    SetScoreBar(categoryBars[4], results.scores.antiPatterns)

    local barIdx = 0
    for _, barDef in ipairs(results.barOrder) do
        local barData = results.bars[barDef.key]
        if barData and not barData.excluded and barData.filledCount > 0 then
            barIdx = barIdx + 1
            local lbl = barSummaryLabels[barIdx]
            if lbl then
                local ratio = barData.boundCount / barData.filledCount
                local r, g, b = GetBarColor(ratio * 100)
                lbl:SetText(sformat(
                    "%s:  |cFF%02x%02x%02x%d / %d bound|r",
                    barData.label,
                    r * 255, g * 255, b * 255,
                    barData.boundCount, barData.filledCount
                ))
                lbl:Show()
            end
        end
    end
    for i = barIdx + 1, 8 do
        barSummaryLabels[i]:Hide()
    end

    -- Skipped macros note
    local skippedLabel = resultsPage.skippedLabel
    if results.skippedMacros > 0 then
        skippedLabel:SetText(sformat("%d non-combat macro(s) skipped", results.skippedMacros))
        skippedLabel:Show()
    else
        skippedLabel:Hide()
    end

    lastResults = results

    -- Issues
    local issues = results.issues
    resultsPage.noIssues:SetShown(#issues == 0)

    -- Hide scroll bar when nothing to scroll
    local scrollBar = issueContainer.ScrollBar or _G["BoundToLearnAuditScrollScrollBar"]
    if scrollBar then
        scrollBar:SetShown(#issues > 10)
    end

    for i = 1, 20 do
        local row = issueRows[i]
        local issue = issues[i]
        if issue then
            local sc = SEVERITY_COLORS[issue.severity] or SEVERITY_COLORS.low
            row.strip:SetColorTexture(sc[1], sc[2], sc[3], 1)

            if issue.icon then
                row.icon:SetTexture(issue.icon)
                row.icon:Show()
                row.text:SetPoint("TOPLEFT", 34, -3)
                row.detail:SetPoint("TOPLEFT", 34, -17)
            else
                row.icon:Hide()
                row.text:SetPoint("TOPLEFT", 12, -3)
                row.detail:SetPoint("TOPLEFT", 12, -17)
            end

            row.text:SetText(issue.text)
            row.detail:SetText(issue.detail or "")
            row:Show()
        else
            row:Hide()
        end
    end

    issueScrollChild:SetHeight(mmax(1, #issues * ISSUE_ROW_HEIGHT))
end

function KeybindAuditUI:Toggle()
    if not auditFrame then
        self:CreateFrame()
    end
    if auditFrame:IsShown() then
        auditFrame:Hide()
    else
        local db = GetDb()
        if db.skipBarSelection then
            self:ShowResults()
        else
            self:ShowSetup()
        end
        auditFrame:Show()
    end
end

function KeybindAuditUI:Show()
    if not auditFrame then
        self:CreateFrame()
    end
    local db = GetDb()
    if db.skipBarSelection then
        self:ShowResults()
    else
        self:ShowSetup()
    end
    auditFrame:Show()
end

function KeybindAuditUI:Hide()
    if auditFrame then auditFrame:Hide() end
end
