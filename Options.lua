local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local Utils     = ns.Utils
local sformat   = Utils.sformat
local mfloor    = Utils.mfloor
local mceil     = Utils.mceil
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

local function CreateThemedButton(parent, width, height, text)
    return ns.Theme.CreateButton(parent, text, width, height)
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
    accent:SetColorTexture(ns.Theme.RGB(ns.Theme.C.ACCENT, 0.4))

    local arrow = ns.Theme.CreateArrow(header, 9)
    arrow:SetPoint("LEFT", 5, -3)
    header.arrow = arrow

    local goldText = "|cFF" .. ns.Theme.GOLD_HEX .. text .. "|r"
    local hoverText = "|cFF" .. ns.Theme.CREAM_HEX .. text .. "|r"
    local label = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 18, -3)
    label:SetText(goldText)

    header:SetScript("OnEnter", function()
        label:SetText(hoverText)
    end)
    header:SetScript("OnLeave", function()
        label:SetText(goldText)
    end)

    return header
end

-- Overhead: title+tabs (65) + bottom buttons (50) + padding (10)
local FRAME_OVERHEAD = 125
local MIN_FRAME_HEIGHT = 160

-- Keep the window's TOP edge fixed while sections expand/collapse so the
-- frame grows and shrinks downward instead of jerking about its center.
local function AnchorTopFixed(h)
    local top = optionsFrame:GetTop()
    if top then
        local cx = optionsFrame:GetLeft() + optionsFrame:GetWidth() / 2
        optionsFrame:ClearAllPoints()
        optionsFrame:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx, top)
    end
    optionsFrame:SetHeight(h)
end

local function ReflowSections(sections)
    local y = 0
    for _, sec in ipairs(sections) do
        sec.header:ClearAllPoints()
        sec.header:SetPoint("TOPLEFT", 0, y)
        sec.header:SetPoint("TOPRIGHT", 0, y)
        y = y - HEADER_HEIGHT
        if sec.expanded then
            sec.content:ClearAllPoints()
            sec.content:SetPoint("TOPLEFT", 0, y)
            sec.content:SetPoint("TOPRIGHT", 0, y)
            sec.content:Show()
            y = y - sec.contentHeight
        else
            sec.content:Hide()
        end
        y = y - SECTION_GAP
        sec.header.arrow:SetDirection(sec.expanded and "down" or "right")
    end
    if optionsFrame then
        AnchorTopFixed(mmax(-y + FRAME_OVERHEAD, MIN_FRAME_HEIGHT))
    end
end

-- buildFunc returns its final (negative) y cursor; the section measures its
-- own content height from that so callers never hand-maintain a magic number.
local function AddSection(sections, parent, title, buildFunc)
    local header = CreateSectionHeader(parent, title)
    local content = CreateFrame("Frame", nil, parent)
    content:Hide()

    local sec = {
        header = header,
        content = content,
        contentHeight = 1,
        expanded = false,
    }

    header:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        sec.expanded = not sec.expanded
        ReflowSections(sections)
    end)

    tinsert(sections, sec)

    local endY = buildFunc(content) or 0
    sec.contentHeight = mmax(-endY, 1)
    content:SetHeight(sec.contentHeight)
    return sec
end

function Options:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function Options:CreateFrame()
    if optionsFrame then return end

    optionsFrame = CreateFrame("Frame", "BoundToLearnOptionsFrame", UIParent)
    optionsFrame:SetSize(440, 500)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:SetFrameStrata("DIALOG")
    ns.Theme.StylePanel(optionsFrame)
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

    local close = ns.Theme.CreateCloseButton(optionsFrame, function() optionsFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    local title = ns.Theme.CreateTitle(optionsFrame, "BoundToLearn Options", 16)
    title:SetPoint("TOP", 0, -12)

    local tabs = { { key = "general", label = "General" }, { key = "game", label = "Game" } }
    optionsFrame.tabs = {}
    for i, t in ipairs(tabs) do
        local tab = ns.Theme.CreateTab(optionsFrame, t.label)
        tab:SetSize(100, 24)
        tab:SetPoint("TOPLEFT", 15 + (i - 1) * 110, -35)
        tab.tabKey = t.key

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
        tab:SetActive(tab.tabKey == tabKey)
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
    AddSection(sections, panel, "General", function(content)
        local y = 0
        y = self:AddThemePicker(content, y)
        y = self:AddCheckbox(content, "Mute Chat Messages", y,
            function() return BoundToLearn.db.options.muteChat end,
            function(v) BoundToLearn.db.options.muteChat = v end)
        y = self:AddCheckbox(content, "Show Minimap Button", y,
            function() return BoundToLearn.db.options.showMinimapButton end,
            function(v)
                BoundToLearn.db.options.showMinimapButton = v
                BoundToLearn:UpdateMinimapButton()
            end)

        y = y - 8
        local filterNames = {
            { key = "mounts",          label = "Mounts" },
            { key = "toys",            label = "Toys" },
            { key = "hearthstones",    label = "Hearthstones" },
            { key = "teleports",       label = "Teleports" },
            { key = "consumables",     label = "Consumables" },
            { key = "professions",     label = "Professions" },
            { key = "skyriding",       label = "Skyriding" },
            { key = "nonCombatMacros", label = "Non-combat macros" },
            { key = "buffs",           label = "Buffs" },
        }
        y = self:AddGroupedGrid(content, y, "Ignore these action types:", filterNames, 3,
            function(key) return BoundToLearn.db.filter[key] end,
            function(key, v) BoundToLearn.db.filter[key] = v end)
        return y
    end)

    -- Section 2: Keybind Tracker
    AddSection(sections, panel, "Keybind Tracker", function(content)
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
        return y
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

    AddSection(sections, panel, "Click Blocking", function(content)
        local y = 0
        y = self:AddCheckbox(content, "Enable Click Blocking", y,
            function() return BoundToLearn.db.clickBlock.enabled end,
            function(v)
                if ns.ClickBlock then
                    if v then ns.ClickBlock:Enable() else ns.ClickBlock:Disable() end
                end
                if updateModeState then updateModeState() end
            end)
        y = self:AddDivider(content, y)

        local modeOptions = {
            { value = "all",       label = "All Abilities" },
            { value = "cc",        label = "CC + Interrupts" },
            { value = "interrupt", label = "Interrupts Only" },
            { value = "custom",    label = "Custom" },
        }

        for i, opt in ipairs(modeOptions) do
            local ry = y - (i - 1) * 26
            local cb = ns.Theme.CreateToggle(content, opt.label)
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", content, "TOPLEFT", 30, ry)
            cb:SetPoint("TOPRIGHT", content, "TOPRIGHT", -8, ry)
            local val = opt.value
            cb:SetScript("OnClick", function()
                BoundToLearn.db.clickBlock.mode = val
                UpdateModeRadios()
                if ns.ClickBlock then ns.ClickBlock:Refresh() end
            end)
            tinsert(modeCBs, { cb = cb, value = val })
        end
        y = y - #modeOptions * 26 - 4

        -- Custom blacklist box, below the modes (shown only in custom mode).
        local boxY = y
        blacklistBox = CreateFrame("Frame", nil, content)
        blacklistBox:SetHeight(120)
        blacklistBox.RestPosition = function(self)
            self:SetParent(content)
            self:ClearAllPoints()
            self:SetPoint("TOPLEFT", content, "TOPLEFT", 4, boxY)
            self:SetPoint("TOPRIGHT", content, "TOPRIGHT", -4, boxY)
            self:SetFrameLevel(1)
        end
        blacklistBox:RestPosition()
        ns.Theme.StyleCard(blacklistBox, ns.Theme.C.PANEL_DARK)
        blacklistBox:Hide()

        local boxTitle = blacklistBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        boxTitle:SetPoint("TOPLEFT", 8, -6)
        boxTitle:SetText("|cFF" .. ns.Theme.ACCENT_HEX .. "Blocked Spells|r")

        local blScrollFrame = CreateFrame("ScrollFrame", nil, blacklistBox, "UIPanelScrollFrameTemplate")
        blScrollFrame:SetPoint("TOPLEFT", 6, -22)
        blScrollFrame:SetPoint("BOTTOMRIGHT", -26, 30)
        ns.Theme.StyleScrollBar(blScrollFrame.ScrollBar)

        local blContent = CreateFrame("Frame", nil, blScrollFrame)
        blContent:SetSize(340, 1)
        blScrollFrame:SetScrollChild(blContent)
        blacklistBox.content = blContent

        local selectBtn = CreateThemedButton(blacklistBox, 78, 22, "Select")
        selectBtn:SetPoint("BOTTOMLEFT", 8, 6)

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
        dimHintLine1:SetText("|cFF" .. ns.Theme.ACCENT_HEX .. "Click the spells you want to block|r")
        local dimHintLine2 = panelDim:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        dimHintLine2:SetPoint("TOP", dimHintLine1, "BOTTOM", 0, -4)
        dimHintLine2:SetText("|cFF888888Go ahead, click away.\nThis is the one time we'll allow it.|r")
        dimHintLine2:SetJustifyH("CENTER")

        local function SetSelectUI(active)
            selectBtn.selectHighlight = active
            if active then
                selectBtn:SetText("|cFF" .. ns.Theme.ACCENT_HEX .. "Done|r")
                ns.Theme.SetFillColor(selectBtn, ns.Theme.C.ACCENT_DIM)
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
                selectBtn:SetText("Select")
                ns.Theme.SetFillColor(selectBtn, ns.Theme.C.BTN_NORMAL)
                optionsFrame:SetFrameStrata("DIALOG")
                panelDim:Hide()
                -- Reparent back to the content frame at its resting spot.
                blacklistBox:RestPosition()
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
                ns.Theme.SetFillColor(self, ns.Theme.C.ACCENT_DIM)
            else
                ns.Theme.SetFillColor(self, ns.Theme.C.BTN_NORMAL)
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
        return boxY - 126
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
    AddSection(sections, panel, "Game Settings", function(content)
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
        return y
    end)

    -- Section 2: Action Bars
    AddSection(sections, panel, "Action Bars", function(content)
        local barDefs = {
            { key = "main",        label = "Bar 1 (Main)" },
            { key = "bottomLeft",  label = "Bar 2" },
            { key = "bottomRight", label = "Bar 3" },
            { key = "right",       label = "Bar 4" },
            { key = "left",        label = "Bar 5" },
            { key = "bar6",        label = "Bar 6" },
            { key = "bar7",        label = "Bar 7" },
            { key = "bar8",        label = "Bar 8" },
        }
        return self:AddGroupedGrid(content, 0, "Action bars to include in the game:", barDefs, 3,
            function(key) return BoundToLearn.db.game.bars[key] end,
            function(key, v) BoundToLearn.db.game.bars[key] = v end)
    end)

    ReflowSections(sections)
end

-- =========================================
-- Shared UI helpers
-- =========================================

-- Single-column control rows span the full content width: label on the left,
-- control pinned to a shared right column. Optional indent nudges sub-options
-- (e.g. click-block modes under their master toggle) to the right.
local ROW_RIGHT = -8
local ROW_STEP = 26

function Options:AddCheckbox(parent, label, y, getter, setter, indent)
    local cb = ns.Theme.CreateToggle(parent, label)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", parent, "TOPLEFT", 14 + (indent or 0), y)
    cb:SetPoint("TOPRIGHT", parent, "TOPRIGHT", ROW_RIGHT, y)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self)
        setter(self:GetChecked())
    end)
    return y - ROW_STEP
end

function Options:AddSlider(parent, label, minVal, maxVal, step, y, getter, setter, formatFunc)
    formatFunc = formatFunc or function(v) return sformat("%.0f", v) end
    y = y - 4

    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(18)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", ROW_RIGHT, y)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
    lbl:SetText(label)

    local valText = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valText:SetPoint("RIGHT", row, "RIGHT", 0, 0)
    valText:SetJustifyH("RIGHT")
    valText:SetWidth(46)
    valText:SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_BODY))

    local slider = ns.Theme.CreateSlider(row, 150, minVal, maxVal, step)
    slider:SetPoint("RIGHT", valText, "LEFT", -8, 0)

    slider:SetValue(getter())
    valText:SetText(formatFunc(getter()))
    slider:SetScript("OnValueChanged", function(self, value)
        value = mfloor(value / step + 0.5) * step
        setter(value)
        valText:SetText(formatFunc(value))
    end)
    return y - ROW_STEP
end

-- Thin separator under a gating master toggle (or between blocks).
function Options:AddDivider(parent, y)
    local line = ns.Theme.CreateDivider(parent)
    line:SetPoint("TOPLEFT", parent, "TOPLEFT", 8, y - 2)
    line:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -8, y - 2)
    return y - 8
end

-- Related toggles wrapped in one grouped backdrop card, laid
-- out in a grid. Each cell right-aligns its own switch.
local GROUP_CARD_W = 440 - 15 * 2 - 4 * 2   -- frame width - panel inset - card inset
function Options:AddGroupedGrid(parent, y, caption, items, perRow, getState, onToggle)
    if caption then
        local cap = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cap:SetPoint("TOPLEFT", 4, y)
        cap:SetText(caption)
        cap:SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_DIM))
        y = y - 16
    end
    local PAD, CELL_H = 8, 24
    local rows = mceil(#items / perRow)
    local card = CreateFrame("Frame", nil, parent)
    card:SetPoint("TOPLEFT", 4, y)
    card:SetPoint("TOPRIGHT", -4, y)
    card:SetHeight(rows * CELL_H + PAD * 2)
    ns.Theme.StyleCard(card, ns.Theme.C.SECTION_FILL)

    local cellW = (GROUP_CARD_W - PAD * 2) / perRow
    for i, item in ipairs(items) do
        local col = (i - 1) % perRow
        local rw = mfloor((i - 1) / perRow)
        local cb = ns.Theme.CreateToggle(card, item.label, nil, cellW - 6)
        cb:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + col * cellW, -PAD - rw * CELL_H)
        cb:SetChecked(getState(item.key))
        local key = item.key
        cb:SetScript("OnClick", function(self) onToggle(key, self:GetChecked()) end)
    end
    return y - (rows * CELL_H + PAD * 2) - 6
end

StaticPopupDialogs["BOUNDTOLEARN_THEME_RELOAD"] = {
    text = "Reload your interface to apply the new color theme?",
    button1 = _G.RELOADUI or "Reload UI",
    button2 = _G.CANCEL or "Cancel",
    OnAccept = function() C_UI.Reload() end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Color theme picker: a right-aligned row of accent swatches. Picking one saves
-- the choice and prompts a reload, which applies the whole theme at once (a live
-- partial retint looks broken).
function Options:AddThemePicker(parent, y)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(20)
    row:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, y)
    row:SetPoint("TOPRIGHT", parent, "TOPRIGHT", ROW_RIGHT, y)

    local lbl = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("LEFT", row, "LEFT", 4, 0)
    lbl:SetText("Color Theme")
    lbl:SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_PRIMARY))

    local order = ns.Theme.THEME_ORDER
    local n = #order
    local SIZE, GAP = 16, 6
    local swatches = {}
    local function refreshSel()
        local cur = BoundToLearn.db.options.colorTheme
        for i = 1, n do
            local sw = swatches[i]
            sw.underline:SetShown(sw.themeName == cur)
            sw:SetAlpha(sw.themeName == cur and 1 or 0.6)
        end
    end
    for i = n, 1, -1 do
        local name = order[i]
        local ac = ns.Theme.THEMES[name][1]
        local sw = CreateFrame("Button", nil, row)
        sw.themeName = name
        sw:SetSize(SIZE, SIZE)
        sw:SetPoint("RIGHT", row, "RIGHT", -(n - i) * (SIZE + GAP), 0)
        ns.Theme.Round(sw)
        ns.Theme.SetBarHeight(sw, SIZE)
        ns.Theme.SetBorderShown(sw, false)
        ns.Theme.SetFillColor(sw, ac)
        local underline = sw:CreateTexture(nil, "OVERLAY")
        underline:SetHeight(2)
        underline:SetPoint("TOPLEFT", sw, "BOTTOMLEFT", 0, -2)
        underline:SetPoint("TOPRIGHT", sw, "BOTTOMRIGHT", 0, -2)
        underline:SetColorTexture(0.95, 0.95, 0.95, 1)
        underline:Hide()
        sw.underline = underline
        ns.Theme.AttachTooltip(sw, name, "Use the " .. name .. " color theme.")
        sw:SetScript("OnClick", function()
            if BoundToLearn.db.options.colorTheme == name then return end
            BoundToLearn.db.options.colorTheme = name
            refreshSel()
            -- Do not retint live: applying only part of the UI looks broken. Save
            -- the choice and let the reload apply the whole theme at once.
            StaticPopup_Show("BOUNDTOLEARN_THEME_RELOAD")
        end)
        swatches[i] = sw
    end
    refreshSel()

    return y - 24
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
            db.filter.mounts = true
            db.filter.toys = true
            db.filter.hearthstones = true
            db.filter.teleports = true
            db.filter.consumables = true
            db.filter.professions = true
            db.filter.skyriding = true
            db.filter.nonCombatMacros = true
            db.filter.buffs = true
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
