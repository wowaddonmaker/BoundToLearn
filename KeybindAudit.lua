local ADDON_NAME, ns = ...

local KeybindAudit = {}
ns.KeybindAudit = KeybindAudit

local Utils   = ns.Utils
local sformat = Utils.sformat
local mfloor  = Utils.mfloor
local mmin    = Utils.mmin
local mmax    = Utils.mmax
local tinsert = Utils.tinsert
local pairs   = Utils.pairs
local ipairs  = Utils.ipairs
local slower  = Utils.slower

local msqrt  = Utils.msqrt or math.sqrt

local HasAction        = HasAction
local GetActionInfo    = GetActionInfo
local GetActionTexture = GetActionTexture
local GetActionText    = GetActionText
local GetBindingKey    = GetBindingKey
local GetBindingAction = GetBindingAction
local C_Spell          = C_Spell

-- Key reachability tiers (base key only, modifiers stripped)
local PRIME_KEYS = {
    ["1"] = true, ["2"] = true, ["3"] = true, ["4"] = true, ["5"] = true,
    ["Q"] = true, ["E"] = true, ["R"] = true, ["F"] = true, ["G"] = true,
    ["Z"] = true, ["X"] = true, ["C"] = true, ["V"] = true, ["T"] = true,
    ["B"] = true, ["`"] = true, ["TAB"] = true, ["CAPSLOCK"] = true,
    ["BUTTON3"] = true, ["BUTTON4"] = true, ["BUTTON5"] = true,
}

local POOR_KEYS = {
    ["7"] = true, ["8"] = true, ["9"] = true, ["0"] = true,
    ["-"] = true, ["="] = true,
    ["F1"] = true, ["F2"] = true, ["F3"] = true, ["F4"] = true,
    ["F5"] = true, ["F6"] = true, ["F7"] = true, ["F8"] = true,
    ["F9"] = true, ["F10"] = true, ["F11"] = true, ["F12"] = true,
}

-- MMO mouse: number row keys are on the mouse thumb pad, so all are prime
local MMO_MOUSE_PRIME = {
    ["6"] = true, ["7"] = true, ["8"] = true, ["9"] = true,
    ["0"] = true, ["-"] = true, ["="] = true,
}

-- How many abilities fit on prime keys before modifiers are expected.
local function CountKeys(set)
    local n = 0
    for _ in pairs(set) do n = n + 1 end
    return n
end
local PRIME_KEY_COUNT = CountKeys(PRIME_KEYS)
local MMO_PRIME_COUNT = CountKeys(MMO_MOUSE_PRIME)

local BAR_MAPPINGS = {
    { key = "main",        label = "Action Bar 1",  bindPrefix = "ACTIONBUTTON",          buttonPrefix = "ActionButton",               startSlot = 1 },
    { key = "bottomLeft",  label = "Action Bar 2",  bindPrefix = "MULTIACTIONBAR1BUTTON", buttonPrefix = "MultiBarBottomLeftButton",   startSlot = 61 },
    { key = "bottomRight", label = "Action Bar 3",  bindPrefix = "MULTIACTIONBAR2BUTTON", buttonPrefix = "MultiBarBottomRightButton",  startSlot = 49 },
    { key = "right",       label = "Action Bar 4",  bindPrefix = "MULTIACTIONBAR3BUTTON", buttonPrefix = "MultiBarRightButton",        startSlot = 25 },
    { key = "left",        label = "Action Bar 5",  bindPrefix = "MULTIACTIONBAR4BUTTON", buttonPrefix = "MultiBarLeftButton",         startSlot = 37 },
    { key = "bar6",        label = "Action Bar 6",  bindPrefix = "MULTIACTIONBAR5BUTTON", buttonPrefix = "MultiBar5Button",            startSlot = 145 },
    { key = "bar7",        label = "Action Bar 7",  bindPrefix = "MULTIACTIONBAR6BUTTON", buttonPrefix = "MultiBar6Button",            startSlot = 157 },
    { key = "bar8",        label = "Action Bar 8",  bindPrefix = "MULTIACTIONBAR7BUTTON", buttonPrefix = "MultiBar7Button",            startSlot = 169 },
}

KeybindAudit.BAR_MAPPINGS = BAR_MAPPINGS

-- Map button prefix to the well-known bar frame global name
local BAR_FRAME_NAMES = {
    ActionButton               = "MainMenuBar",
    MultiBarBottomLeftButton   = "MultiBarBottomLeft",
    MultiBarBottomRightButton  = "MultiBarBottomRight",
    MultiBarRightButton        = "MultiBarRight",
    MultiBarLeftButton         = "MultiBarLeft",
    MultiBar5Button            = "MultiBar5",
    MultiBar6Button            = "MultiBar6",
    MultiBar7Button            = "MultiBar7",
}

-- Resolve bar label from the bar frame's Edit Mode systemIndex
-- systemIndex is the bar number directly (2-8), MainMenuBar has no systemIndex (always bar 1)
function KeybindAudit.ResolveBarLabel(buttonPrefix, fallback)
    local barFrameName = BAR_FRAME_NAMES[buttonPrefix]
    if barFrameName then
        local barFrame = _G[barFrameName]
        if barFrame and barFrame.systemIndex ~= nil then
            return "Action Bar " .. barFrame.systemIndex
        end
    end
    return fallback
end

-- Which GetActionBarToggles() return slot each button prefix maps to. The API
-- reports the seven optional bars (Action Bars 2-8) in this order; the main bar
-- (Action Bar 1) is always shown and has no toggle.
local BAR_TOGGLE_INDEX = {
    MultiBarBottomLeftButton  = 1,
    MultiBarBottomRightButton = 2,
    MultiBarRightButton       = 3,
    MultiBarLeftButton        = 4,
    MultiBar5Button           = 5,
    MultiBar6Button           = 6,
    MultiBar7Button           = 7,
}

-- Whether a bar is enabled, straight from the game's own action-bar toggle API
-- rather than poking at frames or buttons (which proved unreliable).
function KeybindAudit.IsBarVisible(buttonPrefix)
    if buttonPrefix == "ActionButton" then return true end
    local idx = BAR_TOGGLE_INDEX[buttonPrefix]
    if not idx then return false end
    return select(idx, GetActionBarToggles()) and true or false
end

-- Keyboard layout coordinate maps: key → {x, y}
-- Row positions use QWERTY-style stagger offsets
local KEYBOARD_LAYOUTS = {
    QWERTY = {
        ["`"]={0,0},["1"]={1,0},["2"]={2,0},["3"]={3,0},["4"]={4,0},["5"]={5,0},
        ["6"]={6,0},["7"]={7,0},["8"]={8,0},["9"]={9,0},["0"]={10,0},["-"]={11,0},["="]={12,0},
        ["TAB"]={0.5,1},["Q"]={1.5,1},["W"]={2.5,1},["E"]={3.5,1},["R"]={4.5,1},["T"]={5.5,1},
        ["Y"]={6.5,1},["U"]={7.5,1},["I"]={8.5,1},["O"]={9.5,1},["P"]={10.5,1},
        ["CAPSLOCK"]={0.75,2},["A"]={1.75,2},["S"]={2.75,2},["D"]={3.75,2},["F"]={4.75,2},
        ["G"]={5.75,2},["H"]={6.75,2},["J"]={7.75,2},["K"]={8.75,2},["L"]={9.75,2},
        ["Z"]={2.25,3},["X"]={3.25,3},["C"]={4.25,3},["V"]={5.25,3},["B"]={6.25,3},
        ["N"]={7.25,3},["M"]={8.25,3},
        ["F1"]={1,-1},["F2"]={2,-1},["F3"]={3,-1},["F4"]={4,-1},
        ["F5"]={5.5,-1},["F6"]={6.5,-1},["F7"]={7.5,-1},["F8"]={8.5,-1},
        ["F9"]={10,-1},["F10"]={11,-1},["F11"]={12,-1},["F12"]={13,-1},
    },
    AZERTY = {
        ["`"]={0,0},["1"]={1,0},["2"]={2,0},["3"]={3,0},["4"]={4,0},["5"]={5,0},
        ["6"]={6,0},["7"]={7,0},["8"]={8,0},["9"]={9,0},["0"]={10,0},["-"]={11,0},["="]={12,0},
        ["TAB"]={0.5,1},["A"]={1.5,1},["Z"]={2.5,1},["E"]={3.5,1},["R"]={4.5,1},["T"]={5.5,1},
        ["Y"]={6.5,1},["U"]={7.5,1},["I"]={8.5,1},["O"]={9.5,1},["P"]={10.5,1},
        ["CAPSLOCK"]={0.75,2},["Q"]={1.75,2},["S"]={2.75,2},["D"]={3.75,2},["F"]={4.75,2},
        ["G"]={5.75,2},["H"]={6.75,2},["J"]={7.75,2},["K"]={8.75,2},["L"]={9.75,2},
        ["W"]={2.25,3},["X"]={3.25,3},["C"]={4.25,3},["V"]={5.25,3},["B"]={6.25,3},
        ["N"]={7.25,3},["M"]={8.25,3},
        ["F1"]={1,-1},["F2"]={2,-1},["F3"]={3,-1},["F4"]={4,-1},
        ["F5"]={5.5,-1},["F6"]={6.5,-1},["F7"]={7.5,-1},["F8"]={8.5,-1},
        ["F9"]={10,-1},["F10"]={11,-1},["F11"]={12,-1},["F12"]={13,-1},
    },
    QWERTZ = {
        ["`"]={0,0},["1"]={1,0},["2"]={2,0},["3"]={3,0},["4"]={4,0},["5"]={5,0},
        ["6"]={6,0},["7"]={7,0},["8"]={8,0},["9"]={9,0},["0"]={10,0},["-"]={11,0},["="]={12,0},
        ["TAB"]={0.5,1},["Q"]={1.5,1},["W"]={2.5,1},["E"]={3.5,1},["R"]={4.5,1},["T"]={5.5,1},
        ["Z"]={6.5,1},["U"]={7.5,1},["I"]={8.5,1},["O"]={9.5,1},["P"]={10.5,1},
        ["CAPSLOCK"]={0.75,2},["A"]={1.75,2},["S"]={2.75,2},["D"]={3.75,2},["F"]={4.75,2},
        ["G"]={5.75,2},["H"]={6.75,2},["J"]={7.75,2},["K"]={8.75,2},["L"]={9.75,2},
        ["Y"]={2.25,3},["X"]={3.25,3},["C"]={4.25,3},["V"]={5.25,3},["B"]={6.25,3},
        ["N"]={7.25,3},["M"]={8.25,3},
        ["F1"]={1,-1},["F2"]={2,-1},["F3"]={3,-1},["F4"]={4,-1},
        ["F5"]={5.5,-1},["F6"]={6.5,-1},["F7"]={7.5,-1},["F8"]={8.5,-1},
        ["F9"]={10,-1},["F10"]={11,-1},["F11"]={12,-1},["F12"]={13,-1},
    },
    DVORAK = {
        ["`"]={0,0},["1"]={1,0},["2"]={2,0},["3"]={3,0},["4"]={4,0},["5"]={5,0},
        ["6"]={6,0},["7"]={7,0},["8"]={8,0},["9"]={9,0},["0"]={10,0},["-"]={11,0},["="]={12,0},
        ["TAB"]={0.5,1},["'"]={1.5,1},[","]={2.5,1},["."]={3.5,1},["P"]={4.5,1},["Y"]={5.5,1},
        ["F"]={6.5,1},["G"]={7.5,1},["C"]={8.5,1},["R"]={9.5,1},["L"]={10.5,1},
        ["CAPSLOCK"]={0.75,2},["A"]={1.75,2},["O"]={2.75,2},["E"]={3.75,2},["U"]={4.75,2},
        ["I"]={5.75,2},["D"]={6.75,2},["H"]={7.75,2},["T"]={8.75,2},["N"]={9.75,2},
        [";"]={2.25,3},["Q"]={3.25,3},["J"]={4.25,3},["K"]={5.25,3},["X"]={6.25,3},
        ["B"]={7.25,3},["M"]={8.25,3},["W"]={9.25,3},["V"]={10.25,3},["Z"]={11.25,3},
        ["F1"]={1,-1},["F2"]={2,-1},["F3"]={3,-1},["F4"]={4,-1},
        ["F5"]={5.5,-1},["F6"]={6.5,-1},["F7"]={7.5,-1},["F8"]={8.5,-1},
        ["F9"]={10,-1},["F10"]={11,-1},["F11"]={12,-1},["F12"]={13,-1},
    },
}

KeybindAudit.KEYBOARD_LAYOUTS = KEYBOARD_LAYOUTS

local ROLE_LABELS = {
    defensive    = "Defensives",
    offensive_cd = "Offensive CDs",
    cc           = "Crowd Control",
    interrupt    = "Interrupts",
}

KeybindAudit.ROLE_LABELS = ROLE_LABELS

local function KeyDistance(layout, key1, key2)
    local pos1 = layout[key1]
    local pos2 = layout[key2]
    if not pos1 or not pos2 then return nil end
    local dx = pos1[1] - pos2[1]
    local dy = pos1[2] - pos2[2]
    return msqrt(dx * dx + dy * dy)
end

-- Average pairwise distance for a list of base keys
local function AveragePairwiseDistance(layout, baseKeys)
    local n = #baseKeys
    if n < 2 then return 0 end
    local totalDist = 0
    local pairCount = 0
    for i = 1, n - 1 do
        for j = i + 1, n do
            local d = KeyDistance(layout, baseKeys[i], baseKeys[j])
            if d then
                totalDist = totalDist + d
                pairCount = pairCount + 1
            end
        end
    end
    return pairCount > 0 and (totalDist / pairCount) or 0
end

-- Score a role group's average pairwise distance (0-100)
local function ScoreGroupDistance(avgDist)
    if avgDist <= 0.5 then return 100 end  -- same key (modifier variants)
    if avgDist <= 1.5 then return 90 end   -- adjacent keys
    if avgDist <= 2.5 then return 75 end   -- nearby
    if avgDist <= 3.5 then return 60 end   -- moderate
    if avgDist <= 5.0 then return 40 end   -- spread out
    return 20                               -- scattered
end

local GRADES = {
    { min = 95, grade = "A+", color = { 0.2, 0.8, 0.2 } },
    { min = 90, grade = "A",  color = { 0.2, 0.8, 0.2 } },
    { min = 85, grade = "A-", color = { 0.3, 0.75, 0.3 } },
    { min = 80, grade = "B+", color = { 0.8, 0.8, 0.2 } },
    { min = 75, grade = "B",  color = { 0.8, 0.8, 0.2 } },
    { min = 70, grade = "B-", color = { 0.8, 0.75, 0.2 } },
    { min = 65, grade = "C+", color = { 0.8, 0.6, 0.2 } },
    { min = 60, grade = "C",  color = { 0.8, 0.6, 0.2 } },
    { min = 50, grade = "D",  color = { 0.6, 0.3, 0.3 } },
    { min = 0,  grade = "F",  color = { 0.6, 0.3, 0.3 } },
}

local SUMMARIES = {
    { min = 95, text = "Your keybinds are in great shape" },
    { min = 85, text = "Strong keybind setup" },
    { min = 75, text = "Good foundation, a few improvements possible" },
    { min = 65, text = "Decent start, some abilities need attention" },
    { min = 50, text = "Room for improvement on several fronts" },
    { min = 0,  text = "Lots of room to grow" },
}

local auditResults

local function StripModifiers(bind)
    local base = bind
    local hasModifier = false
    base = base:gsub("^ALT%-", function() hasModifier = true; return "" end)
    base = base:gsub("^CTRL%-", function() hasModifier = true; return "" end)
    base = base:gsub("^SHIFT%-", function() hasModifier = true; return "" end)
    return base, hasModifier
end

-- The left hand on the movement keys reaches as far as the 6/Y/H/N column (x 7.25
-- on the layout maps). A key right of it (U, I, O, P, J, K, L, M and beyond) is the
-- right hand's, as far a reach as 7-0.
local LEFT_HAND_MAX_X = 7.3

-- Keys the layout maps do not place, all on the right side of the keyboard.
local RIGHT_SIDE_KEYS = {
    ["["] = true, ["]"] = true, ["\\"] = true, [";"] = true, ["'"] = true,
    [","] = true, ["."] = true, ["/"] = true, ["ENTER"] = true, ["BACKSPACE"] = true,
    ["INSERT"] = true, ["HOME"] = true, ["PAGEUP"] = true, ["DELETE"] = true,
    ["END"] = true, ["PAGEDOWN"] = true, ["UP"] = true, ["DOWN"] = true,
    ["LEFT"] = true, ["RIGHT"] = true,
}

local function ClassifyKey(bind, mmoMouse, uniqueBinds, layout)
    local base, hasModifier = StripModifiers(bind)
    -- A key the player has declared on their mouse is fully reachable; any other
    -- declared location (numpad, function row, other) is a far reach.
    local declared = uniqueBinds and uniqueBinds[base]
    local pos = layout and layout[base]
    local tier
    if declared == "mouse" then
        tier = "prime"
    elseif declared then
        tier = "poor"
    elseif PRIME_KEYS[base] then
        tier = "prime"
    elseif mmoMouse and MMO_MOUSE_PRIME[base] then
        tier = "prime"
    elseif POOR_KEYS[base] then
        tier = "poor"
    elseif pos and pos[1] > LEFT_HAND_MAX_X then
        tier = "poor"
    elseif not pos and (RIGHT_SIDE_KEYS[base] or base:find("^NUMPAD")) then
        tier = "poor"
    else
        tier = "acceptable"   -- 6, Y, H, N, Space, the mouse wheel, extra mouse buttons
    end
    return tier, hasModifier, base
end


local function GetActionName(slot)
    local actionType, id = GetActionInfo(slot)
    if not actionType then return nil end

    if actionType == "spell" and id and id > 0 then
        local info = C_Spell.GetSpellInfo(id)
        return info and info.name
    elseif actionType == "macro" then
        local macroText = GetActionText(slot)
        if macroText and macroText ~= "" then return macroText end
    elseif actionType == "item" and id and id > 0 then
        local name = C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)
        return name
    end
    return nil
end

function KeybindAudit:GetGrade(score)
    for _, g in ipairs(GRADES) do
        if score >= g.min then
            return g.grade, g.color
        end
    end
    return "F", GRADES[#GRADES].color
end

function KeybindAudit:GetSummary(score)
    for _, s in ipairs(SUMMARIES) do
        if score >= s.min then return s.text end
    end
    return SUMMARIES[#SUMMARIES].text
end

function KeybindAudit:GetScoreColor(score)
    if score >= 90 then return 0.2, 0.8, 0.2 end
    if score >= 70 then return 0.8, 0.8, 0.2 end
    if score >= 50 then return 0.8, 0.6, 0.2 end
    return 0.6, 0.3, 0.3
end

function KeybindAudit:Scan(options)
    options = options or {}
    local barFilter = options.barFilter
    local mmoMouse = options.mmoMouse
    local uniqueBinds = options.uniqueBinds
    local keyboardLayout = options.keyboardLayout or "QWERTY"
    local layout = KEYBOARD_LAYOUTS[keyboardLayout] or KEYBOARD_LAYOUTS.QWERTY
    local ShouldIgnoreAction = ns.Tracker and ns.Tracker.ShouldIgnoreAction
    if ns.Tracker and ns.Tracker.BuildProfessionCache then ns.Tracker.BuildProfessionCache() end

    local bars = {}
    local allSlots = {}
    local issues = {}

    local totalFilled = 0
    local totalBound = 0
    local totalModified = 0
    local nearModified = 0   -- modifier combos on a prime or acceptable base key
    local reachSum = 0
    local poorCount = 0
    local skippedMacros = 0

    for _, barDef in ipairs(BAR_MAPPINGS) do
        local resolvedLabel = KeybindAudit.ResolveBarLabel(barDef.buttonPrefix, barDef.label)
        if barFilter and not barFilter[barDef.key] then
            bars[barDef.key] = {
                key = barDef.key,
                label = resolvedLabel,
                slots = {},
                filledCount = 0,
                boundCount = 0,
                excluded = true,
            }
        else
            local barData = {
                key = barDef.key,
                label = resolvedLabel,
                slots = {},
                filledCount = 0,
                boundCount = 0,
            }

            for i = 1, 12 do
                -- Use the button's actual slot if available (handles Edit Mode remapping)
                local slot = barDef.startSlot + (i - 1)
                local btn = _G[barDef.buttonPrefix .. i]
                if btn then
                    local actualSlot = btn.action or (btn.GetAction and btn:GetAction())
                    if actualSlot then slot = actualSlot end
                end
                if HasAction(slot) and not (ShouldIgnoreAction and ShouldIgnoreAction(slot)) then
                        local actionType, actionId = GetActionInfo(slot)
                        local keybind = GetBindingKey(barDef.bindPrefix .. i)
                        local icon = GetActionTexture(slot)
                        local name = GetActionName(slot) or sformat("Slot %d", slot)

                        local tier, hasModifier, base
                        if keybind then
                            tier, hasModifier, base = ClassifyKey(keybind, mmoMouse, uniqueBinds, layout)
                        end

                        -- Resolve spell role for grouping
                        local spellID
                        if actionType == "spell" and actionId and actionId > 0 then
                            spellID = actionId
                        end
                        local role
                        if spellID and ns.SpellData then
                            role = ns.SpellData:GetSpellRole(spellID)
                        end

                        local slotData = {
                            slot = slot,
                            barIndex = i,
                            barKey = barDef.key,
                            barLabel = resolvedLabel,
                            actionName = name,
                            actionType = actionType,
                            actionId = actionId,
                            icon = icon,
                            keybind = keybind,
                            tier = tier,
                            hasModifier = hasModifier,
                            baseKey = base,
                            spellID = spellID,
                            role = role,
                        }

                        tinsert(barData.slots, slotData)
                        tinsert(allSlots, slotData)
                        barData.filledCount = barData.filledCount + 1
                        totalFilled = totalFilled + 1

                        if keybind then
                            barData.boundCount = barData.boundCount + 1
                            totalBound = totalBound + 1
                            if hasModifier then
                                totalModified = totalModified + 1
                                if tier ~= "poor" then nearModified = nearModified + 1 end
                            end

                            if tier == "prime" then
                                reachSum = reachSum + 100
                            elseif tier == "acceptable" then
                                reachSum = reachSum + 60
                            else
                                reachSum = reachSum + 20
                                poorCount = poorCount + 1
                            end
                        end
                end
            end

            bars[barDef.key] = barData
        end
    end

    -- Coverage score (40%)
    local coverageScore = totalFilled > 0 and (totalBound / totalFilled * 100) or 100

    -- Reachability score (30%)
    local reachScore = totalBound > 0 and (reachSum / totalBound) or 0

    -- Modifier usage score (15%). A modifier is only worth reaching for once the
    -- abilities outnumber the prime keys: before that an unmodified near key is as
    -- good or better. Expected: every ability past the prime keys sits on a
    -- modifier combo of a near key (a combo on a far key saves no reach).
    local primeKeys = PRIME_KEY_COUNT + (mmoMouse and MMO_PRIME_COUNT or 0)
    local modNeeded = mmax(0, totalBound - primeKeys)
    local modScore
    if modNeeded == 0 then
        modScore = 100
    else
        local share = nearModified / modNeeded
        if share >= 1 then modScore = 100
        elseif share >= 0.66 then modScore = 80
        elseif share >= 0.33 then modScore = 60
        elseif share > 0 then modScore = 40
        else modScore = 20 end
    end

    -- Anti-pattern score (15%)
    local antiScore = 100
    local keyboardTurning = false

    local aAction = GetBindingAction("A")
    local dAction = GetBindingAction("D")
    if aAction == "TURNLEFT" or dAction == "TURNRIGHT" then
        keyboardTurning = true
        antiScore = antiScore - 40
        tinsert(issues, {
            severity = "high",
            icon = nil,
            text = "Keyboard turning detected",
            detail = "Rebind A/D to strafe for better movement control.",
        })
    end

    local unboundCount = totalFilled - totalBound
    antiScore = antiScore - mmin(unboundCount * 5, 40)
    antiScore = antiScore - mmin(poorCount * 3, 20)
    antiScore = mmax(antiScore, 0)

    for _, slotData in ipairs(allSlots) do
        if not slotData.keybind then
            tinsert(issues, {
                severity = "medium",
                icon = slotData.icon,
                kind = "unbound",
                barKey = slotData.barKey,   -- shown under its bar's section
                text = sformat("%s has no keybind", slotData.actionName),
                detail = sformat("Slot %d.", slotData.barIndex),
            })
        end
    end

    for _, slotData in ipairs(allSlots) do
        if slotData.keybind and slotData.tier == "poor" then
            tinsert(issues, {
                severity = "low",
                icon = slotData.icon,
                kind = "distant",
                barKey = slotData.barKey,
                text = sformat("%s is on a distant key (%s)", slotData.actionName, slotData.keybind),
                detail = "Move this to a key closer to WASD for faster access.",
            })
        end
    end

    if modNeeded > nearModified then
        local short = modNeeded - nearModified
        tinsert(issues, {
            severity = "low",
            icon = nil,
            text = sformat("%d abilities, %d prime keys: put %d more on modifier combos", totalBound, primeKeys, short),
            detail = "Shift/Ctrl/Alt combos of your near keys reach the extra abilities without moving your hand.",
        })
    end

    -- A bar with nothing keybound needs no row of its own: its section in the
    -- results already lists every unbound ability under the bar's name.

    -- Grouping score (experimental, opt-in)
    -- Measures physical key proximity of abilities in the same role group
    -- (defensives near each other, CCs near each other, etc.)
    local includeGrouping = options.includeGrouping
    local groupingScore
    local roleGroups = {}  -- role → { baseKeys = {}, slots = {} }

    for _, slotData in ipairs(allSlots) do
        if slotData.keybind and slotData.baseKey and slotData.role then
            if not roleGroups[slotData.role] then
                roleGroups[slotData.role] = { baseKeys = {}, slots = {} }
            end
            tinsert(roleGroups[slotData.role].baseKeys, slotData.baseKey)
            tinsert(roleGroups[slotData.role].slots, slotData)
        end
    end

    -- Score each role group with 2+ abilities, then average
    local scoredGroups = 0
    local groupScoreSum = 0
    local roleScores = {}  -- role → { score, avgDist, count }

    for role, group in pairs(roleGroups) do
        if #group.baseKeys >= 2 then
            local avgDist = AveragePairwiseDistance(layout, group.baseKeys)
            local roleScore = ScoreGroupDistance(avgDist)
            roleScores[role] = { score = roleScore, avgDist = avgDist, count = #group.baseKeys }
            groupScoreSum = groupScoreSum + roleScore
            scoredGroups = scoredGroups + 1
        end
    end

    groupingScore = scoredGroups > 0 and (groupScoreSum / scoredGroups) or 0

    -- Generate issues for scattered role groups; explain when nothing was scoreable
    -- (so a 0 grouping bar reads as "couldn't measure" rather than a failing grade).
    if includeGrouping then
        if scoredGroups > 0 then
            for role, info in pairs(roleScores) do
                if info.score <= 40 then
                    local label = ROLE_LABELS[role] or role
                    tinsert(issues, {
                        severity = "low",
                        icon = nil,
                        text = sformat("%s are spread across distant keys", label),
                        detail = sformat("Group your %d %s on nearby keys or modifier variants of the same key.",
                            info.count, slower(label)),
                    })
                end
            end
        else
            local classifiedCount = 0
            for _, group in pairs(roleGroups) do
                classifiedCount = classifiedCount + #group.slots
            end
            local detail
            if classifiedCount == 0 then
                detail = "None of your keybound abilities are recognized by the role list yet, so there are no groups to compare. This score is experimental and its spell data is still growing."
            else
                detail = "No single role (defensives, CCs, cooldowns) has two or more keybound abilities, so there are no pairs to measure. This score is experimental."
            end
            tinsert(issues, {
                severity = "low",
                icon = nil,
                text = "Grouping not scored",
                detail = detail,
            })
        end
    end

    local sevOrder = { high = 1, medium = 2, low = 3 }
    table.sort(issues, function(a, b)
        return (sevOrder[a.severity] or 9) < (sevOrder[b.severity] or 9)
    end)

    -- Overall score: only fold grouping in when it actually produced a score.
    -- If it's N/A (no role has 2+ bound abilities), counting it as 0 would penalize
    -- the whole grade for something we couldn't measure, so fall back to the
    -- four-category weighting instead.
    local overall
    if includeGrouping and scoredGroups > 0 then
        -- Coverage 35%, Reachability 25%, Modifiers 12%, Anti-patterns 13%, Grouping 15%
        overall = coverageScore * 0.35 + reachScore * 0.25 + modScore * 0.12 + antiScore * 0.13 + groupingScore * 0.15
    else
        overall = coverageScore * 0.40 + reachScore * 0.30 + modScore * 0.15 + antiScore * 0.15
    end
    overall = mmin(mmax(mfloor(overall + 0.5), 0), 100)

    local grade, gradeColor = self:GetGrade(overall)

    auditResults = {
        bars = bars,
        barOrder = BAR_MAPPINGS,
        allSlots = allSlots,
        scores = {
            coverage = mfloor(coverageScore + 0.5),
            reachability = mfloor(reachScore + 0.5),
            modifiers = modScore,
            antiPatterns = antiScore,
            grouping = mfloor(groupingScore + 0.5),
            overall = overall,
        },
        scoredGroups = scoredGroups,
        primeKeys = primeKeys,
        modNeeded = modNeeded,
        nearModified = nearModified,
        issues = issues,
        grade = grade,
        gradeColor = gradeColor,
        summary = self:GetSummary(overall),
        keyboardTurning = keyboardTurning,
        totalFilled = totalFilled,
        totalBound = totalBound,
        skippedMacros = skippedMacros,
        includeGrouping = includeGrouping,
        roleGroups = roleGroups,
        roleScores = roleScores,
        keyboardLayout = keyboardLayout,
    }

    return auditResults
end

function KeybindAudit:GetResults()
    return auditResults
end

-- Probe (/btl auditlist): every action the last audit counted, with its type
-- and ID, saved in BoundToLearnDB.auditActions so non-combat actions that
-- slip past the filters show up all at once.
function KeybindAudit:ListActions()
    local results = auditResults
    if not results then
        BoundToLearn:Print("Run the Keybind Audit first, then /btl auditlist.")
        return
    end
    local lines = {}
    for _, s in ipairs(results.allSlots) do
        lines[#lines + 1] = sformat("%s: %s (%s %s) %s", tostring(s.barLabel), tostring(s.actionName),
            tostring(s.actionType), tostring(s.actionId), s.keybind or "unbound")
    end
    BoundToLearnDB.auditActions = lines
    BoundToLearn:Print(sformat("Audit counted %d actions; saved for review.", #lines))
end
