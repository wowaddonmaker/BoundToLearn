local ADDON_NAME, ns = ...

local Utils = {}
ns.Utils = Utils

-- LOCALIZED GLOBALS
local pairs, ipairs, type, select, unpack, next = pairs, ipairs, type, select, unpack, next
local tinsert, tsort, tconcat, tremove = table.insert, table.sort, table.concat, table.remove
local sfind, slower, ssub, sformat, smatch = string.find, string.lower, string.sub, string.format, string.match
local mmin, mmax, mabs, mceil, mfloor = math.min, math.max, math.abs, math.ceil, math.floor
local pcall, tostring, tonumber = pcall, tostring, tonumber
local GetTime, CreateFrame = GetTime, CreateFrame
local PlaySound = PlaySound
local PlaySoundFile = PlaySoundFile
local wipe = wipe

Utils.pairs    = pairs
Utils.ipairs   = ipairs
Utils.type     = type
Utils.select   = select
Utils.unpack   = unpack
Utils.next     = next

Utils.tinsert  = tinsert
Utils.tsort    = tsort
Utils.tconcat  = tconcat
Utils.tremove  = tremove

Utils.sfind    = sfind
Utils.slower   = slower
Utils.ssub     = ssub
Utils.sformat  = sformat
Utils.smatch   = smatch

Utils.mmin     = mmin
Utils.mmax     = mmax
Utils.mabs     = mabs
Utils.mceil    = mceil
Utils.mfloor   = mfloor

Utils.pcall    = pcall
Utils.tostring = tostring
Utils.tonumber = tonumber

Utils.GetTime     = GetTime
Utils.CreateFrame = CreateFrame
Utils.PlaySound   = PlaySound
Utils.wipe        = wipe

-- UI click sounds (SOUNDKIT IDs - PlaySound works reliably)
Utils.SOUND_CLICK = 856   -- igMainMenuOptionCheckboxOn
Utils.SOUND_TAB   = 841   -- igCharacterInfoTab
Utils.SOUND_CLOSE = 851   -- igMainMenuClose

function Utils.PlayUISound(soundKitID)
    PlaySound(soundKitID)
end

-- WoW Forever (Interface 16001): mainline UI on the classic world.
local tocVersion = select(4, GetBuildInfo())
Utils.IS_FOREVER = tocVersion >= 16000 and tocVersion < 20000

-- Esc closes our newest open window. Never UISpecialFrames: a frame of
-- ours in that list taints the client's Esc walk. Escape is bound to our
-- button while a window is up and handed back for combat.
local InCombatLockdown = InCombatLockdown
local escStack = {}
local escClose = {}
local escArmed = false
local escPressed = false
local escHeader = CreateFrame("Frame", nil, UIParent, "SecureHandlerBaseTemplate")

local function EscArm()
    if InCombatLockdown() then return end
    local want = #escStack > 0
    if want == escArmed then return end
    escArmed = want
    if want then
        escHeader:Execute([[ self:SetBindingClick(true, "ESCAPE", "BoundToLearnEscButton") ]])
    else
        escHeader:Execute([[ self:ClearBindings() ]])
    end
end

local function EscRemove(frame)
    for i = #escStack, 1, -1 do
        if escStack[i] == frame then tremove(escStack, i) end
    end
end

-- A bound button must be sized and placed or the key goes to the client.
local escButton = CreateFrame("Button", "BoundToLearnEscButton", UIParent)
escButton:SetSize(1, 1)
escButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 0, 0)
escButton:EnableMouse(false)
escButton:RegisterForClicks("AnyDown", "AnyUp")
escButton:SetScript("OnClick", function(_, _, down)
    -- A press can click on the way down and up; act on the first only.
    if not down and escPressed then
        escPressed = false
        return
    end
    escPressed = down
    local top = escStack[#escStack]
    if not top then return end
    local close = escClose[top]
    if close then close() else top:Hide() end
end)

escHeader:RegisterEvent("PLAYER_REGEN_DISABLED")
escHeader:RegisterEvent("PLAYER_REGEN_ENABLED")
escHeader:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_ENABLED" then
        EscArm()
    elseif escArmed then
        escArmed = false
        escHeader:Execute([[ self:ClearBindings() ]])
    end
end)

-- close (optional) runs in place of hiding the frame.
function Utils.CloseOnEscape(frame, close)
    escClose[frame] = close
    -- Own child: the window's OnShow/OnHide scripts stay the caller's.
    local watch = CreateFrame("Frame", nil, frame)
    watch:SetScript("OnShow", function()
        EscRemove(frame)
        escStack[#escStack + 1] = frame
        EscArm()
    end)
    watch:SetScript("OnHide", function()
        EscRemove(frame)
        EscArm()
    end)
    if frame:IsVisible() then
        escStack[#escStack + 1] = frame
        EscArm()
    end
end

-- Brand orange (matches Theme.ACCENT_HEX); kept literal so chat output
-- never depends on Theme load order.
Utils.BRAND_HEX = "FF8A33"

function Utils.Print(msg)
    local hex = (ns.Theme and ns.Theme.ACCENT_HEX) or Utils.BRAND_HEX
    print(sformat("|cFF%s[BoundToLearn]|r %s", hex, msg))
end

function Utils.DebugPrint(...)
    if BoundToLearn and BoundToLearn.db and BoundToLearn.db.devMode then
        print("|cff33ff99[BTL Debug]|r", ...)
    end
end

-- Hit quality weights for accuracy: perfect counts full, great and good count partially,
-- miss zero. So an all-"good" run no longer reads 100% -- only an all-perfect run does.
local ACC_WEIGHT = { perfect = 1.0, great = 0.75, good = 0.5 }

function Utils.WeightedHits(hc)
    if not hc then return 0 end
    return (hc.perfect or 0) * ACC_WEIGHT.perfect
         + (hc.great or 0) * ACC_WEIGHT.great
         + (hc.good or 0) * ACC_WEIGHT.good
end

function Utils.HitAccuracy(hc)
    if not hc then return 0 end
    local total = (hc.perfect or 0) + (hc.great or 0) + (hc.good or 0) + (hc.miss or 0)
    if total <= 0 then return 0 end
    return Utils.WeightedHits(hc) / total * 100
end
