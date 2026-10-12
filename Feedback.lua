local ADDON_NAME, ns = ...

-- Give feedback: a GitHub issue link with the details of the screen the player
-- is on already filled in (addon version, client, the track and difficulty, the
-- round's numbers). The game cannot open a browser, so the link is shown in a
-- box ready to copy. Never includes the character's name or realm: issues are
-- public.

local Feedback = {}
ns.Feedback = Feedback

local Utils = ns.Utils
local sformat, tconcat = string.format, table.concat

local ISSUE_URL = "https://github.com/wowaddonmaker/BoundToLearn/issues/new"
local TEMPLATE = "feedback.yml"
local MAX_ADDON_LIST = 600   -- characters of other addon names, keeps the link short

local function Encode(s)
    s = tostring(s):gsub("\r?\n", "\r\n")
    s = s:gsub("([^%w%-%.%_%~ ])", function(c) return sformat("%%%02X", c:byte()) end)
    return (s:gsub(" ", "+"))
end

function Feedback.Version()
    local get = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return (get and get(ADDON_NAME, "Version")) or "unknown"
end

local function ClientLine()
    local version, build, _, toc = GetBuildInfo()
    return sformat("%s %s (build %s, interface %s)",
        Utils.IS_FOREVER and "WoW Forever" or "Retail", version or "?", build or "?", toc or "?")
end

-- Other loaded addons, Blizzard's own left out: the usual suspect when nobody
-- else can reproduce a problem.
local function OtherAddons()
    local num = (C_AddOns and C_AddOns.GetNumAddOns or GetNumAddOns)()
    local info = C_AddOns and C_AddOns.GetAddOnInfo or GetAddOnInfo
    local loaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded
    local names, len = {}, 0
    for i = 1, num do
        local name = info(i)
        if name and name ~= ADDON_NAME and not name:match("^Blizzard_") and loaded(i) then
            if len + #name > MAX_ADDON_LIST then
                names[#names + 1] = "..."
                break
            end
            names[#names + 1] = name
            len = len + #name + 2
        end
    end
    return #names > 0 and tconcat(names, ", ") or "none"
end

-- The details block: what every report carries, then the screen's own lines.
function Feedback.Details(screen, lines)
    local out = {
        "Addon: BoundToLearn " .. Feedback.Version(),
        "Client: " .. ClientLine(),
        "Screen: " .. screen,
    }
    for _, line in ipairs(lines or {}) do out[#out + 1] = line end
    local _, class = UnitClass("player")
    out[#out + 1] = sformat("Character: %s, level %d", class or "?", UnitLevel("player") or 0)
    local w, h = 0, 0
    if GetPhysicalScreenSize then w, h = GetPhysicalScreenSize() end
    out[#out + 1] = sformat("Display: %dx%d, UI scale %.2f, locale %s",
        w, h, UIParent:GetEffectiveScale(), GetLocale())
    out[#out + 1] = "Other addons: " .. OtherAddons()
    return tconcat(out, "\n")
end

function Feedback.URL(screen, lines)
    return sformat("%s?template=%s&title=%s&details=%s", ISSUE_URL, TEMPLATE,
        Encode(screen .. ": "), Encode(Feedback.Details(screen, lines)))
end

-- The copy box. Read-only: typing puts the link back.
local popup
local function CreatePopup()
    local f = CreateFrame("Frame", "BoundToLearnFeedback", UIParent)
    f:SetSize(460, 168)
    f:SetPoint("CENTER", 0, 160)
    f:SetFrameStrata("FULLSCREEN_DIALOG")
    f:SetFrameLevel(300)
    f:SetToplevel(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    ns.Theme.StylePanel(f)
    f:Hide()
    Utils.CloseOnEscape(f)

    local title = ns.Theme.CreateTitle(f, "Give feedback", 16)
    title:SetPoint("TOP", 0, -20)

    local msg = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    msg:SetPoint("TOP", title, "BOTTOM", 0, -8)
    msg:SetWidth(400)
    msg:SetText("Press Ctrl+C to copy this link, then paste it into your browser. "
        .. "The details of this screen are already filled in; you only describe what you saw or want.")

    local box = CreateFrame("EditBox", nil, f, "InputBoxTemplate")
    box:SetSize(400, 22)
    box:SetPoint("TOP", msg, "BOTTOM", 0, -10)
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetScript("OnEscapePressed", function() f:Hide() end)
    box:SetScript("OnEnterPressed", function(self) self:HighlightText() end)
    box:SetScript("OnTextChanged", function(self, userInput)
        if userInput then
            self:SetText(f.url or "")
            self:HighlightText()
        end
    end)
    box:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    -- Ctrl+C copies the highlighted link; say so and close.
    box:SetScript("OnKeyDown", function(_, key)
        if key == "C" and IsControlKeyDown() then
            f.status:SetText("Copied. Paste it into your browser.")
            C_Timer.After(0.8, function() f:Hide() end)
        end
    end)
    f.box = box

    local status = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    status:SetPoint("TOP", box, "BOTTOM", 0, -6)
    f.status = status

    local close = ns.Theme.CreateButton(f, CLOSE or "Close", 90, 22)
    close:SetPoint("BOTTOM", 0, 18)
    close:SetScript("OnClick", function() f:Hide() end)

    return f
end

-- screen: a name for where the player is ("Track select"); lines: that
-- screen's own "Label: value" details.
function Feedback:Open(screen, lines)
    popup = popup or CreatePopup()
    popup.url = Feedback.URL(screen, lines)
    popup.status:SetText("")
    popup.box:SetText(popup.url)
    popup:Show()
    popup.box:SetFocus()
    popup.box:SetCursorPosition(0)
    popup.box:HighlightText()
end

-- Our windows, for a report sent from the minimap menu or /btl feedback.
local WINDOWS = {
    { "BoundToLearnSongSelect", "Track select" },
    { "BoundToLearnIconGameMenu", "Game menu" },
    { "BoundToLearnPingGame", "Ping Trainer" },
    { "BoundToLearnQuizFrame", "Keybind Quiz" },
    { "BoundToLearnAuditFrame", "Keybind Audit" },
    { "BoundToLearnStatsFrame", "Statistics" },
    { "BoundToLearnOptionsFrame", "Options" },
    { "BoundToLearnLeaderboard", "Leaderboard" },
    { "BoundToLearnTrackerWidget", "Tracker widget" },
}

-- A report from outside any one window: lists the open ones, and takes the
-- track select's own details when it is open.
function Feedback:OpenGeneral()
    local open = {}
    for _, w in ipairs(WINDOWS) do
        local frame = _G[w[1]]
        if frame and frame:IsVisible() then open[#open + 1] = w[2] end
    end
    local lines = { "Open windows: " .. (#open > 0 and tconcat(open, ", ") or "none") }
    local songSelect = _G.BoundToLearnSongSelect
    if songSelect and songSelect:IsVisible() and ns.GameUI then
        local _, gameLines = ns.GameUI:FeedbackContext()
        for _, line in ipairs(gameLines) do lines[#lines + 1] = line end
    end
    local ping = _G.BoundToLearnPingGame
    local pdb = BoundToLearn.db and BoundToLearn.db.pingTrainer
    if ping and ping:IsVisible() and pdb then
        lines[#lines + 1] = sformat("Ping Trainer: background %s, targets %s",
            tostring(pdb.background), tostring(pdb.targetStyle))
    end
    self:Open("General", lines)
end

-- A "Give feedback" button for a window. context() returns screen, lines at the
-- moment of the click, so the details match what is on screen.
function Feedback.CreateButton(parent, context)
    local b = ns.Theme.CreateButton(parent, "Give feedback", 100, 22)
    b:SetWidth(b:GetFontString():GetUnboundedStringWidth() + 24)
    ns.Theme.AttachTooltip(b, "Give feedback",
        "Report a problem or suggest an idea. You get a link with this screen's details filled in.")
    b:SetScript("OnClick", function()
        Utils.PlayUISound(Utils.SOUND_CLICK)
        local screen, lines = context()
        Feedback:Open(screen, lines)
    end)
    return b
end
