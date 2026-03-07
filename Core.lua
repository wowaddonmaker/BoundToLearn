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
    tracker = {
        enabled = true,
        showWidget = true,
        widgetPosition = nil,
        widgetScale = 1.0,
        combatOnly = false,
        hideInCombat = false,
        blocklist = {},
        maxSegments = 6,
        filter = {
            mounts = true,
            toys = true,
            hearthstones = true,
            teleports = true,
            consumables = true,
            professions = true,
        },
    },
    game = {
        difficulty = "Medium",
        mode = "timed",            -- "timed", "practice", "competitive"
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
        },
    },
    stats = {
        sessions = {},
        personalBest = {
            longestCombo = 0,
            highestScore = 0,
            bestAccuracy = 0,
            bestKeybindRatio = 0,
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
    },
    options = {
        showLoginMessage = true,
        showMinimapButton = true,
        firstRun = true,
        showGameWarning = true,
        muteChat = false,
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
        elseif msg == "hide" then
            if ns.TrackerUI then ns.TrackerUI:Hide() end
            if ns.GameUI then ns.GameUI:Hide() end
        elseif msg == "help" or msg == "" then
            BoundToLearn:PrintHelp()
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
    end)

    C_Timer.After(0.6, function()
        if BoundToLearn.db.options.showMinimapButton then
            BoundToLearn:CreateMinimapButton()
        end
    end)

    if BoundToLearn.db.options.showLoginMessage then
        C_Timer.After(1, function()
            BoundToLearn:Print("Loaded. Type /btl to get started.")
        end)
    end

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
        "|cFF55CCFFBoundToLearn|r - Keybind training companion",
        "  /btl track       - Enable/disable keybind tracker",
        "  /btl game        - Open keybind practice game",
        "  /btl lb          - Show leaderboard",
        "  /btl challenge   - Challenge your party to a round",
        "  /btl accept      - Accept a challenge",
        "  /btl decline     - Decline a challenge",
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
        GameTooltip:SetText("|cFF55CCFFBoundToLearn|r")
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
        minimapMenu = CreateFrame("Frame", "BoundToLearnMinimapMenu", UIParent, "BackdropTemplate")
        minimapMenu:SetSize(140, 156)
        minimapMenu:SetFrameStrata("FULLSCREEN_DIALOG")
        minimapMenu:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 },
        })
        minimapMenu:SetBackdropColor(0.05, 0.05, 0.05, 0.95)
        minimapMenu:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.9)
        minimapMenu:Hide()

        local menuItems = {
            { getText = function()
                return self.db.tracker.enabled and "Disable Tracker" or "Enable Tracker"
            end, func = function() self:ToggleTracker() end },
            { getText = function() return "Open Game" end, func = function() self:OpenGame() end },
            { getText = function() return "Leaderboard" end, func = function() if ns.LeaderboardUI then ns.LeaderboardUI:Toggle() end end },
            { getText = function() return "Statistics" end, func = function() self:ShowStats() end },
            { getText = function() return "Options" end, func = function() self:OpenOptions() end },
        }

        local menuBtns = {}
        for i, item in ipairs(menuItems) do
            local menuBtn = CreateFrame("Button", nil, minimapMenu)
            menuBtn:SetSize(130, 22)
            menuBtn:SetPoint("TOPLEFT", 5, -5 - (i - 1) * 26)
            menuBtn:SetNormalFontObject("GameFontHighlightSmall")
            menuBtn:SetHighlightFontObject("GameFontNormalSmall")
            menuBtn:SetText(item.getText())
            menuBtn:SetScript("OnClick", function()
                PlayUISound(SOUND_CLICK)
                minimapMenu:Hide()
                item.func()
            end)
            menuBtns[i] = { btn = menuBtn, getText = item.getText }
        end

        minimapMenu:SetScript("OnShow", function(self)
            for _, entry in ipairs(menuBtns) do
                entry.btn:SetText(entry.getText())
            end
            self:SetScript("OnUpdate", function(self)
                if not self:IsMouseOver() and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
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
    minimapMenu:SetPoint("TOPRIGHT", anchor, "BOTTOMLEFT", 0, 0)
    minimapMenu:Show()
end

-- Welcome popup for first-time users
local welcomeFrame

function BoundToLearn:ShowWelcome()
    if welcomeFrame then welcomeFrame:Show(); return end

    local f = CreateFrame("Frame", "BoundToLearnWelcome", UIParent, "BackdropTemplate")
    f:SetSize(420, 390)
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
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = f:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 18, "OUTLINE")
    title:SetPoint("TOP", 0, -14)
    title:SetText("|cFF55CCFFWelcome to BoundToLearn|r")

    local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    body:SetPoint("TOPLEFT", 20, -45)
    body:SetPoint("TOPRIGHT", -20, -45)
    body:SetJustifyH("LEFT")
    body:SetSpacing(3)
    body:SetText(
        "|cFFFFCC00Keybind Tracker|r\n" ..
        "Automatically tracks whether you use keybinds or click " ..
        "your abilities. A small floating widget shows your keybind " ..
        "ratio in real time. The goal: build muscle memory so " ..
        "keybinds become second nature.\n\n" ..
        "|cFFFFCC00Practice Game|r\n" ..
        "A rhythm-based minigame where spell icons fall toward " ..
        "your action bar. Press the correct keybind at the right time " ..
        "to score points. Build combos for multipliers and bonus rewards.\n\n" ..
        "|cFFFF6600Note:|r Starting the practice game will |cFFFF6600temporarily " ..
        "disable your abilities|r so keypresses are scored instead of " ..
        "casting spells. Your abilities return to normal the moment the " ..
        "game ends. The game cannot run during combat.\n\n" ..
        "|cFFFFCC00Getting Started|r\n" ..
        "Use |cFF55CCFF/btl|r to see all commands, or right-click the " ..
        "minimap button for quick access to options."
    )

    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
    cb:SetPoint("BOTTOMLEFT", 14, 40)
    cb:SetChecked(false)
    local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    cbText:SetText("Don't show this again")

    local btn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btn:SetSize(100, 24)
    btn:SetPoint("BOTTOM", 0, 14)
    btn:SetText("Got It")
    btn:SetScript("OnClick", function()
        if cb:GetChecked() then
            BoundToLearn.db.options.firstRun = false
        end
        f:Hide()
    end)

    close:SetScript("OnClick", function()
        if cb:GetChecked() then
            BoundToLearn.db.options.firstRun = false
        end
        f:Hide()
    end)

    f:Show()
    welcomeFrame = f
end

-- Game start confirmation with "don't show again" option
local gameConfirmFrame

local function ShowGameConfirm()
    if not gameConfirmFrame then
        local f = CreateFrame("Frame", "BoundToLearnGameConfirm", UIParent, "BackdropTemplate")
        f:SetSize(340, 190)
        f:SetPoint("CENTER", 0, 60)
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

        local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", 20, -16)
        body:SetPoint("TOPRIGHT", -20, -16)
        body:SetJustifyH("CENTER")
        body:SetSpacing(3)
        body:SetText(
            "Starting the practice game will |cFFFF6600temporarily\n" ..
            "disable your abilities|r so keypresses are\n" ..
            "scored instead of casting spells.\n\n" ..
            "Your abilities return to normal when the game ends."
        )

        local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate")
        cb:SetPoint("BOTTOMLEFT", 14, 38)
        local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
        cbText:SetText("Don't ask again")
        f.dontAsk = cb

        local startBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        startBtn:SetSize(100, 24)
        startBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOM", -4, 10)
        startBtn:SetText("Start")
        startBtn:SetScript("OnClick", function()
            if cb:GetChecked() then
                BoundToLearn.db.options.showGameWarning = false
            end
            f:Hide()
            if ns.Game then ns.Game:Start() end
        end)

        local cancelBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        cancelBtn:SetSize(100, 24)
        cancelBtn:SetPoint("BOTTOMLEFT", f, "BOTTOM", 4, 10)
        cancelBtn:SetText("Cancel")
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
