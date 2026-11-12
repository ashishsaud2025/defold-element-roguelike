-- /src/ui/layout.lua
-- Phase B (UI overhaul): the single source of truth for every screen rect in
-- design space (960x640, origin bottom-left, +y up). Pure Lua: no gui.* or go.*,
-- so the smoke harness can require() it and tools/validate_ui.py can load it headlessly.
--
-- Conventions:
--   rect: { x, y, w, h } with x, y = BOTTOM-LEFT corner of the rect (not centre).
--   text position: { x, y } = the CENTRE of the text node (the GUI default pivot).
--   every id here must exist in main/hud.gui (see tools/validate_ui.py + the
--   ALL_NODES audit printed at HUD init).
-- Text fit math uses the vendored Cascadia Code's measured fixed advance:
--   advance = 1200 units @ upem 2048 => 0.5859375 em per character, uniform.
-- Never average glyph widths by proportion: this font is monospace.
local data = require "src.core.data"

local M = {}

-- ===== Design space & tuning =====
M.DESIGN_W, M.DESIGN_H = 960, 640
M.MARGIN = 16
M.GAP = 12
M.BUTTON_W, M.BUTTON_H = 280, 56
M.BUTTON_MIN_H = 40
M.BUTTON_MIN_W = 100
M.MONO_ADVANCE = 1200 / 2048            -- measured from assets/fonts/CascadiaCode.ttf

-- Width of the widest line. Callers that pass multi-line text (e.g. the F1
-- audit reading gui.get_text of credits_body) get the longest line measured,
-- which is what must fit the node's width; single-line callers are unchanged.
function M.text_width(s, font_size)
    local widest = 0
    for line in tostring(s):gmatch("[^\n]+") do
        if #line > widest then widest = #line end
    end
    return widest * (font_size or 14) * M.MONO_ADVANCE
end

-- ===== Palette =====
M.palette = {
    background  = { r = 0.01, g = 0.02, b = 0.05, a = 1.00 },
    panel       = { r = 0.04, g = 0.05, b = 0.09, a = 0.94 },
    panel_soft  = { r = 0.04, g = 0.05, b = 0.09, a = 0.72 },
    panel_border= { r = 0.30, g = 0.33, b = 0.45, a = 1.00 },
    panel_title = { r = 0.10, g = 0.12, b = 0.18, a = 1.00 },
    accent_gold = { r = 1.00, g = 0.78, b = 0.25, a = 1.00 },
    text        = { r = 1.00, g = 1.00, b = 1.00, a = 1.00 },
    text_dim    = { r = 0.55, g = 0.60, b = 0.72, a = 1.00 },
    box         = { r = 0.16, g = 0.18, b = 0.26, a = 1.00 },
    box_hover   = { r = 0.24, g = 0.27, b = 0.38, a = 1.00 },
    box_pressed = { r = 0.30, g = 0.55, b = 0.60, a = 1.00 },
    box_ready   = { r = 0.22, g = 0.55, b = 0.35, a = 1.00 },
    box_dim     = { r = 0.10, g = 0.11, b = 0.16, a = 1.00 },
    slot_bg     = { r = 0.09, g = 0.10, b = 0.16, a = 1.00 },
    pick_off    = { r = 0.18, g = 0.20, b = 0.28, a = 1.00 },
    warning     = { r = 0.90, g = 0.25, b = 0.25, a = 1.00 },
    hp          = { r = 0.85, g = 0.25, b = 0.32, a = 1.00 },
    hp_bg       = { r = 0.16, g = 0.10, b = 0.14, a = 1.00 },
    win         = { r = 0.35, g = 0.85, b = 0.45, a = 1.00 },
    cd          = { r = 0.00, g = 0.00, b = 0.00, a = 0.62 },
    toast       = { r = 1.00, g = 0.88, b = 0.35, a = 1.00 },
}
for _, el in ipairs({ "fire", "water", "wind", "earth" }) do
    local c = data.ELEMENTS[el]
    if c then M.palette["elem_" .. el] = { r = c.r, g = c.g, b = c.b, a = 1.0 } end
end

-- ===== Components (pure specs the GUI draws) =====
-- Panel: filled box + 2 px border + title bar. Returns rects in design space.
function M.panel(x, y, w, h, title)
    return {
        x = x, y = y, w = w, h = h,
        border = { x = x, y = y, w = w, h = h },
        fill   = { x = x + 2, y = y + 2, w = w - 4, h = h - 4 },
        title_bar = title and { x = x + 2, y = y + h - 44, w = w - 4, h = 42 } or nil,
        title = title,
        z_border = -2, z_fill = -1, z_bar = 0, z_text = 1,
    }
end

-- Button: id carries the action name (see ACTIONS). Returns rect + text pos.
function M.button(id, action, x, y, w, h, label, enabled)
    return {
        id = id, action = action, label = label,
        x = x, y = y, w = w or M.BUTTON_W, h = h or M.BUTTON_H,
        enabled = enabled ~= false,
        text = { x = x + (w or M.BUTTON_W) * 0.5, y = y + (h or M.BUTTON_H) * 0.5 },
    }
end

-- Card: three-block reward/relic card (Phase C+). Icon slot + name + kind tag + description.
function M.card(id, x, y, w, h)
    return {
        id = id, x = x, y = y, w = w, h = h,
        icon = { x = x + 16, y = y + h - 64, w = 48, h = 48 },
        name = { x = x + 76, y = y + h - 40, w = w - 92, h = 28 },
        tag  = { x = x + w - 74, y = y + h - 40, w = 56, h = 18 },
        desc = { x = x + 16, y = y + 18, w = w - 32, h = 34 },
        z = 1,
    }
end

-- icon_slot: fixed square for icons/ingredients.
function M.icon_slot(x, y, size)
    local s = size or 48
    return { x = x, y = y, w = s, h = s }
end

-- ===== wrap(text, max_chars) =====
-- Greedy, deterministic word wrap. Never emits a line longer than max_chars.
-- Empty input -> {}. A word longer than max_chars is hard-split at max_chars.
function M.wrap(text, max_chars)
    local limit = math.max(1, math.floor(max_chars or 58))
    local out = {}
    for paragraph in tostring(text or ""):gmatch("[^\n]*") do
        local cur = ""
        for word0 in paragraph:gmatch("%S+") do
            local word = word0
            while #word > limit do
                if #cur > 0 then out[#out + 1] = cur; cur = "" end
                out[#out + 1] = word:sub(1, limit)
                word = word:sub(limit + 1)
            end
            if #cur == 0 then
                cur = word
            elseif #cur + 1 + #word <= limit then
                cur = cur .. " " .. word
            else
                out[#out + 1] = cur
                cur = word
            end
        end
        if #cur > 0 then out[#out + 1] = cur end
    end
    return out
end

-- ===== Screens (Phase B proof set: TITLE, COMBOS, CREDITS) =====
-- All rects inside the 960x640 design area; text positions are node centres.
M.VERSION = "v15"
M.SCREENS = {
    TITLE = {
        buttons = {
            M.button("start_box",   "start",   340, 262, 280, 56, "START",   true),
            M.button("combos_box",  "combos",  340, 194, 280, 56, "COMBOS",  true),
            M.button("credits_box", "credits", 340, 126, 280, 56, "CREDITS", true),
        },
        texts = {
            title_text    = { x = 480, y = 470, size = 36, color = "text",     text = "ELEMENT ROGUE" },
            subtitle_text = { x = 480, y = 380, size = 14, color = "text_dim", text = "Mix two elements. Pick a shape. Survive." },
            version_text  = { x = 900, y = 24,  size = 14, color = "text_dim", text = M.VERSION },
        },
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
    },
    COMBOS = {
        panel = M.panel(40, 20, 880, 600, "COMBOS"),
        texts = {
            credits_title = { x = 480, y = 576, size = 24, color = "text" },
            credits_body  = { x = 480, y = 330, size = 14, color = "text" },
        },
        buttons = {
            M.button("back_box", "back", 420, 34, 120, 48, "BACK", true),
        },
        back_rect = { x = 420, y = 34, w = 120, h = 48 },
    },
    CREDITS = {
        panel = M.panel(40, 20, 880, 600, "CREDITS"),
        texts = {
            credits_title = { x = 480, y = 576, size = 24, color = "text" },
            credits_body  = { x = 480, y = 330, size = 14, color = "text" },
        },
        buttons = {
            M.button("back_box", "back", 420, 34, 120, 48, "BACK", true),
        },
        back_rect = { x = 420, y = 34, w = 120, h = 48 },
    },
    -- ===== Phase C: gameplay screens =====
    PICK_START = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            pick_title  = { x = 480, y = 566, size = 28, color = "text" },
            pick_hint   = { x = 480, y = 534, size = 13, color = "text_dim", max_w = 900 },
            pick_status = { x = 480, y = 196, size = 20, color = "text" },
            enter_text  = { x = 480, y = 116, size = 17, color = "text" },
            e1_text = { x = 195, y = 306, size = 17, color = "text" },
            e2_text = { x = 385, y = 306, size = 17, color = "text" },
            e3_text = { x = 575, y = 306, size = 17, color = "text" },
            e4_text = { x = 765, y = 306, size = 17, color = "text" },
            e1_role = { x = 195, y = 274, size = 11, color = "text_dim", max_w = 150 },
            e2_role = { x = 385, y = 274, size = 11, color = "text_dim", max_w = 150 },
            e3_role = { x = 575, y = 274, size = 11, color = "text_dim", max_w = 150 },
            e4_role = { x = 765, y = 274, size = 11, color = "text_dim", max_w = 150 },
        },
        buttons = {
            { id = "e1_box", action = "pick", label = "FIRE",  x = 120, y = 330, w = 150, h = 150, enabled = true, element = "fire",  text = { x = 195, y = 405 } },
            { id = "e2_box", action = "pick", label = "WATER", x = 310, y = 330, w = 150, h = 150, enabled = true, element = "water", text = { x = 385, y = 405 } },
            { id = "e3_box", action = "pick", label = "WIND",  x = 500, y = 330, w = 150, h = 150, enabled = true, element = "wind",  text = { x = 575, y = 405 } },
            { id = "e4_box", action = "pick", label = "EARTH", x = 690, y = 330, w = 150, h = 150, enabled = true, element = "earth", text = { x = 765, y = 405 } },
            M.button("enter_box", "enter", 340, 88, 280, 56, "ENTER ROOM", true),
        },
        tiles = {
            { id = "e1_box", element = "fire",  text_id = "e1_text", role_id = "e1_role" },
            { id = "e2_box", element = "water", text_id = "e2_text", role_id = "e2_role" },
            { id = "e3_box", element = "wind",  text_id = "e3_text", role_id = "e3_role" },
            { id = "e4_box", element = "earth", text_id = "e4_text", role_id = "e4_role" },
        },
    },
    ROOM = {
        -- no panel: this is the in-combat HUD, not a menu screen
        texts = {
            hp_text   = { x = 164, y = 601, size = 13, color = "text", max_w = 280 },
            room_text = { x = 480, y = 601, size = 16, color = "text", max_w = 340 },
            s1_name   = { x = 169, y = 96,  size = 13, color = "text", max_w = 258 },
            s1_quirk  = { x = 169, y = 78,  size = 11, color = "text_dim", max_w = 258 },
            s2_name   = { x = 791, y = 96,  size = 13, color = "text", max_w = 258 },
            s2_quirk  = { x = 791, y = 78,  size = 11, color = "text_dim", max_w = 258 },
            help_text = { x = 480, y = 14,  size = 13, color = "text_dim", max_w = 900 },
        },
        hp_bar    = { x = 24, y = 590, w = 280, h = 22 },
        slot_s1   = { x = 24,  y = 24, w = 290, h = 88 },
        slot_s2   = { x = 646, y = 24, w = 290, h = 88 },
        shape_icon_s1 = { x = 40,  y = 42, w = 46, h = 46 },
        shape_icon_s2 = { x = 662, y = 42, w = 46, h = 46 },
        dot1_s1 = { x = 96,  y = 44, w = 28, h = 28 },
        dot2_s1 = { x = 132, y = 44, w = 28, h = 28 },
        dot1_s2 = { x = 718, y = 44, w = 28, h = 28 },
        dot2_s2 = { x = 754, y = 44, w = 28, h = 28 },
        relic_bar = { x = 776, y = 590, slot = 34, gap = 8 },
        relic_slots = { "relic1", "relic2", "relic3", "relic4" },
    },
    REWARD = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            reward_title = { x = 480, y = 552, size = 30, color = "text" },
            card1_text = { x = 250, y = 330, size = 16, color = "text", max_w = 180 },
            card2_text = { x = 480, y = 330, size = 16, color = "text", max_w = 180 },
            card3_text = { x = 710, y = 330, size = 16, color = "text", max_w = 180 },
            card1_tag  = { x = 250, y = 294, size = 11, color = "text_dim", max_w = 120 },
            card2_tag  = { x = 480, y = 294, size = 11, color = "text_dim", max_w = 120 },
            card3_tag  = { x = 710, y = 294, size = 11, color = "text_dim", max_w = 120 },
            card1_desc = { x = 250, y = 216, size = 12, color = "text_dim", max_w = 170 },
            card2_desc = { x = 480, y = 216, size = 12, color = "text_dim", max_w = 170 },
            card3_desc = { x = 710, y = 216, size = 12, color = "text_dim", max_w = 170 },
        },
        cards = {
            M.card("card1", 150, 150, 200, 280),
            M.card("card2", 380, 150, 200, 280),
            M.card("card3", 610, 150, 200, 280),
        },
        buttons = {
            { id = "card1_box", action = "reward_pick", label = "CARD 1", x = 150, y = 150, w = 200, h = 280, enabled = true, index = 1, text = { x = 250, y = 290 } },
            { id = "card2_box", action = "reward_pick", label = "CARD 2", x = 380, y = 150, w = 200, h = 280, enabled = true, index = 2, text = { x = 480, y = 290 } },
            { id = "card3_box", action = "reward_pick", label = "CARD 3", x = 610, y = 150, w = 200, h = 280, enabled = true, index = 3, text = { x = 710, y = 290 } },
        },
        owned_strip = { x = 480, y = 96 },
    },
    CAULDRON = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, "CAULDRON"),
        texts = {
            cauldron_title = { x = 480, y = 590, size = 26, color = "text" },
            ing_title      = { x = 152, y = 520, size = 16, color = "text" },
            ing_elem_1     = { x = 152, y = 478, size = 13, color = "text" },
            ing_elem_2     = { x = 152, y = 434, size = 13, color = "text" },
            ing_elem_3     = { x = 152, y = 390, size = 13, color = "text" },
            ing_elem_4     = { x = 152, y = 346, size = 13, color = "text" },
            shape_title    = { x = 152, y = 306, size = 14, color = "text_dim" },
            ing_shape_1    = { x = 152, y = 278, size = 12, color = "text" },
            ing_shape_2    = { x = 152, y = 246, size = 12, color = "text" },
            ing_shape_3    = { x = 152, y = 214, size = 12, color = "text" },
            ing_shape_4    = { x = 152, y = 182, size = 12, color = "text" },
            ing_shape_5    = { x = 152, y = 150, size = 12, color = "text" },
            sel_ea_text    = { x = 346, y = 404, size = 12, color = "text", max_w = 100 },
            sel_eb_text    = { x = 480, y = 404, size = 12, color = "text", max_w = 100 },
            sel_shape_text = { x = 614, y = 404, size = 12, color = "text", max_w = 100 },
            preview_name   = { x = 480, y = 340, size = 21, color = "text" },
            preview_detail = { x = 480, y = 314, size = 13, color = "text_dim", max_w = 400 },
            preview_quirk  = { x = 480, y = 288, size = 13, color = "text" },
            preview_status = { x = 480, y = 264, size = 12, color = "text_dim" },
            reaction_hint  = { x = 480, y = 238, size = 11, color = "toast", max_w = 400 },
            craft1_text    = { x = 350, y = 156, size = 11, color = "text", max_w = 164 },
            craft2_text    = { x = 520, y = 156, size = 11, color = "text", max_w = 164 },
            relic_title    = { x = 818, y = 520, size = 16, color = "text" },
            relic_1        = { x = 818, y = 478, size = 11, color = "text", max_w = 220 },
            relic_2        = { x = 818, y = 396, size = 11, color = "text", max_w = 220 },
            relic_3        = { x = 818, y = 314, size = 11, color = "text", max_w = 220 },
            relic_4        = { x = 818, y = 232, size = 11, color = "text", max_w = 220 },
            done_text      = { x = 480, y = 76,  size = 16, color = "text" },
        },
        ing_icons = {
            { id = "ing_icon_1", x = 48, y = 464, w = 28, h = 28 },
            { id = "ing_icon_2", x = 48, y = 420, w = 28, h = 28 },
            { id = "ing_icon_3", x = 48, y = 376, w = 28, h = 28 },
            { id = "ing_icon_4", x = 48, y = 332, w = 28, h = 28 },
        },
        slots = {
            { box = "sel_ea_box",    label = "ELEM A", x = 292, y = 436, w = 108, h = 108, icon = "slot_icon_ea" },
            { box = "sel_eb_box",    label = "ELEM B", x = 426, y = 436, w = 108, h = 108, icon = "slot_icon_eb" },
            { box = "sel_shape_box", label = "SHAPE",  x = 560, y = 436, w = 108, h = 108, icon = "slot_icon_shape" },
        },
        craft1_box = { x = 264, y = 120, w = 172, h = 72 },
        craft2_box = { x = 452, y = 120, w = 172, h = 72 },
        done_box   = { x = 380, y = 40,  w = 200, h = 56 },
        buttons = {
            { id = "sel_ea_box",    action = "cauldron_cycle", label = "ELEM A", x = 292, y = 436, w = 108, h = 108, enabled = true, field = "ea",    text = { x = 346, y = 490 } },
            { id = "sel_eb_box",    action = "cauldron_cycle", label = "ELEM B", x = 426, y = 436, w = 108, h = 108, enabled = true, field = "eb",    text = { x = 480, y = 490 } },
            { id = "sel_shape_box", action = "cauldron_cycle", label = "SHAPE",  x = 560, y = 436, w = 108, h = 108, enabled = true, field = "shape", text = { x = 614, y = 490 } },
            { id = "craft1_box",    action = "craft",          label = "SLOT 1", x = 264, y = 120, w = 172, h = 72,  enabled = true, slot = 1,        text = { x = 350, y = 156 } },
            { id = "craft2_box",    action = "craft",          label = "SLOT 2", x = 452, y = 120, w = 172, h = 72,  enabled = true, slot = 2,        text = { x = 520, y = 156 } },
            { id = "done_box",      action = "done",           label = "DONE",   x = 380, y = 40,  w = 200, h = 56,  enabled = true,                  text = { x = 480, y = 68  } },
        },
        relic_panel = { x = 700, y = 120, w = 236, h = 424 },
        reaction_lines = 2,
    },
    DEAD = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            overlay_title = { x = 480, y = 430, size = 40, color = "warning" },
            death_room    = { x = 480, y = 352, size = 18, color = "text" },
            death_relics  = { x = 480, y = 310, size = 14, color = "text_dim", max_w = 720 },
            overlay_hint  = { x = 480, y = 180, size = 14, color = "text_dim" },
        },
    },
    WIN = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            overlay_title = { x = 480, y = 430, size = 40, color = "win" },
            death_room    = { x = 480, y = 352, size = 18, color = "text" },
            death_relics  = { x = 480, y = 310, size = 14, color = "text_dim", max_w = 720 },
            overlay_hint  = { x = 480, y = 180, size = 14, color = "text_dim" },
        },
    },
}
-- ENTER ROOM needs two picks: the HUD passes ctx = { picks = self.picks }.
M.SCREENS.PICK_START.buttons[5].requires = "two_picks"

-- Everything the Phase C screens draw is authored statically in main/hud.gui;
-- this list is kept for future runtime-created ids (tools/validate_ui.py skips
-- the "exists in hud.gui" check for ids listed here).
M.CREATED_IDS = {}

-- ===== Validation helpers (shared by validate_ui.py, the smoke suite, and F1 audit) =====
local function inside(r)
    return r.x >= 0 and r.y >= 0 and r.x + r.w <= M.DESIGN_W and r.y + r.h <= M.DESIGN_H
end

local function overlap(a, b)
    return a.x < b.x + b.w and b.x < a.x + a.w and a.y < b.y + b.h and b.y < a.y + a.h
end

-- Returns a list of problem strings for one screen (empty list = clean).
function M.audit_screen(screen_name)
    local problems = {}
    local scr = M.SCREENS[screen_name]
    if not scr then return { "unknown screen " .. tostring(screen_name) } end
    if scr.panel and not inside(scr.panel) then problems[#problems + 1] = screen_name .. ": panel leaves 960x640" end
    local bs = scr.buttons or {}
    for i, b in ipairs(bs) do
        if not inside(b) then problems[#problems + 1] = screen_name .. ": " .. b.id .. " leaves 960x640" end
        if b.h < M.BUTTON_MIN_H then problems[#problems + 1] = screen_name .. ": " .. b.id .. " height " .. b.h .. " < 40" end
        if b.w < M.BUTTON_MIN_W then problems[#problems + 1] = screen_name .. ": " .. b.id .. " width " .. b.w .. " < 100" end
        for j = i + 1, #bs do
            if overlap(b, bs[j]) then problems[#problems + 1] = screen_name .. ": " .. b.id .. " overlaps " .. bs[j].id end
        end
    end
    return problems
end

-- All texts on every screen must fit the panel rect they sit in (mono width math).
-- Measures only specs carrying a literal .text (TITLE-style) plus the COMBOS/CREDITS
-- bodies; everything else is measured live by the F1 audit in hud.gui_script.
function M.audit_text_fit()
    local problems = {}
    for _, name in ipairs({ "TITLE", "PICK_START", "ROOM", "REWARD", "CAULDRON", "COMBOS", "CREDITS", "DEAD", "WIN" }) do
        local scr = M.SCREENS[name]
        if scr and scr.texts then
            local panel_inner = ((scr.panel and scr.panel.w) or M.DESIGN_W) - 32
            for id, spec in pairs(scr.texts) do
                local body_text = spec.text
                if body_text then
                    local inner = spec.max_w or panel_inner
                    local fs = spec.size or 14
                    local limit_chars = math.max(1, math.floor(inner / (fs * M.MONO_ADVANCE)))
                    local lines = M.wrap(body_text, limit_chars)
                    for i, line in ipairs(lines) do
                        if M.text_width(line, fs) > inner then
                            problems[#problems + 1] = name .. ": " .. id .. " line " .. i .. " wider than its container"
                        end
                    end
                end
            end
        end
    end
    return problems
end

-- ===== Button registry + hit test (z = reverse insertion: later drawn above) =====
M.REGISTRY = {}
for name, scr in pairs(M.SCREENS) do
    M.REGISTRY[name] = {}
    for _, b in ipairs(scr.buttons or {}) do
        table.insert(M.REGISTRY[name], b)
    end
end

function M.hit(screen, x, y)
    local list = M.REGISTRY[screen]
    if not list then return nil end
    for i = #list, 1, -1 do
        local b = list[i]
        if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
            return b
        end
    end
    return nil
end

function M.hit_enabled(screen, x, y, ctx)
    local b = M.hit(screen, x, y)
    if not b or b.enabled ~= true then return nil end
    if b.requires == "two_picks" then
        local picks = ctx and ctx.picks
        if not picks or #picks < 2 then return nil end
    end
    return b
end

return M
