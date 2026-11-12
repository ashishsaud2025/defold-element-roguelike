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
      text = "", enabled = true, color = nil, flipbook = nil }
  end
  return nodes[id]
end

gui = {
  get_node = function(id) return node_of(id) end,
  set_enabled = function(node, b) if type(b) ~= "boolean" then err("gui.set_enabled: expected boolean") end; if node then node.enabled = b end end,
  set_position = function(node, p)
    if not is_vec3(p) then err("gui.set_position: expected vmath.vector3, got " .. tostring(p)); return end
    if node then node.pos = p end
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
    n.pos, n.size = pos, size
    return n
  end,
  new_text_node = function(pos, text)
    if not is_vec3(pos) then err("gui.new_text_node: expected vector3 pos"); return nil end
    gen = gen + 1
    local id = new_known_id("__gen" .. gen)
    local n = node_of(id)
    n.pos, n.text = pos, tostring(text or "")
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
    ui.relics = { inferno_heart = true, echoing_crystal = true }
  end
  if state == "ROOM" or state == "REWARD" or state == "CAULDRON" then
    ui.inventory = { elements = { fire = 3, water = 2, wind = 1, earth = 0 },
                     shapes = { projectile = 2, puddle = 1, orbit = 0, cone = 1, burst = 0 } }
  end
  if state == "REWARD" then
    ui.reward_options = {
      { kind = "element", id = "fire" },
      { kind = "shape", id = "puddle" },
      { kind = "relic", id = "inferno_heart" },
    }
  end
  if state == "CAULDRON" then
    ui.cauldron = { ea = "fire", eb = "water", shape = "puddle" }
    ui.preview = { name = "Steam Pool", quirk = "repeats once", power = 7, cooldown = 4.0, statuses = { "push", "blind" } }
  end
  return ui
end

local STATES = { "TITLE", "COMBOS", "CREDITS", "PICK_START", "ROOM", "REWARD", "CAULDRON", "DEAD", "WIN" }
local function send_ui(state)
  on_message(self, hash("ui"), example_ui(state))
end
for _, state in ipairs(STATES) do
  send_ui(state)
end

-- ===== Text fits its container (fixed-advance math; widest line) =====
-- Only screens that have a layout.lua spec are checked here. Phase C adds the
-- gameplay screens and they join this loop automatically (no harness change).
for _, state in ipairs(STATES) do
  local scr = layout.SCREENS[state]
  if scr and scr.texts then
    local inner = ((scr.panel and scr.panel.w) or layout.DESIGN_W) - 32
    for id, spec in pairs(scr.texts) do
      local node = nodes[id]
      if node then
        local w = layout.text_width(node.text, spec.size or 14)
        sf(w <= inner, string.format("%s: text '%s' is %.0fpx wide, exceeds its %.0fpx container (fixed-advance math)",
          state, id, w, inner))
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
