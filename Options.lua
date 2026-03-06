local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local Utils     = ns.Utils
local sformat   = Utils.sformat
local mfloor    = Utils.mfloor
local mmin, mmax = Utils.mmin, Utils.mmax
local tonumber  = Utils.tonumber
local tostring  = Utils.tostring
local tinsert   = Utils.tinsert
local ipairs    = Utils.ipairs
local pairs     = Utils.pairs
local CreateFrame = Utils.CreateFrame

local UIParent = UIParent

local optionsFrame
local isInitialized = false
local activeTab = "general"

local PANEL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

function Options:Initialize()
    if isInitialized then return end
    isInitialized = true
end

-- =========================================
-- Main frame + tabs
-- =========================================

function Options:CreateFrame()
    if optionsFrame then return end

    optionsFrame = CreateFrame("Frame", "BoundToLearnOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(440, 460)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:SetFrameStrata("DIALOG")
    optionsFrame:SetBackdrop(PANEL_BACKDROP)
    optionsFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    optionsFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    optionsFrame:EnableMouse(true)
    optionsFrame:SetMovable(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)

    local close = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = optionsFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFBoundToLearn Options|r")

    -- Tab buttons
    local tabs = { { key = "general", label = "General" }, { key = "game", label = "Game" } }
    optionsFrame.tabs = {}
    for i, t in ipairs(tabs) do
        local tab = CreateFrame("Button", nil, optionsFrame)
        tab:SetSize(100, 24)
        tab:SetPoint("TOPLEFT", 15 + (i - 1) * 110, -35)
        tab:SetNormalFontObject("GameFontNormal")
        tab:SetHighlightFontObject("GameFontHighlight")
        tab:SetText(t.label)
        tab.tabKey = t.key

        local underline = tab:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 0, -2)
        underline:SetPoint("BOTTOMRIGHT", 0, -2)
        underline:SetHeight(2)
        underline:SetColorTexture(0.33, 0.8, 1, 1)
        underline:Hide()
        tab.underline = underline

        tab:SetScript("OnClick", function()
            self:SetTab(t.key)
        end)

        optionsFrame.tabs[i] = tab
    end

    -- Tab content panels
    self:CreateGeneralPanel()
    self:CreateGamePanel()

    -- Bottom buttons (shared)
    self:CreateResetButtons()

    self:SetTab("general")
    optionsFrame:Hide()
end

function Options:SetTab(tabKey)
    activeTab = tabKey
    if optionsFrame.generalPanel then
        optionsFrame.generalPanel:SetShown(tabKey == "general")
    end
    if optionsFrame.gamePanel then
        optionsFrame.gamePanel:SetShown(tabKey == "game")
    end
    for _, tab in ipairs(optionsFrame.tabs) do
        tab.underline:SetShown(tab.tabKey == tabKey)
    end
end

-- =========================================
-- General tab (general + tracker settings)
-- =========================================

function Options:CreateGeneralPanel()
    local panel = CreateFrame("Frame", nil, optionsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("BOTTOMRIGHT", -15, 50)
    optionsFrame.generalPanel = panel

    local y = 0

    -- General section
    y = self:AddSectionHeader(panel, "General", y)
    y = self:AddCheckbox(panel, "Show Login Message", y,
        function() return BoundToLearn.db.options.showLoginMessage end,
        function(v) BoundToLearn.db.options.showLoginMessage = v end)
    y = self:AddCheckbox(panel, "Mute Chat Messages", y,
        function() return BoundToLearn.db.options.muteChat end,
        function(v) BoundToLearn.db.options.muteChat = v end)
    y = self:AddCheckbox(panel, "Show Minimap Button", y,
        function() return BoundToLearn.db.options.showMinimapButton end,
        function(v)
            BoundToLearn.db.options.showMinimapButton = v
            BoundToLearn:UpdateMinimapButton()
        end)

    y = y - 10

    -- Tracker section
    y = self:AddSectionHeader(panel, "Keybind Tracker", y)
    y = self:AddCheckbox(panel, "Enable on Login", y,
        function() return BoundToLearn.db.tracker.enabled end,
        function(v) BoundToLearn.db.tracker.enabled = v end)
    y = self:AddCheckbox(panel, "Show Floating Widget", y,
        function() return BoundToLearn.db.tracker.showWidget end,
        function(v)
            BoundToLearn.db.tracker.showWidget = v
            if ns.TrackerUI then
                if v and ns.Tracker and ns.Tracker:IsTracking() then
                    ns.TrackerUI:Show()
                else
                    ns.TrackerUI:Hide()
                end
            end
        end)
    y = self:AddCheckbox(panel, "Widget in Combat Only", y,
        function() return BoundToLearn.db.tracker.combatOnly end,
        function(v) BoundToLearn.db.tracker.combatOnly = v end)
    y = self:AddSlider(panel, "Widget Scale", 0.5, 2.0, 0.1, y,
        function() return BoundToLearn.db.tracker.widgetScale end,
        function(v)
            BoundToLearn.db.tracker.widgetScale = v
            if ns.TrackerUI and ns.TrackerUI.widget then
                ns.TrackerUI.widget:SetScale(v)
            end
        end, function(v) return sformat("%.0f%%", v * 100) end)

    -- Tracker filters
    y = y - 6
    local filterLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    filterLabel:SetPoint("TOPLEFT", 14, y)
    filterLabel:SetText("Ignore in Tracker:")
    filterLabel:SetTextColor(0.55, 0.55, 0.55)
    y = y - 18

    local filterNames = {
        { key = "mounts",      label = "Mounts" },
        { key = "toys",        label = "Toys" },
        { key = "hearthstones", label = "Hearthstones" },
        { key = "teleports",   label = "Teleports" },
    }
    for i, f in ipairs(filterNames) do
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", (i - 1) * 100 + 14, y)
        cb:SetChecked(BoundToLearn.db.tracker.filter[f.key])
        local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cbText:SetText(f.label)
        local key = f.key
        cb:SetScript("OnClick", function(self)
            BoundToLearn.db.tracker.filter[key] = self:GetChecked()
        end)
    end
end

-- =========================================
-- Game tab (game settings + bars + custom sliders)
-- =========================================

function Options:CreateGamePanel()
    local panel = CreateFrame("Frame", nil, optionsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("BOTTOMRIGHT", -15, 50)
    panel:Hide()
    optionsFrame.gamePanel = panel

    local y = 0

    y = self:AddSectionHeader(panel, "Game Settings", y)
    y = self:AddCheckbox(panel, "Game Sounds", y,
        function() return BoundToLearn.db.game.soundEnabled end,
        function(v) BoundToLearn.db.game.soundEnabled = v end)
    y = self:AddCheckbox(panel, "Show Combo Counter", y,
        function() return BoundToLearn.db.game.showCombo end,
        function(v) BoundToLearn.db.game.showCombo = v end)

    y = y - 10

    -- Action bars section
    y = self:AddSectionHeader(panel, "Action Bars", y)

    local barLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    barLabel:SetPoint("TOPLEFT", 14, y)
    barLabel:SetText("Select which action bars to include in the game:")
    barLabel:SetTextColor(0.6, 0.6, 0.6)
    y = y - 18

    local barDefs = {
        { key = "main",        label = "Action Bar 1 (Main Bar)" },
        { key = "bottomLeft",  label = "Action Bar 2" },
        { key = "bottomRight", label = "Action Bar 3" },
        { key = "right",       label = "Action Bar 4" },
        { key = "left",        label = "Action Bar 5" },
    }

    -- Two-column layout for bars
    for i, b in ipairs(barDefs) do
        local col = (i - 1) % 2
        local row = mfloor((i - 1) / 2)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetPoint("TOPLEFT", 14 + col * 200, y - row * 24)
        cb:SetChecked(BoundToLearn.db.game.bars[b.key])
        local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cbText:SetText(b.label)
        local key = b.key
        cb:SetScript("OnClick", function(self)
            BoundToLearn.db.game.bars[key] = self:GetChecked()
        end)
    end
    y = y - mfloor((#barDefs + 1) / 2) * 24

    y = y - 10

    -- Custom difficulty sliders (practice mode)
    y = self:AddSectionHeader(panel, "Custom Difficulty", y)

    local custLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    custLabel:SetPoint("TOPLEFT", 14, y)
    custLabel:SetText("These settings apply when difficulty is set to Custom (practice mode).")
    custLabel:SetTextColor(0.6, 0.6, 0.6)
    y = y - 18

    y = self:AddSlider(panel, "Fall Speed", 50, 300, 10, y,
        function() return BoundToLearn.db.game.fallSpeed end,
        function(v) BoundToLearn.db.game.fallSpeed = v end)
    y = self:AddSlider(panel, "Spawn Interval", 0.5, 3.0, 0.1, y,
        function() return BoundToLearn.db.game.spawnInterval end,
        function(v) BoundToLearn.db.game.spawnInterval = v end,
        function(v) return sformat("%.1fs", v) end)
    y = self:AddSlider(panel, "Max Notes", 1, 6, 1, y,
        function() return BoundToLearn.db.game.maxActiveNotes end,
        function(v) BoundToLearn.db.game.maxActiveNotes = v end)
    y = self:AddSlider(panel, "Fall Distance", 150, 500, 25, y,
        function() return BoundToLearn.db.game.fallDistance end,
        function(v) BoundToLearn.db.game.fallDistance = v end)
end

-- =========================================
-- Shared UI helpers
-- =========================================

function Options:AddSectionHeader(parent, text, y)
    local accent = parent:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, y)
    accent:SetPoint("TOPRIGHT", 0, y)
    accent:SetHeight(1)
    accent:SetColorTexture(0.33, 0.8, 1, 0.4)

    local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("TOPLEFT", 2, y - 5)
    label:SetText("|cFF55CCFF" .. text .. "|r")
    return y - 22
end

function Options:AddCheckbox(parent, label, y, getter, setter)
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", 14, y)
    cb:SetChecked(getter())
    local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbText:SetText(label)
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    return y - 24
end

function Options:AddSlider(parent, label, minVal, maxVal, step, y, getter, setter, formatFunc)
    formatFunc = formatFunc or function(v) return sformat("%.0f", v) end

    local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("TOPLEFT", 18, y - 2)
    lbl:SetText(label)

    local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
    slider:SetWidth(160)
    slider:SetPoint("TOPLEFT", 170, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    slider:SetObeyStepOnDrag(true)
    slider.Low:SetText("")
    slider.High:SetText("")
    slider.Text:SetText("")

    local valText = slider:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    valText:SetPoint("LEFT", slider, "RIGHT", 8, 0)

    slider:SetValue(getter())
    valText:SetText(formatFunc(getter()))

    slider:SetScript("OnValueChanged", function(self, value)
        value = mfloor(value / step + 0.5) * step
        setter(value)
        valText:SetText(formatFunc(value))
    end)

    return y - 26
end

-- =========================================
-- Reset buttons (shared, anchored to main frame bottom)
-- =========================================

function Options:CreateResetButtons()
    local resetStats = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    resetStats:SetSize(120, 24)
    resetStats:SetPoint("BOTTOMLEFT", 20, 15)
    resetStats:SetText("Reset Stats")
    resetStats:SetScript("OnClick", function()
        StaticPopup_Show("BOUNDTOLEARN_RESET_STATS")
    end)

    local resetDefaults = CreateFrame("Button", nil, optionsFrame, "UIPanelButtonTemplate")
    resetDefaults:SetSize(120, 24)
    resetDefaults:SetPoint("BOTTOMRIGHT", -20, 15)
    resetDefaults:SetText("Reset Defaults")
    resetDefaults:SetScript("OnClick", function()
        StaticPopup_Show("BOUNDTOLEARN_RESET_DEFAULTS")
    end)

    StaticPopupDialogs["BOUNDTOLEARN_RESET_STATS"] = {
        text = "Reset all BoundToLearn statistics? This cannot be undone.",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            local db = BoundToLearn.db.stats
            wipe(db.sessions)
            db.personalBest.longestCombo = 0
            db.personalBest.highestScore = 0
            db.personalBest.bestAccuracy = 0
            db.personalBest.bestKeybindRatio = 0
            db.lifetimeClicks = 0
            db.lifetimeKeybinds = 0
            db.lifetimeGameNotes = 0
            db.lifetimeGameHits = 0
            BoundToLearn:Print("Statistics reset.")
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }

    StaticPopupDialogs["BOUNDTOLEARN_RESET_DEFAULTS"] = {
        text = "Reset all BoundToLearn settings to defaults?",
        button1 = "Reset",
        button2 = "Cancel",
        OnAccept = function()
            local db = BoundToLearn.db
            db.tracker.enabled = true
            db.tracker.showWidget = true
            db.tracker.widgetScale = 1.0
            db.tracker.combatOnly = false
            db.tracker.filter.mounts = true
            db.tracker.filter.toys = true
            db.tracker.filter.hearthstones = true
            db.tracker.filter.teleports = true
            db.game.difficulty = "Medium"
            db.game.fallSpeed = 150
            db.game.fallDistance = 300
            db.game.spawnInterval = 1.5
            db.game.maxActiveNotes = 3
            db.game.timingPerfect = 0.08
            db.game.timingGreat = 0.15
            db.game.timingGood = 0.25
            db.game.soundEnabled = true
            db.game.showCombo = true
            db.options.showLoginMessage = true
            db.options.muteChat = false
            BoundToLearn:Print("Settings reset to defaults.")
            if optionsFrame and optionsFrame:IsShown() then
                optionsFrame:Hide()
                self:Toggle()
            end
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
    }
end

-- =========================================
-- Public API
-- =========================================

function Options:Toggle()
    if not optionsFrame then
        self:CreateFrame()
    end
    if optionsFrame:IsShown() then
        optionsFrame:Hide()
    else
        optionsFrame:Show()
    end
end

function Options:Show()
    if not optionsFrame then
        self:CreateFrame()
    end
    optionsFrame:Show()
end

function Options:Hide()
    if optionsFrame then optionsFrame:Hide() end
end
