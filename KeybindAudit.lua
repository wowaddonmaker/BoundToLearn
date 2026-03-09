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
local wipe    = Utils.wipe
local slower  = Utils.slower
local sfind   = Utils.sfind

local HasAction        = HasAction
local GetActionInfo    = GetActionInfo
local GetActionTexture = GetActionTexture
local GetActionText    = GetActionText
local GetBindingKey    = GetBindingKey
local GetBindingAction = GetBindingAction
local GetMacroBody     = GetMacroBody
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

local function ClassifyKey(bind, mmoMouse)
    local base, hasModifier = StripModifiers(bind)
    local tier
    if PRIME_KEYS[base] then
        tier = "prime"
    elseif mmoMouse and MMO_MOUSE_PRIME[base] then
        tier = "prime"
    elseif POOR_KEYS[base] then
        tier = "poor"
    else
        tier = "acceptable"
    end
    return tier, hasModifier, base
end

local function IsCombatMacro(macroIndex)
    local body = GetMacroBody(macroIndex)
    if not body then return false end
    body = slower(body)
    if sfind(body, "/cast", 1, true) then return true end
    if sfind(body, "/use", 1, true) then return true end
    if sfind(body, "/castsequence", 1, true) then return true end
    if sfind(body, "/cancelaura", 1, true) then return true end
    if sfind(body, "/cancelform", 1, true) then return true end
    if sfind(body, "/startattack", 1, true) then return true end
    if sfind(body, "/stopattack", 1, true) then return true end
    if sfind(body, "/petattack", 1, true) then return true end
    if sfind(body, "/stopcasting", 1, true) then return true end
    return false
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
    local skipNonCombat = options.skipNonCombat
    local mmoMouse = options.mmoMouse

    local bars = {}
    local allSlots = {}
    local issues = {}

    local totalFilled = 0
    local totalBound = 0
    local totalModified = 0
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
                if HasAction(slot) then
                    local actionType, actionId = GetActionInfo(slot)

                    -- Skip non-combat macros
                    if skipNonCombat and actionType == "macro" and actionId and not IsCombatMacro(actionId) then
                        skippedMacros = skippedMacros + 1
                    else
                        local keybind = GetBindingKey(barDef.bindPrefix .. i)
                        local icon = GetActionTexture(slot)
                        local name = GetActionName(slot) or sformat("Slot %d", slot)

                        local tier, hasModifier, base
                        if keybind then
                            tier, hasModifier, base = ClassifyKey(keybind, mmoMouse)
                        end

                        local slotData = {
                            slot = slot,
                            barIndex = i,
                            barLabel = resolvedLabel,
                            actionName = name,
                            icon = icon,
                            keybind = keybind,
                            tier = tier,
                            hasModifier = hasModifier,
                            baseKey = base,
                        }

                        tinsert(barData.slots, slotData)
                        tinsert(allSlots, slotData)
                        barData.filledCount = barData.filledCount + 1
                        totalFilled = totalFilled + 1

                        if keybind then
                            barData.boundCount = barData.boundCount + 1
                            totalBound = totalBound + 1
                            if hasModifier then totalModified = totalModified + 1 end

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
            end

            bars[barDef.key] = barData
        end
    end

    -- Coverage score (40%)
    local coverageScore = totalFilled > 0 and (totalBound / totalFilled * 100) or 100

    -- Reachability score (30%)
    local reachScore = totalBound > 0 and (reachSum / totalBound) or 0

    -- Modifier usage score (15%)
    local modRatio = totalBound > 0 and (totalModified / totalBound) or 0
    local modScore
    if modRatio >= 0.51 then modScore = 100
    elseif modRatio >= 0.31 then modScore = 80
    elseif modRatio >= 0.16 then modScore = 60
    elseif modRatio >= 0.01 then modScore = 40
    else modScore = 20 end

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
                text = sformat("%s has no keybind", slotData.actionName),
                detail = sformat("On %s, slot %d.", slotData.barLabel, slotData.barIndex),
            })
        end
    end

    for _, slotData in ipairs(allSlots) do
        if slotData.keybind and slotData.tier == "poor" then
            tinsert(issues, {
                severity = "low",
                icon = slotData.icon,
                text = sformat("%s is on a distant key (%s)", slotData.actionName, slotData.keybind),
                detail = "Move this to a key closer to WASD for faster access.",
            })
        end
    end

    if totalBound >= 6 and totalModified == 0 then
        tinsert(issues, {
            severity = "low",
            icon = nil,
            text = "No modifier combos used",
            detail = "Shift/Ctrl/Alt combos let you triple your available keys without moving your hand.",
        })
    end

    for _, barDef in ipairs(BAR_MAPPINGS) do
        local barData = bars[barDef.key]
        if not barData.excluded and barData.filledCount > 0 and barData.boundCount == 0 then
            tinsert(issues, {
                severity = "medium",
                icon = nil,
                text = sformat("%s has %d abilities but none are keybound", barData.label, barData.filledCount),
                detail = "Every ability on your bar should have a keybind.",
            })
        end
    end

    local sevOrder = { high = 1, medium = 2, low = 3 }
    table.sort(issues, function(a, b)
        return (sevOrder[a.severity] or 9) < (sevOrder[b.severity] or 9)
    end)

    local overall = coverageScore * 0.40 + reachScore * 0.30 + modScore * 0.15 + antiScore * 0.15
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
            overall = overall,
        },
        issues = issues,
        grade = grade,
        gradeColor = gradeColor,
        summary = self:GetSummary(overall),
        keyboardTurning = keyboardTurning,
        totalFilled = totalFilled,
        totalBound = totalBound,
        skippedMacros = skippedMacros,
    }

    return auditResults
end

function KeybindAudit:GetResults()
    return auditResults
end
