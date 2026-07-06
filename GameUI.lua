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
local pauseOverlay, pauseText
local notePool = {}
local resultPool = {}
local hitZonePool = {}
local countdownFrame, countdownText
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
    closeBtn:SetSize(16, 16)
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
        modifierDropdown.rows = {}
        modifierDropdown:HookScript("OnShow", function() PaintModifierBtn(modifierBtn:IsMouseOver()) end)
        modifierDropdown:HookScript("OnHide", function() PaintModifierBtn(modifierBtn:IsMouseOver()) end)
    end
    local opener = GameUI.modifierOpener or modifierBtn

    local list = Mods.MODIFIER_LIST
    local rowH = 26
    local pad = 6
    local rowW = 208
    modifierDropdown:SetSize(220, #list * rowH + pad * 2)
    modifierDropdown:ClearAllPoints()
    modifierDropdown:SetPoint("TOPLEFT", opener, "BOTTOMLEFT", 0, -2)

    local active = Mods:GetActive()
    local rows = modifierDropdown.rows
    for i, m in ipairs(list) do
        local row = rows[i]
        if not row then
            row = Theme.CreateToggle(modifierDropdown, "", nil, rowW)
            Theme.DelayedTooltip(row, ModifierRowTooltip)
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

function GameUI:RecordSongScore(score)
    local db = BoundToLearn.db.game
    local key, diff = db.songKey, db.difficulty
    if not key or not score then return false end
    db.songScores = db.songScores or {}
    db.songScores[key] = db.songScores[key] or {}
    if (db.songScores[key][diff] or 0) < score then
        db.songScores[key][diff] = score
        return true
    end
    return false
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

-- Keycap widget: a little keyboard-key shape (front lip + top face) whose face
-- fills bottom-up by a fraction. Used for the difficulty meters and the in-game
-- health gauge, tying the visuals to the addon's keybind theme.
-- A physical keyboard keycap: rounded body with a dark rim (depth), a bottom-up
-- coloured fill for the meter, and a soft top sheen. Built from the shared
-- rounded-rect toolkit so it matches the rest of the UI instead of flat squares.
local function MakeKeycap(parent, w, h)
    local cap = CreateFrame("Frame", nil, parent)
    cap:SetSize(w, h)
    Theme.Round(cap)
    Theme.SetBarHeight(cap, mmin(10, h))          -- ~5px corner radius, not a pill
    Theme.SetFill(cap, 0.13, 0.13, 0.15, 1)
    Theme.SetBorderColor(cap, 0, 0, 0, 0.95)      -- dark rim reads as key depth
    cap:SetClipsChildren(true)

    local fill = cap:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("BOTTOMLEFT", 1, 2)             -- 2px front lip at the bottom
    fill:SetPoint("BOTTOMRIGHT", -1, 2)
    fill:SetColorTexture(1, 1, 1, 1)
    fill:Hide()
    cap.fill = fill

    local gloss = cap:CreateTexture(nil, "OVERLAY")
    gloss:SetPoint("TOPLEFT", 2, -2)
    gloss:SetPoint("TOPRIGHT", -2, -2)
    gloss:SetHeight(mmax(2, (h - 4) * 0.42))
    gloss:SetColorTexture(1, 1, 1, 1)
    gloss:SetGradient("VERTICAL", CreateColor(1, 1, 1, 0), CreateColor(1, 1, 1, 0.14))
    cap.gloss = gloss

    cap.faceH = h - 3
    return cap
end

local function SetKeycap(cap, r, g, b, frac, dim)
    frac = frac or 0
    if frac <= 0 then
        cap.fill:Hide()
        Theme.SetFill(cap, 0.12, 0.12, 0.14, dim and 0.5 or 0.95)
        cap.gloss:SetAlpha(dim and 0.4 or 0.8)
        return
    end
    Theme.SetFill(cap, r * 0.22, g * 0.22, b * 0.22, 1)
    cap.fill:SetHeight(mmax(1, cap.faceH * mmin(1, frac)))
    cap.fill:SetColorTexture(r, g, b, dim and 0.6 or 1)
    cap.fill:Show()
    cap.gloss:SetAlpha(dim and 0.5 or 1)
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
    -- selected track's era. This is the ONLY background layer (StylePanel no
    -- longer stamps the generic stone), so nothing is stacked behind it.
    local xbg = f:CreateTexture(nil, "ARTWORK")
    xbg:SetPoint("TOPLEFT", 7, -7)
    xbg:SetPoint("BOTTOMRIGHT", -7, 7)
    xbg:SetAlpha(0.9)
    f.xpacBg = xbg

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    title:SetPoint("TOPLEFT", 18, -14)
    title:SetText("Select Music")
    title:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))

    local closeBtn = Theme.CreateCloseButton(f, function() GameUI:HideSongSelect() end)
    closeBtn:SetSize(16, 16)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)

    -- Right column: a 3D-style song wheel. Fixed slots the tracks roll through
    -- with a sliding animation; the selected track is the large centre slot and
    -- neighbours shrink and run off the clipped right edge above/below.
    f:SetClipsChildren(true)
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
    search:SetPoint("TOPLEFT", 250, -20)
    search:SetPoint("TOPRIGHT", -24, -20)
    search:SetHeight(22)
    search:SetAutoFocus(false)
    search:SetFontObject("GameFontHighlightSmall")
    search:SetTextInsets(10, 10, 0, 0)
    Theme.StylePanel(search, 0.92)

    local ph = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ph:SetPoint("LEFT", 10, 0)
    ph:SetText("Search tracks...")
    search.placeholder = ph

    search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:SetScript("OnEditFocusGained", function(self) self.placeholder:Hide() end)
    search:SetScript("OnEditFocusLost", function(self)
        if self:GetText() == "" then self.placeholder:Show() end
    end)
    search:SetScript("OnTextChanged", function(self, userInput)
        self.placeholder:SetShown(self:GetText() == "")
        if userInput then GameUI:ApplySongSearch(self:GetText()) end
    end)
    f.searchBox = search

    f.wheelCenter = 5
    f.wheelSpacing = 38
    f.animOffset = 0
    f.selIndex = 1
    f.slots = {}
    for s = 1, 9 do
        local slot = CreateFrame("Button", nil, wheelClip)
        slot:EnableMouseWheel(true)
        slot:SetScript("OnMouseWheel", function(_, delta) GameUI:CycleSong(-delta) end)

        local bg = slot:CreateTexture(nil, "ARTWORK")
        bg:SetAllPoints()
        bg:SetColorTexture(1, 1, 1, 1)
        slot.bg = bg

        -- Additive hover glow so hovering a track clearly lights up.
        local hl = slot:CreateTexture(nil, "HIGHLIGHT")
        hl:SetAllPoints()
        hl:SetAtlas("UI-Journeys-Renown-Button")
        hl:SetBlendMode("ADD")
        hl:SetAlpha(0.22)

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

        slot:SetScript("OnClick", function(self)
            if self.dist then GameUI:CycleSong(self.dist) end
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
        Theme.Round(drow)
        Theme.SetBarHeight(drow, 12)
        Theme.SetBorderShown(drow, false)
        drow.diffName = name

        local dl = drow:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dl:SetPoint("LEFT", 10, 0)
        dl:SetText(name)
        drow.label = dl

        local segs = {}
        local SEGN, SEGW, SEGGAP = 10, 12, 2
        for s = 1, SEGN do
            local cap = MakeKeycap(drow, SEGW, 16)
            cap:SetPoint("RIGHT", drow, "RIGHT", -8 - (SEGN - s) * (SEGW + SEGGAP), 0)
            segs[s] = cap
        end
        f.diffSegs[i] = segs

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
    local rp = CreateFrame("Frame", nil, f)
    rp:SetPoint("TOPLEFT", 16, -66)
    rp:SetPoint("BOTTOMLEFT", 16, 14)
    rp:SetWidth(252)
    rp:Hide()

    rp.title = rp:CreateFontString(nil, "OVERLAY")
    rp.title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    rp.title:SetPoint("TOP", 0, -2)

    rp.scoreFS = rp:CreateFontString(nil, "OVERLAY")
    rp.scoreFS:SetFont("Fonts\\FRIZQT__.TTF", 34, "OUTLINE")
    rp.scoreFS:SetPoint("TOP", 0, -30)
    rp.scoreFS:SetTextColor(Theme.RGB(Theme.C.ACCENT_BRIGHT))

    rp.scoreLabel = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rp.scoreLabel:SetPoint("TOP", rp.scoreFS, "BOTTOM", 0, -1)
    rp.scoreLabel:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))

    rp.statFS = rp:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    rp.statFS:SetPoint("TOP", rp.scoreLabel, "BOTTOM", 0, -10)

    rp.bars = {}
    local BAR_W, ROWH, gTop = 150, 22, -132
    for i, j in ipairs(RESULT_JUDGMENTS) do
        local y = gTop - (i - 1) * ROWH
        local lbl = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", 4, y)
        lbl:SetWidth(50)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(j.label)
        lbl:SetTextColor(j.r, j.g, j.b)

        local track = rp:CreateTexture(nil, "ARTWORK")
        track:SetPoint("TOPLEFT", 56, y - 1)
        track:SetSize(BAR_W, 12)
        track:SetColorTexture(1, 1, 1, 0.08)

        local fill = rp:CreateTexture(nil, "OVERLAY")
        fill:SetPoint("TOPLEFT", 56, y - 1)
        fill:SetSize(1, 12)
        fill:SetColorTexture(j.r, j.g, j.b, 0.9)

        local cnt = rp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        cnt:SetPoint("LEFT", track, "RIGHT", 6, 0)
        cnt:SetText("0")

        rp.bars[i] = { spec = j, label = lbl, track = track, fill = fill, count = cnt, w = BAR_W }
    end

    rp.shareBtn = MakeBubbleButton(rp, "Share", 120, 24)
    rp.shareBtn:SetPoint("BOTTOMLEFT", 0, 4)
    rp.shareBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleShareMenu(rp.shareBtn)
    end)

    rp.backBtn = MakeBubbleButton(rp, "Back to Songs", 120, 24)
    rp.backBtn:SetPoint("BOTTOMRIGHT", 0, 4)
    rp.backBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ExitResultsMode()
    end)

    f.resultsPanel = rp
end

function GameUI:ShowResultsOnSelect(results)
    if not songSelect then self:CreateSongSelect() end
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

    local rp = songSelect.resultsPanel
    local totalNotes = results.totalNotes or 0
    local accuracy = totalNotes > 0 and ((totalNotes - (hc.miss or 0)) / totalNotes * 100) or 0

    rp.title:SetText(results.focusFailed and "|cFFFF6666Round Over|r"
        or "|cFF" .. Theme.ACCENT_HEX .. "Round Complete|r")
    rp.scoreFS:SetText(sformat("%d", results.score or 0))
    rp.statFS:SetText(sformat("Accuracy |cFFFFFFFF%.1f%%|r   Max Combo |cFFFFFFFF%d|r",
        accuracy, results.maxCombo or 0))

    local diff = results.difficulty
    local dbb = BoundToLearn.db.stats.difficultyBest
    local diffBest = dbb and diff and dbb[diff]
    local bestScore = diffBest and diffBest.highestScore or 0
    local isNewBest = (results.score or 0) > 0 and results.score >= bestScore
    rp.scoreLabel:SetText(isNewBest and "Score  |cFF33FF66NEW BEST|r" or "Score")

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
    if songSelect.searchBox then
        songSelect.searchBox:Show()
        if songSelect.searchBox.placeholder then songSelect.searchBox.placeholder:Show() end
    end
    self:RefreshSongSelect()
end

-- The carousel always walks the full track list; search scrolls it to a match
-- rather than filtering (a short filtered list would repeat around the wheel).
function GameUI:GetWheelSongs()
    return ns.SongData.songs
end

-- Scroll the carousel to the track that best matches the query: a title prefix
-- wins over a title substring, which wins over an artist match.
function GameUI:ApplySongSearch(query)
    if not songSelect then return end
    query = (query or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if query == "" then return end
    local songs = ns.SongData.songs
    local best, bestRank
    for i, sg in ipairs(songs) do
        local title = sg.title:lower()
        local at = title:find(query, 1, true)
        local rank
        if at == 1 then
            rank = 1
        elseif at then
            rank = 2
        elseif sg.artist and sg.artist:lower():find(query, 1, true) then
            rank = 3
        end
        if rank and (not bestRank or rank < bestRank) then
            best, bestRank = i, rank
            if rank == 1 then break end
        end
    end
    if not best then return end
    songSelect.selIndex = best
    BoundToLearn.db.game.songKey = songs[best].key
    songSelect.animOffset = 0
    songSelect.donutDirty = true
    self:RefreshSongSelect()
    self:PlaySongPreview()
end

function GameUI:CycleSong(step)
    if not songSelect or not step or step == 0 then return end
    if songSelect.resultsMode then self:ExitResultsMode() end
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
        local secs = mfloor(ns.SongData.PlayLength(sg) + 0.5)
        slot.durFS:SetText(mfloor(secs / 60) .. ":" .. (secs % 60 < 10 and "0" or "") .. (secs % 60))
        slot.durFS:SetTextColor(Theme.RGB(Theme.C.TEXT_PRIMARY, mmax(0.4, 0.85 - ae * 0.12)))
        local dsz = mmax(13, mfloor(h * 0.55))
        slot.donut:SetSize(dsz, dsz)
        -- Selected bubble shows its themed dungeon/raid art; the rest are the
        -- renown atlas desaturated to silver so they read on any backdrop.
        if ae < 0.5 then
            local img, tc = ns.SongData.InstanceImage(sg)
            if img then
                slot.bg:SetTexture(img)
                if tc then slot.bg:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
            else
                slot.bg:SetAtlas("UI-Journeys-Renown-Button-pressed")
            end
            slot.bg:SetDesaturated(false)
            slot.bg:SetVertexColor(1, 1, 1, 1)
            slot.titleFS:SetTextColor(1, 1, 1)
        else
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
        if songSelect.donutDirty or slot.donutKey ~= slot.songKey then
            slot.donutKey = slot.songKey
            SetDonut(slot.donut, SongBestProgress(sg.key), ar, ag, ab)
        end
        slot:SetAlpha(mmax(0.28, 1 - ae * 0.09))
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
    for s, slot in ipairs(slots) do
        -- Constant right offset for every slot so their right edges (and the
        -- bottom-right duration) line up instead of fanning per position.
        slot:ClearAllPoints()
        slot:SetPoint("RIGHT", songSelect.wheelClip, "RIGHT", 14, yc[s] - y0)
        -- Round-over shows only the played track, not the whole carousel.
        slot:SetShown(not songSelect.resultsMode or s == center)
    end
    songSelect.donutDirty = false
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
            Theme.SetFill(drow, c[1] * 0.4, c[2] * 0.4, c[3] * 0.4, 0.85)
            drow.label:SetTextColor(c[1], c[2], c[3])
        else
            Theme.SetFill(drow, 0.10, 0.09, 0.08, 0.6)
            drow.label:SetTextColor(c[1] * 0.55, c[2] * 0.55, c[3] * 0.55)
        end
        local rating = (ns.SongData and ns.SongData.Rating(song, name)) or 5
        local caps = songSelect.diffSegs[i]
        for s = 1, #caps do
            SetKeycap(caps[s], c[1], c[2], c[3], (s <= rating) and 1 or 0, not selected)
        end
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
-- scrolling only plays the track the player lands on. PlayMusic overrides the
-- client's zone music, so no volume muting is needed.
local previewToken = 0
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
    self:RefreshSongSelect()
    songSelect:Show()
    self:PlaySongPreview()
end

function GameUI:HideSongSelect()
    if songSelect then songSelect:Hide() end
    if modifierDropdown then modifierDropdown:Hide() end
    StopMusic()
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
    hf:SetSize(540, 34)
    hf:SetPoint("TOP", UIParent, "TOP", 0, -22)
    hf:SetFrameStrata("FULLSCREEN")
    hf:SetFrameLevel(80)
    Theme.StylePanel(hf, 0.92)
    hf:Hide()

    local label = hf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", 12, 0)
    label:SetText("LIFE")
    label:SetTextColor(Theme.RGB(Theme.C.TEXT_DIM))

    self.healthCaps = {}
    local N, CW = 10, 15
    for i = 1, N do
        local cap = MakeKeycap(hf, CW, 18)
        cap:SetPoint("LEFT", 44 + (i - 1) * (CW + 2), 0)
        self.healthCaps[i] = cap
    end

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

function GameUI:UpdateHealthCaps(pct)
    if not self.healthCaps then return end
    local r, g, b
    if pct > 0.6 then
        r, g, b = 0.35, 0.85, 0.45
    elseif pct > 0.3 then
        r, g, b = 0.98, 0.62, 0.18
    else
        r, g, b = 0.85, 0.32, 0.32
    end
    local N = #self.healthCaps
    for i = 1, N do
        local frac = mmax(0, mmin(1, (pct - (i - 1) / N) * N))
        SetKeycap(self.healthCaps[i], r, g, b, frac, false)
    end
end

function GameUI:UpdateFocusBar(current, max)
    self:UpdateHealthCaps(max > 0 and (current / max) or 0)
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

    countdownText = countdownFrame:CreateFontString(nil, "OVERLAY")
    countdownText:SetFont("Fonts\\FRIZQT__.TTF", 72, "OUTLINE")
    countdownText:SetPoint("CENTER")
    countdownText:SetTextColor(1, 0.84, 0)
end

-- Public methods called by Game.lua

local DIFFROW_BOTTOM = 125 -- fixed layout: accent+score+dividers+best+diffRow+modifierRow

function GameUI:ResizeScoreFrame()
    if not scoreFrame or not controlBar then return end
    scoreFrame:SetHeight(DIFFROW_BOTTOM + 4 + controlBar:GetHeight() + 6)
end

function GameUI:ShowReadyState()
    -- The song-select carousel is the ready-state menu. The compact score HUD
    -- and life gauge only appear once a round starts (OnGameStart).
    if scoreFrame then scoreFrame:Hide() end
    if self.healthFrame then self.healthFrame:Hide() end
    if modifierDropdown then modifierDropdown:Hide() end
    self:UpdateDifficultyButtons()
    self:ShowSongSelect()
end

function GameUI:OnGameStart(slots)
    self:ResetStreakTitle()
    self:HideSongSelect()
    self:CreateHealthBar()
    if self.healthFrame then self.healthFrame:Show() end
    self:UpdateHealthCaps(1)
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
    if self.healthFrame then self.healthFrame.pauseBtn:SetText("Pause") end
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
    local fallDist = BoundToLearn.db.game.fallDistance / fScale

    local mods = note.modifiers or {}

    -- Accelerate: remap progress so notes speed up as they fall
    local effectiveProgress = progress
    if mods.accelerate then
        effectiveProgress = progress * progress  -- quadratic ease-in
    end

    local x, y
    if note.spawnAngle then
        local remaining = 1.0 - effectiveProgress
        x = xTarget + math.cos(note.spawnAngle) * fallDist * remaining
        y = yTarget + math.sin(note.spawnAngle) * fallDist * remaining
    else
        x = xTarget
        y = yTarget + fallDist * (1.0 - effectiveProgress)
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

function GameUI:ShowCountdown(seconds, onComplete)
    countdownFrame:Show()
    countdownCancelFlag = false
    local remaining = seconds
    local function Tick()
        if countdownCancelFlag then return end
        if remaining > 0 then
            countdownText:SetText(tostring(remaining))
            countdownText:SetTextColor(1, 0.84, 0)
            PlaySound(SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_TIMER)
            remaining = remaining - 1
            C_Timer.After(1, Tick)
        else
            countdownText:SetText("GO!")
            countdownText:SetTextColor(0.2, 1.0, 0.2)
            PlaySound(SOUNDKIT.UI_BATTLEGROUND_COUNTDOWN_FINISHED)
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
    if countdownFrame then countdownFrame:Hide() end
end

function GameUI:ShowSummary(results)
    if not self.summaryFrame then
        self:CreateSummaryFrame()
    end

    self.lastResults = results
    local sf = self.summaryFrame
    local totalNotes = results.totalNotes
    local accuracy = totalNotes > 0 and ((totalNotes - results.hitCounts.miss) / totalNotes * 100) or 0

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
    local totalNotes = results.totalNotes
    local accuracy = totalNotes > 0 and ((totalNotes - results.hitCounts.miss) / totalNotes * 100) or 0
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
