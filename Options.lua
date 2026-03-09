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
local PlayUISound = Utils.PlayUISound
local SOUND_CLICK = Utils.SOUND_CLICK
local SOUND_TAB   = Utils.SOUND_TAB

local UIParent = UIParent
local wipe = wipe
local C_Spell = C_Spell
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local InCombatLockdown = InCombatLockdown

local optionsFrame
local isInitialized = false
local activeTab = "general"

local PANEL_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 16,
    insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local INNER_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 14,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function CreateThemedButton(parent, width, height, text)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:SetBackdrop(INNER_BACKDROP)
    btn:SetBackdropColor(0.12, 0.12, 0.12, 1)
    btn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("CENTER")
    label:SetText(text)
    btn.label = label

    btn:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.33, 0.8, 1, 1)
    end)
    btn:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    return btn
end

-- Collapsible section system
local HEADER_HEIGHT = 22
local SECTION_GAP = 4

local function CreateSectionHeader(parent, text)
    local header = CreateFrame("Button", nil, parent)
    header:SetHeight(HEADER_HEIGHT)

    local accent = header:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 0, 0)
    accent:SetPoint("TOPRIGHT", 0, 0)
    accent:SetHeight(1)
    accent:SetColorTexture(0.33, 0.8, 1, 0.4)

    local arrow = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    arrow:SetPoint("LEFT", 4, -3)
    arrow:SetTextColor(0.33, 0.8, 1)
    header.arrow = arrow

    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 18, -3)
    label:SetText("|cFF55CCFF" .. text .. "|r")

    header:SetScript("OnEnter", function()
        label:SetText("|cFFAAEEFF" .. text .. "|r")
    end)
    header:SetScript("OnLeave", function()
        label:SetText("|cFF55CCFF" .. text .. "|r")
    end)

    return header
end

-- Overhead: title+tabs (65) + bottom buttons (50) + padding (10)
local FRAME_OVERHEAD = 125
local MIN_FRAME_HEIGHT = 160

local function ReflowSections(sections)
    local y = 0
    for _, sec in ipairs(sections) do
        sec.header:SetPoint("TOPLEFT", 0, y)
        sec.header:SetPoint("TOPRIGHT", 0, y)
        y = y - HEADER_HEIGHT
        if sec.expanded then
            sec.content:SetPoint("TOPLEFT", 0, y)
            sec.content:SetPoint("TOPRIGHT", 0, y)
            sec.content:Show()
            y = y - sec.contentHeight
        else
            sec.content:Hide()
        end
        y = y - SECTION_GAP
        sec.header.arrow:SetText(sec.expanded and "v" or ">")
    end
    if optionsFrame then
        local h = mmax(-y + FRAME_OVERHEAD, MIN_FRAME_HEIGHT)
        optionsFrame:SetHeight(h)
    end
end

local function AddSection(sections, parent, title, contentHeight, buildFunc)
    local header = CreateSectionHeader(parent, title)
    local content = CreateFrame("Frame", nil, parent)
    content:SetHeight(contentHeight)
    content:Hide()

    local sec = {
        header = header,
        content = content,
        contentHeight = contentHeight,
        expanded = false,
    }

    header:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        sec.expanded = not sec.expanded
        ReflowSections(sections)
    end)

    tinsert(sections, sec)

    buildFunc(content)
    return sec
end

function Options:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function Options:CreateFrame()
    if optionsFrame then return end

    optionsFrame = CreateFrame("Frame", "BoundToLearnOptionsFrame", UIParent, "BackdropTemplate")
    optionsFrame:SetSize(440, 500)
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
    optionsFrame:SetScript("OnHide", function()
        if ns.ClickBlock and ns.ClickBlock:IsSelecting() then
            ns.ClickBlock:StopSelect()
        end
    end)
    tinsert(UISpecialFrames, "BoundToLearnOptionsFrame")

    local close = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = optionsFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFBoundToLearn Options|r")

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
            PlayUISound(SOUND_TAB)
            self:SetTab(t.key)
        end)

        optionsFrame.tabs[i] = tab
    end

    self:CreateGeneralPanel()
    self:CreateGamePanel()
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
    local sections = (tabKey == "general" and optionsFrame.generalSections)
        or (tabKey == "game" and optionsFrame.gameSections)
    if sections then
        ReflowSections(sections)
    end
end

-- =========================================
-- General tab
-- =========================================

function Options:CreateGeneralPanel()
    local panel = CreateFrame("Frame", nil, optionsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("TOPRIGHT", -15, -65)
    panel:SetHeight(1)
    optionsFrame.generalPanel = panel

    local sections = {}
    optionsFrame.generalSections = sections

    -- Section 1: General
    AddSection(sections, panel, "General", 72, function(content)
        local y = 0
        y = self:AddCheckbox(content, "Show Login Message", y,
            function() return BoundToLearn.db.options.showLoginMessage end,
            function(v) BoundToLearn.db.options.showLoginMessage = v end)
        y = self:AddCheckbox(content, "Mute Chat Messages", y,
            function() return BoundToLearn.db.options.muteChat end,
            function(v) BoundToLearn.db.options.muteChat = v end)
        y = self:AddCheckbox(content, "Show Minimap Button", y,
            function() return BoundToLearn.db.options.showMinimapButton end,
            function(v)
                BoundToLearn.db.options.showMinimapButton = v
                BoundToLearn:UpdateMinimapButton()
            end)
    end)

    -- Section 2: Keybind Tracker
    AddSection(sections, panel, "Keybind Tracker", 290, function(content)
        local y = 0
        y = self:AddCheckbox(content, "Enable on Login", y,
            function() return BoundToLearn.db.tracker.enabled end,
            function(v) BoundToLearn.db.tracker.enabled = v end)
        y = self:AddCheckbox(content, "Show Floating Widget", y,
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
        y = self:AddCheckbox(content, "Widget in Combat Only", y,
            function() return BoundToLearn.db.tracker.combatOnly end,
            function(v)
                BoundToLearn.db.tracker.combatOnly = v
                if v then BoundToLearn.db.tracker.hideInCombat = false end
                if ns.TrackerUI and ns.TrackerUI.widget then
                    ns.TrackerUI.widget:SetShown(
                        BoundToLearn.db.tracker.showWidget and BoundToLearn.db.tracker.enabled
                        and (not v or InCombatLockdown()))
                end
            end)
        y = self:AddCheckbox(content, "Hide Widget in Combat", y,
            function() return BoundToLearn.db.tracker.hideInCombat end,
            function(v)
                BoundToLearn.db.tracker.hideInCombat = v
                if v then BoundToLearn.db.tracker.combatOnly = false end
                if ns.TrackerUI and ns.TrackerUI.widget then
                    ns.TrackerUI.widget:SetShown(
                        BoundToLearn.db.tracker.showWidget and BoundToLearn.db.tracker.enabled
                        and (not v or not InCombatLockdown()))
                end
            end)
        y = self:AddSlider(content, "Widget Scale", 0.5, 2.0, 0.1, y,
            function() return BoundToLearn.db.tracker.widgetScale end,
            function(v)
                BoundToLearn.db.tracker.widgetScale = v
                if ns.TrackerUI and ns.TrackerUI.widget then
                    ns.TrackerUI.widget:SetScale(v)
                end
            end, function(v) return sformat("%.0f%%", v * 100) end)
        y = self:AddSlider(content, "Visible Segments", 2, 20, 1, y,
            function() return BoundToLearn.db.tracker.maxSegments end,
            function(v) BoundToLearn.db.tracker.maxSegments = v end,
            function(v) return sformat("%.0f", v) end)

        y = y - 6
        local filterLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        filterLabel:SetPoint("TOPLEFT", 14, y)
        filterLabel:SetText("Ignore in Tracker:")
        filterLabel:SetTextColor(0.55, 0.55, 0.55)
        y = y - 18

        local filterNames = {
            { key = "mounts",          label = "Mounts" },
            { key = "toys",            label = "Toys" },
            { key = "hearthstones",    label = "Hearthstones" },
            { key = "teleports",       label = "Teleports" },
            { key = "consumables",     label = "Consumables" },
            { key = "professions",     label = "Professions" },
            { key = "skyriding",       label = "Skyriding" },
            { key = "nonCombatMacros", label = "Non-combat macros" },
            { key = "buffs",           label = "Buffs (out of combat)" },
        }
        local FILTERS_PER_ROW = 3
        local FILTER_SPACING = 130
        for i, f in ipairs(filterNames) do
            local col = (i - 1) % FILTERS_PER_ROW
            local row = mfloor((i - 1) / FILTERS_PER_ROW)
            local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", col * FILTER_SPACING + 14, y - row * 28)
            cb:SetChecked(BoundToLearn.db.tracker.filter[f.key])
            local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cbText:SetText(f.label)
            local key = f.key
            cb:SetScript("OnClick", function(self)
                BoundToLearn.db.tracker.filter[key] = self:GetChecked()
            end)
        end
    end)

    -- Section 3: Click Blocking
    local updateModeState
    local modeCBs = {}
    local blacklistBox

    local function UpdateBlacklistBox()
        if not blacklistBox then return end
        blacklistBox:SetShown(BoundToLearn.db.clickBlock.mode == "custom"
            and BoundToLearn.db.clickBlock.enabled)
    end

    local function RefreshBlacklistContent()
        if not blacklistBox then return end
        local blContent = blacklistBox.content
        if blContent.rows then
            for _, row in ipairs(blContent.rows) do
                row:Hide()
            end
        end
        blContent.rows = blContent.rows or {}
        local db = BoundToLearn.db.clickBlock.customBlacklist
        local i = 0
        for spellID, spellName in pairs(db) do
            i = i + 1
            local row = blContent.rows[i]
            if not row then
                row = CreateFrame("Frame", nil, blContent)
                row:SetHeight(20)
                row:SetPoint("TOPLEFT", 2, -(i - 1) * 20)
                row:SetPoint("TOPRIGHT", -2, -(i - 1) * 20)

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(16, 16)
                icon:SetPoint("LEFT", 2, 0)
                icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                row.icon = icon

                local name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                name:SetPoint("LEFT", icon, "RIGHT", 4, 0)
                name:SetPoint("RIGHT", -20, 0)
                name:SetJustifyH("LEFT")
                row.name = name

                local removeBtn = CreateFrame("Button", nil, row)
                removeBtn:SetSize(14, 14)
                removeBtn:SetPoint("RIGHT", -2, 0)
                local removeText = removeBtn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                removeText:SetPoint("CENTER")
                removeText:SetText("X")
                removeBtn:SetScript("OnEnter", function()
                    removeText:SetTextColor(1, 0.3, 0.3)
                end)
                removeBtn:SetScript("OnLeave", function()
                    removeText:SetTextColor(0.5, 0.5, 0.5)
                end)
                row.removeBtn = removeBtn

                blContent.rows[i] = row
            end

            local tex = GetSpellTexture and GetSpellTexture(spellID)
            row.icon:SetTexture(tex or 134400)
            row.name:SetText(spellName)
            local sid = spellID
            row.removeBtn:SetScript("OnClick", function()
                BoundToLearn.db.clickBlock.customBlacklist[sid] = nil
                RefreshBlacklistContent()
                if ns.ClickBlock then ns.ClickBlock:Refresh() end
            end)
            row:Show()
        end
        blContent:SetHeight(mmax(i * 20, 1))
    end

    local function UpdateModeRadios()
        local cur = BoundToLearn.db.clickBlock.mode
        local enabled = BoundToLearn.db.clickBlock.enabled
        for _, entry in ipairs(modeCBs) do
            entry.cb:SetChecked(entry.value == cur)
            entry.cb:SetEnabled(enabled)
            entry.cb:SetAlpha(enabled and 1 or 0.4)
        end
        UpdateBlacklistBox()
        RefreshBlacklistContent()
    end

    AddSection(sections, panel, "Click Blocking", 148, function(content)
        local y = 0
        y = self:AddCheckbox(content, "Enable Click Blocking", y,
            function() return BoundToLearn.db.clickBlock.enabled end,
            function(v)
                if ns.ClickBlock then
                    if v then ns.ClickBlock:Enable() else ns.ClickBlock:Disable() end
                end
                if updateModeState then updateModeState() end
            end)

        local modeOptions = {
            { value = "all",       label = "All Abilities" },
            { value = "cc",        label = "CC + Interrupts" },
            { value = "interrupt", label = "Interrupts Only" },
            { value = "custom",    label = "Custom" },
        }

        for i, opt in ipairs(modeOptions) do
            local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
            cb:SetPoint("TOPLEFT", 26, y - (i - 1) * 24)
            local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
            cbText:SetText(opt.label)
            local val = opt.value
            cb:SetScript("OnClick", function()
                BoundToLearn.db.clickBlock.mode = val
                UpdateModeRadios()
                if ns.ClickBlock then ns.ClickBlock:Refresh() end
            end)
            tinsert(modeCBs, { cb = cb, value = val })
        end
        y = y - #modeOptions * 24

        -- Custom blacklist box (right side)
        blacklistBox = CreateFrame("Frame", nil, content, "BackdropTemplate")
        blacklistBox:SetSize(175, 120)
        blacklistBox:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, 0)
        blacklistBox:SetBackdrop(INNER_BACKDROP)
        blacklistBox:SetBackdropColor(0.08, 0.08, 0.08, 1)
        blacklistBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
        blacklistBox:Hide()

        local boxTitle = blacklistBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        boxTitle:SetPoint("TOP", 0, -6)
        boxTitle:SetText("|cFF55CCFFBlocked Spells|r")

        local blScrollFrame = CreateFrame("ScrollFrame", nil, blacklistBox, "UIPanelScrollFrameTemplate")
        blScrollFrame:SetPoint("TOPLEFT", 6, -20)
        blScrollFrame:SetPoint("BOTTOMRIGHT", -24, 30)

        local blContent = CreateFrame("Frame", nil, blScrollFrame)
        blContent:SetSize(140, 1)
        blScrollFrame:SetScrollChild(blContent)
        blacklistBox.content = blContent

        local selectBtn = CreateThemedButton(blacklistBox, 78, 22, "Select")
        selectBtn:SetPoint("BOTTOMLEFT", 6, 5)

        -- Dim overlay for the options frame (blocks interaction with dimmed controls)
        local panelDim = CreateFrame("Frame", nil, optionsFrame)
        panelDim:SetAllPoints()
        panelDim:SetFrameLevel(optionsFrame:GetFrameLevel() + 50)
        panelDim:EnableMouse(true)
        local panelDimBg = panelDim:CreateTexture(nil, "OVERLAY")
        panelDimBg:SetAllPoints()
        panelDimBg:SetColorTexture(0, 0, 0, 0.7)
        panelDim:Hide()

        -- Instruction text below the options frame
        local dimHintLine1 = panelDim:CreateFontString(nil, "OVERLAY")
        dimHintLine1:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
        dimHintLine1:SetPoint("TOP", optionsFrame, "BOTTOM", 0, -12)
        dimHintLine1:SetText("|cFF55CCFFClick the spells you want to block|r")
        local dimHintLine2 = panelDim:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dimHintLine2:SetPoint("TOP", dimHintLine1, "BOTTOM", 0, -4)
        dimHintLine2:SetText("|cFF888888Go ahead, click away.\nThis is the one time we'll allow it.|r")
        dimHintLine2:SetJustifyH("CENTER")

        -- Save original parent for reparenting during select mode
        local blacklistOrigParent = blacklistBox:GetParent()

        local function SetSelectUI(active)
            selectBtn.selectHighlight = active
            if active then
                selectBtn.label:SetText("|cFF00FF00Done|r")
                selectBtn:SetBackdropBorderColor(0.2, 1, 0.2, 1)
                optionsFrame:SetFrameStrata("TOOLTIP")
                panelDim:Show()
                -- Reparent blacklist box to optionsFrame so it sits above the dim
                local left = blacklistBox:GetLeft() - optionsFrame:GetLeft()
                local top = blacklistBox:GetTop() - optionsFrame:GetTop()
                blacklistBox:SetParent(optionsFrame)
                blacklistBox:ClearAllPoints()
                blacklistBox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", left, top)
                blacklistBox:SetFrameLevel(panelDim:GetFrameLevel() + 5)
            else
                selectBtn.label:SetText("Select")
                selectBtn:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
                optionsFrame:SetFrameStrata("DIALOG")
                panelDim:Hide()
                -- Reparent back to original content frame
                blacklistBox:SetParent(blacklistOrigParent)
                blacklistBox:ClearAllPoints()
                blacklistBox:SetPoint("TOPRIGHT", blacklistOrigParent, "TOPRIGHT", -4, 0)
                blacklistBox:SetFrameLevel(1)
            end
        end

        local function EnterSelectMode()
            ns.ClickBlock:StartSelect(
                function() RefreshBlacklistContent() end,
                function() SetSelectUI(false) end
            )
            SetSelectUI(true)
        end

        local function ExitSelectMode()
            ns.ClickBlock:StopSelect()
        end

        selectBtn:SetScript("OnClick", function()
            if InCombatLockdown() then return end
            if ns.ClickBlock then
                if ns.ClickBlock:IsSelecting() then
                    ExitSelectMode()
                else
                    EnterSelectMode()
                end
            end
        end)
        selectBtn:SetScript("OnLeave", function(self)
            if self.selectHighlight then
                self:SetBackdropBorderColor(0.2, 1, 0.2, 1)
            else
                self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
            end
        end)

        local clearBtn = CreateThemedButton(blacklistBox, 78, 22, "Clear")
        clearBtn:SetPoint("BOTTOMRIGHT", -6, 5)
        clearBtn:SetScript("OnClick", function()
            local dialog = StaticPopup_Show("BOUNDTOLEARN_CLEAR_BLACKLIST")
            if dialog and ns.ClickBlock and ns.ClickBlock:IsSelecting() then
                dialog:SetFrameStrata("TOOLTIP")
            end
        end)

        StaticPopupDialogs["BOUNDTOLEARN_CLEAR_BLACKLIST"] = {
            text = "Clear the custom spell blacklist?",
            button1 = "Clear",
            button2 = "Cancel",
            OnAccept = function()
                if ns.ClickBlock then ns.ClickBlock:ClearBlacklist() end
                RefreshBlacklistContent()
            end,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
        }
    end)

    updateModeState = UpdateModeRadios
    UpdateModeRadios()
    ReflowSections(sections)
end

-- =========================================
-- Game tab
-- =========================================

function Options:CreateGamePanel()
    local panel = CreateFrame("Frame", nil, optionsFrame)
    panel:SetPoint("TOPLEFT", 15, -65)
    panel:SetPoint("TOPRIGHT", -15, -65)
    panel:SetHeight(1)
    panel:Hide()
    optionsFrame.gamePanel = panel

    local sections = {}
    optionsFrame.gameSections = sections

    -- Section 1: Game Settings
    AddSection(sections, panel, "Game Settings", 80, function(content)
        local y = 0
        local desc = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        desc:SetPoint("TOPLEFT", 4, y)
        desc:SetPoint("TOPRIGHT", -4, y)
        desc:SetJustifyH("LEFT")
        desc:SetText("A rhythm game where spell icons fall toward your action bars. Press the correct keybind at the right time to score points.")
        desc:SetTextColor(0.6, 0.6, 0.6)
        y = y - (desc:GetStringHeight() or 24) - 8

        y = self:AddCheckbox(content, "Game Sounds", y,
            function() return BoundToLearn.db.game.soundEnabled end,
            function(v) BoundToLearn.db.game.soundEnabled = v end)
        y = self:AddCheckbox(content, "Show Combo Counter", y,
            function() return BoundToLearn.db.game.showCombo end,
            function(v) BoundToLearn.db.game.showCombo = v end)
    end)

    -- Section 2: Action Bars
    AddSection(sections, panel, "Action Bars", 94, function(content)
        local y = 0
        local barLabel = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

        for i, b in ipairs(barDefs) do
            local col = (i - 1) % 2
            local row = mfloor((i - 1) / 2)
            local cb = CreateFrame("CheckButton", nil, content, "UICheckButtonTemplate")
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
    end)

    ReflowSections(sections)
end

-- =========================================
-- Shared UI helpers
-- =========================================

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

    y = y - 4
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
-- Reset buttons
-- =========================================

function Options:CreateResetButtons()
    local resetStats = CreateThemedButton(optionsFrame, 120, 24, "Reset Stats")
    resetStats:SetPoint("BOTTOMLEFT", 20, 15)
    resetStats:SetScript("OnClick", function()
        StaticPopup_Show("BOUNDTOLEARN_RESET_STATS")
    end)

    local resetDefaults = CreateThemedButton(optionsFrame, 120, 24, "Reset Defaults")
    resetDefaults:SetPoint("BOTTOMRIGHT", -20, 15)
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
            db.tracker.hideInCombat = false
            db.tracker.filter.mounts = true
            db.tracker.filter.toys = true
            db.tracker.filter.hearthstones = true
            db.tracker.filter.teleports = true
            db.tracker.filter.consumables = true
            db.tracker.filter.professions = true
            db.tracker.filter.skyriding = true
            db.tracker.filter.nonCombatMacros = true
            db.tracker.filter.buffs = true
            db.clickBlock.enabled = false
            db.clickBlock.mode = "all"
            wipe(db.clickBlock.customBlacklist)
            if ns.ClickBlock then ns.ClickBlock:Disable() end
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

function Options:ShowTrackerSection()
    if not optionsFrame then self:CreateFrame() end
    self:SetTab("general")
    -- Expand the Keybind Tracker section (index 2)
    local sections = optionsFrame.generalSections
    if sections and sections[2] then
        sections[2].expanded = true
        ReflowSections(sections)
    end
    optionsFrame:Show()
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
