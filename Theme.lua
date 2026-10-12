local ADDON_NAME, ns = ...

-- Shared visual toolkit: a hand-curated rounded-rect UI system so every
-- BoundToLearn window reads as one addon instead of default Blizzard chrome.
-- The look is a dark near-black panel with a soft bottom gloss, pill-capped
-- rounded borders, toggle switches, and a green/gold accent scheme.

local Theme = {}
ns.Theme = Theme

local Utils = ns.Utils
local CreateFrame = CreateFrame
local unpack, pairs = unpack, pairs
local mmax, mfloor = math.max, math.floor
local mpi = math.pi

local TEX_FILL   = "Interface\\AddOns\\BoundToLearn\\media\\CombinedFill"
local TEX_BORDER = "Interface\\AddOns\\BoundToLearn\\media\\CombinedBorder"

--------------------------------------------------------------------------
-- Palette (green/gold accent over neutral near-black chrome)
--------------------------------------------------------------------------
local C = {
    -- Surfaces (warm near-black chrome)
    PANEL_FILL       = {0.055, 0.050, 0.045},   -- window body
    PANEL_DARK       = {0.038, 0.035, 0.031},   -- deepest inset
    SECTION_FILL     = {0.082, 0.074, 0.065, 0.92}, -- grouped setting card
    INSET_FILL       = {0.000, 0.000, 0.000, 0.45}, -- edit box / scroll well

    -- Accent (warm orange) and its darker/selected variants
    ACCENT           = {0.92, 0.50, 0.16},
    ACCENT_DIM       = {0.44, 0.25, 0.09},
    ACCENT_BRIGHT    = {1.00, 0.64, 0.30},

    -- Interactive button fills (warm-tinted grays, color as affordance)
    BTN_NORMAL       = {0.205, 0.175, 0.150},
    BTN_HOVER        = {0.290, 0.240, 0.195},
    BTN_PRESSED      = {0.150, 0.125, 0.105},
    BTN_DISABLED     = {0.090, 0.080, 0.072},

    -- Toggle track states

    -- Text
    TEXT_PRIMARY     = {1.00, 0.97, 0.86},      -- cream headings
    TEXT_BODY        = {0.80, 0.82, 0.80},
    TEXT_DIM         = {0.55, 0.57, 0.55},
    TEXT_DISABLED    = {0.45, 0.45, 0.45},
    GOLD             = {1.00, 0.82, 0.00},      -- section titles / accents

    -- Semantic (behavioral design: green success, gold good, orange ok, muted red miss)
    SUCCESS          = {0.35, 0.85, 0.45},
    GOOD             = {1.00, 0.82, 0.00},
    OKAY             = {0.98, 0.60, 0.22},
    MISS             = {0.78, 0.34, 0.34},

    BORDER           = {0.42, 0.45, 0.42},
}
Theme.C = C

-- Color-escape hex codes for inline |cFF...|r text (chat, titles, tooltips).
Theme.ACCENT_HEX = "FF8A33"   -- warm orange, readable on dark
Theme.GOLD_HEX   = "FFCC00"
Theme.CREAM_HEX  = "FFF7DB"
Theme.OKAY_HEX   = "FA9838"
Theme.MISS_HEX   = "C85656"

-- Convenience unpackers used across the UI files.
function Theme.RGB(c, alpha)
    if alpha == nil then return c[1], c[2], c[3] end
    return c[1], c[2], c[3], alpha
end
local RGB = Theme.RGB

-- Delayed hover tooltip where the caller populates GameTooltip themselves.
-- buildFn(self) runs 0.4s after mouse-enter (a short grace delay); the
-- owner/anchor is set for you. Returning nothing from buildFn shows nothing.
function Theme.DelayedTooltip(frame, buildFn, anchor)
    frame:HookScript("OnEnter", function(self)
        local token = (self._btlTip or 0) + 1
        self._btlTip = token
        local after = (Utils and Utils.SafeAfter) or C_Timer.After
        after(0.4, function()
            if self._btlTip ~= token or not self:IsMouseOver() then return end
            GameTooltip:SetOwner(self, anchor or "ANCHOR_RIGHT")
            buildFn(self)
            -- Suppress an empty tooltip when the callback added no lines
            -- (conditional tooltips that only populate in some states).
            if GameTooltip:NumLines() > 0 then
                GameTooltip:Show()
            else
                GameTooltip:Hide()
            end
        end)
    end)
    frame:HookScript("OnLeave", function(self)
        self._btlTip = (self._btlTip or 0) + 1
        GameTooltip:Hide()
    end)
end

-- Delayed hover tooltip shared by themed controls.
function Theme.AttachTooltip(frame, title, body)
    frame:HookScript("OnEnter", function(self)
        local token = (self._btlTip or 0) + 1
        self._btlTip = token
        local after = (Utils and Utils.SafeAfter) or C_Timer.After
        after(0.35, function()
            if self._btlTip ~= token or not self:IsMouseOver() then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if title then GameTooltip:SetText(title, RGB(C.TEXT_PRIMARY)) end
            if body then GameTooltip:AddLine(body, 0.85, 0.85, 0.85, true) end
            GameTooltip:Show()
        end)
    end)
    frame:HookScript("OnLeave", function(self)
        self._btlTip = (self._btlTip or 0) + 1
        GameTooltip:Hide()
    end)
end

--------------------------------------------------------------------------
-- 9-slice rounded rect: corners fixed at barHeight/2 (pill caps), edges
-- stretch. When container height == barHeight the silhouette is a pill.
--------------------------------------------------------------------------
local CR = 0.25
local TC9 = {
    tl = {0,      CR,     0,      CR    }, tm = {CR,     1 - CR, 0,      CR    }, tr = {1 - CR, 1,      0,      CR    },
    ml = {0,      CR,     CR,     1 - CR}, mm = {CR,     1 - CR, CR,     1 - CR}, mr = {1 - CR, 1,      CR,     1 - CR},
    bl = {0,      CR,     1 - CR, 1     }, bm = {CR,     1 - CR, 1 - CR, 1     }, br = {1 - CR, 1,      1 - CR, 1     },
}

local function CreateNineSlice(frame, layer, texPath, r, g, b, a)
    local n = {}
    local function P(name)
        local t = frame:CreateTexture(nil, layer)
        t:SetTexture(texPath)
        t:SetTexCoord(unpack(TC9[name]))
        t:SetVertexColor(r, g, b, a)
        return t
    end
    n.tl, n.tm, n.tr = P("tl"), P("tm"), P("tr")
    n.ml, n.mm, n.mr = P("ml"), P("mm"), P("mr")
    n.bl, n.bm, n.br = P("bl"), P("bm"), P("br")
    return n
end

local function AnchorNineSlice(n, cornerSize)
    n.tl:ClearAllPoints(); n.tl:SetPoint("TOPLEFT");     n.tl:SetSize(cornerSize, cornerSize)
    n.tr:ClearAllPoints(); n.tr:SetPoint("TOPRIGHT");    n.tr:SetSize(cornerSize, cornerSize)
    n.bl:ClearAllPoints(); n.bl:SetPoint("BOTTOMLEFT");  n.bl:SetSize(cornerSize, cornerSize)
    n.br:ClearAllPoints(); n.br:SetPoint("BOTTOMRIGHT"); n.br:SetSize(cornerSize, cornerSize)
    n.tm:ClearAllPoints(); n.tm:SetPoint("TOPLEFT", n.tl, "TOPRIGHT"); n.tm:SetPoint("BOTTOMRIGHT", n.tr, "BOTTOMLEFT")
    n.bm:ClearAllPoints(); n.bm:SetPoint("TOPLEFT", n.bl, "TOPRIGHT"); n.bm:SetPoint("BOTTOMRIGHT", n.br, "BOTTOMLEFT")
    n.ml:ClearAllPoints(); n.ml:SetPoint("TOPLEFT", n.tl, "BOTTOMLEFT"); n.ml:SetPoint("BOTTOMRIGHT", n.bl, "TOPRIGHT")
    n.mr:ClearAllPoints(); n.mr:SetPoint("TOPLEFT", n.tr, "BOTTOMLEFT"); n.mr:SetPoint("BOTTOMRIGHT", n.br, "TOPRIGHT")
    n.mm:ClearAllPoints(); n.mm:SetPoint("TOPLEFT", n.tl, "BOTTOMRIGHT"); n.mm:SetPoint("BOTTOMRIGHT", n.br, "TOPLEFT")
end

local function ApplyCornerSize(frame)
    if not frame.rr then return end
    local h = frame.rrBarHeight or frame:GetHeight() or 0
    if h <= 0 then return end
    local cornerSize = h / 2
    AnchorNineSlice(frame.rr.fill, cornerSize)
    AnchorNineSlice(frame.rr.border, cornerSize)
end

-- Attach a rounded-rect fill + border to a frame. Idempotent.
function Theme.Round(frame)
    if frame.rr then return frame end
    local fill   = CreateNineSlice(frame, "BACKGROUND", TEX_FILL,   0, 0, 0, 1)
    local border = CreateNineSlice(frame, "BORDER",     TEX_BORDER, C.BORDER[1], C.BORDER[2], C.BORDER[3], 1)
    frame.rr = { fill = fill, border = border }
    ApplyCornerSize(frame)
    frame:HookScript("OnSizeChanged", ApplyCornerSize)
    return frame
end

function Theme.SetBarHeight(frame, h)
    frame.rrBarHeight = h
    ApplyCornerSize(frame)
end

function Theme.SetFill(frame, r, g, b, a)
    if not (frame.rr and frame.rr.fill) then return end
    a = a or 1
    for _, t in pairs(frame.rr.fill) do
        t:SetVertexColor(r, g, b, a)
        t:SetAlpha(a)
    end
end

function Theme.SetFillColor(frame, color, a)
    Theme.SetFill(frame, color[1], color[2], color[3], a or color[4] or 1)
end

function Theme.SetBorderColor(frame, r, g, b, a)
    if not (frame.rr and frame.rr.border) then return end
    for _, t in pairs(frame.rr.border) do t:SetVertexColor(r, g, b, a or 1) end
end

function Theme.SetBorderShown(frame, shown)
    if not (frame.rr and frame.rr.border) then return end
    for _, t in pairs(frame.rr.border) do t:SetShown(shown) end
end

function Theme.SetFillAlpha(frame, alpha)
    if not (frame.rr and frame.rr.fill) then return end
    for _, t in pairs(frame.rr.fill) do t:SetAlpha(alpha) end
end

--------------------------------------------------------------------------
-- Rounded art overlay: crop an arbitrary texture (a real image) to the same
-- rounded-rect silhouette via a nine-slice. Only the four fixed-size corner
-- cells carry a circle-disc mask, so a wide bubble never stretches a mask
-- across its middle (which shatters the art); edge and centre cells are plain
-- crops. Masks are a standalone disc file, not an atlas region -- a MaskTexture
-- samples its whole file, so an atlas region mask samples the entire sheet.
--------------------------------------------------------------------------
local ART_MASK_TEX = "Interface\\AddOns\\BoundToLearn\\media\\FilterButtonCircle"
local ART_ANCHORS = { tl = "TOPLEFT", tr = "TOPRIGHT", bl = "BOTTOMLEFT", br = "BOTTOMRIGHT" }

local function UpdateArtCrop(frame)
    local art = frame.art
    if not art then return end
    local w, h = frame:GetWidth() or 0, frame:GetHeight() or 0
    if w <= 0 or h <= 0 then return end
    local c = art.corner or h * 0.3
    if c > h / 2 then c = h / 2 end
    if c > w / 2 then c = w / 2 end
    AnchorNineSlice(art.cells, c)
    local d = c * 2
    for _, mask in pairs(art.masks) do mask:SetSize(d, d) end
    -- Divide the base crop region across the nine cells in proportion to each
    -- cell's share of the frame, so the source image fills the bubble exactly.
    local tc = art.tc
    local bx1, bx2, by1, by2 = tc[1], tc[2], tc[3], tc[4]
    local fx, fy = c / w, c / h
    local ax1, ax2 = bx1 + (bx2 - bx1) * fx, bx2 - (bx2 - bx1) * fx
    local ay1, ay2 = by1 + (by2 - by1) * fy, by2 - (by2 - by1) * fy
    local n = art.cells
    n.tl:SetTexCoord(bx1, ax1, by1, ay1); n.tm:SetTexCoord(ax1, ax2, by1, ay1); n.tr:SetTexCoord(ax2, bx2, by1, ay1)
    n.ml:SetTexCoord(bx1, ax1, ay1, ay2); n.mm:SetTexCoord(ax1, ax2, ay1, ay2); n.mr:SetTexCoord(ax2, bx2, ay1, ay2)
    n.bl:SetTexCoord(bx1, ax1, ay2, by2); n.bm:SetTexCoord(ax1, ax2, ay2, by2); n.br:SetTexCoord(ax2, bx2, ay2, by2)
end

local function OnArtSizeChanged(frame)
    if frame.art and frame.art.cells.mm:IsShown() then UpdateArtCrop(frame) end
end

-- Attach the art nine-slice + corner masks to a frame. Idempotent.
function Theme.CreateArt(frame)
    if frame.art then return frame end
    local cells, masks = {}, {}
    for name in pairs(TC9) do
        local cell = frame:CreateTexture(nil, "ARTWORK", nil, 1)
        cell:Hide()
        local anchor = ART_ANCHORS[name]
        if anchor then
            local mask = frame:CreateMaskTexture()
            mask:SetTexture(ART_MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetPoint(anchor, cell, anchor)
            cell:AddMaskTexture(mask)
            masks[name] = mask
        end
        cells[name] = cell
    end
    frame.art = { cells = cells, masks = masks, tc = { 0, 1, 0, 1 } }
    frame:HookScript("OnSizeChanged", OnArtSizeChanged)
    return frame
end

-- Set the art texture and base crop (texcoords into the source), then reflow.
function Theme.SetArt(frame, tex, l, r, t, b)
    local art = frame.art
    if not art then return end
    for _, cell in pairs(art.cells) do cell:SetTexture(tex) end
    art.tc[1], art.tc[2], art.tc[3], art.tc[4] = l or 0, r or 1, t or 0, b or 1
    UpdateArtCrop(frame)
end

function Theme.SetArtCorner(frame, c)
    if not frame.art then return end
    frame.art.corner = c
    UpdateArtCrop(frame)
end

function Theme.SetArtVertexColor(frame, r, g, b, a)
    if not frame.art then return end
    for _, cell in pairs(frame.art.cells) do cell:SetVertexColor(r, g, b, a or 1) end
end

function Theme.ShowArt(frame, shown)
    if not frame.art then return end
    for _, cell in pairs(frame.art.cells) do cell:SetShown(shown) end
end

--------------------------------------------------------------------------
-- Panels wear the client's own frame art, body and border, so retail,
-- Forever and Era each show their native look: the dark dialog frame on
-- windows, the tooltip frame on menus and small panels.
--------------------------------------------------------------------------
local DIALOG_BG = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark"
local DIALOG_BG_INSET = 7

local function CreateWindowArt(frame)
    local art = CreateFrame("Frame", nil, frame, "NineSlicePanelTemplate")
    art:SetUsingParentLevel(true)
    -- Border over the window's own art; the client's default layer is under it.
    art.layoutTextureLayer = "OVERLAY"
    NineSliceUtil.ApplyLayoutByName(art, "Dialog")
    local bg = art:CreateTexture(nil, "BACKGROUND", nil, -5)
    bg:SetTexture(DIALOG_BG, "REPEAT", "REPEAT")
    bg:SetHorizTile(true)
    bg:SetVertTile(true)
    bg:SetPoint("TOPLEFT", DIALOG_BG_INSET, -DIALOG_BG_INSET)
    bg:SetPoint("BOTTOMRIGHT", -DIALOG_BG_INSET, DIALOG_BG_INSET)
    return art
end

local function CreateMenuArt(frame)
    local art = CreateFrame("Frame", nil, frame, "TooltipBackdropTemplate")
    art:SetAllPoints()
    art:SetUsingParentLevel(true)
    return art
end

-- One-call native panel (window bodies, popups). kind is "window" or
-- "menu"; a panel given an alpha is a menu.
-- Every styled panel, for the layout checker at the end of this file.
Theme.panels = {}

function Theme.StylePanel(frame, alpha, kind)
    if not frame._btlArt then
        kind = kind or (alpha and "menu" or "window")
        frame._btlKind = kind
        frame._btlArt = (kind == "window" and CreateWindowArt or CreateMenuArt)(frame)
        Theme.panels[#Theme.panels + 1] = frame
    end
    return frame
end

-- Flat rounded fill card (grouped settings, stat cards, insets). Borderless
-- by default: the rounded border ring aliases badly at small sizes, so cards
-- read by their fill contrast against the panel. Pass showBorder=true only
-- where a ring is deliberate (e.g. a gold reward frame).
function Theme.StyleCard(frame, color, barH, showBorder)
    Theme.Round(frame)
    Theme.SetBarHeight(frame, barH or 8)
    if showBorder then
        Theme.SetBorderShown(frame, true)
        Theme.SetBorderColor(frame, C.BORDER[1], C.BORDER[2], C.BORDER[3], 0.5)
    else
        Theme.SetBorderShown(frame, false)
    end
    Theme.SetFillColor(frame, color or C.SECTION_FILL)
    return frame
end

--------------------------------------------------------------------------
-- Buttons are the client's own, so each client shows its native art.
--------------------------------------------------------------------------
function Theme.CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    btn:SetSize(width or 120, height or 24)
    btn:SetText(text or "")
    btn._label = btn:GetFontString()
    return btn
end

-- The client has one button style; a primary action is told by its place.
Theme.CreateAccentButton = Theme.CreateButton

--------------------------------------------------------------------------
-- Checkbox: the client's own check art in a row that is clickable across
-- its whole width (SetChecked/GetChecked/OnClick as on any check button).
-- A row with no label holds the caller's own content, so its box sits right.
--------------------------------------------------------------------------
function Theme.CreateToggle(parent, labelText, tooltipText, width)
    local ROW_H, BOX = 26, 24
    local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonArtTemplate")
    cb:SetSize(width or 280, ROW_H)
    cb:RegisterForClicks("LeftButtonUp")

    local side = (labelText and labelText ~= "") and "LEFT" or "RIGHT"
    for _, art in ipairs({ cb:GetNormalTexture(), cb:GetPushedTexture(), cb:GetHighlightTexture(),
                           cb:GetCheckedTexture(), cb:GetDisabledCheckedTexture() }) do
        art:ClearAllPoints()
        art:SetPoint(side, cb, side, 0, 0)
        art:SetSize(BOX, BOX)
    end

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "LEFT", BOX - 2, 0)
    text:SetPoint("RIGHT", cb, "RIGHT", -2, 0)
    text:SetJustifyH("LEFT")
    text:SetText(labelText or "")
    cb.Text = text

    cb:HookScript("OnEnable", function() text:SetFontObject("GameFontHighlightSmall") end)
    cb:HookScript("OnDisable", function() text:SetFontObject("GameFontDisableSmall") end)
    if tooltipText then
        Theme.AttachTooltip(cb, labelText, tooltipText)
    end
    return cb
end

--------------------------------------------------------------------------
-- Close button (styled X, replaces UIPanelCloseButton)
--------------------------------------------------------------------------
function Theme.CreateCloseButton(parent, onClose)
    -- The client's own close button, to match its border art.
    local btn = CreateFrame("Button", nil, parent, "UIPanelCloseButtonNoScripts")
    btn:SetSize(22, 22)
    btn:SetFrameLevel(parent:GetFrameLevel() + 10)
    btn._btlEdgeOK = true   -- sits on the corner by design (layout check)
    btn:SetScript("OnClick", function()
        if Utils.PlayUISound then Utils.PlayUISound(Utils.SOUND_CLOSE) end
        if onClose then onClose() end
    end)
    return btn
end

--------------------------------------------------------------------------
-- Section title (gold heading) + hairline divider
--------------------------------------------------------------------------
function Theme.CreateSectionTitle(parent, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetText(text or "")
    fs:SetTextColor(RGB(C.GOLD, 1))
    return fs
end

function Theme.CreateDivider(parent, width)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetHeight(1)
    if width then line:SetWidth(width) end
    line:SetColorTexture(C.BORDER[1], C.BORDER[2], C.BORDER[3], 0.35)
    return line
end

-- Title FontString for a window header (cream, larger).
function Theme.CreateTitle(parent, text, size)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if size then
        local path, _, flags = fs:GetFont()
        if path then fs:SetFont(path, size, flags) end
    end
    fs:SetText(text or "")
    fs:SetTextColor(RGB(C.TEXT_PRIMARY, 1))
    return fs
end

--------------------------------------------------------------------------
-- Scrollbar restyle: dark thumb, no default arrow chrome.
--------------------------------------------------------------------------
--------------------------------------------------------------------------
-- Tab button with accent underline (SetActive drives the highlight)
--------------------------------------------------------------------------
function Theme.CreateTab(parent, text, fontObject, accentColor)
    local tab = CreateFrame("Button", nil, parent)
    local label = tab:CreateFontString(nil, "OVERLAY", fontObject or "GameFontNormal")
    label:SetPoint("CENTER", 0, 1)
    label:SetText(text or "")
    tab.label = label

    local ac = accentColor or C.ACCENT
    local underline = tab:CreateTexture(nil, "ARTWORK")
    underline:SetHeight(2)
    underline:SetPoint("BOTTOMLEFT", 4, 0)
    underline:SetPoint("BOTTOMRIGHT", -4, 0)
    underline:SetColorTexture(ac[1], ac[2], ac[3], 1)
    underline:Hide()
    tab.underline = underline
    tab:SetSize((label:GetStringWidth() or 40) + 24, 26)

    tab.SetActive = function(self, active)
        self.active = active
        underline:SetShown(active)
        label:SetTextColor(RGB(active and C.TEXT_PRIMARY or C.TEXT_DIM, 1))
    end
    tab:HookScript("OnEnter", function(self) if not self.active then label:SetTextColor(RGB(C.TEXT_BODY, 1)) end end)
    tab:HookScript("OnLeave", function(self) if not self.active then label:SetTextColor(RGB(C.TEXT_DIM, 1)) end end)
    tab:SetActive(false)
    return tab
end

--------------------------------------------------------------------------
-- Sleek horizontal slider using Blizzard's Minimal_SliderBar atlases (thin
-- track endcaps + stretch middle + diamond thumb).
-- Native Slider API: SetMinMaxValues/SetValue/GetValue/SetValueStep +
-- OnValueChanged.
--------------------------------------------------------------------------
function Theme.CreateSlider(parent, width, minV, maxV, step)
    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(width or 160, 20)
    slider:SetMinMaxValues(minV or 0, maxV or 1)
    slider:SetValueStep(step or 1)
    slider:SetObeyStepOnDrag(true)
    slider:EnableMouseWheel(false)

    local trackLeft = slider:CreateTexture(nil, "ARTWORK")
    trackLeft:SetAtlas("Minimal_SliderBar_Left", true)
    trackLeft:SetPoint("LEFT", 0, 0)
    local trackRight = slider:CreateTexture(nil, "ARTWORK")
    trackRight:SetAtlas("Minimal_SliderBar_Right", true)
    trackRight:SetPoint("RIGHT", 0, 0)
    local trackMid = slider:CreateTexture(nil, "ARTWORK")
    trackMid:SetAtlas("_Minimal_SliderBar_Middle", false)
    trackMid:SetPoint("LEFT", trackLeft, "RIGHT", 0, 0)
    trackMid:SetPoint("RIGHT", trackRight, "LEFT", 0, 0)
    local capH = trackLeft:GetHeight()
    trackMid:SetHeight((capH and capH > 0) and capH or 8)

    -- Need a real texture file before GetThumbTexture returns a valid object,
    -- then swap it to the Minimal diamond atlas.
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    if thumb then
        thumb:SetAtlas("Minimal_SliderBar_Button", true)
        thumb:SetSize(20, 19)
    end
    return slider
end

--------------------------------------------------------------------------
-- Triangle indicator (shared flat-triangle texture, points DOWN by default).
-- :SetDirection("down"/"right"/"up"/"left") rotates it (collapse carets,
-- prev/next arrows). SetRotation is counterclockwise.
--------------------------------------------------------------------------
local ARROW_TEX = "Interface\\AddOns\\BoundToLearn\\media\\filter-arrow"
local ARROW_ROT = { down = 0, right = mpi / 2, up = mpi, left = -mpi / 2 }
function Theme.CreateArrow(parent, size, color)
    local tex = parent:CreateTexture(nil, "OVERLAY")
    tex:SetSize(size or 12, size or 12)
    tex:SetTexture(ARROW_TEX)
    local c = color or C.ACCENT
    tex:SetVertexColor(c[1], c[2], c[3], c[4] or 1)
    tex.SetDirection = function(self, dir)
        self:SetRotation(ARROW_ROT[dir] or 0)
    end
    tex:SetDirection("down")
    return tex
end

function Theme.StyleScrollBar(scrollBar)
    if not scrollBar then return end
    -- Modern (retail) ScrollBar: has a Track/Thumb. Older: has Up/Down/Thumb.
    local thumb = scrollBar.GetThumb and scrollBar:GetThumb()
        or (scrollBar.ThumbTexture)
        or _G[(scrollBar:GetName() or "") .. "ThumbTexture"]
    if thumb and thumb.SetColorTexture then
        thumb:SetColorTexture(RGB(C.ACCENT_DIM, 0.9))
    end
    for _, part in ipairs({ "ScrollUpButton", "ScrollDownButton", "Back", "Forward" }) do
        local b = scrollBar[part] or _G[(scrollBar:GetName() or "") .. part]
        if b and b.Hide then b:Hide() end
    end
    -- Catch arrow buttons the named lookups miss (anonymous scrollbars): the classic
    -- thumb is a texture, so hiding Button children removes the arrows but keeps the thumb.
    for _, child in ipairs({ scrollBar:GetChildren() }) do
        if child.GetObjectType and child:GetObjectType() == "Button" then
            child:Hide()
        end
    end
end

--------------------------------------------------------------------------
-- Sidebar navigation: a left rail of stacked nav buttons plus a fixed
-- content region. One tab is shown at a time; picking a nav button swaps
-- the visible content frame. Fixed-size window model, no scrolling.
--------------------------------------------------------------------------
local IsMouseButtonDown = IsMouseButtonDown
local tostring = tostring

local function PaintNavButton(btn, state)
    if state == "active" then
        Theme.SetFill(btn, C.BTN_NORMAL[1], C.BTN_NORMAL[2], C.BTN_NORMAL[3], 1)
        btn.label:SetTextColor(RGB(C.TEXT_PRIMARY, 1))
    elseif state == "hover" then
        Theme.SetFill(btn, 1, 1, 1, 0.06)
        btn.label:SetTextColor(RGB(C.TEXT_BODY, 1))
    else
        Theme.SetFill(btn, 1, 1, 1, 0)
        btn.label:SetTextColor(RGB(C.TEXT_DIM, 1))
    end
end

function Theme.CreateSidebar(parent, opts)
    opts = opts or {}
    local width = opts.width or 132
    local inset = opts.inset or 10
    local contentTop = opts.contentTopInset or 46
    local contentRight = opts.contentRightInset or 14
    local contentBottom = opts.contentBottomInset or 14

    local nav = { buttons = {}, tabs = {}, current = 0 }

    local sidebar = CreateFrame("Frame", nil, parent)
    sidebar:SetPoint("TOPLEFT", parent, "TOPLEFT", inset, -inset)
    sidebar:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", inset, inset)
    sidebar:SetWidth(width)
    Theme.Round(sidebar)
    Theme.SetBarHeight(sidebar, 14)
    Theme.SetBorderShown(sidebar, false)
    Theme.SetFill(sidebar, 0.020, 0.019, 0.017, 1)
    nav.sidebar = sidebar

    local divider = parent:CreateTexture(nil, "ARTWORK")
    divider:SetPoint("TOPLEFT", sidebar, "TOPRIGHT", 8, -2)
    divider:SetPoint("BOTTOMLEFT", sidebar, "BOTTOMRIGHT", 8, 2)
    divider:SetWidth(1)
    divider:SetColorTexture(1, 1, 1, 0.08)

    if opts.title then
        local title = sidebar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        title:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 10, -10)
        title:SetText(opts.title)
        title:SetTextColor(RGB(C.TEXT_PRIMARY, 1))
        nav.title = title
    end

    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", width + 32, -contentTop)
    content:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -contentRight, contentBottom)
    nav.content = content

    function nav:SwitchToTab(index)
        self.current = index
        for i = 1, #self.tabs do
            self.tabs[i]:SetShown(i == index)
            PaintNavButton(self.buttons[i], i == index and "active" or "clear")
        end
    end

    function nav:AddTab(label)
        local index = #self.tabs + 1
        local btn = CreateFrame("Button", nil, sidebar)
        btn:SetSize(width - 16, 28)
        btn:SetPoint("TOPLEFT", sidebar, "TOPLEFT", 8, -34 - (index - 1) * 32)
        Theme.Round(btn)
        Theme.SetBarHeight(btn, 10)
        Theme.SetBorderShown(btn, false)
        btn._navIndex = index

        local lbl = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", btn, "LEFT", 10, 0)
        lbl:SetPoint("RIGHT", btn, "RIGHT", -10, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(label or "")
        btn.label = lbl
        PaintNavButton(btn, "clear")

        btn:SetScript("OnEnter", function(self)
            if nav.current ~= self._navIndex then PaintNavButton(self, "hover") end
        end)
        btn:SetScript("OnLeave", function(self)
            if nav.current ~= self._navIndex then PaintNavButton(self, "clear") end
        end)
        btn:SetScript("OnClick", function()
            if Utils.PlayUISound then Utils.PlayUISound(Utils.SOUND_TAB) end
            nav:SwitchToTab(index)
        end)
        self.buttons[index] = btn

        local tabContent = CreateFrame("Frame", nil, content)
        tabContent:SetAllPoints(content)
        tabContent:Hide()
        self.tabs[index] = tabContent
        return tabContent
    end

    return nav
end

--------------------------------------------------------------------------
-- Flyout dropdown: a pill selector button that drops a rounded panel of
-- option rows. A shared registry keeps only one open at a time; an open
-- panel closes on any click outside itself.
--------------------------------------------------------------------------
local openFlyouts = {}

local function FindWindow(frame)
    local f = frame
    while f do
        local p = f:GetParent()
        if not p or p == UIParent then return f end
        f = p
    end
    return frame
end

function Theme.CreateFlyoutSelector(parent, width, rightInset)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 160, 22)
    btn:SetPoint("RIGHT", parent, "RIGHT", -(rightInset or 8), 0)
    Theme.Round(btn)
    Theme.SetBarHeight(btn, 11)
    Theme.SetBorderShown(btn, false)
    Theme.SetFillColor(btn, C.BTN_NORMAL)

    local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetPoint("LEFT", btn, "LEFT", 8, 0)
    text:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
    text:SetJustifyH("CENTER")
    text:SetTextColor(RGB(C.TEXT_PRIMARY, 1))
    btn.text = text

    local caret = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    caret:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    caret:SetText("v")
    caret:SetTextColor(RGB(C.TEXT_DIM, 1))
    btn.caret = caret

    btn:SetScript("OnEnter", function(self) if self:IsEnabled() then Theme.SetFillColor(self, C.BTN_HOVER) end end)
    btn:SetScript("OnLeave", function(self) if self:IsEnabled() then Theme.SetFillColor(self, C.BTN_NORMAL) end end)
    return btn, text
end

function Theme.CreateFlyoutPanel(btnFrame, width, numRows)
    local flyout = CreateFrame("Frame", nil, btnFrame)
    openFlyouts[#openFlyouts + 1] = flyout
    flyout:SetSize(width or 160, (numRows or 1) * 20 + 6)
    flyout:SetPoint("TOPRIGHT", btnFrame, "BOTTOMRIGHT", 0, -2)
    local win = FindWindow(btnFrame)
    flyout:SetFrameStrata(win:GetFrameStrata())
    flyout:SetFrameLevel(win:GetFrameLevel() + 20)
    Theme.Round(flyout)
    Theme.SetBarHeight(flyout, 10)
    Theme.SetBorderShown(flyout, true)
    Theme.SetBorderColor(flyout, C.BORDER[1], C.BORDER[2], C.BORDER[3], 0.6)
    Theme.SetFill(flyout, 0.07, 0.065, 0.06, 1)
    flyout:Hide()

    btnFrame:SetScript("OnClick", function()
        local opening = not flyout:IsShown()
        if opening then
            for i = 1, #openFlyouts do
                if openFlyouts[i] ~= flyout then openFlyouts[i]:Hide() end
            end
        end
        flyout:SetShown(opening)
        if btnFrame.caret then btnFrame.caret:SetText(opening and "^" or "v") end
    end)
    flyout:SetScript("OnShow", function(self)
        self:SetFrameLevel(FindWindow(btnFrame):GetFrameLevel() + 20)
        self:SetScript("OnUpdate", function(self)
            if not self:IsMouseOver() and not btnFrame:IsMouseOver()
               and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")) then
                self:Hide()
            end
        end)
    end)
    flyout:SetScript("OnHide", function(self)
        self:SetScript("OnUpdate", nil)
        if btnFrame.caret then btnFrame.caret:SetText("v") end
    end)
    return flyout
end

function Theme.AddFlyoutOptions(flyout, choices, itemWidth, onSelect, labelFn, styleFn)
    local rows = {}
    for i = 1, #choices do
        local choice = choices[i]
        local optBtn = CreateFrame("Button", nil, flyout)
        optBtn:SetSize(itemWidth, 18)
        optBtn:SetPoint("TOPLEFT", flyout, "TOPLEFT", 3, -3 - (i - 1) * 20)
        local rowBg = CreateFrame("Frame", nil, optBtn)
        rowBg:SetAllPoints()
        rowBg:EnableMouse(false)
        Theme.Round(rowBg)
        Theme.SetBarHeight(rowBg, 9)
        Theme.SetBorderShown(rowBg, false)
        Theme.SetFill(rowBg, 1, 1, 1, 0)

        local lbl = optBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", optBtn, "LEFT", 6, 0)
        lbl:SetPoint("RIGHT", optBtn, "RIGHT", -6, 0)
        lbl:SetJustifyH("LEFT")
        lbl:SetText(labelFn and labelFn(choice) or choice.label)
        lbl:SetTextColor(RGB(C.TEXT_BODY, 1))
        optBtn._label = lbl
        if styleFn then styleFn(optBtn, choice, lbl) end

        optBtn:SetScript("OnEnter", function() Theme.SetFill(rowBg, 1, 1, 1, 0.08); lbl:SetTextColor(1, 1, 1, 1) end)
        optBtn:SetScript("OnLeave", function() Theme.SetFill(rowBg, 1, 1, 1, 0); lbl:SetTextColor(RGB(C.TEXT_BODY, 1)) end)
        optBtn:SetScript("OnClick", function()
            onSelect(choice)
            flyout:Hide()
        end)
        rows[i] = optBtn
    end

    local contentW = 0
    for i = 1, #rows do
        local lbl = rows[i]._label
        local getW = lbl.GetUnboundedStringWidth or lbl.GetStringWidth
        local w = 6 + getW(lbl) + 6 + (rows[i]._rightIconW or 0)
        if w > contentW then contentW = w end
    end
    local rowW = mmax(itemWidth, mfloor(contentW + 0.5))
    if rowW > itemWidth then
        for i = 1, #rows do rows[i]:SetWidth(rowW) end
        flyout:SetWidth(rowW + 6)
    end
    return rows
end

-- Labeled preset row: caption on the left, a flyout dropdown on the right.
-- choices are { {label=, value=}, ... }. opts: width, btnWidth, defaultValue,
-- tooltip, styleFn, format. Returns the row, which carries :SetValue for refresh.
function Theme.CreateFlyoutRow(parent, labelText, choices, getter, setter, opts)
    opts = opts or {}
    local rowW = opts.width or 330
    local btnW = opts.btnWidth or 170
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(rowW, 24)

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -btnW - 18, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(RGB(C.TEXT_BODY, 1))
    label:SetText(labelText or "")
    row.label = label

    local function LabelFor(value)
        for i = 1, #choices do
            if choices[i].value == value then return choices[i].label end
        end
        if opts.format then return opts.format(value) end
        return tostring(value)
    end
    local function FlyoutLabelFor(choice)
        if opts.defaultValue ~= nil and choice.value == opts.defaultValue then
            return choice.label .. " (" .. (_G["DEFAULT"] or "Default") .. ")"
        end
        return choice.label
    end

    local btn, btnText = Theme.CreateFlyoutSelector(row, btnW)

    -- Optional color swatch on the CLOSED selector: a small filled circle
    -- left of the label, tinted by opts.swatch(value). Used by the theme
    -- picker so the button shows the active accent, not just the name.
    local updateSwatch
    if opts.swatch then
        local dot = CreateFrame("Frame", nil, btn)
        dot:SetSize(12, 12)
        dot:SetPoint("LEFT", btn, "LEFT", 8, 0)
        Theme.Round(dot)
        Theme.SetBarHeight(dot, 12)
        Theme.SetBorderShown(dot, false)
        btnText:ClearAllPoints()
        btnText:SetPoint("LEFT", dot, "RIGHT", 6, 0)
        btnText:SetPoint("RIGHT", btn, "RIGHT", -18, 0)
        btnText:SetJustifyH("LEFT")
        updateSwatch = function(value)
            local col = opts.swatch(value)
            if col then Theme.SetFillColor(dot, col); dot:Show() else dot:Hide() end
        end
    end

    btnText:SetText(LabelFor(getter()))
    if updateSwatch then
        updateSwatch(getter())
    end
    local flyout = Theme.CreateFlyoutPanel(btn, btnW, #choices)
    Theme.AddFlyoutOptions(flyout, choices, btnW - 6, function(choice)
        setter(choice.value)
        btnText:SetText(LabelFor(choice.value))
        if updateSwatch then updateSwatch(choice.value) end
    end, FlyoutLabelFor, opts.styleFn)

    if opts.tooltip then
        row:EnableMouse(true)
        Theme.AttachTooltip(row, labelText, opts.tooltip)
    end

    row.flyout = flyout
    row.SetValue = function(_, value)
        btnText:SetText(LabelFor(value))
        if updateSwatch then updateSwatch(value) end
    end
    return row
end

--------------------------------------------------------------------------
-- Stepper row: label + [-] [numeric field] [+]. The field is typeable and
-- clamps to [minVal, maxVal] on commit. Exposes SetValue and SetGroupEnabled.
--------------------------------------------------------------------------
function Theme.CreateStepperRow(parent, labelText, minVal, maxVal, getter, setter, opts)
    opts = opts or {}
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(opts.width or 330, 28)
    row.enabled = true

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("LEFT", row, "LEFT", 8, 0)
    label:SetPoint("RIGHT", row, "RIGHT", -112, 0)
    label:SetJustifyH("LEFT")
    label:SetTextColor(RGB(C.TEXT_BODY, 1))
    label:SetText(labelText or "")

    local plusBtn = Theme.CreateButton(row, "+", 24, 20)
    plusBtn:SetPoint("RIGHT", row, "RIGHT", -8, 0)

    local shell = CreateFrame("Frame", nil, row)
    shell:SetSize(38, 20)
    shell:SetPoint("RIGHT", plusBtn, "LEFT", -4, 0)
    Theme.Round(shell)
    Theme.SetBarHeight(shell, 10)
    Theme.SetBorderShown(shell, false)
    Theme.SetFillColor(shell, C.INSET_FILL)

    local field = CreateFrame("EditBox", nil, shell)
    field:SetPoint("TOPLEFT", shell, "TOPLEFT", 4, 0)
    field:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -4, 0)
    field:SetFontObject("GameFontHighlightSmall")
    field:SetJustifyH("CENTER")
    field:SetAutoFocus(false)
    field:SetNumeric(true)
    field:SetMaxLetters(5)
    shell:EnableMouse(true)
    shell:SetScript("OnMouseDown", function() if row.enabled then field:SetFocus() end end)

    local minusBtn = Theme.CreateButton(row, "-", 24, 20)
    minusBtn:SetPoint("RIGHT", shell, "LEFT", -4, 0)

    local function clamp(v)
        v = mfloor((v or minVal) + 0.5)
        if v < minVal then v = minVal end
        if v > maxVal then v = maxVal end
        return v
    end
    local function commit(v)
        v = clamp(v)
        setter(v)
        field:SetText(tostring(v))
    end
    local function stepBy(delta)
        if row.enabled then commit((getter() or minVal) + delta) end
    end
    minusBtn:SetScript("OnClick", function() stepBy(-1) end)
    plusBtn:SetScript("OnClick", function() stepBy(1) end)
    field:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    field:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    field:SetScript("OnEscapePressed", function(self)
        self._cancel = true
        self:ClearFocus()
    end)
    field:SetScript("OnEditFocusLost", function(self)
        if self._cancel then
            self._cancel = nil
            self:SetText(tostring(clamp(getter())))
            return
        end
        if row.enabled then commit(self:GetNumber()) else self:SetText(tostring(clamp(getter()))) end
        self:HighlightText(0, 0)
    end)

    row.SetValue = function(_, v) field:SetText(tostring(clamp(v))) end
    row.SetGroupEnabled = function(self, enabled)
        self.enabled = enabled
        self:SetAlpha(enabled and 1 or 0.35)
        label:SetTextColor(RGB(enabled and C.TEXT_BODY or C.TEXT_DISABLED, 1))
        if enabled then
            minusBtn:Enable(); plusBtn:Enable(); field:Enable()
        else
            minusBtn:Disable(); plusBtn:Disable(); field:ClearFocus(); field:Disable()
        end
    end

    if opts.tooltip then
        row:EnableMouse(true)
        Theme.AttachTooltip(row, labelText, opts.tooltip)
    end
    field:SetText(tostring(clamp(getter())))
    return row
end

--------------------------------------------------------------------------
-- Settings-group card: a rounded fill card that owns a list of controls
-- and cascades enable/disable to them.
--------------------------------------------------------------------------
function Theme.CreateSettingsGroup(parent, width, height, color)
    local group = CreateFrame("Frame", nil, parent)
    group:SetSize(width, height)
    Theme.StyleCard(group, color or C.SECTION_FILL)
    group.controls = {}
    group.AddControl = function(self, control)
        if control then self.controls[#self.controls + 1] = control end
        return control
    end
    group.SetGroupEnabled = function(self, enabled)
        self:SetAlpha(enabled and 1 or 0.35)
        for i = 1, #self.controls do
            local control = self.controls[i]
            if control.SetGroupEnabled then
                control:SetGroupEnabled(enabled)
            elseif control.Enable and control.Disable then
                if enabled then control:Enable() else control:Disable() end
            end
        end
    end
    return group
end

--------------------------------------------------------------------------
-- Floating dialogs (confirm + copy-link). A shared scaffold builds a themed
-- panel that always draws above the addon's other windows -- including the
-- options window while it is temporarily raised for blacklist selection -- so
-- a dialog can never hide behind them. TOOLTIP strata sits above every window
-- strata; a high level plus Raise keeps it on top of same-strata frames.
--------------------------------------------------------------------------
local DIALOG_STRATA = "TOOLTIP"
local DIALOG_LEVEL = 5000

-- A themed panel with a title line and a close-X, floating above everything.
-- The caller fills in body/buttons. A named dialog closes on Escape
-- (Utils.CloseOnEscape). Returns the frame; call frame:Present()
-- to show it and re-assert its top-of-stack strata/level.
function Theme.CreateDialogShell(name, width, height)
    local f = CreateFrame("Frame", name, UIParent)
    f:SetSize(width, height)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:SetFrameStrata(DIALOG_STRATA)
    f:SetToplevel(true)
    f:SetFrameLevel(DIALOG_LEVEL)
    Theme.StylePanel(f)
    f:EnableMouse(true)
    if name then Utils.CloseOnEscape(f) end

    local titleFS = Theme.CreateTitle(f, "", 15)
    titleFS:SetPoint("TOP", 0, -14)
    f.titleFS = titleFS

    local close = Theme.CreateCloseButton(f, function() f:Hide() end)
    close:SetPoint("TOPRIGHT", -8, -8)
    f.closeBtn = close

    f.Present = function(self)
        self:SetFrameStrata(DIALOG_STRATA)
        self:SetFrameLevel(DIALOG_LEVEL)
        self:Show()
        self:Raise()
    end
    return f
end

-- Shared confirmation dialog: title + body + Accept/Cancel. opts =
-- { title, body, acceptText, onAccept }. One reusable frame for every confirm.
local confirmDialog
function Theme.ShowConfirm(opts)
    opts = opts or {}
    if not confirmDialog then
        confirmDialog = Theme.CreateDialogShell("BoundToLearnConfirmDialog", 360, 150)

        local body = confirmDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", confirmDialog, "TOPLEFT", 20, -44)
        body:SetPoint("TOPRIGHT", confirmDialog, "TOPRIGHT", -20, -44)
        body:SetJustifyH("CENTER")
        body:SetSpacing(3)
        body:SetTextColor(RGB(C.TEXT_BODY, 1))
        confirmDialog.body = body

        -- Accept (accent) on the left, Cancel (neutral) on the right, matching
        -- the default button1/button2 order the old popups used.
        local accept = Theme.CreateAccentButton(confirmDialog, "", 140, 26)
        accept:SetPoint("BOTTOMRIGHT", confirmDialog, "BOTTOM", -6, 16)
        confirmDialog.accept = accept

        local cancel = Theme.CreateButton(confirmDialog, _G["CANCEL"] or "Cancel", 110, 26)
        cancel:SetPoint("BOTTOMLEFT", confirmDialog, "BOTTOM", 6, 16)
        cancel:SetScript("OnClick", function() confirmDialog:Hide() end)
        confirmDialog.cancel = cancel
    end

    confirmDialog.titleFS:SetText(opts.title or "")
    confirmDialog.body:SetText(opts.body or "")
    confirmDialog.accept:SetText(opts.acceptText or (_G["OKAY"] or "OK"))
    local onAccept = opts.onAccept
    confirmDialog.accept:SetScript("OnClick", function()
        confirmDialog:Hide()
        if onAccept then onAccept() end
    end)

    -- Grow to fit the body so long confirmations are not clipped.
    local bodyH = confirmDialog.body:GetStringHeight() or 40
    confirmDialog:SetHeight(mfloor(bodyH + 0.5) + 108)
    confirmDialog:Present()
end

-- Shared input dialog: title + body + a typeable field + Accept/Cancel. opts =
-- { title, body, acceptText, maxLetters, onAccept(text) }. Enter or Accept
-- commits the typed text; Escape or Cancel dismisses.
local promptDialog
function Theme.ShowPrompt(opts)
    opts = opts or {}
    if not promptDialog then
        promptDialog = Theme.CreateDialogShell("BoundToLearnPromptDialog", 340, 158)

        local body = promptDialog:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOP", promptDialog.titleFS, "BOTTOM", 0, -10)
        body:SetPoint("LEFT", promptDialog, "LEFT", 20, 0)
        body:SetPoint("RIGHT", promptDialog, "RIGHT", -20, 0)
        body:SetJustifyH("CENTER")
        body:SetTextColor(RGB(C.TEXT_BODY, 1))
        promptDialog.body = body

        local shell = CreateFrame("Frame", nil, promptDialog)
        shell:SetSize(280, 22)
        shell:SetPoint("TOP", body, "BOTTOM", 0, -12)
        Theme.Round(shell)
        Theme.SetBarHeight(shell, 10)
        Theme.SetBorderShown(shell, false)
        Theme.SetFillColor(shell, C.INSET_FILL)
        local eb = CreateFrame("EditBox", nil, shell)
        eb:SetPoint("TOPLEFT", shell, "TOPLEFT", 8, 0)
        eb:SetPoint("BOTTOMRIGHT", shell, "BOTTOMRIGHT", -8, 0)
        eb:SetAutoFocus(false)
        eb:SetFontObject("GameFontHighlight")
        eb:SetTextColor(0.95, 0.95, 0.95, 1)
        promptDialog.editBox = eb

        local function commit()
            local val = promptDialog.editBox:GetText()
            local cb = promptDialog._onAccept
            promptDialog:Hide()
            if cb then cb(val) end
        end
        eb:SetScript("OnEnterPressed", commit)
        eb:SetScript("OnEscapePressed", function() promptDialog:Hide() end)

        local accept = Theme.CreateAccentButton(promptDialog, "", 120, 26)
        accept:SetPoint("BOTTOMRIGHT", promptDialog, "BOTTOM", -6, 16)
        accept:SetScript("OnClick", commit)
        promptDialog.accept = accept

        local cancel = Theme.CreateButton(promptDialog, _G["CANCEL"] or "Cancel", 110, 26)
        cancel:SetPoint("BOTTOMLEFT", promptDialog, "BOTTOM", 6, 16)
        cancel:SetScript("OnClick", function() promptDialog:Hide() end)
    end

    promptDialog.titleFS:SetText(opts.title or "")
    promptDialog.body:SetText(opts.body or "")
    promptDialog.accept:SetText(opts.acceptText or (_G["OKAY"] or "OK"))
    promptDialog.editBox:SetMaxLetters(opts.maxLetters or 64)
    promptDialog.editBox:SetText("")
    promptDialog._onAccept = opts.onAccept
    promptDialog:SetHeight(158)
    promptDialog:Present()
    promptDialog.editBox:SetFocus()
end

--------------------------------------------------------------------------
-- Accent family: the client's own gold, for the few themed pieces left.
--------------------------------------------------------------------------
local function setC(key, r, g, b)
    local t = C[key]
    t[1], t[2], t[3] = r, g, b
end
setC("ACCENT", 1.00, 0.82, 0.00)
setC("ACCENT_DIM", 0.48, 0.39, 0.00)
setC("ACCENT_BRIGHT", 1.00, 0.90, 0.35)
Theme.ACCENT_HEX = "FFD100"

ns.Theme = Theme

--------------------------------------------------------------------------
do
-- Layout checker (/btl layoutcheck): opens every screen in turn, reads the
-- live screen rectangles of everything inside the addon's shown panels and
-- reports controls or text that sit on top of each other or are crowded.
-- "/btl layoutcheck here" checks only what is open. Findings also go to
-- BoundToLearnDB.layoutReport.
local LayoutCheck = {}
ns.LayoutCheck = LayoutCheck

local Utils = ns.Utils
local sformat, mmax, mmin, mfloor = Utils.sformat, Utils.mmax, Utils.mmin, Utils.mfloor
local tinsert, ipairs = Utils.tinsert, Utils.ipairs

local MIN_OVERLAP = 3          -- screen pixels on both axes before it counts
local MIN_GAP = 4              -- controls on one row closer than this are crowded
-- Border art is drawn inside the frame: content closer than this to an edge
-- sits on it (UI units; the Dialog metal band, the tooltip edge).
local EDGE = { window = 14, menu = 5 }
local CONTROL_TYPES = { Button = true, CheckButton = true, EditBox = true, Slider = true }

local function Label(obj)
    local text = obj.GetText and obj:GetText()
    if (not text or text == "") and obj.GetFontString then
        local fs = obj:GetFontString()
        text = fs and fs:GetText()
    end
    text = text and text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("^%s+", "")
    if text and text ~= "" then return '"' .. text:sub(1, 28) .. '"' end
    return obj:GetDebugName():match("[^%.]+$") or obj:GetObjectType()
end

-- Screen rectangle of what is drawn: text uses its real width, not its anchors.
local function ScreenRect(obj, isText)
    local left, bottom, width, height = obj:GetRect()
    if not left or width <= 0 or height <= 0 then return nil end
    if isText then
        local textW = mmin(width, obj:GetStringWidth())
        local textH = mmin(height, obj:GetStringHeight())
        local justify = obj:GetJustifyH()
        if justify == "CENTER" then
            left = left + (width - textW) / 2
        elseif justify == "RIGHT" then
            left = left + width - textW
        end
        bottom = bottom + (height - textH) / 2
        width, height = textW, textH
    end
    local scale = obj:GetEffectiveScale()
    return left * scale, bottom * scale, (left + width) * scale, (bottom + height) * scale
end

local function Clip(l, b, r, t, clip)
    if not clip then return l, b, r, t end
    return mmax(l, clip[1]), mmax(b, clip[2]), mmin(r, clip[3]), mmin(t, clip[4])
end

local function Shown(obj)
    return obj:IsVisible() and obj:GetEffectiveAlpha() > 0.05
end

-- Walk a panel: collect controls and texts with their clipped screen rects.
local function Collect(frame, items, clip, panelArea)
    if frame._btlNoLayoutCheck or not Shown(frame) then return end
    if frame.DoesClipChildren and frame:DoesClipChildren() then
        local l, b, r, t = ScreenRect(frame)
        if l then clip = { Clip(l, b, r, t, clip) } end
    end
    -- A control's own label is covered by the control's rectangle.
    local ownText = not CONTROL_TYPES[frame:GetObjectType()]
    for _, region in ipairs({ frame:GetRegions() }) do
        if ownText and region:GetObjectType() == "FontString" and Shown(region) and (region:GetText() or "") ~= "" then
            local l, b, r, t = ScreenRect(region, true)
            if l then
                l, b, r, t = Clip(l, b, r, t, clip)
                if r - l > 0 and t - b > 0 then
                    tinsert(items, { obj = region, owner = frame, text = true, l, b, r, t })
                end
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if CONTROL_TYPES[child:GetObjectType()] and Shown(child) and not child._btlNoLayoutCheck then
            local l, b, r, t = ScreenRect(child)
            if l then
                l, b, r, t = Clip(l, b, r, t, clip)
                -- A catcher or backdrop the size of the panel is not a control.
                if r - l > 0 and t - b > 0 and (r - l) * (t - b) < panelArea * 0.5 then
                    tinsert(items, { obj = child, owner = child, l, b, r, t })
                end
            end
        end
        Collect(child, items, clip, panelArea)
    end
end

local function Inside(frame, ancestor)
    while frame do
        if frame == ancestor then return true end
        frame = frame:GetParent()
    end
    return false
end

-- A control's own label, or something built inside it, is not an overlap.
local function Related(a, b)
    return Inside(a.owner, b.owner) or Inside(b.owner, a.owner)
end

-- Content on the border art of the panel it sits in. Things wholly outside
-- the panel (tabs hung below it) are deliberate and not reported.
local EDGE_NAMES = { "left", "bottom", "right", "top" }
local function OnBorder(item, isPanel)
    local host, f = nil, item.owner
    while f and not host do
        if f._btlEdgeOK then return end
        if isPanel[f] then host = f end
        f = f:GetParent()
    end
    if not host then return end
    local hl, hb, hr, ht = ScreenRect(host)
    if not hl then return end
    local l, b, r, t = item[1], item[2], item[3], item[4]
    if r <= hl or l >= hr or t <= hb or b >= ht then return end
    local gaps = { l - hl, b - hb, hr - r, ht - t }
    local side = 1
    for i = 2, 4 do
        if gaps[i] < gaps[side] then side = i end
    end
    local scale = host:GetEffectiveScale()
    local need = EDGE[host._btlKind] or EDGE.window
    if gaps[side] / scale < need then
        return sformat("%s sits on the border of %s (%d from the %s edge, needs %d)",
            Label(item.obj), Label(host), mfloor(gaps[side] / scale), EDGE_NAMES[side], need)
    end
end

function LayoutCheck:Scan()
    local found = {}
    local isPanel = {}
    for _, panel in ipairs(ns.Theme.panels) do isPanel[panel] = true end
    for _, panel in ipairs(ns.Theme.panels) do
        -- A panel inside another panel is covered by the outer one's walk.
        local nested, up = false, panel:GetParent()
        while up do
            if isPanel[up] then nested = true break end
            up = up:GetParent()
        end
        if Shown(panel) and not nested then
            local pl, pb, pr, pt = ScreenRect(panel)
            if pl then
                local items = {}
                Collect(panel, items, nil, (pr - pl) * (pt - pb))
                for i = 1, #items do
                    local a = items[i]
                    local border = OnBorder(a, isPanel)
                    if border then tinsert(found, border) end
                    for j = i + 1, #items do
                        local b = items[j]
                        -- Text on text inside one frame is a deliberate stack more often than not.
                        if not (a.text and b.text and a.owner == b.owner) and not Related(a, b) then
                            local w = mmin(a[3], b[3]) - mmax(a[1], b[1])
                            local h = mmin(a[4], b[4]) - mmax(a[2], b[2])
                            if w >= MIN_OVERLAP and h >= MIN_OVERLAP then
                                tinsert(found, sformat("%s over %s (%dx%d px) in %s",
                                    Label(a.obj), Label(b.obj), mfloor(w), mfloor(h), Label(panel)))
                            elseif not a.text and not b.text and h >= MIN_OVERLAP and w > -MIN_GAP then
                                -- Side by side on one row with next to no gap.
                                tinsert(found, sformat("%s crowds %s (%d px gap) in %s",
                                    Label(a.obj), Label(b.obj), mfloor(mmax(0, -w)), Label(panel)))
                            end
                        end
                    end
                end
            end
        end
    end
    return found
end

-- Screens the sweep can open by itself. Rounds in play (the in-round HUD,
-- a quiz round, a ping round) are left out: they take over the action bars.
local FAKE_RESULTS = {
    score = 1362, maxCombo = 15, totalNotes = 30, chartTotal = 96, notesShown = 30,
    difficulty = "Medium", mode = "practice", duration = 60,
    hitCounts = { perfect = 13, great = 12, good = 3, miss = 2, redHerring = 0 },
}

local function HideNamed(name)
    local frame = _G[name]
    if frame then frame:Hide() end
end

local function BuildScreens()
    local GameUI, screens = ns.GameUI, {}
    local function add(name, open, close) tinsert(screens, { name = name, open = open, close = close }) end

    add("minimap menu", function() HideNamed("BoundToLearnMinimapMenu"); BoundToLearn:ShowMinimapMenu() end,
        function() HideNamed("BoundToLearnMinimapMenu") end)
    add("welcome", function() BoundToLearn:ShowWelcome() end, function() HideNamed("BoundToLearnWelcome") end)
    add("start confirm", function() BoundToLearn.ShowGameConfirm() end, function() HideNamed("BoundToLearnGameConfirm") end)
    -- The quiz start screen; the bars are only taken once a mode is picked.
    add("quiz start", function() ns.KeybindQuiz:Start() end, function() ns.KeybindQuiz:CancelReady() end)

    add("game menu", function() GameUI:Initialize(); GameUI:ShowMainMenu() end, function() GameUI:HideMainMenu() end)
    add("track select", function() GameUI:ShowSongSelect() end)
    add("stats summary", function() GameUI:ShowStatsPage(); GameUI:SetStatsView("summary") end)
    add("stats by song", function() GameUI:SetStatsView("song") end, function() GameUI:HideStatsPage() end)
    local keptResults
    add("round over", function()
        keptResults = GameUI.lastResults
        GameUI:ShowResultsOnSelect(FAKE_RESULTS)
    end, function()
        GameUI:ExitResultsMode()
        GameUI.lastResults = keptResults
        GameUI:HideSongSelect()
    end)

    ns.Options:Show()
    local nav = BoundToLearnOptionsFrame.nav
    for i = 1, #nav.buttons do
        add("options tab " .. i, function() ns.Options:Show(); nav:SwitchToTab(i) end,
            i == #nav.buttons and function() ns.Options:Hide() end or nil)
    end
    ns.Options:Hide()

    for _, key in ipairs({ "tracker", "game", "quiz" }) do
        add("statistics: " .. key, function() ns.StatsUI:Show(); ns.StatsUI:SetTab(key) end,
            key == "quiz" and function() ns.StatsUI:Hide() end or nil)
    end

    local Audit = ns.KeybindAuditUI
    add("audit setup", function() Audit:Show(); Audit:ShowSetup() end)
    add("audit results", function() Audit:ShowResults() end)
    add("audit methodology", function() Audit:ToggleMethodology() end,
        function() Audit:ToggleMethodology(); Audit:Hide() end)

    add("ping trainer", function() HideNamed("BoundToLearnPingGame"); ns.PingGameUI:Toggle() end,
        function() HideNamed("BoundToLearnPingGame") end)
    return screens
end

local function Record(line)
    Utils.Print(line)
    local log = BoundToLearnDB.layoutReport
    log[#log + 1] = line
end

-- Scan what is on screen now and record it under a screen name.
local function ScanScreen(name)
    local found = LayoutCheck:Scan()
    for _, line in ipairs(found) do Record(sformat("[%s] %s", name, line)) end
    return #found
end

local SETTLE = 0.35   -- seconds for a screen to lay out before it is read
local sweeping = false

function LayoutCheck:Run(arg)
    BoundToLearnDB.layoutReport = {}
    if arg == "here" then
        if ScanScreen("open now") == 0 then Utils.Print("No overlaps in what is open now.") end
        return
    end
    if sweeping then return end
    if InCombatLockdown() then
        Utils.Print("Layout check runs out of combat.")
        return
    end

    local screens = BuildScreens()
    local index, total, failed = 0, 0, 0
    sweeping = true
    Utils.Print(sformat("Layout check: opening %d screens, hands off for %d seconds.",
        #screens, mfloor(#screens * SETTLE) + 1))

    local function Step()
        local prev = screens[index]
        if prev then
            if not prev.skip then total = total + ScanScreen(prev.name) end
            if prev.close then pcall(prev.close) end
        end
        index = index + 1
        local screen = screens[index]
        if not screen or InCombatLockdown() then
            sweeping = false
            Record(sformat("Layout check done: %d findings on %d screens, %d could not open.",
                total, index - 1, failed))
            return
        end
        -- One broken screen must not end the sweep; it is reported instead.
        local ok, err = pcall(screen.open)
        if not ok then
            failed = failed + 1
            Record(sformat("[%s] could not open: %s", screen.name, tostring(err)))
            screens[index] = { name = screen.name, close = screen.close, skip = true }
        end
        C_Timer.After(SETTLE, Step)
    end
    Step()
end
end
