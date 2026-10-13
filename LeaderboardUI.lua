local ADDON_NAME, ns = ...

local LeaderboardUI = {}
ns.LeaderboardUI = LeaderboardUI

local Utils   = ns.Utils
local sformat = Utils.sformat
local ipairs  = Utils.ipairs
local pairs   = Utils.pairs
local tinsert = Utils.tinsert
local CreateFrame = Utils.CreateFrame
local PlayUISound = Utils.PlayUISound
local SOUND_CLICK = Utils.SOUND_CLICK

local DIFFICULTIES = { "Easy", "Medium", "Hard", "Extreme" }
local DIFF_COLORS = {
    Easy    = { 0.30, 0.85, 0.30 },
    Medium  = { 1.00, 0.82, 0.00 },
    Hard    = { 1.00, 0.50, 0.10 },
    Extreme = { 0.90, 0.15, 0.15 },
}
local GUILD_MAX_ROWS = 15
local PARTY_MAX_ROWS = 13
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

-- Guild column layout
local GUILD_COLS = {
    { key = "rank",  x = 0,   w = 22,  header = "#",      justify = "CENTER" },
    { key = "name",  x = 24,  w = 105, header = "Player",  justify = "LEFT" },
    { key = "score", x = 131, w = 50,  header = "Score",   justify = "LEFT" },
    { key = "combo", x = 183, w = 40,  header = "Combo",   justify = "LEFT" },
    { key = "acc",   x = 225, w = 35,  header = "Acc",     justify = "LEFT" },
}

-- Party column layout
local PARTY_COLS = {
    { key = "name",  x = 0,   w = 105, header = "Player",  justify = "LEFT" },
    { key = "score", x = 107, w = 50,  header = "Score",   justify = "LEFT" },
    { key = "combo", x = 159, w = 45,  header = "Combo",   justify = "LEFT" },
    { key = "acc",   x = 206, w = 50,  header = "Acc",     justify = "LEFT" },
}

local leaderboardPanel
local tabButtons
local guildPage, partyPage
local guildRows = {}
local partyRows = {}
local confirmDialog
local currentDifficulty = "Medium"
local currentTab = "guild"
local isInitialized = false

function LeaderboardUI:Initialize()
    if isInitialized then return end
    isInitialized = true
end

function LeaderboardUI:Toggle()
    if leaderboardPanel and leaderboardPanel:IsShown() then
        leaderboardPanel:Hide()
        return
    end
    if not leaderboardPanel then
        self:CreatePanel()
    end
    self:Refresh()
    leaderboardPanel:Show()
end

function LeaderboardUI:Show()
    if not leaderboardPanel then
        self:CreatePanel()
    end
    self:Refresh()
    leaderboardPanel:Show()
end

function LeaderboardUI:Hide()
    if leaderboardPanel then leaderboardPanel:Hide() end
end

local function CreateColumnDividers(parent, cols, topY, bottomY)
    for i = 2, #cols do
        local divX = cols[i].x - 2
        local vline = parent:CreateTexture(nil, "ARTWORK")
        -- Anchor both ends to the parent TOPLEFT so topY/bottomY read as
        -- top-relative offsets. Anchoring the bottom to "BOTTOMLEFT" (the
        -- SetPoint default relativePoint) measured bottomY up from the page
        -- bottom, driving the line hundreds of pixels below the panel edge.
        vline:SetPoint("TOPLEFT", parent, "TOPLEFT", divX, topY)
        vline:SetPoint("BOTTOMLEFT", parent, "TOPLEFT", divX, bottomY)
        vline:SetWidth(1)
        vline:SetColorTexture(ns.Theme.RGB(ns.Theme.C.BORDER, 0.35))
    end
end

local function CreateRowBG(parent, y)
    local bg = parent:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 0, y)
    bg:SetPoint("RIGHT")
    bg:SetHeight(ROW_HEIGHT)
    return bg
end

function LeaderboardUI:CreatePanel()
    local scoreFrame = ns.GameUI and ns.GameUI:GetScoreFrame()
    if not scoreFrame then return end

    local panel = CreateFrame("Frame", "BoundToLearnLeaderboard", scoreFrame)
    panel:SetSize(280, 380)
    panel:SetPoint("TOPRIGHT", scoreFrame, "TOPLEFT", -14, 0)
    panel:SetFrameStrata(scoreFrame:GetFrameStrata())
    panel:SetFrameLevel(scoreFrame:GetFrameLevel() + 1)
    ns.Theme.StylePanel(panel)
    panel:EnableMouse(true)
    panel:Hide()

    -- Tab buttons: Guild / Party (underline style)
    tabButtons = {}
    local tabDefs = {
        { label = "Guild", key = "guild" },
        { label = "Party", key = "party" },
    }
    for i, def in ipairs(tabDefs) do
        local tab = ns.Theme.CreateTab(panel, def.label, "GameFontNormalSmall")
        tab:SetSize(120, 18)
        tab:SetPoint("TOPLEFT", 8 + (i - 1) * 124, -8)
        tab.tabKey = def.key

        tab:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            currentTab = def.key
            LeaderboardUI:UpdateTabs()
            LeaderboardUI:Refresh()
        end)

        tabButtons[i] = tab
    end

    -- Difficulty sub-tabs (on panel, shared by both pages)
    panel.diffBtns = {}
    for i, name in ipairs(DIFFICULTIES) do
        local btn = CreateFrame("Button", nil, panel)
        btn:SetSize(55, 16)
        btn:SetPoint("TOPLEFT", 16 + (i - 1) * 58, -30)
        btn:SetNormalFontObject("GameFontDisableSmall")
        btn:SetHighlightFontObject("GameFontHighlightSmall")
        btn:SetText(name)
        btn.diffName = name

        btn:SetScript("OnClick", function()
            PlayUISound(SOUND_CLICK)
            currentDifficulty = name
            LeaderboardUI:UpdateDiffButtons()
            LeaderboardUI:Refresh()
        end)

        panel.diffBtns[i] = btn
    end

    -- Content area starts below tabs + difficulty row
    local contentY = -50

    -- Guild page
    guildPage = CreateFrame("Frame", nil, panel)
    guildPage:SetPoint("TOPLEFT", 8, contentY)
    guildPage:SetPoint("BOTTOMRIGHT", -8, 30)
    panel.guildPage = guildPage

    for _, col in ipairs(GUILD_COLS) do
        local ht = guildPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("TOPLEFT", col.x, 0)
        ht:SetWidth(col.w)
        ht:SetJustifyH(col.justify)
        ht:SetText(col.header)
        ht:SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_DIM))
    end

    local divider = guildPage:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", 0, -14)
    divider:SetPoint("TOPRIGHT", 0, -14)
    divider:SetHeight(1)
    divider:SetColorTexture(ns.Theme.RGB(ns.Theme.C.BORDER, 0.5))

    -- Column separators run from the header rule down to the last data row,
    -- both offsets measured down from the page top so they stay inside it.
    CreateColumnDividers(guildPage, GUILD_COLS, -14, -14 - GUILD_MAX_ROWS * ROW_HEIGHT)

    for i = 1, GUILD_MAX_ROWS do
        local y = -16 - (i - 1) * ROW_HEIGHT
        local row = {}

        row.bg = CreateRowBG(guildPage, y)
        if i % 2 == 0 then
            row.bg:SetColorTexture(ns.Theme.RGB(ns.Theme.C.SECTION_FILL, 0.4))
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        for _, col in ipairs(GUILD_COLS) do
            local fs = guildPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", col.x, y)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.justify)
            row[col.key] = fs
        end

        guildRows[i] = row
    end

    -- Party page
    partyPage = CreateFrame("Frame", nil, panel)
    partyPage:SetPoint("TOPLEFT", 8, contentY)
    partyPage:SetPoint("BOTTOMRIGHT", -8, 30)
    partyPage:Hide()
    panel.partyPage = partyPage

    local partyNote = partyPage:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    partyNote:SetPoint("TOPLEFT", 0, 0)
    partyNote:SetPoint("RIGHT")
    partyNote:SetJustifyH("CENTER")
    partyNote:SetWordWrap(true)
    partyNote:SetText("Recent scores from party/raid members")
    partyNote:SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_DIM))
    panel.partyNote = partyNote

    for _, col in ipairs(PARTY_COLS) do
        local ht = partyPage:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        ht:SetPoint("TOPLEFT", col.x, -20)
        ht:SetWidth(col.w)
        ht:SetJustifyH(col.justify)
        ht:SetText(col.header)
        ht:SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_DIM))
    end

    local pdiv = partyPage:CreateTexture(nil, "ARTWORK")
    pdiv:SetPoint("TOPLEFT", 0, -34)
    pdiv:SetPoint("TOPRIGHT", 0, -34)
    pdiv:SetHeight(1)
    pdiv:SetColorTexture(ns.Theme.RGB(ns.Theme.C.BORDER, 0.5))

    CreateColumnDividers(partyPage, PARTY_COLS, -34, -34 - PARTY_MAX_ROWS * ROW_HEIGHT)

    for i = 1, PARTY_MAX_ROWS do
        local y = -36 - (i - 1) * ROW_HEIGHT
        local row = {}

        row.bg = CreateRowBG(partyPage, y)
        if i % 2 == 0 then
            row.bg:SetColorTexture(ns.Theme.RGB(ns.Theme.C.SECTION_FILL, 0.4))
        else
            row.bg:SetColorTexture(0, 0, 0, 0)
        end

        for _, col in ipairs(PARTY_COLS) do
            local fs = partyPage:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetPoint("TOPLEFT", col.x, y)
            fs:SetWidth(col.w)
            fs:SetJustifyH(col.justify)
            row[col.key] = fs
        end

        partyRows[i] = row
    end

    -- Bottom buttons
    local challengeBtn = ns.Theme.CreateAccentButton(partyPage, "Challenge Party", 120, 22)
    challengeBtn:SetPoint("BOTTOMLEFT", 0, -24)
    challengeBtn:SetScript("OnClick", function()
        if not IsInGroup() then
            BoundToLearn:Print("You need to be in a group to challenge someone.")
            return
        end
        if ns.Leaderboard then
            ns.Leaderboard:SendChallenge("party")
        end
    end)
    ns.Theme.DelayedTooltip(challengeBtn, function(self)
        GameTooltip:SetText("Challenge")
        GameTooltip:AddLine("Challenge your party to a round. Both sides play the same difficulty and compare scores.", 1, 1, 1, true)
    end)
    panel.challengeBtn = challengeBtn

    local resetBtn = ns.Theme.CreateButton(panel, "Reset", 70, 22)
    resetBtn:SetPoint("BOTTOMRIGHT", -8, 6)
    resetBtn:SetScript("OnClick", function()
        LeaderboardUI:ShowResetConfirm()
    end)
    ns.Theme.DelayedTooltip(resetBtn, function(self)
        GameTooltip:SetText("Reset Leaderboard")
        GameTooltip:AddLine("Clear all leaderboard data. This cannot be undone.", 1, 0.5, 0.5, true)
    end)
    panel.resetBtn = resetBtn

    leaderboardPanel = panel
    self:UpdateTabs()
    self:UpdateDiffButtons()
end

function LeaderboardUI:ShowResetConfirm()
    if confirmDialog then
        confirmDialog:Show()
        return
    end

    local dialog = CreateFrame("Frame", nil, leaderboardPanel)
    dialog:SetSize(240, 100)
    dialog:SetPoint("CENTER", leaderboardPanel, "CENTER")
    dialog:SetFrameLevel(leaderboardPanel:GetFrameLevel() + 10)
    ns.Theme.StylePanel(dialog)
    dialog:EnableMouse(true)

    local warningText = dialog:CreateFontString(nil, "OVERLAY")
    warningText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    warningText:SetPoint("TOP", 0, -14)
    warningText:SetWidth(210)
    warningText:SetJustifyH("CENTER")
    warningText:SetText("|cFFFF6666Reset all leaderboard data?|r")

    local detailText = dialog:CreateFontString(nil, "OVERLAY")
    detailText:SetFont("Fonts\\FRIZQT__.TTF", 9, "OUTLINE")
    detailText:SetPoint("TOP", warningText, "BOTTOM", 0, -4)
    detailText:SetWidth(210)
    detailText:SetJustifyH("CENTER")
    detailText:SetText("All scores for every difficulty will be permanently deleted.")
    detailText:SetTextColor(0.7, 0.7, 0.7)

    local confirmBtn = ns.Theme.CreateAccentButton(dialog, "Reset", 90, 22)
    confirmBtn:SetPoint("BOTTOMLEFT", 18, 10)
    confirmBtn:SetScript("OnClick", function()
        local db = BoundToLearn.db.leaderboard
        for _, diff in ipairs(DIFFICULTIES) do
            db[diff] = {}
        end
        BoundToLearn:Print("Leaderboard data has been reset.")
        dialog:Hide()
        LeaderboardUI:Refresh()
    end)

    local cancelBtn = ns.Theme.CreateButton(dialog, "Cancel", 90, 22)
    cancelBtn:SetPoint("BOTTOMRIGHT", -18, 10)
    cancelBtn:SetScript("OnClick", function()
        dialog:Hide()
    end)

    confirmDialog = dialog
end

function LeaderboardUI:UpdateTabs()
    if not tabButtons then return end
    for _, btn in ipairs(tabButtons) do
        btn:SetActive(btn.tabKey == currentTab)
    end

    if guildPage then guildPage:SetShown(currentTab == "guild") end
    if partyPage then partyPage:SetShown(currentTab == "party") end
end

function LeaderboardUI:UpdateDiffButtons()
    if not leaderboardPanel or not leaderboardPanel.diffBtns then return end
    for _, btn in ipairs(leaderboardPanel.diffBtns) do
        local c = DIFF_COLORS[btn.diffName]
        if btn.diffName == currentDifficulty then
            btn:SetNormalFontObject("GameFontNormalSmall")
            btn:GetFontString():SetTextColor(c[1], c[2], c[3])
        else
            btn:SetNormalFontObject("GameFontDisableSmall")
            btn:GetFontString():SetTextColor(ns.Theme.RGB(ns.Theme.C.TEXT_DIM))
        end
    end
end

function LeaderboardUI:Refresh()
    if not leaderboardPanel or not leaderboardPanel:IsShown() then return end

    if currentTab == "guild" then
        self:RefreshGuild()
    else
        self:RefreshParty()
    end
end

function LeaderboardUI:RefreshGuild()
    local board = ns.Leaderboard and ns.Leaderboard:GetLeaderboard(currentDifficulty) or {}

    for i = 1, GUILD_MAX_ROWS do
        local row = guildRows[i]
        local entry = board[i]

        if entry then
            if i <= 3 then
                local colors = { {1, 0.84, 0}, {0.75, 0.75, 0.75}, {0.8, 0.5, 0.2} }
                local c = colors[i]
                row.rank:SetText(sformat("|cFF%02x%02x%02x%d|r", c[1]*255, c[2]*255, c[3]*255, i))
            else
                row.rank:SetText(tostring(i))
                row.rank:SetTextColor(0.6, 0.6, 0.6)
            end

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
            row.bg:Show()
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

    local sorted = {}
    for playerName, data in pairs(scores) do
        if data.difficulty == currentDifficulty then
            data.name = playerName
            tinsert(sorted, data)
        end
    end
    table.sort(sorted, function(a, b) return a.score > b.score end)

    for i = 1, PARTY_MAX_ROWS do
        local row = partyRows[i]
        local entry = sorted[i]

        if entry then
            local cc = CLASS_COLORS[entry.class] or {0.7, 0.7, 0.7}
            row.name:SetText(sformat("|cFF%02x%02x%02x%s|r", cc[1]*255, cc[2]*255, cc[3]*255, entry.name))
            row.score:SetText(sformat("%d", entry.score))
            row.score:SetTextColor(1, 0.84, 0)
            row.combo:SetText(sformat("%d", entry.combo or 0))
            row.combo:SetTextColor(0.8, 0.8, 0.8)
            row.acc:SetText(sformat("%d%%", entry.accuracy or 0))
            row.acc:SetTextColor(0.6, 0.9, 0.6)

            row.name:Show()
            row.score:Show()
            row.combo:Show()
            row.acc:Show()
            row.bg:Show()
        else
            row.name:Hide()
            row.score:Hide()
            row.combo:Hide()
            row.acc:Hide()
        end
    end

    if #sorted == 0 then
        leaderboardPanel.partyNote:SetText("No party scores yet. Play a round while in a group.")
    else
        leaderboardPanel.partyNote:SetText("Recent scores from party/raid members")
    end
end
