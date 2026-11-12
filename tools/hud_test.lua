-- Headless HUD harness: loads main/hud.gui_script with a stub gui.* API, runs
-- init(), renders EVERY screen state with a representative "ui" message, and
-- clicks every screen's buttons (through the real "click" message path the
-- game uses). This is the missing safety net for GUI code the mock Defold
-- API would otherwise never execute.
--
-- Checks (any failure is reported; run_smoke_test.py gates on this file too):
--   * gui.set_color only receives vmath.vector4 (the classic plain-palette bug)
--   * gui.set_position/set_scale only receive vmath.vector3, scales strictly positive
--   * gui.set_text only receives strings; node enables only receive booleans
--   * every node id used exists in main/hud.gui (or was created at init)
--   * every screen's text stays inside its container (fixed-advance width math)
--   * every button on every screen sends exactly the action its layout rect carries
--   * no errors at any point
local ROOT = (os.getenv("PROJECT_ROOT") or ".") .. "/"
package.path = ROOT .. "?.lua;" .. package.path

local errors, checks = {}, 0
local set_texts = {}
local function err(m)
  if #errors < 8 then errors[#errors + 1] = tostring(m) .. " @ " .. debug.traceback("", 3):gsub("\n", " ; ") end
end
local function sf(cond, msg)
  if cond then checks = checks + 1 else err(msg) end
end
local function isnum(v) return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge end

-- ===== vmath stub (NaN / wrong-type poisoning, like tools/smoke_test.lua) =====
vmath = {
  vector3 = function(x, y, z)
    if not (isnum(x) and isnum(y) and isnum(z or 0)) then err("NaN/wrong vector3 (" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. ")") return nil end
    return { x = x, y = y, z = z or 0 }
  end,
  vector4 = function(x, y, z, w)
    if not (isnum(x) and isnum(y) and isnum(z) and isnum(w)) then err("NaN/wrong vector4") return nil end
    return { x = x, y = y, z = z, w = w }
  end,
}
local function is_vec3(v)
  return type(v) == "table" and isnum(v.x) and isnum(v.y) and isnum(v.z)
end
local function is_vec4(v)
  return type(v) == "table" and isnum(v.x) and isnum(v.y) and isnum(v.z) and isnum(v.w)
end
local function is_plain_palette(v)
  return type(v) == "table" and v.x == nil and v.r ~= nil
end
function hash(s) return s end

-- ===== Parse main/hud.gui: known node ids + their sizes =====
local gui_text = io.open(ROOT .. "main/hud.gui", "r"):read("*a")
local known = {}
for id in gui_text:gmatch('id:%s*"([^"]+)"') do known[id] = true end
local node_spec = {}   -- id -> { w, h } when the node carries a size
for block in gui_text:gmatch("nodes%s*{(.-)\n}\n") do
  local id = block:match('id:%s*"([^"]+)"')
  if id then
    local sw, sh = block:match("size%s*{%s*x:%s*([%d.]+)%s*y:%s*([%d.]+)%s*}")
    local sx, sy = block:match("position%s*{%s*x:%s*([%-%d.]+)%s*y:%s*([%-%d.]+)")
    node_spec[id] = { w = tonumber(sw), h = tonumber(sh), px = tonumber(sx), py = tonumber(sy) }
  end
end

local nodes = {}
local gen = 0
local function new_known_id(id)
  known[id] = true
  return id
end
local function node_of(id)
  if not nodes[id] then
    if not known[id] then
      err("gui.get_node('" .. tostring(id) .. "'): id does not exist in main/hud.gui or at init")
      return nil
    end
    local spec = node_spec[id] or {}
    nodes[id] = { id = id,
      pos = vmath.vector3(spec.px or 0, spec.py or 0, 0),
      size = vmath.vector3(spec.w or 0, spec.h or 0, 0),
      scale = vmath.vector3(1, 1, 1),
      text = "", enabled = true, color = nil, flipbook = nil, positioned = false }
  end
  return nodes[id]
end

gui = {
  get_node = function(id) return node_of(id) end,
  set_enabled = function(node, b) if type(b) ~= "boolean" then err("gui.set_enabled: expected boolean") end; if node then node.enabled = b end end,
  set_position = function(node, p)
    if not is_vec3(p) then err("gui.set_position: expected vmath.vector3, got " .. tostring(p)); return end
    if node then node.pos = p; node.positioned = true end
  end,
  set_scale = function(node, s)
    if not is_vec3(s) then err("gui.set_scale: expected vmath.vector3, got " .. tostring(s)); return end
    if s.x <= 0 or s.y <= 0 or s.z <= 0 then err("gui.set_scale: non-positive component"); return end
    if node then node.scale = s end
  end,
  set_color = function(node, c)
    if is_plain_palette(c) then
      err("gui.set_color: plain palette table passed ({r,g,b,a}); gui colors must be vmath.vector4")
      return
    end
    if not is_vec4(c) then err("gui.set_color: expected vmath.vector4, got " .. tostring(c)); return end
    if node then node.color = c end
  end,
  set_text = function(node, s)
    if type(s) ~= "string" then err("gui.set_text: expected string, got " .. type(s)); return end
    if node then
      node.text = s
      set_texts[#set_texts + 1] = { id = node.id, text = s }
    end
  end,
  get_text = function(node) return node and node.text or "" end,
  get_position = function(node) return node and node.pos or vmath.vector3(0, 0, 0) end,
  get_size = function(node) return node and node.size or vmath.vector3(0, 0, 0) end,
  get_scale = function(node) return node and node.scale or vmath.vector3(1, 1, 1) end,
  set_layer = function(node, layer) end,
  play_flipbook = function(node, id)
    if id == nil or id == "" then err("gui.play_flipbook: empty animation id") end
    if node then node.flipbook = id end
  end,
  new_box_node = function(pos, size)
    if not is_vec3(pos) or not is_vec3(size) then err("gui.new_box_node: expected vector3 pos and size"); return nil end
    gen = gen + 1
    local id = new_known_id("__gen" .. gen)
    local n = node_of(id)
    n.pos, n.size, n.positioned = pos, size, true
    return n
  end,
  new_text_node = function(pos, text)
    if not is_vec3(pos) then err("gui.new_text_node: expected vector3 pos"); return nil end
    gen = gen + 1
    local id = new_known_id("__gen" .. gen)
    local n = node_of(id)
    n.pos, n.text, n.positioned = pos, tostring(text or ""), true
    return n
  end,
}

local sent_actions = {}
msg = {
  url = function(sock, path, frag) return { path = path, frag = frag } end,
  post = function(target, id, message)
    if target == "/game#script" and id == "ui_action" then
      sent_actions[#sent_actions + 1] = message
    end
  end,
}

-- ===== Load the actual gui script and run init() =====
local chunk = loadfile(ROOT .. "main/hud.gui_script")
if not chunk then
  print("HUD HARNESS CRASHED: hud.gui_script failed to load")
  return { errors = { "hud.gui_script failed to load" }, checks = 0 }
end
chunk()

local data = require "src.core.data"
local layout = require "src.ui.layout"
local relics_mod = require "src.core.relics"
local self = {}
init(self)

local HP_STEPS = { 100, 73, 41, 5 }
local hp_i = 0
local function example_ui(state)
  hp_i = hp_i + 1
  local hp = HP_STEPS[((hp_i - 1) % #HP_STEPS) + 1]
  local ui = {
    state = state,
    hp = hp, max_hp = 100,
    room = 4,
    boss = (state == "ROOM"),
    boss_hp = 88, boss_max_hp = 120,
    flash = (state == "ROOM") and 0.3 or 0,
    toast = (state == "ROOM") and "BURNING MUD" or nil,
    hover_x = 480, hover_y = 320,
  }
  if state == "PICK_START" then ui.picks = { "fire", "water" } end
  if state == "ROOM" or state == "DEAD" or state == "WIN" then
    ui.s1 = { name = "Inferno Nova", quirk = "splits in two", cd = 0.2, cd_max = 2.5, ea = "fire", eb = "wind" }
    ui.s2 = { name = "Tide Pool",   quirk = "repeats once",  cd = 0,   cd_max = 4.0, ea = "water", eb = "water" }
  end
  if state == "ROOM" or state == "REWARD" or state == "CAULDRON" or state == "DEAD" or state == "WIN" then
    ui.relics = { inferno_heart = true, echoing_crystal = true, ancient_catalyst = true, orbital_crown = true }
  end
  if state == "ROOM" or state == "REWARD" or state == "CAULDRON" then
    ui.inventory = { elements = { fire = 3, water = 2, wind = 1, earth = 0 },
                     shapes = { projectile = 2, puddle = 1, orbit = 0, cone = 1, burst = 0 } }
  end
  if state == "REWARD" then
    ui.reward_options = {
      { kind = "element", id = "fire" },
      { kind = "shape", id = "puddle" },
      -- icon deliberately differs from DEFS[inferno_heart].icon to prove the payload is used
      { kind = "relic", id = "inferno_heart", name = "Inferno Heart", desc = "Fire spells +15% power", icon = "icon_cauldron" },
    }
  end
  if state == "CAULDRON" then
    ui.cauldron = { ea = "fire", eb = "water", shape = "puddle" }
    ui.preview = { name = "Steam Pool", quirk = "repeats once", power = 7, cooldown = 4.0, statuses = { "push", "blind" } }
  end
  return ui
end

-- ===== Geometry audits: every node is positioned from a layout rect, inside
-- the 960x640 design area, and the visible union covers what the layout says =====
local TEXT_SPEC = {}
for _, scr in pairs(layout.SCREENS) do
  for id, spec in pairs(scr.texts or {}) do
    TEXT_SPEC[id] = TEXT_SPEC[id] or spec
  end
end

-- Approximate each node's screen rect. Boxes: authored size x scale, centred on
-- the node position. Texts: width from fixed-advance math against the spec's
-- size; height = line count x size x LINE_HEIGHT.
local function compute_rect(id, node)
  if not node then return nil end
  local p, s, sc = node.pos, node.size, node.scale
  if s.x > 0 and s.y > 0 then
    local w, h = s.x * sc.x, s.y * sc.y
    return { x = p.x - w * 0.5, y = p.y - h * 0.5, w = w, h = h }
  end
  local fs = (TEXT_SPEC[id] and TEXT_SPEC[id].size) or 14
  local lines = 1
  for _ in tostring(node.text):gmatch("\n") do lines = lines + 1 end
  local w = layout.text_width(node.text, fs)
  local h = lines * fs * layout.LINE_HEIGHT
  return { x = p.x - w * 0.5, y = p.y - h * 0.5, w = w, h = h }
end

-- E minus R -> list of uncovered rectangles
local function subtract_rect(E, R)
  local ix = math.max(E.x, R.x)
  local iy = math.max(E.y, R.y)
  local ix2 = math.min(E.x + E.w, R.x + R.w)
  local iy2 = math.min(E.y + E.h, R.y + R.h)
  if ix >= ix2 or iy >= iy2 then return { E } end
  local out = {}
  if E.x < ix then out[#out + 1] = { x = E.x, y = E.y, w = ix - E.x, h = E.h } end
  if E.x + E.w > ix2 then out[#out + 1] = { x = ix2, y = E.y, w = (E.x + E.w) - ix2, h = E.h } end
  if E.y < iy then out[#out + 1] = { x = ix, y = E.y, w = ix2 - ix, h = iy - E.y } end
  if E.y + E.h > iy2 then out[#out + 1] = { x = ix, y = iy2, w = ix2 - ix, h = (E.y + E.h) - iy2 } end
  return out
end

-- Is E fully covered by the union of rects?
local function rect_covered(E, rects)
  local pieces = { E }
  for _, r in ipairs(rects) do
    local next_pieces = {}
    for _, p in ipairs(pieces) do
      for _, q in ipairs(subtract_rect(p, r)) do next_pieces[#next_pieces + 1] = q end
    end
    pieces = next_pieces
    if #pieces == 0 then return true end
  end
  return #pieces == 0
end

local function assert_geometry(state)
  -- (a) every node ends with a position set by apply_layout/render/creation,
  -- never the authored default
  for id, node in pairs(nodes) do
    sf(node.positioned == true,
      state .. ": node '" .. id .. "' was never positioned (authored position kept)")
  end
  -- collect visible rects; assert all inside 960x640 (b)
  local visible = {}
  for id, node in pairs(nodes) do
    if node.enabled then
      local r = compute_rect(id, node)
      if r then
        visible[#visible + 1] = r
        sf(r.x >= -0.01 and r.y >= -0.01 and r.x + r.w <= layout.DESIGN_W + 0.01 and r.y + r.h <= layout.DESIGN_H + 0.01,
          string.format("%s: visible node '%s' leaves 960x640 (x=%.1f y=%.1f %.0fx%.0f)", state, id, r.x, r.y, r.w, r.h))
      end
    end
  end
  -- (c) the two full-screen nodes are exactly the screen
  for _, id in ipairs({ "panel", "flash_box" }) do
    local r = compute_rect(id, nodes[id])
    sf(r ~= nil and r.x == 0 and r.y == 0 and r.w == layout.DESIGN_W and r.h == layout.DESIGN_H,
      string.format("%s: %s must cover the full 960x640 screen (x=%.1f y=%.1f %.0fx%.0f)",
        state, id, r and r.x or -1, r and r.y or -1, r and r.w or -1, r and r.h or -1))
  end
  -- (d) the visible union covers the regions the layout requires
  local scr = layout.SCREENS[state]
  local expected = {}
  if scr and scr.panel then
    expected = { scr.panel }
  elseif state == "ROOM" then
    expected = { layout.SCREENS.ROOM.hp_bar, layout.SCREENS.ROOM.slot_s1, layout.SCREENS.ROOM.slot_s2 }
  end
  for _, E in ipairs(expected) do
    sf(rect_covered(E, visible),
      string.format("%s: visible nodes do not cover the expected region (x=%.0f y=%.0f %.0fx%.0f)", state, E.x, E.y, E.w, E.h))
  end
end

local STATES = { "TITLE", "COMBOS", "CREDITS", "PICK_START", "ROOM", "REWARD", "CAULDRON", "DEAD", "WIN" }
local function send_ui(state)
  on_message(self, hash("ui"), example_ui(state))
end
for _, state in ipairs(STATES) do
  send_ui(state)
  assert_geometry(state)
end

-- ===== Text fits its container (fixed-advance math; widest line) =====
-- Only screens that have a layout.lua spec are checked here. Phase C adds the
-- gameplay screens and they join this loop automatically (no harness change).
for _, state in ipairs(STATES) do
  local scr = layout.SCREENS[state]
  if scr and scr.texts then
    local panel_inner = ((scr.panel and scr.panel.w) or layout.DESIGN_W) - 32
    for id, spec in pairs(scr.texts) do
      local node = nodes[id]
      if node then
        local fs = spec.size or 14
        local inner = spec.max_w or panel_inner
        local w = layout.text_width(node.text, fs)
        sf(w <= inner, string.format("%s: text '%s' is %.0fpx wide, exceeds its %.0fpx container (fixed-advance math)",
          state, id, w, inner))
        if spec.max_h then
          local line_count = 1
          for _ in node.text:gmatch("\n") do line_count = line_count + 1 end
          local h = line_count * fs * layout.LINE_HEIGHT
          sf(h <= spec.max_h, string.format("%s: text '%s' vertical overflow: %d line(s) x %.1fpx = %.0fpx, exceeds its %dpx container (max_h)",
            state, id, line_count, fs * layout.LINE_HEIGHT, h, spec.max_h))
        end
      end
    end
  end
end

-- ===== Every button sends its expected action (through the real click path) =====
-- TITLE / COMBOS / CREDITS: layout.SCREENS registry is the contract.
-- PICK_START / REWARD / CAULDRON / DEAD / WIN: legacy node-geometry buttons with
-- fixed ids; Phase C moves them into the registry and this table flips over.
for state, buttons in pairs(layout.SCREENS) do
  if buttons.buttons and #buttons.buttons > 0 then
    for _, b in ipairs(buttons.buttons) do
      if b.enabled ~= false then
        send_ui(state)
        sent_actions = {}
        on_message(self, hash("click"), { x = b.x + b.w * 0.5, y = b.y + b.h * 0.5 })
        local got = sent_actions[#sent_actions]
        sf(got ~= nil, state .. "." .. b.id .. ": click sent no ui_action")
        if got then
          sf(got.action == b.action,
            string.format("%s.%s: click sent action '%s', registry expects '%s'", state, b.id, tostring(got.action), b.action))
        end
      end
    end
  end
end

-- PICK_START: ENTER must stay inert until two picks land
send_ui("PICK_START")
self.picks = {}
on_message(self, hash("ui"), { state = "PICK_START", hp = 100, max_hp = 100, picks = {} })
sent_actions = {}
local enter = layout.SCREENS.PICK_START.buttons[5]
on_message(self, hash("click"), { x = enter.x + enter.w * 0.5, y = enter.y + enter.h * 0.5 })
sf(#sent_actions == 0, "PICK_START: ENTER fired with zero picks")
self.picks = { "fire" }
on_message(self, hash("ui"), { state = "PICK_START", hp = 100, max_hp = 100, picks = { "fire" } })
sent_actions = {}
on_message(self, hash("click"), { x = enter.x + enter.w * 0.5, y = enter.y + enter.h * 0.5 })
sf(#sent_actions == 0, "PICK_START: ENTER fired with one pick")

-- ===== Content shown comes from data / relics.DEFS =====
-- REWARD: element/shape/relic cards carry data-derived name, tag, desc
do
  set_texts = {}
  on_message(self, hash("ui"), {
    state = "REWARD", room = 4,
    reward_options = {
      { kind = "element", id = "fire" },
      { kind = "shape", id = "puddle" },
      { kind = "relic", id = "inferno_heart" },
    },
    s1 = nil, s2 = nil,
  })
  local function text_for(id)
    for _, rec in ipairs(set_texts) do
      if rec.id == id then return rec.text end
    end
    return nil
  end
  sf(text_for("card1_text") == "FIRE", "REWARD: element card name must be the ELEMENT label")
  sf(text_for("card1_tag") == "ELEMENT", "REWARD: element card tag")
  local function wrapped_desc(s)
    local w = layout.wrap(s, 24)
    if #w > 2 then w = { w[1], w[2] } end
    return table.concat(w, "\n")
  end
  sf(text_for("card1_desc") == wrapped_desc(data.ELEMENTS.fire.role), "REWARD: element card desc must come from data.ELEMENTS.role")
  sf(text_for("card2_text") == "POOL", "REWARD: shape card name must be the SHAPE name")
  sf(text_for("card2_tag") == "SHAPE", "REWARD: shape card tag")
  sf(text_for("card2_desc") == wrapped_desc(data.SHAPES.puddle.blurb), "REWARD: shape card desc must come from data.SHAPES.blurb")
  local def = relics_mod.DEFS.inferno_heart
  sf(text_for("card3_text") == string.upper(def.name), "REWARD: relic card name must come from relics.DEFS.name")
  sf(text_for("card3_tag") == "RELIC", "REWARD: relic card tag")
  sf(text_for("card3_desc") == def.desc, "REWARD: relic card desc must come from relics.DEFS.desc")
end

-- CAULDRON: the preview panel renders exactly what the game sent, plus data-derived hints
do
  set_texts = {}
  local cd = { ea = "fire", eb = "water", shape = "puddle" }
  on_message(self, hash("ui"), {
    state = "CAULDRON", room = 4,
    cauldron = cd,
    preview = { name = "Steam Pool", quirk = "repeats once", power = 7, cooldown = 4.0, statuses = { "push", "blind" } },
    inventory = { elements = { fire = 2, water = 2, wind = 1, earth = 0 },
                  shapes = { projectile = 1, puddle = 2, orbit = 0, cone = 0, burst = 0 } },
    relics = { echoing_crystal = true },
    slots = { "Inferno Spray", "empty" },
  })
  local function text_for(id)
    for _, rec in ipairs(set_texts) do
      if rec.id == id then return rec.text end
    end
    return nil
  end
  sf(text_for("preview_name") == "Steam Pool", "CAULDRON: preview_name must render the sent preview")
  sf(text_for("preview_status") == "Statuses: push, blind", "CAULDRON: preview_status must render the sent statuses")
  sf(text_for("ing_elem_1") == "FIRE  x2", "CAULDRON: ingredient row shows element + count from inventory")
  sf(text_for("ing_shape_2") == "POOL  x2", "CAULDRON: shape row shows shape + count from inventory")
  sf(text_for("craft1_text"):find("Inferno Spray", 1, true) ~= nil, "CAULDRON: craft button shows current slot contents")
  sf(text_for("craft2_text"):find("empty", 1, true) ~= nil, "CAULDRON: empty slot is reported as empty")
  local relic_txt = text_for("relic_2")   -- echoing_crystal is RELIC_ORDER[2]
  local def = relics_mod.DEFS.echoing_crystal
  local wrapped = layout.wrap(def.desc, 34)
  if #wrapped > 2 then wrapped = { wrapped[1], wrapped[2] } end
  local expect = def.name .. "\n" .. table.concat(wrapped, "\n")
  sf(relic_txt == expect, "CAULDRON: owned relic panel must render relics.DEFS name + desc")
  -- mixed elements: no reaction hint; pure pool: hint must name the reacting combos from data
  sf((text_for("reaction_hint") or "") == "", "CAULDRON: mixed elements must not show a pure-pool hint")
  set_texts = {}
  on_message(self, hash("ui"), {
    state = "CAULDRON", room = 4,
    cauldron = { ea = "fire", eb = "fire", shape = "puddle" },
    preview = { name = "Inferno Pool", quirk = "leaves a trail", power = 14, cooldown = 4.0, statuses = { "burn" } },
    inventory = { elements = { fire = 2, water = 0, wind = 1, earth = 0 },
                  shapes = { projectile = 0, puddle = 2, orbit = 0, cone = 0, burst = 0 } },
    relics = {},
    slots = { "empty", "empty" },
  })
  text_for = function(id)
    for _, rec in ipairs(set_texts) do
      if rec.id == id then return rec.text end
    end
    return nil
  end
  local hint = text_for("reaction_hint") or ""
  sf(hint:find("STEAM VENT", 1, true) ~= nil, "CAULDRON: pure fire pool reacts with water (STEAM VENT) from data.REACTIONS")
  sf(hint:find("MOLTEN GROUND", 1, true) ~= nil, "CAULDRON: pure fire pool reacts with earth (MOLTEN GROUND) from data.REACTIONS")
  sf(hint:find("FIRESTORM", 1, true) == nil, "CAULDRON: fire+wind cell belongs to Fire Cyclone, never a reaction")
end

-- All four element roles fit their tiles (PICK_START): wrapped at render time
-- to the role node's inner width, with the data strings unchanged.
do
  send_ui("PICK_START")
  for _, el in ipairs({ "fire", "water", "wind", "earth" }) do
    local i = ({ fire = 1, water = 2, wind = 3, earth = 4 })[el]
    local id = "e" .. i .. "_role"
    local spec = layout.SCREENS.PICK_START.texts[id]
    local node = nodes[id]
    sf(node ~= nil, id .. ": node missing from the harness")
    if node then
      local role = data.ELEMENTS[el] and data.ELEMENTS[el].role or ""
      sf(#role > 0, "data: ELEMENTS." .. el .. ".role missing")
      local lines = {}
      for l in tostring(node.text):gmatch("[^\n]+") do lines[#lines + 1] = l end
      local fs = spec.size
      local max_chars = math.floor(spec.max_w / (fs * layout.MONO_ADVANCE))
      local expect = table.concat(layout.wrap(role, max_chars), "\n")
      sf(node.text == expect, id .. ": must render data.ELEMENTS.role wrapped to the tile's inner width")
      for _, l in ipairs(lines) do
        sf(layout.text_width(l, fs) <= spec.max_w, id .. ": wrapped role line wider than the tile's inner width")
      end
      sf(#lines <= 3, id .. ": more than three lines (vertical budget)")
      sf(#lines * fs * layout.LINE_HEIGHT <= spec.max_h, id .. ": wrapped role lines exceed the tile's vertical budget (max_h)")
    end
  end
end

-- ROOM: HP text renders the actual numbers; relic bar matches owned relics; toast reuses help_text
do
  set_texts = {}
  on_message(self, hash("ui"), {
    state = "ROOM", room = 6,
    hp = 73, max_hp = 100,
    s1 = { name = "Inferno Nova", quirk = "splits in two", cd = 0.2, cd_max = 2.5, ea = "fire", eb = "wind", shape = "burst" },
    s2 = { name = "Tide Pool",   quirk = "repeats once",  cd = 0,   cd_max = 4.0, ea = "water", eb = "water", shape = "puddle" },
    boss = false, boss_hp = 0, boss_max_hp = 0, flash = 0,
    toast = "DENSE CLOUD",
    inventory = { elements = { fire = 3, water = 2, wind = 1, earth = 1 },
                  shapes = { projectile = 2, puddle = 1, orbit = 1, cone = 0, burst = 1 } },
    relics = { inferno_heart = true, orbital_crown = true },
  })
  local function text_for(id)
    for _, rec in ipairs(set_texts) do
      if rec.id == id then return rec.text end
    end
    return nil
  end
  sf(text_for("hp_text") == "73 / 100", "ROOM: hp_text must render current/max (73 / 100)")
  sf(text_for("room_text") == "Room 6", "ROOM: room_text must render the room number")
  sf(text_for("help_text") == "DENSE CLOUD", "ROOM: banner must reuse the help_text node")
  sf(nodes["relic1"] and nodes["relic1"].enabled == true, "ROOM: owned relic icon must be shown")
  sf(nodes["relic4"] and nodes["relic4"].enabled == true, "ROOM: second owned relic icon must be shown")
  sf(nodes["relic2"] and nodes["relic2"].enabled == false, "ROOM: unowned relic slot must stay hidden")
  sf(nodes["relic3"] and nodes["relic3"].enabled == false, "ROOM: unowned relic slot must stay hidden")
  sf(nodes["relic1"] and nodes["relic1"].flipbook == hash("icon_fire"),
    "ROOM: relic bar icon must come from relics.DEFS (inferno_heart -> icon_fire)")
  sf(nodes["relic4"] and nodes["relic4"].flipbook == hash("particle_twirl"),
    "ROOM: relic bar icon must come from relics.DEFS (orbital_crown -> particle_twirl)")
  sf(nodes["echo_pip1"] and nodes["echo_pip1"].enabled == false,
    "ROOM: pips stay hidden without the Echoing Crystal")
  -- Phase D: hover the relic bar -> name + desc on the control line; move away -> restored
  set_texts = {}
  on_message(self, hash("ui"), {
    state = "ROOM", room = 6,
    hp = 73, max_hp = 100,
    s1 = { name = "Inferno Nova", quirk = "splits in two", cd = 0, cd_max = 2.5, ea = "fire", eb = "wind", shape = "burst" },
    boss = false, boss_hp = 0, boss_max_hp = 0, flash = 0, toast = nil,
    inventory = { elements = { fire = 3, water = 2, wind = 1, earth = 1 },
                  shapes = { projectile = 2, puddle = 1, orbit = 1, cone = 0, burst = 1 } },
    relics = { inferno_heart = true, orbital_crown = true },
    hover_x = 776 + 17, hover_y = 590 + 17,
  })
  do
    local expect = relics_mod.describe("inferno_heart")
    local got
    for _, rec in ipairs(set_texts) do
      if rec.id == "help_text" then got = rec.text end
    end
    sf(got == expect, "ROOM: hovering a relic icon must show name + desc from relics.DEFS, got: " .. tostring(got))
  end
  set_texts = {}
  on_message(self, hash("ui"), {
    state = "ROOM", room = 6,
    hp = 73, max_hp = 100,
    s1 = { name = "Inferno Nova", quirk = "splits in two", cd = 0, cd_max = 2.5, ea = "fire", eb = "wind", shape = "burst" },
    boss = false, boss_hp = 0, boss_max_hp = 0, flash = 0, toast = nil,
    inventory = { elements = { fire = 3, water = 2, wind = 1, earth = 1 },
                  shapes = { projectile = 2, puddle = 1, orbit = 1, cone = 0, burst = 1 } },
    relics = { inferno_heart = true, orbital_crown = true },
    hover_x = 480, hover_y = 320,
  })
  do
    local got
    for _, rec in ipairs(set_texts) do
      if rec.id == "help_text" then got = rec.text end
    end
    sf(got == self.help_default, "ROOM: leaving the relic bar restores the control hint")
  end
  -- Phase D: Echoing Crystal pips render and advance on the player's casts
  for _, casts in ipairs({ 3, 7, 10, 11 }) do
    set_texts = {}
    on_message(self, hash("ui"), {
      state = "ROOM", room = 6,
      hp = 73, max_hp = 100,
      s1 = { name = "Tide Pool", quirk = "repeats once", cd = 0, cd_max = 4.0, ea = "water", eb = "water", shape = "puddle" },
      boss = false, boss_hp = 0, boss_max_hp = 0, flash = 0, toast = nil,
      inventory = { elements = { fire = 3, water = 2, wind = 1, earth = 1 },
                    shapes = { projectile = 2, puddle = 1, orbit = 1, cone = 0, burst = 1 } },
      relics = { echoing_crystal = true },
      casts = casts,
    })
    local done = ({ [3] = 3, [7] = 2, [10] = 5, [11] = 1 })[casts]
    for i = 1, 5 do
      local n = nodes["echo_pip" .. i]
      sf(n and n.enabled == true, "pips: pip" .. i .. " must be visible with the Echoing Crystal")
      local gold = n and n.color and math.abs(n.color.y - 0.78) < 0.05
      sf((i <= done) == gold, string.format("pips: cast %d -> pip %d must be %s", casts, i, i <= done and "gold" or "dim"))
    end
  end
end

-- DEAD / WIN: any click continues; room reached + relics owned come from data
for _, state in ipairs({ "DEAD", "WIN" }) do
  send_ui(state)
  sent_actions = {}
  on_message(self, hash("click"), { x = 10, y = 10 })
  on_message(self, hash("click"), { x = 959, y = 639 })
  sf(#sent_actions == 2 and sent_actions[1].action == "continue" and sent_actions[2].action == "continue",
    state .. ": clicking anywhere should send continue twice")
end
set_texts = {}
on_message(self, hash("ui"), { state = "DEAD", room = 7, relics = { inferno_heart = true } })
do
  local death_relics, death_room
  for _, rec in ipairs(set_texts) do
    if rec.id == "death_relics" then death_relics = rec.text end
    if rec.id == "death_room" then death_room = rec.text end
  end
  sf(death_room == "Reached Room 7", "DEAD: room reached must render the actual room number")
  local def = relics_mod.DEFS.inferno_heart
  sf(death_relics == "Relics: " .. def.name, "DEAD: relics owned must come from relics.DEFS.name")
end

-- Every text-spec id must exist in main/hud.gui. The engine's gui.get_node
-- raises on an unknown id, which used to kill the F1 audit mid-handler
-- (version_text was runtime-created; the audit crashed on TITLE).
for _, state in ipairs(STATES) do
  local scr = layout.SCREENS[state]
  for id, _ in pairs(scr and scr.texts or {}) do
    sf(known[id] == true,
      "F1 audit would raise on missing node: spec '" .. id .. "' (" .. state .. ") is not authored in main/hud.gui")
  end
end

-- The F1 audit path, executed headlessly on every state: the handler must not
-- raise and must print a clean zero-problem summary.
for _, state in ipairs(STATES) do
  send_ui(state)
  local printed = {}
  local real_print = print
  print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    printed[#printed + 1] = table.concat(parts, " ")
  end
  local ok, audit_err = pcall(on_message, self, hash("ui_audit"), {})
  print = real_print
  sf(ok, state .. ": ui_audit handler raised: " .. tostring(audit_err))
  if ok then
    sf(#printed > 0, state .. ": ui_audit printed nothing")
    local last = printed[#printed] or ""
    sf(last:find("UI AUDIT: 0 problems", 1, true) ~= nil,
      state .. ": expected 'UI AUDIT: 0 problems', got: " .. tostring(last))
  end
end

-- ===== HUD survives a hostile message (almost everything absent) =====
for _, state in ipairs(STATES) do
  on_message(self, hash("ui"), { state = state })
end
sf(#errors == 0, "hostile/empty ui message produced errors: " .. table.concat(errors, " | "))

-- ===== Disabled buttons must not send =====
for state, buttons in pairs(layout.SCREENS) do
  for _, b in ipairs(buttons.buttons or {}) do
    if b.enabled == false then
      send_ui(state)
      sent_actions = {}
      on_message(self, hash("click"), { x = b.x + b.w * 0.5, y = b.y + b.h * 0.5 })
      sf(#sent_actions == 0, state .. "." .. b.id .. ": disabled button sent an action")
    end
  end
end

return {
  errors = errors,
  checks = checks,
}
