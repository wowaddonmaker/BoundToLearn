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
local pauseOverlay, pauseText
local notePool = {}
local resultPool = {}
local hitZonePool = {}
local countdownFrame, countdownText
local compBarFrame
local compBarButtons = {}
local dangerOverlay
local dangerPulseAG

local NOTE_POOL_SIZE = 20
local RESULT_POOL_SIZE = 10
local NOTE_SIZE = 40
local ICON_CROP = 0.07

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
    if best and best.highestScore > 0 then
        scoreFrame.bestText:SetText(sformat("Best: |cFFFFCC00%d|r", best.highestScore))
    else
        scoreFrame.bestText:SetText("")
    end
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
    controlBar:SetPoint("TOPLEFT", scoreFrame.diffRow, "BOTTOMLEFT", 0, -4)
    controlBar:SetPoint("TOPRIGHT", scoreFrame.diffRow, "BOTTOMRIGHT", 0, -4)
    controlBar:EnableMouse(true)

    local pauseBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    pauseBtn:SetSize(105, 22)
    pauseBtn:SetPoint("TOPLEFT", scoreFrame.diffRow, "BOTTOMLEFT", -1, -4)
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
    stopBtn:SetPoint("TOPRIGHT", scoreFrame.diffRow, "BOTTOMRIGHT", 1, -4)
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
        GameTooltip:AddLine("5 fixed lanes, same for everyone.", 1, 1, 1, true)
        GameTooltip:AddLine("Bomb notes destroy your lane if missed.", 1, 0.8, 0.3, true)
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

local DIFFROW_BOTTOM = 103 -- fixed layout above diffRow: accent+score+dividers+best+diffRow

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
    self:ResizeScoreFrame()
end

function GameUI:OnGameStart(slots)
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

    -- Show/hide difficulty row based on mode
    local mode = ns.Game and ns.Game:GetMode() or "timed"
    if scoreFrame and scoreFrame.diffRow then
        scoreFrame.diffRow:SetShown(mode ~= "competitive")
    end
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
            local glow = CreateFrame("Frame", nil, gameOverlay)
            glow:SetSize(NOTE_SIZE + 8, NOTE_SIZE + 8)
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
            f.icon:SetTexture(note.displayTexture or note.slotInfo.texture)
            f.label:SetText(GameUI:FormatKeybind(note.slotInfo.keybind))
            f.isBomb = note.isBomb

            if note.isBomb then
                f.border:SetVertexColor(1, 0.15, 0.1, 1)
                if not f.bombAG then
                    f.bombAG = f:CreateAnimationGroup()
                    f.bombAG:SetLooping("BOUNCE")
                    local scale = f.bombAG:CreateAnimation("Scale")
                    scale:SetScaleFrom(1, 1)
                    scale:SetScaleTo(1.15, 1.15)
                    scale:SetDuration(0.3)
                    scale:SetSmoothing("IN_OUT")
                end
                f.bombAG:Play()
            else
                f.border:SetVertexColor(1, 1, 1, 0.8)
                if f.bombAG then f.bombAG:Stop() end
            end

            f:Show()
            note.noteFrame = f
            return
        end
    end
end

function GameUI:ReleaseNote(note)
    local f = note.noteFrame
    if f then
        if f.bombAG then f.bombAG:Stop() end
        f:Hide()
        f.inUse = false
        note.noteFrame = nil
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

    local x, y
    if note.spawnAngle then
        -- Random angle approach: converge to target then continue past
        local remaining = 1.0 - progress
        x = xTarget + math.cos(note.spawnAngle) * fallDist * remaining
        y = yTarget + math.sin(note.spawnAngle) * fallDist * remaining
    else
        -- Standard: fall straight down
        x = xTarget
        y = yTarget + fallDist * (1.0 - progress)
    end

    f:ClearAllPoints()
    f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x, y)

    local proximity = mmax(0, 1.0 - mabs(1.0 - progress) * 3)
    local r = 1.0 - proximity * 0.8
    local g = 1.0
    local b = 1.0 - proximity * 0.8
    f.border:SetVertexColor(r, g, b, 0.6 + proximity * 0.4)
end

function GameUI:ShowHitResult(note, result, points)
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
    sf:SetSize(320, 380)
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
    title:SetFont("Fonts\\FRIZQT__.TTF", 20, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFRound Complete|r")
    sf.title = title

    local y = -45
    local function AddRow(label, valueColor)
        local lbl = sf:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("TOPLEFT", 20, y)
        lbl:SetText(label)
        lbl:SetJustifyH("LEFT")

        local val = sf:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
        val:SetPoint("TOPRIGHT", -20, y)
        val:SetJustifyH("RIGHT")
        if valueColor then
            val:SetTextColor(valueColor[1], valueColor[2], valueColor[3])
        end

        y = y - 28
        return lbl, val
    end

    sf.scoreLabel, sf.scoreValue = AddRow("Score", {1, 0.84, 0})
    sf.comboLabel, sf.comboValue = AddRow("Best Combo", {1, 1, 1})
    sf.accuracyLabel, sf.accuracyValue = AddRow("Accuracy", {0.2, 1, 0.2})
    y = y - 10

    local divider = sf:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("LEFT", 15, 0)
    divider:SetPoint("RIGHT", -15, 0)
    divider:SetPoint("TOP", 0, y)
    divider:SetHeight(1)
    divider:SetColorTexture(0.4, 0.4, 0.4, 0.5)
    y = y - 15

    sf.perfectLabel, sf.perfectValue = AddRow("Perfect", RESULT_COLORS.perfect)
    sf.greatLabel, sf.greatValue = AddRow("Great", RESULT_COLORS.great)
    sf.goodLabel, sf.goodValue = AddRow("Good", RESULT_COLORS.good)
    sf.missLabel, sf.missValue = AddRow("Miss", RESULT_COLORS.miss)
    sf.fakeLabel, sf.fakeValue = AddRow("Fakes Hit", RESULT_COLORS.redHerring)
    y = y - 5
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
        "[BoundToLearn] %s %s: Score %d | Accuracy %.1f | Combo %d | P:%d G:%d OK:%d M:%d",
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

-- Competitive bar: 5 universal buttons
local COMP_BTN_SIZE = 48
local COMP_BTN_GAP = 6

function GameUI:CreateCompBar()
    local CD = ns.CompetitiveData
    if not CD then return end

    if not compBarFrame then
        compBarFrame = CreateFrame("Frame", "BoundToLearnCompBar", UIParent, "BackdropTemplate")
        compBarFrame:SetFrameStrata("FULLSCREEN")
        compBarFrame:SetFrameLevel(55)
        local totalW = 5 * (COMP_BTN_SIZE + COMP_BTN_GAP) - COMP_BTN_GAP + 24
        local totalH = COMP_BTN_SIZE + 24
        compBarFrame:SetSize(totalW, totalH)
        compBarFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 100)
        compBarFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        compBarFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.85)
        compBarFrame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
    end

    -- Clear old buttons
    for _, btn in ipairs(compBarButtons) do
        btn:Hide()
    end
    wipe(compBarButtons)

    for i, slotDef in ipairs(CD.slots) do
        local c = slotDef.color
        local btn = CreateFrame("Frame", nil, compBarFrame)
        btn:SetSize(COMP_BTN_SIZE, COMP_BTN_SIZE)
        btn:SetPoint("TOPLEFT", compBarFrame, "TOPLEFT",
            12 + (i - 1) * (COMP_BTN_SIZE + COMP_BTN_GAP), -12)

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(COMP_BTN_SIZE - 4, COMP_BTN_SIZE - 4)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture(slotDef.texture)
        btn.icon = icon

        -- Colored border
        local bSize = 2
        local edgeDefs = {
            { "TOPLEFT", "TOPRIGHT", bSize, nil },
            { "BOTTOMLEFT", "BOTTOMRIGHT", bSize, nil },
            { "TOPLEFT", "BOTTOMLEFT", nil, bSize },
            { "TOPRIGHT", "BOTTOMRIGHT", nil, bSize },
        }
        for _, e in ipairs(edgeDefs) do
            local t = btn:CreateTexture(nil, "OVERLAY")
            t:SetPoint(e[1])
            t:SetPoint(e[2])
            if e[3] then t:SetHeight(e[3]) end
            if e[4] then t:SetWidth(e[4]) end
            t:SetColorTexture(c[1], c[2], c[3], 0.7)
        end

        -- Keybind label
        local keybind = GetBindingKey("ACTIONBUTTON" .. i)
        if keybind then
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
            lbl:SetPoint("BOTTOMRIGHT", -2, 2)
            lbl:SetText(keybind)
            lbl:SetTextColor(0.9, 0.9, 0.9)
        end

        -- Destroyed overlay (hidden by default)
        local destroyOverlay = btn:CreateTexture(nil, "ARTWORK", nil, 2)
        destroyOverlay:SetAllPoints(icon)
        destroyOverlay:SetColorTexture(0.8, 0.1, 0.05, 0.6)
        destroyOverlay:Hide()
        btn.destroyOverlay = destroyOverlay

        local destroyX = btn:CreateFontString(nil, "OVERLAY")
        destroyX:SetFont("Fonts\\FRIZQT__.TTF", 24, "OUTLINE")
        destroyX:SetPoint("CENTER")
        destroyX:SetText("X")
        destroyX:SetTextColor(1, 0.2, 0.1)
        destroyX:Hide()
        btn.destroyX = destroyX

        -- Timer text for destruction countdown
        local timerLabel = btn:CreateFontString(nil, "OVERLAY")
        timerLabel:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
        timerLabel:SetPoint("TOP", 0, -2)
        timerLabel:SetTextColor(1, 0.4, 0.3)
        timerLabel:Hide()
        btn.timerLabel = timerLabel

        btn:Show()
        compBarButtons[i] = btn
    end

    compBarFrame:Show()
end

function GameUI:GetCompBarButtons()
    return compBarButtons
end

function GameUI:HideCompBar()
    if compBarFrame then compBarFrame:Hide() end
end

function GameUI:DestroyLane(laneIdx, duration)
    local btn = compBarButtons[laneIdx]
    if not btn then return end
    btn.destroyOverlay:Show()
    btn.destroyX:Show()
    btn.timerLabel:Show()
    btn.destroyExpire = GetTime() + duration

    -- Tick the countdown
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
    btn.destroyOverlay:Hide()
    btn.destroyX:Hide()
    btn.timerLabel:Hide()
    btn.destroyExpire = nil
    btn:SetScript("OnUpdate", nil)
    btn.destroyTicker = nil
end
