local ADDON_NAME, ns = ...

local TrackerUI = {}
ns.TrackerUI = TrackerUI

local Utils      = ns.Utils
local sformat    = Utils.sformat
local mmin, mmax = Utils.mmin, Utils.mmax
local mfloor     = Utils.mfloor
local ssub       = Utils.ssub
local CreateFrame = Utils.CreateFrame
local GetTime    = Utils.GetTime
local ipairs     = Utils.ipairs
local PlayUISound = Utils.PlayUISound
local SOUND_CLICK = Utils.SOUND_CLICK
local SOUND_CLOSE = Utils.SOUND_CLOSE

local UIParent = UIParent
local GameTooltip = GameTooltip
local IsMouseButtonDown = IsMouseButtonDown
local InCombatLockdown = InCombatLockdown

local widget
local ratioText, countText, ratioBar
local segLabel, segLeftBtn, segRightBtn
local recentIcons = {}
local RECENT_ICON_COUNT = 5
local isInitialized = false

-- viewIndex: 0 = current, -1 = overall, 1+ = segment history index
local viewIndex = 0

local WIDGET_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

-- Color thresholds for the ratio bar (keybind %)
-- Green at 90%+, yellow at 70-89%, red below 70%
local function GetRatioColor(ratio)
    if ratio >= 90 then
        return 0.2, 0.8, 0.2
    elseif ratio >= 70 then
        local t = (ratio - 70) / 20
        return 0.8 - 0.6 * t, 0.8, 0.2
    else
        local t = ratio / 70
        return 0.8, 0.2 + 0.6 * t, 0.2
    end
end

local function ShouldShowWidget()
    if not BoundToLearn.db.tracker.showWidget then return false end
    if not BoundToLearn.db.tracker.enabled then return false end
    local inCombat = InCombatLockdown()
    if BoundToLearn.db.tracker.combatOnly and not inCombat then return false end
    if BoundToLearn.db.tracker.hideInCombat and inCombat then return false end
    return true
end

function TrackerUI:Initialize()
    if isInitialized then return end
    isInitialized = true

    self:CreateWidget()

    local combatFrame = CreateFrame("Frame")
    combatFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    combatFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    combatFrame:SetScript("OnEvent", function()
        if widget then
            widget:SetShown(ShouldShowWidget())
        end
    end)

    widget:SetShown(ShouldShowWidget())
end

function TrackerUI:CreateWidget()
    widget = CreateFrame("Frame", "BoundToLearnTrackerWidget", UIParent, "BackdropTemplate")
    widget:SetSize(180, 102)
    widget:SetFrameStrata("MEDIUM")
    widget:SetFrameLevel(100)
    widget:SetBackdrop(WIDGET_BACKDROP)
    widget:SetBackdropColor(0.05, 0.05, 0.05, 0.85)
    widget:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    widget:SetClampedToScreen(true)
    widget:EnableMouse(true)
    widget:SetMovable(true)
    widget:RegisterForDrag("LeftButton")
    widget:Hide()

    -- Restore saved position or default to top-center
    local pos = BoundToLearn.db.tracker.widgetPosition
    if pos then
        widget:SetPoint(pos.point, UIParent, pos.relPoint, pos.x, pos.y)
    else
        widget:SetPoint("TOP", UIParent, "TOP", 0, -120)
    end

    local scale = BoundToLearn.db.tracker.widgetScale or 1.0
    widget:SetScale(scale)

    widget:SetScript("OnDragStart", function(self)
        self:StartMoving()
    end)
    widget:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        local point, _, relPoint, x, y = self:GetPoint()
        BoundToLearn.db.tracker.widgetPosition = {
            point = point, relPoint = relPoint, x = x, y = y,
        }
    end)

    -- Row 1: Title + reset button
    local title = widget:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", 8, -6)
    title:SetText("|cFF55CCFFKeybind Tracker|r")
    title:SetJustifyH("LEFT")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, widget)
    closeBtn:SetSize(14, 14)
    closeBtn:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -6, -5)
    local closeLabel = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    closeLabel:SetPoint("CENTER")
    closeLabel:SetText("x")
    closeBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLOSE)
        if BoundToLearn then BoundToLearn:ToggleTracker() end
    end)
    closeBtn:SetScript("OnEnter", function(self)
        closeLabel:SetFontObject("GameFontHighlightSmall")
        closeLabel:SetTextColor(1, 0.3, 0.3)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Close Tracker")
        GameTooltip:Show()
    end)
    closeBtn:SetScript("OnLeave", function()
        closeLabel:SetFontObject("GameFontDisableSmall")
        GameTooltip:Hide()
    end)

    local resetBtn = CreateFrame("Button", nil, widget)
    resetBtn:SetSize(14, 14)
    resetBtn:SetPoint("RIGHT", closeBtn, "LEFT", -4, 0)
    resetBtn:SetNormalFontObject("GameFontDisableSmall")
    resetBtn:SetHighlightFontObject("GameFontHighlightSmall")
    local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resetLabel:SetPoint("CENTER")
    resetLabel:SetText("R")
    resetBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        if ns.Tracker then
            ns.Tracker:ResetSession()
            TrackerUI:ResetDisplay()
        end
    end)
    resetBtn:SetScript("OnEnter", function(self)
        resetLabel:SetFontObject("GameFontHighlightSmall")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Reset Session")
        GameTooltip:Show()
    end)
    resetBtn:SetScript("OnLeave", function()
        resetLabel:SetFontObject("GameFontDisableSmall")
        GameTooltip:Hide()
    end)

    -- Pause/resume button
    local pauseBtn = CreateFrame("Button", nil, widget)
    pauseBtn:SetSize(14, 14)
    pauseBtn:SetPoint("RIGHT", resetBtn, "LEFT", -4, 0)
    local pauseLabel = pauseBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    pauseLabel:SetPoint("CENTER")
    pauseLabel:SetText("II")
    pauseBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        if ns.Tracker then ns.Tracker:TogglePause() end
    end)
    pauseBtn:SetScript("OnEnter", function(self)
        pauseLabel:SetFontObject("GameFontHighlightSmall")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        local paused = ns.Tracker and ns.Tracker:IsPaused()
        GameTooltip:SetText(paused and "Resume Tracking" or "Pause Tracking")
        GameTooltip:Show()
    end)
    pauseBtn:SetScript("OnLeave", function()
        pauseLabel:SetFontObject("GameFontDisableSmall")
        GameTooltip:Hide()
    end)
    self.pauseLabel = pauseLabel

    -- Options button
    local optBtn = CreateFrame("Button", nil, widget)
    optBtn:SetSize(14, 14)
    optBtn:SetPoint("RIGHT", pauseBtn, "LEFT", -4, 0)
    local optLabel = optBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    optLabel:SetPoint("CENTER")
    optLabel:SetText("O")
    optBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        if ns.Options then ns.Options:ShowTrackerSection() end
    end)
    optBtn:SetScript("OnEnter", function(self)
        optLabel:SetFontObject("GameFontHighlightSmall")
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Options")
        GameTooltip:Show()
    end)
    optBtn:SetScript("OnLeave", function()
        optLabel:SetFontObject("GameFontDisableSmall")
        GameTooltip:Hide()
    end)

    -- Row 2: Ratio % on left, count on right
    ratioText = widget:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    ratioText:SetPoint("TOPLEFT", widget, "TOPLEFT", 8, -20)
    ratioText:SetText("0%")
    ratioText:SetJustifyH("LEFT")

    countText = widget:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countText:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -8, -22)
    countText:SetText("0 KB / 0 Click")
    countText:SetJustifyH("RIGHT")

    -- Row 3: Recent action icons (centered)
    local iconRowWidth = RECENT_ICON_COUNT * 22 - 2
    local iconRowLeft = (180 - iconRowWidth) / 2
    for i = 1, RECENT_ICON_COUNT do
        local frame = CreateFrame("Frame", nil, widget)
        frame:SetSize(20, 20)
        frame:SetPoint("TOPLEFT", widget, "TOPLEFT", iconRowLeft + (i - 1) * 22, -42)

        local icon = frame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(18, 18)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        frame.icon = icon

        -- Red tint overlay for clicks
        local tint = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        tint:SetSize(18, 18)
        tint:SetPoint("CENTER")
        tint:SetColorTexture(0.8, 0.1, 0.1, 0.45)
        tint:Hide()
        frame.tint = tint

        local borderSize = 1.5
        local edges = {}
        local edgeAnchors = {
            { "TOPLEFT", "TOPRIGHT", 0, 0, 20, borderSize },
            { "BOTTOMLEFT", "BOTTOMRIGHT", 0, 0, 20, borderSize },
            { "TOPLEFT", "BOTTOMLEFT", 0, 0, borderSize, 20 },
            { "TOPRIGHT", "BOTTOMRIGHT", 0, 0, borderSize, 20 },
        }
        for _, anchor in ipairs(edgeAnchors) do
            local edge = frame:CreateTexture(nil, "OVERLAY")
            edge:SetPoint(anchor[1])
            edge:SetPoint(anchor[2])
            edge:SetSize(anchor[5], anchor[6])
            edge:SetColorTexture(0.3, 0.3, 0.3, 0.8)
            edges[#edges + 1] = edge
        end
        frame.edges = edges

        frame.icon:SetTexture(nil)
        frame:Hide()
        recentIcons[i] = frame
    end

    -- Row 4: Ratio bar
    ratioBar = CreateFrame("StatusBar", nil, widget)
    ratioBar:SetSize(164, 8)
    ratioBar:SetPoint("TOPLEFT", widget, "TOPLEFT", 8, -66)
    ratioBar:SetMinMaxValues(0, 100)
    ratioBar:SetValue(0)
    ratioBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ratioBar:SetStatusBarColor(0.2, 0.8, 0.2)

    local barBg = ratioBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

    -- Row 5: Segment navigation
    segLeftBtn = CreateFrame("Button", nil, widget)
    segLeftBtn:SetSize(14, 14)
    segLeftBtn:SetPoint("BOTTOMLEFT", widget, "BOTTOMLEFT", 6, 4)
    local segLeftLabel = segLeftBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    segLeftLabel:SetPoint("CENTER")
    segLeftLabel:SetText("<")
    segLeftBtn:SetScript("OnEnter", function() segLeftLabel:SetFontObject("GameFontHighlightSmall") end)
    segLeftBtn:SetScript("OnLeave", function() segLeftLabel:SetFontObject("GameFontDisableSmall") end)
    segLeftBtn:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); TrackerUI:NavigateSegment(-1) end)

    segRightBtn = CreateFrame("Button", nil, widget)
    segRightBtn:SetSize(14, 14)
    segRightBtn:SetPoint("BOTTOMRIGHT", widget, "BOTTOMRIGHT", -6, 4)
    local segRightLabel = segRightBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    segRightLabel:SetPoint("CENTER")
    segRightLabel:SetText(">")
    segRightBtn:SetScript("OnEnter", function() segRightLabel:SetFontObject("GameFontHighlightSmall") end)
    segRightBtn:SetScript("OnLeave", function() segRightLabel:SetFontObject("GameFontDisableSmall") end)
    segRightBtn:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); TrackerUI:NavigateSegment(1) end)

    local segLabelBtn = CreateFrame("Button", nil, widget)
    segLabelBtn:SetHeight(14)
    segLabelBtn:SetPoint("BOTTOMLEFT", segLeftBtn, "BOTTOMRIGHT", 2, 0)
    segLabelBtn:SetPoint("BOTTOMRIGHT", segRightBtn, "BOTTOMLEFT", -2, 0)
    segLabel = segLabelBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    segLabel:SetPoint("CENTER")
    segLabel:SetText("Current")
    segLabel:SetJustifyH("CENTER")
    segLabelBtn:SetScript("OnEnter", function() segLabel:SetFontObject("GameFontHighlightSmall") end)
    segLabelBtn:SetScript("OnLeave", function() segLabel:SetFontObject("GameFontDisableSmall") end)
    segLabelBtn:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); TrackerUI:ToggleSegmentDropdown() end)

    self.widget = widget
end

function TrackerUI:OnActionRecorded(entry)
    if not widget or not widget:IsShown() then return end

    -- Update stats display for Current and Overall (both change in real time)
    if viewIndex == 0 or viewIndex == -1 then
        self:RefreshSegmentView()
    end

    -- Always update recent icons regardless of viewed segment
    for i = 1, RECENT_ICON_COUNT - 1 do
        local src = recentIcons[i + 1]
        local dst = recentIcons[i]
        dst.icon:SetTexture(src.icon:GetTexture())
        dst.tint:SetShown(src.tint:IsShown())
        for e = 1, 4 do
            local sr, sg, sb, sa = src.edges[e]:GetVertexColor()
            dst.edges[e]:SetVertexColor(sr, sg, sb, sa)
        end
        dst:SetShown(src:IsShown())
    end

    -- Set the newest icon
    local last = recentIcons[RECENT_ICON_COUNT]
    if entry.icon then
        last.icon:SetTexture(entry.icon)
        last:Show()
        local cr, cg, cb = 0.2, 0.8, 0.2 -- green for keybind
        if entry.wasClick then
            cr, cg, cb = 0.8, 0.2, 0.2   -- red for click
        end
        last.tint:SetShown(entry.wasClick)
        for e = 1, 4 do
            last.edges[e]:SetVertexColor(cr, cg, cb, 1)
        end
    else
        last:Hide()
    end
end

function TrackerUI:OnSessionStart()
    if not isInitialized then return end
    if ShouldShowWidget() then
        self:ResetDisplay()
        widget:Show()
    end
end

function TrackerUI:OnSessionStop()
    -- Keep widget visible briefly to show final stats
end

function TrackerUI:ResetDisplay()
    viewIndex = 0
    if ratioText then ratioText:SetText("0%"); ratioText:SetTextColor(0.2, 0.8, 0.2) end
    if countText then countText:SetText("0 KB / 0 Click") end
    if ratioBar then ratioBar:SetValue(0); ratioBar:SetStatusBarColor(0.2, 0.8, 0.2) end
    if segLabel then segLabel:SetText("Current") end
    for i = 1, RECENT_ICON_COUNT do
        recentIcons[i]:Hide()
    end
end

function TrackerUI:Show()
    if widget then widget:Show() end
end

function TrackerUI:Hide()
    if widget then widget:Hide() end
end

function TrackerUI:Toggle()
    if widget then widget:SetShown(not widget:IsShown()) end
end

function TrackerUI:OnPauseChanged(paused)
    if self.pauseLabel then
        self.pauseLabel:SetText(paused and ">" or "II")
    end
    if widget then
        widget:SetAlpha(paused and 0.5 or 1.0)
    end
end

function TrackerUI:NavigateSegment(direction)
    local tracker = ns.Tracker
    if not tracker then return end

    local segCount = tracker:GetSegmentCount()
    -- Navigation order: Current (0) -> segments (1..N) -> Overall (-1) -> wrap
    local newIndex = viewIndex + direction

    if newIndex > segCount then
        newIndex = -1  -- wrap to Overall
    elseif newIndex < -1 then
        newIndex = segCount  -- wrap to last segment
    end

    viewIndex = newIndex
    self:RefreshSegmentView()
end

local MAX_LABEL_LEN = 18

local function TruncateLabel(text, maxLen)
    if #text <= maxLen then return text end
    return ssub(text, 1, maxLen - 1) .. "..."
end

function TrackerUI:RefreshSegmentView()
    local tracker = ns.Tracker
    if not tracker or not widget then return end

    local clicks, keybinds, label

    if viewIndex == 0 then
        -- Current segment
        local data = tracker:GetSessionData()
        clicks = data.clicks
        keybinds = data.keybinds
        label = tracker:GetCurrentLabel()
    elseif viewIndex == -1 then
        -- Overall
        local data = tracker:GetOverallData()
        clicks = data.clicks
        keybinds = data.keybinds
        label = "Overall"
    else
        -- Historical segment
        local seg = tracker:GetSegment(viewIndex)
        if seg then
            clicks = seg.clicks
            keybinds = seg.keybinds
            label = seg.label
        else
            viewIndex = 0
            self:RefreshSegmentView()
            return
        end
    end

    local total = clicks + keybinds
    local ratio = total > 0 and (keybinds / total) * 100 or 0

    ratioText:SetText(sformat("%.0f%%", ratio))
    local r, g, b = GetRatioColor(ratio)
    ratioText:SetTextColor(r, g, b)
    countText:SetText(sformat("%d KB / %d Click", keybinds, clicks))
    ratioBar:SetValue(ratio)
    ratioBar:SetStatusBarColor(r, g, b)

    if segLabel then
        segLabel:SetText(TruncateLabel(label, 20))
    end
end

function TrackerUI:OnSegmentChanged()
    if viewIndex == 0 then
        self:RefreshSegmentView()
    end
end

-- Segment dropdown menu
local segDropdown

local DROPDOWN_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

function TrackerUI:ToggleSegmentDropdown()
    if segDropdown and segDropdown:IsShown() then
        segDropdown:Hide()
        return
    end
    self:ShowSegmentDropdown()
end

local ROW_HEIGHT = 18
local SEP_HEIGHT = 9
local MENU_WIDTH = 160
local function CreateSegmentButton(parent)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(MENU_WIDTH - 8, ROW_HEIGHT)
    btn:SetNormalFontObject("GameFontHighlightSmall")
    btn:SetHighlightFontObject("GameFontNormalSmall")
    btn:SetScript("OnEnter", function(self)
        if self.tooltipText then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.tooltipText, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    return btn
end

local function SetupDropdownFrame()
    segDropdown = CreateFrame("Frame", nil, widget, "BackdropTemplate")
    segDropdown:SetFrameStrata("FULLSCREEN_DIALOG")
    segDropdown:SetBackdrop(DROPDOWN_BACKDROP)
    segDropdown:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    segDropdown:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    segDropdown:Hide()

    -- Fixed header: Current + Overall
    segDropdown.headerButtons = {}
    for i = 1, 2 do
        local btn = CreateSegmentButton(segDropdown)
        btn:SetPoint("TOPLEFT", 4, -4 - (i - 1) * ROW_HEIGHT)
        segDropdown.headerButtons[i] = btn
    end

    -- Separator
    local sep = segDropdown:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetColorTexture(0.3, 0.3, 0.3, 0.6)
    sep:SetPoint("TOPLEFT", 8, -4 - 2 * ROW_HEIGHT - 4)
    sep:SetPoint("TOPRIGHT", -8, -4 - 2 * ROW_HEIGHT - 4)
    segDropdown.sep = sep

    -- Scrollable segment area
    local SCROLLBAR_WIDTH = 4
    local headerHeight = 2 * ROW_HEIGHT + SEP_HEIGHT + 4
    local scrollFrame = CreateFrame("ScrollFrame", nil, segDropdown)
    scrollFrame:SetPoint("TOPLEFT", 0, -headerHeight)
    scrollFrame:SetPoint("BOTTOMRIGHT", 0, 4)
    segDropdown.scrollFrame = scrollFrame

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetWidth(MENU_WIDTH)
    scrollFrame:SetScrollChild(scrollChild)
    segDropdown.scrollChild = scrollChild
    segDropdown.segButtons = {}

    -- Scrollbar track + thumb
    local track = CreateFrame("Frame", nil, segDropdown)
    track:SetWidth(SCROLLBAR_WIDTH)
    track:SetPoint("TOPRIGHT", segDropdown, "TOPRIGHT", -2, -headerHeight)
    track:SetPoint("BOTTOMRIGHT", segDropdown, "BOTTOMRIGHT", -2, 4)
    local trackBg = track:CreateTexture(nil, "BACKGROUND")
    trackBg:SetAllPoints()
    trackBg:SetColorTexture(0.15, 0.15, 0.15, 0.4)
    segDropdown.scrollTrack = track

    local thumb = track:CreateTexture(nil, "OVERLAY")
    thumb:SetWidth(SCROLLBAR_WIDTH)
    thumb:SetColorTexture(0.5, 0.5, 0.5, 0.6)
    thumb:SetPoint("TOP", track, "TOP", 0, 0)
    thumb:SetHeight(20)
    segDropdown.scrollThumb = thumb

    local function UpdateScrollbar()
        local viewH = scrollFrame:GetHeight()
        local contentH = scrollChild:GetHeight()
        local trackH = track:GetHeight()
        if contentH - viewH < 1 or trackH <= 0 then
            track:Hide()
            return
        end
        track:Show()
        local thumbH = mmax(12, (viewH / contentH) * trackH)
        thumb:SetHeight(thumbH)
        local maxScroll = contentH - viewH
        local scrollPos = scrollFrame:GetVerticalScroll()
        local thumbTravel = trackH - thumbH
        local offset = (scrollPos / maxScroll) * thumbTravel
        thumb:ClearAllPoints()
        thumb:SetPoint("TOP", track, "TOP", 0, -offset)
    end
    segDropdown.UpdateScrollbar = UpdateScrollbar

    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local cur = self:GetVerticalScroll()
        local maxScroll = mmax(0, scrollChild:GetHeight() - self:GetHeight())
        self:SetVerticalScroll(mmin(mmax(cur - delta * ROW_HEIGHT * 2, 0), maxScroll))
        UpdateScrollbar()
    end)

    -- Also scroll when wheeling over the whole dropdown
    segDropdown:EnableMouseWheel(true)
    segDropdown:SetScript("OnMouseWheel", function(_, delta)
        scrollFrame:GetScript("OnMouseWheel")(scrollFrame, delta)
    end)

    segDropdown:SetScript("OnShow", function(self)
        self:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not widget:IsMouseOver()
                and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                self:Hide()
            end
        end)
    end)
    segDropdown:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
    end)
end

function TrackerUI:ShowSegmentDropdown()
    local tracker = ns.Tracker
    if not tracker or not widget then return end

    if not segDropdown then SetupDropdownFrame() end

    -- Header buttons
    local headerItems = {
        { label = "Current", index = 0 },
        { label = "Overall", index = -1 },
    }
    for i, item in ipairs(headerItems) do
        local btn = segDropdown.headerButtons[i]
        btn:SetText(item.label)
        btn.tooltipText = nil
        if item.index == viewIndex then
            btn:SetNormalFontObject("GameFontNormalSmall")
        else
            btn:SetNormalFontObject("GameFontHighlightSmall")
        end
        local idx = item.index
        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            viewIndex = idx
            TrackerUI:RefreshSegmentView()
            segDropdown:Hide()
        end)
    end

    -- Segment history buttons
    local segs = tracker:GetSegments()
    local segCount = #segs

    segDropdown.sep:SetShown(segCount > 0)

    -- Ensure enough buttons
    for i = #segDropdown.segButtons + 1, segCount do
        segDropdown.segButtons[i] = CreateSegmentButton(segDropdown.scrollChild)
    end

    for i = 1, segCount do
        local seg = segs[i]
        local total = seg.clicks + seg.keybinds
        local ratio = total > 0 and mfloor((seg.keybinds / total) * 100) or 0
        local btn = segDropdown.segButtons[i]
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", 4, -(i - 1) * ROW_HEIGHT)
        local truncName = TruncateLabel(seg.label, MAX_LABEL_LEN)
        btn:SetText(sformat("%s  |cFF888888%d%%|r", truncName, ratio))
        btn.tooltipText = (#seg.label > MAX_LABEL_LEN)
            and sformat("%s\n%d%% keybinds", seg.label, ratio) or nil
        btn:Show()
        if i == viewIndex then
            btn:SetNormalFontObject("GameFontNormalSmall")
        else
            btn:SetNormalFontObject("GameFontHighlightSmall")
        end
        local idx = i
        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            viewIndex = idx
            TrackerUI:RefreshSegmentView()
            segDropdown:Hide()
        end)
    end
    for i = segCount + 1, #segDropdown.segButtons do
        segDropdown.segButtons[i]:Hide()
    end

    -- Size the scroll child to fit all segment rows
    segDropdown.scrollChild:SetHeight(mmax(1, segCount * ROW_HEIGHT))

    -- Size the dropdown: header is fixed, scroll area is capped
    local headerHeight = 2 * ROW_HEIGHT + (segCount > 0 and SEP_HEIGHT or 0) + 4
    local maxVisible = BoundToLearn.db and BoundToLearn.db.tracker.maxSegments or 6
    local visibleSegs = mmin(segCount, maxVisible)
    local scrollHeight = visibleSegs * ROW_HEIGHT
    local totalHeight = headerHeight + scrollHeight + 4

    segDropdown:SetSize(MENU_WIDTH, totalHeight)
    segDropdown:ClearAllPoints()
    segDropdown:SetPoint("TOPLEFT", widget, "BOTTOMLEFT", 0, 2)

    -- Reset scroll position and update scrollbar
    segDropdown.scrollFrame:SetVerticalScroll(0)
    segDropdown:Show()
    segDropdown.UpdateScrollbar()
end
