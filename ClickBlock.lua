local ADDON_NAME, ns = ...

local ClickBlock = {}
ns.ClickBlock = ClickBlock

local Utils = ns.Utils
local pairs = Utils.pairs
local ipairs = Utils.ipairs
local wipe = Utils.wipe
local sformat = Utils.sformat
local CreateFrame = Utils.CreateFrame

local GetActionInfo = GetActionInfo
local HasAction = HasAction
local InCombatLockdown = InCombatLockdown
local UIParent = UIParent
local C_Spell = C_Spell
local tostring = tostring
local tinsert = Utils.tinsert

local isActive = false
local overlays = {}     -- slot → overlay frame
local pendingApply = false

local BUTTON_PREFIXES = {
    "ActionButton",
    "MultiBarBottomLeftButton",
    "MultiBarBottomRightButton",
    "MultiBarRightButton",
    "MultiBarLeftButton",
}

local RED_TINT = { r = 0.8, g = 0.1, b = 0.1, a = 0.35 }

local function GetButtonSpellID(btn, slot)
    local actionType, id, subType = GetActionInfo(slot)
    if id and id ~= 0 and (actionType == "spell" or subType == "spell") then
        return id
    end
    return nil
end

local function ShouldBlockSlot(btn, slot)
    local db = BoundToLearn.db.clickBlock
    if db.mode == "all" then
        return HasAction(slot)
    end
    local spellID = GetButtonSpellID(btn, slot)
    if not spellID then return false end
    if db.mode == "custom" then
        return db.customBlacklist[spellID] ~= nil
    end
    if ns.SpellData then
        if db.mode == "cc" then
            return ns.SpellData:IsCCOrInterrupt(spellID)
        elseif db.mode == "interrupt" then
            return ns.SpellData:IsInterrupt(spellID)
        end
    end
    return false
end

local function CreateOverlay(btn, slot)
    local overlay = CreateFrame("Button", nil, btn)
    overlay:SetAllPoints(btn)
    overlay:SetFrameStrata(btn:GetFrameStrata())
    overlay:SetFrameLevel(btn:GetFrameLevel() + 10)
    overlay:EnableMouse(true)
    overlay:RegisterForClicks("AnyUp", "AnyDown")

    -- Red tint texture (hidden until hover)
    local tint = overlay:CreateTexture(nil, "OVERLAY")
    tint:SetAllPoints()
    tint:SetColorTexture(RED_TINT.r, RED_TINT.g, RED_TINT.b, RED_TINT.a)
    tint:Hide()
    overlay.tint = tint

    -- Block icon (small X or lock indicator)
    local icon = overlay:CreateTexture(nil, "OVERLAY", nil, 1)
    icon:SetSize(16, 16)
    icon:SetPoint("TOPRIGHT", -1, -1)
    icon:SetAtlas("XMarksTheSpot")
    icon:SetAlpha(0.6)
    icon:Hide()
    overlay.lockIcon = icon

    overlay:SetScript("OnEnter", function(self)
        tint:Show()
        icon:Show()
        -- Pass through tooltip from parent button
        if btn:GetScript("OnEnter") then
            btn:GetScript("OnEnter")(btn)
        end
    end)
    overlay:SetScript("OnLeave", function(self)
        tint:Hide()
        icon:Hide()
        if btn:GetScript("OnLeave") then
            btn:GetScript("OnLeave")(btn)
        end
    end)
    overlay:SetScript("OnClick", function()
        -- Consume the click (do nothing)
    end)

    overlay.slot = slot
    return overlay
end

local function ApplyOverlays()
    -- Hide all existing overlays first
    for _, overlay in pairs(overlays) do
        overlay:Hide()
    end

    if not isActive then return end

    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn then
                local slot = btn.action or (btn.GetAction and btn:GetAction())
                if slot and ShouldBlockSlot(btn, slot) then
                    if not overlays[slot] then
                        overlays[slot] = CreateOverlay(btn, slot)
                    end
                    local overlay = overlays[slot]
                    overlay:SetParent(btn)
                    overlay:SetAllPoints(btn)
                    overlay:SetFrameStrata(btn:GetFrameStrata())
                    overlay:SetFrameLevel(btn:GetFrameLevel() + 10)
                    overlay:Show()
                end
            end
        end
    end
end

local function QueueApply()
    if InCombatLockdown() then
        pendingApply = true
    else
        ApplyOverlays()
    end
end

-- Event frame for combat state changes and actionbar updates
local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_REGEN_ENABLED" then
        if pendingApply then
            pendingApply = false
            ApplyOverlays()
        end
    elseif event == "ACTIONBAR_SLOT_CHANGED" or event == "UPDATE_BONUS_ACTIONBAR"
        or event == "ACTIONBAR_PAGE_CHANGED" then
        if isActive then
            QueueApply()
        end
    end
end)

function ClickBlock:Initialize()
    if ns.SpellData then
        ns.SpellData:Initialize()
    end
    local db = BoundToLearn.db.clickBlock
    if db.enabled then
        self:Enable()
    end
end

function ClickBlock:Enable()
    isActive = true
    BoundToLearn.db.clickBlock.enabled = true
    eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
    eventFrame:RegisterEvent("ACTIONBAR_SLOT_CHANGED")
    eventFrame:RegisterEvent("UPDATE_BONUS_ACTIONBAR")
    eventFrame:RegisterEvent("ACTIONBAR_PAGE_CHANGED")
    QueueApply()
end

function ClickBlock:Disable()
    isActive = false
    BoundToLearn.db.clickBlock.enabled = false
    eventFrame:UnregisterAllEvents()
    for _, overlay in pairs(overlays) do
        overlay:Hide()
    end
    pendingApply = false
end

function ClickBlock:Toggle()
    if isActive then
        self:Disable()
        Utils.Print("Click blocking disabled.")
    else
        self:Enable()
        Utils.Print(sformat("Click blocking enabled (mode: %s).", BoundToLearn.db.clickBlock.mode))
    end
end

local selectOverlays = {}
local isSelecting = false
local onSelectCallback
local onStopCallback
local screenDim

local function ClearSelectOverlays()
    for _, ov in pairs(selectOverlays) do
        ov:Hide()
        ov:SetParent(nil)
    end
    wipe(selectOverlays)
end

local function ShowScreenDim()
    if not screenDim then
        screenDim = CreateFrame("Frame", nil, UIParent)
        screenDim:SetAllPoints()
        screenDim:SetFrameStrata("BACKGROUND")
        screenDim:SetFrameLevel(0)
        local bg = screenDim:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints()
        bg:SetColorTexture(0, 0, 0, 0.5)
    end
    screenDim:Show()
end

local function HideScreenDim()
    if screenDim then screenDim:Hide() end
end

function ClickBlock:StartSelect(callback, stopCallback)
    if isSelecting then return end
    isSelecting = true
    onSelectCallback = callback
    onStopCallback = stopCallback

    ShowScreenDim()

    for _, prefix in ipairs(BUTTON_PREFIXES) do
        for i = 1, 12 do
            local btn = _G[prefix .. i]
            if btn then
                local slot = btn.action or (btn.GetAction and btn:GetAction())
                if slot and HasAction(slot) then
                    local spellID = GetButtonSpellID(btn, slot)
                    if spellID then
                        local ov = CreateFrame("Button", nil, btn)
                        ov:SetAllPoints(btn)
                        ov:SetFrameStrata(btn:GetFrameStrata())
                        ov:SetFrameLevel(btn:GetFrameLevel() + 20)
                        ov:EnableMouse(true)
                        ov:RegisterForClicks("LeftButtonUp")

                        local highlight = ov:CreateTexture(nil, "OVERLAY")
                        highlight:SetAllPoints()
                        highlight:SetColorTexture(0.2, 0.8, 1, 0.3)
                        highlight:Hide()
                        ov:SetScript("OnEnter", function() highlight:Show() end)
                        ov:SetScript("OnLeave", function() highlight:Hide() end)
                        local sid = spellID
                        ov:SetScript("OnClick", function()
                            local name = C_Spell and C_Spell.GetSpellInfo(sid)
                            local spellName = name and name.name or tostring(sid)
                            BoundToLearn.db.clickBlock.customBlacklist[sid] = spellName
                            if onSelectCallback then onSelectCallback() end
                            if isActive then QueueApply() end
                        end)
                        tinsert(selectOverlays, ov)
                    end
                end
            end
        end
    end
end

function ClickBlock:StopSelect()
    isSelecting = false
    onSelectCallback = nil
    ClearSelectOverlays()
    HideScreenDim()
    if onStopCallback then
        onStopCallback()
        onStopCallback = nil
    end
end

function ClickBlock:IsSelecting()
    return isSelecting
end

function ClickBlock:ClearBlacklist()
    wipe(BoundToLearn.db.clickBlock.customBlacklist)
    if isActive then QueueApply() end
end

function ClickBlock:SetMode(mode)
    if mode ~= "all" and mode ~= "cc" and mode ~= "interrupt" and mode ~= "custom" then
        Utils.Print(sformat("Unknown mode: %s. Use 'all', 'cc', 'interrupt', or 'custom'.", mode))
        return
    end
    BoundToLearn.db.clickBlock.mode = mode
    Utils.Print(sformat("Click block mode set to: %s", mode))
    if isActive then
        QueueApply()
    end
end

function ClickBlock:IsActive()
    return isActive
end

function ClickBlock:Refresh()
    if isActive then
        QueueApply()
    end
end

