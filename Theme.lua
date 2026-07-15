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
local mmin, mmax, mfloor = math.min, math.max, math.floor
local mpi = math.pi
local CreateColor = CreateColor

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
    TOGGLE_ON        = {0.92, 0.50, 0.16},
    TOGGLE_ON_DIS    = {0.42, 0.26, 0.12},
    TOGGLE_OFF       = {0.23, 0.22, 0.21},
    TOGGLE_OFF_DIS   = {0.14, 0.13, 0.12},
    KNOB             = {0.97, 0.96, 0.95},

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

--------------------------------------------------------------------------
-- Live retint: themed elements register a closure that re-applies their
-- accent-family colors from Theme.C. Theme.ApplyTheme mutates the palette in
-- place, then runs every registered closure so already-built frames recolor
-- without a reload. Each run is guarded so one bad element cannot break the
-- pass; registration is once-per-frame so the registry stays bounded.
--------------------------------------------------------------------------
Theme._retinters = {}
function Theme.RegisterRetinter(fn)
    Theme._retinters[#Theme._retinters + 1] = fn
end

function Theme.RunRetinters()
    local rt = Theme._retinters
    for i = 1, #rt do
        pcall(rt[i])
    end
end

-- The exact C tables ApplyTheme mutates. A rounded-rect fill painted from one
-- of these must retint; fills from fixed neutrals (greys, dark chrome, knob,
-- gold, insets) never change hue and are left alone.
local THEMED_FILLS = {
    [C.ACCENT] = true, [C.ACCENT_DIM] = true, [C.ACCENT_BRIGHT] = true,
    [C.TOGGLE_ON] = true, [C.TOGGLE_ON_DIS] = true,
    [C.BTN_NORMAL] = true, [C.BTN_HOVER] = true, [C.BTN_PRESSED] = true,
}

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
    -- Remember accent-family fills (matched by table identity) so a later
    -- theme switch can re-apply them live. Register once per frame.
    if THEMED_FILLS[color] then
        frame._themedFill = color
        frame._themedFillAlpha = a
        if not frame._fillRetinter then
            frame._fillRetinter = true
            Theme.RegisterRetinter(function()
                local col = frame._themedFill
                if col and frame.rr then
                    Theme.SetFill(frame, col[1], col[2], col[3],
                        frame._themedFillAlpha or col[4] or 1)
                end
            end)
        end
    else
        frame._themedFill = nil
    end
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
-- Panel gloss: single vertical gradient sampled per 9-slice cell, brightness
-- ramp packed into the bottom 10% so banding collapses to a few pixels.
--------------------------------------------------------------------------
local GLOSS_DARK_FRAC = 0.90
local function Smoothstep(t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    return t * t * (3 - 2 * t)
end
local function Lerp(a, b, t) return a + (b - a) * t end

local function GlossColorAt(y, height, base, top)
    local t = y / height
    if t < GLOSS_DARK_FRAC then
        t = 0
    else
        t = Smoothstep((t - GLOSS_DARK_FRAC) / (1 - GLOSS_DARK_FRAC))
    end
    return Lerp(base[1], top[1], t), Lerp(base[2], top[2], t), Lerp(base[3], top[3], t)
end

local function GlossRamp(cell, yTop, yBot, height, base, top)
    if not cell then return end
    local r1, g1, b1 = GlossColorAt(yTop, height, base, top)
    local r2, g2, b2 = GlossColorAt(yBot, height, base, top)
    cell:SetGradient("VERTICAL", CreateColor(r2, g2, b2, 1), CreateColor(r1, g1, b1, 1))
end

local GLOSS_BASE = {0.036, 0.033, 0.030}
local GLOSS_TOP  = {0.22, 0.15, 0.09}

local function ApplyGloss(frame)
    local fill = frame.rr and frame.rr.fill
    if not fill then return end
    local height = frame:GetHeight()
    if not height or height <= 0 then return end
    local corner = (frame.rrBarHeight or 32) / 2
    GlossRamp(fill.tl, 0, corner, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.tm, 0, corner, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.tr, 0, corner, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.ml, corner, height - corner, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.mm, corner, height - corner, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.mr, corner, height - corner, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.bl, height - corner, height, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.bm, height - corner, height, height, GLOSS_BASE, GLOSS_TOP)
    GlossRamp(fill.br, height - corner, height, height, GLOSS_BASE, GLOSS_TOP)
end
Theme.ApplyGloss = ApplyGloss

-- One-call dark glossy panel background (window bodies, popups). The outline is
-- the addon's own soft rounded-rect nine-slice (the same CombinedBorder texture
-- the search results window uses), not a low-res tooltip/dialog edge.
function Theme.StylePanel(frame, alpha)
    Theme.Round(frame)
    Theme.SetBarHeight(frame, 24)
    Theme.SetBorderShown(frame, true)
    Theme.SetFill(frame, 0.045, 0.042, 0.038, 1)
    Theme.SetFillAlpha(frame, alpha or 1)
    ApplyGloss(frame)
    if not frame._btlGlossHooked then
        frame._btlGlossHooked = true
        frame:HookScript("OnSizeChanged", ApplyGloss)
        -- The bottom sheen is tinted from the accent; re-apply it on a switch.
        Theme.RegisterRetinter(function() ApplyGloss(frame) end)
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
-- Modern pill button
--------------------------------------------------------------------------
function Theme.CreateButton(parent, text, width, height)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(width or 120, height or 24)
    Theme.Round(btn)
    Theme.SetBarHeight(btn, mmin(height or 24, 11))
    Theme.SetBorderShown(btn, false)
    Theme.SetFillColor(btn, C.BTN_NORMAL)

    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("CENTER")
    label:SetText(text or "")
    label:SetTextColor(RGB(C.TEXT_PRIMARY, 1))
    btn._label = label
    btn.SetText = function(self, v) self._label:SetText(v or "") end
    btn.GetText = function(self) return self._label:GetText() or "" end
    btn.SetTextColor = function(self, ...) self._label:SetTextColor(...) end

    local function paint(color)
        if btn:IsEnabled() then Theme.SetFillColor(btn, color) end
    end
    btn:SetScript("OnEnter", function() paint(C.BTN_HOVER) end)
    btn:SetScript("OnLeave", function() paint(C.BTN_NORMAL) end)
    btn:SetScript("OnMouseDown", function() paint(C.BTN_PRESSED) end)
    btn:SetScript("OnMouseUp", function()
        paint(btn:IsMouseOver() and C.BTN_HOVER or C.BTN_NORMAL)
    end)
    btn:HookScript("OnDisable", function() Theme.SetFillColor(btn, C.BTN_DISABLED); label:SetTextColor(RGB(C.TEXT_DISABLED, 1)) end)
    btn:HookScript("OnEnable", function() Theme.SetFillColor(btn, C.BTN_NORMAL); label:SetTextColor(RGB(C.TEXT_PRIMARY, 1)) end)
    return btn
end

-- Primary (accent-filled) action button variant.
function Theme.CreateAccentButton(parent, text, width, height)
    local btn = Theme.CreateButton(parent, text, width, height)
    local function paint(color) if btn:IsEnabled() then Theme.SetFillColor(btn, color) end end
    Theme.SetFillColor(btn, C.ACCENT_DIM)
    btn:SetScript("OnEnter", function() paint(C.ACCENT) end)
    btn:SetScript("OnLeave", function() paint(C.ACCENT_DIM) end)
    btn:SetScript("OnMouseDown", function() paint(C.ACCENT_DIM) end)
    btn:SetScript("OnMouseUp", function() paint(btn:IsMouseOver() and C.ACCENT or C.ACCENT_DIM) end)
    btn._label:SetTextColor(1, 1, 1, 1)
    return btn
end

--------------------------------------------------------------------------
-- Toggle switch (drop-in for a check button: SetChecked/GetChecked/OnClick)
--------------------------------------------------------------------------
function Theme.CreateToggle(parent, labelText, tooltipText, width)
    local ROW_H, TW, TH = 26, 32, 16
    local KNOB = TH - 2
    local cb = CreateFrame("CheckButton", nil, parent)
    cb:SetSize(width or 280, ROW_H)
    cb:RegisterForClicks("LeftButtonUp")

    local text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    text:SetPoint("LEFT", cb, "LEFT", 2, 0)
    text:SetJustifyH("LEFT")
    text:SetText(labelText or "")
    cb.Text = text

    local track = CreateFrame("Frame", nil, cb)
    track:SetSize(TW, TH)
    track:SetPoint("RIGHT", cb, "RIGHT", -2, 0)
    Theme.Round(track)
    Theme.SetBarHeight(track, TH)
    Theme.SetBorderShown(track, false)
    cb.track = track
    text:SetPoint("RIGHT", track, "LEFT", -8, 0)

    local knob = CreateFrame("Frame", nil, track)
    knob:SetSize(KNOB, KNOB)
    Theme.Round(knob)
    Theme.SetBarHeight(knob, KNOB)
    Theme.SetBorderShown(knob, false)
    Theme.SetFillColor(knob, C.KNOB)
    cb.knob = knob

    local function paint(self)
        local enabled = self:IsEnabled()
        local checked = self:GetChecked()
        if checked and enabled then
            Theme.SetFillColor(track, C.TOGGLE_ON); text:SetTextColor(1, 1, 1, 1)
        elseif checked then
            Theme.SetFillColor(track, C.TOGGLE_ON_DIS); text:SetTextColor(0.55, 0.55, 0.55, 1)
        elseif enabled then
            Theme.SetFillColor(track, C.TOGGLE_OFF); text:SetTextColor(RGB(C.TEXT_BODY, 1))
        else
            Theme.SetFillColor(track, C.TOGGLE_OFF_DIS); text:SetTextColor(0.45, 0.45, 0.45, 1)
        end
        knob:ClearAllPoints()
        knob:SetPoint(checked and "RIGHT" or "LEFT", track, checked and "RIGHT" or "LEFT", checked and -1 or 1, 0)
    end

    local rawSet = cb.SetChecked
    cb.SetChecked = function(self, v) rawSet(self, v) paint(self) end
    cb.RefreshVisual = paint
    local rawSetScript = cb.SetScript
    cb.SetScript = function(self, t, h)
        if t == "OnClick" and h then
            rawSetScript(self, "OnClick", function(s, ...) paint(s) h(s, ...) end)
        else
            rawSetScript(self, t, h)
        end
    end
    cb:HookScript("OnClick", paint)
    cb:HookScript("OnEnable", paint)
    cb:HookScript("OnDisable", paint)
    if tooltipText then
        Theme.AttachTooltip(cb, labelText, tooltipText)
    end
    paint(cb)
    -- Re-run the on/off visual on a theme switch so the accent track recolors.
    Theme.RegisterRetinter(function() if cb.track then paint(cb) end end)
    return cb
end

--------------------------------------------------------------------------
-- Close button (styled X, replaces UIPanelCloseButton)
--------------------------------------------------------------------------
function Theme.CreateCloseButton(parent, onClose)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(18, 18)
    -- Two rotated strokes make the x; no button shape, just the mark itself,
    -- faint at rest and lighting up on hover. Strokes track the button size so
    -- callers can resize freely.
    local function MakeStroke()
        local t = btn:CreateTexture(nil, "OVERLAY")
        t:SetTexture("Interface\\Buttons\\WHITE8x8")
        t:SetPoint("CENTER")
        return t
    end
    local s1 = MakeStroke(); s1:SetRotation(math.pi / 4)
    local s2 = MakeStroke(); s2:SetRotation(-math.pi / 4)
    local function SizeStrokes(w, h)
        local len = mmin(w, h) * 0.62   -- smaller mark with padding, not edge-to-edge
        s1:SetSize(len, 1.6); s2:SetSize(len, 1.6)
    end
    SizeStrokes(btn:GetSize())
    btn:HookScript("OnSizeChanged", function(_, w, h) SizeStrokes(w, h) end)
    local function setX(r, g, b, a) s1:SetVertexColor(r, g, b, a); s2:SetVertexColor(r, g, b, a) end
    setX(RGB(C.TEXT_DIM, 1))
    btn:SetScript("OnEnter", function() setX(1, 1, 1, 1) end)
    btn:SetScript("OnLeave", function() setX(RGB(C.TEXT_DIM, 1)) end)
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

    -- Nav buttons paint via SetFill (raw), so they are not caught by the
    -- fill-color retinter; re-assert each button's current state on a switch.
    Theme.RegisterRetinter(function()
        for i = 1, #nav.buttons do
            local navBtn = nav.buttons[i]
            if navBtn and navBtn.label then
                PaintNavButton(navBtn, nav.current == navBtn._navIndex and "active" or "clear")
            end
        end
    end)

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
        -- Keep the closed swatch showing the active theme after a switch.
        Theme.RegisterRetinter(function() updateSwatch(getter()) end)
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
-- Color themes: a preset accent hue drives the whole interactive palette.
-- Each preset gives the accent RGB + a text-safe hex; the button/toggle/gloss
-- tints are derived, so adding a theme is one line. Applied once on load from
-- the saved setting (a full effect requires reopening windows / reload).
--------------------------------------------------------------------------
Theme.THEMES = {
    Orange = { {0.92, 0.50, 0.16}, "FF8A33" },
    Blue   = { {0.26, 0.56, 0.92}, "4F9BFF" },
    Green  = { {0.30, 0.72, 0.40}, "5FC46B" },
    Yellow = { {0.95, 0.77, 0.16}, "FFD23F" },
    Red    = { {0.86, 0.30, 0.30}, "F26666" },
    Purple = { {0.62, 0.44, 0.90}, "B98CFF" },
    Teal   = { {0.18, 0.70, 0.66}, "3FC7BC" },
    Gray   = { {0.56, 0.58, 0.62}, "AEB2B8" },
}
-- Blue is the default look, so it leads the picker order.
Theme.THEME_ORDER = { "Blue", "Orange", "Green", "Yellow", "Red", "Purple", "Teal", "Gray" }
Theme.activeTheme = "Orange"

local function setC(key, r, g, b)
    local t = C[key]
    t[1], t[2], t[3] = r, g, b
end

function Theme.ApplyTheme(name)
    local preset = Theme.THEMES[name]
    if not preset then name, preset = "Orange", Theme.THEMES.Orange end
    Theme.activeTheme = name
    local ac = preset[1]
    local r, g, b = ac[1], ac[2], ac[3]
    setC("ACCENT", r, g, b)
    setC("ACCENT_DIM", r * 0.48, g * 0.48, b * 0.48)
    setC("ACCENT_BRIGHT", mmin(1, r * 1.15 + 0.10), mmin(1, g * 1.15 + 0.10), mmin(1, b * 1.15 + 0.10))
    setC("TOGGLE_ON", r, g, b)
    setC("TOGGLE_ON_DIS", r * 0.5, g * 0.5, b * 0.5)
    -- Nudge the neutral button grays toward the accent hue.
    setC("BTN_NORMAL", 0.17 + r * 0.05, 0.17 + g * 0.05, 0.17 + b * 0.05)
    setC("BTN_HOVER", 0.24 + r * 0.07, 0.24 + g * 0.07, 0.24 + b * 0.07)
    setC("BTN_PRESSED", 0.115 + r * 0.03, 0.115 + g * 0.03, 0.115 + b * 0.03)
    Theme.ACCENT_HEX = preset[2]
    GLOSS_TOP[1], GLOSS_TOP[2], GLOSS_TOP[3] = r * 0.22, g * 0.22, b * 0.22
    -- Re-apply live: already-built frames read the mutated palette. Safe on
    -- the login path too, where the registry is still empty.
    Theme.RunRetinters()
end

-- Blue is the addon's default look, so the factory colours are blue too (not the orange
-- literals above); Core re-applies the player's saved theme on login.
Theme.ApplyTheme("Blue")

ns.Theme = Theme
