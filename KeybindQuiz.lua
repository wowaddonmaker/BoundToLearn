local ADDON_NAME, ns = ...

local KeybindQuiz = {}
ns.KeybindQuiz = KeybindQuiz

local Utils      = ns.Utils
local sformat    = Utils.sformat
local tinsert    = Utils.tinsert
local ipairs     = Utils.ipairs
local wipe       = Utils.wipe
local CreateFrame = Utils.CreateFrame
local mmin       = Utils.mmin
local mmax       = Utils.mmax
local mfloor     = Utils.mfloor

local UIParent         = UIParent
local HasAction        = HasAction
local GetActionInfo    = GetActionInfo
local GetActionTexture = GetActionTexture
local GetActionText    = GetActionText
local GetBindingKey    = GetBindingKey
local C_Spell          = C_Spell
local C_Timer          = C_Timer
local GetTime          = GetTime
local IsAltKeyDown     = IsAltKeyDown
local IsControlKeyDown = IsControlKeyDown
local IsShiftKeyDown   = IsShiftKeyDown
local InCombatLockdown = InCombatLockdown
local PlaySound        = PlaySound

local ICON_SIZE = 80
local ICON_CROP = 0.07
local HEAP_ICON_SIZE = 36
local HEAP_X_OFFSET = 160
local HEAP_Y_BASE = -20
local HEAP_SCATTER = 20
local FLY_DURATION = 0.35

local MODIFIER_KEYS = {
    LSHIFT = true, RSHIFT = true, LCTRL = true, RCTRL = true,
    LALT = true, RALT = true,
}

local BAR_MAPPINGS = {
    { bindPrefix = "ACTIONBUTTON",           btnPrefix = "ActionButton",              startSlot = 1,   barFrame = "MainMenuBar" },
    { bindPrefix = "MULTIACTIONBAR1BUTTON",  btnPrefix = "MultiBarBottomLeftButton",  startSlot = 61,  barFrame = "MultiBarBottomLeft" },
    { bindPrefix = "MULTIACTIONBAR2BUTTON",  btnPrefix = "MultiBarBottomRightButton", startSlot = 49,  barFrame = "MultiBarBottomRight" },
    { bindPrefix = "MULTIACTIONBAR3BUTTON",  btnPrefix = "MultiBarRightButton",       startSlot = 25,  barFrame = "MultiBarRight" },
    { bindPrefix = "MULTIACTIONBAR4BUTTON",  btnPrefix = "MultiBarLeftButton",        startSlot = 37,  barFrame = "MultiBarLeft" },
    { bindPrefix = "MULTIACTIONBAR5BUTTON",  btnPrefix = "MultiBar5Button",           startSlot = 145, barFrame = "MultiBar5" },
    { bindPrefix = "MULTIACTIONBAR6BUTTON",  btnPrefix = "MultiBar6Button",           startSlot = 157, barFrame = "MultiBar6" },
    { bindPrefix = "MULTIACTIONBAR7BUTTON",  btnPrefix = "MultiBar7Button",           startSlot = 169, barFrame = "MultiBar7" },
}

-- State
local quizFrame, inputFrame, dimmer
local allCards = {}
local deck = {}
local currentIndex = 0
local correctPile = {}
local wrongPile = {}
local isRunning = false
local quizFinished = false
local waitingForNext = false
local advanceTimer
local wrongFlyTimer
local hiddenBars = {}
local roundNumber = 1
local isReviewRound = false
local isPractice = false
local quizStartTime = 0
local totalWrongAnswers = 0
local pendingFly       -- { texture, whichPile, anchorFrame }
local pendingWrongIcon -- { texture, anchorFrame } for wrong answers awaiting fly timer

-- UI refs
local cardFrame, cardIcon, cardBorder, glowBorder
local cardName, promptText, answerLabel, answerKeybind
local progressText, correctCountText, wrongCountText, roundText, timerText
local correctHeapLabel, wrongHeapLabel
local heapPool = {}
local activeHeapIcons = { correct = {}, wrong = {} }
local flyerFrame

-- Helpers

local function GetAbilityName(slot)
    local actionType, id = GetActionInfo(slot)
    if actionType == "spell" and id and id > 0 then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    elseif actionType == "macro" then
        return GetActionText(slot)
    elseif actionType == "item" and id then
        return C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
    end
    return nil
end

local function FormatKeybind(bind)
    if not bind then return "" end
    bind = bind:gsub("SHIFT%-", "S-")
    bind = bind:gsub("CTRL%-", "C-")
    bind = bind:gsub("ALT%-", "A-")
    return bind
end

local function Shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
end

local function DiscoverCards()
    wipe(allCards)
    local shouldIgnore = ns.Tracker and ns.Tracker.ShouldIgnoreAction
    local seen = {}

    for _, bar in ipairs(BAR_MAPPINGS) do
        for i = 1, 12 do
            local slot = bar.startSlot + (i - 1)
            local btn = _G[bar.btnPrefix .. i]
            if btn then
                local actualSlot = btn.action or (btn.GetAction and btn:GetAction())
                if actualSlot then slot = actualSlot end
            end

            if HasAction(slot) then
                local keybind = GetBindingKey(bar.bindPrefix .. i)
                if keybind and not seen[keybind] then
                    local skip = shouldIgnore and shouldIgnore(slot)
                    if not skip then
                        seen[keybind] = true
                        tinsert(allCards, {
                            slot = slot,
                            keybind = keybind,
                            texture = GetActionTexture(slot) or "Interface\\Icons\\INV_Misc_QuestionMark",
                            name = GetAbilityName(slot) or sformat("Slot %d", slot),
                        })
                    end
                end
            end
        end
    end
end

-- Class bars that aren't quizzed but should still be hidden so nothing is referenceable.
local EXTRA_BARS = {
    { barFrame = "PetActionBar", btnPrefix = "PetActionButton", count = 10 },
    { barFrame = "StanceBar",    btnPrefix = "StanceButton",    count = 10 },
}

-- Hide the action bars entirely for the duration of the quiz so there is nothing to
-- reference. Alpha (not Hide) keeps this out of protected-frame territory and is fully
-- reversible; both the bar frame and its buttons are dimmed so bar art disappears too.
-- Hiding the buttons directly guarantees they vanish even if the frame name is wrong.
local function DimBar(frameName, btnPrefix, count)
    local frame = frameName and _G[frameName]
    if frame then
        hiddenBars[#hiddenBars + 1] = { region = frame, alpha = frame:GetAlpha() }
        frame:SetAlpha(0)
    end
    for i = 1, count do
        local btn = _G[btnPrefix .. i]
        if btn then
            hiddenBars[#hiddenBars + 1] = { region = btn, alpha = btn:GetAlpha() }
            btn:SetAlpha(0)
        end
    end
end

local function HideActionBars()
    wipe(hiddenBars)
    for _, bar in ipairs(BAR_MAPPINGS) do
        DimBar(bar.barFrame, bar.btnPrefix, 12)
    end
    for _, bar in ipairs(EXTRA_BARS) do
        DimBar(bar.barFrame, bar.btnPrefix, bar.count)
    end
end

local function RestoreActionBars()
    for _, entry in ipairs(hiddenBars) do
        entry.region:SetAlpha(entry.alpha)
    end
    wipe(hiddenBars)
end

local function CancelAdvanceTimer()
    if advanceTimer then
        advanceTimer:Cancel()
        advanceTimer = nil
    end
end

local function CancelWrongFlyTimer()
    if wrongFlyTimer then
        wrongFlyTimer:Cancel()
        wrongFlyTimer = nil
    end
end

local function ScheduleAdvance(delay)
    CancelAdvanceTimer()
    advanceTimer = C_Timer.NewTimer(delay, function()
        advanceTimer = nil
        if isRunning and waitingForNext and not quizFinished then
            waitingForNext = false
            KeybindQuiz:NextCard()
        end
    end)
end

-- Heap icon management

local function AcquireHeapIcon()
    local icon = tremove(heapPool)
    if icon then
        return icon
    end

    local frame = CreateFrame("Frame", nil, quizFrame)
    frame:SetSize(HEAP_ICON_SIZE, HEAP_ICON_SIZE)

    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetPoint("TOPLEFT", 3, -3)
    tex:SetPoint("BOTTOMRIGHT", -3, 3)
    tex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
    frame.icon = tex

    local border = frame:CreateTexture(nil, "OVERLAY")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    frame.border = border

    return frame
end

local function ReleaseHeapIcon(frame)
    frame:ClearAllPoints()
    frame:Hide()
    tinsert(heapPool, frame)
end

local function ClearHeapIcons(whichPile)
    local icons = activeHeapIcons[whichPile]
    for i = #icons, 1, -1 do
        ReleaseHeapIcon(icons[i])
        icons[i] = nil
    end
end

local function AddHeapIcon(texture, whichPile, anchorFrame)
    local frame = AcquireHeapIcon()
    frame:SetFrameLevel(quizFrame:GetFrameLevel() + 2 + #activeHeapIcons[whichPile])
    frame.icon:SetTexture(texture)

    -- Random scatter for natural pile look
    local offsetX = math.random(-HEAP_SCATTER, HEAP_SCATTER)
    local offsetY = math.random(-HEAP_SCATTER, HEAP_SCATTER)
    frame:SetPoint("CENTER", anchorFrame, "CENTER", offsetX, offsetY)

    if whichPile == "correct" then
        frame.border:SetVertexColor(0.3, 0.9, 0.3, 0.8)
    else
        frame.border:SetVertexColor(0.9, 0.3, 0.3, 0.8)
    end

    frame:Show()
    tinsert(activeHeapIcons[whichPile], frame)
end

local function CompletePendingFly()
    if pendingFly then
        if flyerFrame then
            flyerFrame:SetScript("OnUpdate", nil)
            flyerFrame:Hide()
        end
        AddHeapIcon(pendingFly.texture, pendingFly.whichPile, pendingFly.anchorFrame)
        pendingFly = nil
    end
end

-- Fly animation: card icon shrinks and moves to the target heap

local function FlyToHeap(texture, whichPile, anchorFrame, onFinish)
    if not flyerFrame then
        flyerFrame = CreateFrame("Frame", nil, quizFrame)
        flyerFrame:SetSize(ICON_SIZE, ICON_SIZE)
        flyerFrame:SetFrameLevel(quizFrame:GetFrameLevel() + 50)

        local tex = flyerFrame:CreateTexture(nil, "ARTWORK")
        tex:SetPoint("TOPLEFT", 3, -3)
        tex:SetPoint("BOTTOMRIGHT", -3, 3)
        tex:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
        flyerFrame.icon = tex

        local border = flyerFrame:CreateTexture(nil, "OVERLAY")
        border:SetPoint("TOPLEFT", -1, 1)
        border:SetPoint("BOTTOMRIGHT", 1, -1)
        border:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
        flyerFrame.border = border
    end

    CompletePendingFly()
    pendingFly = { texture = texture, whichPile = whichPile, anchorFrame = anchorFrame }

    flyerFrame.icon:SetTexture(texture)
    if whichPile == "correct" then
        flyerFrame.border:SetVertexColor(0.3, 0.9, 0.3, 1)
    else
        flyerFrame.border:SetVertexColor(0.9, 0.3, 0.3, 1)
    end

    -- Start at card position
    flyerFrame:ClearAllPoints()
    flyerFrame:SetPoint("CENTER", cardFrame, "CENTER")
    flyerFrame:SetSize(ICON_SIZE, ICON_SIZE)
    flyerFrame:Show()

    -- Animate via OnUpdate
    local startTime = GetTime()
    local startX, startY = cardFrame:GetCenter()
    local endX, endY = anchorFrame:GetCenter()

    flyerFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        local progress = mmin((now - startTime) / FLY_DURATION, 1.0)

        -- Ease-out (decelerate)
        local t = 1 - (1 - progress) * (1 - progress)

        local curX = startX + (endX - startX) * t
        local curY = startY + (endY - startY) * t
        local curSize = ICON_SIZE + (HEAP_ICON_SIZE - ICON_SIZE) * t

        self:ClearAllPoints()
        self:SetSize(curSize, curSize)
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", curX, curY)

        if progress >= 1.0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            pendingFly = nil
            AddHeapIcon(texture, whichPile, anchorFrame)
            if onFinish then onFinish() end
        end
    end)
end

-- Fly animation: heap icon grows and moves to the card position (reverse of FlyToHeap)

local function FlyFromHeap(texture, anchorFrame, onFinish)
    if not flyerFrame then return end

    flyerFrame.icon:SetTexture(texture)
    flyerFrame.border:SetVertexColor(0.9, 0.3, 0.3, 1)

    flyerFrame:ClearAllPoints()
    flyerFrame:SetPoint("CENTER", anchorFrame, "CENTER")
    flyerFrame:SetSize(HEAP_ICON_SIZE, HEAP_ICON_SIZE)
    flyerFrame:Show()

    local startTime = GetTime()
    local startX, startY = anchorFrame:GetCenter()
    local endX, endY = cardFrame:GetCenter()

    flyerFrame:SetScript("OnUpdate", function(self)
        local progress = mmin((GetTime() - startTime) / FLY_DURATION, 1.0)
        local t = 1 - (1 - progress) * (1 - progress)

        local curX = startX + (endX - startX) * t
        local curY = startY + (endY - startY) * t
        local curSize = HEAP_ICON_SIZE + (ICON_SIZE - HEAP_ICON_SIZE) * t

        self:ClearAllPoints()
        self:SetSize(curSize, curSize)
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", curX, curY)

        if progress >= 1.0 then
            self:SetScript("OnUpdate", nil)
            self:Hide()
            if onFinish then onFinish() end
        end
    end)
end

-- Glow effect on correct answer

local function FlashGlow()
    if not glowBorder then return end
    glowBorder:SetAlpha(0.8)
    glowBorder:Show()

    local startTime = GetTime()
    local duration = 0.4

    cardFrame:SetScript("OnUpdate", function(self, elapsed)
        local now = GetTime()
        local progress = (now - startTime) / duration
        if progress >= 1.0 then
            glowBorder:Hide()
            self:SetScript("OnUpdate", nil)
            return
        end
        -- Quick pulse up then fade out
        local alpha
        if progress < 0.3 then
            alpha = 0.8
        else
            alpha = 0.8 * (1 - (progress - 0.3) / 0.7)
        end
        glowBorder:SetAlpha(mmax(alpha, 0))
    end)
end

-- UI

local correctHeapAnchor, wrongHeapAnchor
local UpdateCounts

local function CreateQuizUI()
    -- Dimmer
    dimmer = CreateFrame("Frame", nil, UIParent)
    dimmer:SetAllPoints()
    dimmer:SetFrameStrata("FULLSCREEN")
    dimmer:SetFrameLevel(10)
    local dimTex = dimmer:CreateTexture(nil, "BACKGROUND")
    dimTex:SetAllPoints()
    dimTex:SetColorTexture(0, 0, 0, 0.5)
    dimmer:EnableMouse(false)
    dimmer:Hide()

    -- Container (no visuals, just for positioning)
    quizFrame = CreateFrame("Frame", "BoundToLearnQuizFrame", UIParent)
    quizFrame:SetSize(500, 300)
    quizFrame:SetPoint("CENTER", 0, 40)
    quizFrame:SetFrameStrata("FULLSCREEN")
    quizFrame:SetFrameLevel(15)
    quizFrame:EnableMouse(false)
    quizFrame:Hide()

    -- Title
    local title = ns.Theme.CreateTitle(quizFrame, "Keybind Quiz", 16)
    title:SetPoint("TOP", 0, 10)

    roundText = quizFrame:CreateFontString(nil, "OVERLAY")
    roundText:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    roundText:SetPoint("TOP", title, "BOTTOM", 0, -4)
    roundText:SetTextColor(0.55, 0.55, 0.55)

    progressText = quizFrame:CreateFontString(nil, "OVERLAY")
    progressText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    progressText:SetPoint("TOP", roundText, "BOTTOM", 0, -2)
    progressText:SetTextColor(0.8, 0.8, 0.8)

    -- Card icon (centered)
    cardFrame = CreateFrame("Frame", nil, quizFrame)
    cardFrame:SetSize(ICON_SIZE, ICON_SIZE)
    cardFrame:SetPoint("CENTER", 0, 10)

    cardIcon = cardFrame:CreateTexture(nil, "ARTWORK")
    cardIcon:SetPoint("TOPLEFT", 4, -4)
    cardIcon:SetPoint("BOTTOMRIGHT", -4, 4)
    cardIcon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)

    cardBorder = cardFrame:CreateTexture(nil, "OVERLAY")
    cardBorder:SetPoint("TOPLEFT", -2, 2)
    cardBorder:SetPoint("BOTTOMRIGHT", 2, -2)
    cardBorder:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    cardBorder:SetVertexColor(1, 1, 1, 0.9)

    -- Green glow (oversized border with additive blend)
    glowBorder = cardFrame:CreateTexture(nil, "ARTWORK", nil, -1)
    glowBorder:SetPoint("TOPLEFT", -10, 10)
    glowBorder:SetPoint("BOTTOMRIGHT", 10, -10)
    glowBorder:SetAtlas("UI-HUD-ActionBar-IconFrame-Mouseover")
    glowBorder:SetVertexColor(0.2, 1.0, 0.3, 0.8)
    glowBorder:SetBlendMode("ADD")
    glowBorder:Hide()

    -- Ability name (below card)
    cardName = quizFrame:CreateFontString(nil, "OVERLAY")
    cardName:SetFont("Fonts\\FRIZQT__.TTF", 21, "OUTLINE")
    cardName:SetPoint("TOP", cardFrame, "BOTTOM", 0, -10)
    cardName:SetWidth(280)
    cardName:SetTextColor(1, 1, 1)

    -- Prompt
    promptText = quizFrame:CreateFontString(nil, "OVERLAY")
    promptText:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    promptText:SetPoint("TOP", cardName, "BOTTOM", 0, -10)
    promptText:SetTextColor(0.7, 0.7, 0.7)

    -- Answer reveal
    answerLabel = quizFrame:CreateFontString(nil, "OVERLAY")
    answerLabel:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    answerLabel:SetPoint("TOP", promptText, "BOTTOM", 0, -6)
    answerLabel:SetTextColor(0.7, 0.7, 0.7)
    answerLabel:Hide()

    answerKeybind = quizFrame:CreateFontString(nil, "OVERLAY")
    answerKeybind:SetFont("Fonts\\FRIZQT__.TTF", 30, "OUTLINE")
    answerKeybind:SetPoint("TOP", answerLabel, "BOTTOM", 0, -4)
    answerKeybind:Hide()

    -- Heap anchors (invisible frames that heaps pile around)
    correctHeapAnchor = CreateFrame("Frame", nil, quizFrame)
    correctHeapAnchor:SetSize(HEAP_ICON_SIZE, HEAP_ICON_SIZE)
    correctHeapAnchor:SetPoint("CENTER", -HEAP_X_OFFSET, HEAP_Y_BASE)

    wrongHeapAnchor = CreateFrame("Frame", nil, quizFrame)
    wrongHeapAnchor:SetSize(HEAP_ICON_SIZE, HEAP_ICON_SIZE)
    wrongHeapAnchor:SetPoint("CENTER", HEAP_X_OFFSET, HEAP_Y_BASE)

    -- Heap labels
    correctHeapLabel = quizFrame:CreateFontString(nil, "OVERLAY")
    correctHeapLabel:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    correctHeapLabel:SetPoint("TOP", correctHeapAnchor, "BOTTOM", 0, -HEAP_ICON_SIZE - HEAP_SCATTER - 4)
    correctHeapLabel:SetTextColor(0.3, 0.8, 0.3)

    wrongHeapLabel = quizFrame:CreateFontString(nil, "OVERLAY")
    wrongHeapLabel:SetFont("Fonts\\FRIZQT__.TTF", 15, "OUTLINE")
    wrongHeapLabel:SetPoint("TOP", wrongHeapAnchor, "BOTTOM", 0, -HEAP_ICON_SIZE - HEAP_SCATTER - 4)
    wrongHeapLabel:SetTextColor(0.8, 0.3, 0.3)

    correctCountText = quizFrame:CreateFontString(nil, "OVERLAY")
    correctCountText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    correctCountText:SetPoint("TOP", correctHeapLabel, "BOTTOM", 0, -2)
    correctCountText:SetTextColor(0.3, 0.8, 0.3)

    wrongCountText = quizFrame:CreateFontString(nil, "OVERLAY")
    wrongCountText:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    wrongCountText:SetPoint("TOP", wrongHeapLabel, "BOTTOM", 0, -2)
    wrongCountText:SetTextColor(0.8, 0.3, 0.3)

    -- Timer
    timerText = quizFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
    timerText:SetPoint("TOPRIGHT", quizFrame, "TOPRIGHT", -10, 10)
    timerText:SetTextColor(0.6, 0.6, 0.6)

    -- ESC hint
    local escHint = quizFrame:CreateFontString(nil, "OVERLAY")
    escHint:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
    escHint:SetPoint("TOP", promptText, "BOTTOM", 0, -50)
    escHint:SetTextColor(0.4, 0.4, 0.4)
    escHint:SetText("ESC to exit")

    -- Ready screen (standalone frame above dimmer)
    local readyFrame = CreateFrame("Frame", nil, UIParent)
    readyFrame:SetSize(300, 188)
    readyFrame:SetPoint("CENTER", 0, 40)
    readyFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    readyFrame:SetFrameLevel(50)
    ns.Theme.StylePanel(readyFrame)
    readyFrame:Hide()
    ns.Utils.CloseOnEscape(readyFrame, function()
        readyFrame:Hide()
        dimmer:Hide()
    end)

    local readyTitle = ns.Theme.CreateTitle(readyFrame, "Keybind Quiz", 18)
    readyTitle:SetPoint("TOP", 0, -20)

    local readyDesc = readyFrame:CreateFontString(nil, "OVERLAY")
    readyDesc:SetFont("Fonts\\FRIZQT__.TTF", 13, "")
    readyDesc:SetPoint("TOP", readyTitle, "BOTTOM", 0, -12)
    readyDesc:SetWidth(260)
    readyDesc:SetTextColor(0.7, 0.7, 0.7)
    readyFrame.desc = readyDesc

    local barNote = readyFrame:CreateFontString(nil, "OVERLAY")
    barNote:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
    barNote:SetPoint("TOP", readyDesc, "BOTTOM", 0, -8)
    barNote:SetWidth(260)
    barNote:SetTextColor(0.95, 0.80, 0.35)
    barNote:SetText("Your action bars are hidden during the quiz.")

    local timedBtn = ns.Theme.CreateAccentButton(readyFrame, "Timed Run", 120, 28)
    timedBtn:SetPoint("BOTTOMRIGHT", readyFrame, "BOTTOM", -6, 36)

    local practiceBtn = ns.Theme.CreateButton(readyFrame, "Practice", 120, 28)
    practiceBtn:SetPoint("BOTTOMLEFT", readyFrame, "BOTTOM", 6, 36)

    local practiceHint = readyFrame:CreateFontString(nil, "OVERLAY")
    practiceHint:SetFont("Fonts\\FRIZQT__.TTF", 9, "")
    practiceHint:SetPoint("TOP", practiceBtn, "BOTTOM", 0, -2)
    practiceHint:SetTextColor(0.45, 0.45, 0.45)
    practiceHint:SetText("Not saved to stats")

    local readyHint = readyFrame:CreateFontString(nil, "OVERLAY")
    readyHint:SetFont("Fonts\\FRIZQT__.TTF", 10, "")
    readyHint:SetPoint("BOTTOM", 0, 6)
    readyHint:SetTextColor(0.4, 0.4, 0.4)
    readyHint:SetText("ESC to cancel")

    quizFrame.readyFrame = readyFrame
    quizFrame.timedBtn = timedBtn
    quizFrame.practiceBtn = practiceBtn

    -- Input capture frame
    inputFrame = CreateFrame("Frame", "BoundToLearnQuizInput", UIParent)
    inputFrame:SetAllPoints()
    inputFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    inputFrame:SetFrameLevel(100)
    inputFrame:EnableKeyboard(true)
    inputFrame:SetPropagateKeyboardInput(false)
    inputFrame:Hide()

    inputFrame:SetScript("OnKeyDown", function(_, key)
        if MODIFIER_KEYS[key] then
            inputFrame:SetPropagateKeyboardInput(true)
            return
        end
        inputFrame:SetPropagateKeyboardInput(false)

        if key == "ESCAPE" then
            C_Timer.After(0, function() KeybindQuiz:Stop() end)
            return
        end

        local fullKey = ""
        if IsAltKeyDown() then fullKey = fullKey .. "ALT-" end
        if IsControlKeyDown() then fullKey = fullKey .. "CTRL-" end
        if IsShiftKeyDown() then fullKey = fullKey .. "SHIFT-" end
        KeybindQuiz:PressKey(fullKey .. key)
    end)
end

-- One answer press, from the key reader or the mouse catch (mouse binds).
function KeybindQuiz:PressKey(fullKey)
    if not isRunning then return end
    if quizFinished then
        C_Timer.After(0, function() KeybindQuiz:Stop() end)
        return
    end

    if waitingForNext then
        CancelAdvanceTimer()
        CancelWrongFlyTimer()
        CompletePendingFly()
        if pendingWrongIcon then
            AddHeapIcon(pendingWrongIcon.texture, "wrong", pendingWrongIcon.anchorFrame)
            pendingWrongIcon = nil
            UpdateCounts()
        end
        waitingForNext = false
        KeybindQuiz:NextCard()
        return
    end

    KeybindQuiz:CheckAnswer(fullKey)
end

-- Logic

UpdateCounts = function()
    correctCountText:SetText(sformat("%d", #correctPile))
    wrongCountText:SetText(sformat("%d", #wrongPile))
    correctHeapLabel:SetShown(#correctPile > 0)
    wrongHeapLabel:SetShown(#wrongPile > 0)
end

local function RevealCard(card)
    cardFrame:Show()
    cardIcon:SetTexture(card.texture)
    cardIcon:SetAlpha(1)
    cardBorder:SetVertexColor(1, 1, 1, 0.9)
    cardBorder:SetAlpha(1)
    cardBorder:Show()
    glowBorder:Hide()
    cardFrame:SetScript("OnUpdate", nil)
    cardName:SetText(card.name)
    promptText:SetText("Press the correct keybind")
    promptText:SetTextColor(0.7, 0.7, 0.7)
    answerLabel:Hide()
    answerKeybind:Hide()
    progressText:SetText(sformat("%d / %d", currentIndex, #deck))
    progressText:SetTextColor(0.8, 0.8, 0.8)
    UpdateCounts()
end

local function ShowCurrentCard()
    if currentIndex < 1 or currentIndex > #deck then return end
    local card = deck[currentIndex]

    if isReviewRound and wrongHeapAnchor then
        -- Hide card content until fly animation finishes
        cardFrame:Show()
        cardIcon:SetAlpha(0)
        cardBorder:SetAlpha(0)
        cardName:SetText("")
        promptText:SetText("")
        answerLabel:Hide()
        answerKeybind:Hide()
        progressText:SetText(sformat("%d / %d", currentIndex, #deck))

        FlyFromHeap(card.texture, wrongHeapAnchor, function()
            if isRunning then
                RevealCard(card)
            end
        end)
    else
        RevealCard(card)
    end
end

function KeybindQuiz:CheckAnswer(pressedKey)
    if not isRunning or waitingForNext then return end
    if currentIndex < 1 or currentIndex > #deck then return end
    local card = deck[currentIndex]

    if pressedKey == card.keybind then
        tinsert(correctPile, card)
        FlashGlow()
        promptText:SetText("|cFF44DD44Correct!|r")
        answerLabel:Hide()
        answerKeybind:Hide()
        if BoundToLearn.db.game.soundEnabled then
            PlaySound(891)
        end
        waitingForNext = true
        -- Fly to correct heap, then advance
        cardIcon:SetAlpha(0)
        cardBorder:SetAlpha(0)
        FlyToHeap(card.texture, "correct", correctHeapAnchor, function()
            UpdateCounts()
        end)
        ScheduleAdvance(0.5)
    else
        tinsert(wrongPile, card)
        totalWrongAnswers = totalWrongAnswers + 1
        cardBorder:SetVertexColor(0.9, 0.2, 0.2, 1)
        promptText:SetText("|cFFDD4444Not quite|r")
        answerLabel:SetText("Correct keybind:")
        answerLabel:Show()
        answerKeybind:SetText("|cFFFFCC00" .. FormatKeybind(card.keybind) .. "|r")
        answerKeybind:Show()
        if BoundToLearn.db.game.soundEnabled then
            PlaySound(846)
        end
        waitingForNext = true
        -- Fly to wrong heap after a pause to absorb the correct answer
        CancelWrongFlyTimer()
        pendingWrongIcon = { texture = card.texture, anchorFrame = wrongHeapAnchor }
        wrongFlyTimer = C_Timer.NewTimer(2.0, function()
            wrongFlyTimer = nil
            pendingWrongIcon = nil
            if isRunning then
                cardIcon:SetAlpha(0)
                cardBorder:SetAlpha(0)
                FlyToHeap(card.texture, "wrong", wrongHeapAnchor, function()
                    UpdateCounts()
                end)
            end
        end)
        ScheduleAdvance(3.0)
    end
    UpdateCounts()
end

function KeybindQuiz:NextCard()
    if not isRunning then return end
    -- Restore card visibility for next card
    cardIcon:SetAlpha(1)
    cardBorder:SetAlpha(1)
    currentIndex = currentIndex + 1
    if currentIndex > #deck then
        self:FinishRound()
        return
    end
    ShowCurrentCard()
end

function KeybindQuiz:FinishRound()
    if #wrongPile == 0 then
        quizFinished = true
        cardIcon:SetTexture(nil)
        cardIcon:SetAlpha(1)
        cardBorder:Hide()
        glowBorder:Hide()
        cardFrame:SetScript("OnUpdate", nil)
        local total = #correctPile

        local elapsed = GetTime() - quizStartTime
        quizFrame:SetScript("OnUpdate", nil)
        local mins = mfloor(elapsed / 60)
        local secs = mfloor(elapsed % 60)
        local tenths = mfloor((elapsed * 10) % 10)
        local timeStr
        if mins > 0 then
            timeStr = sformat("%d:%02d.%d", mins, secs, tenths)
        else
            timeStr = sformat("%d.%ds", secs, tenths)
        end
        timerText:SetText(timeStr)

        cardName:SetText("|cFF44DD44Quiz Complete!|r")
        if roundNumber == 1 then
            promptText:SetText(sformat("Perfect: all %d correct on the first try (%s)", total, timeStr))
        else
            promptText:SetText(sformat("All %d abilities learned in %d rounds (%s)", total, roundNumber, timeStr))
        end
        promptText:SetTextColor(0.7, 0.7, 0.7)
        answerLabel:Hide()
        answerKeybind:Hide()
        progressText:SetText("Press any key to close")
        progressText:SetTextColor(0.5, 0.5, 0.5)

        if not isPractice and ns.Stats then
            ns.Stats:RecordQuizSession({
                totalAbilities = total,
                rounds = roundNumber,
                elapsed = elapsed,
                wrongAnswers = totalWrongAnswers,
            })
        end

        if BoundToLearn.db.game.soundEnabled then
            PlaySound(888)
        end
    else
        roundNumber = roundNumber + 1
        isReviewRound = true
        local reviewCount = #wrongPile

        CancelWrongFlyTimer()
        CompletePendingFly()
        pendingWrongIcon = nil

        wipe(deck)
        for _, card in ipairs(wrongPile) do
            tinsert(deck, card)
        end
        wipe(wrongPile)
        ClearHeapIcons("wrong")
        Shuffle(deck)
        currentIndex = 0

        cardIcon:SetTexture(nil)
        cardIcon:SetAlpha(1)
        cardBorder:SetAlpha(1)
        cardBorder:SetVertexColor(0.8, 0.6, 0.2, 0.6)
        glowBorder:Hide()
        cardFrame:SetScript("OnUpdate", nil)
        cardName:SetText("")
        promptText:SetText(sformat("|cFFFFCC00Reviewing %d to practice...|r", reviewCount))
        promptText:SetTextColor(0.7, 0.7, 0.7)
        answerLabel:Hide()
        answerKeybind:Hide()
        roundText:SetText(sformat("Round %d", roundNumber))
        progressText:SetText("")
        UpdateCounts()

        waitingForNext = true
        ScheduleAdvance(1.5)
    end
end

function KeybindQuiz:Start()
    if InCombatLockdown() then
        BoundToLearn:Print("Cannot start quiz during combat.")
        return
    end
    if isRunning then return end
    if quizFrame and (quizFrame:IsShown() or quizFrame.readyFrame:IsShown()) then return end

    local gameInput = _G["BoundToLearnGameInput"]
    if gameInput and gameInput:IsShown() then
        BoundToLearn:Print("Stop the game first before starting the quiz.")
        return
    end

    DiscoverCards()
    if #allCards == 0 then
        BoundToLearn:Print("No quizzable abilities found. Check your action bars and keybinds.")
        return
    end

    if not quizFrame then CreateQuizUI() end

    local readyFrame = quizFrame.readyFrame
    readyFrame.desc:SetText(sformat("Quizzing %d abilities from your action bars.", #allCards))

    local function StartQuiz(practice)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        isPractice = practice
        readyFrame:Hide()
        KeybindQuiz:BeginRound()
    end

    quizFrame.timedBtn:SetScript("OnClick", function() StartQuiz(false) end)
    quizFrame.practiceBtn:SetScript("OnClick", function() StartQuiz(true) end)
    quizFrame.timedBtn:Show()
    quizFrame.practiceBtn:Show()

    dimmer:Show()
    readyFrame:Show()
end

function KeybindQuiz:BeginRound()
    wipe(deck)
    wipe(correctPile)
    wipe(wrongPile)
    ClearHeapIcons("correct")
    ClearHeapIcons("wrong")

    for _, card in ipairs(allCards) do
        tinsert(deck, card)
    end
    Shuffle(deck)
    currentIndex = 0
    roundNumber = 1
    waitingForNext = false
    quizFinished = false
    isReviewRound = false
    totalWrongAnswers = 0
    isRunning = true
    quizStartTime = GetTime()

    quizFrame:Show()
    quizFrame:SetScript("OnUpdate", function()
        if not isRunning then return end
        local elapsed = GetTime() - quizStartTime
        local mins = mfloor(elapsed / 60)
        local secs = mfloor(elapsed % 60)
        timerText:SetText(sformat("%d:%02d", mins, secs))
    end)

    -- The action bars are hidden during the quiz, so end it if combat starts: the
    -- player needs their bars back to fight.
    quizFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
    quizFrame:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_DISABLED" and isRunning then
            BoundToLearn:Print("Combat started, ending the quiz.")
            KeybindQuiz:Stop()
        end
    end)
    cardFrame:Show()
    roundText:SetText("Round 1")
    progressText:SetTextColor(0.8, 0.8, 0.8)
    correctHeapLabel:SetText("Correct")
    wrongHeapLabel:SetText("Wrong")
    correctHeapLabel:Hide()
    wrongHeapLabel:Hide()
    correctCountText:SetText("0")
    wrongCountText:SetText("0")
    UpdateCounts()

    HideActionBars()
    inputFrame:Show()
    -- Mouse-bound answers come through the catch; their spells do not fire.
    local mouseKeys = {}
    for _, bar in ipairs(BAR_MAPPINGS) do
        for i = 1, 12 do
            for _, key in ipairs({ GetBindingKey(bar.bindPrefix .. i) }) do
                if ns.Utils.IsMouseBind(key) then mouseKeys[#mouseKeys + 1] = key end
            end
        end
    end
    ns.Utils.CatchMouseBinds(mouseKeys, function(key) KeybindQuiz:PressKey(key) end)

    self:NextCard()
end

function KeybindQuiz:Stop()
    local wasRunning = isRunning
    isRunning = false
    waitingForNext = false
    quizFinished = false
    if wasRunning then
        CancelAdvanceTimer()
        CancelWrongFlyTimer()
        RestoreActionBars()
        ns.Utils.ReleaseMouseBinds()
    end
    pendingFly = nil
    pendingWrongIcon = nil
    ClearHeapIcons("correct")
    ClearHeapIcons("wrong")
    if flyerFrame then
        flyerFrame:SetScript("OnUpdate", nil)
        flyerFrame:Hide()
    end
    if cardFrame then
        cardFrame:SetScript("OnUpdate", nil)
        cardIcon:SetAlpha(1)
        cardBorder:SetAlpha(1)
    end
    if quizFrame then
        quizFrame:SetScript("OnUpdate", nil)
        quizFrame:UnregisterEvent("PLAYER_REGEN_DISABLED")
        quizFrame:SetScript("OnEvent", nil)
        quizFrame.readyFrame:Hide()
        quizFrame:Hide()
    end
    if dimmer then dimmer:Hide() end
    if inputFrame then inputFrame:Hide() end
end

function KeybindQuiz:Toggle()
    if isRunning then
        self:Stop()
    else
        self:Start()
    end
end
