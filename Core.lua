local ADDON_NAME, ns = ...

local Utils   = ns.Utils
local sformat = Utils.sformat
local pairs   = Utils.pairs
local type    = Utils.type
local mmin, mmax = Utils.mmin, Utils.mmax
local mfloor  = Utils.mfloor
local ipairs  = Utils.ipairs
local PlayUISound = Utils.PlayUISound
local SOUND_CLICK = Utils.SOUND_CLICK

BoundToLearn = {}
BoundToLearn._ns = ns
ns.BoundToLearn = BoundToLearn

local DB_DEFAULTS = {
    filter = {
        mounts = true,
        toys = true,
        hearthstones = true,
        teleports = true,
        consumables = true,
        professions = true,
        skyriding = true,
        nonCombatMacros = true,
        buffs = true,
    },
    tracker = {
        enabled = true,
        showWidget = true,
        widgetPosition = nil,
        widgetScale = 1.0,
        combatOnly = false,
        hideInCombat = false,
        blocklist = {},
        maxSegments = 6,
    },
    game = {
        difficulty = "Medium",
        modifiers = {},
        songKey = "s1",            -- selected track for the rhythm game
        songScores = {},           -- [songKey][difficulty] = best score
        songProgress = {},         -- [songKey] = best fraction (0-1) reached
        songHistory = {},          -- [songKey][difficulty] = { recent scores } for the results trend
        songStats = {},            -- [songKey][difficulty] = { plays, bestAccuracy, bestCombo }
        mode = "timed",            -- "timed", "practice", "competitive"
        compBarPos = false,        -- saved competitive lane-bar position (drag setup)
        duration = 90,             -- seconds (timed/competitive)
        fallSpeed = 150,
        fallDistance = 300,
        spawnInterval = 1.5,
        maxActiveNotes = 3,
        timingPerfect = 0.08,
        timingGreat = 0.15,
        timingGood = 0.25,
        soundEnabled = true,
        showCombo = true,
        bars = {
            main = true,           -- ActionButton1-12
            bottomLeft = true,     -- MultiBarBottomLeft
            bottomRight = false,   -- MultiBarBottomRight
            right = false,         -- MultiBarRight
            left = false,          -- MultiBarLeft
            bar6 = false,          -- MultiBar5
            bar7 = false,          -- MultiBar6
            bar8 = false,          -- MultiBar7
        },
    },
    pingTrainer = {
        targetStyle = "portraits",  -- "portraits", "blobs", "3d"
        background = "classic",     -- selected expansion background id
        randomBG = false,           -- randomize from unlocked backgrounds
        unlockedBGs = { classic = true, tbc = true },
        muteMusic = false,
        mutePingSounds = true,      -- ping sounds off by default
    },
    stats = {
        sessions = {},
        personalBest = {
            longestCombo = 0,
            highestScore = 0,
            bestAccuracy = 0,
            bestKeybindRatio = 0,
            fastestQuiz = 0,
        },
        difficultyBest = {
            Easy = { highestScore = 0, longestCombo = 0 },
            Medium = { highestScore = 0, longestCombo = 0 },
            Hard = { highestScore = 0, longestCombo = 0 },
            Extreme = { highestScore = 0, longestCombo = 0 },
        },
        lifetimeClicks = 0,
        lifetimeKeybinds = 0,
        lifetimeGameNotes = 0,
        lifetimeGameHits = 0,
        lifetimeQuizzes = 0,
        lifetimeQuizAbilities = 0,
        scoreScaleV2 = false,
    },
    options = {
        showMinimapButton = true,
        firstRun = true,
        showGameWarning = true,
        muteChat = false,
        colorTheme = "Blue",
    },
    leaderboard = {
        Easy = {},
        Medium = {},
        Hard = {},
        Extreme = {},
    },
    clickBlock = {
        enabled = false,
        mode = "all",   -- "all", "cc", "interrupt", "custom"
        customBlacklist = {},  -- { [spellID] = spellName }
    },
    audit = {
        bars = {
            main = true,
            bottomLeft = true,
            bottomRight = true,
            right = true,
            left = true,
            bar6 = true,
            bar7 = true,
            bar8 = true,
        },
        skipBarSelection = false,
        mmoMouse = false,
        includeGrouping = false,
        keyboardLayout = "QWERTY",
    },
    achievements = {
        unlocked = {},  -- [achievementID] = timestamp
    },
    minimap = {
        angle = 220,
    },
}

local function MergeDefaults(target, defaults)
    for k, v in pairs(defaults) do
        if target[k] == nil then
            target[k] = v
        elseif type(v) == "table" and type(target[k]) == "table" then
            MergeDefaults(target[k], v)
        end
    end
end

local function OnInitialize()
    if not BoundToLearnDB then
        BoundToLearnDB = {}
    end
    MergeDefaults(BoundToLearnDB, DB_DEFAULTS)
    BoundToLearn.db = BoundToLearnDB

    -- One-time reset of score bests when scoring moved to the normalized money-score
    -- (capped near 100k). Old bests were on a much larger, length-dependent scale and
    -- would be permanently unbeatable. Combo and accuracy bests are scale-independent
    -- and kept.
    if not BoundToLearnDB.stats.scoreScaleV2 then
        BoundToLearnDB.stats.personalBest.highestScore = 0
        for _, d in pairs(BoundToLearnDB.stats.difficultyBest) do d.highestScore = 0 end
        for _, board in pairs(BoundToLearnDB.leaderboard) do wipe(board) end
        BoundToLearnDB.stats.scoreScaleV2 = true
    end

    -- Apply the saved color theme before any UI is built.
    if ns.Theme and ns.Theme.ApplyTheme then
        ns.Theme.ApplyTheme(BoundToLearnDB.options.colorTheme)
    end

    -- Crash recovery for the round music fade: if a round set the Music volume
    -- low/zero for a fade and a crash skipped the restore, put it back.
    if BoundToLearnDB.pendingMusicRestore then
        SetCVar("Sound_MusicVolume", BoundToLearnDB.pendingMusicRestore)
        BoundToLearnDB.pendingMusicRestore = nil
    end

    -- One-time recovery for an earlier build that muted the Music channel via the
    -- Sound_MusicVolume CVar and could leave it at 0 permanently on a crash.
    if not BoundToLearnDB.musicVolRestored then
        BoundToLearnDB.musicVolRestored = true
        if (tonumber(GetCVar("Sound_MusicVolume")) or 0) == 0 then
            SetCVar("Sound_MusicVolume", 0.4)
        end
    end

    -- Competitive mode is removed from main for now (kept on the experimental
    -- branch); fall back to timed if an old saved value still selects it.
    if BoundToLearnDB.game.mode == "competitive" then
        BoundToLearnDB.game.mode = "timed"
    end

    -- Migrate: filter moved from tracker.filter to top-level filter
    if BoundToLearnDB.tracker and BoundToLearnDB.tracker.filter then
        for k, v in pairs(BoundToLearnDB.tracker.filter) do
            BoundToLearnDB.filter[k] = v
        end
        BoundToLearnDB.tracker.filter = nil
    end
    -- Migrate: skipNonCombat moved to shared filter
    if BoundToLearnDB.audit and BoundToLearnDB.audit.skipNonCombat ~= nil then
        BoundToLearnDB.filter.nonCombatMacros = BoundToLearnDB.audit.skipNonCombat
        BoundToLearnDB.audit.skipNonCombat = nil
    end

    -- Migrate: Ping Trainer backgrounds are now per-expansion. Retire the old
    -- zone-art ids, seed the always-on Classic/TBC backdrops, and reset any stale
    -- selection to Classic.
    local pt = BoundToLearnDB.pingTrainer
    if pt then
        pt.unlockedBGs = pt.unlockedBGs or {}
        pt.unlockedBGs.orgrimmar = nil
        pt.unlockedBGs.darnassus = nil
        pt.unlockedBGs.naxxramas = nil
        pt.unlockedBGs.classic = true
        pt.unlockedBGs.tbc = true
        if pt.background == "orgrimmar" or pt.background == "darnassus" or pt.background == "naxxramas" then
            pt.background = "classic"
        end
    end

    -- Migrate: money-score scale dropped 10x (SCORE_CAP 100000 -> 10000). Rescale
    -- every stored score once so old bests stay comparable to new runs.
    if not BoundToLearnDB.scoresRescaled10 then
        BoundToLearnDB.scoresRescaled10 = true
        local st = BoundToLearnDB.stats
        if type(st) == "table" then
            if type(st.personalBest) == "table" and type(st.personalBest.highestScore) == "number" then
                st.personalBest.highestScore = mfloor(st.personalBest.highestScore / 10)
            end
            if type(st.difficultyBest) == "table" then
                for _, d in pairs(st.difficultyBest) do
                    if type(d) == "table" and type(d.highestScore) == "number" then
                        d.highestScore = mfloor(d.highestScore / 10)
                    end
                end
            end
            if type(st.sessions) == "table" then
                for _, s in ipairs(st.sessions) do
                    if type(s) == "table" and type(s.score) == "number" then
                        s.score = mfloor(s.score / 10)
                    end
                end
            end
        end
        local ss = BoundToLearnDB.game and BoundToLearnDB.game.songScores
        if type(ss) == "table" then
            for _, perDiff in pairs(ss) do
                if type(perDiff) == "table" then
                    for diff, sc in pairs(perDiff) do
                        if type(sc) == "number" then perDiff[diff] = mfloor(sc / 10) end
                    end
                end
            end
        end
        local lb = BoundToLearnDB.leaderboard
        if type(lb) == "table" then
            for _, board in pairs(lb) do
                if type(board) == "table" then
                    for _, entry in ipairs(board) do
                        if type(entry) == "table" and type(entry.score) == "number" then
                            entry.score = mfloor(entry.score / 10)
                        end
                    end
                end
            end
        end
    end

    ns.version = C_AddOns.GetAddOnMetadata(ADDON_NAME, "Version")

    SLASH_KBTRACK1 = "/kbtrack"
    SlashCmdList["KBTRACK"] = function()
        BoundToLearn:ToggleTracker()
    end

    SLASH_BOUNDTOLEARN1 = "/btl"
    SlashCmdList["BOUNDTOLEARN"] = function(msg)
        msg = msg and msg:lower():trim() or ""

        if msg == "track" then
            BoundToLearn:ToggleTracker()
        elseif msg == "game" then
            BoundToLearn:OpenGame()
        elseif msg == "stats" then
            BoundToLearn:ShowStats()
        elseif msg == "o" or msg == "options" or msg == "config" or msg == "settings" then
            BoundToLearn:OpenOptions()
        elseif msg == "reset" then
            if ns.Tracker then ns.Tracker:ResetSession() end
            BoundToLearn:Print("Session reset.")
        elseif msg == "reset scores" or msg == "resetscores" then
            BoundToLearn:ConfirmResetScores()
        elseif msg == "lb" or msg == "leaderboard" then
            if ns.LeaderboardUI then ns.LeaderboardUI:Toggle() end
        elseif msg == "accept" then
            if ns.Leaderboard then ns.Leaderboard:AcceptChallenge() end
        elseif msg == "decline" then
            if ns.Leaderboard then ns.Leaderboard:DeclineChallenge() end
        elseif msg:sub(1, 9) == "challenge" then
            local target = msg:sub(11):trim()
            if target == "" then target = "party" end
            if ns.Leaderboard then ns.Leaderboard:SendChallenge(target) end
        elseif msg == "enforce" or msg == "block" then
            if ns.ClickBlock then ns.ClickBlock:Toggle() end
        elseif msg == "enforce all" or msg == "block all" then
            if ns.ClickBlock then ns.ClickBlock:SetMode("all"); ns.ClickBlock:Enable() end
        elseif msg == "enforce cc" or msg == "block cc" then
            if ns.ClickBlock then ns.ClickBlock:SetMode("cc"); ns.ClickBlock:Enable() end
        elseif msg == "enforce interrupt" or msg == "block interrupt" then
            if ns.ClickBlock then ns.ClickBlock:SetMode("interrupt"); ns.ClickBlock:Enable() end
        elseif msg == "audit" or msg == "keybinds" then
            if ns.KeybindAuditUI then ns.KeybindAuditUI:Toggle() end
        elseif msg == "quiz" then
            if ns.KeybindQuiz then ns.KeybindQuiz:Toggle() end
        elseif msg == "debughitbox" then
            if ns.PingGameUI then ns.PingGameUI:ToggleDebugHitbox() end
        elseif msg == "wheeldbg" then
            if ns.GameUI then ns.GameUI:DumpWheel() end
        elseif msg == "ping" then
            if ns.PingGameUI then ns.PingGameUI:Toggle() end
        elseif msg == "hide" then
            if ns.TrackerUI then ns.TrackerUI:Hide() end
            if ns.GameUI then ns.GameUI:Hide() end
        elseif msg == "help" or msg == "?" then
            BoundToLearn:PrintHelp()
        elseif msg == "" then
            BoundToLearn:ShowMinimapMenu()
        else
            BoundToLearn:Print(sformat("Unknown command: %s. Type /btl help for options.", msg))
        end
    end
end

local function OnPlayerLogin()
    C_Timer.After(0.5, function()
        if ns.Tracker       then ns.Tracker:Initialize()       end
        if ns.TrackerUI     then ns.TrackerUI:Initialize()     end
        if ns.Stats         then ns.Stats:Initialize()         end
        if ns.Game          then ns.Game:Initialize()          end
        if ns.GameUI        then ns.GameUI:Initialize()        end
        if ns.StatsUI       then ns.StatsUI:Initialize()       end
        if ns.Options       then ns.Options:Initialize()       end
        if ns.Leaderboard   then ns.Leaderboard:Initialize()   end
        if ns.LeaderboardUI then ns.LeaderboardUI:Initialize() end
        if ns.ClickBlock   then ns.ClickBlock:Initialize()   end
        if ns.PingGame     then ns.PingGame:Initialize()     end
        if ns.PingGameUI   then ns.PingGameUI:Initialize()   end
    end)

    C_Timer.After(0.6, function()
        if BoundToLearn.db.options.showMinimapButton then
            BoundToLearn:CreateMinimapButton()
        end
    end)

    if BoundToLearn.db.options.firstRun then
        C_Timer.After(2, function()
            BoundToLearn:ShowWelcome()
        end)
    end
end

-- Event dispatch
local eventFrame = CreateFrame("Frame")
ns.eventFrame = eventFrame

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")

eventFrame:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        OnInitialize()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        OnPlayerLogin()
        self.loginHandled = true
        self:UnregisterEvent("PLAYER_LOGIN")
    elseif event == "PLAYER_ENTERING_WORLD" then
        if arg2 and not self.loginHandled then
            OnPlayerLogin()
        end
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    end
end)

-- Public API
function BoundToLearn:ToggleTracker()
    if not ns.Tracker then return end
    local db = self.db.tracker
    if db.enabled then
        db.enabled = false
        ns.Tracker:StopSession()
        if ns.TrackerUI then ns.TrackerUI:Hide() end
    else
        db.enabled = true
        ns.Tracker:StartSession()
        if ns.TrackerUI then
            ns.TrackerUI:OnSessionStart()
        end
    end
end

function BoundToLearn:ShowStats()
    if ns.StatsUI then ns.StatsUI:Toggle() end
end

function BoundToLearn:OpenOptions()
    if ns.Options then ns.Options:Toggle() end
end

function BoundToLearn:Print(msg)
    if self.db and self.db.options.muteChat then return end
    Utils.Print(msg)
end

function BoundToLearn:PrintHelp()
    local lines = {
        "|cFFFF8A33BoundToLearn|r - Keybind training companion",
        "  /btl track       - Enable/disable keybind tracker",
        "  /btl game        - Open keybind practice game",
        "  /btl lb          - Show leaderboard",
        "  /btl challenge   - Challenge your party to a round",
        "  /btl accept      - Accept a challenge",
        "  /btl decline     - Decline a challenge",
        "  /btl audit       - Show keybind audit",
        "  /btl quiz        - Start keybind quiz",
        "  /btl ping        - Open ping trainer",
        "  /btl stats       - Show statistics panel",
        "  /btl options     - Open settings",
        "  /btl enforce      - Toggle click blocking (keybind-only mode)",
        "  /btl enforce all  - Block all ability clicks",
        "  /btl enforce cc   - Block only CC/interrupt clicks",
        "  /btl reset       - Reset current session",
        "  /btl hide        - Hide all UI",
        "  /btl help     - Show this help",
    }
    for _, line in ipairs(lines) do
        print(line)
    end
end

-- Hidden testing command (/btl reset scores): wipe all persistent progress.
-- Not listed in help; confirmed via popup so a user who stumbles on it is
-- warned about exactly what they lose before anything is erased.
function BoundToLearn:ConfirmResetScores()
    if not StaticPopupDialogs["BOUNDTOLEARN_RESET_SCORES"] then
        StaticPopupDialogs["BOUNDTOLEARN_RESET_SCORES"] = {
            text = "Reset ALL BoundToLearn progress?\n\nThis permanently erases every achievement, trophy, personal best, high score, and leaderboard entry. It cannot be undone.",
            button1 = "Erase Everything",
            button2 = "Cancel",
            showAlert = true,
            timeout = 0,
            whileDead = true,
            hideOnEscape = true,
            preferredIndex = 3,
            OnAccept = function()
                local db = BoundToLearn.db
                wipe(db.achievements.unlocked)
                for _, board in pairs(db.leaderboard) do wipe(board) end
                local s = db.stats
                wipe(s.sessions)
                local pb = s.personalBest
                pb.longestCombo, pb.highestScore = 0, 0
                pb.bestAccuracy, pb.bestKeybindRatio, pb.fastestQuiz = 0, 0, 0
                for _, d in pairs(s.difficultyBest) do
                    d.highestScore, d.longestCombo = 0, 0
                end
                s.lifetimeClicks, s.lifetimeKeybinds = 0, 0
                s.lifetimeGameNotes, s.lifetimeGameHits = 0, 0
                s.lifetimeQuizzes, s.lifetimeQuizAbilities = 0, 0
                BoundToLearn:Print("All scores, achievements, and trophies reset.")
            end,
        }
    end
    StaticPopup_Show("BOUNDTOLEARN_RESET_SCORES")
end

-- Minimap button
local minimapButton

function BoundToLearn:CreateMinimapButton()
    if minimapButton then
        minimapButton:Show()
        return
    end

    local btn = CreateFrame("Button", "BoundToLearnMinimapButton", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(8)
    btn:SetClampedToScreen(true)
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    -- Icon (keyboard-style icon using a standard texture)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER")
    icon:SetTexture("Interface\\MacroFrame\\MacroFrame-Icon")
    btn.icon = icon

    -- Border (standard minimap button border)
    local border = btn:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture(136430) -- Standard minimap button border
    btn.border = border

    -- Background
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(24, 24)
    bg:SetPoint("CENTER")
    bg:SetTexture(136467) -- Standard minimap button background
    btn.bg = bg

    local function UpdatePosition(angle)
        local rads = math.rad(angle)
        local radius = (Minimap:GetWidth() / 2) + 5
        local x = math.cos(rads) * radius
        local y = math.sin(rads) * radius
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER", x, y)
    end

    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            local angle = math.deg(math.atan2(cy - my, cx - mx))
            BoundToLearn.db.minimap.angle = angle
            UpdatePosition(angle)
        end)
    end)
    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            BoundToLearn:OpenOptions()
        else
            -- Left click: show a quick menu
            BoundToLearn:ShowMinimapMenu(self)
        end
    end)

    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("|cFFFF8A33BoundToLearn|r")
        GameTooltip:AddLine("Left-click: Menu", 1, 1, 1)
        GameTooltip:AddLine("Right-click: Options", 1, 1, 1)
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    UpdatePosition(BoundToLearn.db.minimap.angle)
    btn:Show()
    minimapButton = btn
end

-- Simple dropdown menu from minimap button
local minimapMenu

function BoundToLearn:ShowMinimapMenu(anchor)
    if not minimapMenu then
        minimapMenu = CreateFrame("Frame", "BoundToLearnMinimapMenu", UIParent)
        minimapMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        -- Capture the mouse over the whole menu so hovers do not fall through to
        -- the minimap buttons behind it (their tooltips were bleeding over the menu).
        minimapMenu:EnableMouse(true)
        ns.Theme.StylePanel(minimapMenu, 0.97)
        minimapMenu:Hide()

        local menuEntries = {
            { header = "Games" },
            { getText = function() return "Icon Game" end, func = function() self:OpenGame() end },
            { getText = function() return "Ping Trainer" end, func = function() if ns.PingGameUI then ns.PingGameUI:Toggle() end end },
            { header = "Practice" },
            { getText = function() return "Keybind Quiz" end, func = function() if ns.KeybindQuiz then ns.KeybindQuiz:Toggle() end end },
            { getText = function() return "Keybind Audit" end, func = function() if ns.KeybindAuditUI then ns.KeybindAuditUI:Toggle() end end },
            { header = "Tracker" },
            { getText = function()
                return self.db.tracker.enabled and "Disable Tracker" or "Enable Tracker"
            end, func = function() self:ToggleTracker() end },
            { separator = true },
            { getText = function() return "Statistics" end, func = function() self:ShowStats() end },
            { getText = function() return "Options" end, func = function() self:OpenOptions() end },
        }

        local menuBtns = {}
        local yOff = -5
        for _, item in ipairs(menuEntries) do
            if item.header then
                yOff = yOff - 6
                local label = minimapMenu:CreateFontString(nil, "OVERLAY")
                label:SetFont("Fonts\\FRIZQT__.TTF", 13, "OUTLINE")
                label:SetPoint("TOP", 0, yOff)
                label:SetTextColor(ns.Theme.RGB(ns.Theme.C.GOLD))
                label:SetText(item.header)
                yOff = yOff - 18
            elseif item.separator then
                local div = minimapMenu:CreateTexture(nil, "ARTWORK")
                div:SetHeight(1)
                div:SetPoint("TOPLEFT", 6, yOff - 2)
                div:SetPoint("TOPRIGHT", -6, yOff - 2)
                div:SetColorTexture(ns.Theme.RGB(ns.Theme.C.BORDER, 0.35))
                yOff = yOff - 5
            else
                local menuBtn = CreateFrame("Button", nil, minimapMenu)
                menuBtn:SetSize(130, 22)
                menuBtn:SetPoint("TOPLEFT", 5, yOff)
                menuBtn:SetNormalFontObject("GameFontHighlightSmall")
                menuBtn:SetHighlightFontObject("GameFontNormalSmall")
                local hl = CreateFrame("Frame", nil, menuBtn)
                hl:SetPoint("TOPLEFT", -1, 1)
                hl:SetPoint("BOTTOMRIGHT", 1, -1)
                ns.Theme.Round(hl)
                ns.Theme.SetBarHeight(hl, 10)
                ns.Theme.SetBorderShown(hl, false)
                ns.Theme.SetFillColor(hl, ns.Theme.C.ACCENT, 0)
                menuBtn:HookScript("OnEnter", function() ns.Theme.SetFillColor(hl, ns.Theme.C.ACCENT, 0.18) end)
                menuBtn:HookScript("OnLeave", function() ns.Theme.SetFillColor(hl, ns.Theme.C.ACCENT, 0) end)
                menuBtn:SetText(item.getText())
                menuBtn:SetScript("OnClick", function()
                    PlayUISound(SOUND_CLICK)
                    minimapMenu:Hide()
                    item.func()
                end)
                tinsert(menuBtns, { btn = menuBtn, getText = item.getText })
                yOff = yOff - 26
            end
        end
        minimapMenu:SetSize(140, -yOff + 5)

        minimapMenu:SetScript("OnShow", function(self)
            for _, entry in ipairs(menuBtns) do
                entry.btn:SetText(entry.getText())
            end
            self:SetScript("OnUpdate", function(self)
                if not self:IsMouseOver() and not (minimapButton and minimapButton:IsMouseOver())
                   and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                    self:Hide()
                end
            end)
        end)

        minimapMenu:SetScript("OnHide", function(self)
            self:SetScript("OnUpdate", nil)
        end)
    end

    if minimapMenu:IsShown() then
        minimapMenu:Hide()
        return
    end

    minimapMenu:ClearAllPoints()
    if anchor then
        -- Hang straight down from the button so it reads as attached; clamping
        -- keeps it on-screen when the button sits near a screen edge.
        minimapMenu:SetClampedToScreen(true)
        minimapMenu:SetPoint("TOP", anchor, "BOTTOM", 0, -2)
    else
        -- Bare /btl: drop the menu at the cursor.
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        minimapMenu:SetPoint("TOP", UIParent, "BOTTOMLEFT", cx / scale, cy / scale)
    end
    minimapMenu:Show()
end

-- Welcome popup for first-time users
local welcomeFrame

function BoundToLearn:ShowWelcome()
    if welcomeFrame then welcomeFrame:Show(); return end

    local f = CreateFrame("Frame", "BoundToLearnWelcome", UIParent)
    f:SetSize(420, 390)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    ns.Theme.StylePanel(f)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local title = ns.Theme.CreateTitle(f, "Welcome to BoundToLearn", 18)
    title:SetPoint("TOP", 0, -16)

    local titleRule = ns.Theme.CreateDivider(f)
    titleRule:SetPoint("TOPLEFT", 16, -40)
    titleRule:SetPoint("TOPRIGHT", -16, -40)

    local GOLD, ACC, WARN = ns.Theme.GOLD_HEX, ns.Theme.ACCENT_HEX, ns.Theme.OKAY_HEX
    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 20, -52)
    body:SetPoint("TOPRIGHT", -20, -52)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText(
        "|cFF" .. GOLD .. "Keybind Tracker|r\n" ..
        "Automatically tracks whether you use keybinds or click " ..
        "your abilities. A small floating widget shows your keybind " ..
        "ratio in real time. The goal: build muscle memory so " ..
        "keybinds become second nature.\n\n" ..
        "|cFF" .. GOLD .. "Practice Game|r\n" ..
        "A rhythm-based minigame where spell icons fall toward " ..
        "your action bar. Press the correct keybind at the right time " ..
        "to score points. Build combos for multipliers and bonus rewards.\n\n" ..
        "|cFF" .. WARN .. "Note:|r Starting the practice game will |cFF" .. WARN .. "temporarily " ..
        "disable your abilities|r so keypresses are scored instead of " ..
        "casting spells. Your abilities return to normal the moment the " ..
        "game ends. The game cannot run during combat.\n\n" ..
        "|cFF" .. GOLD .. "Getting Started|r\n" ..
        "Use |cFF" .. ACC .. "/btl|r to see all commands, or right-click the " ..
        "minimap button for quick access to options."
    )

    local cb = ns.Theme.CreateToggle(f, "Don't show this again", nil, 190)
    cb:SetPoint("BOTTOMLEFT", 16, 18)
    cb:SetChecked(false)

    local btn = ns.Theme.CreateAccentButton(f, "Got It", 100, 26)
    btn:SetPoint("BOTTOMRIGHT", -16, 16)
    local function dismiss()
        if cb:GetChecked() then
            BoundToLearn.db.options.firstRun = false
        end
        f:Hide()
    end
    btn:SetScript("OnClick", dismiss)

    local close = ns.Theme.CreateCloseButton(f, dismiss)
    close:SetPoint("TOPRIGHT", -8, -8)

    f:Show()
    welcomeFrame = f
end

-- Game start confirmation with "don't show again" option
local gameConfirmFrame

local function ShowGameConfirm()
    if not gameConfirmFrame then
        local f = CreateFrame("Frame", "BoundToLearnGameConfirm", UIParent)
        f:SetSize(340, 200)
        f:SetPoint("CENTER", 0, 60)
        f:SetFrameStrata("DIALOG")
        ns.Theme.StylePanel(f)
        f:EnableMouse(true)

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", 20, -22)
        body:SetPoint("TOPRIGHT", -20, -22)
        body:SetJustifyH("CENTER")
        body:SetSpacing(3)
        body:SetText(
            "Starting the practice game will |cFF" .. ns.Theme.OKAY_HEX .. "temporarily\n" ..
            "disable your abilities|r so keypresses are\n" ..
            "scored instead of casting spells.\n\n" ..
            "Your abilities return to normal when the game ends."
        )

        local cb = ns.Theme.CreateToggle(f, "Don't ask again", nil, 160)
        cb:SetPoint("BOTTOMLEFT", 16, 16)
        f.dontAsk = cb

        local startBtn = ns.Theme.CreateAccentButton(f, "Start", 100, 26)
        startBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 14)
        startBtn:SetScript("OnClick", function()
            if cb:GetChecked() then
                BoundToLearn.db.options.showGameWarning = false
            end
            f:Hide()
            if ns.Game then ns.Game:Start() end
        end)

        local cancelBtn = ns.Theme.CreateButton(f, "Cancel", 100, 26)
        cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 14)
        cancelBtn:SetScript("OnClick", function()
            f:Hide()
        end)

        f:SetScript("OnKeyDown", function(self, key)
            if key == "ESCAPE" then
                self:SetPropagateKeyboardInput(false)
                self:Hide()
            else
                self:SetPropagateKeyboardInput(true)
            end
        end)

        f:Hide()
        gameConfirmFrame = f
    end

    gameConfirmFrame.dontAsk:SetChecked(false)
    gameConfirmFrame:Show()
end

function BoundToLearn:OpenGame()
    if ns.Game and ns.Game:IsRunning() then
        self:Print("Game is already running.")
        return
    end
    if ns.GameUI then
        ns.GameUI:Initialize()
        ns.GameUI:ShowReadyState()
    end
end

function BoundToLearn:ToggleGame()
    if ns.Game then
        if ns.Game:IsRunning() then
            ns.Game:Stop()
        else
            if InCombatLockdown() then
                self:Print("Cannot start game during combat.")
                return
            end
            if self.db.options.showGameWarning then
                ShowGameConfirm()
            else
                ns.Game:Start()
            end
        end
    end
end

function BoundToLearn:UpdateMinimapButton()
    if BoundToLearn.db.options.showMinimapButton then
        self:CreateMinimapButton()
    elseif minimapButton then
        minimapButton:Hide()
    end
end

-- Blizzard addon compartment (the addon-list button under the minimap).
-- Gives players a way in even when the minimap button is hidden.
function BoundToLearn_OnAddonCompartmentClick(_, button, menuButtonFrame)
    if button == "RightButton" then
        BoundToLearn:OpenOptions()
    else
        BoundToLearn:ShowMinimapMenu(menuButtonFrame)
    end
end
