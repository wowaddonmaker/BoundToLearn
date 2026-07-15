local ADDON_NAME, ns = ...

local Options = {}
ns.Options = Options

local Theme     = ns.Theme
local Utils     = ns.Utils
local sformat   = Utils.sformat
local mfloor    = Utils.mfloor
local mceil     = Utils.mceil
local mmax      = Utils.mmax
local tinsert   = Utils.tinsert
local pairs     = Utils.pairs
local CreateFrame = Utils.CreateFrame

local UIParent = UIParent
local wipe = wipe
local C_Spell = C_Spell
local GetSpellTexture = C_Spell and C_Spell.GetSpellTexture
local InCombatLockdown = InCombatLockdown
local StaticPopupDialogs = StaticPopupDialogs
local StaticPopup_Show = StaticPopup_Show

local C = Theme.C

-- Fixed-size sidebar window. WINDOW_H is sized so the tallest tab (General,
-- with the click-block block and its 120px blacklist card in custom mode)
-- fits above the bottom reset buttons. The content column width is derived
-- from the window and sidebar so nothing drifts.
local WINDOW_W     = 544
local WINDOW_H     = 508
local PANEL_SCALE  = 0.9
local FRAME_STRATA = "FULLSCREEN_DIALOG"
local FRAME_LEVEL  = 700
local SIDEBAR_W    = 132
local CONTENT_TOP  = 46
local CONTENT_RIGHT = 14
local CONTENT_W    = WINDOW_W - (SIDEBAR_W + 32) - CONTENT_RIGHT
local BTN_W        = 170

-- Support links. Bug/feature open the GitHub issue forms (see
-- .github/ISSUE_TEMPLATE); the repo must be public for players to use them.
local URL_HOMEPAGE    = "https://www.curseforge.com/wow/addons/boundtolearn"
local URL_BUG_REPORT  = "https://github.com/wowaddonmaker/BoundToLearn/issues/new?template=bug_report.yml"
local URL_FEATURE_REQ = "https://github.com/wowaddonmaker/BoundToLearn/issues/new?template=feature_request.yml"

local optionsFrame
local nav
local isInitialized = false
local blizzardRegistered = false
local trackerTabIndex
local homeTabIndex
local feedbackTabIndex
local resetGroup
local blacklistBox
local RefreshBlacklistContent
local refreshers = {}

-- =========================================
-- Shared refresh / gating
-- =========================================

local function UpdateBlacklistVisibility()
    if not blacklistBox then return end
    local show = BoundToLearn.db.clickBlock.mode == "custom"
        and BoundToLearn.db.clickBlock.enabled
    blacklistBox:SetShown(show)
end

-- Re-read every control from the DB. Runs on show and after a reset so the
-- widgets always reflect the live values.
local function SyncControls()
    for i = 1, #refreshers do refreshers[i]() end
    if RefreshBlacklistContent then RefreshBlacklistContent() end
    UpdateBlacklistVisibility()
end

-- =========================================
-- Row builders (top-down layout within a tab)
-- =========================================

local function AddCheckbox(tab, y, label, getter, setter)
    local cb = Theme.CreateToggle(tab, label)
    cb:ClearAllPoints()
    cb:SetPoint("TOPLEFT", tab, "TOPLEFT", 6, y)
    cb:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -6, y)
    cb:SetChecked(getter())
    cb:SetScript("OnClick", function(self) setter(self:GetChecked()) end)
    refreshers[#refreshers + 1] = function() cb:SetChecked(getter()) end
    return cb, y - 28
end

local function AddDivider(tab, y)
    local line = Theme.CreateDivider(tab)
    line:ClearAllPoints()
    line:SetPoint("TOPLEFT", tab, "TOPLEFT", 8, y - 2)
    line:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -8, y - 2)
    return y - 10
end

local function AddFlyoutRow(tab, y, label, choices, getter, setter, opts)
    opts = opts or {}
    opts.width = CONTENT_W
    opts.btnWidth = BTN_W
    local row = Theme.CreateFlyoutRow(tab, label, choices, getter, setter, opts)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, y)
    refreshers[#refreshers + 1] = function() row:SetValue(getter()) end
    return row, y - 28
end

local function AddStepper(tab, y, label, minV, maxV, getter, setter, opts)
    local row = Theme.CreateStepperRow(tab, label, minV, maxV, getter, setter, opts)
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y)
    row:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, y)
    refreshers[#refreshers + 1] = function() row:SetValue(getter()) end
    return row, y - 30
end

-- Related toggles wrapped in one grouped card, laid out in a grid. Each
-- cell right-aligns its own switch.
local GRID_CELL_H = 24
local function AddGrid(tab, y, caption, items, perRow, getState, onToggle)
    if caption then
        local cap = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cap:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, y)
        cap:SetText(caption)
        cap:SetTextColor(Theme.RGB(C.TEXT_DIM))
        y = y - 16
    end
    local PAD = 8
    local rowCount = mceil(#items / perRow)
    local card = Theme.CreateSettingsGroup(tab, CONTENT_W, rowCount * GRID_CELL_H + PAD * 2)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, y)
    card:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, y)
    local cellW = (CONTENT_W - PAD * 2) / perRow
    for i = 1, #items do
        local item = items[i]
        local col = (i - 1) % perRow
        local rowIdx = mfloor((i - 1) / perRow)
        local cell = Theme.CreateToggle(card, item.label, nil, cellW - 6)
        cell:SetPoint("TOPLEFT", card, "TOPLEFT", PAD + col * cellW, -PAD - rowIdx * GRID_CELL_H)
        cell:SetChecked(getState(item.key))
        local key = item.key
        cell:SetScript("OnClick", function(self) onToggle(key, self:GetChecked()) end)
        refreshers[#refreshers + 1] = function() cell:SetChecked(getState(key)) end
    end
    return y - (rowCount * GRID_CELL_H + PAD * 2) - 6
end

-- Read-only rounded editbox showing a link the user can select and copy. The
-- text resets to the stored link on any change so it cannot be typed into;
-- focusing it selects the link for Ctrl+C. shell:SetURL swaps the link so one
-- box can be reused for different destinations.
local function CreateURLBox(parent, url, width)
    local shell = CreateFrame("Frame", nil, parent)
    shell:SetSize(width, 20)
    Theme.Round(shell)
    Theme.SetBarHeight(shell, 10)
    Theme.SetBorderShown(shell, false)
    Theme.SetFillColor(shell, C.INSET_FILL)

    local box = CreateFrame("EditBox", nil, shell)
    box:SetPoint("TOPLEFT", shell, "TOPLEFT", 8, 0)
    box:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -8, 0)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextColor(0.92, 0.92, 0.92, 1)
    box._url = url
    box:SetText(url)
    box:SetCursorPosition(0)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    box:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    box:SetScript("OnTextChanged", function(self) self:SetText(self._url); self:SetCursorPosition(0) end)
    shell.editBox = box
    shell.SetURL = function(_, u)
        box._url = u
        box:SetText(u)
        box:SetCursorPosition(0)
    end
    return shell
end

-- Convert an RGB color table to a |cFF hex string (for inline colored text).
local function ColorToHex(c)
    return sformat("%02X%02X%02X", mfloor(c[1] * 255 + 0.5), mfloor(c[2] * 255 + 0.5), mfloor(c[3] * 255 + 0.5))
end

-- One reusable themed copy-link dialog, shared by every link button. It sits
-- on the same strata as the options window but at a much higher frame level,
-- so it draws above all window content and any open flyout dropdown.
local linkDialog
local function ShowLinkDialog(title, url)
    if not linkDialog then
        linkDialog = CreateFrame("Frame", "BoundToLearnLinkDialog", optionsFrame)
        linkDialog:SetSize(340, 128)
        linkDialog:SetPoint("CENTER", optionsFrame, "CENTER", 0, 30)
        linkDialog:SetFrameStrata(FRAME_STRATA)
        linkDialog:SetToplevel(true)
        Theme.StylePanel(linkDialog)
        linkDialog:EnableMouse(true)
        tinsert(UISpecialFrames, "BoundToLearnLinkDialog")

        local titleFS = Theme.CreateTitle(linkDialog, "", 15)
        titleFS:SetPoint("TOP", 0, -14)
        linkDialog.titleFS = titleFS

        local hint = linkDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("TOP", titleFS, "BOTTOM", 0, -8)
        hint:SetText("Select the link and press Ctrl+C to copy.")
        hint:SetTextColor(Theme.RGB(C.TEXT_DIM, 1))

        local box = CreateURLBox(linkDialog, url, 300)
        box:ClearAllPoints()
        box:SetPoint("TOP", hint, "BOTTOM", 0, -12)
        linkDialog.urlBox = box

        local okBtn = Theme.CreateButton(linkDialog, _G["CLOSE"] or "Close", 110, 24)
        okBtn:SetPoint("BOTTOM", 0, 14)
        okBtn:SetScript("OnClick", function() linkDialog:Hide() end)

        local close = Theme.CreateCloseButton(linkDialog, function() linkDialog:Hide() end)
        close:SetPoint("TOPRIGHT", -8, -8)
    end

    linkDialog.titleFS:SetText(title or "")
    linkDialog.urlBox:SetURL(url)
    linkDialog:SetFrameStrata(FRAME_STRATA)
    linkDialog:SetFrameLevel((optionsFrame and optionsFrame:GetFrameLevel() or FRAME_LEVEL) + 100)
    linkDialog:Show()
    linkDialog:Raise()
    linkDialog.urlBox.editBox:SetFocus()
    linkDialog.urlBox.editBox:HighlightText()
end

-- =========================================
-- Custom blacklist card (Click Blocking block)
-- =========================================

local function BuildBlacklistCard(tab, boxY)
    blacklistBox = CreateFrame("Frame", nil, tab)
    blacklistBox:SetHeight(120)
    blacklistBox.RestPosition = function(self)
        self:SetParent(tab)
        self:ClearAllPoints()
        self:SetPoint("TOPLEFT", tab, "TOPLEFT", 0, boxY)
        self:SetPoint("TOPRIGHT", tab, "TOPRIGHT", 0, boxY)
        self:SetFrameLevel(1)
    end
    blacklistBox:RestPosition()
    Theme.StyleCard(blacklistBox, C.PANEL_DARK)
    blacklistBox:Hide()

    local boxTitle = blacklistBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boxTitle:SetPoint("TOPLEFT", 8, -6)
    local function applyBoxTitle() boxTitle:SetText("|cFF" .. Theme.ACCENT_HEX .. "Blocked Spells|r") end
    applyBoxTitle()
    Theme.RegisterRetinter(applyBoxTitle)

    local scroll = CreateFrame("ScrollFrame", nil, blacklistBox, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -22)
    scroll:SetPoint("BOTTOMRIGHT", -26, 30)
    Theme.StyleScrollBar(scroll.ScrollBar)

    local blContent = CreateFrame("Frame", nil, scroll)
    blContent:SetSize(320, 1)
    scroll:SetScrollChild(blContent)
    blacklistBox.content = blContent

    RefreshBlacklistContent = function()
        local rows = blContent.rows
        if rows then
            for i = 1, #rows do rows[i]:Hide() end
        end
        rows = rows or {}
        blContent.rows = rows
        local db = BoundToLearn.db.clickBlock.customBlacklist
        local i = 0
        for spellID, spellName in pairs(db) do
            i = i + 1
            local row = rows[i]
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
                removeBtn:SetScript("OnEnter", function() removeText:SetTextColor(1, 0.3, 0.3) end)
                removeBtn:SetScript("OnLeave", function() removeText:SetTextColor(0.5, 0.5, 0.5) end)
                row.removeBtn = removeBtn

                rows[i] = row
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

    local selectBtn = Theme.CreateButton(blacklistBox, "Select", 78, 22)
    selectBtn:SetPoint("BOTTOMLEFT", 8, 6)

    -- Dim overlay for the options frame (blocks interaction with dimmed controls).
    local panelDim = CreateFrame("Frame", nil, optionsFrame)
    panelDim:SetAllPoints()
    panelDim:SetFrameLevel(optionsFrame:GetFrameLevel() + 50)
    panelDim:EnableMouse(true)
    local panelDimBg = panelDim:CreateTexture(nil, "OVERLAY")
    panelDimBg:SetAllPoints()
    panelDimBg:SetColorTexture(0, 0, 0, 0.7)
    panelDim:Hide()

    local dimHintLine1 = panelDim:CreateFontString(nil, "OVERLAY")
    dimHintLine1:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    dimHintLine1:SetPoint("TOP", optionsFrame, "BOTTOM", 0, -12)
    local function applyDimHint() dimHintLine1:SetText("|cFF" .. Theme.ACCENT_HEX .. "Click the spells you want to block|r") end
    applyDimHint()
    Theme.RegisterRetinter(applyDimHint)
    local dimHintLine2 = panelDim:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    dimHintLine2:SetPoint("TOP", dimHintLine1, "BOTTOM", 0, -4)
    dimHintLine2:SetText("|cFF888888Go ahead, click away.\nThis is the one time we'll allow it.|r")
    dimHintLine2:SetJustifyH("CENTER")

    local function SetSelectUI(active)
        selectBtn.selectHighlight = active
        if active then
            selectBtn:SetText("|cFF" .. Theme.ACCENT_HEX .. "Done|r")
            Theme.SetFillColor(selectBtn, C.ACCENT_DIM)
            optionsFrame:SetFrameStrata("TOOLTIP")
            panelDim:Show()
            -- Reparent the blacklist box above the dim so it stays interactive.
            local left = blacklistBox:GetLeft() - optionsFrame:GetLeft()
            local top = blacklistBox:GetTop() - optionsFrame:GetTop()
            blacklistBox:SetParent(optionsFrame)
            blacklistBox:ClearAllPoints()
            blacklistBox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", left, top)
            blacklistBox:SetFrameLevel(panelDim:GetFrameLevel() + 5)
        else
            selectBtn:SetText("Select")
            Theme.SetFillColor(selectBtn, C.BTN_NORMAL)
            optionsFrame:SetFrameStrata(FRAME_STRATA)
            panelDim:Hide()
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
            Theme.SetFillColor(self, C.ACCENT_DIM)
        else
            Theme.SetFillColor(self, C.BTN_NORMAL)
        end
    end)

    local clearBtn = Theme.CreateButton(blacklistBox, "Clear", 78, 22)
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

    RefreshBlacklistContent()
end

-- The click-block block appended to the bottom of the General tab: master
-- toggle, divider, mode dropdown, and the custom blacklist card.
local function AppendClickBlock(tab, y)
    local _
    _, y = AddCheckbox(tab, y, "Enable Click Blocking",
        function() return BoundToLearn.db.clickBlock.enabled end,
        function(v)
            if ns.ClickBlock then
                if v then ns.ClickBlock:Enable() else ns.ClickBlock:Disable() end
            end
            UpdateBlacklistVisibility()
        end)
    y = AddDivider(tab, y)

    local modeChoices = {
        { label = "All Abilities",   value = "all" },
        { label = "CC + Interrupts", value = "cc" },
        { label = "Interrupts Only", value = "interrupt" },
        { label = "Custom",          value = "custom" },
    }
    _, y = AddFlyoutRow(tab, y, "Block Mode", modeChoices,
        function() return BoundToLearn.db.clickBlock.mode end,
        function(v)
            BoundToLearn.db.clickBlock.mode = v
            if ns.ClickBlock then ns.ClickBlock:Refresh() end
            UpdateBlacklistVisibility()
        end)

    y = y - 4
    BuildBlacklistCard(tab, y)
    UpdateBlacklistVisibility()
end

-- =========================================
-- Tabs
-- =========================================

local function BuildHomeTab()
    local tab = nav:AddTab("Home")
    homeTabIndex = #nav.tabs

    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(80, 80)
    icon:SetPoint("TOPLEFT", tab, "TOPLEFT", 12, -8)
    icon:SetTexture("Interface\\MacroFrame\\MacroFrame-Icon")

    local title = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    local titlePath, _, titleFlags = title:GetFont()
    if titlePath then title:SetFont(titlePath, 28, titleFlags) end
    title:SetPoint("LEFT", icon, "RIGHT", 14, 6)
    title:SetText("BoundToLearn")
    title:SetTextColor(Theme.RGB(C.TEXT_PRIMARY, 1))

    local version = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    version:SetPoint("BOTTOMLEFT", title, "BOTTOMRIGHT", 6, 2)
    version:SetText("v" .. (ns.version or ""))
    version:SetTextColor(0.53, 0.53, 0.53, 1)

    local desc = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", icon, "BOTTOMLEFT", 0, -20)
    desc:SetPoint("RIGHT", tab, "RIGHT", -12, 0)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(3)
    local function applyDescText()
        desc:SetText("Build muscle memory for your keybinds. The tracker shows how often "
            .. "you click versus press your abilities. When you are ready to practice, "
            .. "play the Icon Game (a falling-note rhythm challenge), warm up your "
            .. "reflexes in the Ping Trainer, test your recall with the Keybind Quiz, "
            .. "or review your bars with the Keybind Audit. Type |cFF"
            .. Theme.ACCENT_HEX .. "/btl|r for all commands, or right-click the "
            .. "minimap button.")
    end
    applyDescText()
    Theme.RegisterRetinter(applyDescText)

    local urlLabel = tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    urlLabel:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    urlLabel:SetText("Homepage")
    urlLabel:SetTextColor(Theme.RGB(C.GOLD, 1))

    local urlBox = CreateURLBox(tab, URL_HOMEPAGE, CONTENT_W - 8)
    urlBox:SetPoint("TOPLEFT", urlLabel, "BOTTOMLEFT", 0, -4)

    -- Cross-promo for the author's other addon. The link target is hidden
    -- behind the clickable word (opens the copy-link popup) so the Home tab
    -- does not read as a wall of URLs. This is the one sanctioned place the
    -- other addon is named by request; the inline word is the click target.
    local promo = CreateFrame("Frame", nil, tab)
    promo:SetPoint("TOPLEFT", urlBox, "BOTTOMLEFT", 0, -18)
    promo:SetPoint("RIGHT", tab, "RIGHT", -12, 0)
    promo:SetHeight(52)
    promo:EnableMouse(true)
    promo:SetHyperlinksEnabled(true)

    local promoText = promo:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    promoText:SetPoint("TOPLEFT", promo, "TOPLEFT", 0, 0)
    promoText:SetPoint("RIGHT", promo, "RIGHT", 0, 0)
    promoText:SetJustifyH("LEFT")
    promoText:SetSpacing(3)
    promoText:SetTextColor(Theme.RGB(C.TEXT_DIM, 1))

    local PROMO_URL = "https://www.curseforge.com/wow/addons/easyfind"
    local promoHover = false
    local function applyPromo()
        -- Brighten the clickable word on hover; base accent otherwise.
        local hex = promoHover and ColorToHex(C.ACCENT_BRIGHT) or Theme.ACCENT_HEX
        promoText:SetText("If you enjoy BoundToLearn, you might also like another addon "
            .. "I made: |Hbtl_promo:link|h|cFF" .. hex .. "EasyFind|r|h. "
            .. "It lets you instantly search for and jump to any interface panel, "
            .. "setting, or map location.")
    end
    applyPromo()
    Theme.RegisterRetinter(applyPromo)
    promo:SetHeight((promoText:GetStringHeight() or 48) + 2)

    promo:SetScript("OnHyperlinkClick", function(_, link)
        if link == "btl_promo:link" then
            ShowLinkDialog("Open on CurseForge", PROMO_URL)
        end
    end)
    promo:SetScript("OnHyperlinkEnter", function(self, link)
        if link ~= "btl_promo:link" then return end
        promoHover = true
        applyPromo()
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Open on CurseForge", 1, 0.82, 0)
        GameTooltip:Show()
    end)
    promo:SetScript("OnHyperlinkLeave", function()
        promoHover = false
        applyPromo()
        GameTooltip:Hide()
    end)

    -- Thanks line at the window bottom-right, mirroring the reference. The
    -- reset buttons are hidden on this tab, so it sits at the corner.
    local thanks = tab:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    thanks:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -6, 8)
    thanks:SetText("Thanks for trying BoundToLearn!")
    thanks:SetTextColor(Theme.RGB(C.TEXT_DIM, 1))
end

local function BuildGeneralTab()
    local tab = nav:AddTab("General")
    local y = -6
    local _

    local themeChoices = {}
    for i = 1, #Theme.THEME_ORDER do
        local name = Theme.THEME_ORDER[i]
        themeChoices[i] = { label = name, value = name }
    end
    _, y = AddFlyoutRow(tab, y, "Color Theme", themeChoices,
        function() return BoundToLearn.db.options.colorTheme end,
        function(value)
            if BoundToLearn.db.options.colorTheme == value then return end
            BoundToLearn.db.options.colorTheme = value
            -- Apply immediately: ApplyTheme mutates the palette and re-runs the
            -- registered retinters, so the open window recolors with no reload.
            if Theme.ApplyTheme then Theme.ApplyTheme(value) end
        end,
        {
            -- Closed selector shows a dot in the active accent.
            swatch = function(value)
                local preset = Theme.THEMES[value]
                return preset and preset[1] or nil
            end,
            -- Each flyout row shows its own accent dot.
            styleFn = function(optBtn, choice, lbl)
                local preset = Theme.THEMES[choice.value]
                if not preset then return end
                local dot = CreateFrame("Frame", nil, optBtn)
                dot:SetSize(12, 12)
                dot:SetPoint("RIGHT", optBtn, "RIGHT", -6, 0)
                Theme.Round(dot)
                Theme.SetBarHeight(dot, 12)
                Theme.SetBorderShown(dot, false)
                Theme.SetFillColor(dot, preset[1])
                lbl:SetPoint("RIGHT", optBtn, "RIGHT", -22, 0)
                optBtn._rightIconW = 12 + 8
            end,
        })

    _, y = AddCheckbox(tab, y, "Mute Chat Messages",
        function() return BoundToLearn.db.options.muteChat end,
        function(v) BoundToLearn.db.options.muteChat = v end)
    _, y = AddCheckbox(tab, y, "Show Minimap Button",
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
    y = AddGrid(tab, y, "Ignore these action types:", filterNames, 3,
        function(key) return BoundToLearn.db.filter[key] end,
        function(key, v) BoundToLearn.db.filter[key] = v end)

    AppendClickBlock(tab, y)
end

local function BuildTrackerTab()
    local tab = nav:AddTab("Keybind Tracker")
    trackerTabIndex = #nav.tabs
    local y = -6
    local _

    _, y = AddCheckbox(tab, y, "Enable on Login",
        function() return BoundToLearn.db.tracker.enabled end,
        function(v) BoundToLearn.db.tracker.enabled = v end)
    _, y = AddCheckbox(tab, y, "Show Floating Widget",
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
    _, y = AddCheckbox(tab, y, "Widget in Combat Only",
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
    _, y = AddCheckbox(tab, y, "Hide Widget in Combat",
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

    local scaleChoices = {
        { label = "50%",  value = 0.5  },
        { label = "75%",  value = 0.75 },
        { label = "100%", value = 1.0  },
        { label = "125%", value = 1.25 },
        { label = "150%", value = 1.5  },
        { label = "200%", value = 2.0  },
    }
    _, y = AddFlyoutRow(tab, y, "Widget Scale", scaleChoices,
        function() return BoundToLearn.db.tracker.widgetScale end,
        function(v)
            BoundToLearn.db.tracker.widgetScale = v
            if ns.TrackerUI and ns.TrackerUI.widget then
                ns.TrackerUI.widget:SetScale(v)
            end
        end,
        { format = function(v) return sformat("%.0f%%", v * 100) end })

    _, y = AddStepper(tab, y, "Visible Segments", 2, 20,
        function() return BoundToLearn.db.tracker.maxSegments end,
        function(v) BoundToLearn.db.tracker.maxSegments = v end)
end

local function BuildGameTab()
    local tab = nav:AddTab("Game")
    local y = -6
    local _

    local desc = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", tab, "TOPLEFT", 4, y)
    desc:SetPoint("TOPRIGHT", tab, "TOPRIGHT", -4, y)
    desc:SetJustifyH("LEFT")
    desc:SetText("A rhythm game where spell icons fall toward your action bars. Press the correct keybind at the right time to score points.")
    desc:SetTextColor(0.6, 0.6, 0.6)
    y = y - (desc:GetStringHeight() or 24) - 8

    _, y = AddCheckbox(tab, y, "Game Sounds",
        function() return BoundToLearn.db.game.soundEnabled end,
        function(v) BoundToLearn.db.game.soundEnabled = v end)
    _, y = AddCheckbox(tab, y, "Show Combo Counter",
        function() return BoundToLearn.db.game.showCombo end,
        function(v) BoundToLearn.db.game.showCombo = v end)

    y = y - 8
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
    AddGrid(tab, y, "Action bars to include in the game:", barDefs, 3,
        function(key) return BoundToLearn.db.game.bars[key] end,
        function(key, v) BoundToLearn.db.game.bars[key] = v end)
end

local function BuildFeedbackTab()
    local tab = nav:AddTab("Feedback")
    feedbackTabIndex = #nav.tabs

    local desc = tab:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", tab, "TOPLEFT", 12, -16)
    desc:SetPoint("RIGHT", tab, "RIGHT", -12, 0)
    desc:SetJustifyH("LEFT")
    desc:SetSpacing(3)
    desc:SetText("Found a bug or have an idea? Your feedback shapes what gets built next. Use the links below.")

    local bugBtn = Theme.CreateButton(tab, "Report a Bug", 120, 20)
    bugBtn:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -14)
    bugBtn:SetScript("OnClick", function()
        ShowLinkDialog("Report a Bug", URL_BUG_REPORT)
    end)

    local featureBtn = Theme.CreateButton(tab, "Request a Feature", 140, 20)
    featureBtn:SetPoint("LEFT", bugBtn, "RIGHT", 12, 0)
    featureBtn:SetScript("OnClick", function()
        ShowLinkDialog("Request a Feature", URL_FEATURE_REQ)
    end)
end

local function BuildResetButtons()
    -- A grouped pair centered along the window bottom. Shown only on the
    -- setting tabs (SwitchToTab toggles the group; see BuildFrame).
    resetGroup = CreateFrame("Frame", nil, optionsFrame)
    resetGroup:SetSize(248, 24)   -- 120 + 8 gap + 120
    resetGroup:SetPoint("BOTTOM", nav.content, "BOTTOM", 0, 0)

    local resetStats = Theme.CreateButton(resetGroup, "Reset Stats", 120, 24)
    resetStats:SetPoint("LEFT", resetGroup, "LEFT", 0, 0)
    resetStats:SetScript("OnClick", function()
        StaticPopup_Show("BOUNDTOLEARN_RESET_STATS")
    end)

    local resetDefaults = Theme.CreateButton(resetGroup, "Reset Defaults", 120, 24)
    resetDefaults:SetPoint("LEFT", resetStats, "RIGHT", 8, 0)
    resetDefaults:SetScript("OnClick", function()
        StaticPopup_Show("BOUNDTOLEARN_RESET_DEFAULTS")
    end)
end

-- =========================================
-- Frame assembly
-- =========================================

local function BuildFrame()
    if optionsFrame then return end

    optionsFrame = CreateFrame("Frame", "BoundToLearnOptionsFrame", UIParent, "BackdropTemplate")
    ns.optionsFrame = optionsFrame
    optionsFrame:SetSize(WINDOW_W, WINDOW_H)
    optionsFrame:SetScale(PANEL_SCALE)
    optionsFrame:SetPoint("CENTER")
    optionsFrame:SetFrameStrata(FRAME_STRATA)
    optionsFrame:SetFrameLevel(FRAME_LEVEL)
    Theme.StylePanel(optionsFrame)
    optionsFrame:EnableMouse(true)
    optionsFrame:SetMovable(true)
    optionsFrame:SetClampedToScreen(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:SetScript("OnDragStart", optionsFrame.StartMoving)
    optionsFrame:SetScript("OnDragStop", optionsFrame.StopMovingOrSizing)
    optionsFrame:SetScript("OnHide", function()
        if ns.ClickBlock and ns.ClickBlock:IsSelecting() then
            ns.ClickBlock:StopSelect()
        end
    end)
    tinsert(UISpecialFrames, "BoundToLearnOptionsFrame")

    local close = Theme.CreateCloseButton(optionsFrame, function() optionsFrame:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    optionsFrame.closeBtn = close

    nav = Theme.CreateSidebar(optionsFrame, {
        width = SIDEBAR_W,
        contentTopInset = CONTENT_TOP,
        contentRightInset = CONTENT_RIGHT,
        title = "BoundToLearn",
    })
    optionsFrame.nav = nav

    -- The reset pair belongs to the setting tabs only; hide it on Home and
    -- Feedback by toggling the shared group whenever the tab changes.
    local baseSwitch = nav.SwitchToTab
    nav.SwitchToTab = function(self, index)
        baseSwitch(self, index)
        if resetGroup then
            resetGroup:SetShown(index ~= homeTabIndex and index ~= feedbackTabIndex)
        end
    end

    BuildHomeTab()
    BuildGeneralTab()
    BuildTrackerTab()
    BuildGameTab()
    BuildFeedbackTab()
    BuildResetButtons()

    nav:SwitchToTab(1)
    optionsFrame:Hide()
end

local function EnsureFrame()
    if not optionsFrame then BuildFrame() end
end

-- =========================================
-- Public API
-- =========================================

function Options:Initialize()
    if isInitialized then return end
    isInitialized = true
    self:RegisterWithBlizzardOptions()
end

function Options:RegisterWithBlizzardOptions()
    if blizzardRegistered then return end
    blizzardRegistered = true

    local panel = CreateFrame("Frame")
    panel.name = "BoundToLearn"

    panel:SetScript("OnShow", function(self)
        EnsureFrame()
        Options.embedded = true
        Options.embedding = true

        optionsFrame.closeBtn:Hide()
        optionsFrame:SetScale(1)
        optionsFrame:SetParent(self)
        optionsFrame:ClearAllPoints()
        optionsFrame:SetPoint("TOPLEFT", self, "TOPLEFT", 0, -10)
        optionsFrame:SetFrameStrata("HIGH")
        optionsFrame:SetMovable(false)
        optionsFrame:RegisterForDrag()

        Options:Show()
        Options.embedding = false
    end)

    panel:SetScript("OnHide", function()
        if not Options.embedded then return end
        Options:RestoreStandalone()
        optionsFrame:Hide()
    end)

    if Settings and Settings.RegisterCanvasLayoutCategory then
        local category = Settings.RegisterCanvasLayoutCategory(panel, panel.name)
        Settings.RegisterAddOnCategory(category)
    elseif InterfaceOptions_AddCategory then
        InterfaceOptions_AddCategory(panel)
    end
end

function Options:RestoreStandalone()
    self.embedded = false
    if not optionsFrame then return end

    optionsFrame.closeBtn:Show()
    optionsFrame:SetScale(PANEL_SCALE)
    optionsFrame:SetParent(UIParent)
    optionsFrame:SetFrameStrata(FRAME_STRATA)
    optionsFrame:SetFrameLevel(FRAME_LEVEL)
    optionsFrame:SetMovable(true)
    optionsFrame:RegisterForDrag("LeftButton")
    optionsFrame:ClearAllPoints()
    optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
end

function Options:Show()
    EnsureFrame()
    if self.embedded and not self.embedding then
        self:RestoreStandalone()
    end
    if not self.embedded then
        optionsFrame:SetFrameStrata(FRAME_STRATA)
        optionsFrame:SetFrameLevel(FRAME_LEVEL)
    end
    SyncControls()
    optionsFrame:Show()
    optionsFrame:Raise()
end

function Options:Hide()
    if optionsFrame then optionsFrame:Hide() end
end

function Options:Toggle()
    EnsureFrame()
    if self.embedded then
        self:RestoreStandalone()
        self:Show()
        return
    end
    if optionsFrame:IsShown() then
        self:Hide()
    else
        self:Show()
    end
end

function Options:ShowTrackerSection()
    EnsureFrame()
    if self.embedded then self:RestoreStandalone() end
    if not self.embedded then
        optionsFrame:SetFrameStrata(FRAME_STRATA)
        optionsFrame:SetFrameLevel(FRAME_LEVEL)
    end
    SyncControls()
    if nav and trackerTabIndex then nav:SwitchToTab(trackerTabIndex) end
    optionsFrame:Show()
    optionsFrame:Raise()
end

-- =========================================
-- Static popups
-- =========================================

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
        SyncControls()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}
