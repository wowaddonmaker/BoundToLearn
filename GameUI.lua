local ADDON_NAME, ns = ...

local GameUI = {}
ns.GameUI = GameUI

local Utils      = ns.Utils
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
local SOUND_CLOSE = Utils.SOUND_CLOSE

local UIParent = UIParent
local GameTooltip = GameTooltip
local SendChatMessage = SendChatMessage
local IsMouseButtonDown = IsMouseButtonDown

local gameOverlay
local controlBar
local scoreFrame, scoreText, comboText, multiplierText, difficultyText, timerText
local modifierRow, modifierBtn, modifierDropdown
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

local DIFF_COLORS = {
    Easy    = { 0.30, 0.85, 0.30 },
    Medium  = { 1.00, 0.82, 0.00 },
    Hard    = { 1.00, 0.50, 0.10 },
    Extreme = { 0.90, 0.15, 0.15 },
}

local DARK_BACKDROP = {
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
}

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
    local DIFFICULTIES = { "Easy", "Medium", "Hard", "Extreme" }

    scoreFrame = CreateFrame("Frame", "BoundToLearnScoreHUD", UIParent, "BackdropTemplate")
    scoreFrame:SetSize(240, 178)
    scoreFrame:SetPoint("TOP", UIParent, "TOP", 0, -30)
    scoreFrame:SetFrameStrata("FULLSCREEN")
    scoreFrame:SetFrameLevel(70)
    scoreFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    scoreFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.92)
    scoreFrame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.9)
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
    accent:SetColorTexture(0.33, 0.8, 1, 0.7)

    -- Close button (top-right, below accent)
    local closeBtn = CreateFrame("Button", nil, scoreFrame)
    closeBtn:SetSize(20, 20)
    closeBtn:SetPoint("TOPRIGHT", -6, -8)
    local closeTex = closeBtn:CreateFontString(nil, "OVERLAY")
    closeTex:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    closeTex:SetPoint("CENTER", 0, 0)
    closeTex:SetText("x")
    closeTex:SetTextColor(0.5, 0.5, 0.5)
    closeBtn:SetScript("OnEnter", function() closeTex:SetTextColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeTex:SetTextColor(0.5, 0.5, 0.5) end)
    closeBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLOSE)
        if ns.Game and ns.Game:IsRunning() then
            ns.Game:Stop()
        end
        scoreFrame:Hide()
    end)

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

    -- Rank icon (tinted achievement symbol next to best score, with tooltip)
    local rankBtn = CreateFrame("Frame", nil, scoreFrame)
    rankBtn:SetSize(18, 18)
    rankBtn:SetPoint("LEFT", bestText, "RIGHT", 3, 0)
    rankBtn:EnableMouse(true)
    rankBtn:Hide()

    local rankTex = rankBtn:CreateTexture(nil, "OVERLAY")
    rankTex:SetAllPoints()
    rankTex:SetAtlas("UI-HUD-MicroMenu-Achievements-Mouseover")
    rankBtn.tex = rankTex

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

        local btnBg = btn:CreateTexture(nil, "BACKGROUND")
        btnBg:SetAllPoints()
        btnBg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
        btn.bg = btnBg

        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            BoundToLearn.db.game.difficulty = name
            GameUI:UpdateDifficultyButtons()
            GameUI:UpdateBestText()
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

    local modBg = modifierBtn:CreateTexture(nil, "BACKGROUND")
    modBg:SetAllPoints()
    modBg:SetColorTexture(0.12, 0.12, 0.18, 0.6)
    modifierBtn.bg = modBg

    modifierBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleModifierDropdown()
    end)
    GameUI:UpdateModifierButton()

    -- Sidebar tab anchored flush to the right edge of scoreFrame, centered vertically
    local sideTab = CreateFrame("Button", nil, scoreFrame, "BackdropTemplate")
    sideTab:SetSize(18, 80)
    sideTab:SetPoint("LEFT", scoreFrame, "RIGHT", -3, 0)
    sideTab:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    sideTab:SetBackdropColor(0.06, 0.05, 0.02, 0.95)
    sideTab:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)

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
        self:SetBackdropBorderColor(0.6, 0.5, 0.2, 1)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Achievements")
        GameTooltip:Show()
    end)
    sideTab:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
        GameTooltip:Hide()
    end)
    scoreFrame.sideTab = sideTab

    -- Leaderboard tab anchored flush to the left edge of scoreFrame
    local lbTab = CreateFrame("Button", nil, scoreFrame, "BackdropTemplate")
    lbTab:SetSize(18, 80)
    lbTab:SetPoint("RIGHT", scoreFrame, "LEFT", 3, 0)
    lbTab:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 8,
        insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    lbTab:SetBackdropColor(0.02, 0.05, 0.06, 0.95)
    lbTab:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)

    local lbIcon = lbTab:CreateTexture(nil, "ARTWORK")
    lbIcon:SetSize(12, 12)
    lbIcon:SetPoint("CENTER")
    lbIcon:SetAtlas("UI-HUD-MicroMenu-GuildCommunities-Mouseover")
    lbTab.icon = lbIcon

    lbTab:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        if ns.LeaderboardUI then ns.LeaderboardUI:Toggle() end
    end)
    lbTab:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(0.2, 0.5, 0.6, 1)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Leaderboard")
        GameTooltip:Show()
    end)
    lbTab:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.9)
        GameTooltip:Hide()
    end)
    scoreFrame.lbTab = lbTab
end

function GameUI:UpdateDifficultyButtons()
    if not difficultyText then return end
    local current = BoundToLearn.db.game.difficulty
    for _, btn in ipairs(difficultyText) do
        local c = DIFF_COLORS[btn.diffName]
        if btn.diffName == current then
            btn.bg:SetColorTexture(c[1], c[2], c[3], 0.3)
            btn:GetFontString():SetTextColor(c[1], c[2], c[3])
        else
            btn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
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
        fs:SetTextColor(count > 0 and 0.4 or 0.7, count > 0 and 0.8 or 0.7, count > 0 and 1.0 or 0.7)
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
        modifierDropdown = CreateFrame("Frame", nil, modifierBtn, "BackdropTemplate")
        modifierDropdown:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 10,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        modifierDropdown:SetBackdropColor(0.06, 0.05, 0.08, 0.95)
        modifierDropdown:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.9)
        modifierDropdown:SetFrameStrata("FULLSCREEN_DIALOG")
        modifierDropdown:SetFrameLevel(100)
    end

    -- Clear old children
    for _, child in ipairs({modifierDropdown:GetChildren()}) do
        child:Hide()
        child:SetParent(nil)
    end

    local list = Mods.MODIFIER_LIST
    local rowH = 20
    local pad = 4
    modifierDropdown:SetSize(220, #list * rowH + pad * 2)
    modifierDropdown:ClearAllPoints()
    modifierDropdown:SetPoint("TOPLEFT", modifierBtn, "BOTTOMLEFT", 0, -2)

    local active = Mods:GetActive()
    for i, m in ipairs(list) do
        local row = CreateFrame("Button", nil, modifierDropdown)
        row:SetSize(216, rowH)
        row:SetPoint("TOPLEFT", pad, -(pad + (i - 1) * rowH))
        row:SetNormalFontObject("GameFontNormalSmall")
        row:SetHighlightFontObject("GameFontHighlightSmall")

        local unlocked = Mods:IsUnlocked(m.id)
        local isActive = active[m.id]

        if unlocked then
            local prefix = isActive and "|cFF44CC44[x]|r " or "|cFF666666[ ]|r "
            row:SetText(prefix .. m.name)
            local fs = row:GetFontString()
            fs:SetTextColor(isActive and 0.4 or 0.85, isActive and 0.8 or 0.85, isActive and 1.0 or 0.85)
            row:SetScript("OnClick", function()
                PlayUISound(SOUND_CLICK)
                Mods:Toggle(m.id)
                GameUI:BuildModifierDropdown()
                GameUI:UpdateModifierButton()
            end)
        else
            row:SetText("|cFF555555[ ] " .. m.name .. "|r")
            row:SetScript("OnClick", function() end)
        end

        row:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(m.name)
            GameTooltip:AddLine(m.desc, 1, 1, 1, true)
            if m.descExtra then
                GameTooltip:AddLine(m.descExtra, 0.6, 0.8, 1.0, true)
            end
            if not unlocked and m.unlockHint then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Unlock: " .. m.unlockHint, 1, 0.5, 0.2, true)
            end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    modifierDropdown:Show()
end

function GameUI:UpdateTimer(remaining)
    if timerText then
        if remaining then
            local mins = mfloor(remaining / 60)
            local secs = mfloor(remaining % 60)
            timerText:SetText(sformat("%d:%02d", mins, secs))
            if remaining <= 10 then
                timerText:SetTextColor(1, 0.3, 0.3)
            elseif remaining <= 30 then
                timerText:SetTextColor(1, 0.85, 0.3)
            else
                timerText:SetTextColor(0.7, 0.7, 0.7)
            end
        else
            timerText:SetText("")
        end
    end
end

function GameUI:CreateControlBar()
    controlBar = CreateFrame("Frame", nil, scoreFrame)
    controlBar:SetPoint("TOPLEFT", scoreFrame.modifierRow, "BOTTOMLEFT", 0, -4)
    controlBar:SetPoint("TOPRIGHT", scoreFrame.modifierRow, "BOTTOMRIGHT", 0, -4)
    controlBar:EnableMouse(true)

    local pauseBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    pauseBtn:SetSize(105, 22)
    pauseBtn:SetPoint("TOPLEFT", scoreFrame.modifierRow, "BOTTOMLEFT", -1, -4)
    pauseBtn:SetText("Pause")
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

    local stopBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    stopBtn:SetSize(105, 22)
    stopBtn:SetPoint("TOPRIGHT", scoreFrame.modifierRow, "BOTTOMRIGHT", 1, -4)
    stopBtn:SetText("Stop")
    stopBtn:SetScript("OnClick", function()
        if ns.Game then ns.Game:Stop() end
    end)
    controlBar.stopBtn = stopBtn

    -- Start button (shown in ready state, hidden during gameplay)
    local startBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    startBtn:SetSize(220, 22)
    startBtn:SetPoint("TOP", 0, 0)
    startBtn:SetText("Start")
    startBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "timed"
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    startBtn:Hide()
    controlBar.startBtn = startBtn

    -- Practice button (below Start, shown in ready state)
    local practiceBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    practiceBtn:SetSize(108, 22)
    practiceBtn:SetPoint("TOPLEFT", startBtn, "BOTTOMLEFT", 0, -2)
    practiceBtn:SetText("Practice")
    practiceBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "practice"
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    practiceBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Practice Mode")
        GameTooltip:AddLine("No time limit. Play until you stop.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    practiceBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    practiceBtn:Hide()
    controlBar.practiceBtn = practiceBtn

    -- Competitive button (right of Practice, shown in ready state)
    local compBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    compBtn:SetSize(108, 22)
    compBtn:SetPoint("TOPRIGHT", startBtn, "BOTTOMRIGHT", 0, -2)
    compBtn:SetText("Competitive")
    compBtn:SetScript("OnClick", function()
        BoundToLearn.db.game.mode = "competitive"
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    compBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Competitive Mode")
        GameTooltip:AddLine("15 fixed lanes (1-5, Shift, Ctrl), same for everyone.", 1, 1, 1, true)
        GameTooltip:AddLine("Bomb notes destroy your lane if missed.", 1, 0.8, 0.3, true)
        GameTooltip:AddLine("Extreme forces angled notes.", 0.6, 0.8, 1.0, true)
        GameTooltip:AddLine("Pausing resets your score to zero.", 1, 0.5, 0.5, true)
        GameTooltip:Show()
    end)
    compBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    compBtn:Hide()
    controlBar.compBtn = compBtn

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

function GameUI:UpdateFocusBar(current, max)
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
    if scoreFrame then
        scoreFrame:Show()
        scoreText:SetText("0")
        comboText:SetText("")
        multiplierText:SetText("")
        timerText:SetText("")
        self:UpdateDifficultyButtons()
        if scoreFrame.diffRow then scoreFrame.diffRow:Show() end
        if modifierRow then modifierRow:Show() end
        self:UpdateModifierButton()
        self:UpdateBestText()
    end
    if controlBar then
        controlBar.pauseBtn:Hide()
        controlBar.stopBtn:Hide()
        controlBar.startBtn:Show()
        controlBar.practiceBtn:Show()
        controlBar.compBtn:Show()
        controlBar:SetHeight(46)
    end
    if modifierDropdown then modifierDropdown:Hide() end
    self:ResizeScoreFrame()
end

function GameUI:OnGameStart(slots)
    self:ResetStreakTitle()
    if self.summaryFrame and self.summaryFrame:IsShown() then
        self.summaryFrame:Hide()
    end
    if gameOverlay then gameOverlay:Show() end
    if scoreFrame then scoreFrame:Show() end
    if pauseOverlay then pauseOverlay:Hide() end
    if controlBar then
        controlBar.pauseBtn:SetText("Pause")
        controlBar.pauseBtn:Show()
        controlBar.stopBtn:Show()
        controlBar.startBtn:Hide()
        controlBar.practiceBtn:Hide()
        controlBar.compBtn:Hide()
        controlBar:SetHeight(22)
    end
    self:ResizeScoreFrame()

    -- Hide difficulty and modifier rows during gameplay
    local mode = ns.Game and ns.Game:GetMode() or "timed"
    if scoreFrame and scoreFrame.diffRow then
        scoreFrame.diffRow:SetShown(mode ~= "competitive")
    end
    if modifierRow then modifierRow:Hide() end
    if modifierDropdown then modifierDropdown:Hide() end
    self:UpdateDifficultyButtons()

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

    self:ShowReadyState()
    self:ShowSummary(results)
end

function GameUI:OnGamePause()
    if pauseOverlay then pauseOverlay:Show() end
    if controlBar then controlBar.pauseBtn:SetText("Resume") end
end

function GameUI:OnGameResume()
    if pauseOverlay then pauseOverlay:Hide() end
    if controlBar then controlBar.pauseBtn:SetText("Pause") end
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
            tex:SetColorTexture(1, 1, 1, 0.1)
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
    if scoreText then
        scoreText:SetText(sformat("%d", currentScore))
    end
    if comboText then
        if currentCombo > 0 and BoundToLearn.db.game.showCombo then
            comboText:SetText(sformat("%d Combo", currentCombo))
            if currentCombo >= 30 then
                comboText:SetTextColor(1, 0.3, 0.3)
            elseif currentCombo >= 15 then
                comboText:SetTextColor(1, 0.6, 0.2)
            elseif currentCombo >= 5 then
                comboText:SetTextColor(1, 0.85, 0.3)
            else
                comboText:SetTextColor(0.7, 0.7, 0.7)
            end
        else
            comboText:SetText("")
        end
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
            sf.title:SetText("|cFF55CCFFRound Complete|r")
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
    local sf = CreateFrame("Frame", "BoundToLearnSummary", UIParent, "BackdropTemplate")
    sf:SetSize(280, 310)
    sf:SetFrameStrata("FULLSCREEN_DIALOG")
    sf:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    sf:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    sf:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    sf:EnableMouse(true)

    local title = sf:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFF55CCFFRound Complete|r")
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
    local shareBtn = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    shareBtn:SetSize(100, 22)
    shareBtn:SetPoint("BOTTOM", 0, 10)
    shareBtn:SetText("Share")
    shareBtn:SetScript("OnClick", function()
        PlayUISound(SOUND_CLICK)
        GameUI:ToggleShareMenu(sf)
    end)
    y = y - 30

    local close = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

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
        local menu = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        menu:SetSize(100, 118)
        menu:SetFrameStrata("FULLSCREEN_DIALOG")
        menu:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        menu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        menu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
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
    -- Anchor so the top row (base keys) stays at the same position as the old single row
    compBarFrame:SetPoint("TOP", UIParent, "BOTTOM", 0, 220 + COMP_BTN_SIZE)

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

local achievementPanel

function GameUI:ToggleAchievementPanel()
    if achievementPanel and achievementPanel:IsShown() then
        achievementPanel:Hide()
        return
    end
    if not achievementPanel then
        self:CreateAchievementPanel()
    end
    self:RefreshAchievementPanel()
    achievementPanel:Show()
end

function GameUI:CreateAchievementPanel()
    if not scoreFrame then return end

    local panel = CreateFrame("Frame", "BoundToLearnAchievements", scoreFrame, "BackdropTemplate")
    panel:SetSize(260, 380)
    panel:SetPoint("TOPLEFT", scoreFrame, "TOPRIGHT", 14, 0)
    panel:SetFrameStrata(scoreFrame:GetFrameStrata())
    panel:SetFrameLevel(scoreFrame:GetFrameLevel() + 1)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    panel:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    panel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
    panel:EnableMouse(true)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    title:SetPoint("TOP", 0, -10)
    title:SetText("|cFFFFCC00Achievements|r")

    local countText = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    countText:SetPoint("TOP", title, "BOTTOM", 0, -3)
    countText:SetTextColor(0.7, 0.7, 0.7)
    panel.countText = countText

    local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 8, -38)
    scrollFrame:SetPoint("BOTTOMRIGHT", -26, 8)

    local content = CreateFrame("Frame", nil, scrollFrame)
    content:SetWidth(scrollFrame:GetWidth())
    scrollFrame:SetScrollChild(content)
    panel.content = content

    panel.rows = {}
    achievementPanel = panel
end

function GameUI:RefreshAchievementPanel()
    if not achievementPanel then return end
    local Ach = ns.Achievements
    if not Ach then return end

    local content = achievementPanel.content
    local list = Ach.ACHIEVEMENT_LIST

    -- Update count
    local unlocked, total = Ach:GetUnlockedCount()
    achievementPanel.countText:SetText(sformat("%d / %d Unlocked", unlocked, total))

    local ROW_H = 36
    local PAD = 2

    for i, achDef in ipairs(list) do
        local row = achievementPanel.rows[i]
        if not row then
            row = CreateFrame("Frame", nil, content, "BackdropTemplate")
            row:SetHeight(ROW_H)
            row:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 },
            })

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

            achievementPanel.rows[i] = row
        end

        row:SetPoint("TOPLEFT", 0, -((i - 1) * (ROW_H + PAD)))
        row:SetPoint("RIGHT")

        local isUnlocked = Ach:IsUnlocked(achDef.id)

        if isUnlocked then
            row.name:SetText(sformat("|cFFFFD700%s|r", achDef.name))
        else
            row.name:SetText(sformat("|cFF888888%s|r", achDef.name))
        end

        -- Description
        row.desc:SetText(achDef.desc)
        row.desc:SetTextColor(isUnlocked and 0.8 or 0.5, isUnlocked and 0.8 or 0.5, isUnlocked and 0.8 or 0.5)

        -- Background tint
        if isUnlocked then
            row:SetBackdropColor(0.15, 0.12, 0.02, 0.8)
            row:SetBackdropBorderColor(0.6, 0.5, 0.2, 0.8)
        else
            row:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
            row:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.5)
        end

        row:Show()
    end

    -- Hide excess rows
    for i = #list + 1, #achievementPanel.rows do
        achievementPanel.rows[i]:Hide()
    end

    content:SetHeight(#list * (ROW_H + PAD))
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
        local f = CreateFrame("Frame", "BoundToLearnAchToast", UIParent, "BackdropTemplate")
        f:SetSize(300, 50)
        f:SetPoint("TOP", UIParent, "TOP", 0, -80)
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        f:SetBackdropColor(0.1, 0.08, 0.02, 0.95)
        f:SetBackdropBorderColor(0.8, 0.65, 0.2, 1)
        f:Hide()

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

    toastFrame.icon:SetAtlas(def.icon)
    toastFrame.name:SetText(def.name)
    toastFrame:Show()
    toastFrame:SetAlpha(0)
    toastFrame.fadeAG:Stop()
    toastFrame.fadeAG:Play()

    PlaySound(888)  -- achievement sound
end
