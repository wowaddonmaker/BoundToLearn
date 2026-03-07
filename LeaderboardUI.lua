local ADDON_NAME, ns = ...

local LeaderboardUI = {}
ns.LeaderboardUI = LeaderboardUI

local Utils   = ns.Utils
local sformat = Utils.sformat
local mfloor  = Utils.mfloor
local ipairs  = Utils.ipairs
local pairs   = Utils.pairs
local tinsert = Utils.tinsert
local CreateFrame = Utils.CreateFrame
local PlayUISound = Utils.PlayUISound
local SOUND_TAB   = Utils.SOUND_TAB
local SOUND_CLICK = Utils.SOUND_CLICK

local DIFFICULTIES = { "Easy", "Medium", "Hard", "Extreme" }
local MAX_ROWS = 15
local ROW_HEIGHT = 18

local CLASS_COLORS = {
    WARRIOR     = { 0.78, 0.61, 0.43 },
    PALADIN     = { 0.96, 0.55, 0.73 },
    HUNTER      = { 0.67, 0.83, 0.45 },
    ROGUE       = { 1.00, 0.96, 0.41 },
    PRIEST      = { 1.00, 1.00, 1.00 },
    DEATHKNIGHT = { 0.77, 0.12, 0.23 },
    SHAMAN      = { 0.00, 0.44, 0.87 },
    MAGE        = { 0.25, 0.78, 0.92 },
    WARLOCK     = { 0.53, 0.53, 0.93 },
    MONK        = { 0.00, 1.00, 0.60 },
    DRUID       = { 1.00, 0.49, 0.04 },
    DEMONHUNTER = { 0.64, 0.19, 0.79 },
    EVOKER      = { 0.20, 0.58, 0.50 },
}

local mainFrame, tabButtons, guildPanel, partyPanel
local guildRows = {}
local partyRows = {}
local currentDifficulty = "Medium"
local currentTab = "guild"
local isInitialized = false

function LeaderboardUI:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function LeaderboardUI:Toggle()
    if not mainFrame then
        self:CreateMainFrame()
    end
    if mainFrame:IsShown() then
        mainFrame:Hide()
    else
        self:Refresh()
        mainFrame:Show()
    end
end

function LeaderboardUI:Show()
    if not mainFrame then
        self:CreateMainFrame()
    end
    self:Refresh()
    mainFrame:Show()
end

function LeaderboardUI:Hide()
    if mainFrame then mainFrame:Hide() end
end

function LeaderboardUI:CreateMainFrame()
    mainFrame = CreateFrame("Frame", "BoundToLearnLeaderboard", UIParent, "BackdropTemplate")
    mainFrame:SetSize(380, 440)
    mainFrame:SetPoint("CENTER")
    mainFrame:SetFrameStrata("DIALOG")
    mainFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    mainFrame:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
    mainFrame:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    mainFrame:EnableMouse(true)
    mainFrame:SetMovable(true)
    mainFrame:SetClampedToScreen(true)
    mainFrame:Hide()

    mainFrame:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then self:StartMoving() end
    end)
    mainFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

    -- Accent line
    local accent = mainFrame:CreateTexture(nil, "ARTWORK")
    accent:SetPoint("TOPLEFT", 6, -5)
    accent:SetPoint("TOPRIGHT", -6, -5)
    accent:SetHeight(2)
    accent:SetColorTexture(0.33, 0.8, 1, 0.7)

    -- Close button
    local close = CreateFrame("Button", nil, mainFrame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    -- Title
    local title = mainFrame:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", 0, -12)
    title:SetText("|cFF55CCFFLeaderboard|r")

    -- Tab buttons: Guild / Party
    local tabY = -34
    tabButtons = {}
    local tabNames = { "Guild", "Party" }
    for i, name in ipairs(tabNames) do
        local btn = CreateFrame("Button", nil, mainFrame)
        btn:SetSize(80, 22)
        btn:SetPoint("TOPLEFT", 10 + (i - 1) * 85, tabY)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(name)
        btn.tabName = name:lower()

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
        btn.bg = bg

        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_TAB)
            currentTab = btn.tabName
            LeaderboardUI:UpdateTabs()
            LeaderboardUI:Refresh()
        end)

        tabButtons[i] = btn
    end

    -- Difficulty buttons (for guild tab)
    local diffRow = CreateFrame("Frame", nil, mainFrame)
    diffRow:SetSize(360, 20)
    diffRow:SetPoint("TOP", 0, tabY - 26)
    mainFrame.diffRow = diffRow

    mainFrame.diffBtns = {}
    for i, name in ipairs(DIFFICULTIES) do
        local btn = CreateFrame("Button", nil, diffRow)
        btn:SetSize(53, 18)
        btn:SetPoint("LEFT", 30 + (i - 1) * 75, 0)
        btn:SetNormalFontObject("GameFontNormalSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(name)
        btn.diffName = name

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
        btn.bg = bg

        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            currentDifficulty = name
            LeaderboardUI:UpdateDiffButtons()
            LeaderboardUI:Refresh()
        end)

        mainFrame.diffBtns[i] = btn
    end

    -- Guild panel
    guildPanel = CreateFrame("Frame", nil, mainFrame)
    guildPanel:SetPoint("TOPLEFT", 10, tabY - 52)
    guildPanel:SetPoint("BOTTOMRIGHT", -10, 40)

    -- Column headers
    local headerY = 0
    local headers = {
        { text = "#", x = 0, w = 20 },
        { text = "Player", x = 24, w = 140 },
        { text = "Score", x = 170, w = 70 },
        { text = "Combo", x = 240, w = 50 },
        { text = "Acc", x = 295, w = 40 },
    }
    for _, h in ipairs(headers) do
        local ht = guildPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("TOPLEFT", h.x, headerY)
        ht:SetText(h.text)
        ht:SetTextColor(0.55, 0.55, 0.55)
    end

    local divider = guildPanel:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 0, headerY - 14)
    divider:SetPoint("TOPRIGHT", 0, headerY - 14)
    divider:SetHeight(1)
    divider:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    -- Rows
    for i = 1, MAX_ROWS do
        local y = headerY - 16 - (i - 1) * ROW_HEIGHT
        local row = {}

        row.rank = guildPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.rank:SetPoint("TOPLEFT", 0, y)
        row.rank:SetWidth(20)
        row.rank:SetJustifyH("CENTER")

        row.name = guildPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", 24, y)
        row.name:SetWidth(140)
        row.name:SetJustifyH("LEFT")

        row.score = guildPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.score:SetPoint("TOPLEFT", 170, y)
        row.score:SetWidth(70)
        row.score:SetJustifyH("RIGHT")

        row.combo = guildPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.combo:SetPoint("TOPLEFT", 240, y)
        row.combo:SetWidth(50)
        row.combo:SetJustifyH("RIGHT")

        row.acc = guildPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.acc:SetPoint("TOPLEFT", 295, y)
        row.acc:SetWidth(40)
        row.acc:SetJustifyH("RIGHT")

        guildRows[i] = row
    end

    -- Party panel
    partyPanel = CreateFrame("Frame", nil, mainFrame)
    partyPanel:SetPoint("TOPLEFT", 10, tabY - 52)
    partyPanel:SetPoint("BOTTOMRIGHT", -10, 40)
    partyPanel:Hide()

    local partyNote = partyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyNote:SetPoint("TOP", 0, 0)
    partyNote:SetText("Recent scores from party/raid members")
    partyNote:SetTextColor(0.55, 0.55, 0.55)
    partyPanel.note = partyNote

    -- Party column headers
    local pHeaders = {
        { text = "Player", x = 0, w = 140 },
        { text = "Difficulty", x = 145, w = 70 },
        { text = "Score", x = 220, w = 60 },
        { text = "Combo", x = 280, w = 50 },
    }
    for _, h in ipairs(pHeaders) do
        local ht = partyPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("TOPLEFT", h.x, -20)
        ht:SetText(h.text)
        ht:SetTextColor(0.55, 0.55, 0.55)
    end

    local pdiv = partyPanel:CreateTexture(nil, "ARTWORK")
    pdiv:SetPoint("TOPLEFT", 0, -34)
    pdiv:SetPoint("TOPRIGHT", 0, -34)
    pdiv:SetHeight(1)
    pdiv:SetColorTexture(0.3, 0.3, 0.3, 0.5)

    for i = 1, 10 do
        local y = -36 - (i - 1) * ROW_HEIGHT
        local row = {}

        row.name = partyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.name:SetPoint("TOPLEFT", 0, y)
        row.name:SetWidth(140)
        row.name:SetJustifyH("LEFT")

        row.diff = partyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.diff:SetPoint("TOPLEFT", 145, y)
        row.diff:SetWidth(70)
        row.diff:SetJustifyH("LEFT")

        row.score = partyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.score:SetPoint("TOPLEFT", 220, y)
        row.score:SetWidth(60)
        row.score:SetJustifyH("RIGHT")

        row.combo = partyPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.combo:SetPoint("TOPLEFT", 280, y)
        row.combo:SetWidth(50)
        row.combo:SetJustifyH("RIGHT")

        partyRows[i] = row
    end

    -- Challenge button
    local challengeBtn = CreateFrame("Button", nil, mainFrame, "UIPanelButtonTemplate")
    challengeBtn:SetSize(140, 24)
    challengeBtn:SetPoint("BOTTOM", 0, 10)
    challengeBtn:SetText("Challenge Party")
    challengeBtn:SetScript("OnClick", function()
        if not IsInGroup() then
            BoundToLearn:Print("You need to be in a group to challenge someone.")
            return
        end
        -- Challenge all party members
        if ns.Leaderboard then
            ns.Leaderboard:SendChallenge("party")
        end
    end)
    challengeBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Challenge")
        GameTooltip:AddLine("Challenge your party to a round. Both sides play the same difficulty and compare scores.", 1, 1, 1, true)
        GameTooltip:Show()
    end)
    challengeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
    mainFrame.challengeBtn = challengeBtn

    self:UpdateTabs()
    self:UpdateDiffButtons()
end

function LeaderboardUI:UpdateTabs()
    if not tabButtons then return end
    for _, btn in ipairs(tabButtons) do
        if btn.tabName == currentTab then
            btn.bg:SetColorTexture(0.33, 0.8, 1, 0.3)
            btn:GetFontString():SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
    end

    if guildPanel then guildPanel:SetShown(currentTab == "guild") end
    if partyPanel then partyPanel:SetShown(currentTab == "party") end
    if mainFrame and mainFrame.diffRow then
        mainFrame.diffRow:SetShown(currentTab == "guild")
    end
    if mainFrame and mainFrame.challengeBtn then
        mainFrame.challengeBtn:SetShown(currentTab == "party")
    end
end

function LeaderboardUI:UpdateDiffButtons()
    if not mainFrame or not mainFrame.diffBtns then return end
    for _, btn in ipairs(mainFrame.diffBtns) do
        if btn.diffName == currentDifficulty then
            btn.bg:SetColorTexture(0.33, 0.8, 1, 0.3)
            btn:GetFontString():SetTextColor(1, 1, 1)
        else
            btn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.6)
            btn:GetFontString():SetTextColor(0.5, 0.5, 0.5)
        end
    end
end

function LeaderboardUI:Refresh()
    if not mainFrame or not mainFrame:IsShown() then return end

    if currentTab == "guild" then
        self:RefreshGuild()
    else
        self:RefreshParty()
    end
end

function LeaderboardUI:RefreshGuild()
    local board = ns.Leaderboard and ns.Leaderboard:GetLeaderboard(currentDifficulty) or {}

    for i = 1, MAX_ROWS do
        local row = guildRows[i]
        local entry = board[i]

        if entry then
            -- Rank
            if i <= 3 then
                local colors = { {1, 0.84, 0}, {0.75, 0.75, 0.75}, {0.8, 0.5, 0.2} }
                local c = colors[i]
                row.rank:SetText(sformat("|cFF%02x%02x%02x%d|r", c[1]*255, c[2]*255, c[3]*255, i))
            else
                row.rank:SetText(tostring(i))
                row.rank:SetTextColor(0.6, 0.6, 0.6)
            end

            -- Name with class color
            local cc = CLASS_COLORS[entry.class] or {0.7, 0.7, 0.7}
            row.name:SetText(sformat("|cFF%02x%02x%02x%s|r", cc[1]*255, cc[2]*255, cc[3]*255, entry.name))

            row.score:SetText(sformat("%d", entry.score))
            row.score:SetTextColor(1, 0.84, 0)

            row.combo:SetText(sformat("%d", entry.combo or 0))
            row.combo:SetTextColor(0.8, 0.8, 0.8)

            row.acc:SetText(sformat("%d%%", entry.accuracy or 0))
            row.acc:SetTextColor(0.6, 0.9, 0.6)

            row.rank:Show()
            row.name:Show()
            row.score:Show()
            row.combo:Show()
            row.acc:Show()
        else
            row.rank:Hide()
            row.name:Hide()
            row.score:Hide()
            row.combo:Hide()
            row.acc:Hide()
        end
    end
end

function LeaderboardUI:RefreshParty()
    local scores = ns.Leaderboard and ns.Leaderboard:GetPartyScores() or {}

    -- Sort by score desc
    local sorted = {}
    for name, data in pairs(scores) do
        data.name = name
        tinsert(sorted, data)
    end
    table.sort(sorted, function(a, b) return a.score > b.score end)

    for i = 1, 10 do
        local row = partyRows[i]
        local entry = sorted[i]

        if entry then
            local cc = CLASS_COLORS[entry.class] or {0.7, 0.7, 0.7}
            row.name:SetText(sformat("|cFF%02x%02x%02x%s|r", cc[1]*255, cc[2]*255, cc[3]*255, entry.name))
            row.diff:SetText(entry.difficulty or "?")
            row.diff:SetTextColor(0.7, 0.7, 0.7)
            row.score:SetText(sformat("%d", entry.score))
            row.score:SetTextColor(1, 0.84, 0)
            row.combo:SetText(sformat("%d", entry.combo or 0))
            row.combo:SetTextColor(0.8, 0.8, 0.8)

            row.name:Show()
            row.diff:Show()
            row.score:Show()
            row.combo:Show()
        else
            row.name:Hide()
            row.diff:Hide()
            row.score:Hide()
            row.combo:Hide()
        end
    end

    if #sorted == 0 then
        partyPanel.note:SetText("No party scores yet. Play a round while in a group.")
    else
        partyPanel.note:SetText("Recent scores from party/raid members")
    end
end
