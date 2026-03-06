local ADDON_NAME, ns = ...

local TrackerUI = {}
ns.TrackerUI = TrackerUI

local Utils      = ns.Utils
local sformat    = Utils.sformat
local mmin, mmax = Utils.mmin, Utils.mmax
local mfloor     = Utils.mfloor
local CreateFrame = Utils.CreateFrame
local GetTime    = Utils.GetTime
local ipairs     = Utils.ipairs

local UIParent = UIParent
local GameTooltip = GameTooltip
local IsMouseButtonDown = IsMouseButtonDown

local widget
local ratioText, countText, ratioBar
local recentIcons = {}
local RECENT_ICON_COUNT = 5
local isInitialized = false

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

function TrackerUI:Initialize()
    if isInitialized then return end
    isInitialized = true

    self:CreateWidget()

    if BoundToLearn.db.tracker.showWidget and BoundToLearn.db.tracker.enabled then
        widget:Show()
    end
end

function TrackerUI:CreateWidget()
    widget = CreateFrame("Frame", "BoundToLearnTrackerWidget", UIParent, "BackdropTemplate")
    widget:SetSize(180, 88)
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

    local resetBtn = CreateFrame("Button", nil, widget)
    resetBtn:SetSize(14, 14)
    resetBtn:SetPoint("TOPRIGHT", widget, "TOPRIGHT", -6, -5)
    resetBtn:SetNormalFontObject("GameFontDisableSmall")
    resetBtn:SetHighlightFontObject("GameFontHighlightSmall")
    local resetLabel = resetBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    resetLabel:SetPoint("CENTER")
    resetLabel:SetText("R")
    resetBtn:SetScript("OnClick", function()
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

    -- Row 4: Ratio bar at the bottom
    ratioBar = CreateFrame("StatusBar", nil, widget)
    ratioBar:SetSize(164, 8)
    ratioBar:SetPoint("BOTTOM", widget, "BOTTOM", 0, 7)
    ratioBar:SetMinMaxValues(0, 100)
    ratioBar:SetValue(0)
    ratioBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    ratioBar:SetStatusBarColor(0.2, 0.8, 0.2)

    local barBg = ratioBar:CreateTexture(nil, "BACKGROUND")
    barBg:SetAllPoints()
    barBg:SetColorTexture(0.1, 0.1, 0.1, 0.6)

    self.widget = widget
end

function TrackerUI:OnActionRecorded(entry)
    if not widget or not widget:IsShown() then return end

    local tracker = ns.Tracker
    local ratio = tracker:GetRatio()
    local data = tracker:GetSessionData()

    -- Update ratio display
    ratioText:SetText(sformat("%.0f%%", ratio))
    local r, g, b = GetRatioColor(ratio)
    ratioText:SetTextColor(r, g, b)

    -- Update count
    countText:SetText(sformat("%d KB / %d Click", data.keybinds, data.clicks))

    -- Update bar
    ratioBar:SetValue(ratio)
    ratioBar:SetStatusBarColor(r, g, b)

    -- Shift recent icons left and add new one at the end
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
    if BoundToLearn.db.tracker.showWidget then
        self:ResetDisplay()
        widget:Show()
    end
end

function TrackerUI:OnSessionStop()
    -- Keep widget visible briefly to show final stats
end

function TrackerUI:ResetDisplay()
    if ratioText then ratioText:SetText("0%"); ratioText:SetTextColor(0.2, 0.8, 0.2) end
    if countText then countText:SetText("0 KB / 0 Click") end
    if ratioBar then ratioBar:SetValue(0); ratioBar:SetStatusBarColor(0.2, 0.8, 0.2) end
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
