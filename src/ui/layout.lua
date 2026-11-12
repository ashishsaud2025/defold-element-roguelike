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
M.ALL_SCREENS = { "TITLE", "COMBOS", "CREDITS", "HOME", "HOME_EDIT", "ROOM", "REWARD", "CAULDRON", "DEAD", "WIN", "PAUSED", "SETTINGS" }
-- Full-screen nodes (panel, flash_box) get this explicit rect: centre 480,320.
M.FULL_SCREEN = { x = 0, y = 0, w = M.DESIGN_W, h = M.DESIGN_H }
M.MARGIN = 16
M.GAP = 12
M.BUTTON_W, M.BUTTON_H = 280, 56
M.BUTTON_MIN_H = 40
M.BUTTON_MIN_W = 100
M.MONO_ADVANCE = 1200 / 2048            -- measured from assets/fonts/CascadiaCode.ttf
-- Assumed line spacing, in ems, for vertical-fit math: 1 line x font size x
-- LINE_HEIGHT. The engine may space lines differently (the value is not
-- exposed to scripts and cannot be measured headlessly), so a vertical pass
-- here is an ESTIMATE and the human's rendered screen stays the authority.
M.LINE_HEIGHT = 1.2

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
        icon = { x = x + 16, y = y + h - 72, w = 56, h = 56 },
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
M.VERSION = "v16"
M.SCREENS = {
    TITLE = {
        buttons = {
            M.button("start_box",    "start",    340, 336, 280, 52, "START",         true),
            M.button("combos_box",   "combos",   340, 276, 280, 52, "COMBOS",        true),
            M.button("credits_box",  "credits",  340, 216, 280, 52, "CREDITS",       true),
            M.button("settings_box", "settings_open", 340, 156, 280, 52, "SETTINGS", true),
            M.button("training_box", "training", 340,  96, 280, 52, "TRAINING HALL", true),
            M.button("exit_box",     "exit",     340,  36, 280, 52, "QUIT",          true),
        },
        texts = {
            title_text = { x = 480, y = 470, size = 36, color = "text",     text = "ELEMENT ROGUE", max_h = 46 },
            subtitle_text = { x = 480, y = 444, size = 14, color = "text_dim", text = "Mix two elements. Pick a shape. Survive.", max_h = 24 },
            version_text = { x = 900, y = 10, size = 14, color = "text_dim", text = M.VERSION, max_h = 24 },
        },
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
    },
    COMBOS = {
        panel = M.panel(40, 20, 880, 600, "COMBOS"),
        texts = {
            credits_title = { x = 480, y = 576, size = 24, color = "text", max_h = 34 },
            credits_body = { x = 480, y = 330, size = 14, color = "text", max_h = 400 },
        },
        buttons = {
            M.button("back_box", "back", 420, 34, 120, 48, "BACK", true),
        },
        back_rect = { x = 420, y = 34, w = 120, h = 48 },
    },
    CREDITS = {
        panel = M.panel(40, 20, 880, 600, "CREDITS"),
        texts = {
            credits_title = { x = 480, y = 576, size = 24, color = "text", max_h = 34 },
            credits_body = { x = 480, y = 330, size = 14, color = "text", max_h = 400 },
        },
        buttons = {
            M.button("back_box", "back", 420, 34, 120, 48, "BACK", true),
        },
        back_rect = { x = 420, y = 34, w = 120, h = 48 },
    },
    -- ===== The Lantern Hall home room =====
    HOME = {},
    -- ===== Loadout editor (the altar's modal) =====
    HOME_EDIT = {
        panel = M.panel(40, 20, 880, 600, "SPELL LOADOUT"),
        texts = {
            loadout_title = { x = 480, y = 586, size = 22, color = "text", max_h = 30 },
            loadout_preview = { x = 480, y = 190, size = 14, color = "text", max_w = 820, max_h = 26 },
            loadout_quirk_desc = { x = 480, y = 158, size = 12, color = "text_dim", max_w = 820, max_h = 40 },
            row_ea_label = { x = 140, y = 464, size = 13, color = "text_dim", max_w = 150, max_h = 24 },
            row_ea_val = { x = 480, y = 464, size = 14, color = "text", max_w = 320, max_h = 24 },
            row_eb_label = { x = 140, y = 396, size = 13, color = "text_dim", max_w = 150, max_h = 24 },
            row_eb_val = { x = 480, y = 396, size = 14, color = "text", max_w = 320, max_h = 24 },
            row_shape_label = { x = 140, y = 328, size = 13, color = "text_dim", max_w = 150, max_h = 24 },
            row_shape_val = { x = 480, y = 328, size = 14, color = "text", max_w = 320, max_h = 24 },
            row_quirk_label = { x = 140, y = 260, size = 13, color = "text_dim", max_w = 150, max_h = 24 },
            row_quirk_val = { x = 480, y = 260, size = 14, color = "text", max_w = 320, max_h = 24 },
        },
        buttons = {
            { id = "tab_mouse_box", action = "tab", label = "MOUSE", x = 228, y = 520, w = 160, h = 44, enabled = true, slot = 3, text = { x = 308, y = 542 } },
            { id = "tab_q_box",     action = "tab", label = "Q",     x = 400, y = 520, w = 160, h = 44, enabled = true, slot = 1, text = { x = 480, y = 542 } },
            { id = "tab_r_box",     action = "tab", label = "R",     x = 572, y = 520, w = 160, h = 44, enabled = true, slot = 2, text = { x = 652, y = 542 } },
            { id = "row_ea_prev_box", action = "cycle", label = "<", x = 210, y = 440, w = 100, h = 48, enabled = true, field = "ea", dir = -1, text = { x = 260, y = 464 } },
            { id = "row_ea_next_box", action = "cycle", label = ">", x = 650, y = 440, w = 100, h = 48, enabled = true, field = "ea", dir = 1,  text = { x = 700, y = 464 } },
            { id = "row_eb_prev_box", action = "cycle", label = "<", x = 210, y = 372, w = 100, h = 48, enabled = true, field = "eb", dir = -1, text = { x = 260, y = 396 } },
            { id = "row_eb_next_box", action = "cycle", label = ">", x = 650, y = 372, w = 100, h = 48, enabled = true, field = "eb", dir = 1,  text = { x = 700, y = 396 } },
            { id = "row_shape_prev_box", action = "cycle", label = "<", x = 210, y = 304, w = 100, h = 48, enabled = true, field = "shape", dir = -1, text = { x = 260, y = 328 } },
            { id = "row_shape_next_box", action = "cycle", label = ">", x = 650, y = 304, w = 100, h = 48, enabled = true, field = "shape", dir = 1,  text = { x = 700, y = 328 } },
            { id = "row_quirk_prev_box", action = "cycle", label = "<", x = 210, y = 236, w = 100, h = 48, enabled = true, field = "quirk", dir = -1, text = { x = 260, y = 260 } },
            { id = "row_quirk_next_box", action = "cycle", label = ">", x = 650, y = 236, w = 100, h = 48, enabled = true, field = "quirk", dir = 1,  text = { x = 700, y = 260 } },
            M.button("done_box", "done", 380, 40, 200, 56, "DONE", true),   -- shared with CAULDRON: same rect on both screens
        },
    },
    ROOM = {
        -- no panel: this is the in-combat HUD, not a menu screen
        texts = {
            hp_text = { x = 200, y = 596, size = 13, color = "text", max_w = 120, max_h = 22 },
            room_text = { x = 480, y = 601, size = 14, color = "text", max_w = 340, max_h = 26 },
            s1_quirk = { x = 124, y = 10, size = 10, color = "text_dim", max_w = 88, max_h = 16 },
            s2_quirk = { x = 200, y = 10, size = 10, color = "text_dim", max_w = 88, max_h = 16 },
            s3_quirk = { x = 48, y = 10, size = 10, color = "text_dim", max_w = 88, max_h = 16 },
            help_text = { x = 480, y = 128, size = 13, color = "text_dim", max_w = 900, max_h = 24 },
        },
        hp_bar    = { x = 80, y = 584, w = 240, h = 24 },
        dash_bar  = { x = 80, y = 572, w = 240, h = 6 },
        portrait  = { x = 16, y = 568, w = 56, h = 56 },
        slot_s1   = { x = 92, y = 18, w = 64, h = 64 },
        slot_s2   = { x = 168, y = 18, w = 64, h = 64 },
        slot_s3   = { x = 16, y = 18, w = 64, h = 64 },
        shape_icon_s1 = { x = 94, y = 32, w = 28, h = 28 },
        shape_icon_s2 = { x = 170, y = 32, w = 28, h = 28 },
        shape_icon_s3 = { x = 18, y = 32, w = 28, h = 28 },
        dot1_s1 = { x = 124, y = 56, w = 16, h = 16 },
        dot2_s1 = { x = 124, y = 38, w = 16, h = 16 },
        dot1_s2 = { x = 200, y = 56, w = 16, h = 16 },
        dot2_s2 = { x = 200, y = 38, w = 16, h = 16 },
        dot1_s3 = { x = 48, y = 56, w = 16, h = 16 },
        dot2_s3 = { x = 48, y = 38, w = 16, h = 16 },
        key_s1 = { x = 112, y = 86, w = 24, h = 24 },
        key_s2 = { x = 188, y = 86, w = 24, h = 24 },
        key_s3 = { x = 36, y = 86, w = 24, h = 24 },
        relic_bar = { x = 776, y = 590, slot = 34, gap = 8 },
        relic_slots = { "relic1", "relic2", "relic3", "relic4" },
        pips = { x = 776, y = 566, size = 14, gap = 8 },
        pip_ids = { "echo_pip1", "echo_pip2", "echo_pip3", "echo_pip4", "echo_pip5" },
    },
    REWARD = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            reward_title = { x = 480, y = 552, size = 30, color = "text", max_h = 42 },
            card1_text = { x = 250, y = 330, size = 16, color = "text", max_w = 180, max_h = 26 },
            card2_text = { x = 480, y = 330, size = 16, color = "text", max_w = 180, max_h = 26 },
            card3_text = { x = 710, y = 330, size = 16, color = "text", max_w = 180, max_h = 26 },
            card1_tag = { x = 250, y = 294, size = 11, color = "text_dim", max_w = 120, max_h = 18 },
            card2_tag = { x = 480, y = 294, size = 11, color = "text_dim", max_w = 120, max_h = 18 },
            card3_tag = { x = 710, y = 294, size = 11, color = "text_dim", max_w = 120, max_h = 18 },
            card1_desc = { x = 250, y = 216, size = 12, color = "text_dim", max_w = 170, max_h = 60 },
            card2_desc = { x = 480, y = 216, size = 12, color = "text_dim", max_w = 170, max_h = 60 },
            card3_desc = { x = 710, y = 216, size = 12, color = "text_dim", max_w = 170, max_h = 60 },
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
        -- Redesigned screen (target mock): pixel-art backdrop, ingredients panel on the
        -- left, title banner + status scroll on top, three ingredient tiles under the
        -- cauldron, spell preview + two craft cards below, DONE button at the bottom and
        -- a small relic summary top-right. `panel` is kept for the audits only; the
        -- screen itself is drawn by the cd_* art nodes (see `art`).
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, "CAULDRON"),
        -- decorative art rects (bottom-left x, y). Sizes equal the PNG sizes in
        -- assets/art/ui/cd_*.png (tools/make_cauldron_ui.py); tile art is 1:1 pixels.
        art = {
            cd_bg            = { x = 0,   y = 0,   w = 960, h = 640 },
            cd_ing_panel     = { x = 16,  y = 60,  w = 230, h = 470 },
            cd_title_banner  = { x = 310, y = 548, w = 340, h = 72 },
            cd_scroll        = { x = 250, y = 496, w = 460, h = 44 },
            cd_preview_panel = { x = 286, y = 84,  w = 388, h = 130 },
            cd_done_art      = { x = 330, y = 16,  w = 300, h = 56 },
            cd_small_box_1   = { x = 800, y = 556, w = 140, h = 34 },
            cd_small_box_2   = { x = 800, y = 515, w = 140, h = 34 },
            cd_gem           = { x = 807, y = 564, w = 18,  h = 18 },
            cd_trophy        = { x = 807, y = 523, w = 18,  h = 18 },
            cd_hl_1          = { x = 26,  y = 451, w = 210, h = 30 },   -- moved at runtime (rows)
            cd_hl_2          = { x = 26,  y = 417, w = 210, h = 30 },
            cd_hl_s          = { x = 26,  y = 273, w = 210, h = 30 },
            cd_preview_icon  = { x = 306, y = 116, w = 72,  h = 72 },
            cd_card_icon_1   = { x = 726, y = 114, w = 36,  h = 36 },
            cd_card_icon_2   = { x = 852, y = 114, w = 36,  h = 36 },
            cd_smoke_1       = { x = 414, y = 426, w = 72,  h = 72 },
            cd_smoke_2       = { x = 444, y = 430, w = 72,  h = 72 },
            cd_smoke_3       = { x = 474, y = 426, w = 72,  h = 72 },
        },
        -- left-aligned text uses align = "w" (PIVOT_W, x = left edge); right-aligned "e".
        -- Everything else is centred on x.
        texts = {
            cauldron_title = { x = 480, y = 577, size = 28, color = "text", max_w = 220, max_h = 36 },
            cd_status      = { x = 480, y = 518, size = 11, color = "text", max_w = 390, max_h = 16 },
            ing_title      = { x = 131, y = 515, size = 15, color = "text", max_w = 140, max_h = 22 },
            ing_elem_1 = { x = 80, y = 466, size = 14, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_elem_2 = { x = 80, y = 432, size = 14, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_elem_3 = { x = 80, y = 398, size = 14, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_elem_4 = { x = 80, y = 364, size = 14, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_cnt_1  = { x = 226, y = 466, size = 14, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_cnt_2  = { x = 226, y = 432, size = 14, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_cnt_3  = { x = 226, y = 398, size = 14, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_cnt_4  = { x = 226, y = 364, size = 14, color = "text", align = "e", max_w = 50, max_h = 20 },
            shape_title = { x = 131, y = 322, size = 13, color = "text", max_w = 100, max_h = 20 },
            ing_shape_1 = { x = 80, y = 288, size = 13, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_shape_2 = { x = 80, y = 256, size = 13, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_shape_3 = { x = 80, y = 224, size = 13, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_shape_4 = { x = 80, y = 192, size = 13, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_shape_5 = { x = 80, y = 160, size = 13, color = "text", align = "w", max_w = 100, max_h = 20 },
            ing_shcnt_1 = { x = 226, y = 288, size = 13, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_shcnt_2 = { x = 226, y = 256, size = 13, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_shcnt_3 = { x = 226, y = 224, size = 13, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_shcnt_4 = { x = 226, y = 192, size = 13, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_shcnt_5 = { x = 226, y = 160, size = 13, color = "text", align = "e", max_w = 50, max_h = 20 },
            ing_info_1 = { x = 64, y = 114, size = 11, color = "text_dim", align = "w", max_w = 170, max_h = 16 },
            ing_info_2 = { x = 64, y = 98,  size = 11, color = "text_dim", align = "w", max_w = 170, max_h = 16 },
            sel_ea_text    = { x = 346, y = 266, size = 11, color = "text", max_w = 100, max_h = 42 },
            sel_eb_text    = { x = 480, y = 266, size = 11, color = "text", max_w = 100, max_h = 42 },
            sel_shape_text = { x = 614, y = 266, size = 11, color = "text", max_w = 100, max_h = 42 },
            reaction_hint = { x = 480, y = 225, size = 10, color = "toast", max_w = 390, max_h = 14 },
            preview_name   = { x = 412, y = 182, size = 20, color = "text", align = "w", max_w = 250, max_h = 28 },
            preview_detail = { x = 412, y = 135, size = 12, color = "text", align = "w", max_w = 250, max_h = 18 },
            preview_quirk  = { x = 412, y = 116, size = 12, color = "text", align = "w", max_w = 250, max_h = 18 },
            preview_status = { x = 412, y = 97,  size = 12, color = "text_dim", align = "w", max_w = 250, max_h = 18 },
            craft1_text = { x = 744, y = 182, size = 10, color = "text", max_w = 110, max_h = 42 },
            craft2_text = { x = 870, y = 182, size = 10, color = "text", max_w = 110, max_h = 42 },
            relic_title = { x = 830, y = 573, size = 11, color = "text", align = "w", max_w = 104, max_h = 16 },
            relic_1     = { x = 830, y = 532, size = 10, color = "text", align = "w", max_w = 104, max_h = 14 },
            done_text = { x = 480, y = 44, size = 16, color = "text", max_w = 190, max_h = 24 },
        },
        -- ingredient rows (icons): element rows then shape rows
        ing_icons = {
            { id = "ing_icon_1", x = 40, y = 454, w = 24, h = 24 },
            { id = "ing_icon_2", x = 40, y = 420, w = 24, h = 24 },
            { id = "ing_icon_3", x = 40, y = 386, w = 24, h = 24 },
            { id = "ing_icon_4", x = 40, y = 352, w = 24, h = 24 },
        },
        ing_shape_icons = {
            { id = "ing_shape_icon_1", x = 40, y = 276, w = 24, h = 24 },
            { id = "ing_shape_icon_2", x = 40, y = 244, w = 24, h = 24 },
            { id = "ing_shape_icon_3", x = 40, y = 212, w = 24, h = 24 },
            { id = "ing_shape_icon_4", x = 40, y = 180, w = 24, h = 24 },
            { id = "ing_shape_icon_5", x = 40, y = 148, w = 24, h = 24 },
        },
        slots = {
            { box = "sel_ea_box",    label = "ELEM A", x = 286, y = 236, w = 120, h = 124, icon = "slot_icon_ea" },
            { box = "sel_eb_box",    label = "ELEM B", x = 420, y = 236, w = 120, h = 124, icon = "slot_icon_eb" },
            { box = "sel_shape_box", label = "SHAPE",  x = 554, y = 236, w = 120, h = 124, icon = "slot_icon_shape" },
        },
        craft1_box = { x = 684, y = 100, w = 120, h = 114 },
        craft2_box = { x = 810, y = 100, w = 120, h = 114 },
        done_box   = { x = 380, y = 40,  w = 200, h = 56 },   -- hit rect (shared with HOME_EDIT)
        buttons = {
            { id = "sel_ea_box",    action = "cauldron_cycle", label = "ELEM A", x = 286, y = 236, w = 120, h = 124, enabled = true, field = "ea",    text = { x = 346, y = 266 } },
            { id = "sel_eb_box",    action = "cauldron_cycle", label = "ELEM B", x = 420, y = 236, w = 120, h = 124, enabled = true, field = "eb",    text = { x = 480, y = 266 } },
            { id = "sel_shape_box", action = "cauldron_cycle", label = "SHAPE",  x = 554, y = 236, w = 120, h = 124, enabled = true, field = "shape", text = { x = 614, y = 266 } },
            { id = "craft1_box",    action = "craft",          label = "SLOT 1", x = 684, y = 100, w = 120, h = 114, enabled = true, slot = 1,        text = { x = 744, y = 182 } },
            { id = "craft2_box",    action = "craft",          label = "SLOT 2", x = 810, y = 100, w = 120, h = 114, enabled = true, slot = 2,        text = { x = 870, y = 182 } },
            { id = "done_box",      action = "done",           label = "DONE",   x = 380, y = 40,  w = 200, h = 56,  enabled = true,                  text = { x = 480, y = 44  } },
        },
        reaction_lines = 2,
    },
    DEAD = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            overlay_title = { x = 480, y = 430, size = 40, color = "warning", max_h = 52 },
            death_room = { x = 480, y = 352, size = 18, color = "text", max_h = 28 },
            death_relics = { x = 480, y = 310, size = 14, color = "text_dim", max_w = 720, max_h = 40 },
            overlay_hint = { x = 480, y = 180, size = 14, color = "text_dim", max_h = 24 },
        },
    },
    WIN = {
        panel = M.panel(0, 0, M.DESIGN_W, M.DESIGN_H, nil),
        texts = {
            overlay_title = { x = 480, y = 430, size = 40, color = "win", max_h = 52 },
            death_room = { x = 480, y = 352, size = 18, color = "text", max_h = 28 },
            death_relics = { x = 480, y = 310, size = 14, color = "text_dim", max_w = 720, max_h = 40 },
            overlay_hint = { x = 480, y = 180, size = 14, color = "text_dim", max_h = 24 },
        },
    },
    PAUSED = {
        panel = M.panel(240, 80, 480, 480, nil),
        texts = {
            paused_title = { x = 480, y = 500, size = 28, color = "text", max_h = 38 },
            resume_text = { x = 480, y = 415, size = 15, color = "text", max_h = 26 },
            paused_settings_text = { x = 480, y = 331, size = 15, color = "text", max_h = 26 },
            quit_text = { x = 480, y = 247, size = 15, color = "text", max_h = 26 },
            quit_main_text = { x = 480, y = 163, size = 15, color = "text_dim", max_h = 26 },
        },
        buttons = {
            { id = "resume_box",     action = "resume",        label = "RESUME",        x = 270, y = 386, w = 420, h = 56, enabled = true, text = { x = 480, y = 414 } },
            { id = "paused_settings_box", action = "settings_open", label = "SETTINGS", x = 270, y = 302, w = 420, h = 56, enabled = true, text = { x = 480, y = 330 } },
            { id = "quit_box",       action = "quit",          label = "QUIT",          x = 270, y = 218, w = 420, h = 56, enabled = true, text = { x = 480, y = 246 } },
            { id = "quit_main_box",  action = "quit_main",     label = "QUIT TO MENU",  x = 270, y = 134, w = 420, h = 56, enabled = true, text = { x = 480, y = 162 } },
        },
    },
    SETTINGS = {
        panel = M.panel(40, 20, 880, 600, "SETTINGS"),
        texts = {
            settings_title = { x = 480, y = 575, size = 24, color = "text", max_h = 30 },
            master_label = { x = 80, y = 531, size = 14, color = "text", max_w = 100, max_h = 24 },
            master_value = { x = 315, y = 531, size = 16, color = "text", max_w = 44, max_h = 24 },
            master_minus_text = { x = 241, y = 531, size = 20, color = "text", max_h = 26 },
            master_plus_text = { x = 401, y = 531, size = 20, color = "text", max_h = 26 },
            sfx_label = { x = 80, y = 434, size = 14, color = "text", max_w = 100, max_h = 24 },
            sfx_value = { x = 315, y = 434, size = 16, color = "text", max_w = 44, max_h = 24 },
            sfx_minus_text = { x = 241, y = 434, size = 20, color = "text", max_h = 26 },
            sfx_plus_text = { x = 401, y = 434, size = 20, color = "text", max_h = 26 },
            music_label = { x = 80, y = 337, size = 14, color = "text", max_w = 100, max_h = 24 },
            music_value = { x = 315, y = 337, size = 16, color = "text", max_w = 44, max_h = 24 },
            music_minus_text = { x = 241, y = 337, size = 20, color = "text", max_h = 26 },
            music_plus_text = { x = 401, y = 337, size = 20, color = "text", max_h = 26 },
            bindings_title = { x = 480, y = 277, size = 16, color = "text_dim", max_h = 24 },
            row_up_label = { x = 80, y = 234, size = 13, color = "text_dim", max_w = 130, max_h = 22 },
            row_left_label = { x = 80, y = 180, size = 13, color = "text_dim", max_w = 130, max_h = 22 },
            row_down_label = { x = 80, y = 126, size = 13, color = "text_dim", max_w = 130, max_h = 22 },
            row_right_label = { x = 80, y = 72, size = 13, color = "text_dim", max_w = 130, max_h = 22 },
            row_cast1_label = { x = 430, y = 234, size = 13, color = "text_dim", max_w = 160, max_h = 22 },
            row_cast2_label = { x = 430, y = 180, size = 13, color = "text_dim", max_w = 160, max_h = 22 },
            row_interact_label = { x = 430, y = 126, size = 13, color = "text_dim", max_w = 160, max_h = 22 },
            row_dash_label = { x = 430, y = 72, size = 13, color = "text_dim", max_w = 160, max_h = 22 },
            row_up_bind_text = { x = 300, y = 234, size = 15, color = "text", max_w = 120, max_h = 24 },
            row_left_bind_text = { x = 300, y = 180, size = 15, color = "text", max_w = 120, max_h = 24 },
            row_down_bind_text = { x = 300, y = 126, size = 15, color = "text", max_w = 120, max_h = 24 },
            row_right_bind_text = { x = 300, y = 72, size = 15, color = "text", max_w = 120, max_h = 24 },
            row_cast1_bind_text = { x = 650, y = 234, size = 15, color = "text", max_w = 120, max_h = 24 },
            row_cast2_bind_text = { x = 650, y = 180, size = 15, color = "text", max_w = 120, max_h = 24 },
            row_interact_bind_text = { x = 650, y = 126, size = 15, color = "text", max_w = 140, max_h = 24 },
            row_dash_bind_text = { x = 650, y = 72, size = 15, color = "text", max_w = 160, max_h = 24 },
            capture_note = { x = 480, y = 16, size = 11, color = "text_dim", max_w = 600, max_h = 16 },
            settings_back_text = { x = 818, y = 575, size = 16, color = "text", max_h = 24 },
        },
        bars = {
            master_bar = { x = 480, y = 524, w = 220, h = 14 },
            master_fill = { x = 480, y = 524, w = 220, h = 14 },
            sfx_bar = { x = 480, y = 427, w = 220, h = 14 },
            sfx_fill = { x = 480, y = 427, w = 220, h = 14 },
            music_bar = { x = 480, y = 330, w = 220, h = 14 },
            music_fill = { x = 480, y = 330, w = 220, h = 14 },
        },
        buttons = {
            { id = "master_minus_box", action = "volume_down", label = "-", x = 190, y = 508, w = 100, h = 48, enabled = true, field = "master", text = { x = 240, y = 532 } },
            { id = "master_plus_box",  action = "volume_up",   label = "+", x = 350, y = 508, w = 100, h = 48, enabled = true, field = "master", text = { x = 400, y = 532 } },
            { id = "sfx_minus_box",    action = "volume_down", label = "-", x = 190, y = 411, w = 100, h = 48, enabled = true, field = "sfx",    text = { x = 240, y = 435 } },
            { id = "sfx_plus_box",     action = "volume_up",   label = "+", x = 350, y = 411, w = 100, h = 48, enabled = true, field = "sfx",    text = { x = 400, y = 435 } },
            { id = "music_minus_box",  action = "volume_down", label = "-", x = 190, y = 314, w = 100, h = 48, enabled = true, field = "music",  text = { x = 240, y = 338 } },
            { id = "music_plus_box",   action = "volume_up",   label = "+", x = 350, y = 314, w = 100, h = 48, enabled = true, field = "music",  text = { x = 400, y = 338 } },
            { id = "row_up_bind_box",        action = "bind", label = "UP",      x = 240, y = 212, w = 140, h = 48, enabled = true, bind_id = "up",       text = { x = 310, y = 236 } },
            { id = "row_left_bind_box",      action = "bind", label = "LEFT",    x = 240, y = 158, w = 140, h = 48, enabled = true, bind_id = "left",     text = { x = 310, y = 182 } },
            { id = "row_down_bind_box",      action = "bind", label = "DOWN",    x = 240, y = 104, w = 140, h = 48, enabled = true, bind_id = "down",     text = { x = 310, y = 128 } },
            { id = "row_right_bind_box",     action = "bind", label = "RIGHT",   x = 240, y = 50,  w = 140, h = 48, enabled = true, bind_id = "right",    text = { x = 310, y = 74 } },
            { id = "row_cast1_bind_box",     action = "bind", label = "SPELL 1", x = 590, y = 212, w = 140, h = 48, enabled = true, bind_id = "cast1",    text = { x = 660, y = 236 } },
            { id = "row_cast2_bind_box",     action = "bind", label = "SPELL 2", x = 590, y = 158, w = 140, h = 48, enabled = true, bind_id = "cast2",    text = { x = 660, y = 182 } },
            { id = "row_interact_bind_box",  action = "bind", label = "USE",     x = 590, y = 104, w = 140, h = 48, enabled = true, bind_id = "interact", text = { x = 660, y = 128 } },
            { id = "row_dash_bind_box",      action = "bind", label = "DASH",    x = 590, y = 50,  w = 140, h = 48, enabled = true, bind_id = "dash",     text = { x = 660, y = 74 } },
            { id = "settings_back_box",     action = "back", label = "BACK",    x = 760, y = 550, w = 138, h = 48, enabled = true,                      text = { x = 829, y = 574 } },
        },
    },
}
-- Everything the screens draw is authored statically in main/hud.gui;
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

-- Every static text on every screen must fit its container, both ways:
--   width:   the widest rendered line <= the container width (mono advance math);
--   height:  line count x font size x LINE_HEIGHT <= the container height (max_h).
-- LINE_HEIGHT is an assumed 1.2 em (the engine's value is not measurable
-- headlessly); a vertical pass here is an estimate. Runtime-built bodies
-- (COMBOS/CREDITS panels) can be passed as bodies = { "COMBOS:credits_body" = text }.
function M.audit_text_fit(bodies)
    bodies = bodies or {}
    local problems = {}
    for _, name in ipairs(M.ALL_SCREENS) do
        local scr = M.SCREENS[name]
        if scr and scr.texts then
            local panel_inner = ((scr.panel and scr.panel.w) or M.DESIGN_W) - 32
            for id, spec in pairs(scr.texts) do
                local body_text = spec.text or bodies[name .. ":" .. id]
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
                    if spec.max_h then
                        local h = #lines * fs * M.LINE_HEIGHT
                        if h > spec.max_h then
                            problems[#problems + 1] = string.format(
                                "%s: %s vertical overflow: %d line(s) x %.1fpx = %.0fpx, container %dpx",
                                name, id, #lines, fs * M.LINE_HEIGHT, h, spec.max_h)
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
    return b
end

-- ===== Full position map for EVERY authored node id (used by the harness and
-- validate_ui.py to prove every node is positioned from a layout rect) =====
-- ALL_RECT_RECT[id] = { x, y, w, h }   (x,y = BOTTOM-LEFT, as everywhere here)
-- ALL_RECTS[id]     = centre position { x, y }
M.ALL_RECT_RECT = {}
local function put(id, x, y, w, h)
    if id then M.ALL_RECT_RECT[id] = { x = x, y = y, w = w or 0, h = h or 0 } end
end
local function put_rect(id, r)
    if r then put(id, r.x, r.y, r.w, r.h) end
end
local function put_center(id, cx, cy)
    if id then put(id, cx, cy, 0, 0) end
end

-- texts (node position = spec.x, spec.y; no w/h)
for _, name in ipairs(M.ALL_SCREENS) do
    local scr = M.SCREENS[name]
    for id, spec in pairs(scr.texts or {}) do
        put_center(id, spec.x, spec.y)
    end
end
-- buttons on every screen
for _, name in ipairs(M.ALL_SCREENS) do
    local scr = M.SCREENS[name]
    for _, b in ipairs(scr.buttons or {}) do
        put_rect(b.id, b)
        -- button label nodes position from b.text (node ids follow the
        -- <button>_text convention; credits_box is the one exception)
        if b.text and b.text.x then
            local LABEL_OF = { credits_box = "credits_text_btn" }
            put_center(LABEL_OF[b.id] or b.id:gsub("_box$", "_text"), b.text.x, b.text.y)
        end
    end
end
-- REWARD cards (frame = card expanded by 6 px on every side)
for _, card in ipairs(M.SCREENS.REWARD.cards) do
    local box_id = card.id .. "_box"
    put_rect(box_id, card)
    put_rect(card.id .. "_frame", { x = card.x - 6, y = card.y - 6, w = card.w + 12, h = card.h + 12 })
    put_rect(card.id .. "_icon", card.icon)
end
-- ROOM HUD
local R = M.SCREENS.ROOM
put_rect("hp_bg", R.hp_bar)
put_rect("hp_fill", R.hp_bar)
put_rect("dash_bg", R.dash_bar)
put_rect("dash_fill", R.dash_bar)
put_rect("portrait", R.portrait)
for i = 1, 3 do
    local prefix = "s" .. i
    put_rect(prefix .. "_bg", R["slot_" .. prefix])
    put_rect(prefix .. "_cd", R["slot_" .. prefix])
    put_rect(prefix .. "_frame", R["slot_" .. prefix])
    put_rect(prefix .. "_key", R["key_" .. prefix])
    put_rect(prefix .. "_shape_icon", R["shape_icon_" .. prefix])
    put_rect(prefix .. "_dot1", R["dot1_" .. prefix])
    put_rect(prefix .. "_dot2", R["dot2_" .. prefix])
end
for i, _ in ipairs(R.relic_slots) do
    local step = R.relic_bar.slot + R.relic_bar.gap
    put_rect("relic" .. i, { x = R.relic_bar.x + (i - 1) * step, y = R.relic_bar.y, w = R.relic_bar.slot, h = R.relic_bar.slot })
end
for i, _ in ipairs(R.pip_ids) do
    local step = R.pips.size + R.pips.gap
    put_rect("echo_pip" .. i, { x = R.pips.x + (i - 1) * step, y = R.pips.y, w = R.pips.size, h = R.pips.size })
end
-- CAULDRON art, ingredients, slots, craft cards and the done button
local CD = M.SCREENS.CAULDRON
for id, r in pairs(CD.art) do
    put_rect(id, r)
end
for _, ic in ipairs(CD.ing_icons) do
    put_rect(ic.id, ic)
end
for _, ic in ipairs(CD.ing_shape_icons) do
    put_rect(ic.id, ic)
end
for _, s in ipairs(CD.slots) do
    put_rect(s.box, s)
    put_rect(s.icon, { x = s.x + s.w * 0.5 - 24, y = s.y + s.h - 39 - 24, w = 48, h = 48 })
end
put_rect("craft1_box", CD.craft1_box)
put_rect("craft2_box", CD.craft2_box)
put_rect("done_box", CD.done_box)
-- PAUSED: panel is authored; every button + its label are positioned
local P = M.SCREENS.PAUSED
for _, b in ipairs(P.buttons) do
    put_rect(b.id, b)
    put_center(b.id:gsub("_box$", "_text"), b.text.x, b.text.y)
end
-- SETTINGS: panel, volume bars, binding rows
local S = M.SCREENS.SETTINGS
for k, v in pairs(S.bars) do put_rect(k, v) end
for _, b in ipairs(S.buttons) do
    put_rect(b.id, b)
    put_center(b.id:gsub("_box$", "_text"), b.text.x, b.text.y)
end
-- full-screen nodes
put_rect("panel", M.FULL_SCREEN)
put_rect("flash_box", M.FULL_SCREEN)

M.ALL_RECTS = {}
for id, r in pairs(M.ALL_RECT_RECT) do
    M.ALL_RECTS[id] = { x = r.x + r.w * 0.5, y = r.y + r.h * 0.5 }
end

return M
