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

local UIParent = UIParent

local gameOverlay
local controlBar
local scoreFrame, scoreText, comboText, multiplierText, difficultyText, timerText
local pauseOverlay, pauseText
local notePool = {}
local resultPool = {}
local hitZonePool = {}
local countdownFrame, countdownText
local mockBarFrame
local mockBarButtons = {}
local specSelectorFrame

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
        icon:SetSize(NOTE_SIZE - 4, NOTE_SIZE - 4)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        f.icon = icon

        local borderSize = 2
        local edges = {}

        local topEdge = f:CreateTexture(nil, "OVERLAY")
        topEdge:SetPoint("TOPLEFT")
        topEdge:SetPoint("TOPRIGHT")
        topEdge:SetHeight(borderSize)
        topEdge:SetColorTexture(1, 1, 1, 0.8)
        edges[1] = topEdge

        local botEdge = f:CreateTexture(nil, "OVERLAY")
        botEdge:SetPoint("BOTTOMLEFT")
        botEdge:SetPoint("BOTTOMRIGHT")
        botEdge:SetHeight(borderSize)
        botEdge:SetColorTexture(1, 1, 1, 0.8)
        edges[2] = botEdge

        local leftEdge = f:CreateTexture(nil, "OVERLAY")
        leftEdge:SetPoint("TOPLEFT")
        leftEdge:SetPoint("BOTTOMLEFT")
        leftEdge:SetWidth(borderSize)
        leftEdge:SetColorTexture(1, 1, 1, 0.8)
        edges[3] = leftEdge

        local rightEdge = f:CreateTexture(nil, "OVERLAY")
        rightEdge:SetPoint("TOPRIGHT")
        rightEdge:SetPoint("BOTTOMRIGHT")
        rightEdge:SetWidth(borderSize)
        rightEdge:SetColorTexture(1, 1, 1, 0.8)
        edges[4] = rightEdge

        f.edges = edges

        local label = f:CreateFontString(nil, "OVERLAY")
        label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        label:SetPoint("BOTTOMRIGHT", -2, 2)
        label:SetShadowOffset(1, -1)
        label:SetTextColor(1, 1, 1)
        f.label = label

        f.inUse = false
        notePool[i] = f
    end
end

function GameUI:CreateResultPool()
    for i = 1, RESULT_POOL_SIZE do
        local f = gameOverlay:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        f:Hide()
        f.inUse = false

        local ag = f:CreateAnimationGroup()
        local translate = ag:CreateAnimation("Translation")
        translate:SetOffset(0, 60)
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
    scoreFrame:SetSize(240, 160)
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

    -- Divider above difficulty row
    local divider2 = scoreFrame:CreateTexture(nil, "ARTWORK")
    divider2:SetPoint("LEFT", 14, 0)
    divider2:SetPoint("RIGHT", -14, 0)
    divider2:SetPoint("TOP", divider1, "BOTTOM", 0, -22)
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
            BoundToLearn.db.game.difficulty = name
            GameUI:UpdateDifficultyButtons()
        end)

        difficultyText[i] = btn
    end
end

function GameUI:UpdateDifficultyButtons()
    if not difficultyText then return end
    local current = BoundToLearn.db.game.difficulty
    for _, btn in ipairs(difficultyText) do
        if btn.diffName == current then
            btn.bg:SetColorTexture(0.33, 0.8, 1, 0.3)
            btn:GetFontString():SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
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
    controlBar:SetSize(240, 28)
    controlBar:SetPoint("BOTTOMLEFT", scoreFrame, "BOTTOMLEFT", 0, 4)
    controlBar:SetPoint("BOTTOMRIGHT", scoreFrame, "BOTTOMRIGHT", 0, 4)
    controlBar:EnableMouse(true)

    local pauseBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    pauseBtn:SetSize(105, 22)
    pauseBtn:SetPoint("LEFT", 10, 0)
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
    stopBtn:SetPoint("RIGHT", -10, 0)
    stopBtn:SetText("Stop")
    stopBtn:SetScript("OnClick", function()
        if ns.Game then ns.Game:Stop() end
    end)
    controlBar.stopBtn = stopBtn

    -- Start button (shown in ready state, hidden during gameplay)
    local startBtn = CreateFrame("Button", nil, controlBar, "UIPanelButtonTemplate")
    startBtn:SetSize(220, 22)
    startBtn:SetPoint("CENTER", 0, 0)
    startBtn:SetText("Start")
    startBtn:SetScript("OnClick", function()
        if BoundToLearn then BoundToLearn:ToggleGame() end
    end)
    startBtn:Hide()
    controlBar.startBtn = startBtn
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

function GameUI:ShowReadyState()
    if scoreFrame then
        scoreFrame:Show()
        scoreText:SetText("0")
        comboText:SetText("")
        multiplierText:SetText("")
        timerText:SetText("")
        self:UpdateDifficultyButtons()
        if scoreFrame.diffRow then scoreFrame.diffRow:Show() end
    end
    if controlBar then
        controlBar.pauseBtn:Hide()
        controlBar.stopBtn:Hide()
        controlBar.startBtn:Show()
    end
end

function GameUI:OnGameStart(slots)
    if gameOverlay then gameOverlay:Show() end
    if scoreFrame then scoreFrame:Show() end
    if pauseOverlay then pauseOverlay:Hide() end
    if controlBar then
        controlBar.pauseBtn:SetText("Pause")
        controlBar.pauseBtn:Show()
        controlBar.stopBtn:Show()
        controlBar.startBtn:Hide()
    end

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
end

function GameUI:OnGameEnd(results)
    for _, hz in ipairs(hitZonePool) do
        hz:Hide()
    end
    self:ReleaseAllNotes()

    if pauseOverlay then pauseOverlay:Hide() end
    if gameOverlay then gameOverlay:Hide() end
    if scoreFrame then scoreFrame:Hide() end

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

function GameUI:AcquireNote(note)
    for _, f in ipairs(notePool) do
        if not f.inUse then
            f.inUse = true
            f.icon:SetTexture(note.displayTexture or note.slotInfo.texture)
            f.label:SetText(note.slotInfo.keybind)
            for e = 1, 4 do
                f.edges[e]:SetVertexColor(1, 1, 1, 0.8)
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
        -- Random angle approach: start from angle, converge to target
        local remaining = 1.0 - mmin(progress, 1.0)
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
    for e = 1, 4 do
        f.edges[e]:SetVertexColor(r, g, b, 0.6 + proximity * 0.4)
    end
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

    local btn = note.slotInfo.button
    if btn then
        local bx, by = btn:GetCenter()
        if bx then
            local scale = btn:GetEffectiveScale() / f:GetEffectiveScale()
            f:ClearAllPoints()
            f:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bx * scale, by * scale + 30)
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

    local sf = self.summaryFrame
    local totalNotes = results.totalNotes
    local accuracy = totalNotes > 0 and ((totalNotes - results.hitCounts.miss) / totalNotes * 100) or 0

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

    local pb = BoundToLearn.db.stats.personalBest
    local isNewHighScore = results.score > 0 and results.score >= pb.highestScore
    local isNewBestCombo = results.maxCombo > 0 and results.maxCombo >= pb.longestCombo

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
    sf:SetSize(320, 390)
    sf:SetPoint("CENTER")
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

    local close = CreateFrame("Button", nil, sf, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local playAgain = CreateFrame("Button", nil, sf, "UIPanelButtonTemplate")
    playAgain:SetSize(120, 26)
    playAgain:SetPoint("BOTTOM", 0, 14)
    playAgain:SetText("Play Again")
    playAgain:SetScript("OnClick", function()
        sf:Hide()
        GameUI:HideLevelUpEffect()
        GameUI:ShowReadyState()
    end)

    sf:SetScript("OnHide", function()
        GameUI:HideLevelUpEffect()
    end)

    sf:Hide()
    self.summaryFrame = sf
end

function GameUI:Hide()
    if gameOverlay then gameOverlay:Hide() end
    if scoreFrame then scoreFrame:Hide() end
    if countdownFrame then countdownFrame:Hide() end
    if pauseOverlay then pauseOverlay:Hide() end
    if self.summaryFrame then self.summaryFrame:Hide() end
    if specSelectorFrame then specSelectorFrame:Hide() end
    self:HideLevelUpEffect()
    self:HideMockBars()
    self:ReleaseAllNotes()
end

-- Mock action bars for competitive mode
local MOCK_BTN_SIZE = 36
local MOCK_BTN_GAP = 2

function GameUI:CreateMockBars(classKey, specIndex)
    local CD = ns.CompetitiveData
    if not CD or not CD.classes[classKey] then return end
    local specData = CD.classes[classKey].specs[specIndex]
    if not specData then return end

    if not mockBarFrame then
        mockBarFrame = CreateFrame("Frame", "BoundToLearnMockBars", UIParent, "BackdropTemplate")
        mockBarFrame:SetFrameStrata("FULLSCREEN")
        mockBarFrame:SetFrameLevel(55)

        local totalW = 12 * (MOCK_BTN_SIZE + MOCK_BTN_GAP) - MOCK_BTN_GAP + 20
        local totalH = 2 * (MOCK_BTN_SIZE + MOCK_BTN_GAP) - MOCK_BTN_GAP + 20
        mockBarFrame:SetSize(totalW, totalH)
        mockBarFrame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 100)
        mockBarFrame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        mockBarFrame:SetBackdropColor(0.03, 0.03, 0.03, 0.85)
        mockBarFrame:SetBackdropBorderColor(0.25, 0.25, 0.25, 0.8)
    end

    -- Clear old buttons
    for _, btn in ipairs(mockBarButtons) do
        btn:Hide()
    end
    wipe(mockBarButtons)

    local bindPrefixes = { "ACTIONBUTTON", "MULTIACTIONBAR1BUTTON" }
    local classColor = CD.classColors[classKey] or { 0.5, 0.5, 0.5 }

    for i, spellID in ipairs(specData.spells) do
        local row = (i <= 12) and 0 or 1
        local col = (i <= 12) and (i - 1) or (i - 13)
        local barIdx = row + 1
        local btnIdx = col + 1

        local btn = CreateFrame("Frame", nil, mockBarFrame)
        btn:SetSize(MOCK_BTN_SIZE, MOCK_BTN_SIZE)
        btn:SetPoint("TOPLEFT", mockBarFrame, "TOPLEFT",
            10 + col * (MOCK_BTN_SIZE + MOCK_BTN_GAP),
            -10 - row * (MOCK_BTN_SIZE + MOCK_BTN_GAP))

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(MOCK_BTN_SIZE - 4, MOCK_BTN_SIZE - 4)
        icon:SetPoint("CENTER")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local texture = C_Spell.GetSpellTexture(spellID)
        icon:SetTexture(texture or 134400)
        btn.icon = icon

        -- Colored border
        local bSize = 1.5
        local edges = {
            { "TOPLEFT", "TOPRIGHT", bSize, nil },
            { "BOTTOMLEFT", "BOTTOMRIGHT", bSize, nil },
            { "TOPLEFT", "BOTTOMLEFT", nil, bSize },
            { "TOPRIGHT", "BOTTOMRIGHT", nil, bSize },
        }
        for _, e in ipairs(edges) do
            local t = btn:CreateTexture(nil, "OVERLAY")
            t:SetPoint(e[1])
            t:SetPoint(e[2])
            if e[3] then t:SetHeight(e[3]) end
            if e[4] then t:SetWidth(e[4]) end
            t:SetColorTexture(classColor[1], classColor[2], classColor[3], 0.6)
        end

        -- Keybind label
        local keybind = GetBindingKey(bindPrefixes[barIdx] .. btnIdx)
        if keybind then
            local lbl = btn:CreateFontString(nil, "OVERLAY")
            lbl:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
            lbl:SetPoint("BOTTOMRIGHT", -1, 1)
            lbl:SetText(keybind)
            lbl:SetTextColor(0.9, 0.9, 0.9)
        end

        btn:Show()
        mockBarButtons[i] = btn
    end

    mockBarFrame:Show()
end

function GameUI:GetMockBarButtons()
    return mockBarButtons
end

function GameUI:HideMockBars()
    if mockBarFrame then mockBarFrame:Hide() end
end

-- Spec selector for competitive mode
function GameUI:ShowSpecSelector(onSelect)
    if not specSelectorFrame then
        self:CreateSpecSelector()
    end
    specSelectorFrame.onSelect = onSelect
    specSelectorFrame:Show()
end

function GameUI:CreateSpecSelector()
    local CD = ns.CompetitiveData
    local f = CreateFrame("Frame", "BoundToLearnSpecSelector", UIParent, "BackdropTemplate")
    f:SetSize(460, 400)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    f:EnableMouse(true)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFCompetitive Mode|r")

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOP", title, "BOTTOM", 0, -4)
    subtitle:SetText("Select a class and spec")
    subtitle:SetTextColor(0.6, 0.6, 0.6)

    -- Class buttons grid (left side)
    local classLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classLabel:SetPoint("TOPLEFT", 16, -48)
    classLabel:SetText("CLASS")
    classLabel:SetTextColor(0.55, 0.55, 0.55)

    local specContainer = CreateFrame("Frame", nil, f)
    specContainer:SetSize(200, 300)
    specContainer:SetPoint("TOPRIGHT", -16, -48)
    f.specContainer = specContainer

    local specLabel = specContainer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    specLabel:SetPoint("TOPLEFT", 0, 0)
    specLabel:SetText("SPEC")
    specLabel:SetTextColor(0.55, 0.55, 0.55)

    local selectedClass = BoundToLearn.db.game.lastCompClass or "WARRIOR"
    f.selectedClass = selectedClass

    local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    startBtn:SetSize(120, 26)
    startBtn:SetPoint("BOTTOM", 0, 14)
    startBtn:SetText("Start")
    startBtn:SetScript("OnClick", function()
        f:Hide()
        if f.onSelect and f.selectedClass and f.selectedSpec then
            f.onSelect(f.selectedClass, f.selectedSpec)
        end
    end)
    f.startBtn = startBtn

    -- Build class buttons
    local classButtons = {}
    for i, classKey in ipairs(CD.classOrder) do
        local classData = CD.classes[classKey]
        local color = CD.classColors[classKey]
        local row = mfloor((i - 1) / 2)
        local col = (i - 1) % 2

        local btn = CreateFrame("Button", nil, f)
        btn:SetSize(100, 20)
        btn:SetPoint("TOPLEFT", 16 + col * 104, -62 - row * 24)
        btn:SetNormalFontObject("GameFontHighlightSmall")
        btn:SetHighlightFontObject("GameFontNormalSmall")
        btn:SetText(classData.name)
        btn:GetFontString():SetTextColor(color[1], color[2], color[3])

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(color[1], color[2], color[3], 0.1)
        btn.bg = bg

        btn:SetScript("OnClick", function()
            f.selectedClass = classKey
            for _, cb in ipairs(classButtons) do
                cb.bg:SetColorTexture(0.1, 0.1, 0.1, 0.3)
            end
            bg:SetColorTexture(color[1], color[2], color[3], 0.25)
            self:PopulateSpecButtons(f, classKey)
        end)

        classButtons[i] = btn
    end
    f.classButtons = classButtons

    -- Populate initial spec buttons
    self:PopulateSpecButtons(f, selectedClass)
    -- Highlight the initially selected class
    for i, classKey in ipairs(CD.classOrder) do
        if classKey == selectedClass then
            local color = CD.classColors[classKey]
            classButtons[i].bg:SetColorTexture(color[1], color[2], color[3], 0.25)
        end
    end

    f:Hide()
    specSelectorFrame = f
end

function GameUI:PopulateSpecButtons(frame, classKey)
    local CD = ns.CompetitiveData
    local classData = CD.classes[classKey]
    local color = CD.classColors[classKey]
    local container = frame.specContainer

    -- Clear old spec buttons
    if container.buttons then
        for _, btn in ipairs(container.buttons) do
            btn:Hide()
        end
    end
    container.buttons = {}

    local savedSpec = (classKey == BoundToLearn.db.game.lastCompClass) and BoundToLearn.db.game.lastCompSpec or 1
    frame.selectedSpec = savedSpec

    for i, specData in ipairs(classData.specs) do
        local btn = CreateFrame("Button", nil, container)
        btn:SetSize(190, 28)
        btn:SetPoint("TOPLEFT", 0, -16 - (i - 1) * 32)
        btn:SetNormalFontObject("GameFontHighlight")
        btn:SetHighlightFontObject("GameFontNormal")
        btn:SetText(specData.name)

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
        btn.bg = bg

        if i == savedSpec then
            bg:SetColorTexture(color[1], color[2], color[3], 0.25)
        end

        btn:SetScript("OnClick", function()
            frame.selectedSpec = i
            for _, sb in ipairs(container.buttons) do
                sb.bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
            end
            bg:SetColorTexture(color[1], color[2], color[3], 0.25)
        end)

        container.buttons[i] = btn
    end
end
