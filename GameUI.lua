local ADDON_NAME, ns = ...

local GameUI = {}
ns.GameUI = GameUI

local Utils      = ns.Utils
local Theme      = ns.Theme
local sformat    = Utils.sformat
local mmin, mmax = Utils.mmin, Utils.mmax
local mabs       = Utils.mabs
local mfloor     = Utils.mfloor
local tinsert    = Utils.tinsert
local tremove    = Utils.tremove
local ipairs     = Utils.ipairs
local CreateFrame = Utils.CreateFrame
local GetTime    = Utils.GetTime
local wipe       = Utils.wipe
local PlayUISound = Utils.PlayUISound
local SOUND_CLICK = Utils.SOUND_CLICK

local UIParent = UIParent
local GameTooltip = GameTooltip
local SendChatMessage = SendChatMessage
local IsMouseButtonDown = IsMouseButtonDown

local gameOverlay
local controlBar
local scoreFrame, scoreText, comboText, multiplierText, difficultyText, timerText
local modifierRow, modifierBtn, modifierDropdown
local achievementPanel
local songSelect
local mainMenu
local pauseOverlay, pauseText
local notePool = {}
local resultPool = {}
local hitZonePool = {}
local countdownFrame, countdownText, countdownPop, countdownPopAG
local usingNativeCountdown = false
local compBarFrame
local compBarButtons = {}
local dangerOverlay
local dangerPulseAG
local projectilePool = {}

local NOTE_POOL_SIZE = 30
local RESULT_POOL_SIZE = 10
local NOTE_SIZE = 40
local ICON_CROP = 0.07
local COMP_BTN_SIZE = 48
local COMP_BTN_GAP = 6

local isInitialized = false

local RESULT_COLORS = {
    perfect    = { 0.2, 1.0, 0.2 },
    great      = { 1.0, 0.9, 0.2 },
    good       = { 1.0, 0.6, 0.1 },
    miss       = { 0.6, 0.2, 0.2 },
    redHerring = { 0.8, 0.1, 0.1 },
}

local RESULT_LABELS = {
    perfect    = "PERFECT",
    great      = "GREAT",
    good       = "GOOD",
    miss       = "MISS",
    redHerring = "FAKE",
}

local DIFFICULTIES = { "Easy", "Medium", "Hard", "Extreme" }

local DIFF_COLORS = {
    Easy    = { 0.30, 0.85, 0.30 },
    Medium  = { 1.00, 0.82, 0.00 },
    Hard    = { 1.00, 0.50, 0.10 },
    Extreme = { 0.90, 0.15, 0.15 },
}

-- Row metrics for the achievement/trophy lists, shared by the refresh and
-- resize helpers so the panel can size itself to its content.
local ACH_ROW_H, ACH_ROW_PAD = 36, 2
local TROPHY_ROW_H, TROPHY_ROW_PAD = 40, 3
local ACH_PANEL_MAX_H = 420

-- Side tab fill: accent-dim when its panel is open, lit on hover, else neutral.
local function PaintSideTab(tab)
    if tab.active then
        Theme.SetFillColor(tab, Theme.C.ACCENT_DIM)
    elseif tab.hovered then
        Theme.SetFillColor(tab, Theme.C.BTN_HOVER)
    else
        Theme.SetFillColor(tab, Theme.C.BTN_NORMAL)
    end
end

-- Modifier opener fill: accent-dim while its dropdown is open, lit on hover.
local function PaintModifierBtn(hovered)
    if not modifierBtn then return end
    if modifierDropdown and modifierDropdown:IsShown() then
        Theme.SetFillColor(modifierBtn, Theme.C.ACCENT_DIM)
    elseif hovered then
        Theme.SetFillColor(modifierBtn, Theme.C.BTN_HOVER)
    else
        Theme.SetFillColor(modifierBtn, Theme.C.BTN_NORMAL)
    end
end

local function ModifierRowClick(self)
    local Mods = ns.Modifiers
    if not Mods or not self.mod then return end
    PlayUISound(SOUND_CLICK)
    Mods:Toggle(self.mod.id)
    GameUI:UpdateModifierButton()
    GameUI:BuildModifierDropdown()
end

local function ModifierRowTooltip(self)
    local m = self.mod
    if not m then return end
    GameTooltip:SetText(m.name)
    GameTooltip:AddLine(m.desc, 1, 1, 1, true)
    if m.descExtra then
        GameTooltip:AddLine(m.descExtra, 0.6, 0.8, 1.0, true)
    end
    if self.isRequired then
        local diff = BoundToLearn.db.game.difficulty
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Required for " .. diff .. " difficulty", 0.8, 0.8, 0.4, true)
    elseif self.locked and m.unlockHint then
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Unlock: " .. m.unlockHint, 1, 0.5, 0.2, true)
    end
end

function GameUI:Initialize()
    if isInitialized then return end
    isInitialized = true

    self:CreateOverlay()
    self:CreateNotePool()
    self:CreateResultPool()
    self:CreateScoreDisplay()
    self:CreateControlBar()
    self:CreatePauseOverlay()
    self:CreateCountdown()
    self:CreateDangerOverlay()
    self:CreateStreakTitle()
end

function GameUI:CreateOverlay()
    gameOverlay = CreateFrame("Frame", "BoundToLearnGameOverlay", UIParent)
    gameOverlay:SetAllPoints()
    gameOverlay:SetFrameStrata("FULLSCREEN")
    gameOverlay:SetFrameLevel(50)
    gameOverlay:Hide()
end

function GameUI:CreateNotePool()
    for i = 1, NOTE_POOL_SIZE do
        local f = CreateFrame("Frame", "BoundToLearnNote" .. i, gameOverlay)
        f:SetSize(NOTE_SIZE, NOTE_SIZE)
        f:SetFrameStrata("FULLSCREEN")
        f:SetFrameLevel(60)
        f:Hide()

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        f.icon = icon

        -- Rounded border overlay
        local border = f:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        border:SetVertexColor(1, 1, 1, 0.8)
        f.border = border


        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        label:SetPoint("TOPRIGHT", -2, -2)
        label:SetShadowOffset(1, -1)
        label:SetTextColor(1, 1, 1)
        f.label = label

        -- Bomb indicator: skull + fuse spark
        local bombIcon = f:CreateTexture(nil, "OVERLAY", nil, 2)
        bombIcon:SetSize(20, 20)
        bombIcon:SetPoint("TOPLEFT", -6, 6)
        bombIcon:SetAtlas("Warfronts-BaseMapIcons-Horde-Attacked-Large")
        bombIcon:Hide()
        f.bombIcon = bombIcon

        local fuse = f:CreateTexture(nil, "OVERLAY", nil, 3)
        fuse:SetSize(10, 10)
        fuse:SetPoint("CENTER", bombIcon, "TOP", 2, 0)
        fuse:SetAtlas("Spark")
        fuse:SetBlendMode("ADD")
        fuse:Hide()
        f.fuse = fuse

        -- Bomb blink animation (alpha pulse on the whole frame)
        local blinkAG = f:CreateAnimationGroup()
        blinkAG:SetLooping("BOUNCE")
        local blink = blinkAG:CreateAnimation("Alpha")
        blink:SetFromAlpha(1)
        blink:SetToAlpha(0.4)
        blink:SetDuration(0.25)
        blink:SetSmoothing("IN_OUT")
        f.blinkAG = blinkAG

        -- Fuse spark shimmer
        local fuseAG = fuse:CreateAnimationGroup()
        fuseAG:SetLooping("BOUNCE")
        local fuseAlpha = fuseAG:CreateAnimation("Alpha")
        fuseAlpha:SetFromAlpha(1)
        fuseAlpha:SetToAlpha(0.2)
        fuseAlpha:SetDuration(0.15)
        local fuseScale = fuseAG:CreateAnimation("Scale")
        fuseScale:SetScaleFrom(1, 1)
        fuseScale:SetScaleTo(1.4, 1.4)
        fuseScale:SetDuration(0.15)
        f.fuseAG = fuseAG

        f.inUse = false
        notePool[i] = f
    end
end

function GameUI:CreateResultPool()
    for i = 1, RESULT_POOL_SIZE do
        local f = gameOverlay:CreateFontString(nil, "OVERLAY")
        f:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
        f:Hide()
        f.inUse = false

        local ag = f:CreateAnimationGroup()
        local translate = ag:CreateAnimation("Translation")
        translate:SetOffset(0, 80)
        translate:SetDuration(0.7)
        translate:SetSmoothing("OUT")

        f.animGroup = ag
        resultPool[i] = f
    end
end

function GameUI:CreateScoreDisplay()
    local IsShiftKeyDown = IsShiftKeyDown

    scoreFrame = CreateFrame("Frame", "BoundToLearnScoreHUD", UIParent)
    scoreFrame:SetSize(240, 178)
    scoreFrame:SetPoint("TOP", UIParent, "TOP", 0, -30)
    scoreFrame:SetFrameStrata("FULLSCREEN")
    scoreFrame:SetFrameLevel(70)
    Theme.StylePanel(scoreFrame, 0.94)
    scoreFrame:EnableMouse(true)
    scoreFrame:SetMovable(true)
    scoreFrame:SetClampedToScreen(true)
    scoreFrame:Hide()

    scoreFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" and IsShiftKeyDown() then
            self:StartMoving()
            self.isMoving = true
        end
    end)
    scoreFrame:SetScript("OnMouseUp", function(self)
        if self.isMoving then
            self:StopMovingOrSizing()
            self.isMoving = false
        end
    end)

    -- Accent line
    local accent = scoreFrame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 6, -5)
    accent:SetPoint("TOPRIGHT", -6, -5)
    accent:SetHeight(2)
    accent:SetColorTexture(Theme.RGB(Theme.C.ACCENT, 0.7))

    -- Close button (top-right, below accent)
    local closeBtn = Theme.CreateCloseButton(scoreFrame, function()
        if ns.Game and ns.Game:IsRunning() then
            ns.Game:Stop()
        end
        scoreFrame:Hide()
    end)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", -6, -8)

    -- SCORE label (left) and Timer (right) on top row
    local scoreLabel = scoreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    scoreLabel:SetPoint("TOPLEFT", 14, -11)
    scoreLabel:SetText("SCORE")
    scoreLabel:SetTextColor(0.55, 0.55, 0.55)

    timerText = scoreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerText:SetPoint("TOPRIGHT", -30, -11)
    timerText:SetTextColor(0.7, 0.7, 0.7)
    timerText:SetText("")

    -- Score number
    scoreText = scoreFrame:CreateFontString(nil, "OVERLAY")
    scoreText:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
    scoreText:SetPoint("TOP", 0, -24)
    scoreText:SetText("0")
    scoreText:SetTextColor(1, 0.84, 0)

    -- Divider below score
    local divider1 = scoreFrame:CreateTexture(nil, "ARTWORK")
    divider1:SetPoint("LEFT", 14, 0)
    divider1:SetPoint("RIGHT", -14, 0)
    divider1:SetPoint("TOP", scoreText, "BOTTOM", 0, -4)
    divider1:SetHeight(1)
    divider1:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- Combo (left) and Multiplier (right)
    comboText = scoreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    comboText:SetPoint("TOPLEFT", divider1, "BOTTOMLEFT", 0, -5)
    comboText:SetText("")
    comboText:SetTextColor(0.8, 0.8, 0.8)

    multiplierText = scoreFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    multiplierText:SetPoint("TOPRIGHT", divider1, "BOTTOMRIGHT", 0, -5)
    multiplierText:SetText("")
    multiplierText:SetTextColor(1, 1, 1)

    -- Personal best text (between score and difficulty)
    local bestText = scoreFrame:CreateFontString(nil, "OVERLAY")
    bestText:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    bestText:SetPoint("TOP", divider1, "BOTTOM", 0, -7)
    bestText:SetTextColor(0.65, 0.55, 0.4)
    bestText:SetText("")
    scoreFrame.bestText = bestText

    -- Rank icon (tinted achievement symbol next to best score, clickable to open trophies)
    local rankBtn = CreateFrame("Button", nil, scoreFrame)
    rankBtn:SetSize(18, 18)
    rankBtn:SetPoint("LEFT", bestText, "RIGHT", 3, 0)
    rankBtn:RegisterForClicks("LeftButtonUp")
    rankBtn:Hide()

    local rankTex = rankBtn:CreateTexture(nil, "OVERLAY")
    rankTex:SetAllPoints()
    rankTex:SetAtlas("UI-HUD-MicroMenu-Achievements-Mouseover")
    rankBtn.tex = rankTex

    rankBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        local diff = BoundToLearn.db.game.difficulty
        GameUI:ShowAchievementPanel("trophies", diff)
    end)
    rankBtn:SetScript("OnEnter", function(self)
        if not self.rankData then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(sformat("|cFF%s%s|r", self.rankData.color, self.rankData.name))
        local next = self.nextRank
        if next then
            GameTooltip:AddLine(sformat("Next: %s (%d pts)", next.name, next.threshold), 0.7, 0.7, 0.7)
        else
            GameTooltip:AddLine("Highest rank achieved", 0.7, 0.7, 0.7)
        end
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("Left-click to view trophies", 0.5, 0.5, 0.5)
        GameTooltip:Show()
    end)
    rankBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    scoreFrame.rankBtn = rankBtn

    -- Divider above difficulty row
    local divider2 = scoreFrame:CreateTexture(nil, "ARTWORK")
    divider2:SetPoint("LEFT", 14, 0)
    divider2:SetPoint("RIGHT", -14, 0)
    divider2:SetPoint("TOP", divider1, "BOTTOM", 0, -24)
    divider2:SetHeight(1)
    divider2:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- Difficulty selector row (4 buttons)
    local diffRow = CreateFrame("Frame", nil, scoreFrame)
    diffRow:SetSize(220, 20)
    diffRow:SetPoint("TOP", divider2, "BOTTOM", 0, -3)
    scoreFrame.diffRow = diffRow

    difficultyText = {}
    for i, name in ipairs(DIFFICULTIES) do
        local btn = CreateFrame("Button", nil, diffRow)
        btn:SetSize(53, 18)
        btn:SetPoint("LEFT", (i - 1) * 55 + 1, 0)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(name)
        btn.diffName = name

        Theme.Round(btn)
        Theme.SetBarHeight(btn, 10)
        Theme.SetBorderShown(btn, false)
        Theme.SetFill(btn, 0.14, 0.13, 0.12, 0.85)

        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            -- Clear saved toggles for modifiers required by the OLD difficulty
            local Mods = ns.Modifiers
            if Mods then
                local oldRequired = Mods.REQUIRED_MODIFIERS[BoundToLearn.db.game.difficulty]
                if oldRequired then
                    local saved = BoundToLearn.db.game.modifiers
                    if saved then
                        for _, reqId in ipairs(oldRequired) do
                            saved[reqId] = nil
                        end
                    end
                end
            end
            BoundToLearn.db.game.difficulty = name
            GameUI:UpdateDifficultyButtons()
            GameUI:UpdateBestText()
            GameUI:UpdateModifierButton()
            if modifierDropdown and modifierDropdown:IsShown() then
                GameUI:BuildModifierDropdown()
            end
        end)

        difficultyText[i] = btn
    end

    -- Modifier selector row
    modifierRow = CreateFrame("Frame", nil, scoreFrame)
    modifierRow:SetSize(220, 20)
    modifierRow:SetPoint("TOP", diffRow, "BOTTOM", 0, -2)
    scoreFrame.modifierRow = modifierRow

    modifierBtn = CreateFrame("Button", nil, modifierRow)
    modifierBtn:SetSize(220, 18)
    modifierBtn:SetPoint("CENTER")
    modifierBtn:SetNormalFontObject("GameFontNormalSmall")
    modifierBtn:SetHighlightFontObject("GameFontHighlightSmall")

    Theme.Round(modifierBtn)
    Theme.SetBarHeight(modifierBtn, 10)
    Theme.SetBorderShown(modifierBtn, false)
    Theme.SetFillColor(modifierBtn, Theme.C.BTN_NORMAL)

    modifierBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI.modifierOpener = modifierBtn
        GameUI:ToggleModifierDropdown()
    end)
    modifierBtn:HookScript("OnEnter", function() PaintModifierBtn(true) end)
    modifierBtn:HookScript("OnLeave", function() PaintModifierBtn(false) end)
    GameUI:UpdateModifierButton()

    -- Sidebar tab anchored flush to the right edge of scoreFrame, centered vertically
    local sideTab = CreateFrame("Button", nil, scoreFrame)
    sideTab:SetSize(18, 80)
    sideTab:SetPoint("LEFT", scoreFrame, "RIGHT", -3, 0)
    Theme.StyleCard(sideTab, Theme.C.BTN_NORMAL)
    Theme.SetBorderShown(sideTab, false)

    local tabIcon = sideTab:CreateTexture(nil, "ARTWORK")
    tabIcon:SetSize(12, 12)
    tabIcon:SetPoint("CENTER")
    tabIcon:SetAtlas("UI-HUD-MicroMenu-Achievements-Mouseover")
    sideTab.icon = tabIcon

    sideTab:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleAchievementPanel()
    end)
    sideTab:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintSideTab(self)
    end)
    sideTab:SetScript("OnLeave", function(self)
        self.hovered = false
        PaintSideTab(self)
    end)
    Theme.DelayedTooltip(sideTab, function()
        GameTooltip:SetText("Achievements")
    end)
    scoreFrame.sideTab = sideTab

    -- Leaderboard tab anchored flush to the left edge of scoreFrame
    local lbTab = CreateFrame("Button", nil, scoreFrame)
    lbTab:SetSize(18, 80)
    lbTab:SetPoint("RIGHT", scoreFrame, "LEFT", 3, 0)
    Theme.StyleCard(lbTab, Theme.C.BTN_NORMAL)
    Theme.SetBorderShown(lbTab, false)

    local lbIcon = lbTab:CreateTexture(nil, "ARTWORK")
    lbIcon:SetSize(12, 12)
    lbIcon:SetPoint("CENTER")
    lbIcon:SetAtlas("UI-HUD-MicroMenu-GuildCommunities-Mouseover")
    lbTab.icon = lbIcon

    lbTab:SetScript("OnClick", function(self)
        PlayUISound(SOUND_CLICK)
        if ns.LeaderboardUI then ns.LeaderboardUI:Toggle() end
        local lbf = _G.BoundToLearnLeaderboard
        if lbf and not lbf._btlTabHooked then
            lbf._btlTabHooked = true
            lbf:HookScript("OnShow", function() GameUI:RefreshSideTabs() end)
            lbf:HookScript("OnHide", function() GameUI:RefreshSideTabs() end)
        end
        GameUI:RefreshSideTabs()
    end)
    lbTab:SetScript("OnEnter", function(self)
        self.hovered = true
        PaintSideTab(self)
    end)
    lbTab:SetScript("OnLeave", function(self)
        self.hovered = false
        PaintSideTab(self)
    end)
    Theme.DelayedTooltip(lbTab, function()
        GameTooltip:SetText("Leaderboard")
    end, "ANCHOR_LEFT")
    scoreFrame.lbTab = lbTab
end

function GameUI:RefreshSideTabs()
    if not scoreFrame then return end
    local st = scoreFrame.sideTab
    if st then
        st.active = achievementPanel and achievementPanel:IsShown() or false
        PaintSideTab(st)
    end
    local lb = scoreFrame.lbTab
    if lb then
        local lbf = _G.BoundToLearnLeaderboard
        lb.active = lbf and lbf:IsShown() or false
        PaintSideTab(lb)
    end
end

function GameUI:UpdateDifficultyButtons()
    if not difficultyText then return end
    local current = BoundToLearn.db.game.difficulty
    for _, btn in ipairs(difficultyText) do
        local c = DIFF_COLORS[btn.diffName]
        if btn.diffName == current then
            Theme.SetFill(btn, c[1] * 0.55, c[2] * 0.55, c[3] * 0.55, 0.9)
            btn:GetFontString():SetTextColor(c[1], c[2], c[3])
        else
            Theme.SetFill(btn, 0.14, 0.13, 0.12, 0.85)
            btn:GetFontString():SetTextColor(c[1] * 0.5, c[2] * 0.5, c[3] * 0.5)
        end
    end
end

function GameUI:UpdateBestText()
    if not scoreFrame or not scoreFrame.bestText then return end
    local diff = BoundToLearn.db.game.difficulty
    local db = BoundToLearn.db.stats.difficultyBest
    local best = db and db[diff]
    local rb = scoreFrame.rankBtn
    if best and best.highestScore > 0 then
        local Ach = ns.Achievements
        local rank = Ach and Ach:GetRank(best.highestScore)
        scoreFrame.bestText:SetText(sformat("Best: |cFFFFCC00%d|r", best.highestScore))
        if rank and rank.threshold > 0 and rb then
            local c = rank.rgb
            rb.tex:SetVertexColor(c[1], c[2], c[3], 1)
            rb.rankData = rank
            rb.nextRank = Ach:GetNextRank(best.highestScore)
            rb:Show()
        elseif rb then
            rb:Hide()
        end
    else
        scoreFrame.bestText:SetText("")
        if rb then rb:Hide() end
    end
end

function GameUI:UpdateModifierButton()
    if not modifierBtn then return end
    local Mods = ns.Modifiers
    if not Mods then return end
    modifierBtn:SetText("Modifiers")
    local count = Mods:GetActiveCount()
    local fs = modifierBtn:GetFontString()
    if fs then
        if count > 0 then
            fs:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))
        else
            fs:SetTextColor(0.7, 0.7, 0.7)
        end
    end
end

function GameUI:ToggleModifierDropdown()
    if modifierDropdown and modifierDropdown:IsShown() then
        modifierDropdown:Hide()
        return
    end
    self:BuildModifierDropdown()
end

function GameUI:BuildModifierDropdown()
    local Mods = ns.Modifiers
    if not Mods then return end

    if not modifierDropdown then
        modifierDropdown = CreateFrame("Frame", nil, UIParent)
        Theme.StylePanel(modifierDropdown, 0.97)
        modifierDropdown:SetFrameStrata("FULLSCREEN_DIALOG")
        modifierDropdown:SetFrameLevel(100)
        modifierDropdown:SetClampedToScreen(true)
        modifierDropdown.rows = {}
        modifierDropdown:HookScript("OnShow", function() PaintModifierBtn(modifierBtn:IsMouseOver()) end)
        modifierDropdown:HookScript("OnHide", function() PaintModifierBtn(modifierBtn:IsMouseOver()) end)
    end
    local opener = GameUI.modifierOpener or modifierBtn

    local list = Mods.MODIFIER_LIST
    local rowH = 26
    local pad = 6
    local rowW = 208
    local ddH = #list * rowH + pad * 2
    modifierDropdown:SetSize(220, ddH)
    modifierDropdown:ClearAllPoints()
    -- Drop down from the opener, or flip above it when there is not enough room
    -- below; SetClampedToScreen keeps the remaining edges on-screen.
    local opScale = opener:GetEffectiveScale() or 1
    local ddScale = modifierDropdown:GetEffectiveScale() or 1
    if (opener:GetBottom() or 0) * opScale < ddH * ddScale + 8 then
        modifierDropdown:SetPoint("BOTTOMLEFT", opener, "TOPLEFT", 0, 2)
    else
        modifierDropdown:SetPoint("TOPLEFT", opener, "BOTTOMLEFT", 0, -2)
    end

    local active = Mods:GetActive()
    local rows = modifierDropdown.rows
    for i, m in ipairs(list) do
        local row = rows[i]
        if not row then
            row = Theme.CreateToggle(modifierDropdown, "", nil, rowW)
            -- Locked/required rows are Disabled; enable motion scripts so they
            -- still fire OnEnter for the unlock tooltip and the hover wash.
            row:SetMotionScriptsWhileDisabled(true)
            Theme.DelayedTooltip(row, ModifierRowTooltip)
            -- Subtle accent hover wash behind the row (same treatment as the
            -- minimap menu), shown for locked and unlocked rows alike.
            local hl = CreateFrame("Frame", nil, modifierDropdown)
            hl:SetFrameLevel(modifierDropdown:GetFrameLevel())
            hl:SetPoint("TOPLEFT", row, "TOPLEFT", -2, 1)
            hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 2, -1)
            Theme.Round(hl)
            Theme.SetBarHeight(hl, 10)
            Theme.SetBorderShown(hl, false)
            Theme.SetFillColor(hl, Theme.C.ACCENT, 0)
            row.hl = hl
            row:HookScript("OnEnter", function(self) Theme.SetFillColor(self.hl, Theme.C.ACCENT, 0.15) end)
            row:HookScript("OnLeave", function(self) Theme.SetFillColor(self.hl, Theme.C.ACCENT, 0) end)
            rows[i] = row
        end

        local unlocked = Mods:IsUnlocked(m.id)
        local isActive = active[m.id]
        local isRequired = Mods:IsRequired(m.id)

        row.mod = m
        row.isRequired = isRequired
        row.locked = not unlocked
        row.Text:SetText(m.name)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", modifierDropdown, "TOPLEFT", pad, -(pad + (i - 1) * rowH))

        if isRequired then
            row:Disable()
            row:SetChecked(true)
            row:SetScript("OnClick", nil)
        elseif unlocked then
            row:Enable()
            row:SetChecked(isActive and true or false)
            row:SetScript("OnClick", ModifierRowClick)
        else
            row:Disable()
            row:SetChecked(false)
            row:SetScript("OnClick", nil)
        end
        row:Show()
    end

    for i = #list + 1, #rows do
        rows[i]:Hide()
    end

    modifierDropdown:Show()
end

function GameUI:UpdateTimer(remaining)
    local str, tr, tg, tb = "", 0.7, 0.7, 0.7
    if remaining then
        str = sformat("%d:%02d", mfloor(remaining / 60), mfloor(remaining % 60))
        if remaining <= 10 then
            tr, tg, tb = 1, 0.3, 0.3
        elseif remaining <= 30 then
            tr, tg, tb = 1, 0.85, 0.3
        end
    end
    if timerText then
        timerText:SetText(str)
        timerText:SetTextColor(tr, tg, tb)
    end
    local hf = self.healthFrame
    if hf then
        hf.timerFS:SetText(str)
        hf.timerFS:SetTextColor(tr, tg, tb)
    end
end

function GameUI:CreateControlBar()
    controlBar = CreateFrame("Frame", nil, scoreFrame)
    controlBar:SetPoint("TOPLEFT", scoreFrame.modifierRow, "BOTTOMLEFT", 0, -4)
    controlBar:SetPoint("TOPRIGHT", scoreFrame.modifierRow, "BOTTOMRIGHT", 0, -4)
    controlBar:EnableMouse(true)

    local pauseBtn = Theme.CreateButton(controlBar, "Pause", 105, 22)
    pauseBtn:SetPoint("TOPLEFT", scoreFrame.modifierRow, "BOTTOMLEFT", -1, -4)
    pauseBtn:SetScript("OnClick", function()
        if ns.Game then
            if ns.Game:IsPaused() then
                ns.Game:Resume()
            else
                ns.Game:Pause()
            end
        end
    end)
    controlBar.pauseBtn = pauseBtn

    local stopBtn = Theme.CreateButton(controlBar, "Stop", 105, 22)
    stopBtn:SetPoint("TOPRIGHT", scoreFrame.modifierRow, "BOTTOMRIGHT", 1, -4)
    stopBtn:SetScript("OnClick", function()
        if ns.Game then ns.Game:Stop() end
    end)
    controlBar.stopBtn = stopBtn

    -- Start button (shown in ready state, hidden during gameplay)
    local startBtn = Theme.CreateAccentButton(controlBar, "Start", 220, 22)
    startBtn:SetPoint("TOP", 0, 0)
    startBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "timed"
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    startBtn:Hide()
    controlBar.startBtn = startBtn

    -- Practice button (below Start, shown in ready state)
    local practiceBtn = Theme.CreateAccentButton(controlBar, "Practice", 108, 22)
    practiceBtn:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", 0, -2)
    practiceBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "practice"
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    practiceBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Practice Mode")
        GameTooltip:AddLine("No time limit. Play until you stop.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    practiceBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    practiceBtn:Hide()
    controlBar.practiceBtn = practiceBtn

    -- Competitive button (right of Practice, shown in ready state)
    local compBtn = Theme.CreateAccentButton(controlBar, "Competitive", 108, 22)
    compBtn:SetPoint("TOPRIGHT", startBtn, "BOTTOMRIGHT", 0, -2)
    compBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "competitive"
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    compBtn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Competitive Mode")
        GameTooltip:AddLine("15 fixed lanes (1-5, Shift, Ctrl), same for everyone.", 1, 1, 1, true)
        GameTooltip:AddLine("Bomb notes destroy your lane if missed.", 1, 0.8, 0.3, true)
        GameTooltip:AddLine("Extreme forces angled notes.", 0.6, 0.8, 1.0, true)
        GameTooltip:AddLine("Pausing resets your score to zero.", 1, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    compBtn:HookScript("OnLeave", function() GameTooltip:Hide() end)
    compBtn:Hide()
    controlBar.compBtn = compBtn

end

-- =====================================================================
-- Song select carousel: the game's ready-state menu. Pick a track and a
-- difficulty (deterministic per-difficulty charts), see per-song bests to
-- boast about, then Start / Practice / Competitive.
-- =====================================================================
local function SongBestScore(key, diff)
    local ss = BoundToLearn.db.game.songScores
    return (ss and ss[key] and ss[key][diff]) or 0
end

-- Best fraction (0-1) of a track the player has ever reached, across difficulties.
local function SongBestProgress(key)
    local sp = BoundToLearn.db.game.songProgress
    return (sp and sp[key]) or 0
end

local SONG_HISTORY_MAX = 8
function GameUI:RecordSongScore(score, accuracy, maxCombo)
    local db = BoundToLearn.db.game
    local key, diff = db.songKey, db.difficulty
    if not key or not score then return false end
    db.songScores = db.songScores or {}
    db.songScores[key] = db.songScores[key] or {}
    local prevBest = db.songScores[key][diff] or 0
    local isNewBest = score > prevBest
    if isNewBest then db.songScores[key][diff] = score end
    -- Persisted per-song, per-difficulty attempt history (survives reloads) so the
    -- results screen can chart this run against previous attempts.
    db.songHistory = db.songHistory or {}
    db.songHistory[key] = db.songHistory[key] or {}
    local hist = db.songHistory[key][diff] or {}
    hist[#hist + 1] = score
    while #hist > SONG_HISTORY_MAX do tremove(hist, 1) end
    db.songHistory[key][diff] = hist
    -- Richer per-track, per-difficulty stats for the Tracks stats view: play count and
    -- best accuracy / combo (best score already lives in songScores).
    db.songStats = db.songStats or {}
    db.songStats[key] = db.songStats[key] or {}
    local st = db.songStats[key][diff] or { plays = 0, bestAccuracy = 0, bestCombo = 0 }
    st.plays = (st.plays or 0) + 1
    if accuracy and accuracy > (st.bestAccuracy or 0) then st.bestAccuracy = accuracy end
    if maxCombo and maxCombo > (st.bestCombo or 0) then st.bestCombo = maxCombo end
    db.songStats[key][diff] = st
    -- Snapshot for ShowResultsOnSelect (prevBest is the best before this run).
    self.songCompare = { prevBest = prevBest, score = score, isNewBest = isNewBest, history = hist }
    return isNewBest
end

function GameUI:RecordSongProgress(key, frac)
    if not key or not frac then return end
    local db = BoundToLearn.db.game
    db.songProgress = db.songProgress or {}
    if (db.songProgress[key] or 0) < frac then
        db.songProgress[key] = frac
    end
    if songSelect then songSelect.donutDirty = true end
end


-- Fill colour ramps with how full the bar is: green when barely filled (easy) through
-- yellow and orange to red when nearly full (hard).
local DIFF_RAMP = {
    { 0.00, 0.35, 0.82, 0.35 },  -- green
    { 0.38, 0.92, 0.86, 0.22 },  -- yellow
    { 0.68, 0.96, 0.52, 0.14 },  -- orange
    { 1.00, 0.95, 0.20, 0.14 },  -- red
}
local function DiffRampColor(frac)
    frac = mmax(0, mmin(1, frac))
    for i = 2, #DIFF_RAMP do
        local a, b = DIFF_RAMP[i - 1], DIFF_RAMP[i]
        if frac <= b[1] then
            local t = (frac - a[1]) / (b[1] - a[1])
            return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
        end
    end
    local last = DIFF_RAMP[#DIFF_RAMP]
    return last[2], last[3], last[4]
end

-- Difficulty meter: a dark rounded track holding Blizzard's cast-bar fill, revealed to
-- the rating (fuller = harder) and coloured by the ramp above. The rounded track IS the
-- edge -- no ornate cast-bar frame, whose fixed padding leaves an extra ring on a small bar.
local CAST_FILL_TEX = "Interface\\CastingBar\\UI-CastingBar-Fill"
local function MakeDiffBar(parent, w, h)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(w, h)
    Theme.Round(frame)
    Theme.SetBarHeight(frame, h)
    Theme.SetFill(frame, 0.10, 0.04, 0.04, 1)         -- dark ember track
    Theme.SetBorderColor(frame, 0, 0, 0, 0.85)
    frame:SetClipsChildren(true)

    local bar = CreateFrame("StatusBar", nil, frame)
    bar:SetPoint("TOPLEFT", 4, -2)
    bar:SetPoint("BOTTOMRIGHT", -4, 2)
    bar:SetMinMaxValues(0, 10)
    if C_Texture.GetAtlasInfo("ui-castingbar-filling-standard") then
        bar:SetStatusBarTexture(bar:CreateTexture())
        bar:GetStatusBarTexture():SetAtlas("ui-castingbar-filling-standard")
    else
        bar:SetStatusBarTexture(CAST_FILL_TEX)
    end
    bar:SetStatusBarColor(1, 0.18, 0.13)              -- interrupt red
    frame.bar = bar
    return frame
end

local function SetDiffBar(frame, rating, dim)
    frame.bar:SetValue(rating)
    frame.bar:SetStatusBarColor(DiffRampColor(rating / 10))
    frame:SetAlpha(dim and 0.55 or 1)
end

-- In-round life gauge: the same rounded cast-bar track as the difficulty meter, but the
-- fill is the remaining life and the ramp runs the other way (full = green, empty = red).
local function MakeLifeBar(parent, w, h)
    local frame = MakeDiffBar(parent, w, h)
    frame.bar:SetMinMaxValues(0, 1)
    return frame
end

local function SetLifeBar(frame, frac)
    frac = mmax(0, mmin(1, frac))
    frame.bar:SetValue(frac)
    frame.bar:SetStatusBarColor(DiffRampColor(1 - frac))
end

-- A renown-style progress donut: a dim circular track with a coloured arc that
-- fills clockwise to a fraction. The arc is a paused radial sweep (Cooldown) and
-- a masked centre hole carves the ring. Used per song bubble to show how far the
-- player has gotten through that track.
-- Hollow progress ring drawn from anti-aliased line segments: a many-sided
-- circle outline, nothing in the centre (genuinely see-through), a few pixels
-- thick. Segments up to the fraction are accent-coloured, the rest faint. WoW
-- lines are anti-aliased, so the outline reads as smooth with no square pixels.
-- A ring texture (transparent center) rendered smoothly by the client. The fill
-- is a radial cooldown swipe of the same ring, so partial progress reads as a
-- clean arc with a see-through middle, exactly like the default UI's progress
-- rings. No line segments, so nothing looks faceted.
local DONUT_RING_TEX = "Interface\\Artifacts\\Artifacts-PerkRing-Final"
local DONUT_STATIC_DUR = 1000000
local function MakeDonut(parent, size)
    local d = CreateFrame("Frame", nil, parent)
    d:SetSize(size, size)

    local track = d:CreateTexture(nil, "ARTWORK")
    track:SetAllPoints()
    track:SetTexture(DONUT_RING_TEX)
    track:SetVertexColor(0.62, 0.62, 0.68, 0.28)
    d.track = track

    local cd = CreateFrame("Cooldown", nil, d)
    cd:SetAllPoints()
    cd:SetSwipeTexture(DONUT_RING_TEX)
    cd:SetDrawBling(false)
    cd:SetDrawEdge(false)
    cd:SetHideCountdownNumbers(true)
    cd:SetReverse(true)
    d.cd = cd

    return d
end

local function SetDonut(d, frac, r, g, b)
    frac = mmax(0, mmin(1, frac or 0))
    d.cd:SetSwipeColor(r, g, b, 1)
    if frac <= 0 then
        d.cd:Clear()
    else
        -- Freeze a very long cooldown so the swipe shows a static `frac` of the ring.
        d.cd:SetCooldown(GetTime() - (1 - frac) * DONUT_STATIC_DUR, DONUT_STATIC_DUR)
    end
end

-- A renown-button textured bubble button, desaturated to the same cool silver as
-- the song wheel bubbles so the whole panel shares one colour scheme. An additive
-- highlight of the same shape gives a clear hover glow.
local BUBBLE_SILVER = { 0.80, 0.83, 0.88 }
local function MakeBubbleButton(parent, text, w, h)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetAtlas("UI-Journeys-Renown-Button")
    bg:SetDesaturated(true)
    bg:SetVertexColor(BUBBLE_SILVER[1], BUBBLE_SILVER[2], BUBBLE_SILVER[3])
    b.bg = bg
    local pressed = b:CreateTexture(nil, "BACKGROUND")
    pressed:SetAllPoints()
    pressed:SetAtlas("UI-Journeys-Renown-Button-pressed")
    pressed:SetDesaturated(true)
    pressed:SetVertexColor(BUBBLE_SILVER[1], BUBBLE_SILVER[2], BUBBLE_SILVER[3])
    pressed:Hide()
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetAtlas("UI-Journeys-Renown-Button")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.28)
    local label = b:CreateFontString(nil, "OVERLAY")
    label:SetFont("Fonts\\FRIZQT__.TTF", mmax(12, mfloor(h * 0.5)), "OUTLINE")
    label:SetPoint("CENTER")
    label:SetText(text)
    label:SetTextColor(1, 1, 1)
    b.label = label
    b:SetScript("OnMouseDown", function() bg:Hide(); pressed:Show() end)
    b:SetScript("OnMouseUp", function() pressed:Hide(); bg:Show() end)
    b:HookScript("OnEnter", function() bg:SetVertexColor(1.0, 1.04, 1.12) end)
    b:HookScript("OnLeave", function() bg:SetVertexColor(BUBBLE_SILVER[1], BUBBLE_SILVER[2], BUBBLE_SILVER[3]) end)
    return b
end

-- Groove radar: a five-axis polygon (DDR-style) showing a chart's character.
-- Axis labels come from SongData.RADAR_LABELS. Drawn with anti-aliased lines: a
-- faint pentagon grid + spokes with labels, plus an accent polygon for the
-- current per-song/per-difficulty values (updated by SetRadar).
local RADAR_AXES = 5
local function MakeRadar(parent, size)
    local rf = CreateFrame("Frame", nil, parent)
    rf:SetSize(size, size)
    local R = size * 0.5 - 15
    rf.vx, rf.vy = {}, {}
    for k = 1, RADAR_AXES do
        local ang = (k - 1) * 2 * math.pi / RADAR_AXES
        rf.vx[k] = R * math.sin(ang)
        rf.vy[k] = R * math.cos(ang)
    end
    for k = 1, RADAR_AXES do
        local nk = (k % RADAR_AXES) + 1
        local edge = rf:CreateLine(nil, "ARTWORK")
        edge:SetThickness(1)
        edge:SetColorTexture(1, 1, 1, 0.18)
        edge:SetStartPoint("CENTER", rf, rf.vx[k], rf.vy[k])
        edge:SetEndPoint("CENTER", rf, rf.vx[nk], rf.vy[nk])
        local spoke = rf:CreateLine(nil, "ARTWORK")
        spoke:SetThickness(1)
        spoke:SetColorTexture(1, 1, 1, 0.1)
        spoke:SetStartPoint("CENTER", rf, 0, 0)
        spoke:SetEndPoint("CENTER", rf, rf.vx[k], rf.vy[k])
        local lbl = rf:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
        lbl:SetPoint("CENTER", rf, "CENTER", rf.vx[k] * 1.34, rf.vy[k] * 1.34)
        lbl:SetText(ns.SongData.RADAR_LABELS[k] or "")
        lbl:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))
    end
    rf.valueLines = {}
    for k = 1, RADAR_AXES do
        local vl = rf:CreateLine(nil, "OVERLAY")
        vl:SetThickness(2)
        rf.valueLines[k] = vl
    end
    return rf
end

local function SetRadar(rf, values)
    local ar, ag, ab = Theme.RGB(Theme.C.ACCENT_BRIGHT)
    for k = 1, RADAR_AXES do
        local nk = (k % RADAR_AXES) + 1
        local v  = mmax(0.08, mmin(1, values[k] or 0.1))
        local nv = mmax(0.08, mmin(1, values[nk] or 0.1))
        local vl = rf.valueLines[k]
        vl:SetStartPoint("CENTER", rf, rf.vx[k] * v, rf.vy[k] * v)
        vl:SetEndPoint("CENTER", rf, rf.vx[nk] * nv, rf.vy[nk] * nv)
        vl:SetColorTexture(ar, ag, ab, 0.95)
    end
end

-- Right-click menu for a wheel song: a small popup with a Stats button that opens the
-- stats window straight to that track. A fullscreen catcher behind it closes the menu
-- on any outside click.
function GameUI:ShowSongContextMenu(slot)
    local key = slot and slot.songKey
    if not key then return end
    local menu = self.songMenu
    if not menu then
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:RegisterForClicks("AnyUp")
        catcher:Hide()
        catcher:SetScript("OnClick", function(self) self:Hide() end)

        menu = CreateFrame("Frame", nil, catcher)
        menu:SetSize(150, 62)
        menu:SetFrameLevel(catcher:GetFrameLevel() + 10)
        menu:SetClampedToScreen(true)
        Theme.StylePanel(menu, 0.98)
        menu:EnableMouse(true)

        local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOPLEFT", 8, -8)
        title:SetPoint("TOPRIGHT", -8, -8)
        title:SetJustifyH("CENTER")
        title:SetWordWrap(false)
        menu.title = title

        local statsBtn = Theme.CreateButton(menu, "Stats", 130, 22)
        statsBtn:SetPoint("BOTTOM", 0, 8)
        statsBtn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            catcher:Hide()
            if menu.songKey then GameUI:ShowStatsPage(menu.songKey) end
        end)

        menu.catcher = catcher
        self.songMenu = menu
    end

    menu.songKey = key
    local song = ns.SongData and ns.SongData.Get(key)
    menu.title:SetText((song and song.title) or key)

    local scale = UIParent:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    menu.catcher:Show()
end

function GameUI:CreateSongSelect()
    if songSelect then return end

    local f = CreateFrame("Frame", "BoundToLearnSongSelect", UIParent)
    f:SetSize(568, 432)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(70)
    Theme.StylePanel(f, 0.96)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    f:Hide()

    -- Per-expansion Adventure Guide backdrop for the whole menu, chosen by the
    -- selected track's era, laid over StylePanel's dark rounded fill.
    local xbg = f:CreateTexture(nil, "ARTWORK")
    xbg:SetPoint("TOPLEFT", 7, -7)
    xbg:SetPoint("BOTTOMRIGHT", -7, 7)
    xbg:SetAlpha(0.9)
    f.xpacBg = xbg

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    title:SetPoint("TOPLEFT", 18, -17)
    title:SetText("Select Music")
    title:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))

    local closeBtn = Theme.CreateCloseButton(f, function() GameUI:HideSongSelect() end)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    local statsBtn = MakeBubbleButton(f, "Stats", 62, 22)
    statsBtn:SetPoint("LEFT", title, "RIGHT", 14, 0)
    statsBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleStatsPanel()
    end)
    f.statsBtn = statsBtn

    -- Right column: a 3D-style song wheel. Fixed slots the tracks roll through
    -- with a sliding animation; the selected track is the large centre slot and
    -- neighbours shrink and run off the clipped right edge above/below. The wheel's
    -- own wheelClip clips the bubbles; f itself must not clip, or it would cut off
    -- the tooltip-border child that sits just outside the panel edge.
    f:EnableMouseWheel(true)
    f:SetScript("OnMouseWheel", function(_, delta) GameUI:CycleSong(-delta) end)
    f:SetScript("OnUpdate", function(self, elapsed)
        local ao = self.animOffset
        if ao and ao ~= 0 then
            ao = ao - ao * mmin(1, elapsed * 8)
            if ao < 0.012 and ao > -0.012 then ao = 0 end
            self.animOffset = ao
            GameUI:PositionWheel()
        end
    end)

    -- Slots live in an inset viewport so they are cut off at the interior
    -- border of the background art, not at the outer window edge.
    local wheelClip = CreateFrame("Frame", nil, f)
    wheelClip:SetPoint("TOPLEFT", 250, -58)      -- top edge sits at the interior border
    wheelClip:SetPoint("BOTTOMRIGHT", -24, 14)   -- right edge sits at the interior border
    wheelClip:SetClipsChildren(true)
    f.wheelClip = wheelClip

    -- Search box above the wheel: filters the carousel by title or artist.
    local search = CreateFrame("EditBox", nil, f)
    -- Vertical center aligned with the title/Stats header row (same top, both ~22px).
    search:SetPoint("TOPLEFT", 250, -17)
    search:SetPoint("TOPRIGHT", -24, -17)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetTextInsets(10, 10, 0, 0)
    Theme.StylePanel(search, 0.92)

    local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 10, 0)
    ph:SetText("Search tracks...")
    search.placeholder = ph

    -- Clear (x) button: just an x until hovered, then a button shape appears
    -- behind it. Only shown when there is text.
    local clearBtn = CreateFrame("Button", nil, search)
    clearBtn:SetSize(16, 16)
    clearBtn:SetPoint("RIGHT", -6, 0)
    local clearShape = clearBtn:CreateTexture(nil, "BACKGROUND")
    clearShape:SetPoint("CENTER")
    clearShape:SetSize(22, 20)
    clearShape:SetAtlas("UI-Journeys-Renown-Button")
    clearShape:SetDesaturated(true)
    clearShape:SetVertexColor(0.85, 0.88, 0.95)
    clearShape:Hide()
    local clearIcon = clearBtn:CreateTexture(nil, "OVERLAY")
    clearIcon:SetAllPoints()
    clearIcon:SetAtlas("common-search-clearbutton")
    clearBtn:HookScript("OnEnter", function() clearShape:Show() end)
    clearBtn:HookScript("OnLeave", function() clearShape:Hide() end)
    clearBtn:SetScript("OnClick", function()
        search:SetText("")
        search:ClearFocus()
        search.placeholder:Show()
    end)
    clearBtn:Hide()
    search.clearBtn = clearBtn

    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.placeholder:Show() end
    end)
    search:SetScript("OnTextChanged", function(self)
        local has = self:GetText() ~= ""
        self.placeholder:SetShown(not has)
        self.clearBtn:SetShown(has)
    end)
    f.searchBox = search
    -- Results dropdown: pick a track instead of auto-jumping to the nearest as you type.
    self:AttachSongSearchDropdown(search, function(key)
        local songs = ns.SongData.songs
        for i = 1, #songs do
            if songs[i].key == key then
                f.selIndex = i
                BoundToLearn.db.game.songKey = key
                f.animOffset = 0
                f.donutDirty = true
                GameUI:RefreshSongSelect()
                GameUI:PlaySongPreview()
                return
            end
        end
    end)

    f.wheelCenter = 5
    f.wheelSpacing = 38
    f.animOffset = 0
    f.selIndex = 1
    f.slots = {}
    for s = 1, 9 do
        local slot = CreateFrame("Button", nil, wheelClip)
        slot:EnableMouseWheel(true)
        slot:SetScript("OnMouseWheel", function(_, delta) GameUI:CycleSong(-delta) end)

        -- Solid backing behind the bubble art. The wheel bubbles are distance-faded
        -- (translucent), so without this the busy backdrop shows through them. Uses
        -- the same rounded button atlas as the art so it fills the bubble shape
        -- instead of a square box around it. Fades with the slot like everything else.
        local backing = slot:CreateTexture(nil, "BACKGROUND")
        backing:SetAllPoints()
        backing:SetAtlas("UI-Journeys-Renown-Button")
        backing:SetDesaturated(true)
        backing:SetVertexColor(0.06, 0.055, 0.05, 1)
        slot.backing = backing

        local bg = slot:CreateTexture(nil, "ARTWORK")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        slot.bg = bg

        -- Nine-slice art overlay: shows the selected track's real image clipped to
        -- the rounded bubble shape (bg stays for the atlas bubbles).
        Theme.CreateArt(slot)

        -- Additive hover glow so hovering a track clearly lights up.
        local hl = slot:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetAtlas("UI-Journeys-Renown-Button")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.22)
        slot.hl = hl

        local donut = MakeDonut(slot, 20)      -- resized per-row to ~55% of bubble height
        donut:SetPoint("LEFT", 10, 0)
        slot.donut = donut

        local st = slot:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        st:SetPoint("LEFT", 40, 0)
        st:SetPoint("RIGHT", -14, 0)
        st:SetJustifyH("LEFT")
        st:SetWordWrap(false)
        slot.titleFS = st

        -- Inset past the slot's right overhang (slots extend ~14-19px beyond the
        -- clip so the art meets the interior border) so the time is not clipped.
        local dur = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dur:SetPoint("BOTTOMRIGHT", -30, 6)
        dur:SetJustifyH("RIGHT")
        slot.durFS = dur

        -- Artist/composer: shown only on the enlarged selected bubble, where there
        -- is room. Kept clear of the duration on the right.
        local art = slot:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        art:SetPoint("TOPLEFT", st, "BOTTOMLEFT", 0, -2)
        art:SetPoint("RIGHT", dur, "LEFT", -8, 0)
        art:SetJustifyH("LEFT")
        art:SetWordWrap(false)
        art:Hide()
        slot.artistFS = art

        slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        slot:SetScript("OnClick", function(self, button)
            if button == "RightButton" then
                GameUI:ShowSongContextMenu(self)
            elseif self.dist then
                GameUI:CycleSong(self.dist)
            end
        end)
        slot:HookScript("OnEnter", function(self) self.hover = true; GameUI:PositionWheel() end)
        slot:HookScript("OnLeave", function(self) self.hover = false; GameUI:PositionWheel() end)
        f.slots[s] = slot
    end

    -- Left column: groove radar (chart character), difficulty meters, best score,
    -- action buttons. The redundant song-name card is gone; the selected wheel
    -- bubble already shows the track, so this space holds the radar instead.
    local radar = MakeRadar(f, 116)
    radar:SetPoint("TOPLEFT", 76, -76)
    f.radar = radar

    f.diffRows = {}
    f.diffSegs = {}
    local dyTop = -202
    for i, name in ipairs(DIFFICULTIES) do
        local drow = CreateFrame("Button", nil, f)
        drow:SetSize(270, 22)
        drow:SetPoint("TOPLEFT", 16, dyTop - (i - 1) * 26)
        drow.diffName = name

        -- Same silver renown texture as the song bubbles and action buttons.
        local dbg = drow:CreateTexture(nil, "BACKGROUND")
        dbg:SetAllPoints()
        dbg:SetAtlas("UI-Journeys-Renown-Button")
        dbg:SetDesaturated(true)
        drow.dbg = dbg
        local dhl = drow:CreateTexture(nil, "HIGHLIGHT")
        dhl:SetAllPoints()
        dhl:SetAtlas("UI-Journeys-Renown-Button")
        dhl:SetBlendMode("ADD")
        dhl:SetAlpha(0.18)

        local dl = drow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dl:SetPoint("LEFT", 16, 0)
        dl:SetText(name)
        drow.label = dl

        local dbar = MakeDiffBar(drow, 140, 11)
        dbar:SetPoint("RIGHT", drow, "RIGHT", -18, 0)
        f.diffSegs[i] = dbar

        drow:SetScript("OnClick", function(self)
            PlayUISound(SOUND_CLICK)
            BoundToLearn.db.game.difficulty = self.diffName
            GameUI:UpdateDifficultyButtons()
            GameUI:RefreshSongSelect()
        end)
        f.diffRows[i] = drow
    end

    local best = f:CreateFontString(nil, "OVERLAY")
    best:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    best:SetPoint("TOPLEFT", 18, dyTop - 4 * 26 - 8)
    f.bestText = best

    local startBtn = MakeBubbleButton(f, "Start", 270, 28)
    startBtn:SetPoint("TOPLEFT", 16, dyTop - 4 * 26 - 34)
    startBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "timed"
        GameUI:StartFromSongSelect()
    end)

    local practiceBtn = MakeBubbleButton(f, "Practice", 133, 22)
    practiceBtn:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", 0, -4)
    practiceBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "practice"
        GameUI:StartFromSongSelect()
    end)
    Theme.DelayedTooltip(practiceBtn, function()
        GameTooltip:SetText("Practice Mode")
        GameTooltip:AddLine("No time limit. Play until you stop.", 1, 1, 1, true)
    end)

    local modBtn = MakeBubbleButton(f, "Modifiers", 133, 22)
    modBtn:SetPoint("LEFT", practiceBtn, "RIGHT", 4, 0)
    modBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI.modifierOpener = modBtn
        GameUI:ToggleModifierDropdown()
    end)

    -- The whole left column is a single group so round-over results can swap it
    -- out for the results panel and back.
    f.mainTitle = title
    f.leftControls = { f.radar, f.bestText, startBtn, practiceBtn, modBtn }
    for _, drow in ipairs(f.diffRows) do
        f.leftControls[#f.leftControls + 1] = drow
    end
    self:CreateResultsPanel(f)

    -- ESC closes the menu (and stops the preview music when it hides).
    tinsert(UISpecialFrames, "BoundToLearnSongSelect")
    f:HookScript("OnHide", function() GameUI:StopSongPreview() end)

    songSelect = f
    self:RefreshSongSelect()
end

-- Judgment rows for the round-over graph, in behavioural-design colours:
-- green success, gold reward, orange okay, muted red miss, magenta fake.
local RESULT_JUDGMENTS = {
    { key = "perfect",    label = "Perfect", r = 0.30, g = 0.85, b = 0.42 },
    { key = "great",      label = "Great",   r = 1.00, g = 0.82, b = 0.22 },
    { key = "good",       label = "Good",    r = 0.98, g = 0.60, b = 0.20 },
    { key = "miss",       label = "Miss",    r = 0.82, g = 0.35, b = 0.35 },
    { key = "redHerring", label = "Fake",    r = 0.80, g = 0.30, b = 0.55 },
}

function GameUI:CreateResultsPanel(f)
    -- Full-width, centered results: title/score/graph stacked in the middle, the
    -- played track's art below the stats, and the buttons centered under it.
    local rp = CreateFrame("Frame", nil, f)
    rp:SetPoint("TOPLEFT", 16, -14)
    rp:SetPoint("BOTTOMRIGHT", -16, 14)
    rp:SetFrameLevel(f:GetFrameLevel() + 20)
    rp:Hide()

    rp.title = rp:CreateFontString(nil, "OVERLAY")
    rp.title:SetFont("Fonts\\FRIZQT__.TTF", 22, "OUTLINE")
    rp.title:SetPoint("TOP", 0, -8)

    -- Difficulty badge in the top-right corner, colored to match the song-select tiers.
    rp.diffFS = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    rp.diffFS:SetPoint("TOPRIGHT", -12, -10)

    rp.scoreFS = rp:CreateFontString(nil, "OVERLAY")
    rp.scoreFS:SetFont("Fonts\\FRIZQT__.TTF", 40, "OUTLINE")
    rp.scoreFS:SetPoint("TOP", 0, -54)
    rp.scoreFS:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))

    rp.scoreLabel = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rp.scoreLabel:SetPoint("TOP", rp.scoreFS, "BOTTOM", 0, -1)
    rp.scoreLabel:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))

    rp.statFS = rp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rp.statFS:SetPoint("TOP", rp.scoreLabel, "BOTTOM", 0, -10)

    -- Performance row: judgment breakdown (left) and the attempt-history trend
    -- (right), centered as a pair so the panel height is unchanged.
    local BAR_W, ROWH = 150, 22
    local rowH = #RESULT_JUDGMENTS * ROWH
    local perfRow = CreateFrame("Frame", nil, rp)
    perfRow:SetSize(500, rowH)
    perfRow:SetPoint("TOP", rp.statFS, "BOTTOM", 0, -14)
    rp.perfRow = perfRow

    local graph = CreateFrame("Frame", nil, perfRow)
    graph:SetSize(240, rowH)
    graph:SetPoint("TOPLEFT", 0, 0)
    rp.graph = graph

    -- Attempt-history trend (persisted in songHistory, survives reloads): bars run
    -- oldest -> newest with the newest highlighted. Hidden on a track's first run.
    local trend = CreateFrame("Frame", nil, perfRow)
    trend:SetSize(220, rowH)
    trend:SetPoint("TOPRIGHT", 0, 0)
    rp.trend = trend
    -- Baseline for the trend bars: the bottom of the Miss row (4th of 5) relative to
    -- the frame top, so the histogram sits on the same line as the judgment bars
    -- instead of the frame floor (the hidden Fake row leaves a gap below Miss).
    rp.trendBaseY = -(3 * ROWH + 13)
    rp.trendLabel = trend:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rp.trendLabel:SetPoint("TOP", 0, 0)
    rp.trendLabel:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))
    rp.trendBars = {}
    for i = 1, SONG_HISTORY_MAX do
        rp.trendBars[i] = trend:CreateTexture(nil, "OVERLAY")
    end

    rp.bars = {}
    for i, j in ipairs(RESULT_JUDGMENTS) do
        local y = -(i - 1) * ROWH
        local lbl = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 0, y)
        lbl:SetWidth(50)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(j.label)
        lbl:SetTextColor(j.r, j.g, j.b)

        local track = graph:CreateTexture(nil, "ARTWORK")
        track:SetPoint("TOPLEFT", 52, y - 1)
        track:SetSize(BAR_W, 12)
        track:SetColorTexture(1, 1, 1, 0.08)

        local fill = graph:CreateTexture(nil, "OVERLAY")
        fill:SetPoint("TOPLEFT", 52, y - 1)
        fill:SetSize(1, 12)
        -- Glossy top-to-bottom gradient instead of a flat fill.
        fill:SetColorTexture(1, 1, 1, 1)
        fill:SetGradient("VERTICAL", CreateColor(j.r * 0.6, j.g * 0.6, j.b * 0.6, 0.95),
            CreateColor(mmin(1, j.r * 1.12), mmin(1, j.g * 1.12), mmin(1, j.b * 1.12), 0.95))

        local cnt = graph:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cnt:SetPoint("LEFT", track, "RIGHT", 6, 0)
        cnt:SetText("0")

        rp.bars[i] = { spec = j, label = lbl, track = track, fill = fill, count = cnt, w = BAR_W }
    end

    -- Played track's art, sitting between the stats and the buttons.
    rp.songImage = rp:CreateTexture(nil, "ARTWORK")
    rp.songImage:SetPoint("TOP", perfRow, "BOTTOM", 0, -16)
    rp.songImage:SetSize(300, 68)
    rp.songTitle = rp:CreateFontString(nil, "OVERLAY")
    rp.songTitle:SetFont("Fonts\\FRIZQT__.TTF", 17, "OUTLINE")
    rp.songTitle:SetPoint("CENTER", rp.songImage, "CENTER", 0, 7)
    rp.songTitle:SetTextColor(1, 1, 1)
    -- Artist under the title, matching the selected-song bubble's title/artist stack.
    rp.songArtist = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rp.songArtist:SetPoint("TOP", rp.songTitle, "BOTTOM", 0, -1)
    rp.songArtist:SetTextColor(1, 1, 1, 0.7)

    -- Back to Tracks sits top-left like a return button (with a left arrow); Try
    -- Again and Share are the primary actions, centered as a pair along the bottom.
    rp.backBtn = MakeBubbleButton(rp, "|TInterface\\Buttons\\UI-SpellbookIcon-PrevPage-Up:14:14|t Back to Tracks", 150, 24)
    rp.backBtn:SetPoint("TOPLEFT", 2, -4)
    rp.backBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ExitResultsMode()
    end)

    rp.retryBtn = MakeBubbleButton(rp, "Try Again", 128, 26)
    rp.retryBtn:SetPoint("BOTTOM", -70, 8)
    rp.retryBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        local r = GameUI.lastResults
        if r then
            if r.difficulty then BoundToLearn.db.game.difficulty = r.difficulty end
            if r.mode then BoundToLearn.db.game.mode = r.mode end
        end
        GameUI:ExitResultsMode()
        GameUI:StartFromSongSelect()
    end)

    rp.shareBtn = MakeBubbleButton(rp, "Share", 128, 26)
    rp.shareBtn:SetPoint("BOTTOM", 70, 8)
    rp.shareBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleShareMenu(rp.shareBtn)
    end)

    f.resultsPanel = rp
end

-- Draw the attempt-history mini bar chart: one bar per stored run (oldest -> newest),
-- heights normalized to the tallest, newest bar highlighted (green on a new best).
function GameUI:RenderAttemptTrend(rp, cmp)
    for i = 1, #rp.trendBars do rp.trendBars[i]:Hide() end
    local hist = cmp.history
    local n = hist and #hist or 0
    if n < 1 then rp.trend:Hide() return end
    rp.trend:Show()
    rp.trendLabel:SetText(n == 1 and "First attempt on this track" or sformat("Last %d attempts", n))
    local maxS = 1
    for i = 1, n do if hist[i] > maxS then maxS = hist[i] end end
    local TBW, TBH, GAP = 18, 58, 6
    for j = 1, n do
        local bar = rp.trendBars[j]
        bar:ClearAllPoints()
        bar:SetWidth(TBW)
        bar:SetHeight(mmax(2, (hist[j] / maxS) * TBH))
        -- Grow up from the Miss-row baseline so the histogram lines up with the
        -- judgment bars' bottom.
        bar:SetPoint("BOTTOM", rp.trend, "TOP", (j - (n + 1) / 2) * (TBW + GAP), rp.trendBaseY)
        local r, g, b, a
        if j == n then
            if cmp.isNewBest then r, g, b, a = 0.20, 0.90, 0.35, 0.95
            else r, g, b, a = 1.00, 0.82, 0.00, 0.95 end
        else
            r, g, b, a = 0.45, 0.55, 0.70, 0.72
        end
        bar:SetColorTexture(1, 1, 1, 1)
        bar:SetGradient("VERTICAL", CreateColor(r * 0.5, g * 0.5, b * 0.5, a), CreateColor(r, g, b, a))
        bar:Show()
    end
end

function GameUI:ShowResultsOnSelect(results)
    if not songSelect then self:CreateSongSelect() end
    songSelect.statsMode = false
    if songSelect.statsPanel then songSelect.statsPanel:Hide() end
    self.lastResults = results
    local hc = results.hitCounts or {}

    -- Hide the search box during results; it is a selection control.
    if songSelect.searchBox then
        songSelect.searchBox:SetText("")
        songSelect.searchBox:Hide()
    end

    local key = BoundToLearn.db.game.songKey
    local songs = ns.SongData.songs
    for i = 1, #songs do
        if songs[i].key == key then
            songSelect.selIndex = i
            break
        end
    end
    songSelect.animOffset = 0
    songSelect.donutDirty = true

    songSelect.resultsMode = true
    for _, control in ipairs(songSelect.leftControls) do control:Hide() end
    if songSelect.mainTitle then songSelect.mainTitle:Hide() end
    if songSelect.statsBtn then songSelect.statsBtn:Hide() end

    local rp = songSelect.resultsPanel
    local totalNotes = results.totalNotes or 0
    local accuracy = ns.Utils.HitAccuracy(hc)

    rp.title:SetText(results.focusFailed and "|cFFFF6666Round Over|r"
        or "|cFF" .. Theme.ACCENT_HEX .. "Round Complete|r")
    rp.scoreFS:SetText(sformat("%d", results.score or 0))
    local chartTotal = results.chartTotal or 0
    if chartTotal > 0 then
        rp.statFS:SetText(sformat(
            "Accuracy |cFFFFFFFF%.1f%%|r   Song |cFFFFFFFF%.0f%%|r   Max Combo |cFFFFFFFF%d|r",
            accuracy, (results.notesShown or 0) / chartTotal * 100, results.maxCombo or 0))
    else
        rp.statFS:SetText(sformat("Accuracy |cFFFFFFFF%.1f%%|r   Max Combo |cFFFFFFFF%d|r",
            accuracy, results.maxCombo or 0))
    end

    local diff = results.difficulty
    local dcol = DIFF_COLORS[diff] or { 0.8, 0.8, 0.8 }
    rp.diffFS:SetText((diff or ""):upper())
    rp.diffFS:SetTextColor(dcol[1], dcol[2], dcol[3])

    -- Per-song comparison: best on THIS track+difficulty plus the attempt trend.
    -- songCompare is the snapshot RecordSongScore stashed for this run.
    local cmp = self.songCompare
    local isNewBest = false
    if cmp and cmp.score == (results.score or 0) then
        isNewBest = cmp.isNewBest
        if cmp.isNewBest then
            rp.scoreLabel:SetText(cmp.prevBest > 0
                and sformat("|cFF33FF66NEW BEST!|r  (prev %d)", cmp.prevBest)
                or "|cFF33FF66NEW BEST!|r")
        else
            local gap = cmp.prevBest - cmp.score
            rp.scoreLabel:SetText(gap > 0
                and sformat("Best %d  |cFFFFAA88(%d below)|r", cmp.prevBest, gap)
                or sformat("Best %d  (matched)", cmp.prevBest))
        end
        self:RenderAttemptTrend(rp, cmp)
    else
        rp.scoreLabel:SetText("Score")
        rp.trend:Hide()
    end

    local maxCount = 1
    for _, bar in ipairs(rp.bars) do
        local c = hc[bar.spec.key] or 0
        if c > maxCount then maxCount = c end
    end
    for _, bar in ipairs(rp.bars) do
        local c = hc[bar.spec.key] or 0
        local show = bar.spec.key ~= "redHerring" or c > 0
        bar.label:SetShown(show)
        bar.track:SetShown(show)
        bar.fill:SetShown(show)
        bar.count:SetShown(show)
        if show then
            bar.fill:SetWidth(mmax(1, bar.w * (c / maxCount)))
            bar.count:SetText(sformat("%d", c))
        end
    end

    local song = songs[songSelect.selIndex]
    local img, tc = ns.SongData.InstanceImage(song)
    if img then
        rp.songImage:SetTexture(img)
        if tc then rp.songImage:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
        rp.songImage:SetVertexColor(0.62, 0.63, 0.67, 1)   -- lower gamma to match the wheel bubble
    else
        rp.songImage:SetTexture(nil)
        rp.songImage:SetColorTexture(0.10, 0.09, 0.08, 0.9)
    end
    rp.songTitle:SetText(song and song.title or "")
    rp.songArtist:SetText(song and song.artist or "")

    rp:Show()
    songSelect:Show()
    self:RefreshSongSelect()
    self:PlaySongPreview()

    if isNewBest and results.mode ~= "practice" and totalNotes >= 5 then
        self:PlayLevelUpEffect(songSelect)
    else
        self:HideLevelUpEffect()
    end
end

function GameUI:ExitResultsMode()
    if not songSelect then return end
    songSelect.resultsMode = false
    if songSelect.resultsPanel then songSelect.resultsPanel:Hide() end
    if self.shareMenu then self.shareMenu:Hide() end
    self:HideLevelUpEffect()
    for _, control in ipairs(songSelect.leftControls) do control:Show() end
    if songSelect.mainTitle then songSelect.mainTitle:Show() end
    if songSelect.statsBtn then songSelect.statsBtn:Show() end
    if songSelect.searchBox then
        songSelect.searchBox:Show()
        if songSelect.searchBox.placeholder then songSelect.searchBox.placeholder:Show() end
    end
    self:RefreshSongSelect()
end

-- Game stats overlay, reached from the Stats button on the select screen. Covers
-- the carousel with aggregate lifetime numbers; Back returns to track selection.
local STATS_SONG_DIFFS = { "Easy", "Medium", "Hard", "Extreme" }

-- Shared by the in-game stats page's Reset button and the options panel's reset
-- button, via a themed confirm dialog that floats above both windows.
function GameUI:ConfirmResetStats()
    Theme.ShowConfirm({
        title = "Reset Stats",
        body = "Reset all BoundToLearn statistics? This cannot be undone.",
        acceptText = _G["RESET"] or "Reset",
        onAccept = function()
            if ns.Stats then ns.Stats:ResetAll() end
            if ns.GameUI then ns.GameUI:RefreshStatsPanel() end
            if BoundToLearn then BoundToLearn:Print("Statistics reset.") end
        end,
    })
end

function GameUI:CreateStatsPanel(f)
    local sp = CreateFrame("Frame", nil, f)
    sp:SetPoint("TOPLEFT", 12, -12)
    sp:SetPoint("BOTTOMRIGHT", -12, 12)
    sp:SetFrameLevel(f:GetFrameLevel() + 25)
    sp:Hide()

    -- A page on the same window (like the round-over), not a separate box: no
    -- backing, so the track's expansion backdrop shows through. Back returns to
    -- the carousel.
    local backBtn = MakeBubbleButton(sp, "Back", 66, 22)
    backBtn:SetPoint("TOPLEFT", 2, -4)
    backBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:HideStatsPage()
    end)

    local resetBtn = MakeBubbleButton(sp, "Reset Stats", 92, 22)
    resetBtn:SetPoint("LEFT", backBtn, "RIGHT", 6, 0)
    resetBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ConfirmResetStats()
    end)

    local title = sp:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    title:SetPoint("TOP", 0, -8)
    title:SetText("Your Stats")
    title:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))

    -- Summary / By Song toggle.
    sp.summaryBtn = MakeBubbleButton(sp, "Summary", 78, 20)
    sp.summaryBtn:SetPoint("TOPRIGHT", -102, -5)
    sp.summaryBtn:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); GameUI:SetStatsView("summary") end)
    sp.songBtn = MakeBubbleButton(sp, "By Song", 78, 20)
    sp.songBtn:SetPoint("TOPRIGHT", -20, -5)
    sp.songBtn:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); GameUI:SetStatsView("song") end)

    -- ===== Summary view: lifetime / overall stats =====
    local sum = CreateFrame("Frame", nil, sp)
    sum:SetAllPoints()
    sp.summaryGroup = sum
    sp.values = {}
    local function stat(offsetX, y, key, label, big)
        local val = sum:CreateFontString(nil, "OVERLAY")
        val:SetFont("Fonts\\FRIZQT__.TTF", big and 28 or 19, "OUTLINE")
        val:SetPoint("TOP", sum, "TOP", offsetX, y)
        val:SetTextColor(1, 1, 1)
        local lbl = sum:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOP", val, "BOTTOM", 0, -2)
        lbl:SetText(label)
        lbl:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))
        sp.values[key] = val
    end
    local function header(y, text)
        local h = sum:CreateFontString(nil, "OVERLAY")
        h:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        h:SetPoint("TOP", 0, y)
        h:SetText(text)
        h:SetTextColor(1, 0.82, 0)
        local line = sum:CreateTexture(nil, "ARTWORK")
        line:SetPoint("TOP", h, "BOTTOM", 0, -3)
        line:SetSize(360, 1)
        line:SetColorTexture(1, 1, 1, 0.12)
    end

    stat(-175, -72, "completed", "Tracks Completed", true)
    stat(0,    -72, "accuracy",  "Lifetime Accuracy", true)
    stat(175,  -72, "hits",      "Notes Hit", true)

    header(-168, "Personal Bests")
    stat(-175, -196, "highscore", "High Score", false)
    stat(0,    -196, "combo",     "Longest Combo", false)
    stat(175,  -196, "bestacc",   "Best Accuracy", false)

    header(-284, "Best Score by Difficulty")
    stat(-198, -308, "Easy",    "Easy", false)
    stat(-66,  -308, "Medium",  "Medium", false)
    stat(66,   -308, "Hard",    "Hard", false)
    stat(198,  -308, "Extreme", "Extreme", false)

    local sumShare = MakeBubbleButton(sum, "Share Stats", 110, 22)
    sumShare:SetPoint("BOTTOM", sum, "BOTTOM", 0, 10)
    sumShare:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:OpenShareMenu(sumShare, GameUI:BuildSummaryShareText())
    end)

    -- ===== Song view: per-track stats =====
    local sg = CreateFrame("Frame", nil, sp)
    sg:SetAllPoints()
    sg:Hide()
    sp.songGroup = sg
    self:BuildStatsSongView(sg, sp)

    sp.statsView = "summary"
    f.statsPanel = sp
end

-- The per-track view inside the stats page: a search box, prev/next track picker, and a
-- per-difficulty table (best / accuracy / combo / plays) for the picked track.
function GameUI:BuildStatsSongView(sg, sp)
    local search = CreateFrame("EditBox", nil, sg)
    search:SetSize(240, 22)
    search:SetPoint("TOP", 0, -54)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlight")
    search:SetTextInsets(10, 10, 0, 0)
    Theme.StylePanel(search, 0.9)
    local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 10, 0)
    ph:SetText("Search a track...")
    search.placeholder = ph
    search:SetScript("OnTextChanged", function(self)
        self.placeholder:SetShown(self:GetText() == "")
    end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    sp.songSearch = search
    self:AttachSongSearchDropdown(search, function(key)
        songSelect.statsSongKey = key
        GameUI:RefreshStatsSongView()
    end)

    local prev = MakeBubbleButton(sg, "<", 26, 22)
    prev:SetPoint("TOPLEFT", 20, -104)
    prev:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); GameUI:CycleStatsSong(-1) end)
    local nxt = MakeBubbleButton(sg, ">", 26, 22)
    nxt:SetPoint("TOPRIGHT", -20, -104)
    nxt:SetScript("OnClick", function() PlayUISound(SOUND_CLICK); GameUI:CycleStatsSong(1) end)

    local nameFS = sg:CreateFontString(nil, "OVERLAY")
    nameFS:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    nameFS:SetPoint("LEFT", prev, "RIGHT", 6, 1)
    nameFS:SetPoint("RIGHT", nxt, "LEFT", -6, 1)
    nameFS:SetJustifyH("CENTER")
    nameFS:SetWordWrap(false)
    sp.songName = nameFS
    local artistFS = sg:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    artistFS:SetPoint("TOP", nameFS, "BOTTOM", 0, -1)
    sp.songArtistFS = artistFS

    local COLS, CW = { best = 190, acc = 300, combo = 395, plays = 485 }, 92
    local headY = -166
    local function hdr(text, rightX, leftAt)
        local h = sg:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if leftAt then
            h:SetPoint("TOPLEFT", leftAt, headY)
        else
            h:SetPoint("TOPLEFT", rightX - CW, headY); h:SetWidth(CW); h:SetJustifyH("RIGHT")
        end
        h:SetText(text); h:SetTextColor(1, 0.82, 0)
    end
    hdr("Difficulty", nil, 22)
    hdr("Best", COLS.best); hdr("Accuracy", COLS.acc); hdr("Combo", COLS.combo); hdr("Plays", COLS.plays)

    local ln = sg:CreateTexture(nil, "ARTWORK")
    ln:SetPoint("TOPLEFT", 20, headY - 16); ln:SetPoint("TOPRIGHT", -20, headY - 16)
    ln:SetHeight(1); ln:SetColorTexture(1, 1, 1, 0.12)

    sp.songRows = {}
    for i, diff in ipairs(STATS_SONG_DIFFS) do
        local ry = headY - 26 - (i - 1) * 30
        local row = {}
        row.diff = sg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        row.diff:SetPoint("TOPLEFT", 22, ry); row.diff:SetText(diff)
        local function cell(rightX)
            local fs = sg:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            fs:SetPoint("TOPLEFT", rightX - CW, ry); fs:SetWidth(CW); fs:SetJustifyH("RIGHT")
            return fs
        end
        row.score = cell(COLS.best); row.acc = cell(COLS.acc)
        row.combo = cell(COLS.combo); row.plays = cell(COLS.plays)
        sp.songRows[i] = row
    end

    local prog = sg:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    prog:SetPoint("TOPLEFT", 22, headY - 26 - 4 * 30 - 14)
    sp.songProgFS = prog

    local songShare = MakeBubbleButton(sg, "Share", 90, 22)
    songShare:SetPoint("BOTTOM", sg, "BOTTOM", 0, 10)
    songShare:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        local key = (songSelect and songSelect.statsSongKey) or BoundToLearn.db.game.songKey
        GameUI:OpenShareMenu(songShare, GameUI:BuildSongShareText(key))
    end)
end

function GameUI:RefreshStatsPanel()
    if not (songSelect and songSelect.statsPanel) then return end
    local sp = songSelect.statsPanel
    local stats = BoundToLearn.db.stats
    local g = BoundToLearn.db.game
    local songs = ns.SongData.songs
    local total = #songs

    local completed = 0
    local prog = g.songProgress or {}
    for i = 1, total do
        if (prog[songs[i].key] or 0) >= 0.99 then completed = completed + 1 end
    end

    local acc = (stats.lifetimeGameNotes or 0) > 0
        and (stats.lifetimeGameHits / stats.lifetimeGameNotes * 100) or 0
    local pb = stats.personalBest or {}

    sp.values.completed:SetText(sformat("%d|cFF888888 / %d|r", completed, total))
    sp.values.accuracy:SetText(sformat("%.0f%%", acc))
    sp.values.hits:SetText(sformat("%d", stats.lifetimeGameHits or 0))
    sp.values.highscore:SetText(sformat("%d", pb.highestScore or 0))
    sp.values.combo:SetText(sformat("%d", pb.longestCombo or 0))
    sp.values.bestacc:SetText(sformat("%.1f%%", pb.bestAccuracy or 0))

    local dbest = stats.difficultyBest or {}
    sp.values.Easy:SetText(sformat("%d", (dbest.Easy and dbest.Easy.highestScore) or 0))
    sp.values.Medium:SetText(sformat("%d", (dbest.Medium and dbest.Medium.highestScore) or 0))
    sp.values.Hard:SetText(sformat("%d", (dbest.Hard and dbest.Hard.highestScore) or 0))
    sp.values.Extreme:SetText(sformat("%d", (dbest.Extreme and dbest.Extreme.highestScore) or 0))

    if sp.songRows then self:RefreshStatsSongView() end
end

function GameUI:SetStatsView(view)
    local sp = songSelect and songSelect.statsPanel
    if not sp then return end
    sp.statsView = view
    sp.summaryGroup:SetShown(view ~= "song")
    sp.songGroup:SetShown(view == "song")
    sp.summaryBtn:SetAlpha(view ~= "song" and 1 or 0.55)
    sp.songBtn:SetAlpha(view == "song" and 1 or 0.55)
    self:RefreshStatsPanel()
end

function GameUI:RefreshStatsSongView()
    local sp = songSelect and songSelect.statsPanel
    if not sp or not sp.songRows then return end
    local g = BoundToLearn.db.game
    local key = songSelect.statsSongKey or g.songKey
    songSelect.statsSongKey = key
    local song = ns.SongData and ns.SongData.Get(key)
    sp.songName:SetText((song and song.title) or key or "-")
    sp.songArtistFS:SetText((song and song.artist) or "")
    local scores = g.songScores and g.songScores[key]
    local stats  = g.songStats and g.songStats[key]
    for i, diff in ipairs(STATS_SONG_DIFFS) do
        local row = sp.songRows[i]
        local best = (scores and scores[diff]) or 0
        local st = stats and stats[diff]
        local plays = (st and st.plays) or 0
        row.score:SetText(best > 0 and sformat("%d", best) or "-")
        row.acc:SetText((st and st.bestAccuracy and st.bestAccuracy > 0) and sformat("%.1f%%", st.bestAccuracy) or "-")
        row.combo:SetText((st and st.bestCombo and st.bestCombo > 0) and sformat("%d", st.bestCombo) or "-")
        row.plays:SetText(plays > 0 and sformat("%d", plays) or "-")
        row.diff:SetAlpha((plays > 0 or best > 0) and 1 or 0.45)
    end
    local prog = (g.songProgress and g.songProgress[key]) or 0
    sp.songProgFS:SetText(sformat("Best progress: |cFFFFCC00%d%%|r", mfloor(prog * 100 + 0.5)))
end

--------------------------------------------------------------------------
-- Share stats to chat: a themed destination dropdown. Public/group channels
-- gate on group/guild state; Whisper targets the current unit; Custom prompts
-- for a channel name or number. Selecting a row sends one SendChatMessage.
--------------------------------------------------------------------------
local SHARE_CHANNELS = {
    { chan = "SAY" },
    { chan = "YELL" },
    { chan = "PARTY",         enabled = function() return IsInGroup() end },
    { chan = "INSTANCE_CHAT", enabled = function() return IsInGroup(LE_PARTY_CATEGORY_INSTANCE or 2) end },
    { chan = "RAID",          enabled = function() return IsInRaid() end },
    { chan = "GUILD",         enabled = function() return IsInGuild() end },
}
local shareMenu

-- Whisper target for the current unit target, realm-qualified when cross-realm.
local function ShareTargetName()
    if not UnitExists("target") or not UnitIsPlayer("target") then return nil end
    local name, realm = UnitName("target")
    if not name then return nil end
    if realm and realm ~= "" then return name .. "-" .. realm end
    return name
end

-- Fit a chat payload under the 255-char limit by trimming the free-text head
-- (a song name) rather than the trailing stats.
local function ClampShare(head, tail)
    local budget = 255 - #tail
    if #head > budget then
        local cut = budget - 3
        if cut < 0 then cut = 0 end
        head = head:sub(1, cut) .. "..."
    end
    return head .. tail
end

function GameUI:BuildSummaryShareText()
    local stats = BoundToLearn.db.stats
    local g = BoundToLearn.db.game
    local songs = ns.SongData.songs
    local total = #songs
    local completed = 0
    local prog = g.songProgress or {}
    for i = 1, total do
        if (prog[songs[i].key] or 0) >= 0.99 then completed = completed + 1 end
    end
    local pb = stats.personalBest or {}
    local acc = (stats.lifetimeGameNotes or 0) > 0
        and (stats.lifetimeGameHits / stats.lifetimeGameNotes * 100) or 0
    return sformat("BoundToLearn | Overall: %d/%d tracks, high score %d, %dx combo, %.1f%% best acc (%.0f%% lifetime)",
        completed, total, pb.highestScore or 0, pb.longestCombo or 0, pb.bestAccuracy or 0, acc)
end

function GameUI:BuildSongShareText(key)
    local g = BoundToLearn.db.game
    local song = ns.SongData and ns.SongData.Get(key)
    local name = (song and song.title) or key or "?"
    local scores = (g.songScores and g.songScores[key]) or {}
    local sstats = (g.songStats and g.songStats[key]) or {}
    -- Share the best-scoring difficulty; fall back to the current one if unplayed.
    local bestDiff, bestScore = nil, -1
    for _, diff in ipairs(STATS_SONG_DIFFS) do
        local sc = scores[diff] or 0
        if sc > bestScore then bestScore, bestDiff = sc, diff end
    end
    if bestScore <= 0 then bestDiff = g.difficulty or "Medium" end
    local st = sstats[bestDiff]
    local tail = sformat(" [%s]: %d pts, %.1f%% acc, %dx combo",
        bestDiff, scores[bestDiff] or 0, (st and st.bestAccuracy) or 0, (st and st.bestCombo) or 0)
    return ClampShare("BoundToLearn | " .. name, tail)
end

function GameUI:OpenShareMenu(anchor, text)
    local rows = {}
    for i = 1, #SHARE_CHANNELS do
        local c = SHARE_CHANNELS[i]
        local on = (not c.enabled) or c.enabled()
        local chan = c.chan
        rows[#rows + 1] = {
            text = _G[chan] or chan,
            disabled = not on,
            onClick = on and function() SendChatMessage(text, chan) end or nil,
        }
    end
    local tname = ShareTargetName()
    rows[#rows + 1] = {
        text = tname and ((_G["WHISPER"] or "Whisper") .. ": " .. tname) or (_G["WHISPER"] or "Whisper"),
        disabled = not tname,
        onClick = tname and function() SendChatMessage(text, "WHISPER", nil, tname) end or nil,
    }
    rows[#rows + 1] = {
        text = "Custom Channel...",
        onClick = function()
            Theme.ShowPrompt({
                title = "Custom Channel",
                body = "Enter a channel name or number:",
                maxLetters = 48,
                acceptText = _G["OKAY"] or "OK",
                onAccept = function(val)
                    val = val and strtrim(val) or ""
                    if val == "" then return end
                    local idx = tonumber(val) or GetChannelName(val)
                    if idx and idx > 0 then SendChatMessage(text, "CHANNEL", nil, idx) end
                end,
            })
        end,
    }
    self:ShowShareDropdown(anchor, rows)
end

function GameUI:ShowShareDropdown(anchor, rows)
    local menu = shareMenu
    if not menu then
        menu = CreateFrame("Frame", nil, UIParent)
        Theme.StylePanel(menu, 0.97)
        menu:SetClampedToScreen(true)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu.rows = {}
        menu:SetScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(self)
                if not self:IsMouseOver()
                   and not (self._anchor and self._anchor:IsMouseOver())
                   and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                    self:Hide()
                end
            end)
        end)
        menu:SetScript("OnHide", function(self) self:SetScript("OnUpdate", nil) end)
        shareMenu = menu
    end
    menu._anchor = anchor

    local ROW_H, PAD, W = 24, 6, 174
    local n = #rows
    menu:SetSize(W, n * ROW_H + PAD * 2)
    menu:SetFrameLevel((anchor:GetFrameLevel() or 1) + 40)

    for i = 1, n do
        local spec = rows[i]
        local row = menu.rows[i]
        if not row then
            row = CreateFrame("Button", nil, menu)
            row:SetHeight(ROW_H)
            local hl = CreateFrame("Frame", nil, menu)
            hl:SetFrameLevel(menu:GetFrameLevel())
            hl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
            hl:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", 0, 0)
            Theme.Round(hl)
            Theme.SetBarHeight(hl, 10)
            Theme.SetBorderShown(hl, false)
            Theme.SetFillColor(hl, Theme.C.ACCENT, 0)
            row.hl = hl
            local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("LEFT", row, "LEFT", 10, 0)
            label:SetPoint("RIGHT", row, "RIGHT", -8, 0)
            label:SetJustifyH("LEFT")
            row.label = label
            row:HookScript("OnEnter", function(self)
                if self._enabled then Theme.SetFillColor(self.hl, Theme.C.ACCENT, 0.18) end
            end)
            row:HookScript("OnLeave", function(self)
                Theme.SetFillColor(self.hl, Theme.C.ACCENT, 0)
            end)
            menu.rows[i] = row
        end
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", menu, "TOPLEFT", PAD, -(PAD + (i - 1) * ROW_H))
        row:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -PAD, -(PAD + (i - 1) * ROW_H))
        row.label:SetText(spec.text)
        row._enabled = not spec.disabled
        Theme.SetFillColor(row.hl, Theme.C.ACCENT, 0)
        if spec.disabled then
            row.label:SetTextColor(Theme.RGB(Theme.C.TEXT_DISABLED, 1))
            row:SetScript("OnClick", nil)
        else
            row.label:SetTextColor(Theme.RGB(Theme.C.TEXT_BODY, 1))
            local onClick = spec.onClick
            row:SetScript("OnClick", function()
                PlayUISound(SOUND_CLICK)
                menu:Hide()
                if onClick then onClick() end
            end)
        end
        row:SetShown(true)
    end
    for i = n + 1, #menu.rows do menu.rows[i]:Hide() end

    -- Drop from the button, or flip above it when there is not enough room below.
    menu:ClearAllPoints()
    local opScale = anchor:GetEffectiveScale() or 1
    local mScale = menu:GetEffectiveScale() or 1
    local menuH = n * ROW_H + PAD * 2
    if (anchor:GetBottom() or 0) * opScale < menuH * mScale + 8 then
        menu:SetPoint("BOTTOMLEFT", anchor, "TOPLEFT", 0, 2)
    else
        menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    menu:Show()
    menu:Raise()
end

function GameUI:CycleStatsSong(dir)
    local songs = ns.SongData and ns.SongData.songs
    if not songs or #songs == 0 then return end
    local key = (songSelect and songSelect.statsSongKey) or BoundToLearn.db.game.songKey
    local idx = 1
    for i, s in ipairs(songs) do
        if s.key == key then idx = i; break end
    end
    idx = ((idx - 1 + dir) % #songs) + 1
    songSelect.statsSongKey = songs[idx].key
    self:RefreshStatsSongView()
end

function GameUI:ShowStatsPage(songKey)
    if not songSelect then self:CreateSongSelect() end
    if not songSelect.statsPanel then self:CreateStatsPanel(songSelect) end
    if songSelect.resultsMode then self:ExitResultsMode() end
    songSelect.statsMode = true
    for _, control in ipairs(songSelect.leftControls) do control:Hide() end
    if songSelect.mainTitle then songSelect.mainTitle:Hide() end
    if songSelect.statsBtn then songSelect.statsBtn:Hide() end
    if songSelect.searchBox then
        songSelect.searchBox:SetText("")
        songSelect.searchBox:Hide()
        if songSelect.searchBox.placeholder then songSelect.searchBox.placeholder:Hide() end
    end
    songSelect.statsPanel:Show()
    if songKey then songSelect.statsSongKey = songKey end
    self:SetStatsView(songKey and "song" or (songSelect.statsPanel.statsView or "summary"))
    self:RefreshSongSelect()
end

function GameUI:HideStatsPage()
    if not songSelect then return end
    songSelect.statsMode = false
    if songSelect.statsPanel then songSelect.statsPanel:Hide() end
    for _, control in ipairs(songSelect.leftControls) do control:Show() end
    if songSelect.mainTitle then songSelect.mainTitle:Show() end
    if songSelect.statsBtn then songSelect.statsBtn:Show() end
    if songSelect.searchBox then
        songSelect.searchBox:Show()
        if songSelect.searchBox.placeholder then songSelect.searchBox.placeholder:Show() end
    end
    self:RefreshSongSelect()
end

function GameUI:ToggleStatsPanel()
    if not songSelect then return end
    if songSelect.statsMode then self:HideStatsPage() else self:ShowStatsPage() end
end

-- The carousel always walks the full track list; search scrolls it to a match
-- rather than filtering (a short filtered list would repeat around the wheel).
function GameUI:GetWheelSongs()
    return ns.SongData.songs
end

-- Scroll the carousel to the track that best matches the query: a title prefix
-- wins over a title substring, which wins over an artist match.
-- Fuzzy track matching for the search boxes (carousel + stats), in the spirit of the
-- main search bar: substring/prefix beats a subsequence beats a small typo, title before
-- artist. Reuses one scratch row for the edit distance to stay allocation-free.
local sbyte = string.byte
local fuzzRow = {}
local function EditDistance(a, la, b, lb)
    for j = 0, lb do fuzzRow[j] = j end
    for i = 1, la do
        local prev = fuzzRow[0]
        fuzzRow[0] = i
        local ac = sbyte(a, i)
        for j = 1, lb do
            local tmp = fuzzRow[j]
            local cost = (ac == sbyte(b, j)) and 0 or 1
            local m = fuzzRow[j] + 1
            local d = fuzzRow[j - 1] + 1
            if d < m then m = d end
            d = prev + cost
            if d < m then m = d end
            fuzzRow[j] = m
            prev = tmp
        end
    end
    return fuzzRow[lb]
end

local function IsSubseq(word, query, qlen)
    local wi, wl = 1, #word
    for qi = 1, qlen do
        local qc = sbyte(query, qi)
        local found = false
        while wi <= wl do
            if sbyte(word, wi) == qc then wi = wi + 1; found = true; break end
            wi = wi + 1
        end
        if not found then return false end
    end
    return true
end

local function SongMatchScore(song, query, qlen)
    local title = song.title:lower()
    local at = title:find(query, 1, true)
    if at then return 200 - mmin(at, 40) end               -- substring; prefix scores highest
    for word in title:gmatch("[%w']+") do
        if #word >= qlen and IsSubseq(word, query, qlen) then return 120 end
    end
    if IsSubseq(title, query, qlen) then return 90 end
    if qlen >= 3 then
        local budget = qlen >= 6 and 2 or 1
        for word in title:gmatch("[%w']+") do
            local wl = #word
            local diff = wl - qlen
            if diff < 0 then diff = -diff end
            if diff <= budget and sbyte(word, 1) == sbyte(query, 1)
               and EditDistance(query, qlen, word, wl) <= budget then
                return 70
            end
        end
    end
    local artist = song.artist and song.artist:lower()
    if artist then
        local aa = artist:find(query, 1, true)
        if aa then return 40 - mmin(aa, 20) end
        if IsSubseq(artist, query, qlen) then return 25 end
    end
    return 0
end

-- All tracks that match the query, ranked best-first: { key, score, title, artist }.
local rankTmp = {}
local function rankDesc(a, b) return a[2] > b[2] end
local function RankedSongMatches(query)
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return nil end
    local qlen = #query
    local songs = ns.SongData and ns.SongData.songs
    if not songs then return nil end
    for i = #rankTmp, 1, -1 do rankTmp[i] = nil end
    for i = 1, #songs do
        local sg = songs[i]
        local s = SongMatchScore(sg, query, qlen)
        if s > 0 then rankTmp[#rankTmp + 1] = { sg.key, s, sg.title, sg.artist } end
    end
    table.sort(rankTmp, rankDesc)
    return rankTmp
end

-- A results dropdown under a search box (like the main search bar): typing shows the
-- ranked matches, click a row (or Enter for the top one) to pick. onSelect(key) is the
-- caller's action; the box does not instant-jump while you type.
function GameUI:AttachSongSearchDropdown(editBox, onSelect)
    local dd = CreateFrame("Frame", nil, editBox)
    dd:SetPoint("TOPLEFT", editBox, "BOTTOMLEFT", 0, -2)
    dd:SetPoint("TOPRIGHT", editBox, "BOTTOMRIGHT", 0, -2)
    dd:SetFrameStrata("FULLSCREEN_DIALOG")
    dd:SetFrameLevel(editBox:GetFrameLevel() + 30)
    Theme.StylePanel(dd, 0.98)
    dd:Hide()
    editBox.searchDropdown = dd

    local ROW_H = 28
    local function selectKey(key)
        if not key then return end
        PlayUISound(SOUND_CLICK)
        editBox:SetText("")
        editBox:ClearFocus()
        dd:Hide()
        onSelect(key)
    end

    dd.rows = {}
    for i = 1, 7 do
        local row = CreateFrame("Button", nil, dd)
        row:SetHeight(ROW_H)
        row:SetPoint("TOPLEFT", 3, -3 - (i - 1) * ROW_H)
        row:SetPoint("TOPRIGHT", -3, -3 - (i - 1) * ROW_H)
        local hl = row:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetColorTexture(Theme.RGB(Theme.C.ACCENT, 0.22))
        local t = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        t:SetPoint("LEFT", 8, 5); t:SetJustifyH("LEFT")
        row.titleFS = t
        local a = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        a:SetPoint("LEFT", 8, -7); a:SetJustifyH("LEFT")
        row.artistFS = a
        row:SetScript("OnClick", function(self) selectKey(self.songKey) end)
        row:Hide()
        dd.rows[i] = row
    end

    local function populate()
        local matches = RankedSongMatches(editBox:GetText())
        local n = matches and mmin(#matches, #dd.rows) or 0
        if n == 0 then dd:Hide(); return end
        for i = 1, #dd.rows do
            local row, m = dd.rows[i], matches[i]
            if m then
                row.songKey = m[1]
                row.titleFS:SetText(m[3])
                row.artistFS:SetText(m[4] or "")
                row:Show()
            else
                row:Hide()
            end
        end
        dd:SetHeight(6 + n * ROW_H)
        dd:Show()
    end

    editBox:HookScript("OnTextChanged", function(_, userInput) if userInput then populate() end end)
    editBox:HookScript("OnEditFocusLost", function() C_Timer.After(0.2, function() dd:Hide() end) end)
    editBox:HookScript("OnEnterPressed", function()
        if dd:IsShown() and dd.rows[1]:IsShown() then selectKey(dd.rows[1].songKey) end
    end)
    editBox:HookScript("OnEscapePressed", function() dd:Hide() end)
    return dd
end

function GameUI:CycleSong(step)
    if not songSelect or not step or step == 0 then return end
    -- Keep the round-over up until the player explicitly picks a button. Scrolling
    -- used to drop straight back to track selection, which read like a timeout.
    if songSelect.resultsMode then return end
    if songSelect.searchBox then songSelect.searchBox:ClearFocus() end
    local songs = self:GetWheelSongs()
    local n = #songs
    if n == 0 then return end
    songSelect.selIndex = ((songSelect.selIndex - 1 + step) % n) + 1
    BoundToLearn.db.game.songKey = songs[songSelect.selIndex].key
    songSelect.animOffset = mmax(-1.4, mmin(1.4, (songSelect.animOffset or 0) + step))
    PlayUISound(SOUND_CLICK)
    self:RefreshSongSelect()
    self:PlaySongPreview()
end

-- Pixels over which a wheel bubble fades to zero as its far edge reaches the
-- viewport boundary. Guarantees a bubble is invisible by the time it clips.
local WHEEL_EDGE_FADE = 16

-- Positions/tilts/colours every wheel slot from the current selection plus the
-- live animation offset. Called each animation frame and on any change.
function GameUI:PositionWheel()
    if not songSelect then return end
    local songs = self:GetWheelSongs()
    local n = #songs
    if n == 0 then return end
    local sel = songSelect.selIndex or 1
    local off = songSelect.animOffset or 0
    local center = songSelect.wheelCenter
    local baseLevel = songSelect.wheelClip:GetFrameLevel() + 2
    local ar, ag, ab = Theme.RGB(Theme.C.ACCENT_BRIGHT)
    local slots = songSelect.slots
    for s, slot in ipairs(slots) do
        local home = s - center
        local sg = songs[((sel - 1 + home) % n) + 1]
        slot.songKey = sg.key
        slot.dist = home
        local e = home + off
        local ae = e < 0 and -e or e
        local near = mmax(0, 1 - mmin(ae, 1))
        local h = mfloor(35 + near * 23)                 -- selected grows to ~58 for its art
        slot._e = e
        slot._h = h
        slot:SetSize(mmax(24, mfloor(252 + near * 18)), h)
        slot.titleFS:SetFont("Fonts\\FRIZQT__.TTF", mmax(11, mfloor(14 + near * 4)), "")
        slot.titleFS:SetText(sg.title)
        -- Lift the title as a bubble grows (the artist is anchored below it and
        -- follows), so both sit above the duration instead of centred over the art.
        local ty = mfloor(near * 8)
        slot.titleFS:ClearAllPoints()
        slot.titleFS:SetPoint("LEFT", 40, ty)
        slot.titleFS:SetPoint("RIGHT", -14, ty)
        local secs = mfloor(ns.SongData.PlayLength(sg) + 0.5)
        slot.durFS:SetText(mfloor(secs / 60) .. ":" .. (secs % 60 < 10 and "0" or "") .. (secs % 60))
        slot.durFS:SetTextColor(Theme.RGB(Theme.C.TEXT_PRIMARY, mmax(0.4, 0.85 - ae * 0.12)))
        local dsz = mmax(13, mfloor(h * 0.55))
        slot.donut:SetSize(dsz, dsz)
        -- Reset texcoords before choosing art. SetAtlas does NOT clear a prior
        -- SetTexCoord, so a slot that just showed the cropped instance image keeps
        -- that crop on its atlas: the neighbour-of-selection distortion that appears
        -- only on the side songs scroll toward and sticks until reload. Selected
        -- bubble shows its themed dungeon/raid art; the rest are the renown atlas
        -- desaturated to silver so they read on any backdrop.
        slot.bg:SetTexCoord(0, 1, 0, 1)
        -- Atlas hover glow matches the atlas bubbles; suppress it when the nine-slice
        -- art is showing (its rounded silhouette differs from the atlas shape).
        slot.hl:SetAlpha(0.22)
        if ae < 0.5 then
            local img, tc = ns.SongData.InstanceImage(sg)
            if img then
                -- Real image clipped to the bubble shape by the nine-slice overlay;
                -- hide the square bg texture underneath it.
                Theme.SetArtCorner(slot, slot._h * 0.32)
                Theme.SetArt(slot, img, tc[1], tc[2], tc[3], tc[4])
                Theme.SetArtVertexColor(slot, 0.62, 0.63, 0.67, 1)  -- lower gamma: ground the hazy EJ backdrop
                Theme.ShowArt(slot, true)
                slot.bg:Hide()
                slot.hl:SetAlpha(0)
            else
                Theme.ShowArt(slot, false)
                slot.bg:Show()
                slot.bg:SetAtlas("UI-Journeys-Renown-Button-pressed")
                slot.bg:SetDesaturated(false)
                slot.bg:SetVertexColor(0.62, 0.63, 0.67, 1)
            end
            slot.titleFS:SetTextColor(1, 1, 1)
        else
            Theme.ShowArt(slot, false)
            slot.bg:Show()
            slot.bg:SetAtlas("UI-Journeys-Renown-Button")
            slot.bg:SetDesaturated(true)
            if slot.hover then
                slot.bg:SetVertexColor(0.92, 0.94, 1, 1)
                slot.titleFS:SetTextColor(Theme.RGB(Theme.C.TEXT_PRIMARY))
            else
                local v = mmax(0.55, 0.85 - ae * 0.07)
                slot.bg:SetVertexColor(v * 0.92, v * 0.96, v, 1)     -- cool silver
                slot.titleFS:SetTextColor(Theme.RGB(Theme.C.TEXT_PRIMARY, mmax(0.5, 1 - ae * 0.12)))
            end
        end
        slot.bg:SetRotation(0)
        if ae < 0.5 and sg.artist then
            slot.artistFS:SetText(sg.artist)
            slot.artistFS:SetTextColor(1, 1, 1, 0.7)
            slot.artistFS:Show()
        else
            slot.artistFS:Hide()
        end
        if songSelect.donutDirty or slot.donutKey ~= slot.songKey then
            slot.donutKey = slot.songKey
            SetDonut(slot.donut, SongBestProgress(sg.key), ar, ag, ab)
        end
        -- Depth fade by distance; the final clip-aware alpha is applied in the
        -- positioning pass below, once each slot's on-screen position is known.
        slot._depthAlpha = 1 - mmin(ae, 4) * 0.06
        slot:SetFrameLevel(baseLevel + mmax(0, mfloor((center - ae) * 2)))
    end

    -- Equal visual gap between every bubble despite the centre bubble growing:
    -- position by cumulative half-heights + a constant gap, then anchor the e=0
    -- point to the viewport centre so the selection sits in the middle. The gap
    -- also clears the renown-atlas glow bleed so the tall selected bubble does not
    -- cover the edges of its neighbours.
    local GAP = 11
    local yc = {}
    yc[1] = 0
    for s = 2, #slots do
        yc[s] = yc[s - 1] - (slots[s - 1]._h * 0.5 + GAP + slots[s]._h * 0.5)
    end
    local y0 = yc[1]
    for s = 1, #slots - 1 do
        local ea, eb = slots[s]._e, slots[s + 1]._e
        if ea <= 0 and eb >= 0 and eb ~= ea then
            y0 = yc[s] + (0 - ea) / (eb - ea) * (yc[s + 1] - yc[s])
            break
        end
    end
    -- Apply position, then a clip-aware alpha. A slot fades as it crosses the
    -- viewport edge and is hidden once mostly clipped, so scrolling never leaves a
    -- hard-cut sliver at the top or bottom (the bug that only appeared in motion).
    -- The right offset is constant so every bubble's right edge lines up.
    local viewHalf = songSelect.wheelClip:GetHeight() * 0.5
    for s, slot in ipairs(slots) do
        slot:ClearAllPoints()
        slot:SetPoint("RIGHT", songSelect.wheelClip, "RIGHT", 14, yc[s] - y0)
        if songSelect.resultsMode or songSelect.statsMode then
            slot:Hide()
        elseif viewHalf < 1 then
            slot:SetAlpha(slot._depthAlpha or 1)
            slot:Show()
        else
            -- Fade a bubble out as its FAR edge nears the viewport boundary, so it
            -- reaches zero before the clip cuts it. Keying off the outer edge (not
            -- the amount already clipped) means no partial-clipped sliver is ever
            -- left visible, in motion or at rest.
            local pos = yc[s] - y0
            local dist = pos < 0 and -pos or pos
            local outerEdge = dist + slot._h * 0.5
            local edgeFade = (viewHalf - outerEdge) / WHEEL_EDGE_FADE
            if edgeFade < 0 then edgeFade = 0 elseif edgeFade > 1 then edgeFade = 1 end
            local a = (slot._depthAlpha or 1) * edgeFade
            slot:SetAlpha(a)
            slot:SetShown(a > 0.02)
        end
    end
    songSelect.donutDirty = false
end

-- Diagnostic: dump each bubble's real rendered bounds against the clip region so a
-- persisting "crop" can be pinned to an actual clipped slot (or ruled out). Run
-- /btl wheeldbg after scrolling and stopping. overTop/overBot > 0 on a shown slot
-- means that slot is being hard-clipped at the top/bottom edge.
function GameUI:DumpWheel()
    if not songSelect then BoundToLearn:Print("wheeldbg: song select not open"); return end
    local wc = songSelect.wheelClip
    local ct, cb = wc:GetTop(), wc:GetBottom()
    local clips = wc.DoesClipChildren and wc:DoesClipChildren()
    BoundToLearn:Print(sformat("wheelClip h=%.0f top=%.0f bot=%.0f clips=%s animOff=%.3f results=%s stats=%s",
        wc:GetHeight(), ct or -1, cb or -1, tostring(clips), songSelect.animOffset or 0,
        tostring(songSelect.resultsMode), tostring(songSelect.statsMode)))
    local cl, cr = wc:GetLeft(), wc:GetRight()
    for s, slot in ipairs(songSelect.slots) do
        local st, sb = slot:GetTop(), slot:GetBottom()
        local sl, sr = slot:GetLeft(), slot:GetRight()
        local overTop = (st and ct) and (st - ct) or 0
        local overBot = (sb and cb) and (cb - sb) or 0
        local overL = (sl and cl) and (cl - sl) or 0   -- >0: slot spills past clip LEFT
        local overR = (sr and cr) and (sr - cr) or 0   -- >0: slot spills past clip RIGHT
        local x1, _, _, y2 = slot.bg:GetTexCoord()      -- L, _, _, B; stale != 0/1
        local x2 = select(5, slot.bg:GetTexCoord())     -- R
        BoundToLearn:Print(sformat("  s%d %-11s e=%.2f w=%.0f h=%.0f a=%.2f shown=%s oT=%.0f oB=%.0f oL=%.0f oR=%.0f tc=%.2f,%.2f,%.2f",
            s, tostring(slot.songKey), slot._e or 0, slot:GetWidth() or 0, slot._h or 0, slot:GetAlpha(),
            tostring(slot:IsShown()), overTop, overBot, overL, overR, x1 or 0, x2 or 0, y2 or 0))
    end
end

function GameUI:RefreshSongSelect()
    if not songSelect then return end
    local key = BoundToLearn.db.game.songKey
    local song = ns.SongData and ns.SongData.Get(key)
    if not song then return end

    local songs = self:GetWheelSongs()
    for i = 1, #songs do
        if songs[i].key == key then songSelect.selIndex = i break end
    end

    if songSelect.xpacBg then
        songSelect.xpacBg:SetAtlas(ns.SongData.XpacBackground(song))
    end

    if songSelect.radar then
        SetRadar(songSelect.radar, ns.SongData.Radar(song, BoundToLearn.db.game.difficulty))
    end

    local curDiff = BoundToLearn.db.game.difficulty
    for i, drow in ipairs(songSelect.diffRows) do
        local name = drow.diffName
        local c = DIFF_COLORS[name]
        local selected = (name == curDiff)
        if selected then
            -- Tint the shared silver texture with the difficulty colour.
            drow.dbg:SetVertexColor(c[1], c[2], c[3])
            drow.label:SetTextColor(1, 1, 1)
        else
            drow.dbg:SetVertexColor(0.80, 0.83, 0.88)
            drow.label:SetTextColor(c[1] * 0.7, c[2] * 0.7, c[3] * 0.7)
        end
        local rating = (ns.SongData and ns.SongData.Rating(song, name)) or 5
        SetDiffBar(songSelect.diffSegs[i], rating, not selected)
    end

    local best = SongBestScore(key, curDiff)
    if best > 0 then
        songSelect.bestText:SetText(sformat("Best on %s: |cFFFFCC00%d|r", curDiff, best))
    else
        songSelect.bestText:SetText(sformat("Best on %s: |cFF888888none yet|r", curDiff))
    end
    songSelect.bestText:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))

    self:PositionWheel()
end

-- Preview the selected track while the select screen is open. Debounced so fast
-- scrolling only plays the track the player lands on. PlayMusic plays Blizzard's own
-- file by FileDataID (nothing bundled) and takes over the music channel, so the
-- client's zone music is silenced with no muting needed. The client cannot seek, so
-- the preview starts at 0:00; a long-intro track plays its intro before the hook.
local previewToken = 0
function GameUI:StopSongPreview()
    previewToken = previewToken + 1   -- invalidate any pending debounce
    StopMusic()
end

function GameUI:PlaySongPreview()
    if not (songSelect and songSelect:IsShown()) then return end
    if not BoundToLearn.db.game.soundEnabled then return end
    previewToken = previewToken + 1
    local token = previewToken
    C_Timer.After(0.3, function()
        if token ~= previewToken then return end
        if not (songSelect and songSelect:IsShown()) then return end
        local song = ns.SongData and ns.SongData.Get(BoundToLearn.db.game.songKey)
        if song and song.id then PlayMusic(song.id) end
    end)
end

function GameUI:ShowSongSelect()
    if not songSelect then self:CreateSongSelect() end
    if songSelect.resultsMode then self:ExitResultsMode() end
    if songSelect.statsMode then self:HideStatsPage() end
    self:RefreshSongSelect()
    songSelect:Show()
    self:PlaySongPreview()
end

function GameUI:HideSongSelect()
    if songSelect then songSelect:Hide() end
    if modifierDropdown then modifierDropdown:Hide() end
    if self.songMenu and self.songMenu.catcher then self.songMenu.catcher:Hide() end
    self:StopSongPreview()
end

function GameUI:StartFromSongSelect()
    -- Do not hide the carousel yet: OnGameStart hides it once a round actually
    -- begins, so cancelling the pre-game warning leaves the menu in place.
    if modifierDropdown then modifierDropdown:Hide() end
    if BoundToLearn then BoundToLearn:ToggleGame() end
end

function GameUI:CreatePauseOverlay()
    pauseOverlay = CreateFrame("Frame", nil, gameOverlay)
    pauseOverlay:SetAllPoints()
    pauseOverlay:SetFrameStrata("FULLSCREEN")
    pauseOverlay:SetFrameLevel(65)
    pauseOverlay:Hide()

    local bg = pauseOverlay:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.5)

    pauseText = pauseOverlay:CreateFontString(nil, "OVERLAY")
    pauseText:SetFont("Fonts\\FRIZQT__.TTF", 36, "OUTLINE")
    pauseText:SetPoint("CENTER", 0, 40)
    pauseText:SetText("|cFFFFCC00PAUSED|r")

    local hint = pauseOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hint:SetPoint("TOP", pauseText, "BOTTOM", 0, -12)
    hint:SetText("Click Pause to resume, or Stop to end")
    hint:SetTextColor(0.8, 0.8, 0.8)
end

function GameUI:CreateDangerOverlay()
    dangerOverlay = CreateFrame("Frame", nil, gameOverlay)
    dangerOverlay:SetAllPoints()
    dangerOverlay:SetFrameLevel(gameOverlay:GetFrameLevel() + 2)
    dangerOverlay:Hide()

    -- Red vignette edges (4 gradient textures around screen borders)
    local size = 150

    local top = dangerOverlay:CreateTexture(nil, "OVERLAY")
    top:SetPoint("TOPLEFT")
    top:SetPoint("TOPRIGHT")
    top:SetHeight(size)
    top:SetColorTexture(0.6, 0, 0, 1)
    top:SetGradient("VERTICAL", CreateColor(0.6, 0, 0, 0), CreateColor(0.6, 0, 0, 0.5))
    dangerOverlay.top = top

    local bottom = dangerOverlay:CreateTexture(nil, "OVERLAY")
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(size)
    bottom:SetColorTexture(0.6, 0, 0, 1)
    bottom:SetGradient("VERTICAL", CreateColor(0.6, 0, 0, 0.5), CreateColor(0.6, 0, 0, 0))
    dangerOverlay.bottom = bottom

    local left = dangerOverlay:CreateTexture(nil, "OVERLAY")
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(size)
    left:SetColorTexture(0.6, 0, 0, 1)
    left:SetGradient("HORIZONTAL", CreateColor(0.6, 0, 0, 0.5), CreateColor(0.6, 0, 0, 0))
    dangerOverlay.left = left

    local right = dangerOverlay:CreateTexture(nil, "OVERLAY")
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(size)
    right:SetColorTexture(0.6, 0, 0, 1)
    right:SetGradient("HORIZONTAL", CreateColor(0.6, 0, 0, 0), CreateColor(0.6, 0, 0, 0.5))
    dangerOverlay.right = right

    -- Screen pulse animation for critical focus
    dangerPulseAG = dangerOverlay:CreateAnimationGroup()
    dangerPulseAG:SetLooping("BOUNCE")
    local pulse = dangerPulseAG:CreateAnimation("Alpha")
    pulse:SetFromAlpha(1)
    pulse:SetToAlpha(0.3)
    pulse:SetDuration(0.6)
end

-- In-round life gauge: a strip of keycaps above the score HUD that drains as
-- focus is lost. Enough misses empty it and end the song.
function GameUI:CreateHealthBar()
    if self.healthFrame then return end
    -- The whole in-round HUD: a slim standalone bar (not the old score panel).
    -- Life gauge on the left, compact combo/score/timer readouts and small
    -- pause/stop controls on the right.
    local hf = CreateFrame("Frame", nil, gameOverlay or UIParent)
    hf:SetSize(640, 34)
    hf:SetPoint("TOP", UIParent, "TOP", 0, -22)
    hf:SetFrameStrata("FULLSCREEN")
    hf:SetFrameLevel(80)
    Theme.StylePanel(hf, 0.92)
    hf:Hide()

    local label = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 12, 0)
    label:SetText("LIFE")
    label:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))

    hf.lifeBar = MakeLifeBar(hf, 176, 14)
    hf.lifeBar:SetPoint("LEFT", 44, 0)

    hf.diffFS = hf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    hf.diffFS:SetPoint("LEFT", hf.lifeBar, "RIGHT", 16, 0)

    local stopBtn = Theme.CreateButton(hf, "Stop", 52, 22)
    stopBtn:SetPoint("RIGHT", -8, 0)
    stopBtn:SetScript("OnClick", function() if ns.Game then ns.Game:Stop() end end)
    hf.stopBtn = stopBtn

    local pauseBtn = Theme.CreateButton(hf, "Pause", 60, 22)
    pauseBtn:SetPoint("RIGHT", stopBtn, "LEFT", -4, 0)
    pauseBtn:SetScript("OnClick", function()
        if ns.Game then
            if ns.Game:IsPaused() then ns.Game:Resume() else ns.Game:Pause() end
        end
    end)
    hf.pauseBtn = pauseBtn

    local timerFS = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    timerFS:SetPoint("RIGHT", pauseBtn, "LEFT", -12, 0)
    hf.timerFS = timerFS

    local scoreFS = hf:CreateFontString(nil, "OVERLAY")
    scoreFS:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    scoreFS:SetPoint("RIGHT", timerFS, "LEFT", -16, 0)
    scoreFS:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))
    hf.scoreFS = scoreFS

    local comboFS = hf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    comboFS:SetPoint("RIGHT", scoreFS, "LEFT", -14, 0)
    hf.comboFS = comboFS

    self.healthFrame = hf
end

-- Sit the health bar just above the note start line, so notes appear to fall out from
-- under it. screenY is the shared start line in screen pixels (from PrepChart).
function GameUI:PlaceHealthBarAtLine(screenY)
    local hf = self.healthFrame
    if not hf or not screenY then return end
    hf:ClearAllPoints()
    hf:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, (screenY + 6) / hf:GetEffectiveScale())
end

function GameUI:UpdateLifeBar(pct)
    local hf = self.healthFrame
    if hf and hf.lifeBar then SetLifeBar(hf.lifeBar, pct or 0) end
end

function GameUI:UpdateFocusBar(current, max)
    self:UpdateLifeBar(max > 0 and (current / max) or 0)
    if not dangerOverlay then return end
    local pct = current / max

    if pct <= 0.6 then
        dangerOverlay:Show()
        -- Intensity scales from 0 at 60% to 1 at 0%
        local intensity = mmin(1, (0.6 - pct) / 0.6)
        local alpha = intensity * 0.55
        dangerOverlay.top:SetAlpha(alpha)
        dangerOverlay.bottom:SetAlpha(alpha)
        dangerOverlay.left:SetAlpha(alpha)
        dangerOverlay.right:SetAlpha(alpha)

        -- Pulse the whole overlay when critical
        if pct <= 0.2 then
            if not dangerPulseAG:IsPlaying() then
                dangerOverlay:SetAlpha(1)
                dangerPulseAG:Play()
            end
        else
            if dangerPulseAG:IsPlaying() then
                dangerPulseAG:Stop()
                dangerOverlay:SetAlpha(1)
            end
        end
    else
        if dangerPulseAG:IsPlaying() then
            dangerPulseAG:Stop()
            dangerOverlay:SetAlpha(1)
        end
        dangerOverlay:Hide()
    end
end

local streakText
local streakFadeAG
local lastStreakCombo = 0

function GameUI:CreateStreakTitle()
    streakText = gameOverlay:CreateFontString(nil, "OVERLAY")
    streakText:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    streakText:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
    streakText:SetAlpha(0)

    streakFadeAG = streakText:CreateAnimationGroup()
    local fadeIn = streakFadeAG:CreateAnimation("Alpha")
    fadeIn:SetFromAlpha(0)
    fadeIn:SetToAlpha(1)
    fadeIn:SetDuration(0.2)
    fadeIn:SetOrder(1)
    local hold = streakFadeAG:CreateAnimation("Alpha")
    hold:SetFromAlpha(1)
    hold:SetToAlpha(1)
    hold:SetDuration(1.2)
    hold:SetOrder(2)
    local fadeOut = streakFadeAG:CreateAnimation("Alpha")
    fadeOut:SetFromAlpha(1)
    fadeOut:SetToAlpha(0)
    fadeOut:SetDuration(0.5)
    fadeOut:SetOrder(3)
    streakFadeAG:SetScript("OnFinished", function() streakText:SetAlpha(0) end)
end

function GameUI:ShowStreakTitle(combo)
    if not streakText then return end
    local Ach = ns.Achievements
    if not Ach then return end
    local title = Ach:GetStreakTitle(combo)
    if not title then return end
    -- Only show when crossing a new threshold
    local prev = Ach:GetStreakTitle(lastStreakCombo)
    if prev and prev.combo == title.combo then return end
    lastStreakCombo = combo

    streakText:SetText(title.text)
    streakText:SetTextColor(title.color[1], title.color[2], title.color[3])
    streakFadeAG:Stop()
    streakText:SetAlpha(0)
    streakFadeAG:Play()
end

function GameUI:ResetStreakTitle()
    lastStreakCombo = 0
    if streakFadeAG then streakFadeAG:Stop() end
    if streakText then streakText:SetAlpha(0) end
end

function GameUI:CreateCountdown()
    countdownFrame = CreateFrame("Frame", nil, UIParent)
    countdownFrame:SetAllPoints()
    countdownFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    countdownFrame:Hide()

    -- Big centered numeral that pops in each tick, like Blizzard's pull/BG countdown.
    countdownPop = CreateFrame("Frame", nil, countdownFrame)
    countdownPop:SetSize(260, 260)
    countdownPop:SetPoint("CENTER", 0, 50)

    countdownText = countdownPop:CreateFontString(nil, "OVERLAY")
    countdownText:SetFont("Fonts\\FRIZQT__.TTF", 110, "THICKOUTLINE")
    countdownText:SetPoint("CENTER")
    countdownText:SetTextColor(1, 0.84, 0)

    countdownPopAG = countdownPop:CreateAnimationGroup()
    local sc = countdownPopAG:CreateAnimation("Scale")
    sc:SetScaleFrom(1.7, 1.7)
    sc:SetScaleTo(1.0, 1.0)
    sc:SetDuration(0.35)
    sc:SetSmoothing("OUT")
    local al = countdownPopAG:CreateAnimation("Alpha")
    al:SetFromAlpha(0.0)
    al:SetToAlpha(1.0)
    al:SetDuration(0.22)
end

-- Public methods called by Game.lua

local DIFFROW_BOTTOM = 125 -- fixed layout: accent+score+dividers+best+diffRow+modifierRow

function GameUI:ResizeScoreFrame()
    if not scoreFrame or not controlBar then return end
    scoreFrame:SetHeight(DIFFROW_BOTTOM + 4 + controlBar:GetHeight() + 6)
end

-- Looping icon-fall demo on the main menu: a continuous stream of icons drops
-- onto a small action bar and auto-hits (with the odd miss), previewing the
-- game. Non-interactive; the OnUpdate runs only while the menu is shown and
-- self-cancels on error. Icons stay inside the demo rect (spawned at the top
-- edge, faded out at the bar) so no clipping is needed.
local DEMO_ICONS = {
    "Interface\\Icons\\Spell_Nature_Lightning",
    "Interface\\Icons\\Spell_Fire_Fireball02",
    "Interface\\Icons\\Ability_Warrior_Charge",
    "Interface\\Icons\\Spell_Holy_FlashHeal",
    "Interface\\Icons\\Ability_Rogue_Eviscerate",
    "Interface\\Icons\\Spell_Frost_FrostBolt02",
}
local DEMO_COLS, DEMO_SLOT, DEMO_GAP, DEMO_H = 5, 30, 8, 150
local DEMO_FALL, DEMO_SPAWN = 95, 0.55
local DEMO_HITY = 2 + DEMO_SLOT
local drandom = math.random

local function DemoColX(c)
    return (c - (DEMO_COLS + 1) / 2) * (DEMO_SLOT + DEMO_GAP)
end

local function AcquireDemoIcon(demo)
    local icon = tremove(demo.pool)
    if not icon then
        icon = demo:CreateTexture(nil, "ARTWORK")
        icon:SetSize(DEMO_SLOT - 2, DEMO_SLOT - 2)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    end
    icon:SetTexture(DEMO_ICONS[drandom(#DEMO_ICONS)])
    icon:SetVertexColor(1, 1, 1)
    icon:SetAlpha(1)
    icon:Show()
    return icon
end

local function DemoStep(demo, elapsed)
    demo.spawnT = (demo.spawnT or 0) + elapsed
    if demo.spawnT >= DEMO_SPAWN then
        demo.spawnT = demo.spawnT - DEMO_SPAWN
        local icon = AcquireDemoIcon(demo)
        icon.col = drandom(DEMO_COLS)
        icon.y = DEMO_H - DEMO_SLOT
        icon.hit = false
        icon.miss = (drandom(6) == 1)
        icon:ClearAllPoints()
        icon:SetPoint("BOTTOM", demo, "BOTTOM", DemoColX(icon.col), icon.y)
        demo.active[#demo.active + 1] = icon
    end

    for i = 1, DEMO_COLS do
        local flash = demo.slots[i].flash
        local a = flash:GetAlpha()
        if a > 0 then flash:SetAlpha(mmax(0, a - elapsed * 3)) end
    end

    local active = demo.active
    for i = #active, 1, -1 do
        local icon = active[i]
        if icon.hit then
            local a = icon:GetAlpha() - elapsed * 5
            if a <= 0 then
                icon:Hide()
                tremove(active, i)
                demo.pool[#demo.pool + 1] = icon
            else
                icon:SetAlpha(a)
            end
        else
            icon.y = icon.y - DEMO_FALL * elapsed
            icon:SetPoint("BOTTOM", demo, "BOTTOM", DemoColX(icon.col), icon.y)
            if icon.y <= DEMO_HITY then
                icon.hit = true
                if icon.miss then
                    icon:SetVertexColor(1, 0.5, 0.5)
                else
                    demo.slots[icon.col].flash:SetAlpha(0.75)
                end
            end
        end
    end
end

-- The Icon Game main menu: a landing screen (built on the same window setup as
-- the song-select carousel, Midnight backdrop by default) with a looping demo
-- and a visible-only action-bar picker. Start opens the song-select carousel.
function GameUI:CreateMainMenu()
    if mainMenu then return end

    local f = CreateFrame("Frame", "BoundToLearnIconGameMenu", UIParent)
    f:SetSize(568, 432)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata("FULLSCREEN")
    f:SetFrameLevel(70)
    Theme.StylePanel(f, 0.96)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetClampedToScreen(true)
    tinsert(UISpecialFrames, "BoundToLearnIconGameMenu")
    f:Hide()

    local xbg = f:CreateTexture(nil, "ARTWORK")
    xbg:SetPoint("TOPLEFT", 7, -7)
    xbg:SetPoint("BOTTOMRIGHT", -7, 7)
    xbg:SetAlpha(0.85)
    xbg:SetAtlas("ui-ej-midnight")
    f.xpacBg = xbg

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
    title:SetPoint("TOP", 0, -20)
    title:SetText("Icon Game")
    title:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))

    local subtitle = f:CreateFontString(nil, "OVERLAY")
    subtitle:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetTextColor(0.82, 0.82, 0.82)
    subtitle:SetText("Practice hitting your keybinds to falling icons.")

    local closeBtn = Theme.CreateCloseButton(f, function() f:Hide() end)
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- Start enters the song-selection carousel, where the track and difficulty
    -- are chosen and the round begins.
    local startBtn = Theme.CreateAccentButton(f, "Start", 200, 42)
    startBtn:SetPoint("BOTTOM", 0, 24)
    startBtn._label:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    startBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        f:Hide()
        GameUI:ShowSongSelect()
    end)
    f.startBtn = startBtn

    self:BuildMainMenuDemo(f)
    self:BuildMainMenuBars(f)

    mainMenu = f
end

function GameUI:ShowMainMenu()
    if not mainMenu then self:CreateMainMenu() end
    self:HideSongSelect()
    if scoreFrame then scoreFrame:Hide() end
    if self.healthFrame then self.healthFrame:Hide() end
    self:RefreshMainMenuBars()
    mainMenu:Show()
end

function GameUI:HideMainMenu()
    if mainMenu then mainMenu:Hide() end
end

-- Action-bar picker: which bars the game pulls spells from. Mirrors the Keybind
-- Audit -- only bars currently visible in the UI can be toggled.
function GameUI:BuildMainMenuBars(f)
    local BARS = ns.KeybindAudit and ns.KeybindAudit.BAR_MAPPINGS or {}

    local header = f:CreateFontString(nil, "OVERLAY")
    header:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    header:SetPoint("TOP", 0, -222)
    header:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))
    header:SetText("Action bars in play")

    local hint = f:CreateFontString(nil, "OVERLAY")
    hint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    hint:SetPoint("TOP", header, "BOTTOM", 0, -2)
    hint:SetTextColor(0.72, 0.72, 0.72)
    hint:SetText("Only bars shown in your UI can be picked.")

    f.barToggles = {}
    local COLS, CELL_W, CELL_H = 2, 156, 22
    for i = 1, #BARS do
        local bar = BARS[i]
        local col = (i - 1) % COLS
        local row = mfloor((i - 1) / COLS)
        local cb = Theme.CreateToggle(f, bar.label, nil, CELL_W - 10)
        cb:SetPoint("TOP", f, "TOP", (col - 0.5) * CELL_W, -256 - row * CELL_H)
        cb.barKey = bar.key
        cb.buttonPrefix = bar.buttonPrefix
        cb:SetScript("OnClick", function(self)
            BoundToLearn.db.game.bars[self.barKey] = self:GetChecked()
        end)
        cb:SetMotionScriptsWhileDisabled(true)
        cb:HookScript("OnEnter", function(self)
            if self:IsEnabled() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(bar.label)
            GameTooltip:AddLine("Hidden in your UI, so it can't be used.", 1, 0.82, 0, true)
            GameTooltip:Show()
        end)
        cb:HookScript("OnLeave", function() GameTooltip:Hide() end)
        f.barToggles[i] = cb
    end
end

function GameUI:RefreshMainMenuBars()
    if not mainMenu or not mainMenu.barToggles then return end
    local bars = BoundToLearn.db.game.bars
    for i = 1, #mainMenu.barToggles do
        local cb = mainMenu.barToggles[i]
        local btn1 = _G[cb.buttonPrefix .. "1"]
        local visible = btn1 and btn1:IsVisible() and true or false
        cb:SetEnabled(visible)
        cb:SetChecked(visible and bars[cb.barKey] and true or false)
    end
end

function GameUI:BuildMainMenuDemo(f)
    local demoW = DEMO_COLS * DEMO_SLOT + (DEMO_COLS - 1) * DEMO_GAP
    local demo = CreateFrame("Frame", nil, f)
    demo:SetSize(demoW, DEMO_H)
    demo:SetPoint("TOP", 0, -62)
    demo.pool = {}
    demo.active = {}
    demo.spawnT = 0

    demo.slots = {}
    for c = 1, DEMO_COLS do
        local base = demo:CreateTexture(nil, "BACKGROUND")
        base:SetSize(DEMO_SLOT, DEMO_SLOT)
        base:SetPoint("BOTTOM", demo, "BOTTOM", DemoColX(c), 2)
        base:SetColorTexture(0.10, 0.10, 0.13, 0.85)
        local flash = demo:CreateTexture(nil, "OVERLAY")
        flash:SetSize(DEMO_SLOT, DEMO_SLOT)
        flash:SetPoint("BOTTOM", demo, "BOTTOM", DemoColX(c), 2)
        flash:SetColorTexture(Theme.RGB(Theme.C.ACCENT))
        flash:SetAlpha(0)
        demo.slots[c] = { flash = flash }
    end

    demo:SetScript("OnUpdate", function(self, elapsed)
        if not pcall(DemoStep, self, elapsed) then
            self:SetScript("OnUpdate", nil)
        end
    end)

    f.demo = demo
end

function GameUI:ShowReadyState()
    -- The main menu is the ready-state entry; its Start opens the song-select
    -- carousel. The compact score HUD and life gauge only appear once a round
    -- starts (OnGameStart).
    if scoreFrame then scoreFrame:Hide() end
    if self.healthFrame then self.healthFrame:Hide() end
    if modifierDropdown then modifierDropdown:Hide() end
    self:UpdateDifficultyButtons()
    self:ShowMainMenu()
end

function GameUI:OnGameStart(slots)
    self.songCompare = nil   -- fresh each round; only a scored run repopulates it
    self.noteHighwayTop = nil   -- recomputed by PrepChart once buttons lay out
    self:ResetStreakTitle()
    self:HideSongSelect()
    self:CreateHealthBar()
    if self.healthFrame then self.healthFrame:Show() end
    self:UpdateLifeBar(1)
    if self.healthFrame and self.healthFrame.diffFS then
        local diff = BoundToLearn.db.game.difficulty
        local c = DIFF_COLORS[diff] or { 0.8, 0.8, 0.8 }
        self.healthFrame.diffFS:SetText((diff or ""):upper())
        self.healthFrame.diffFS:SetTextColor(c[1], c[2], c[3])
    end
    if scoreText then scoreText:SetText("0") end
    if comboText then comboText:SetText("") end
    if multiplierText then multiplierText:SetText("") end
    if self.summaryFrame and self.summaryFrame:IsShown() then
        self.summaryFrame:Hide()
    end
    if gameOverlay then gameOverlay:Show() end
    -- The old score panel does not appear during a round; the slim health bar is
    -- the entire in-round HUD.
    if scoreFrame then scoreFrame:Hide() end
    if pauseOverlay then pauseOverlay:Hide() end
    if self.healthFrame then
        local hf = self.healthFrame
        hf.pauseBtn:SetText("Pause")
        -- Pause is Practice-only; hide it entirely in scored modes (combat ends
        -- a scored run rather than pausing it) and close the timer gap.
        local practice = ns.Game ~= nil and ns.Game:GetMode() == "practice"
        hf.pauseBtn:SetShown(practice)
        hf.timerFS:ClearAllPoints()
        hf.timerFS:SetPoint("RIGHT", practice and hf.pauseBtn or hf.stopBtn, "LEFT", -12, 0)
    end
    if modifierDropdown then modifierDropdown:Hide() end

    -- Set initial timer
    local remaining = ns.Game and ns.Game:GetTimeRemaining()
    self:UpdateTimer(remaining)

    self:CreateHitZones(slots)
    self:UpdateScoreDisplay(0, 0, 1)

    if dangerOverlay then
        dangerOverlay:Hide()
        dangerOverlay:SetAlpha(1)
        if dangerPulseAG and dangerPulseAG:IsPlaying() then dangerPulseAG:Stop() end
    end
end

function GameUI:OnGameEnd(results)
    for _, hz in ipairs(hitZonePool) do
        hz:Hide()
    end
    self:ReleaseAllNotes()

    if pauseOverlay then pauseOverlay:Hide() end
    if dangerOverlay then dangerOverlay:Hide() end
    if dangerPulseAG and dangerPulseAG:IsPlaying() then dangerPulseAG:Stop() end
    if gameOverlay then gameOverlay:Hide() end
    if self.healthFrame then self.healthFrame:Hide() end
    if scoreFrame then scoreFrame:Hide() end

    -- Round-over reuses the select screen: results on the song's own backdrop
    -- with the track playing, instead of a separate popup.
    self:ShowResultsOnSelect(results)
end

function GameUI:OnGamePause()
    if pauseOverlay then pauseOverlay:Show() end
    if controlBar then controlBar.pauseBtn:SetText("Resume") end
    if self.healthFrame then self.healthFrame.pauseBtn:SetText("Resume") end
end

function GameUI:OnGameResume()
    if pauseOverlay then pauseOverlay:Hide() end
    if controlBar then controlBar.pauseBtn:SetText("Pause") end
    if self.healthFrame then self.healthFrame.pauseBtn:SetText("Pause") end
end

function GameUI:CreateHitZones(slots)
    for _, hz in ipairs(hitZonePool) do
        hz:Hide()
    end
    wipe(hitZonePool)

    for _, slotInfo in ipairs(slots) do
        local btn = slotInfo.button
        if btn then
            local hzSize = (slotInfo.competitive and COMP_BTN_SIZE or NOTE_SIZE) + 8
            local glow = CreateFrame("Frame", nil, gameOverlay)
            glow:SetSize(hzSize, hzSize)
            glow:SetFrameStrata("FULLSCREEN")
            glow:SetFrameLevel(55)
            glow:SetPoint("CENTER", btn, "CENTER")

            local tex = glow:CreateTexture(nil, "ARTWORK")
            tex:SetAllPoints()
            tex:SetColorTexture(Theme.RGB(Theme.C.ACCENT, 0.14))
            glow.tex = tex

            local ag = glow:CreateAnimationGroup()
            ag:SetLooping("BOUNCE")
            local alpha = ag:CreateAnimation("Alpha")
            alpha:SetFromAlpha(0.05)
            alpha:SetToAlpha(0.2)
            alpha:SetDuration(0.8)
            ag:Play()

            glow:Show()
            tinsert(hitZonePool, glow)
        end
    end
end

function GameUI:FormatKeybind(keybind)
    local text = keybind
    text = text:gsub("SHIFT%-", "s-")
    text = text:gsub("CTRL%-", "c-")
    text = text:gsub("ALT%-", "a-")
    return text
end

function GameUI:AcquireNote(note)
    for _, f in ipairs(notePool) do
        if not f.inUse then
            f.inUse = true
            f.isBomb = note.isBomb

            -- Match comp bar button size in competitive mode
            local size = note.slotInfo.competitive and COMP_BTN_SIZE or NOTE_SIZE
            f:SetSize(size, size)

            if note.isBomb then
                f.icon:SetTexture("Interface\\Icons\\inv_wildfirebomb")
                f.border:SetVertexColor(1, 0.15, 0.1, 1)
                f.bombIcon:Show()
                f.fuse:Show()
                f.blinkAG:Play()
                f.fuseAG:Play()
                if note.slotInfo.competitive then
                    self:SetLaneBombTarget(note.slotInfo.laneIndex, true)
                end
            else
                f.icon:SetTexture(note.displayTexture or note.slotInfo.texture)
                f.border:SetVertexColor(1, 1, 1, 0.8)
                f.bombIcon:Hide()
                f.fuse:Hide()
                f.blinkAG:Stop()
                f.fuseAG:Stop()
                f:SetAlpha(1)
            end

            f.label:SetText(GameUI:FormatKeybind(note.slotInfo.keybind))
            f:Show()
            note.noteFrame = f
            return
        end
    end
end

function GameUI:ReleaseNote(note)
    local f = note.noteFrame
    if f then
        f.blinkAG:Stop()
        f.fuseAG:Stop()
        f:SetAlpha(1)
        f:SetSize(NOTE_SIZE, NOTE_SIZE)
        f.bombIcon:Hide()
        f.fuse:Hide()
        f:Hide()
        f.inUse = false
        note.noteFrame = nil
    end
    if note.isBomb and note.slotInfo.competitive then
        self:SetLaneBombTarget(note.slotInfo.laneIndex, false)
    end
end

function GameUI:ReleaseAllNotes()
    for _, f in ipairs(notePool) do
        if f.inUse then
            f:Hide()
            f.inUse = false
        end
    end
    for _, f in ipairs(resultPool) do
        if f.inUse then
            f:Hide()
            f.inUse = false
        end
    end
end

function GameUI:UpdateNotePosition(note, progress)
    local f = note.noteFrame
    if not f then return end

    local btn = note.slotInfo.button
    if not btn or not btn:IsShown() then return end

    local bx, by = btn:GetCenter()
    if not bx then return end
    local bScale = btn:GetEffectiveScale()
    local fScale = f:GetEffectiveScale()

    local xTarget = (bx * bScale) / fScale
    local yTarget = (by * bScale) / fScale
    -- Fall from the one shared start line (set by PrepChart) down to this note's
    -- button. The per-note fall time keeps the speed constant, so a lower bar just
    -- takes longer. Falls back to a fixed drop until the line is known.
    local nHT = self.noteHighwayTop
    local fallDist = nHT and mmax(20, nHT / fScale - yTarget) or (BoundToLearn.db.game.fallDistance / fScale)

    local mods = note.modifiers or {}

    -- Accelerate: remap progress so notes speed up as they fall
    local effectiveProgress = progress
    if mods.accelerate then
        effectiveProgress = progress * progress  -- quadratic ease-in
    end

    -- Every note starts on the same line (vertical distance is always fallDist).
    -- Angled notes slide in from a horizontal offset instead of starting at a
    -- different height, so the start line stays uniform no matter the angle.
    local remaining = 1.0 - effectiveProgress
    local y = yTarget + fallDist * remaining
    local x = xTarget
    if note.spawnAngle then
        x = xTarget + (fallDist / math.tan(note.spawnAngle)) * remaining
    end

    -- Squiggly: sinusoidal horizontal oscillation
    if mods.squiggly and note.squigglyPhase then
        local amplitude = 40 / fScale
        local freq = 4
        x = x + math.sin(effectiveProgress * freq * math.pi + note.squigglyPhase) * amplitude * (1.0 - effectiveProgress)
    end

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

    -- Fade: notes become transparent as they approach
    if mods.fade then
        local alpha = mmax(0.08, 1.0 - effectiveProgress * 0.95)
        f:SetAlpha(alpha)
    else
        f:SetAlpha(1)
    end

    if not f.isBomb then
        local proximity = mmax(0, 1.0 - mabs(1.0 - effectiveProgress) * 3)
        local r = 1.0 - proximity * 0.8
        local g = 1.0
        local b = 1.0 - proximity * 0.8
        f.border:SetVertexColor(r, g, b, 0.6 + proximity * 0.4)
    end
end

function GameUI:FlashNote(note, result)
    local nf = note.noteFrame
    if not nf then return end

    local color = RESULT_COLORS[result]
    if color and result ~= "miss" then
        nf.border:SetVertexColor(color[1], color[2], color[3], 1)
        nf.icon:SetAlpha(1)
    end

    -- Quick scale pop
    if not nf.hitAG then
        nf.hitAG = nf:CreateAnimationGroup()
        local up = nf.hitAG:CreateAnimation("Scale")
        up:SetScaleFrom(1, 1)
        up:SetScaleTo(1.3, 1.3)
        up:SetDuration(0.08)
        up:SetSmoothing("OUT")
        up:SetOrder(1)
        local down = nf.hitAG:CreateAnimation("Scale")
        down:SetScaleFrom(1.3, 1.3)
        down:SetScaleTo(1, 1)
        down:SetDuration(0.12)
        down:SetSmoothing("IN")
        down:SetOrder(2)
    end
    nf.hitAG:Stop()
    nf.hitAG:Play()
end

function GameUI:FireProjectile(fromBtn, toFrame, note)
    if not fromBtn or not toFrame then return end
    local bx, by = fromBtn:GetCenter()
    local tx, ty = toFrame:GetCenter()
    if not bx or not tx then return end

    local f
    for i = 1, #projectilePool do
        if not projectilePool[i].inUse then
            f = projectilePool[i]
            break
        end
    end
    if not f then
        f = CreateFrame("Frame", nil, gameOverlay)
        f:SetSize(24, 24)
        f:SetFrameStrata("FULLSCREEN")
        f:SetFrameLevel(70)
        local tex = f:CreateTexture(nil, "ARTWORK")
        tex:SetAllPoints()
        tex:SetTexture("Interface\\Icons\\Spell_Fire_FlameBolt")
        tex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        tex:SetBlendMode("ADD")
        f.tex = tex
        local glow = f:CreateTexture(nil, "BACKGROUND")
        glow:SetSize(36, 36)
        glow:SetPoint("CENTER")
        glow:SetAtlas("Spark")
        glow:SetBlendMode("ADD")
        glow:SetVertexColor(1, 0.5, 0.1, 0.6)
        f.glow = glow
        tinsert(projectilePool, f)
    end

    f.inUse = true
    f.elapsed = 0
    f.duration = 0.25
    f.targetNote = note
    local fScale = f:GetEffectiveScale()
    local bScale = fromBtn:GetEffectiveScale()
    local tScale = toFrame:GetEffectiveScale()
    f.sx = (bx * bScale) / fScale
    f.sy = (by * bScale) / fScale
    f.tx = (tx * tScale) / fScale
    f.ty = (ty * tScale) / fScale

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", f.sx, f.sy)
    f:SetAlpha(1)
    f:Show()

    f:SetScript("OnUpdate", function(self, dt)
        self.elapsed = self.elapsed + dt
        local p = self.elapsed / self.duration
        if p >= 1 then
            self:Hide()
            self:SetScript("OnUpdate", nil)
            self.inUse = false
            if self.targetNote then
                PlaySound(44191)  -- bomb explosion on impact
                GameUI:ReleaseNote(self.targetNote)
                self.targetNote = nil
            end
            return
        end
        local x = self.sx + (self.tx - self.sx) * p
        local y = self.sy + (self.ty - self.sy) * p
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)
        self:SetAlpha(1 - p * 0.3)
    end)
end

function GameUI:ShowHitResult(note, result, points)
    -- Fire projectile from cannon to bomb
    if note.isBomb and result ~= "miss" and note.slotInfo.competitive and note.noteFrame then
        local btn = compBarButtons[note.slotInfo.laneIndex]
        self:FireProjectile(btn, note.noteFrame, note)
    end
    self:FlashNote(note, result)

    local f = self:AcquireResultText()
    if not f then return end

    local color = RESULT_COLORS[result] or RESULT_COLORS.miss
    local label = RESULT_LABELS[result] or "MISS"
    f:SetTextColor(color[1], color[2], color[3])
    if points < 0 then
        f:SetText(sformat("%d %s", points, label))
    else
        f:SetText(sformat("+%d %s", points, label))
    end

    -- Position at the note's current location, not the action bar button
    local noteFrame = note.noteFrame
    if noteFrame and noteFrame:IsShown() then
        local nx, ny = noteFrame:GetCenter()
        if nx then
            local scale = noteFrame:GetEffectiveScale() / f:GetEffectiveScale()
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", nx * scale, ny * scale + 20)
        end
    else
        local btn = note.slotInfo.button
        if btn then
            local bx, by = btn:GetCenter()
            if bx then
                local scale = btn:GetEffectiveScale() / f:GetEffectiveScale()
                f:ClearAllPoints()
                f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bx * scale, by * scale + 30)
            end
        end
    end
    f:Show()

    if f.animGroup then
        f.animGroup:Stop()
        f.animGroup:Play()
    end

    C_Timer.After(0.8, function()
        f:Hide()
        f.inUse = false
    end)
end

function GameUI:AcquireResultText()
    for _, f in ipairs(resultPool) do
        if not f.inUse then
            f.inUse = true
            return f
        end
    end
    return nil
end

function GameUI:ShowBonusText(bonus)
    local f = self:AcquireResultText()
    if not f then return end

    f:SetTextColor(1, 0.84, 0)
    f:SetText(sformat("BONUS +%d", bonus))
    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
    f:Show()

    if f.animGroup then
        f.animGroup:Stop()
        f.animGroup:Play()
    end

    C_Timer.After(1.0, function()
        f:Hide()
        f.inUse = false
    end)
end

function GameUI:UpdateScoreDisplay(currentScore, currentCombo, currentMultiplier)
    local hf = self.healthFrame
    local scoreStr = sformat("%d", currentScore)
    if scoreText then scoreText:SetText(scoreStr) end
    if hf then hf.scoreFS:SetText(scoreStr) end

    local comboStr, cr, cg, cb = "", 0.7, 0.7, 0.7
    if currentCombo > 0 and BoundToLearn.db.game.showCombo then
        comboStr = sformat("%d Combo", currentCombo)
        if currentCombo >= 30 then
            cr, cg, cb = 1, 0.3, 0.3
        elseif currentCombo >= 15 then
            cr, cg, cb = 1, 0.6, 0.2
        elseif currentCombo >= 5 then
            cr, cg, cb = 1, 0.85, 0.3
        end
    end
    if comboText then
        comboText:SetText(comboStr)
        comboText:SetTextColor(cr, cg, cb)
    end
    if hf then
        hf.comboFS:SetText(comboStr)
        hf.comboFS:SetTextColor(cr, cg, cb)
    end
    if multiplierText then
        if currentMultiplier > 1 then
            multiplierText:SetText(sformat("|cFFAAAAAAmult|r %dx", currentMultiplier))
        else
            multiplierText:SetText("")
        end
        if currentMultiplier >= 4 then
            multiplierText:SetTextColor(1, 0.3, 0.3)
        elseif currentMultiplier >= 3 then
            multiplierText:SetTextColor(1, 0.6, 0.2)
        elseif currentMultiplier >= 2 then
            multiplierText:SetTextColor(1, 0.85, 0.3)
        else
            multiplierText:SetTextColor(0.7, 0.7, 0.7)
        end
    end

    if currentCombo > 0 then
        self:ShowStreakTitle(currentCombo)
    end
end

local countdownCancelFlag = false

-- Drive Blizzard's TimerTracker so the countdown shows the big fiery numerals from the
-- default UI (BG/arena starts, /pull). There's no public API to trigger it solo, so we
-- call the event handler directly, guarded: if anything is missing on this client the
-- pcall fails and ShowCountdown falls back to the in-house numeral.
function GameUI:TryNativeCountdown(seconds)
    local tt = _G.TimerTracker
    local st = Enum and Enum.StartTimerType
    local timerType = st and (st.PlayerCountdown or st.PvPBeginTimer)
    if not tt or not timerType then return false end
    return pcall(function()
        if tt.timerList then
            for _, timer in pairs(tt.timerList) do
                if FreeTimerTrackerTimer then
                    FreeTimerTrackerTimer(timer)
                elseif timer.bar then
                    timer.bar:Hide()
                end
            end
        end
        if TimerTracker_OnEvent then
            TimerTracker_OnEvent(tt, "START_TIMER", timerType, seconds, seconds)
        else
            tt:OnEvent("START_TIMER", timerType, seconds, seconds)
        end
    end)
end

function GameUI:ShowCountdown(seconds, onComplete)
    countdownCancelFlag = false

    -- Native fiery countdown first; the custom numeral is the fallback.
    if self:TryNativeCountdown(seconds) then
        usingNativeCountdown = true
        if onComplete then
            C_Timer.After(seconds, function()
                if not countdownCancelFlag then onComplete() end
            end)
        end
        return
    end
    usingNativeCountdown = false

    countdownFrame:Show()
    local remaining = seconds
    local function Tick()
        if countdownCancelFlag then return end
        if remaining > 0 then
            countdownText:SetText(tostring(remaining))
            countdownText:SetTextColor(1, 0.84, 0)
            if countdownPopAG then countdownPopAG:Stop() countdownPopAG:Play() end
            -- SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_TIMER is nil on some clients, which
            -- silently plays nothing; 3332 (raid-warning ding) is a confirmed fallback.
            PlaySound(SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_TIMER or 3332)
            remaining = remaining - 1
            C_Timer.After(1, Tick)
        else
            countdownText:SetText("GO!")
            countdownText:SetTextColor(0.2, 1.0, 0.2)
            if countdownPopAG then countdownPopAG:Stop() countdownPopAG:Play() end
            PlaySound(SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED or 8960)
            if onComplete then onComplete() end
            C_Timer.After(0.5, function()
                if not countdownCancelFlag then
                    countdownFrame:Hide()
                end
            end)
        end
    end
    Tick()
end

function GameUI:CancelCountdown()
    countdownCancelFlag = true
    if usingNativeCountdown then
        usingNativeCountdown = false
        local tt = _G.TimerTracker
        if tt and tt.timerList then
            pcall(function()
                for _, timer in pairs(tt.timerList) do
                    if FreeTimerTrackerTimer then
                        FreeTimerTrackerTimer(timer)
                    elseif timer.bar then
                        timer.bar:Hide()
                    end
                end
            end)
        end
    end
    if countdownFrame then countdownFrame:Hide() end
end

function GameUI:ShowSummary(results)
    if not self.summaryFrame then
        self:CreateSummaryFrame()
    end

    self.lastResults = results
    local sf = self.summaryFrame
    local totalNotes = results.totalNotes
    local accuracy = ns.Utils.HitAccuracy(results.hitCounts)

    if sf.title then
        if results.focusFailed then
            sf.title:SetText("|cFFFF6666Round Over|r")
        else
            sf.title:SetText("|cFFFF8A33Round Complete|r")
        end
    end

    sf.scoreValue:SetText(sformat("%d", results.score))
    sf.comboValue:SetText(sformat("%d", results.maxCombo))
    sf.accuracyValue:SetText(sformat("%.1f%%", accuracy))

    sf.perfectValue:SetText(sformat("%d", results.hitCounts.perfect or 0))
    sf.greatValue:SetText(sformat("%d", results.hitCounts.great or 0))
    sf.goodValue:SetText(sformat("%d", results.hitCounts.good or 0))
    sf.missValue:SetText(sformat("%d", results.hitCounts.miss or 0))

    local fakeCount = results.hitCounts.redHerring or 0
    sf.fakeValue:SetText(sformat("%d", fakeCount))
    sf.fakeLabel:SetShown(fakeCount > 0)
    sf.fakeValue:SetShown(fakeCount > 0)

    sf.durationValue:SetText(sformat("%d:%02d", mfloor(results.duration / 60), mfloor(results.duration % 60)))

    -- Check per-difficulty bests (fall back to global if no difficulty data)
    local diff = results.difficulty
    local db = BoundToLearn.db.stats.difficultyBest
    local diffBest = db and diff and db[diff]
    local bestScore = diffBest and diffBest.highestScore or 0
    local bestCombo = diffBest and diffBest.longestCombo or 0

    local isNewHighScore = results.score > 0 and results.score >= bestScore
    local isNewBestCombo = results.maxCombo > 0 and results.maxCombo >= bestCombo

    if isNewHighScore then
        sf.scoreLabel:SetText("Score |cFF00FF00(NEW BEST)|r")
    else
        sf.scoreLabel:SetText("Score")
    end
    if isNewBestCombo then
        sf.comboLabel:SetText("Best Combo |cFF00FF00(NEW BEST)|r")
    else
        sf.comboLabel:SetText("Best Combo")
    end

    sf:ClearAllPoints()
    if scoreFrame and scoreFrame:IsShown() then
        sf:SetPoint("TOP", scoreFrame, "BOTTOM", 0, -40)
    else
        sf:SetPoint("CENTER")
    end
    sf:Show()

    -- Level-up animation for new high scores (timed and competitive only)
    local showLevelUp = (isNewHighScore or isNewBestCombo)
        and results.mode ~= "practice"
        and totalNotes >= 5
    if showLevelUp then
        self:PlayLevelUpEffect(sf)
    else
        self:HideLevelUpEffect()
    end
end

function GameUI:PlayLevelUpEffect(parent)
    if not self.levelUpFrame then
        local luf = CreateFrame("Frame", nil, UIParent)
        luf:SetFrameStrata("FULLSCREEN_DIALOG")
        luf:SetFrameLevel(parent:GetFrameLevel() - 1)
        luf:SetAllPoints(parent)

        -- Golden glow behind the frame
        local glow = luf:CreateTexture(nil, "BACKGROUND")
        glow:SetPoint("CENTER")
        glow:SetSize(500, 500)
        glow:SetTexture("Interface\\LevelUp\\LevelUpTex")
        glow:SetTexCoord(0.00195313, 0.63867188, 0.03710938, 0.23828125)
        glow:SetBlendMode("ADD")
        glow:SetAlpha(0)
        luf.glow = glow

        -- Starburst rays
        local rays = luf:CreateTexture(nil, "ARTWORK")
        rays:SetPoint("CENTER")
        rays:SetSize(480, 480)
        rays:SetTexture("Interface\\LevelUp\\LevelUpTex")
        rays:SetTexCoord(0.00195313, 0.63867188, 0.26562500, 0.51171875)
        rays:SetBlendMode("ADD")
        rays:SetAlpha(0)
        luf.rays = rays

        -- "NEW RECORD" text
        local banner = luf:CreateFontString(nil, "OVERLAY")
        banner:SetFont("Fonts\\MORPHEUS.TTF", 28, "OUTLINE")
        banner:SetPoint("TOP", parent, "TOP", 0, 32)
        banner:SetTextColor(1, 0.82, 0)
        banner:SetText("NEW RECORD")
        banner:SetAlpha(0)
        luf.banner = banner

        luf.animGroup = luf:CreateAnimationGroup()
        luf:Hide()
        self.levelUpFrame = luf
    end

    local luf = self.levelUpFrame
    luf:SetParent(UIParent)
    luf:ClearAllPoints()
    luf:SetPoint("CENTER", parent, "CENTER")
    luf:SetSize(parent:GetWidth(), parent:GetHeight())
    luf:SetFrameLevel(parent:GetFrameLevel() - 1)
    luf.banner:ClearAllPoints()
    luf.banner:SetPoint("TOP", parent, "TOP", 0, 32)
    luf:Show()

    -- Animate: fade in glow + rays, rotate rays, then fade out
    local elapsed = 0
    local duration = 3.0
    luf:SetScript("OnUpdate", function(self, dt)
        elapsed = elapsed + dt
        local t = elapsed / duration

        if t < 0.15 then
            -- Fade in
            local a = t / 0.15
            luf.glow:SetAlpha(a * 0.7)
            luf.rays:SetAlpha(a * 0.5)
            luf.banner:SetAlpha(a)
        elseif t < 0.7 then
            luf.glow:SetAlpha(0.7)
            luf.rays:SetAlpha(0.5)
            luf.banner:SetAlpha(1)
        elseif t < 1.0 then
            -- Fade out
            local a = (1.0 - t) / 0.3
            luf.glow:SetAlpha(a * 0.7)
            luf.rays:SetAlpha(a * 0.5)
            luf.banner:SetAlpha(a)
        else
            luf.glow:SetAlpha(0)
            luf.rays:SetAlpha(0)
            luf.banner:SetAlpha(0)
            luf:SetScript("OnUpdate", nil)
            luf:Hide()
        end

        -- Rotate rays
        local angle = elapsed * 0.4
        local cos, sin = math.cos(angle), math.sin(angle)
        local w, h = luf.rays:GetSize()
        luf.rays:SetRotation(angle)
    end)

    -- Play the actual level-up sound
    PlaySound(888)  -- LevelUp fanfare (used only here, not per-hit)
end

function GameUI:HideLevelUpEffect()
    if self.levelUpFrame then
        self.levelUpFrame:SetScript("OnUpdate", nil)
        self.levelUpFrame:Hide()
    end
end

function GameUI:CreateSummaryFrame()
    local sf = CreateFrame("Frame", "BoundToLearnSummary", UIParent)
    sf:SetSize(280, 310)
    sf:SetFrameStrata("FULLSCREEN_DIALOG")
    Theme.StyleCard(sf, {0.09, 0.08, 0.04}, 12)
    Theme.SetBorderShown(sf, false)
    sf:EnableMouse(true)

    local title = sf:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFFFF8A33Round Complete|r")
    sf.title = title

    local y = -34
    local function AddRow(label, valueColor)
        local lbl = sf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 15, y)
        lbl:SetText(label)
        lbl:SetJustifyH("LEFT")

        local val = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        val:SetPoint("TOPRIGHT", -15, y)
        val:SetJustifyH("RIGHT")
        if valueColor then
            val:SetTextColor(valueColor[1], valueColor[2], valueColor[3])
        end

        y = y - 22
        return lbl, val
    end

    sf.scoreLabel, sf.scoreValue = AddRow("Score", {1, 0.84, 0})
    sf.comboLabel, sf.comboValue = AddRow("Best Combo", {1, 1, 1})
    sf.accuracyLabel, sf.accuracyValue = AddRow("Accuracy", {0.2, 1, 0.2})
    y = y - 4

    local divider = sf:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("LEFT", 12, 0)
    divider:SetPoint("RIGHT", -12, 0)
    divider:SetPoint("TOP", 0, y)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    y = y - 10

    sf.perfectLabel, sf.perfectValue = AddRow("Perfect", RESULT_COLORS.perfect)
    sf.greatLabel, sf.greatValue = AddRow("Great", RESULT_COLORS.great)
    sf.goodLabel, sf.goodValue = AddRow("Good", RESULT_COLORS.good)
    sf.missLabel, sf.missValue = AddRow("Miss", RESULT_COLORS.miss)
    sf.fakeLabel, sf.fakeValue = AddRow("Fakes Hit", RESULT_COLORS.redHerring)
    sf.durationLabel, sf.durationValue = AddRow("Duration", {0.7, 0.7, 0.7})

    -- Share button
    local shareBtn = Theme.CreateButton(sf, "Share", 100, 22)
    shareBtn:SetPoint("BOTTOM", 0, 10)
    shareBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleShareMenu(sf)
    end)
    y = y - 30

    local close = Theme.CreateCloseButton(sf, function() sf:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)

    sf:SetScript("OnHide", function()
        GameUI:HideLevelUpEffect()
        if GameUI.shareMenu then GameUI.shareMenu:Hide() end
    end)

    sf:Hide()
    self.summaryFrame = sf
end

function GameUI:FormatShareMessage(results)
    local accuracy = ns.Utils.HitAccuracy(results.hitCounts)
    local diff = results.difficulty or "?"
    local mode = results.mode or "timed"
    local modeLabel = mode == "practice" and "Practice" or mode == "competitive" and "Competitive" or "Timed"
    return sformat(
        "[BoundToLearn] %s %s - Score %d, Accuracy %.1f, Combo %d (P:%d G:%d OK:%d M:%d)",
        modeLabel, diff, results.score, accuracy, results.maxCombo,
        results.hitCounts.perfect or 0, results.hitCounts.great or 0,
        results.hitCounts.good or 0, results.hitCounts.miss or 0
    )
end

function GameUI:ToggleShareMenu(parent)
    if self.shareMenu and self.shareMenu:IsShown() then
        self.shareMenu:Hide()
        return
    end

    if not self.shareMenu then
        local menu = CreateFrame("Frame", nil, UIParent)
        menu:SetSize(100, 118)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        Theme.StylePanel(menu, 0.97)
        menu:Hide()

        local channels = {
            { label = "Say",     chat = "SAY" },
            { label = "Party",   chat = "PARTY" },
            { label = "Raid",    chat = "RAID" },
            { label = "Guild",   chat = "GUILD" },
        }

        for i, ch in ipairs(channels) do
            local btn = CreateFrame("Button", nil, menu)
            btn:SetSize(90, 22)
            btn:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 24)
            btn:SetNormalFontObject("GameFontHighlightSmall")
            btn:SetHighlightFontObject("GameFontNormalSmall")
            btn:SetText(ch.label)
            btn:SetScript("OnClick", function()
                PlayUISound(SOUND_CLICK)
                if self.lastResults then
                    local msg = self:FormatShareMessage(self.lastResults)
                    SendChatMessage(msg, ch.chat)
                end
                menu:Hide()
            end)
        end

        menu:SetScript("OnShow", function(self)
            self:SetScript("OnUpdate", function(self)
                if not self:IsMouseOver() and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                    self:Hide()
                end
            end)
        end)
        menu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)

        self.shareMenu = menu
    end

    self.shareMenu:ClearAllPoints()
    self.shareMenu:SetPoint("TOP", parent, "BOTTOM", 0, -2)
    self.shareMenu:Show()
end

function GameUI:Hide()
    if gameOverlay then gameOverlay:Hide() end
    if scoreFrame then scoreFrame:Hide() end
    if countdownFrame then countdownFrame:Hide() end
    if pauseOverlay then pauseOverlay:Hide() end
    if dangerOverlay then dangerOverlay:Hide() end
    if dangerPulseAG and dangerPulseAG:IsPlaying() then dangerPulseAG:Stop() end
    if self.summaryFrame then self.summaryFrame:Hide() end
    self:HideLevelUpEffect()
    self:HideCompBar()
    self:ReleaseAllNotes()
end

local COMP_ROW_GAP = 4

function GameUI:CreateCompBar()
    local CD = ns.CompetitiveData
    if not CD then return end

    if not compBarFrame then
        compBarFrame = CreateFrame("Frame", "BoundToLearnCompBar", UIParent)
        compBarFrame:SetFrameStrata("FULLSCREEN")
        compBarFrame:SetFrameLevel(55)
    end

    local cols = CD.COLS
    local rows = #CD.rows
    local totalW = cols * (COMP_BTN_SIZE + COMP_BTN_GAP) - COMP_BTN_GAP
    local totalH = rows * COMP_BTN_SIZE + (rows - 1) * COMP_ROW_GAP
    compBarFrame:ClearAllPoints()
    compBarFrame:SetSize(totalW, totalH)
    -- Use the player's dragged position if they set one, else the default anchor
    -- (top row where the old single row sat).
    local pos = BoundToLearn.db.game.compBarPos
    if pos then
        compBarFrame:SetPoint(pos.point or "TOP", UIParent, pos.relPoint or "BOTTOM", pos.x or 0, pos.y or (220 + COMP_BTN_SIZE))
    else
        compBarFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, 220 + COMP_BTN_SIZE)
    end

    -- Clear old buttons and labels
    for _, btn in pairs(compBarButtons) do
        btn:Hide()
    end
    wipe(compBarButtons)
    if compBarFrame.rowLabels then
        for _, lbl in ipairs(compBarFrame.rowLabels) do
            lbl:Hide()
        end
        wipe(compBarFrame.rowLabels)
    end

    for i, slotDef in ipairs(CD.slots) do
        local c = slotDef.color
        local col = slotDef.col
        local row = slotDef.row

        local btn = CreateFrame("Frame", nil, compBarFrame)
        btn:SetSize(COMP_BTN_SIZE, COMP_BTN_SIZE)
        btn:SetPoint("TOPLEFT", compBarFrame, "TOPLEFT",
            (col - 1) * (COMP_BTN_SIZE + COMP_BTN_GAP),
            -(row - 1) * (COMP_BTN_SIZE + COMP_ROW_GAP))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetPoint("TOPLEFT", 2, -2)
        icon:SetPoint("BOTTOMRIGHT", -2, 2)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(slotDef.texture)
        btn.icon = icon

        -- Atlas border (colored per element)
        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        border:SetVertexColor(c[1], c[2], c[3], 0.8)
        btn.border = border

        -- Keybind label
        local rowDef = CD.rows[row]
        local keybind = rowDef.modifier .. tostring(col)
        local lbl = btn:CreateFontString(nil, "OVERLAY")
        lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
        lbl:SetPoint("BOTTOMRIGHT", -2, 2)
        lbl:SetTextColor(0.9, 0.9, 0.9)
        lbl:SetText(self:FormatKeybind(keybind))
        btn.keybindLabel = lbl

        -- Timer text for destruction countdown
        local timerLabel = btn:CreateFontString(nil, "OVERLAY")
        timerLabel:SetFont("Fonts\\FRIZQT__.TTF", 28, "OUTLINE")
        timerLabel:SetPoint("CENTER")
        timerLabel:SetTextColor(1, 0.4, 0.3)
        timerLabel:Hide()
        btn.timerLabel = timerLabel

        btn:Show()
        compBarButtons[i] = btn
    end

    -- Row labels (Shift, Ctrl) to the left
    compBarFrame.rowLabels = {}
    for r, rowDef in ipairs(CD.rows) do
        if rowDef.label then
            local lbl = compBarFrame:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
            lbl:SetPoint("RIGHT", compBarFrame, "TOPLEFT",
                -6, -(r - 1) * (COMP_BTN_SIZE + COMP_ROW_GAP) - COMP_BTN_SIZE / 2)
            lbl:SetTextColor(0.7, 0.7, 0.7)
            lbl:SetText(rowDef.label)
            tinsert(compBarFrame.rowLabels, lbl)
        end
    end

    compBarFrame:Show()
end

function GameUI:GetCompBarButtons()
    return compBarButtons
end

function GameUI:HideCompBar()
    if compBarFrame then compBarFrame:Hide() end
end

function GameUI:SetMirrorFlipped(flipped)
    if not compBarFrame then return end
    local CD = ns.CompetitiveData
    if not CD or #CD.slots == 0 then return end
    local cols = CD.COLS
    for i, btn in pairs(compBarButtons) do
        local slotDef = CD.slots[i]
        if slotDef then
            local col = flipped and (cols + 1 - slotDef.col) or slotDef.col
            btn:ClearAllPoints()
            btn:SetPoint("TOPLEFT", compBarFrame, "TOPLEFT",
                (col - 1) * (COMP_BTN_SIZE + COMP_BTN_GAP),
                -(slotDef.row - 1) * (COMP_BTN_SIZE + COMP_ROW_GAP))
        end
    end
end

function GameUI:SetLaneBombTarget(laneIdx, active)
    local btn = compBarButtons[laneIdx]
    if not btn then return end
    if active then
        btn.savedTexture = btn.icon:GetTexture()
        btn.icon:SetTexture("Interface\\Icons\\Ability_Vehicle_SiegeEngineRam")
        btn.border:SetVertexColor(1, 0.3, 0.1, 1)
    else
        if btn.savedTexture then
            btn.icon:SetTexture(btn.savedTexture)
            btn.savedTexture = nil
        end
        local CD = ns.CompetitiveData
        if CD and CD.slots[laneIdx] then
            local c = CD.slots[laneIdx].color
            btn.border:SetVertexColor(c[1], c[2], c[3], 0.8)
        end
    end
end

function GameUI:DestroyLane(laneIdx, duration)
    local btn = compBarButtons[laneIdx]
    if not btn then return end
    btn.icon:Hide()
    btn.border:Hide()
    if btn.keybindLabel then btn.keybindLabel:Hide() end
    btn.timerLabel:Show()
    btn.destroyExpire = GetTime() + duration

    if not btn.destroyTicker then
        btn:SetScript("OnUpdate", function(self, dt)
            if not self.destroyExpire then
                self:SetScript("OnUpdate", nil)
                return
            end
            local remaining = self.destroyExpire - GetTime()
            if remaining > 0 then
                self.timerLabel:SetText(sformat("%.0f", remaining))
            else
                self:SetScript("OnUpdate", nil)
            end
        end)
        btn.destroyTicker = true
    end
end

function GameUI:RestoreLane(laneIdx)
    local btn = compBarButtons[laneIdx]
    if not btn then return end
    btn.icon:Show()
    btn.border:Show()
    if btn.keybindLabel then btn.keybindLabel:Show() end
    btn.timerLabel:Hide()
    btn.destroyExpire = nil
    btn:SetScript("OnUpdate", nil)
    btn.destroyTicker = nil
end

-- Achievement Panel

function GameUI:GetScoreFrame()
    return scoreFrame
end

local achActiveTab = "achievements"
local trophyDifficulty = "Easy"

function GameUI:ToggleAchievementPanel()
    if achievementPanel and achievementPanel:IsShown() then
        achievementPanel:Hide()
        return
    end
    self:ShowAchievementPanel(achActiveTab)
end

function GameUI:ShowAchievementPanel(tabKey, difficulty)
    if not achievementPanel then
        self:CreateAchievementPanel()
    end
    if tabKey then achActiveTab = tabKey end
    if difficulty then trophyDifficulty = difficulty end
    self:SetAchievementTab(achActiveTab)
    achievementPanel:Show()
end

function GameUI:CreateAchievementPanel()
    if not scoreFrame then return end

    local panel = CreateFrame("Frame", "BoundToLearnAchievements", scoreFrame)
    panel:SetSize(260, 380)
    panel:SetPoint("TOPLEFT", scoreFrame, "TOPRIGHT", 14, -40)
    panel:SetFrameStrata(scoreFrame:GetFrameStrata())
    panel:SetFrameLevel(scoreFrame:GetFrameLevel() + 1)
    Theme.StylePanel(panel, 0.97)
    panel:EnableMouse(true)
    panel:Hide()
    panel:HookScript("OnShow", function() GameUI:RefreshSideTabs() end)
    panel:HookScript("OnHide", function() GameUI:RefreshSideTabs() end)

    -- Tabs
    local tabDefs = {
        { label = "Achievements", key = "achievements" },
        { label = "Trophies",     key = "trophies" },
    }
    panel.tabBtns = {}
    for i, def in ipairs(tabDefs) do
        local tab = CreateFrame("Button", nil, panel)
        tab:SetSize(120, 18)
        tab:SetPoint("TOPLEFT", 8 + (i - 1) * 124, -8)
        tab:SetNormalFontObject("GameFontNormalSmall")
        tab:SetHighlightFontObject("GameFontHighlightSmall")
        tab:SetText(def.label)
        tab.tabKey = def.key

        local underline = tab:CreateTexture(nil, "OVERLAY")
        underline:SetPoint("BOTTOMLEFT", 0, -2)
        underline:SetPoint("BOTTOMRIGHT", 0, -2)
        underline:SetHeight(2)
        underline:SetColorTexture(0.8, 0.65, 0.2, 1)
        underline:Hide()
        tab.underline = underline

        tab:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            GameUI:SetAchievementTab(def.key)
        end)
        panel.tabBtns[i] = tab
    end

    -- Achievements page
    local achPage = CreateFrame("Frame", nil, panel)
    achPage:SetPoint("TOPLEFT", 0, -30)
    achPage:SetPoint("BOTTOMRIGHT")
    panel.achPage = achPage

    local countText = achPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOP", 0, -2)
    countText:SetTextColor(0.7, 0.7, 0.7)
    panel.countText = countText

    local scrollFrame = CreateFrame("ScrollFrame", nil, achPage, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -16)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)
    Theme.StyleScrollBar(scrollFrame.ScrollBar)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(content)
    panel.achContent = content
    panel.achRows = {}

    -- Trophies page
    local trophyPage = CreateFrame("Frame", nil, panel)
    trophyPage:SetPoint("TOPLEFT", 0, -30)
    trophyPage:SetPoint("BOTTOMRIGHT")
    trophyPage:Hide()
    panel.trophyPage = trophyPage

    -- Difficulty sub-tabs for trophies
    panel.diffTabs = {}
    for i, name in ipairs(DIFFICULTIES) do
        local dtab = CreateFrame("Button", nil, trophyPage)
        dtab:SetSize(55, 16)
        dtab:SetPoint("TOPLEFT", 8 + (i - 1) * 58, -2)
        dtab:SetNormalFontObject("GameFontDisableSmall")
        dtab:SetHighlightFontObject("GameFontHighlightSmall")
        dtab:SetText(name)
        dtab.diffName = name

        dtab:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            trophyDifficulty = name
            GameUI:RefreshTrophies()
        end)
        panel.diffTabs[i] = dtab
    end

    -- Trophy rows container
    local trophyContainer = CreateFrame("Frame", nil, trophyPage)
    trophyContainer:SetPoint("TOPLEFT", 8, -24)
    trophyContainer:SetPoint("RIGHT", -8, 0)
    panel.trophyContainer = trophyContainer
    panel.trophyRows = {}

    achievementPanel = panel
end

function GameUI:SetAchievementTab(tabKey)
    achActiveTab = tabKey
    local panel = achievementPanel
    panel.achPage:SetShown(tabKey == "achievements")
    panel.trophyPage:SetShown(tabKey == "trophies")
    for _, tab in ipairs(panel.tabBtns) do
        tab.underline:SetShown(tab.tabKey == tabKey)
    end
    if tabKey == "achievements" then
        self:RefreshAchievementList()
    else
        self:RefreshTrophies()
    end
    self:ResizeAchievementPanel()
end

-- Size the panel to the active tab's content so no dead space trails the
-- last row. Trophies fit exactly; the scrollable achievement list fits its
-- content up to a cap, then scrolls.
function GameUI:ResizeAchievementPanel()
    local panel = achievementPanel
    if not panel then return end
    local Ach = ns.Achievements
    if achActiveTab == "trophies" then
        local rankCount = Ach and (#Ach.RANKS - 1) or 0
        if rankCount < 0 then rankCount = 0 end
        local rowsH = rankCount > 0 and (rankCount * TROPHY_ROW_H + (rankCount - 1) * TROPHY_ROW_PAD) or 0
        panel:SetHeight(54 + rowsH + 8)
    else
        local n = Ach and #Ach.ACHIEVEMENT_LIST or 0
        local rowsH = n > 0 and (n * ACH_ROW_H + (n - 1) * ACH_ROW_PAD) or 0
        panel:SetHeight(mmin(ACH_PANEL_MAX_H, 46 + rowsH + 8))
    end
end

function GameUI:RefreshAchievementList()
    if not achievementPanel then return end
    local Ach = ns.Achievements
    if not Ach then return end

    local content = achievementPanel.achContent
    local list = Ach.ACHIEVEMENT_LIST

    local unlocked, total = Ach:GetUnlockedCount()
    achievementPanel.countText:SetText(sformat("%d / %d Unlocked", unlocked, total))

    local ROW_H, PAD = ACH_ROW_H, ACH_ROW_PAD

    for i, achDef in ipairs(list) do
        local row = achievementPanel.achRows[i]
        if not row then
            row = CreateFrame("Frame", nil, content)
            row:SetHeight(ROW_H)
            Theme.StyleCard(row, Theme.C.PANEL_DARK)

            local name = row:CreateFontString(nil, "OVERLAY")
            name:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            name:SetPoint("TOPLEFT", 8, -4)
            name:SetPoint("RIGHT", -8, 0)
            name:SetJustifyH("LEFT")
            row.name = name

            local desc = row:CreateFontString(nil, "OVERLAY")
            desc:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            desc:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
            desc:SetPoint("RIGHT", -8, 0)
            desc:SetJustifyH("LEFT")
            row.desc = desc

            achievementPanel.achRows[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + PAD)))
        row:SetPoint("RIGHT")

        local isUnlocked = Ach:IsUnlocked(achDef.id)

        if isUnlocked then
            row.name:SetText(sformat("|cFFFFD700%s|r", achDef.name))
        else
            row.name:SetText(sformat("|cFF888888%s|r", achDef.name))
        end

        row.desc:SetText(achDef.desc)
        row.desc:SetTextColor(isUnlocked and 0.8 or 0.5, isUnlocked and 0.8 or 0.5, isUnlocked and 0.8 or 0.5)

        if isUnlocked then
            Theme.SetFill(row, 0.15, 0.12, 0.02, 0.8)
            Theme.SetBorderColor(row, 0.6, 0.5, 0.2, 0.8)
        else
            Theme.SetFill(row, 0.05, 0.05, 0.05, 0.6)
            Theme.SetBorderColor(row, 0.25, 0.25, 0.25, 0.5)
        end

        row:Show()
    end

    for i = #list + 1, #achievementPanel.achRows do
        achievementPanel.achRows[i]:Hide()
    end

    content:SetHeight(#list * (ROW_H + PAD))
end

function GameUI:RefreshTrophies()
    if not achievementPanel then return end
    local Ach = ns.Achievements
    if not Ach then return end
    local panel = achievementPanel

    -- Update difficulty sub-tab highlight
    local dc = DIFF_COLORS
    for _, dtab in ipairs(panel.diffTabs) do
        local c = dc[dtab.diffName]
        if dtab.diffName == trophyDifficulty then
            dtab:SetNormalFontObject("GameFontNormalSmall")
            dtab:GetFontString():SetTextColor(c[1], c[2], c[3])
        else
            dtab:SetNormalFontObject("GameFontDisableSmall")
            dtab:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
    end

    local db = BoundToLearn.db.stats.difficultyBest
    local best = db and db[trophyDifficulty]
    local bestScore = best and best.highestScore or 0
    local ranks = Ach.RANKS

    local ROW_H, PAD = TROPHY_ROW_H, TROPHY_ROW_PAD

    for i, rank in ipairs(ranks) do
        if rank.threshold > 0 then  -- skip Unranked
            local idx = i - 1  -- 1-based minus Unranked
            local row = panel.trophyRows[idx]
            if not row then
                row = CreateFrame("Frame", nil, panel.trophyContainer)
                row:SetHeight(ROW_H)
                Theme.StyleCard(row, Theme.C.PANEL_DARK)
                row:EnableMouse(true)

                local icon = row:CreateTexture(nil, "ARTWORK")
                icon:SetSize(24, 24)
                icon:SetPoint("LEFT", 8, 0)
                icon:SetAtlas("UI-HUD-MicroMenu-Achievements-Mouseover")
                row.icon = icon

                local nameText = row:CreateFontString(nil, "OVERLAY")
                nameText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
                nameText:SetPoint("LEFT", icon, "RIGHT", 8, 4)
                row.nameText = nameText

                local reqText = row:CreateFontString(nil, "OVERLAY")
                reqText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
                reqText:SetPoint("LEFT", icon, "RIGHT", 8, -7)
                row.reqText = reqText

                local checkmark = row:CreateFontString(nil, "OVERLAY")
                checkmark:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
                checkmark:SetPoint("RIGHT", -10, 0)
                row.checkmark = checkmark

                panel.trophyRows[idx] = row
            end

            row:SetPoint("TOPLEFT", 0, -((idx - 1) * (ROW_H + PAD)))
            row:SetPoint("RIGHT")

            local earned = bestScore >= rank.threshold
            local c = rank.rgb

            row.icon:SetVertexColor(earned and c[1] or 0.3, earned and c[2] or 0.3, earned and c[3] or 0.3, earned and 1 or 0.4)
            row.nameText:SetText(sformat("|cFF%s%s|r", rank.color, rank.name))
            row.reqText:SetText(sformat("%s pts", rank.threshold))
            row.reqText:SetTextColor(earned and 0.7 or 0.4, earned and 0.7 or 0.4, earned and 0.7 or 0.4)
            row.checkmark:SetText(earned and "|cFF44CC44Earned|r" or "")

            if earned then
                Theme.SetFill(row, c[1] * 0.12, c[2] * 0.12, c[3] * 0.12, 0.8)
                Theme.SetBorderColor(row, c[1] * 0.5, c[2] * 0.5, c[3] * 0.5, 0.8)
            else
                Theme.SetFill(row, 0.05, 0.05, 0.05, 0.6)
                Theme.SetBorderColor(row, 0.25, 0.25, 0.25, 0.5)
            end

            row:Show()
        end
    end

    -- Hide excess
    local rankCount = #ranks - 1  -- minus Unranked
    for i = rankCount + 1, #panel.trophyRows do
        panel.trophyRows[i]:Hide()
    end
end

-- Keep backward compat for RefreshAchievementPanel calls
function GameUI:RefreshAchievementPanel()
    if not achievementPanel or not achievementPanel:IsShown() then return end
    if achActiveTab == "achievements" then
        self:RefreshAchievementList()
    else
        self:RefreshTrophies()
    end
end

-- Achievement unlock toast notifications
function GameUI:ShowAchievementUnlocks(unlockIDs)
    local Ach = ns.Achievements
    if not Ach then return end

    for i, id in ipairs(unlockIDs) do
        local def = Ach.achievementByID[id]
        if def then
            C_Timer.After((i - 1) * 1.8, function()
                self:ShowAchievementToast(def)
            end)
        end
    end
end

local toastFrame

function GameUI:ShowAchievementToast(def)
    if not toastFrame then
        local f = CreateFrame("Frame", "BoundToLearnAchToast", UIParent)
        f:SetSize(300, 50)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetFrameLevel(200)
        Theme.StyleCard(f, {0.09, 0.08, 0.04}, 12)
        Theme.SetBorderColor(f, Theme.RGB(Theme.C.GOLD, 0.9))
        Theme.SetBorderShown(f, true)
        f:EnableMouse(true)
        f:RegisterForDrag()
        f:Hide()

        f:SetScript("OnMouseUp", function(self, button)
            if button == "RightButton" then
                self.fadeAG:Stop()
                self:Hide()
            end
        end)

        local icon = f:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30)
        icon:SetPoint("LEFT", 10, 0)
        f.icon = icon

        local header = f:CreateFontString(nil, "OVERLAY")
        header:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        header:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
        header:SetText("|cFFFFCC00Achievement Unlocked|r")
        f.header = header

        local name = f:CreateFontString(nil, "OVERLAY")
        name:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
        name:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 8, 2)
        name:SetTextColor(1, 1, 1)
        f.name = name

        -- Fade animation
        local ag = f:CreateAnimationGroup()
        local fadeIn = ag:CreateAnimation("Alpha")
        fadeIn:SetFromAlpha(0)
        fadeIn:SetToAlpha(1)
        fadeIn:SetDuration(0.3)
        fadeIn:SetOrder(1)
        local hold = ag:CreateAnimation("Alpha")
        hold:SetFromAlpha(1)
        hold:SetToAlpha(1)
        hold:SetDuration(2.5)
        hold:SetOrder(2)
        local fadeOut = ag:CreateAnimation("Alpha")
        fadeOut:SetFromAlpha(1)
        fadeOut:SetToAlpha(0)
        fadeOut:SetDuration(0.5)
        fadeOut:SetOrder(3)
        ag:SetScript("OnFinished", function() f:Hide() end)
        f.fadeAG = ag

        toastFrame = f
    end

    -- Anchor to summary frame if visible, otherwise top of screen
    toastFrame:ClearAllPoints()
    if self.summaryFrame and self.summaryFrame:IsShown() then
        toastFrame:SetPoint("BOTTOM", self.summaryFrame, "TOP", 0, 8)
    else
        toastFrame:SetPoint("TOP", UIParent, "TOP", 0, -80)
    end

    toastFrame.icon:SetAtlas(def.icon)
    toastFrame.name:SetText(def.name)
    toastFrame:Show()
    toastFrame:SetAlpha(0)
    toastFrame.fadeAG:Stop()
    toastFrame.fadeAG:Play()

    PlaySound(888)  -- achievement sound
end
