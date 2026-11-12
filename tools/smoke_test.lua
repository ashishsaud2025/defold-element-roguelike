-- Headless smoke test: runs main/game.script against a mock Defold API.
local ROOT = (os.getenv("PROJECT_ROOT") or ".") .. "/"
package.path = ROOT .. "?.lua;" .. package.path

local live, created, errors, logs = {}, 0, {}, {}
local nextid = 0
local function err(m) if #errors < 6 then errors[#errors+1] = m .. " @ " .. debug.traceback("", 3):gsub("\n", " ; ") end end
anim_seen = {}
local function isnum(v) return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge end

-- Animation ids are the image file names in the atlas (square.png -> "square").
-- Read them from the real atlas so a typo in art.lua is caught instead of guessed.
local VALID_ANIM = {}
do
  local f = io.open(ROOT .. "assets/art/shapes.atlas", "r")
  if f then
    for line in f:lines() do
      local path = line:match('image:%s*"([^"]+)"')
      local name = path and path:match("([^/]+)%.png$")
      if name then VALID_ANIM[name] = 1 end
      -- explicit flipbooks:  animations { id: "fxa_hit230_fire" images { image: ... } ... }
      local aid = line:match('^%s*id:%s*"([^"]+)"')
      if aid then VALID_ANIM[aid] = 1 end
    end
    f:close()
  else
    err("could not read assets/art/shapes.atlas")
  end
end

vmath = {
  vector3 = function(x,y,z) if not (isnum(x) and isnum(y) and isnum(z or 0)) then err("NaN vector3") end return {x=x,y=y,z=z or 0} end,
  vector4 = function(x,y,z,w) if not (isnum(x) and isnum(y) and isnum(z) and isnum(w)) then err("NaN vector4 "..tostring(x)..","..tostring(y)..","..tostring(z)..","..tostring(w)) end return {x=x,y=y,z=z,w=w} end,
  quat_rotation_z = function(a) return {a=a} end,
}
function hash(s) return s end
-- Defold's msg.post has a hard ~2 KB limit on the encoded table (Messaging API
-- manual). The mock cannot compute the engine's encoder exactly, so this is a
-- CONTENT tripwire, not a byte model:
--   * ui_big_str: a >512-byte string in any ui message whose state is not
--     CREDITS. (The pre-fix message carried the ~1.1 KB credits blob on every
--     frame and overflowed the engine's buffer at element #18.)
--   * ui_field_leak: an inventory/relics/reward_options/cauldron/preview field
--     attached to a ui message whose state does not render it.
-- Both are exact, model-free checks of the gating send_ui performs; they fire
-- loudly if anyone re-attaches heavy payloads to every frame.
-- A strict UPPER-BOUND model of the engine's message encoder (the real format
-- is undocumented). Calibrated: the pre-fix always-attach message scored ~2400
-- and overflowed the real 2040-byte engine buffer at element #18; the current
-- state-gated messages score ~400-800. Every ui message the suite posts is
-- measured; any of them at or over 2048 fails the run.
local function enc_upper(v)
  local t = type(v)
  if t == "string" then return #v + 16
  elseif t == "number" or t == "boolean" then return 8
  elseif t == "table" then
    local s = 40
    for k, val in pairs(v) do s = s + (#tostring(k) + 16) + enc_upper(val) end
    return s
  else return 16 end
end
local ui_seen, ui_worst = {}, {}
local ui_big_str, ui_big_str_state = nil, "?"
local ui_field_leak, ui_field_leak_state = nil, "?"
local ui_msg_max, ui_msg_max_state = 0, "?"
local last_ui, hud_clicks = nil, 0
msg = { url = function(sock, path, frag) return {path=path, frag=frag} end, post = function(target, id, message)
  if id == "click" then hud_clicks = hud_clicks + 1; return end
  if type(message) ~= "table" then return end
  if id == "ui" then last_ui = message end
  local st = tostring(message.state)
  local enc = enc_upper(message)
  if enc > ui_msg_max then ui_msg_max = enc; ui_msg_max_state = st end
  ui_seen[st] = (ui_seen[st] or 0) + 1
  if enc > (ui_worst[st] or 0) then ui_worst[st] = enc end
  local gated = { inventory = { REWARD = true, CAULDRON = true },
                  relics    = { ROOM = true, REWARD = true, CAULDRON = true, DEAD = true, WIN = true },
                  reward_options = { REWARD = true },
                  cauldron  = { CAULDRON = true },
                  preview   = { CAULDRON = true },
                  slots     = { CAULDRON = true },
                  s1        = { ROOM = true, DEAD = true, WIN = true },
                  s2        = { ROOM = true, DEAD = true, WIN = true },
                  s3        = { ROOM = true, DEAD = true, WIN = true },
                  dash_cd   = { ROOM = true },
                  prompt    = { HOME = true },
                  editor    = { HOME_EDIT = true },
                  credits   = { CREDITS = true } }
  for field, ok_states in pairs(gated) do
    if message[field] ~= nil and not ok_states[st] then
      if not ui_field_leak then ui_field_leak = field .. " @ " .. st end
      ui_field_leak_state = st
    end
  end
end }
local factories = { ["#visual_factory"]=true, ["#fx_factory"]=true }
local SPRITE_MAX = tonumber(os.getenv("SPRITE_MAX") or "2048")
local function livecount() local n=0 for _ in pairs(live) do n=n+1 end return n end
factory = { create = function(url, pos)
  if livecount() >= SPRITE_MAX then err("SPRITE BUFFER FULL ("..SPRITE_MAX..")") return nil end
  if not factories[url] then err("bad factory url "..tostring(url)) end
  nextid = nextid + 1; local id = "go"..nextid; live[id] = {pos=pos, kind=url, tb=""}; created = created + 1; return id end }
local function chk(id, what) if not live[id] then err(what.." on missing/deleted instance "..tostring(id)) return false end return true end
go = {
  PLAYBACK_LOOP_FORWARD=1, EASING_LINEAR=1,
  set = function(url, prop, val)
    if type(url)~="table" or not chk(url.path, "go.set "..tostring(prop)) then return end
    if prop ~= "tint" then err("go.set unexpected property "..tostring(prop)) end
    if url.frag ~= "sprite" then err("go.set on non-sprite component") end
    live[url.path].tint_val = { r = val.x, g = val.y, b = val.z, a = val.w }
  end,
  set_position = function(p, id) if chk(id,"set_position") then if not (isnum(p.x) and isnum(p.y)) then err("NaN position") end live[id].pos = p end end,
  set_scale = function(s, id)
    if not chk(id,"set_scale") then return end
    if not (isnum(s.x) and isnum(s.y) and isnum(s.z)) then err("NaN scale") end
    -- The engine rejects non-positive components (a flip must use sprite.set_hflip).
    if s.x <= 0 or s.y <= 0 or s.z <= 0 then
      err(string.format("non-positive scale (%s, %s, %s) - use sprite.set_hflip to mirror",
        tostring(s.x), tostring(s.y), tostring(s.z)))
    end
    live[id].scale = { x = s.x, y = s.y, z = s.z }
  end,
  set_rotation = function(q, id) chk(id,"set_rotation") end,
  animate = function(id) chk(id,"animate") end,
  delete = function(id) if chk(id,"go.delete (double delete?)") then live[id]=nil end end,
}
sprite = {
  play_flipbook = function(url, anim)
    if type(url)=="table" then chk(url.path, "play_flipbook") end
    if not VALID_ANIM[anim] then err("unknown animation id: "..tostring(anim)) end
    anim_seen[anim] = (anim_seen[anim] or 0) + 1
  end,
  set_hflip = function(url, flip)
    if type(url)~="table" or url.frag ~= "sprite" then err("set_hflip on non-sprite url") return end
    if not chk(url.path, "set_hflip") then return end
    if type(flip) ~= "boolean" then err("set_hflip expects a boolean, got "..tostring(flip)) end
    live[url.path].hflip = flip
    if flip then flip_true = (flip_true or 0) + 1 else flip_false = (flip_false or 0) + 1 end
  end,
}
local timers = {}
timer = { delay = function(t, rep, fn) timers[#timers+1] = {t=t, fn=fn} end }
local realprint = print
print = function(...) local t = {} for i=1,select('#',...) do t[#t+1]=tostring((select(i,...))) end logs[#logs+1]=table.concat(t," ") end

-- Art mode: the real manifest is active by default. ART_TEST=1 asserts it is on and
-- that every actor animation exists in the atlas; ART_TEST=0 forces the shape fallback.
do
  local art = require "src.core.art"
  local mode = os.getenv("ART_TEST")
  if mode == "1" and not art.ENABLED then
    err("ART_TEST=1 but art.ENABLED is false")
  elseif mode == "0" then
    art.ENABLED = false
  end
  if art.ENABLED then
    for role, a in pairs(art.ACTORS) do
      if not VALID_ANIM[a.anim] then err("actor " .. role .. " uses missing animation " .. tostring(a.anim)) end
    end
  end
end
-- ===== sfx recorder: real src/core/sfx.lua module, stubbed backend =====
-- The game requires the real module (manifest, throttling, bus sums) and its
-- backend routes into this recorder so the suite can assert what was played.
local sfx_plays = {}
package.preload["src.core.sfx"] = function()
  local real = dofile(ROOT .. "src/core/sfx.lua")
  real.backend = function(id, props) sfx_plays[#sfx_plays + 1] = { id = id, props = props } end
  real.stop_backend = function(id) sfx_plays[#sfx_plays + 1] = { id = "stop:" .. id } end
  real.gain_backend = function(id, gain) end
  return real
end

local chunk = assert(loadfile(ROOT.."main/game.script"))
chunk()
local skillgen = require "src.core.skillgen"
local data = require "src.core.data"

local self = {}
init(self)
local baseline = 0 local base_ids = {} for id in pairs(live) do baseline = baseline + 1 base_ids[id]=true end

local function ui(a) on_message(self, "ui_action", a, nil) end
local function act(id, pressed, released, ax, ay)
  -- logical action slots resolve through the rebinding engine by contract
  if self.bind and self.bind[id] then id = self.bind[id] end
  on_input(self, id, {pressed = pressed, released = released, x = ax or 480, y = ay or 320})
end
local dt = 1/60
local max_anims = 0
local function frame()
  update(self, dt)
  if self.anims and #self.anims > max_anims then max_anims = #self.anims end
  for i = #timers, 1, -1 do timers[i].t = timers[i].t - dt if timers[i].t <= 0 then local f = timers[i].fn; table.remove(timers, i); f() end end
end
local function count() local n=0 for _ in pairs(live) do n=n+1 end return n end

local ELEM = {"fire","water","wind","earth"}
local SHAPES = {"projectile","puddle","orbit","cone","burst"}
local recipes = {}
for i=1,4 do for j=i,4 do for _,sh in ipairs(SHAPES) do recipes[#recipes+1] = {ELEM[i],ELEM[j],sh} end end end

local level_mod = require "src.game.level"
local wall_viol, wall_first = 0, nil
local function check_walls()
  if self.state ~= "ROOM" or not self.level then return end
  local p = self.player_pos
  if level_mod.blocked(self.level, p.x, p.y, 8) then wall_viol = wall_viol + 1; wall_first = wall_first or ("player at "..math.floor(p.x)..","..math.floor(p.y).." room "..self.room_number) end
  for _, e in ipairs(self.enemies) do
    if e.alive and e.active and level_mod.blocked(self.level, e.x, e.y, e.radius*0.4) then wall_viol = wall_viol + 1; wall_first = wall_first or (e.type.." at "..math.floor(e.x)..","..math.floor(e.y).." room "..self.room_number) end
  end
end
local function start_run()
  ui({ action = "start" })      -- TITLE -> HOME (through the menu flow)
  ui({ action = "begin_run" })  -- door -> ROOM 1
end
local stats = { rooms=0, wins=0, deaths=0, maxlive=0, maxparticles=0, casts=0 }
local function play_run(allow_death, label)
  start_run()
  local guard = 0
  while guard < 60*60*10 do
    guard = guard + 1
    local st = self.state
    if st == "ROOM" then
      -- random input
      if guard % 20 == 0 then
        for _, k in ipairs{"up","down","left","right"} do if math.random()<0.5 then act(k,true,false) else act(k,false,true) end end
        on_input(self, nil, {x=math.random(0,960), y=math.random(0,640)})
      end
      if guard % 45 == 0 then act("dash", true, false) end
      if guard % 90 == 0 then act("cast1", true, false) end
      if guard % 200 == 0 then act("cast2", true, false) end
      if guard % 400 == 0 then act("cast1", false, true) act("cast2", false, true) end
      -- cycle through all 50 recipes for coverage
      if guard % 100 == 0 then
        local r = recipes[math.floor(guard/100) % #recipes + 1]
        self.slot1 = skillgen.makeSkill(r[1], r[2], r[3]); self.slot1_cooldown = 0; self.slot1_cd_max = self.slot1.cooldown
        local r2 = recipes[(math.floor(guard/100)*7) % #recipes + 1]
        self.slot2 = skillgen.makeSkill(r2[1], r2[2], r2[3]); self.slot2_cooldown = 0; self.slot2_cd_max = self.slot2.cooldown
      end
      if not allow_death then self.player.hp = self.player.max_hp; self.player.alive = true end
      -- force progress if the room drags on
      if (self.room_ticks or 0) > 60*25 then for _, e in ipairs(self.enemies) do e.alive = false end end
      self.room_ticks = (self.room_ticks or 0) + 1
    else
      self.room_ticks = 0
    end
    frame()
    check_walls()
    local c = count(); if c > stats.maxlive then stats.maxlive = c end
    if #self.particles > stats.maxparticles then stats.maxparticles = #self.particles end
    local s = self.state
    if s == "REWARD" then stats.rooms = stats.rooms + 1; ui({action="reward_pick", index=1}); frame()
    elseif s == "CAULDRON" then
      ui({action="cauldron_cycle", field="ea"}); ui({action="craft", slot=math.random(2)}); ui({action="done"}); frame()
    elseif s == "WIN" then stats.wins = stats.wins + 1; stats.rooms = stats.rooms + 1; ui({action="continue"}); frame(); return "WIN"
    elseif s == "DEAD" then stats.deaths = stats.deaths + 1; ui({action="continue"}); frame(); return "DEAD"
    end
  end
  return "TIMEOUT"
end

math.randomseed(42)
local results = {}
results[#results+1] = play_run(false)
results[#results+1] = play_run(false)
-- death path: make the player fragile
for i = 1, 3 do
  start_run()
  self.player.hp = 1; self.player.max_hp = 1
  local g=0 while self.state ~= "DEAD" and g < 60*60 do g=g+1 frame() end
  results[#results+1] = self.state
  ui({action="continue"}); frame()
end

-- ===== Pathing test: stationary player, does every enemy find a way to them? =====
local path_report = {}
for k = 1, 9 do
  -- the fuzz play_run leaves movement keys randomly pressed; nothing releases them.
  -- Pathing must measure a stationary dummy, so reset input inherited from the fuzz.
  self.keys = { up = false, left = false, down = false, right = false }
  self.dash_t, self.dash_cd = 0, 0
  start_run()
  self.room_number = k - 1; self.state = "CAULDRON"
  ui({action="done"})
  local seen, total, unreached = {}, 0, {}
  local waves_seen = 0
  for f = 1, 60*60 do
    self.player.hp = self.player.max_hp
    frame()
    if self.state ~= "ROOM" then break end
    for _, e in ipairs(self.enemies) do
      if e.alive and e.active and not seen[e] then
        local dx, dy = e.x - self.player_pos.x, e.y - self.player_pos.y
        local d = math.sqrt(dx*dx + dy*dy)
        local ok = false
        if e.type == "slinger" then
          ok = d < 330 and level_mod.los(self.level, e.x, e.y, self.player_pos.x, self.player_pos.y, 4)
        else
          ok = d < e.radius + 40
        end
        if ok then seen[e] = true; total = total + 1; e.alive = false end
      end
    end
    local pending = self.pending_wave and #self.pending_wave or 0
    local alive = 0 for _, e in ipairs(self.enemies) do if e.alive then alive = alive + 1 end end
    if alive == 0 and pending == 0 and self.room_clear_timer then break end
  end
  for _, e in ipairs(self.enemies) do if e.alive then unreached[#unreached+1] = e.type..'@'..math.floor(e.x)..','..math.floor(e.y) end end
  path_report[#path_report+1] = string.format("room %d (%s): reached %d / %d%s", k, self.level.name, total, self.room_budget, #unreached>0 and ("  STUCK: "..table.concat(unreached,' ')) or "")
  self.state = "ROOM"; for _, e in ipairs(self.enemies) do e.alive = false end; frame()
  ui({action="continue"}); frame()
end

-- ===== Skill FX coverage: every one of the 50 skills must play ITS OWN animated effects =====
local fxanim = require "src.core.fxanim"
local fx_report, fx_missing = {}, {}
-- every animation named in the generated table must exist in the atlas
for name in pairs(fxanim.ANIMS) do if not VALID_ANIM[name] then fx_missing[#fx_missing+1] = "atlas lacks " .. name end end
for cname, c in pairs(data.COMPOUNDS) do
  if not fxanim.COMPOUND[c.name] then fx_missing[#fx_missing+1] = "no style for compound " .. c.name end
end
-- two compounds must never share the same (hit,pool,spray,nova) combination
do
  local seen = {}
  for cname, st in pairs(fxanim.COMPOUND) do
    local k = st.hit .. "|" .. st.pool .. "|" .. st.spray .. "|" .. st.nova
    if seen[k] then fx_missing[#fx_missing+1] = cname .. " duplicates the effect set of " .. seen[k] end
    seen[k] = cname
  end
end
local function expect_for(skill)
  local st = fxanim.COMPOUND[skill.compound]
  local A, B = skill.elements[1], skill.elements[2]
  local want = { "fxa_" .. fxanim.CAST .. "_" .. A }
  local k = skill.shape_key
  if k == "projectile" then
    want[#want+1] = "fxa_headflame_" .. A; want[#want+1] = "fxa_" .. fxanim.PUFF .. "_" .. B
  elseif k == "puddle" then
    want[#want+1] = "fxa_" .. st.pool .. "_" .. A; want[#want+1] = "fxa_" .. st.pool .. "_" .. B
  elseif k == "orbit" then
    want[#want+1] = "fxa_orbflame_" .. A; want[#want+1] = "fxa_orbflame_" .. B
  elseif k == "cone" then
    want[#want+1] = "fxa_" .. st.spray .. "_" .. A; want[#want+1] = "fxa_" .. st.spray .. "_" .. B
  elseif k == "burst" then
    want[#want+1] = "fxa_" .. st.nova .. "_" .. A; want[#want+1] = "fxa_" .. st.nova .. "_" .. B
  end
  if st.smoke then want[#want+1] = "SMOKE" end
  return want
end
for ri, r in ipairs(recipes) do
  start_run()
  self.player.hp = self.player.max_hp
  local sk = skillgen.makeSkill(r[1], r[2], r[3])
  self.slot1 = sk; self.slot1_cooldown = 0; self.slot1_cd_max = sk.cooldown
  anim_seen = {}
  act("cast1", true, false); act("cast1", false, true)
  for f = 1, 150 do self.player.hp = self.player.max_hp; frame() end
  local want, miss = expect_for(sk), {}
  for _, w in ipairs(want) do
    if w == "SMOKE" then
      if not (anim_seen["fxa_smoke_a"] or anim_seen["fxa_smoke_b"]) then miss[#miss+1] = "smoke" end
    elseif not anim_seen[w] then miss[#miss+1] = w end
  end
  if #miss > 0 then fx_missing[#fx_missing+1] = sk.compound .. " " .. sk.shape .. " missing: " .. table.concat(miss, ",") end
  local n = 0 for k2 in pairs(anim_seen) do if k2:find("^fxa_") then n = n + 1 end end
  fx_report[#fx_report+1] = string.format("%s %s:%d", sk.compound, sk.shape, n)
  self.state = "DEAD"; ui({action="continue"}); frame()   -- end the run so the next recipe starts from TITLE
end

-- ============================================================================
-- Phase 5: spellcraft checks (all 50 combos, 25 quirk/shape cells, relics,
-- environmental interactions, cleanup). Every failure is collected in
-- `spell_fail`; run_smoke_test.py fails the run if it is non-empty.
-- ============================================================================
local relics_mod = require "src.core.relics"
local status_mod = require "src.core.status"
local spell_fail, spell_pass = {}, 0
local function sf(cond, msg)
  if cond then spell_pass = spell_pass + 1 else spell_fail[#spell_fail+1] = msg end
end
local function near(a, b, eps)
  return type(a) == "number" and math.abs(a - b) <= (eps or 0.001)
end
local function list_has(list, want)
  for _, v in ipairs(list or {}) do if v == want then return true end end
  return false
end
local function count_logs(pat)
  local n = 0
  for i = 1, #logs do if logs[i]:find(pat) then n = n + 1 end end
  return n
end
local function trail_count()
  local n = 0
  for _, p in ipairs(self.puddles) do if p.is_trail then n = n + 1 end end
  return n
end

-- A fresh run, room 1, no quirks/relics. Returns true when a ROOM is live.
-- Optional `seed` re-enters the identical room (used by the RNG-purity passes only).
local function begin_room(seed)
  if seed then math.randomseed(seed) end
  self.state = "DEAD"                        -- force reset_run from any prior state
  ui({ action = "continue" })
  start_run()
  self.player.hp, self.player.max_hp = 100, 100
  self.player.alive, self.player.invuln = true, 0
  -- The fuzz play_run leaves movement keys randomly pressed; nothing releases them.
  -- Targeted tests assume a static player, so reset input (AGENTS #58 family: freeze
  -- every channel that could nudge a "stationary" player or orbit).
  self.keys = { up = false, left = false, down = false, right = false }
  self.dash_t, self.dash_cd = 0, 0
  self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
  self.slot1_cooldown, self.slot2_cooldown, self.slot3_cooldown = 0, 0, 0
  self.hold3 = false
  self.relics, self.cast_count, self.status_dur_mul = {}, 0, 1
  return self.state == "ROOM"
end

-- Test frames that cannot die from enemy chip damage (HP stays untouched).
local function frames(n)
  for _ = 1, n do
    self.player.invuln = 5
    frame()
  end
end

-- Skill with a forced quirk id. qid == "" means "no quirk at all".
local function mk(shape, qid, a, b)
  local sk = skillgen.makeSkill(a or "fire", b or "fire", shape)
  sk.quirk_id = qid or ""
  sk.quirk = qid or ""
  return sk
end
local function equip(sk)
  self.slot1 = sk
  self.slot1_cooldown = 0
  self.slot1_cd_max = sk.cooldown
end
local function cast1()
  act("cast1", true, false)
  act("cast1", false, true)
end

-- ===== 5.1 every generated combination has all documented fields ===========
do
  local bad = 0
  local function sorted2(a, b) if a <= b then return a, b else return b, a end end
  for _, r in ipairs(recipes) do
    local sk = skillgen.makeSkill(r[1], r[2], r[3])
    local e1, e2 = sorted2(r[1], r[2])
    local exp = data.COMPOUNDS[e1 .. "+" .. e2]
    local shape = data.SHAPES[r[3]]
    local ok = type(sk.key) == "string" and type(sk.compound) == "string"
      and sk.compound == exp.name and sk.shape_key == r[3] and sk.shape == shape.name
      and type(sk.color) == "table" and type(sk.color.r) == "number"
      and type(sk.power) == "number" and sk.power >= exp.power * 0.9 - 0.5
      and sk.power <= exp.power * 1.1 + 0.5
      and sk.cooldown == shape.cooldown and sk.radius == shape.radius
      and sk.duration == shape.duration
      and type(sk.statuses) == "table" and #sk.statuses == #exp.statuses
      and type(sk.quirk) == "string" and type(sk.quirk_id) == "string"
      and sk.elements[1] == e1 and sk.elements[2] == e2
    for i, name in ipairs(exp.statuses) do
      if sk.statuses[i] ~= name then ok = false end
    end
    local cr = (data.ELEMENTS[e1].r + data.ELEMENTS[e2].r) / 2
    if not near(sk.color.r, cr, 1e-9) then ok = false end
    if not ok then
      bad = bad + 1
      sf(false, "generate " .. r[1] .. "+" .. r[2] .. " " .. r[3] .. " has wrong fields")
    end
  end
  sf(#recipes == 50, "expected 50 recipes, got " .. #recipes)
  sf(bad == 0, "50-combination generation: " .. bad .. " broken")
end

-- ===== Phase 2: every compound's statuses land through every shape ========
local PAIRS = {
  { "fire", "fire" }, { "water", "water" }, { "wind", "wind" }, { "earth", "earth" },
  { "fire", "water" }, { "fire", "wind" }, { "earth", "fire" }, { "water", "wind" },
  { "earth", "water" }, { "earth", "wind" },
}
local DIRS8 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 0.7, 0.7 }, { -0.7, 0.7 }, { 0.7, -0.7 }, { -0.7, -0.7 } }
local function place_target(e, dist)
  local p = self.player_pos
  for _, d in ipairs(DIRS8) do
    local x, y = p.x + d[1] * dist, p.y + d[2] * dist
    if not level_mod.blocked(self.level, x, y, e.radius)
       and level_mod.los(self.level, p.x, p.y, x, y, 4) then
      e.x, e.y = x, y
      return x, y
    end
  end
  e.x, e.y = level_mod.free_point_near(self.level, p.x + dist, p.y, e.radius)
  return e.x, e.y
end

do
  local cells = 0
  for _, pr in ipairs(PAIRS) do
    for _, shape in ipairs({ "projectile", "puddle", "orbit", "cone", "burst" }) do
      local tag = "status " .. pr[1] .. "+" .. pr[2] .. "/" .. shape
      if not begin_room() then
        sf(false, tag .. ": no room")
      else
        local sk = mk(shape, nil, pr[1], pr[2])
        local e = self.enemies[1]
        if not e then
          sf(false, tag .. ": no enemy to test on")
        else
          e.immortal, e.hp, e.speed = true, 999, 0
          e.vx, e.vy = 0, 0
          e.statuses = {}
          -- Room enemies start inactive behind a 0.9 s telegraph. Skip it: bolts only hit
          -- active enemies, so without this the projectile column never lands a hit.
          e.telegraph, e.active = 0, true
          local dist = (shape == "orbit") and 70 or 50
          local tx, ty = place_target(e, dist)
          self.aim.x, self.aim.y = tx, ty
          equip(sk)
          cast1()
          if shape == "puddle" then frames(32)
          elseif shape == "orbit" then frames(12)
          else frames(14) end
          local enemy_want = 0
          for _, name in ipairs(sk.statuses) do
            if name == "hide_self" then
              sf(self.player.statuses ~= nil and self.player.statuses.hide_self ~= nil,
                 tag .. ": hide_self did not affect the caster")
              sf(not (e.statuses and e.statuses.hide_self), tag .. ": hide_self leaked onto the enemy")
            else
              enemy_want = enemy_want + 1
              sf(e.statuses ~= nil and e.statuses[name] ~= nil, tag .. ": missing status " .. name)
            end
          end
          -- one entry per status name: repeated ticks refresh, never stack
          local keys = 0
          for _ in pairs(e.statuses or {}) do keys = keys + 1 end
          sf(keys == enemy_want, tag .. ": status keys=" .. keys .. " expected " .. enemy_want)
          cells = cells + 1
        end
      end
    end
  end
  sf(cells == 50, "status matrix: only " .. cells .. " / 50 cells ran")
end

-- ===== 5.2 five quirks x five shapes ========================================
local function test_quirk(qid, shape)
  local tag = qid .. "/" .. shape
  if not begin_room() then sf(false, tag .. ": could not enter a room") return end
  local sk = mk(shape, qid)
  local base_p, base_r = sk.power, sk.radius
  equip(sk)
  local cast_logs = count_logs("^Cast ")
  cast1()

  if qid == "split_in_two" then
    if shape == "projectile" then
      sf(#self.bolts == 2, tag .. ": bolts=" .. #self.bolts)
      if #self.bolts == 2 then
        sf(near(self.bolts[1].power, base_p * 0.6, 0.01)
           and near(self.bolts[2].power, base_p * 0.6, 0.01), tag .. ": split bolt power")
        sf(self.bolts[1].vx ~= self.bolts[2].vx or self.bolts[1].vy ~= self.bolts[2].vy,
           tag .. ": split bolts share one direction")
      end
    elseif shape == "puddle" then
      sf(#self.puddles == 2, tag .. ": puddles=" .. #self.puddles)
      if #self.puddles == 2 then
        sf(near(self.puddles[1].radius, base_r * 0.72, 0.01), tag .. ": split pool radius")
        sf(near(self.puddles[1].power, base_p * 0.6, 0.01), tag .. ": split pool power")
      end
    elseif shape == "orbit" then
      sf(#self.orbits == 2, tag .. ": orbits=" .. #self.orbits)
      if #self.orbits == 2 then
        sf(self.orbits[1].orbit_radius ~= self.orbits[2].orbit_radius,
           tag .. ": split orbits share one radius")
        sf(near(self.orbits[1].power, base_p * 0.6, 0.01), tag .. ": split orbit power")
      end
    elseif shape == "cone" then
      sf(#self.cones == 2, tag .. ": cones=" .. #self.cones)
      if #self.cones == 2 then
        sf(near(self.cones[1].power, base_p * 0.6, 0.01), tag .. ": split cone power")
      end
    else -- burst
      sf(#self.bursts == 1, tag .. ": first burst missing")
      local first = self.bursts[1]
      frames(30)
      local second = nil
      for _, b in ipairs(self.bursts) do
        if b ~= first and near(b.radius, base_r * 0.72, 0.01) then second = b end
      end
      sf(second ~= nil, tag .. ": split second burst did not appear")
      if second then
        sf(near(second.power, base_p * 0.6, 0.01), tag .. ": split burst power")
      end
    end
  elseif qid == "leaves_trail" then
    if shape == "projectile" then
      frames(30)
      sf(trail_count() >= 1, tag .. ": no bolt trail patches")
    elseif shape == "puddle" then
      sf(trail_count() == data.QUIRK_DATA.leaves_trail.pool_patches,
         tag .. ": pool trail patches=" .. trail_count())
    elseif shape == "orbit" then
      frames(45)
      sf(trail_count() >= 1, tag .. ": no orbit trail patches")
    else -- cone / burst drop one patch at the cast point
      sf(trail_count() >= 1, tag .. ": no " .. shape .. " trail patch")
    end
  elseif qid == "repeat_once" then
    sf(#self.repeat_casts == 1, tag .. ": repeat not scheduled")
    if shape == "puddle" then
      local first = self.puddles[1]
      self.player_pos.x = self.player_pos.x + 100    -- the repeat must use the ORIGINAL spot
      frames(30)
      if first then
        local second = nil
        for _, p in ipairs(self.puddles) do
          if p ~= first and not p.is_trail then second = p break end
        end
        sf(second ~= nil, tag .. ": repeated pool missing")
        sf(second ~= nil and near(second.x, first.x, 0.5), tag .. ": repeat used the moved player position")
      end
    else
      frames(30)
    end
    sf(count_logs("^Cast ") - cast_logs == 2,
       tag .. ": expected 2 casts, saw " .. (count_logs("^Cast ") - cast_logs))
    frames(120)
    sf(count_logs("^Cast ") - cast_logs == 2, tag .. ": repeat chained into more casts")
    sf(#self.repeat_casts == 0, tag .. ": repeat left pending casts")
  elseif qid == "bigger_slower" then
    if shape == "projectile" then
      sf(#self.bolts == 1, tag .. ": bolt missing")
      if self.bolts[1] then
        local sp = math.sqrt(self.bolts[1].vx ^ 2 + self.bolts[1].vy ^ 2)
        sf(near(sp, 450 * 0.8, 0.5), tag .. ": bolt speed " .. sp)
      end
    elseif shape == "puddle" then
      sf(#self.puddles == 1, tag .. ": pool missing")
      if self.puddles[1] then
        sf(near(self.puddles[1].radius, base_r * 1.3, 0.01), tag .. ": pool radius")
        sf(near(self.puddles[1].tick_interval, 0.625, 0.001), tag .. ": pool tick interval")
      end
    elseif shape == "orbit" then
      sf(#self.orbits == 1, tag .. ": orbit missing")
      if self.orbits[1] then
        sf(near(self.orbits[1].orbit_radius, 70 * 1.3, 0.01), tag .. ": orbit radius")
        sf(near(self.orbits[1].rev_per_sec, 1.5 * 0.8, 0.001), tag .. ": orbit spin")
      end
    elseif shape == "cone" then
      sf(#self.cones == 1, tag .. ": cone missing")
      if self.cones[1] then
        sf(near(self.cones[1].range, 90 * 1.3, 0.01), tag .. ": cone range")
        sf(near(self.cones[1].duration, 0.3 / 0.8 - 0.016, 0.001), tag .. ": cone linger")
      end
    else -- burst
      sf(#self.bursts == 1, tag .. ": burst missing")
      if self.bursts[1] then
        sf(near(self.bursts[1].radius, base_r * 1.3, 0.01), tag .. ": burst radius")
      end
    end
  else -- health_cost
    sf(self.player.hp == 95, tag .. ": hp=" .. self.player.hp .. " (expected 95)")
    local got
    if shape == "projectile" then got = self.bolts[1] and self.bolts[1].power
    elseif shape == "puddle" then got = self.puddles[1] and self.puddles[1].power
    elseif shape == "orbit" then got = self.orbits[1] and self.orbits[1].power
    elseif shape == "cone" then got = self.cones[1] and self.cones[1].power
    else got = self.bursts[1] and self.bursts[1].power end
    sf(got ~= nil and near(got, base_p * 1.5, 0.01),
       tag .. ": power " .. tostring(got) .. " (expected " .. (base_p * 1.5) .. ")")
  end
end

for _, qid in ipairs({ "split_in_two", "leaves_trail", "repeat_once", "bigger_slower", "health_cost" }) do
  for _, shape in ipairs({ "projectile", "puddle", "orbit", "cone", "burst" }) do
    test_quirk(qid, shape)
  end
end

-- health_cost edge cases: refused at low HP, never below 1 HP, no cooldown on refusal
if begin_room() then
  local sk = mk("projectile", "health_cost")
  equip(sk)
  self.player.hp = 5
  local before = #self.bolts
  cast1()
  sf(self.player.hp == 5, "health_cost: refused cast changed hp")
  sf(#self.bolts == before, "health_cost: cast fired without paying")
  sf(self.slot1_cooldown == 0, "health_cost: failed cast started a cooldown")
  self.player.hp = 6
  cast1()
  sf(self.player.hp == 1, "health_cost: minimum 1 HP not preserved, hp=" .. self.player.hp)
  sf(#self.bolts == before + 1, "health_cost: paid cast did not fire")
end

-- Debug row must cover BOTH slots (AGENTS 17) and cooldowns must follow the skill (item 18).
if begin_room() then
  local keys = { { "1", "projectile" }, { "2", "puddle" }, { "3", "orbit" }, { "4", "cone" },
                 { "5", "burst" }, { "6", "projectile" }, { "7", "puddle" }, { "8", "orbit" },
                 { "9", "cone" }, { "0", "burst" } }
  for i, k in ipairs(keys) do
    act(k[1], true, false)
    act(k[1], false, true)
    local slot = (i <= 5) and 1 or 2
    local sk = (slot == 1) and self.slot1 or self.slot2
    sf(sk.shape_key == k[2], "debug row: key " .. k[1] .. " -> slot " .. slot .. " shape "
       .. tostring(sk.shape_key) .. " (expected " .. k[2] .. ")")
  end
  self.slot2_cooldown = 3                       -- slot 2 is a burst here
  self.cooldown_ready[2][self.slot2.key] = self.clock + 3
  act("7", true, false)                         -- burst -> pool: a new skill starts ready
  sf(self.slot2.shape_key == "puddle", "debug row: slot 2 pool")
  sf(self.slot2_cooldown == 0, "debug row: a different skill inherited the old cooldown")
  self.slot2_cooldown = 2.5                     -- now the POOL is cooling down
  self.cooldown_ready[2][self.slot2.key] = self.clock + 2.5
  act("6", true, false)                         -- pool -> bolt
  sf(self.slot2.shape_key == "projectile", "debug row: slot 2 bolt")
  sf(self.slot2_cooldown == 0, "debug row: bolt inherited the pool's cooldown")
  act("7", true, false)                         -- back to pool: its own cooldown must resume
  sf(math.abs(self.slot2_cooldown - 2.5) <= 0.05,
     "debug row: pool cooldown did not resume (" .. self.slot2_cooldown .. ")")
end

-- ===== 5.2 relic effects, independently ====================================
if begin_room() then
  self.relics.inferno_heart = true
  local sk = mk("projectile", nil, "fire", "fire")
  equip(sk); cast1()
  local b = self.bolts[1]
  sf(b ~= nil and near(b.power, sk.power * 1.15, 0.01), "inferno_heart: fire bolt power")
end
if begin_room() then
  self.relics.inferno_heart = true
  local sk = mk("projectile", nil, "water", "water")
  equip(sk); cast1()
  local b = self.bolts[1]
  sf(b ~= nil and near(b.power, sk.power, 0.01), "inferno_heart: boosted a non-fire spell")
end
if begin_room() then
  self.status_dur_mul = relics_mod.status_duration_mul({ ancient_catalyst = true })
  sf(near(self.status_dur_mul, 1.2), "ancient_catalyst: multiplier")
  local sk = mk("burst", nil, "fire", "fire")
  equip(sk)
  local e = self.enemies[1]
  sf(e ~= nil, "ancient_catalyst: no enemy to test on")
  if e then
    e.x, e.y = self.player_pos.x + 10, self.player_pos.y
    e.alive, e.active = true, true
    e.hp, e.immortal = 999, true
    e.statuses = {}
    cast1()
    sf(e.statuses.burn ~= nil, "ancient_catalyst: burn not applied")
    if e.statuses.burn then
      sf(near(e.statuses.burn.expiry, 3.6, 0.01),
         "ancient_catalyst: burn duration " .. e.statuses.burn.expiry)
    end
  end
end
if begin_room() then
  self.relics.orbital_crown = true
  equip(mk("orbit", nil)); cast1()
  local o = self.orbits[1]
  sf(o ~= nil and #o.orbs == 4, "orbital_crown: orbs=" .. tostring(o and #o.orbs))
end
if begin_room() then
  equip(mk("orbit", nil)); cast1()
  sf(self.orbits[1] ~= nil and #self.orbits[1].orbs == 3, "orbital_crown: baseline is not 3 orbs")
end
if begin_room() then
  self.relics.echoing_crystal = true
  local sk = mk("projectile", nil)
  local before = count_logs("^Cast ")
  for _ = 1, 5 do equip(sk); cast1() end
  sf(self.cast_count == 5, "echoing_crystal: cast_count=" .. self.cast_count)
  sf(#self.repeat_casts == 1, "echoing_crystal: no echo scheduled on the 5th cast")
  if self.repeat_casts[1] then
    sf(near(self.repeat_casts[1].power_mul or 0, 0.5), "echoing_crystal: echo strength")
  end
  frames(30)
  sf(count_logs("^Cast ") - before == 6,
     "echoing_crystal: expected 6 casts, saw " .. (count_logs("^Cast ") - before))
  frames(180)
  sf(count_logs("^Cast ") - before == 6, "echoing_crystal: echo chained")
  sf(#self.repeat_casts == 0, "echoing_crystal: pending echoes")
end
-- Echo + repeats once: 5 player casts + 5 repeats + 1 echo, then nothing more.
if begin_room() then
  self.relics.echoing_crystal = true
  local sk = mk("projectile", "repeat_once")
  local before = count_logs("^Cast ")
  for _ = 1, 5 do equip(sk); cast1() end
  sf(#self.repeat_casts == 6, "echo+repeat: expected 5 repeats + 1 echo, got " .. #self.repeat_casts)
  frames(60)
  sf(count_logs("^Cast ") - before == 11,
     "echo+repeat: expected 11 casts, saw " .. (count_logs("^Cast ") - before))
  frames(240)
  sf(count_logs("^Cast ") - before == 11, "echo+repeat: infinite repeat chain")
  sf(#self.repeat_casts == 0, "echo+repeat: pending casts")
end
-- Health cost + Echo: the echo must never pay health.
if begin_room() then
  self.relics.echoing_crystal = true
  local sk = mk("projectile", "health_cost")
  local before = count_logs("Blood magic: ")
  for _ = 1, 5 do equip(sk); cast1() end
  sf(self.player.hp == 75, "health+echo: hp after 5 casts=" .. self.player.hp .. " (expected 75)")
  frames(40)
  sf(self.player.hp == 75, "health+echo: the echo paid health, hp=" .. self.player.hp)
  sf(count_logs("Blood magic: ") - before == 5,
     "health+echo: paid " .. (count_logs("Blood magic: ") - before) .. " times")
end

-- relic reward handler + reset (one screen per relic, forced so RNG cannot flake)
for _, id in ipairs(relics_mod.ORDER) do
  if begin_room() then
    self.state = "REWARD"
    self.reward_options = { { kind = "relic", id = id } }
    ui({ action = "reward_pick", index = 1 })
    sf(self.relics[id] == true, "relic pick: " .. id .. " not owned")
    if id == "ancient_catalyst" then
      sf(near(self.status_dur_mul, 1.2), "relic pick: ancient catalyst duration")
    else
      sf(self.status_dur_mul == 1, "relic pick: " .. id .. " changed status duration")
    end
    sf(self.state == "CAULDRON", "relic pick: state " .. tostring(self.state))
  end
end
self.state = "DEAD"; ui({ action = "continue" })
sf(next(self.relics) == nil, "relics did not reset on a new run")
sf(self.status_dur_mul == 1, "status_dur_mul did not reset")

-- reward screens: at most one relic, never an owned one, no unknown ids
if begin_room() then
  self.relics.inferno_heart = true
  local screens, relic_screens, bad = 0, 0, {}
  for _ = 1, 12 do
    if self.state ~= "ROOM" then break end
    self.spawned_count = math.max(self.spawned_count or 0, 1)
    local g = 0
    while self.state == "ROOM" and g < 600 do
      g = g + 1
      for _, e in ipairs(self.enemies) do e.alive = false end
      self.pending_wave = {}
      frame()
    end
    if self.state ~= "REWARD" then break end
    screens = screens + 1
    local rc = 0
    for _, opt in ipairs(self.reward_options or {}) do
      if opt.kind == "relic" then
        rc = rc + 1
        if not relics_mod.DEFS[opt.id] then bad[#bad+1] = "unknown relic " .. tostring(opt.id) end
        if self.relics[opt.id] then bad[#bad+1] = "offered an owned relic " .. opt.id end
      end
    end
    if rc > 1 then bad[#bad+1] = rc .. " relics on one screen" end
    if rc > 0 then relic_screens = relic_screens + 1 end
    local pick = 1
    for i, opt in ipairs(self.reward_options or {}) do
      if opt.kind ~= "relic" then pick = i break end
    end
    ui({ action = "reward_pick", index = pick })
    ui({ action = "done" })
  end
  sf(screens >= 1, "reward flow: no reward screens reached")
  for _, b in ipairs(bad) do sf(false, "reward flow: " .. b) end
end

-- ===== 5.3 environmental interactions =====================================
-- A. Fire over Mud -> Burning Mud, reverts after 3 s.
if begin_room() then
  equip(mk("puddle", nil, "earth", "water")); cast1()
  local mud = self.puddles[1]
  sf(mud ~= nil and mud.compound == "Mud", "burning mud: no Mud pool")
  -- Inferno (pure fire) pool over the Mud pool: the Inferno pool also reacts to the Mud
  -- area (MOLTEN GROUND statuses) but the BURNING MUD banner was announced first in section
  -- A, so the reaction banner must not overwrite it.
  equip(mk("puddle", nil, "fire", "fire")); cast1()
  frames(15)
  sf(mud ~= nil and mud.burning_mud == true, "burning mud: not ignited")
  sf(self.toast_text == "BURNING MUD" and (self.toast_t or 0) > 0,
     "burning mud: no readable banner")
  if mud then
    sf(list_has(mud.statuses, "burn"), "burning mud: no burn status")
    frames(150)                                     -- ~2.5 s: before Burning Mud reverts (3 s)
    sf(mud.burning_mud == true, "burning mud: did not revert early")
    sf((self.toast_t or 0) == 0,
       "burning mud: banner expired (the MOLTEN GROUND reaction on the Inferno pool was suppressed by the banner)")
    frames(90)                                       -- cross the 3 s revert
    sf(mud.burning_mud == false, "burning mud: did not revert after 3 s")
    sf(not list_has(mud.statuses, "burn"), "burning mud: burn was not removed on revert")
    frames(30)
    sf(mud.burning_mud == false, "burning mud: re-ignited forever while the fire area lived")
  end
end
-- B. Fire Cyclone coverage lives in the dedicated suite at the end of the file.
-- The old "spread_fire_area" cloning path is gone (third addendum §5/§6).
-- C. Steam + Dust -> one Dense Cloud that blinds and confuses, then cleans up.
if begin_room() then
  equip(mk("puddle", nil, "fire", "water")); cast1()
  equip(mk("puddle", nil, "earth", "wind")); cast1()
  frames(15)
  sf(#self.clouds == 1, "dense cloud: clouds=" .. #self.clouds)
  sf(self.toast_text == "DENSE CLOUD" and (self.toast_t or 0) > 0,
     "dense cloud: no readable banner")
  local cloud = self.clouds[1]
  if cloud then
    local vis = cloud.vis
    local e = self.enemies[1]
    sf(e ~= nil, "dense cloud: no enemy to test on")
    if e then
      e.x, e.y = cloud.x, cloud.y
      e.alive, e.active = true, true
      e.hp, e.immortal = 999, true
      e.statuses = {}
      frames(35)
      sf(status_mod.has(e, "blind"), "dense cloud: no blind")
      sf(status_mod.has(e, "confuse"), "dense cloud: no confuse")
    end
    frames(150)
    sf(#self.clouds == 0, "dense cloud: not cleaned up after its lifetime")
    sf(vis == nil or live[vis] == nil, "dense cloud: visual leaked")
  end
end
-- Interactions near a wall must never place a pool inside it.
if begin_room() then
  local fx, fy, wx, wy
  local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  for r = 1, level_mod.ROWS do
    for c = 1, level_mod.COLS do
      if not level_mod.SOLID[self.level.grid[r][c]] then
        for _, d in ipairs(dirs) do
          local nc, nr = c + d[1], r + d[2]
          if nc >= 1 and nc <= level_mod.COLS and nr >= 1 and nr <= level_mod.ROWS
             and level_mod.SOLID[self.level.grid[nr][nc]] then
            fx, fy = level_mod.cell_center(c, r)
            wx, wy = level_mod.cell_center(nc, nr)
            break
          end
        end
      end
      if fx then break end
    end
    if fx then break end
  end
  sf(fx ~= nil, "boundary: no wall-adjacent floor cell")
  if fx then
    self.player_pos.x, self.player_pos.y = fx, fy
    self.aim.x, self.aim.y = wx, wy
    equip(mk("puddle", nil, "earth", "water")); cast1()
    equip(mk("puddle", nil, "fire", "fire")); cast1()
    equip(mk("puddle", nil, "wind", "wind")); cast1()
    frames(20)
    local inside = 0
    for _, p in ipairs(self.puddles) do
      if level_mod.is_solid(self.level, p.x, p.y) then inside = inside + 1 end
    end
    sf(inside == 0, "boundary: " .. inside .. " pool(s) placed inside a wall")
    sf(#self.spell_areas <= data.INTERACT.MAX_SPELL_AREAS, "boundary: too many spell areas")
    sf(#self.clouds <= data.INTERACT.MAX_CLOUDS, "boundary: too many clouds")
  end
end
-- Unbounded creation: 60 casts and many interaction pairs stay capped.
if begin_room() then
  local sk = mk("puddle", nil)
  for _ = 1, 60 do equip(sk); cast1() end
  sf(#self.spell_areas <= data.INTERACT.MAX_SPELL_AREAS,
     "area cap: " .. #self.spell_areas .. " > " .. data.INTERACT.MAX_SPELL_AREAS)
  for _ = 1, 10 do
    equip(mk("puddle", nil, "fire", "water")); cast1()
    equip(mk("puddle", nil, "earth", "wind")); cast1()
  end
  frames(20)
  sf(#self.clouds <= data.INTERACT.MAX_CLOUDS,
     "cloud cap: " .. #self.clouds .. " > " .. data.INTERACT.MAX_CLOUDS)
end
-- ===== Phase B: universal Pool infusion — Bolt =============================
-- The pool is cast at the MIDPOINT of the player->target ray, so the bolt's swept
-- path always crosses it. Room 1 has a mostly-open lane for +x.
local infuse_combat = require "src.game.combat"
if begin_room() then
  -- 1. Mud pool + Inferno Bolt: merged statuses, one 1.25x hit.
  local e = self.enemies[1]
  if not e then
    sf(false, "infusion mud: no enemy")
  else
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    local mx, my = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                   self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    self.aim.x, self.aim.y = mx, my
    equip(mk("puddle", nil, "earth", "water")); cast1()     -- Mud: root
    self.aim.x, self.aim.y = e.x, e.y
    local sk1 = mk("projectile", nil, "fire", "fire")
    equip(sk1); cast1()                                     -- Inferno Bolt: burn
    local hp0 = 999
    local exp1 = sk1 and sk1.power * 1.25 or 14
    frames(30)
    sf(e.statuses and e.statuses.burn ~= nil, "infusion mud: native burn missing")
    sf(e.statuses and e.statuses.root ~= nil, "infusion mud: pool root missing")
    local keys = 0 for _ in pairs(e.statuses or {}) do keys = keys + 1 end
    sf(keys == 2, "infusion mud: status keys=" .. keys .. " (expected 2)")
    sf(near(hp0 - e.hp, exp1, 0.001),
       "infusion mud: damage " .. (hp0 - e.hp) .. " (expected " .. tostring(exp1) .. ")")
  end
end
if begin_room() then
  -- Control: the same bolt cast with no pool in the room deals base damage.
  local e = self.enemies[1]
  if not e then
    sf(false, "infusion control: no enemy")
  else
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    self.aim.x, self.aim.y = e.x, e.y
    local sk2 = mk("projectile", nil, "fire", "fire")
    equip(sk2); cast1()
    local hp0 = 999
    local exp2 = sk2.power
    frames(30)
    local keys = 0 for _ in pairs(e.statuses or {}) do keys = keys + 1 end
    sf(keys == 1 and e.statuses.burn ~= nil, "infusion control: unexpected statuses")
    sf(near(hp0 - e.hp, exp2, 0.001), "infusion control: damage " .. (hp0 - e.hp) .. " (expected " .. tostring(exp2) .. ")")
  end
end
if begin_room() then
  -- 2. Same-compound infusion: no new status, still 1.25x (Inferno Pool + Inferno Bolt).
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "fire", "fire")); cast1()        -- Inferno Pool
    self.aim.x, self.aim.y = e.x, e.y
    local sk3 = mk("projectile", nil, "fire", "fire")
    equip(sk3); cast1()
    local hp0 = 999
    local exp3 = sk3.power * 1.25
    frames(30)
    local keys = 0 for _ in pairs(e.statuses or {}) do keys = keys + 1 end
    sf(keys == 1, "infusion same-compound: keys=" .. keys .. " (burn should not double)")
    sf(near(hp0 - e.hp, exp3, 0.001), "infusion same-compound: damage " .. (hp0 - e.hp) .. " (expected " .. tostring(exp3) .. ")")
  end
end
if begin_room() then
  -- 3. Three overlapping pools: union of statuses, push present, ONE 1.25x.
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 220)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud: root
    equip(mk("puddle", nil, "wind", "wind")); cast1()        -- Gale: push
    equip(mk("puddle", nil, "fire", "wind")); cast1()        -- Ember: burn+spread
    self.aim.x, self.aim.y = e.x, e.y
    local sk4 = mk("projectile", nil, "fire", "fire")
    equip(sk4); cast1()
    local hp0 = 999
    local exp4 = sk4.power * 1.25
    frames(30)
    for _, want in ipairs({ "burn", "root", "push", "spread" }) do
      sf(e.statuses and e.statuses[want] ~= nil, "infusion 3 pools: missing " .. want)
    end
    -- Pool reactions (DUST DEVIL on the Gale pool vs the Mud area, FIRESTORM vs the Ember
    -- area) add confuse/burn/spread to the Gale pool since the reactions addendum; the
    -- merged union is 5 keys. Duplicates still merge to one application.
    sf(e.statuses and e.statuses.confuse ~= nil, "infusion 3 pools: missing confuse (DUST DEVIL reaction)")
    local keys = 0 for _ in pairs(e.statuses or {}) do keys = keys + 1 end
    sf(keys == 5, "infusion 3 pools: keys=" .. keys .. " (duplicates must merge, expected 5 incl. reaction)")
    sf(near(hp0 - e.hp, exp4, 0.001),
       "infusion 3 pools: damage " .. (hp0 - e.hp) .. " (multiplier must not stack)")
  end
end
if begin_room() then
  -- 4. Push beats pull (Gale pool over a Tide Bolt): the pool's push drives knockback.
  local e = self.enemies[1]
  local kb = {}
  local orig_kb = infuse_combat.knockback
  infuse_combat.knockback = function(ex, ey, sx, sy, strength, toward)
    kb[#kb + 1] = { toward = toward == true }
    return orig_kb(ex, ey, sx, sy, strength, toward)
  end
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 220)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "wind", "wind")); cast1()        -- Gale: push
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("projectile", nil, "water", "water")); cast1()  -- Tide: pull + slow
    frames(30)
    sf(e.statuses and e.statuses.push ~= nil, "infusion push>pull: push missing")
    sf(e.statuses and e.statuses.pull ~= nil, "infusion push>pull: pull missing")
    sf(#kb == 1, "infusion push>pull: knockback calls=" .. #kb)
    if kb[1] then sf(kb[1].toward == false, "infusion push>pull: pool push lost to pull") end
  end
  infuse_combat.knockback = orig_kb
end
if begin_room() then
  -- 5. Mist pool (blind + hide_self): enemy is blinded, never gets hide_self.
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 180)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "water", "wind")); cast1()       -- Mist: blind + hide_self
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    frames(30)
    sf(e.statuses and e.statuses.blind ~= nil, "infusion mist: blind missing")
    sf(not (e.statuses and e.statuses.hide_self), "infusion mist: hide_self leaked onto the enemy")
  end
end
if begin_room() then
  -- 6. Ancient Catalyst scales the MERGED statuses (root from the pool scales too).
  self.relics.ancient_catalyst = true
  self.status_dur_mul = relics_mod.status_duration_mul(self.relics)
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud: root
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    -- The hit applies statuses mid-frame; the first frame root exists, its expiry is
    -- still exactly duration x mul (decrements start the following frame).
    local hit_root, hit_burn
    for _ = 1, 60 do
      self.player.invuln = 5
      frame()
      if e.statuses and e.statuses.root and not hit_root then
        hit_root = e.statuses.root.expiry
        hit_burn = e.statuses.burn and e.statuses.burn.expiry
      end
    end
    sf(hit_root ~= nil, "infusion catalyst: root was never applied")
    sf(hit_root and near(hit_root, 2.0 * 1.2, 0.02),
       "infusion catalyst: root expiry " .. tostring(hit_root))
    sf(hit_burn ~= nil, "infusion catalyst: burn was never applied")
    sf(hit_burn and near(hit_burn, 3.0 * 1.2, 0.02),
       "infusion catalyst: burn expiry " .. tostring(hit_burn))
  end
end

if begin_room() then
  -- 7. Ember pool + Inferno Bolt: e1 burns and spreads; e2 (within 60 px) is ignited.
  local e1 = self.enemies[1]
  local e2 = self.enemies[2]
  if not (e1 and e2) then
    sf(false, "infusion ember: need two enemies, 1=" .. tostring(e1 ~= nil) .. " 2=" .. tostring(e2 ~= nil))
  else
    for _, en in ipairs({ e1, e2 }) do
      en.alive, en.active, en.telegraph, en.immortal = true, true, 0, false
      en.hp, en.speed, en.vx, en.vy = 999, 0, 0, 0
      en.statuses = {}
    end
    place_target(e1, 180)
    e2.x, e2.y = e1.x + 40, e1.y
    if level_mod.blocked(self.level, e2.x, e2.y, e2.radius) then
      e2.x, e2.y = level_mod.free_point_near(self.level, e1.x + 40, e1.y, e2.radius)
    end
    self.aim.x, self.aim.y = self.player_pos.x + (e1.x - self.player_pos.x) * 0.5,
                                self.player_pos.y + (e1.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "fire", "wind")); cast1()        -- Ember: burn + spread
    self.aim.x, self.aim.y = e1.x, e1.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    frames(45)
    sf(e1.statuses and e1.statuses.burn ~= nil, "infusion ember: e1 missing burn")
    sf(e1.statuses and e1.statuses.spread ~= nil, "infusion ember: e1 missing spread (Ember pool)")
    sf(e2.statuses and e2.statuses.burn ~= nil,
       "infusion ember: e2 did not ignite within 60 px")
  end
end
if begin_room() then
  -- 8. A "leaves a trail" Bolt its own trail patches never infuse; no free +25%.
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 150)
    self.aim.x, self.aim.y = e.x, e.y
    local sk5 = mk("projectile", "leaves_trail", "fire", "fire")
    equip(sk5); cast1()
    local hp0 = 999
    local exp5 = sk5.power
    frames(30)
    local tc = 0 for _, p2 in ipairs(self.puddles) do if p2.is_trail then tc = tc + 1 end end
    sf(tc >= 1, "infusion trail: quirk produced no trail patches")
    sf(near(hp0 - e.hp, exp5, 0.001), "infusion trail: damage " .. (hp0 - e.hp) .. " (own trail must not infuse)")
  end
end
-- ===== Phase B follow-up: real-path grace, mid-grace pool death, single accent ==
-- 1a. Within a grace: hit lands ~0.16 s after the bolt leaves the pool -> infused.
if begin_room() then
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.3,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.3
    equip(mk("puddle", nil, "earth", "water")); cast1()
    self.aim.x, self.aim.y = e.x, e.y
    local sk6 = mk("projectile", nil, "fire", "fire")
    equip(sk6); cast1()
    local hp0 = 999
    local exp6 = sk6.power * 1.25
    frames(30)
    sf(e.statuses and e.statuses.root ~= nil, "grace boundary in: infused hit lost the pool's root")
    sf(near(hp0 - e.hp, exp6, 0.001), "grace boundary in: damage " .. (hp0 - e.hp) .. " (expected " .. tostring(exp6) .. ")")
  end
end
-- 1b. After the grace: same setup, bolt slowed down right as it exits the pool, so the
-- hit lands INFUSE_GRACE+ after leaving it -> NOT infused.
if begin_room() then
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.immortal = true, true, false
    e.telegraph = 0
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 220)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.3,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.3
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local pool = self.puddles[#self.puddles]
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    -- Slow the bolt the moment it leaves the pool; the remaining ~130 px at 50 px/s
    -- outlasts INFUSE_GRACE (~2.6 s) without touching the pool.
    local slowed = false
    for _ = 1, 40 do
      self.player.invuln = 5
      frame()
      if self.bolts[1] and pool and not slowed then
        local b = self.bolts[1]
        local dx, dy = b.x - pool.x, b.y - pool.y
        if dx * dx + dy * dy > (pool.radius + b.radius) ^ 2 then
          local d = math.sqrt(b.vx * b.vx + b.vy * b.vy)
          if d > 0 then b.vx, b.vy = b.vx / d * 50, b.vy / d * 50 end
          slowed = true
        end
      end
    end
    sf(slowed, "grace boundary out: bolt never left the pool")
    -- Stop on the frame the bolt connects: damage is read before any burn tick can land.
    local applied
    for _ = 1, 160 do
      self.player.invuln = 5
      frame()
      if e.hp < 999 then applied = e.hp break end
    end
    sf(applied ~= nil, "grace boundary out: bolt never hit the enemy after slowing")
    local sk7 = self.slot1
    local exp7 = sk7.power
    sf(applied and near(999 - applied, exp7, 0.001),
       "grace boundary out: hit after the grace was infused (damage " .. (applied and (999 - applied) or "nil") .. ", expected " .. tostring(exp7) .. ")")
    sf(e.statuses ~= nil and e.statuses.root == nil,
       "grace boundary out: hit after the grace carried the pool's root")
    sf(e.statuses and e.statuses.burn ~= nil, "grace boundary out: native burn missing")
  end
end
-- 2. Pool dies mid-grace: no error, the stored snapshot still applies until grace ends.
if begin_room() then
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, false, 0, false   -- bolts fly through; activate later
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.3,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.3
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local pool = self.puddles[#self.puddles]
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    local errs_before = #errors
    local exited = false
    for _ = 1, 90 do
      self.player.invuln = 5
      frame()
      if self.bolts[1] and pool then
        local b = self.bolts[1]
        local dx, dy = b.x - pool.x, b.y - pool.y
        if dx * dx + dy * dy > (pool.radius + b.radius) ^ 2 then exited = true break end
      end
    end
    sf(exited, "pool death: bolt never left the pool")
    if pool then pool.duration = 0.02 end     -- let its own tick expire it
    frames(3)
    local pool_alive = false
    for _, p2 in ipairs(self.puddles) do if p2 == pool then pool_alive = true end end
    sf(not pool_alive, "pool death: pool did not expire on its own")
    sf(#errors == errs_before, "pool death: an error occurred while the pool expired")
    -- teleport the enemy just ahead of the bolt; the bolt is still inside its grace window
    local b = self.bolts[1]
    sf(b ~= nil, "pool death: bolt vanished before the post-mortem hit")
    if b then
      local d = math.sqrt(b.vx * b.vx + b.vy * b.vy)
      if d > 0 then
        e.x, e.y = b.x + b.vx / d * 24, b.y + b.vy / d * 24
        if level_mod.blocked(self.level, e.x, e.y, e.radius) then
          e.x, e.y = level_mod.free_point_near(self.level, e.x, e.y, e.radius)
        end
        e.active = true
        local hp0 = e.hp
        local exp8 = self.slot1.power * 1.25
        frames(12)
        sf(e.statuses and e.statuses.root ~= nil,
           "pool death: snapshot root missing (pool was already gone)")
        sf(e.statuses and e.statuses.burn ~= nil, "pool death: native burn missing")
        sf(near(hp0 - e.hp, exp8, 0.001),
           "pool death: damage " .. (hp0 - e.hp) .. " (expected " .. tostring(exp8) .. " from the snapshot)")
      end
    end
    sf(#errors == errs_before, "pool death: error on the post-mortem hit")
  end
end
-- 3. Accent fires once per continuous infusion; re-entry during grace does not re-accent;
-- a full expiry + re-entry does.
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  local p = self.player_pos
  local lane = nil
  for L = 420, 340, -20 do
    if level_mod.los(self.level, p.x, p.y, p.x + L, p.y, 4) then lane = L break end
  end
  if not lane then
    sf(false, "infusion accent: east lane under 340 px in room 1")
  else
    local pool_a, pool_b = p.x + 80, p.x + 260
    local accents, was_infused = 0, false
    local function poll()
      local b = self.bolts[1]
      local inf = b and b.infused_visual or false
      if inf and not was_infused then accents = accents + 1 end
      was_infused = inf
      return b
    end
    self.aim.x, self.aim.y = pool_a, p.y
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- pool A (spans ~20..140)
    self.aim.x, self.aim.y = pool_b, p.y
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- pool B (spans ~200..320)
    self.aim.x, self.aim.y = p.x + 600, p.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    if self.bolts[1] then
      self.bolts[1].x, self.bolts[1].y = p.x + 10, p.y      -- just before pool A
      self.bolts[1].vx, self.bolts[1].vy = 450, 0
    end
    for _ = 1, 200 do                                        -- fly through A and B
      self.player.invuln = 5
      frame()
      local b = poll()
      if not b then break end
      if b.x > pool_b + 65 then break end   -- right after B, well inside the probed lane
    end
    sf(accents == 1, "infusion accent: one continuous infusion accented " .. accents .. " time(s)")
    if self.bolts[1] then
      -- leaving both pools: hover in the clear gap until the grace fully elapses
      self.bolts[1].x, self.bolts[1].y = (pool_a + 60 + pool_b - 60) * 0.5, p.y   -- gap centre
      self.bolts[1].vx, self.bolts[1].vy = 0, 0
      for _ = 1, 75 do self.player.invuln = 5; frame(); poll() end
      sf(was_infused == false, "infusion accent: infusion never fully ended")
      -- teleporting back THROUGH A and B while uninfused: a fresh infusion sequence
      self.bolts[1].x, self.bolts[1].y = p.x + 10, p.y
      self.bolts[1].vx, self.bolts[1].vy = 450, 0
      for _ = 1, 40 do self.player.invuln = 5; frame(); poll() end
      sf(accents == 2, "infusion accent: restarted infusion accented " .. accents .. " time(s) (expected 2)")
    else
      sf(false, "infusion accent: bolt despawned before the grace test finished")
    end
  end
end
-- ===== Phase C: universal Pool infusion — Spray (cone) and Nova (burst) =====
local function place_at(e, angle_deg, dist)
  local a = math.rad(angle_deg)
  e.x = self.player_pos.x + math.cos(a) * dist
  e.y = self.player_pos.y + math.sin(a) * dist
  return e.x, e.y
end
local function calm_enemy(e)
  e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
  e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
  e.statuses = {}
end
if begin_room() then
  -- S1: Pool overlapping the cone, caster OUTSIDE the pool -> infused.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 0, 70)
    self.aim.x, self.aim.y = self.player_pos.x + 130, self.player_pos.y
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud at 130 east
    local pool = self.puddles[#self.puddles]
    if pool then pool.radius = 40 end                        -- shrink: spans 90..170, ticks stop at 52 px
    self.aim.x, self.aim.y = self.player_pos.x + 300, self.player_pos.y
    local skc = mk("cone", nil, "fire", "fire")
    equip(skc); cast1()
    frames(30)
    sf(e.statuses and e.statuses.root ~= nil, "spray s1: pool root missing (outside-pool overlap)")
    sf(near(999 - e.hp, skc.power * 1.25, 0.001),
       "spray s1: damage " .. (999 - e.hp) .. " (expected " .. tostring(skc.power * 1.25) .. ")")
    sf(#self.cones == 0, "spray s1: cone did not clean up after resolution")
  end
end
if begin_room() then
  -- S2: Pool BEHIND the caster -> must NOT infuse.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 0, 70)
    self.aim.x, self.aim.y = self.player_pos.x - 100, self.player_pos.y   -- pool WEST of the player
    equip(mk("puddle", nil, "earth", "water")); cast1()
    self.aim.x, self.aim.y = self.player_pos.x + 300, self.player_pos.y
    local skc2 = mk("cone", nil, "fire", "fire")
    equip(skc2); cast1()
    frames(5)
    sf(not (e.statuses and e.statuses.root), "spray s2: a pool behind the caster infused the cone")
    sf(near(999 - e.hp, skc2.power, 0.001), "spray s2: damage " .. (999 - e.hp) .. " (expected " .. tostring(skc2.power) .. ")")
  end
end
if begin_room() then
  -- S3: Pool touching the caster (apex inside) -> infused.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 0, 80)
    self.aim.x, self.aim.y = self.player_pos.x + 15, self.player_pos.y    -- pool at 15px; apex inside (d <= r)
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local pool = self.puddles[#self.puddles]
    if pool then pool.radius = 40 end                        -- e at 80: dist to pool 65 > 52 (no ticks); apex d=15 <= 40 still inside
    self.aim.x, self.aim.y = self.player_pos.x + 300, self.player_pos.y
    local skc3 = mk("cone", nil, "fire", "fire")
    equip(skc3); cast1()
    frames(5)
    sf(e.statuses and e.statuses.root ~= nil, "spray s3: apex-inside pool did not infuse")
    sf(near(999 - e.hp, skc3.power * 1.25, 0.001),
       "spray s3: damage " .. (999 - e.hp) .. " (expected " .. tostring(skc3.power * 1.25) .. ")")
  end
end
if begin_room() then
  -- S4: split cast, two cones evaluated independently. Aim NORTH (open rows).
  local e1 = self.enemies[1]                    -- +130 deg ray: only cone 2 (110 deg) covers it
  local e2 = self.enemies[2]                    -- +50 deg ray: only cone 1 (70 deg) covers it
  local e3 = self.enemies[3]                    -- dead centre: both cones cover it
  local ok = true
  for _, en in ipairs({ e1, e2, e3 }) do
    if not en then ok = false break end
    calm_enemy(en)
  end
  if ok then
    place_at(e1, 130, 50)
    place_at(e2, 50, 60)
    place_at(e3, 90, 40)
    for _, en in ipairs({ e1, e2, e3 }) do
      if level_mod.blocked(self.level, en.x, en.y, en.radius) then
        sf(false, "spray s4: enemy blocked at its angle"); ok = false break
      end
    end
  end
  if ok then
    self.aim.x, self.aim.y = self.player_pos.x + math.cos(math.rad(130)) * 110,
                               self.player_pos.y + math.sin(math.rad(130)) * 110
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud at 130 deg, d=110
    local pool = self.puddles[#self.puddles]
    if pool then pool.radius = 30 end                        -- allow(cone1) = 35 + asin(30/110) = 50.8 < 60
    self.aim.x, self.aim.y = self.player_pos.x, self.player_pos.y + 400   -- aim straight north
    local skc4 = mk("cone", "split_in_two", "fire", "fire")
    equip(skc4); cast1()
    frames(5)
    local cp = skc4.power * 0.6                              -- per-cone power after split
    -- cone1 (70): diff to pool = 60 > 50.8 -> NOT infused; cone2 (110): diff = 20 -> infused
    sf(e2.statuses and e2.statuses.root == nil,
       "spray s4: cone1 absorbed a pool outside its sector (e_neg)")
    sf(near(999 - e2.hp, cp, 0.001), "spray s4: e_neg damage " .. (999 - e2.hp) .. " (expected " .. tostring(cp) .. ")")
    sf(e1.statuses and e1.statuses.root ~= nil, "spray s4: cone2 did not infuse its own sector (e_pos)")
    sf(near(999 - e1.hp, cp * 1.25, 0.001), "spray s4: e_pos damage " .. (999 - e1.hp) .. " (expected " .. tostring(cp * 1.25) .. ")")
    sf(e3.statuses and e3.statuses.root ~= nil, "spray s4: e_mid lost the pool root")
    sf(near(999 - e3.hp, cp + cp * 1.25, 0.001),
       "spray s4: e_mid damage " .. (999 - e3.hp) .. " (expected " .. tostring(cp + cp * 1.25) .. ")")
  end
end
-- ===== Phase C: universal Pool infusion — Nova (burst) ===========================
if begin_room() then
  -- N1a: rim touching (dist == R + r) -> infused.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 180, 30)                                    -- WEST of the player; inside the burst
    self.aim.x, self.aim.y = self.player_pos.x + 130, self.player_pos.y
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- d = 130 = 70 + 60 (boundary)
    local skb1 = mk("burst", nil, "fire", "fire")
    equip(skb1); cast1()
    frames(30)
    sf(e.statuses and e.statuses.root ~= nil, "nova n1a: rim-touching pool did not infuse")
    sf(near(999 - e.hp, skb1.power * 1.25, 0.001),
       "nova n1a: damage " .. (999 - e.hp) .. " (expected " .. tostring(skb1.power * 1.25) .. ")")
    sf(#self.bursts == 0, "nova n1a: burst did not clean up after resolution")
  end
end
if begin_room() then
  -- N1b: one pixel of a gap (dist == R + r + 1) -> NOT infused.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 180, 30)
    self.aim.x, self.aim.y = self.player_pos.x + 131, self.player_pos.y
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- d = 131
    local skb2 = mk("burst", nil, "fire", "fire")
    equip(skb2); cast1()
    frames(5)
    sf(not (e.statuses and e.statuses.root), "nova n1b: a 1 px gap infused the burst")
    sf(near(999 - e.hp, skb2.power, 0.001), "nova n1b: damage " .. (999 - e.hp) .. " (expected " .. tostring(skb2.power) .. ")")
  end
end
if begin_room() then
  -- N2: split Nova, pool alive: main burst (R=70) infuses, delayed b2 (R=50.4) does not.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 180, 30)
    self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y   -- d = 120
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local skb3 = mk("burst", "split_in_two", "fire", "fire")
    equip(skb3); cast1()
    frames(40)                                                             -- main resolves at cast, b2 at +0.3 s
    local bp = skb3.power
    sf(e.statuses and e.statuses.root ~= nil, "nova n2: snapshot root missing")
    sf(near(999 - e.hp, bp * 1.25 + bp * 0.6, 0.001),
       "nova n2: damage " .. (999 - e.hp) .. " (expected " .. tostring(bp * 1.25 + bp * 0.6) .. " = infused main (full power) + native split (0.6x))")
    sf(#self.bursts == 0, "nova n2: split burst did not clean up")
  end
end
if begin_room() then
  -- N3: split Nova, pool at d=60: BOTH bursts infuse (R=70 and R=50.4 cover it).
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 180, 30)
    self.aim.x, self.aim.y = self.player_pos.x + 60, self.player_pos.y
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local skb4 = mk("burst", "split_in_two", "fire", "fire")
    equip(skb4); cast1()
    frames(40)
    local bp3 = skb4.power
    sf(near(999 - e.hp, bp3 * 1.25 + bp3 * 0.6 * 1.25, 0.001),
       "nova n3: damage " .. (999 - e.hp) .. " (expected " .. tostring(bp3 * 1.25 + bp3 * 0.6 * 1.25) .. " = both bursts infused)")
    sf(e.statuses and e.statuses.root ~= nil, "nova n3: root missing")
  end
end
if begin_room() then
  -- N4: split Nova, pool killed before the delayed resolves: b1 infused, b2 is NOT.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 180, 30)
    self.aim.x, self.aim.y = self.player_pos.x + 60, self.player_pos.y
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local pool = self.puddles[#self.puddles]
    local errs_before = #errors
    local skb5 = mk("burst", "split_in_two", "fire", "fire")
    equip(skb5); cast1()
    local bp4 = skb5.power
    if pool then pool.duration = 0.05 end        -- expires well before the +0.3 s split resolves
    frames(40)
    local pool_alive = false
    for _, p2 in ipairs(self.puddles) do if p2 == pool then pool_alive = true end end
    sf(not pool_alive, "nova n4: pool did not expire before the split resolved")
    sf(near(999 - e.hp, bp4 * 1.25 + bp4 * 0.6, 0.001),
       "nova n4: damage " .. (999 - e.hp) .. " (expected " .. tostring(bp4 * 1.25 + bp4 * 0.6) .. "; split must re-test live pools)")
    sf(e.statuses and e.statuses.root ~= nil, "nova n4: main burst snapshot root missing")
    sf(#errors == errs_before, "nova n4: an error occurred during the delayed split")
  end
end
-- ===== Phase D: universal Pool infusion — Orbit (per-orb records) ===============
-- Orbit rotation is frozen in these tests (orb.rev_per_sec = 0) so each orb sits
-- exactly where placed; the engine path (segment test, grace, hits) is unchanged.
if begin_room() then
  -- D1: only the orb whose path crosses the Pool is infused.
  local e1, e2, e3 = self.enemies[1], self.enemies[2], self.enemies[3]
  if e1 and e2 and e3 then
    for _, en in ipairs({ e1, e2, e3 }) do calm_enemy(en) end
    place_at(e1, 0, 70)
    place_at(e2, 120, 70)
    place_at(e3, 240, 70)
    self.aim.x, self.aim.y = self.player_pos.x + 70, self.player_pos.y
    equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud, d=70
    local pool = self.puddles[#self.puddles]
    if pool then pool.radius = 40 end
    local skd = mk("orbit", nil, "fire", "fire")
    equip(skd); cast1()
    local orb = self.orbits[1]
    if orb then orb.rev_per_sec = 0 end
    frames(10)
    local pwr = skd.power
    sf(e1.statuses and e1.statuses.root ~= nil, "orbit d1: crossing orb did not infuse")
    sf(near(999 - e1.hp, pwr * 1.25, 0.001), "orbit d1: e1 damage " .. (999 - e1.hp))
    for _, en in ipairs({ e2, e3 }) do
      sf(not (en.statuses and en.statuses.root), "orbit d1: an orb that never touched the pool infused its hit")
      sf(near(999 - en.hp, pwr, 0.001), "orbit d1: uninfused orb hit for " .. (999 - en.hp) .. " (expected " .. tostring(pwr) .. ")")
    end
    sf(orb and orb.orbs[1].infuse_live and #orb.orbs[1].infuse_live >= 1,
       "orbit d1: orb in the pool has no live infusion entries")
    sf(orb and (#(orb.orbs[2].infuse_live or {}) == 0) and (#(orb.orbs[3].infuse_live or {}) == 0),
       "orbit d1: an orb outside the pool holds infusion entries")
  end
end
if begin_room() then
  -- D2: standing in a Pool — every orb infused continuously, one merged x1.25 hit.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 0, 70)
    self.aim.x, self.aim.y = self.player_pos.x, self.player_pos.y       -- pool at the player
    equip(mk("puddle", "bigger_slower", "earth", "water")); cast1()     -- radius x1.3 ~ 78 (covers the ring)
    local skd2 = mk("orbit", nil, "fire", "fire")
    equip(skd2); cast1()
    local orb = self.orbits[1]
    if orb then orb.rev_per_sec = 0 end
    frames(12)                                       -- < 0.5 s: no pool tick yet
    for j = 1, #(orb and orb.orbs or {}) do
      local lv = orb.orbs[j].infuse_live
      sf(lv and #lv >= 1, "orbit d2: orb " .. j .. " not infused inside the pool")
    end
    local keys = 0 for _ in pairs(e.statuses or {}) do keys = keys + 1 end
    sf(keys == 2, "orbit d2: statuses " .. keys .. " (expected burn+root)")
    sf(near(999 - e.hp, skd2.power * 1.25, 0.001), "orbit d2: damage " .. (999 - e.hp))
  end
end
if begin_room() then
  -- D3: grace per orb through the real loop; pool dying mid-grace keeps the snapshot.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    local p = self.player_pos
    local lane = nil
    for L = 88, 44, -4 do
      if level_mod.los(self.level, p.x, p.y, p.x + L, p.y, 4) then lane = L break end
    end
    if not lane then sf(false, "orbit d3: no clear east lane in room 1") end
    e.x, e.y = p.x + (lane or 70), p.y
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("puddle", nil, "earth", "water")); cast1()
    local pool = self.puddles[#self.puddles]
    if pool then pool.radius = 40 end
    local skd3 = mk("orbit", nil, "fire", "fire")
    equip(skd3); cast1()
    local orb = self.orbits[1]
    if orb then orb.rev_per_sec = 0 end
    local errs_before = #errors
    frames(8)
    local d1 = 999 - e.hp
    sf(near(d1, skd3.power * 1.25, 0.001), "orbit d3: first hit " .. d1 .. " (expected infused)")
    if pool then pool.duration = 0.02 end         -- pool dies mid-grace
    frames(3)
    local pool_alive = false
    for _, p2 in ipairs(self.puddles) do if p2 == pool then pool_alive = true end end
    sf(not pool_alive, "orbit d3: pool did not expire mid-grace")
    orb.enemy_cooldowns = {}
    local hp2 = e.hp
    frames(2)                                     -- hit inside the grace, pool gone
    local d2 = hp2 - e.hp
    sf(near(d2, skd3.power * 1.25, 0.001),
       "orbit d3: hit inside grace after the pool died = " .. d2 .. " (snapshot missing?)")
    sf(e.statuses and e.statuses.root ~= nil, "orbit d3: snapshot root missing after the pool died")
    orb.enemy_cooldowns = {}
    frames(75)                                    -- let the grace fully elapse
    orb.enemy_cooldowns = {}                      -- hits may have fired during the wait
    e.statuses = {}                               -- native-only check is clean now
    local hp3 = e.hp
    frames(2)
    local d3 = hp3 - e.hp
    sf(near(d3, skd3.power, 0.001),
       "orbit d3: hit after the grace = " .. d3 .. " (expected native " .. skd3.power .. ")")
    sf(e.statuses and e.statuses.root == nil and e.statuses.burn ~= nil,
       "orbit d3: after the grace the hit was not native-only")
    sf(#errors == errs_before, "orbit d3: an error occurred (pool death / grace path)")
  end
end
if begin_room() then
  -- D4: one accent per orb per continuous infusion; others never accent.
  for _, en in ipairs(self.enemies) do en.active = false end
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 70, p.y
  equip(mk("puddle", nil, "earth", "water")); cast1()
  local pool = self.puddles[#self.puddles]
  if pool then pool.radius = 40 end
  equip(mk("orbit", nil, "fire", "fire")); cast1()
  local orb = self.orbits[1]
  if orb then orb.rev_per_sec = 0 end
  local o1, o2 = orb.orbs[1], orb.orbs[2]
  local a1, a2 = 0, 0
  local w1, w2 = o1.infused_visual or false, o2.infused_visual or false
  local function poll()
    if o1.infused_visual and not w1 then a1 = a1 + 1 end
    if o2.infused_visual and not w2 then a2 = a2 + 1 end
    w1, w2 = o1.infused_visual or false, o2.infused_visual or false
  end
  for _ = 1, 6 do self.player.invuln = 5; frame(); poll() end
  sf(a1 == 1, "orbit d4: continuous infusion accented " .. a1 .. " times on orb 1")
  sf(a2 == 0, "orbit d4: an orb never touching the pool accented")
  if pool then
    pool.x, pool.y = p.x + 500, p.y + 300          -- orb leaves the pool; grace runs
    for _ = 1, 5 do self.player.invuln = 5; frame(); poll() end
    pool.x, pool.y = p.x + 70, p.y                  -- back on orb 1, still inside grace
    for _ = 1, 3 do self.player.invuln = 5; frame(); poll() end
    sf(a1 == 1, "orbit d4: re-entry during grace re-accented orb 1")
    pool.x, pool.y = p.x + 500, p.y + 300           -- out of the pool for the full grace
    for _ = 1, 75 do self.player.invuln = 5; frame(); poll() end
    sf(w1 == false, "orbit d4: infusion on orb 1 never fully ended")
    pool.x, pool.y = p.x + 70, p.y                  -- fresh infusion -> a second accent
    for _ = 1, 4 do self.player.invuln = 5; frame(); poll() end
    sf(a1 == 2, "orbit d4: restarted infusion accented " .. a1 .. " times (expected 2)")
  end
end
if begin_room() then
  -- D5: an Orbit with leaves_trail stays at base damage inside its own patches.
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 0, 70)
    local skd5 = mk("orbit", "leaves_trail", "fire", "fire")
    equip(skd5); cast1()
    local orb = self.orbits[1]
    if orb then orb.rev_per_sec = 0 end
    local hp0 = 999
    local logs0 = count_logs("^Enemy HP: ")
    frames(45)                                       -- < 1.0 s: no burn tick yet
    local hits = count_logs("^Enemy HP: ") - logs0
    if hits < 1 then
      sf(false, "orbit d5: no hits landed (hits=" .. hits .. ")")
    else
      sf(near((hp0 - e.hp) / hits, skd5.power, 0.001),
         "orbit d5: avg damage/hit " .. ((hp0 - e.hp) / hits) .. " (expected " .. tostring(skd5.power) .. ")")
    end
    sf(trail_count() >= 1, "orbit d5: leaves_trail spawned no patches")
    sf(not (e.statuses and e.statuses.root), "orbit d5: the orbit's own trail infused it")
  end
end
-- D6: orbit parameters are identical with and without a Pool; per-enemy cooldown is 0.5.
local d6 = {}
if begin_room() then
  local skd6 = mk("orbit", nil, "fire", "wind")
  equip(skd6); cast1()
  local o = self.orbits[1]
  d6.n, d6.rev, d6.rad, d6.pow = #o.orbs, o.rev_per_sec, o.orbit_radius, o.power
  d6.dur = o.duration
  o.rev_per_sec = 0                            -- frozen: orb1 stays at east so the enemy is hit on the next frame
  frames(30)
  d6.dur2 = o.duration
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_at(e, 0, 70)
    for _ = 1, 10 do
      self.player.invuln = 5
      frame()
      if o.enemy_cooldowns[e] then
        sf(near(o.enemy_cooldowns[e], 0.5, 1/60 + 0.001),
           "orbit d6: per-enemy cooldown " .. o.enemy_cooldowns[e] .. " (expected 0.5)")
        break
      end
    end
  end
end
if begin_room() then
  equip(mk("puddle", nil, "earth", "water")); cast1()     -- a pool sits in the room
  local skd6b = mk("orbit", nil, "fire", "wind")
  equip(skd6b); cast1()
  local o = self.orbits[1]
  frames(30)
  sf(d6.n == #o.orbs, "orbit d6: orb count changed with a pool in the room")
  sf(d6.rev == o.rev_per_sec, "orbit d6: rev_per_sec changed with a pool in the room")
  sf(d6.rad == o.orbit_radius, "orbit d6: orbit_radius changed with a pool in the room")
  sf(d6.pow == o.power, "orbit d6: power changed with a pool in the room")
  sf(near(d6.dur, o.duration + 30 * (1/60), 0.001), "orbit d6: duration drifted with a pool in the room")
  sf(near(d6.dur2, o.duration, 0.001), "orbit d6: duration after N frames drifted with a pool in the room")
end
if begin_room() then
  -- D7: Orbital Crown's extra orb gets its own record; split_in_two orbits stay independent.
  self.relics.orbital_crown = true
  equip(mk("orbit", nil, "fire", "fire")); cast1()
  local o = self.orbits[1]
  sf(o and #o.orbs == 4, "orbit d7: orbital crown yielded " .. (o and #o.orbs or -1) .. " orbs (expected 4)")
  if o then
    o.rev_per_sec = 0
    local e_a = self.enemies[1]
    local e_b = self.enemies[2]
    calm_enemy(e_a); calm_enemy(e_b)
    -- orb 1 sits at angle 0, orb 2 at angle 2*pi/4 = 90 deg
    local x1, y1 = o.orbs[1].x, o.orbs[1].y
    local x2, y2 = o.orbs[2].x, o.orbs[2].y
    e_a.x, e_a.y = x1, y1
    e_b.x, e_b.y = x2, y2
    self.aim.x, self.aim.y = x1, y1
    equip(mk("puddle", nil, "earth", "water")); cast1()   -- pool on orb 1's spot only
    local pool = self.puddles[#self.puddles]
    if pool then pool.radius = 40 end
    frames(10)
    sf(e_a.statuses and e_a.statuses.root ~= nil, "orbit d7: crown orb 1 was not infused")
    sf(near(999 - e_a.hp, o.power * 1.25, 0.001), "orbit d7: orb 1 hit " .. (999 - e_a.hp) .. " (expected infused)")
    sf(not (e_b.statuses and e_b.statuses.root), "orbit d7: crown orb 2 was infused by a pool on orb 1")
    sf(near(999 - e_b.hp, o.power, 0.001), "orbit d7: orb 2 hit " .. (999 - e_b.hp) .. " (expected base)")
  end
end
if begin_room() then
  -- D7b: split_in_two creates two independent orbit objects with their own records.
  local e_small = self.enemies[1]
  local e_big = self.enemies[2]
  calm_enemy(e_small); calm_enemy(e_big)
  e_small.x, e_small.y = self.player_pos.x + 52, self.player_pos.y   -- small ring (59.5) hits it
  e_big.x, e_big.y = self.player_pos.x + 104, self.player_pos.y      -- only the big ring (80.5) reaches
  self.aim.x, self.aim.y = self.player_pos.x + 100, self.player_pos.y
  equip(mk("puddle", nil, "earth", "water")); cast1()     -- pool at d=100
  local pool = self.puddles[#self.puddles]
  if pool then pool.radius = 20 end                         -- spans 80..120: big ring only (small ring is 40.5 px away > 20+14)
  equip(mk("orbit", "split_in_two", "fire", "fire")); cast1()
  sf(#self.orbits == 2, "orbit d7b: split did not create two orbit objects")
  for _, ob in ipairs(self.orbits) do ob.rev_per_sec = 0 end
  frames(10)
  local sp = 0
  for _, ob in ipairs(self.orbits) do sp = math.max(sp, ob.power) end
  sf(e_small.statuses and e_small.statuses.root == nil, "orbit d7b: small orbit infused by a pool on the big ring")
  sf(near(999 - e_small.hp, sp, 0.001), "orbit d7b: small-orbit hit " .. (999 - e_small.hp) .. " (expected base " .. tostring(sp) .. ")")
  sf(e_big.statuses and e_big.statuses.root ~= nil, "orbit d7b: big orbit not infused by the pool on its ring")
  sf(near(999 - e_big.hp, sp * 1.25, 0.001), "orbit d7b: big-orbit hit " .. (999 - e_big.hp) .. " (expected infused)")
end
if begin_room() then
  -- D8: orbit expiry and a room reset leave no records or tracked visuals behind.
  equip(mk("puddle", nil, "earth", "water")); cast1()
  equip(mk("orbit", nil, "fire", "fire")); cast1()
  frames(5)
  local orb = self.orbits[1]
  if orb then orb.duration = 0.02 end               -- force expiry
  frames(3)
  sf(#self.orbits == 0, "orbit d8: expired orbit object still tracked")
  equip(mk("orbit", nil, "fire", "fire")); cast1()
  frames(5)
  local errs_before = #errors
  self.state = "DEAD"; ui({ action = "continue" })
  sf(#self.orbits == 0, "orbit d8: orbits survived a room reset")
  frames(30)
  sf(#errors == errs_before, "orbit d8: error after a room reset")
end
-- ===== 8. 40-cell infusion matrix: 10 Pool compounds x Bolt/Orbit/Spray/Nova ======
-- Drives do_cast + the update loop (not the module). Spell compound is deliberately
-- different from the pool pair (Ember, or Mud for the Ember row) so the union is non-trivial.
local POOL_PAIRS = {
  { "fire", "fire" }, { "water", "water" }, { "wind", "wind" }, { "earth", "earth" },
  { "fire", "water" }, { "fire", "wind" }, { "earth", "fire" }, { "water", "wind" },
  { "earth", "water" }, { "earth", "wind" },
}
local reaction_mod = require "src.game.reaction"

-- The engine's reaction rule applied to a fresh pool: statuses the pool GAINS when it
-- overlaps the spell's area (pure pools only; the fire-pool+wind cell is Cyclone's).
-- Mirrors reaction_mod.reaction_for — call the module under test rather than duplicate it.
local function reaction_adds(pa, pb, sa, sb)
  local fresh = mk("puddle", nil, pa, pb)
  local fake = { alive = true, duration = 5, is_trail = false, skill_ref = fresh,
                 elements = { pa, pb }, statuses = fresh.statuses, reacted = {} }
  local r = reaction_mod.reaction_for(fake, { sa, sb })
  if r then return r.added end
  return {}
end
local STAT = status_mod.STATUS_DATA
local DIST = { projectile = 150, orbit = 70, cone = 50, burst = 30 }
local matrix_cells = 0
for _, pp in ipairs(POOL_PAIRS) do
  local pa, pb = pp[1], pp[2]
  local pool_els = pa .. "+" .. pb
  local sa, sb = "fire", "wind"
  if pa == "fire" and pb == "wind" then sa, sb = "earth", "water" end
  for _, shape in ipairs({ "projectile", "orbit", "cone", "burst" }) do
    local tag = "matrix " .. pool_els .. "/" .. shape
    local dist = DIST[shape]
    for _, control in ipairs({ false, true }) do
      if begin_room() then
        local e = self.enemies[1]
        if not e then
          sf(false, tag .. ": no enemy")
        else
          calm_enemy(e)
          place_target(e, dist)
          if not control then
            self.aim.x = self.player_pos.x + (e.x - self.player_pos.x) * 0.55
            self.aim.y = self.player_pos.y + (e.y - self.player_pos.y) * 0.55
            equip(mk("puddle", nil, pa, pb)); cast1()
          end
          local skS = mk(shape, nil, sa, sb)
          local want = {}
          for _, n in ipairs(skS.statuses) do if STAT[n] and not STAT[n].on_player then want[n] = true end end
          if not control then
            local psk = mk("puddle", nil, pa, pb)     -- fresh skill, same statuses as the cast pool
            for _, n in ipairs(psk.statuses) do if STAT[n] and not STAT[n].on_player then want[n] = true end end
            -- the pool also gains its reaction over the spell's area — but only bolts live
            -- past the first 0.2 s interaction tick before hitting; cone/burst hits land on
            -- the cast frame and frozen-orb orbits strike within a frame or two, so their
            -- merged union has no reaction statuses yet.
            if shape == "projectile" then
              for _, n in ipairs(reaction_adds(pa, pb, sa, sb)) do
                if STAT[n] and not STAT[n].on_player then want[n] = true end
              end
            end
          end
          local want_n = 0 for _ in pairs(want) do want_n = want_n + 1 end
          self.aim.x, self.aim.y = e.x, e.y
          equip(skS); cast1()
          local orb = self.orbits[1]
          if orb then orb.rev_per_sec = 0 end
          if shape == "projectile" then frames(30) else frames(10) end
          local have_n = 0 for _ in pairs(e.statuses or {}) do have_n = have_n + 1 end
          local missing = {}
          for n in pairs(want) do
            if not e.statuses or not e.statuses[n] then missing[#missing + 1] = n end
          end
          if control then
            sf(have_n == want_n, tag .. ": control statuses=" .. have_n .. " expected " .. want_n)
            sf(#missing == 0, tag .. ": control missing " .. table.concat(missing, ","))
            sf(near(999 - e.hp, skS.power, 0.001),
               tag .. ": control damage " .. (999 - e.hp) .. " (expected " .. skS.power .. ")")
          else
            sf(have_n == want_n, tag .. ": merged statuses=" .. have_n .. " expected " .. want_n)
            sf(#missing == 0, tag .. ": merged missing " .. table.concat(missing, ","))
            sf(near(999 - e.hp, skS.power * 1.25, 0.001),
               tag .. ": damage " .. (999 - e.hp) .. " (expected " .. tostring(skS.power * 1.25) .. ")")
            matrix_cells = matrix_cells + 1
          end
          sf(not (e.statuses and e.statuses.hide_self), tag .. ": hide_self on the enemy")
        end
      end
    end
  end
end
sf(matrix_cells == 40, "matrix: only " .. matrix_cells .. " / 40 cells ran")
-- Accent survives a full 260-particle budget. Assert the accent particle ENTRIES exist in
-- self.particles (flagged accent), never just the flag that precedes dispatch.
local function accent_count()
  local n = 0
  for _, p in ipairs(self.particles) do if p.accent then n = n + 1 end end
  return n
end
local function fill_particles()
  for _ = 1, 260 do
    local id = factory.create("#fx_factory", vmath.vector3(50, 50, 0.1))
    table.insert(self.particles, {
      id = id, x = 50, y = 50, life = 999, max_life = 999,
      vx = 0, vy = 0, r = 1, g = 1, b = 1, a = 1, s0 = 0.1, s1 = 0.1,
    })
  end
end
-- 1. Bolt: accent entries exist at a full budget.
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  sf(#self.particles == 260, "accent budget: pre-fill failed, particles=" .. #self.particles)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y
  equip(mk("puddle", nil, "earth", "water")); cast1()
  local pool = self.puddles[#self.puddles]
  if pool then pool.radius = 40 end
  self.aim.x, self.aim.y = p.x + 150, p.y               -- bolt flies through the pool on the way
  equip(mk("projectile", nil, "fire", "fire")); cast1()
  frames(15)
  sf(accent_count() >= 6, "accent budget: bolt accent missing at a full particle budget (" .. accent_count() .. ")")
  sf(#self.particles > 260, "accent budget: accent added nothing at a full particle budget")
end
-- 2. Spray: accent entries exist at a full budget.
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y
  equip(mk("puddle", nil, "earth", "water")); cast1()
  self.aim.x, self.aim.y = p.x + 300, p.y               -- cone sweeps across the pool
  equip(mk("cone", nil, "fire", "fire")); cast1()
  frames(2)
  sf(accent_count() >= 6, "accent budget: spray accent missing at a full particle budget (" .. accent_count() .. ")")
end
-- 3. Nova: accent entries exist at a full budget.
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y                -- pool near the player: the rim touches it
  equip(mk("puddle", nil, "earth", "water")); cast1()
  self.aim.x, self.aim.y = p.x + 150, p.y
  equip(mk("burst", nil, "fire", "fire")); cast1()
  frames(2)
  sf(accent_count() >= 6, "accent budget: nova accent missing at a full particle budget (" .. accent_count() .. ")")
end
-- 4. Orbit: accent entries exist at a full budget.
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 70, p.y                -- pool on the orb's ring
  equip(mk("puddle", nil, "earth", "water")); cast1()
  equip(mk("orbit", nil, "fire", "fire")); cast1()
  frames(3)
  sf(accent_count() >= 6, "accent budget: orbit accent missing at a full particle budget (" .. accent_count() .. ")")
end
-- 5. Ceiling: with 260 dummies live, many infusion accents stay within ACCENT_CAP (48).
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y                -- pool inside the cone's reach every cast
  for _ = 1, 10 do
    equip(mk("puddle", nil, "earth", "water")); cast1()
    equip(mk("cone", nil, "fire", "fire")); cast1()
  end
  sf(accent_count() == 48,
     "accent ceiling: accents=" .. accent_count() .. " (expected exactly 48)")
  sf(#self.particles == 308,
     "accent ceiling: dummies+accents=" .. #self.particles .. " (expected 308)")
end
-- ===== Infused Spray/Nova visibility: accent entries + toast at a full particle budget ==
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y
  equip(mk("puddle", nil, "water", "wind")); cast1()   -- Mist: no interaction fires, the toast stays infusion-only
  self.aim.x, self.aim.y = p.x + 300, p.y               -- aim east; the cone sweeps the pool
  equip(mk("cone", nil, "fire", "fire")); cast1()
  frames(2)
  sf(accent_count() >= 13,
     "spray visibility: accent entries " .. accent_count() .. " (expected >= 13: 6 fan + 7 axis)")
  sf(self.toast_text == "INFUSED: Mist", "spray visibility: toast " .. tostring(self.toast_text))
  sf((self.toast_t or 0) > 0 and self.toast_t <= 0.8, "spray visibility: toast_t " .. tostring(self.toast_t))
end
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 300, p.y
  equip(mk("cone", nil, "fire", "fire")); cast1()
  frames(2)
  sf(accent_count() == 0, "spray visibility: control cast accented " .. accent_count())
  sf(self.toast_text == nil, "spray visibility: control cast set a toast (" .. tostring(self.toast_text) .. ")")
end
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y                -- pool near the player: the nova rim touches it
  equip(mk("puddle", nil, "water", "wind")); cast1()      -- Mist: no interaction fires
  equip(mk("burst", nil, "fire", "fire")); cast1()
  frames(2)
  sf(accent_count() >= 15,
     "nova visibility: accent entries " .. accent_count() .. " (expected >= 15: 6 fan + 1 ring + 8 rim)")
  sf(self.toast_text == "INFUSED: Mist", "nova visibility: toast " .. tostring(self.toast_text))
end
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  equip(mk("burst", nil, "fire", "fire")); cast1()
  frames(2)
  sf(accent_count() == 0, "nova visibility: control cast accented " .. accent_count())
  sf(self.toast_text == nil, "nova visibility: control cast set a toast")
end
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  fill_particles()
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 75, p.y
  equip(mk("puddle", nil, "water", "wind")); cast1()      -- Mist: no interaction fires
  equip(mk("burst", "split_in_two", "fire", "fire")); cast1()
  frames(2)
  local first = accent_count()
  sf(first >= 15, "nova split: main burst accent entries " .. first .. " (expected >= 15)")
  frames(22)                                        -- ~+0.4 s: the delayed burst has resolved, its accents are live
  local second = accent_count()
  sf(second >= 15, "nova split: delayed burst left no accents (live=" .. second .. ", main was " .. first .. ")")
  sf(self.toast_text == "INFUSED: Mist", "nova split: toast " .. tostring(self.toast_text) .. " (expected INFUSED: Mist)")
end
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  local p = self.player_pos
  self.toast_text, self.toast_t = "BURNING MUD", 1.4     -- an interaction banner is up
  self.aim.x, self.aim.y = p.x + 75, p.y
  equip(mk("puddle", nil, "water", "wind")); cast1()      -- Mist: the banner stays put either way
  self.aim.x, self.aim.y = p.x + 300, p.y
  equip(mk("cone", nil, "fire", "fire")); cast1()
  frames(2)
  sf(self.toast_text == "BURNING MUD", "toast priority: an interaction banner was overwritten by an infusion")
end
if begin_room() then
  for _, en in ipairs(self.enemies) do en.active = false end
  local p = self.player_pos
  self.toast_text, self.toast_t = nil, 0
  self.infuse_toast_until = self.clock + 1.0             -- rate-limited: no re-toast for 1 s
  self.aim.x, self.aim.y = p.x + 75, p.y
  equip(mk("puddle", nil, "water", "wind")); cast1()      -- Mist
  self.aim.x, self.aim.y = p.x + 300, p.y
  equip(mk("cone", nil, "fire", "fire")); cast1()
  frames(2)
  sf(self.toast_text == nil, "toast rate limit: re-toasted within 1.5 s (" .. tostring(self.toast_text) .. ")")
end
-- Grace lifecycle (module contract, deterministic): entry stays live for exactly
-- INFUSE_GRACE after the pool stops overlapping; re-entry refreshes; expired entries prune.
do
  local infuse_mod = require "src.game.infusion"
  local fake_pool = { x = 0, y = 0, radius = 60, alive = true, duration = 5,
                      is_trail = false, skill_ref = {}, statuses = { "root" }, color = { r = 1, g = 1, b = 1 } }
  local rec = infuse_mod.touch(nil, fake_pool, 100)       -- enters at t=100
  infuse_mod.release(rec, fake_pool, 101, 1.0)            -- leaves at t=101
  local lv = infuse_mod.active(rec, 101.5)
  sf(lv and #lv == 1, "grace: entry shed before the grace ended")
  rec = infuse_mod.touch(rec, fake_pool, 101.6)           -- re-entry refreshes, not duplicated
  lv = infuse_mod.active(rec, 101.7)
  sf(lv and #lv == 1, "grace: re-entry did not refresh the entry")
  infuse_mod.release(rec, fake_pool, 101.7, 1.0)          -- leaves again; grace ends at 102.7
  lv = infuse_mod.active(rec, 102.69)
  sf(lv and #lv == 1, "grace: entry shed before 1.0 s elapsed")
  lv = infuse_mod.active(rec, 102.71)
  sf(lv == nil or #lv == 0, "grace: entry outlived INFUSE_GRACE")
  -- pool dying mid-grace must not error and must not resurrect an in-flight effect
  rec = infuse_mod.touch(nil, fake_pool, 200)
  fake_pool.alive = false                                  -- pool dies while overlapping
  infuse_mod.release(rec, fake_pool, 200.5, 1.0)
  lv = infuse_mod.active(rec, 201.0)
  sf(lv and #lv == 1, "grace: pool dying mid-grace dropped a live entry")
  sf(lv and lv[1] and lv[1].statuses and lv[1].statuses[1] == "root",
     "grace: entry statuses were not the snapshot from touch")
  lv = infuse_mod.active(rec, 201.51)
  sf(lv == nil or #lv == 0, "grace: entry survived past the grace after the pool died")
  local pool_keys = 0
  for k in pairs(rec) do if type(k) == "table" then pool_keys = pool_keys + 1 end end
  sf(pool_keys == 0, "grace: expired entries were not pruned from the record")
end
-- Room reset while the reset happens with a live infused bolt pending: records die with the spell.
if begin_room() then
  local e = self.enemies[1]
  if e then
    e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
    e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
    e.statuses = {}
    place_target(e, 200)
    self.aim.x, self.aim.y = self.player_pos.x + (e.x - self.player_pos.x) * 0.5,
                              self.player_pos.y + (e.y - self.player_pos.y) * 0.5
    equip(mk("puddle", nil, "earth", "water")); cast1()
    self.aim.x, self.aim.y = e.x, e.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    frames(10)                                     -- bolt is inside/past the pool now
    local errs_before = #errors
    self.state = "DEAD"; ui({ action = "continue" })  -- room reset: bolts are cleared
    sf(#self.bolts == 0, "infusion reset: bolts survived a room reset")
    frames(30)
    sf(#errors == errs_before, "infusion reset: leftover callback errored")
  end
end
-- Room reset while split/repeat/trail/interaction effects are pending.
if begin_room() then
  equip(mk("burst", "split_in_two")); cast1()
  equip(mk("projectile", "repeat_once")); cast1()
  equip(mk("puddle", nil, "fire", "water")); cast1()
  equip(mk("puddle", nil, "earth", "wind")); cast1()
  frames(5)
  sf(#self.spell_areas > 0, "cleanup: no spell areas created before the reset")
  local errs_before = #errors
  self.player.hp = 0; self.player.alive = false; self.state = "DEAD"
  ui({ action = "continue" })
  sf(#self.spell_areas == 0, "cleanup: spell areas survived a room reset")
  sf(#self.clouds == 0, "cleanup: clouds survived a room reset")
  sf(#self.repeat_casts == 0, "cleanup: pending repeats survived a room reset")
  frames(60)
  sf(#errors == errs_before, "cleanup: pending timer errored after reset: " .. tostring(errors[errs_before + 1]))
end
self.state = "DEAD"; ui({ action = "continue" })

-- ===== Phase B: Fire Cyclone - wind growing a lingering fire pool =========
-- The wind pool is a normal pool in self.puddles; the fire pool must never be cloned.
local CYCLONE_CYC = require "src.core.data"
local function calm_enemy(e)
  e.alive, e.active, e.telegraph, e.immortal = true, true, 0, false
  e.hp, e.speed, e.vx, e.vy = 999, 0, 0, 0
  e.statuses = {}
end

-- Kill the wind: drop Gale areas' remaining to 0 (they vanish and stop extending), set
-- every Gale pool's duration near-zero so its own tick passes, and collapse every live
-- cyclone's until_time so decay begins immediately.
local function has_element(list, want)
  for _, v in ipairs(list or {}) do if v == want then return true end end
  return false
end
local function force_wind_gone(self)
  for _, a in ipairs(self.spell_areas) do
    if has_element(a.elements, "wind") then a.remaining = 0 end
  end
  for _, p in ipairs(self.puddles) do
    if has_element(p.elements, "wind") then p.duration = math.min(p.duration or 0, 0.05) end
    if p.cyclone then p.cyclone.until_time = 0 end
  end
end

local function settle_pools(self) -- reduce all enemies to next to nothing; no target needed
  for _, en in ipairs(self.enemies) do en.active = false end
end

local function wait_cyclone_clear(self, base, frames_budget)
  -- after the wind is gone, wait until the pool reports it has decayed back to base or the budget runs out
  local n = frames_budget or 120
  for i = 1, n do
    if #self.puddles == 0 then return true end
    local p = self.puddles[1]
    if p and (p.cyclone == nil or near(p.radius, base, 0.001)) then return true end
    frame()
  end
  return false
end

if begin_room() then
  -- 1. Wind over a fire pool: grows to the cap and stops there; never a second fire pool.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()      -- Magma pool at (60,0)
  local pool = self.puddles[1]
  local base_r = pool and pool.radius
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)      -- Gale pool on the same spot
  frames(130)                                             -- ~2.2 s: enough to hit the cap
  sf(pool and pool.radius == data.INTERACT.CYCLONE_MAX_RADIUS,
     "cyclone: did not reach the cap (" .. tostring(pool and pool.radius) .. ")")
  local fire_pools = 0
  for _, p in ipairs(self.puddles) do if p.compound == "Magma" then fire_pools = fire_pools + 1 end end
  sf(fire_pools == 1, "cyclone: wind created a second fire pool (" .. fire_pools .. ")")
  sf(pool and pool.cyclone ~= nil, "cyclone: record missing at the cap")
  force_wind_gone(self)
  frames(90)                                              -- until passes; decay into base
  if pool then sf(pool.cyclone == nil, "cyclone: record not cleared back at base (" .. tostring(pool.radius) .. ")") end
  sf(pool and near(pool.radius, base_r, 0.001),
     "cyclone: radius did not return to base (" .. tostring(pool and pool.radius) .. " vs " .. tostring(base_r) .. ")")
end

if begin_room() then
  -- 2. Re-casting wind extends the wind time (until grows, radius keeps growing).
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(15)
  local until1 = pool.cyclone and pool.cyclone.until_time
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(15)
  local until2 = pool.cyclone and pool.cyclone.until_time
  sf(until1 and until2 and until2 > until1,
     "cyclone: re-cast wind did not extend (" .. tostring(until1) .. " -> " .. tostring(until2) .. ")")
  sf(pool.cyclone ~= nil, "cyclone: record lost on extend")
end

if begin_room() then
  -- 3. Wind ends: back to the exact pre-cyclone radius, record cleared, pool expires normally.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  local base_r = pool and pool.radius
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(30)                                              -- cyclone started, some growth done
  force_wind_gone(self)
  frames(90)                                              -- decay into base
  sf(pool and pool.cyclone == nil, "cyclone: record not cleared (base=" .. tostring(pool and pool.cyclone and pool.cyclone.base) .. ")")
  sf(pool and near(pool.radius, base_r, 0.001),
     "cyclone: radius did not return to base (" .. tostring(pool and pool.radius) .. " vs " .. tostring(base_r) .. ")")
  pool.duration = 0.05
  local n_before = #self.puddles
  frames(10)
  sf(#self.puddles == n_before - 1, "cyclone: pool did not expire normally after the cyclone")
end

if begin_room() then
  -- 4. Pool expires mid-growth: no error, no leaked visual.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(10)
  local pool = self.puddles[1]
  local errs_before = #errors
  if pool then pool.duration = 0.01 end
  frames(3)
  local still = false
  for _, p in ipairs(self.puddles) do if p == pool then still = true end end
  sf(not still, "cyclone: pool did not expire mid-growth")
  sf(pool and live[pool.vis] == nil, "cyclone: pool visual leaked after expiry")
  sf(#errors == errs_before, "cyclone: error during mid-growth expiry")
end

if begin_room() then
  -- 5a. Ember Pool alone starts no cyclone on itself.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "fire", "wind")); cast1()      -- Ember pool (fire + wind)
  local ember = self.puddles[1]
  local ember0 = ember and ember.radius
  frames(30)
  sf(ember and ember.radius == ember0, "cyclone: Ember Pool started a cyclone on itself")
  sf((self.toast_t or 0) == 0, "cyclone: Ember Pool showed a banner on itself")
end

if begin_room() then
  -- 5b. Ember Pool over a separate fire pool: the fire pool cyclones, the Ember Pool does not.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()      -- Magma
  local magma = self.puddles[1]
  equip(mk("puddle", nil, "fire", "wind")); cast1()      -- Ember pool on the same spot
  local ember = self.puddles[2]
  local ember0 = ember and ember.radius
  frames(20)
  sf(magma and magma.radius > 60, "cyclone: Ember Pool did not start a cyclone on the fire pool")
  sf(ember and ember.radius == ember0, "cyclone: the Ember Pool started one on itself too")
end

if begin_room() then
  -- 6. A trail patch never counts as fire: wind over it starts no cyclone.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("projectile", "leaves_trail", "wind", "wind")); cast1()  -- decals: wind trail bolt, drops patches
  frames(80)
  local tc = 0
  for _, pp in ipairs(self.puddles) do if pp.is_trail then tc = tc + 1 end end
  sf(tc >= 1, "trail: leaves_trail bolt produced no patches")
  local first = nil
  for _, pp in ipairs(self.puddles) do if pp.is_trail then first = pp break end end
  if first then
    local base_r = first.radius
    equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)                   -- Gale wind over the trail patches
    frames(60)
    sf(first.cyclone == nil, "cyclone: trail patch started a cyclone")
    sf(near(first.radius, base_r, 0.001), "cyclone: trail patch grew a cyclone (" .. tostring(first.radius) .. ")")
  end
end

if begin_room() then
  -- 7. A wind Bolt over a fire pool starts and extends via CYCLONE_BOLT_WIND_TIME.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()      -- pool at (60,0)
  local pool = self.puddles[1]
  local base_r = pool.radius
  equip(mk("projectile", nil, "wind", "wind")); cast1()   -- Gale bolt along the same line
  frames(80)                                              -- bolt reaches (~450+ px/s): at 60px it passes quickly
  sf(pool.cyclone ~= nil, "cyclone: wind bolt did not start a cyclone")
  if pool.cyclone then
    sf(pool.cyclone.until_time - self.clock <= data.INTERACT.CYCLONE_BOLT_WIND_TIME + 1,
       "cyclone: bolt wind time is over CYCLONE_BOLT_WIND_TIME (diff=" .. tostring(pool.cyclone.until_time - self.clock) .. ")")
  end
  sf(pool.radius > base_r, "cyclone: wind bolt did not grow the pool")
end

if begin_room() then
  -- 7b. Burning Mud counts as fire for the bolt path too (and after the fire pool dies).
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud pool
  equip(mk("puddle", nil, "fire", "fire")); cast1()        -- Inferno pool over it
  frames(15)
  local mud = self.puddles[1]
  sf(mud and mud.burning_mud == true, "burning mud: not ignited")
  for _, p in ipairs(self.puddles) do if p ~= mud then p.duration = 0.05 end end
  frames(3)
  local base_r = mud.radius
  equip(mk("projectile", nil, "wind", "wind")); cast1()    -- Gale bolt across the mud
  frames(80)
  sf(mud and mud.cyclone ~= nil, "cyclone: wind bolt did not treat Burning Mud as fire")
  sf(mud and mud.radius > base_r, "cyclone: Burning Mud pool did not grow (" .. tostring(mud and mud.radius) .. ")")
end

if begin_room() then
  -- 8. A pool at/above the cap: no cyclone, no banner.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  pool.radius = data.INTERACT.CYCLONE_MAX_RADIUS            -- the cap
  self.toast_text = nil
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(20)
  sf(pool.cyclone == nil, "cyclone: cap-sized pool started a cyclone")
  sf((self.toast_t or 0) == 0, "cyclone: cap-sized pool showed a banner")
  sf(pool.radius == data.INTERACT.CYCLONE_MAX_RADIUS, "cyclone: cap-sized pool was rescaled to " .. pool.radius)
end

if begin_room() then
  -- 9. Bigger-but-slower fire pool: grows from 78, decays back to 78.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", "bigger_slower", "earth", "fire")); cast1()
  local pool = self.puddles[1]
  sf(near(pool.radius, 78, 0.01), "cyclone: bigger_slower pool is not 78 (" .. tostring(pool.radius) .. ")")
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  force_wind_gone(self)
  frames(90)
  sf(pool.cyclone == nil, "cyclone: grew but never returned to 78")
  sf(near(pool.radius, 78, 0.001), "cyclone: bigger_slower pool did not decay back to 78 (" .. tostring(pool.radius) .. ")")
end

if begin_room() then
  -- 10. Banner on start; no banner while only extending.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(15)
  sf(self.toast_text == "FIRE CYCLONE" and (self.toast_t or 0) > 0,
     "cyclone: no readable banner on start")
  local until1 = pool.cyclone and pool.cyclone.until_time
  self.toast_text, self.toast_t = nil, 0
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(15)
  sf(pool.cyclone and pool.cyclone.until_time > until1, "cyclone: second wind did not extend")
  sf((self.toast_t or 0) == 0, "cyclone: second wind re-showed the banner")
end

if begin_room() then
  -- 11. vis and ring scale track the radius while cyclonic and return to base exactly.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  local base_r = pool.radius
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(5)
  local sc = pool.radius / 64 * 2
  sf(live[pool.vis] and live[pool.vis].scale and near(live[pool.vis].scale.x, sc * 0.85, 0.001),
     "cyclone: vis scale does not track the radius (" .. tostring(live[pool.vis] and live[pool.vis].scale and live[pool.vis].scale.x) .. ")")
  sf(live[pool.ring] and live[pool.ring].scale and near(live[pool.ring].scale.x, sc, 0.001),
     "cyclone: ring scale does not track the radius (" .. tostring(live[pool.ring] and live[pool.ring].scale and live[pool.ring].scale.x) .. ")")
  force_wind_gone(self)
  frames(90)
  local sbc = base_r / 64 * 2
  local lvm = live[pool.vis]
  local lrg = live[pool.ring]
  sf(lvm ~= nil and lrg ~= nil,
     "cyclone: pool visual(s) missing after decay (vis=" .. tostring(pool.vis) .. " ring=" .. tostring(pool.ring) .. ")")
  sf(lvm and lvm.scale and near(lvm.scale.x, sbc * 0.85, 0.001),
     "cyclone: vis scale did not return to base (" .. tostring(lvm and lvm.scale and lvm.scale.x) .. ")")
  sf(lrg and lrg.scale and near(lrg.scale.x, sbc, 0.001),
     "cyclone: ring scale did not return to base (" .. tostring(lrg and lrg.scale and lrg.scale.x) .. ")")
end

if begin_room() then
  -- 12a. A bolt that misses at base radius is not infused through any growth.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y + 80                -- pool 80 px off the bolt flight line
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  sf(pool ~= nil and pool.radius == 60, "cyclone: magma pool misplaced")
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 150)                                    -- bolt flies east, 80 px shy of the pool
    self.aim.x, self.aim.y = p.x + 150, p.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    frames(80)
    sf(not (e.statuses and e.statuses.slow), "cyclone: bolt infused at base radius (should stay uninfused)")
  end
end

if begin_room() then
  -- 12b. The grown cyclone infuses the same bolt that missed at base.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y + 80
  equip(mk("puddle", nil, "earth", "fire")); cast1()          -- Magma pool at (60, 80)
  sf(self.puddles[1] ~= nil, "cyclone: magma pool not placed")
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)          -- Gale over it
  frames(120)                                                -- grow toward the cap
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 150)                                    -- same bolt line as 12a
    self.aim.x, self.aim.y = p.x + 150, p.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    frames(80)
    sf(e.statuses and e.statuses.slow ~= nil,
       "cyclone: bolt through the grown cyclone was not infused")
  end
  local hint = self.puddles[1]
  force_wind_gone(self)
  frames(90)
  sf(hint == nil or hint.cyclone == nil, "cyclone: grew but did not decay back to nil record")
end

if begin_room() then
  -- 12c. A bolt that is not infused after the cyclone has decayed.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y + 80
  equip(mk("puddle", nil, "earth", "fire")); cast1()          -- Magma pool
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)          -- Gale over it
  frames(120)                                                -- grown
  force_wind_gone(self)
  frames(90)                                                 -- decay back
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 150)
    self.aim.x, self.aim.y = p.x + 150, p.y
    equip(mk("projectile", nil, "fire", "fire")); cast1()
    frames(80)
    sf(not (e.statuses and e.statuses.slow), "cyclone: bolt infused after the cyclone decayed")
  end
end

if begin_room() then
  -- 13. New wind during decay resumes the vortex; no second banner.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  local pool = self.puddles[1]
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(130)                                                -- grow to (cap)
  force_wind_gone(self)
  frames(30)                                                 -- decay begins
  local mid = pool.radius
  sf(mid < data.INTERACT.CYCLONE_MAX_RADIUS and mid > 60, "decay resume: pool not mid-decay (" .. tostring(mid) .. ")")
  sf(self.toast_text ~= "FIRE CYCLONE" or (self.toast_t or 0) == 0, "decay resume: FIRE CYCLONE banner lingered into decay")
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)            -- fresh wind mid-decay
  frames(10)
  sf(pool.radius > mid, "decay resume: fresh wind did not resume growth (" .. tostring(pool.radius) .. " vs " .. tostring(mid) .. ")")
  sf(self.toast_text ~= "FIRE CYCLONE" or (self.toast_t or 0) == 0, "decay resume: second FIRE CYCLONE banner re-shown")
end

if begin_room() then
  -- 16. No pool is spawned while a cyclone grows: absolute count stays constant.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()      -- Magma
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)       -- Gale over it
  local n_before = #self.puddles
  frames(130)                                             -- cap it out, checking no extra pools
  sf(#self.puddles == n_before, "cyclone: pool count changed during growth (" .. #self.puddles .. " vs " .. n_before .. ")")
end

if begin_room() then
  -- 17. Burning Mud counts as fire for the ticker path as well as the bolt path.
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "water")); cast1()      -- Mud pool
  equip(mk("puddle", nil, "fire", "fire")); cast1()        -- Inferno pool over it
  frames(15)
  local mud = self.puddles[1]
  sf(mud and mud.burning_mud == true, "ticker: mud was never ignited")
  for _, pd in ipairs(self.puddles) do if pd ~= mud then pd.duration = 0.05 end end   -- let the fire pool die (bolt path only tests the bolt)
  frames(3)
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)        -- Gale pool over the burning mud (ticker route)
  frames(60)                                              -- several interaction ticks
  sf(mud and mud.cyclone ~= nil, "ticker: Burning Mud did not cyclone via the ticker path")
  sf(mud and mud.radius > 60, "ticker: Burning Mud pool did not grow via the ticker path (" .. tostring(mud and mud.radius) .. ")")
end

if begin_room() then
  -- 18. reset: no cyclone records survive, and live objects return to exactly the pristine baseline.
  local function clean_reset()
    self.state = "DEAD"; ui({ action = "continue" })
    frames(30)
    return count()
  end
  local pristine = clean_reset()                            -- like-for-like: reset without casting
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(5)
  local after = clean_reset()
  sf(#self.puddles == 0, "cyclone reset: pools survived a room reset")
  sf(#self.puddles == 0 and #self.spell_areas == 0, "cyclone reset: spell areas survived a room reset")
  sf(after == pristine, "cyclone reset: live objects drifted (" .. after .. " vs " .. pristine .. ")")
end

if begin_room() then
  -- 14. Room reset and run reset leave no cyclone behind; the count returns to baseline.
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "fire")); cast1()
  equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
  frames(5)
  local errs_before = #errors
  self.state = "DEAD"; ui({ action = "continue" })
  sf(#self.puddles == 0, "cyclone reset: pools survived a room reset")
  frames(30)
  sf(#errors == errs_before, "cyclone reset: error after the reset")
end

-- 15. Fixed-seed comparison: the cyclone path consumes no gameplay RNG.
do
  local PURITY_SEED = 0xC0FFEE
  local real_random = math.random
  local seq_a = {}
  local function record()
    math.random = function(...)
      local v = real_random(...)
      seq_a[#seq_a + 1] = v
      return v
    end
  end
  local function seq_str(t)
    local parts = {}
    for _, v in ipairs(t) do parts[#parts + 1] = string.format("%.10g", v) end
    return table.concat(parts, ",")
  end
  local got_a, got_b
  record()
  if begin_room(PURITY_SEED) then
    for _, en in ipairs(self.enemies) do en.active = false end
    self.motes = {}                                 -- mask mote recycle RNG (cosmetic-only, unrelated)
    local p = self.player_pos
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "fire")); cast1()
    local pool = self.puddles[1]
    if pool then pool.color = nil end
    frames(40)
  end
  got_a = seq_a
  seq_a = {}
  record()
  if begin_room(PURITY_SEED) then
    for _, en in ipairs(self.enemies) do en.active = false end
    self.motes = {}                                 -- mask mote recycle RNG (cosmetic-only, unrelated)
    local p = self.player_pos
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "fire")); cast1()
    local pool = self.puddles[1]
    if pool then pool.color = nil end
    equip(mk("puddle", nil, "fire", "wind")); cast1()  -- mixed: never reacts; wind present; burn+spread never blind (no wander-RNG)
    for _, pp in ipairs(self.puddles) do pp.color = nil end
    frames(40)
  end
  got_b = seq_a
  math.random = real_random
  sf(#got_a > 0, "rng: room consumed no RNG at all (comparison is vacuous)")
  sf(seq_str(got_a) == seq_str(got_b), "rng: the cyclone path consumed gameplay RNG")
end

-- C. Steam + Dust -> one Dense Cloud that blinds and confuses, then cleans up.
-- C. Steam + Dust -> one Dense Cloud that blinds and confuses, then cleans up.
if begin_room() then
  equip(mk("puddle", nil, "fire", "water")); cast1()
  equip(mk("puddle", nil, "earth", "wind")); cast1()
  frames(15)
  sf(#self.clouds == 1, "dense cloud: clouds=" .. #self.clouds)
  sf(self.toast_text == "DENSE CLOUD" and (self.toast_t or 0) > 0,
     "dense cloud: no readable banner")
  local cloud = self.clouds[1]
  if cloud then
    local vis = cloud.vis
    local e = self.enemies[1]
    sf(e ~= nil, "dense cloud: no enemy to test on")
    if e then
      e.x, e.y = cloud.x, cloud.y
      e.alive, e.active = true, true
      e.hp, e.immortal = 999, true
      e.statuses = {}
      frames(35)
      sf(status_mod.has(e, "blind"), "dense cloud: no blind")
      sf(status_mod.has(e, "confuse"), "dense cloud: no confuse")
    end
    frames(150)
    sf(#self.clouds == 0, "dense cloud: not cleaned up after its lifetime")
    sf(vis == nil or live[vis] == nil, "dense cloud: visual leaked")
  end
end
-- Interactions near a wall must never place a pool inside it.
if begin_room() then
  local fx, fy, wx, wy
  local dirs = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
  for r = 1, level_mod.ROWS do
    for c = 1, level_mod.COLS do
      if not level_mod.SOLID[self.level.grid[r][c]] then
        for _, d in ipairs(dirs) do
          local nc, nr = c + d[1], r + d[2]
          if nc >= 1 and nc <= level_mod.COLS and nr >= 1 and nr <= level_mod.ROWS
             and level_mod.SOLID[self.level.grid[nr][nc]] then
            fx, fy = level_mod.cell_center(c, r)
            wx, wy = level_mod.cell_center(nc, nr)
            break
          end
        end
      end
      if fx then break end
    end
    if fx then break end
  end
  sf(fx ~= nil, "boundary: no wall-adjacent floor cell")
  if fx then
    self.player_pos.x, self.player_pos.y = fx, fy
    self.aim.x, self.aim.y = wx, wy
    equip(mk("puddle", nil, "earth", "water")); cast1()
    equip(mk("puddle", nil, "fire", "fire")); cast1()
    equip(mk("puddle", nil, "wind", "water")); cast1()  -- pure wind pool: cyclone only needs wind; may react (banner suppressed by banner fix)
    frames(20)
    local inside = 0
    for _, p in ipairs(self.puddles) do
      if level_mod.is_solid(self.level, p.x, p.y) then inside = inside + 1 end
    end
    sf(inside == 0, "boundary: " .. inside .. " pool(s) placed inside a wall")
    sf(#self.spell_areas <= data.INTERACT.MAX_SPELL_AREAS, "boundary: too many spell areas")
    sf(#self.clouds <= data.INTERACT.MAX_CLOUDS, "boundary: too many clouds")
  end
end
-- Unbounded creation: 60 casts and many interaction pairs stay capped.
if begin_room() then
  local sk = mk("puddle", nil)
  for _ = 1, 60 do equip(sk); cast1() end
  sf(#self.spell_areas <= data.INTERACT.MAX_SPELL_AREAS,
     "area cap: " .. #self.spell_areas .. " > " .. data.INTERACT.MAX_SPELL_AREAS)
  for _ = 1, 10 do
    equip(mk("puddle", nil, "fire", "water")); cast1()
    equip(mk("puddle", nil, "earth", "wind")); cast1()
  end
  frames(20)
  sf(#self.clouds <= data.INTERACT.MAX_CLOUDS,
     "cloud cap: " .. #self.clouds .. " > " .. data.INTERACT.MAX_CLOUDS)
end

-- ===== Phase C: COMBO_DATA and the Combos screen ===========================
local combos_mod = require "src.core.combos"

if begin_room() then
  -- C1. COMBO_DATA: exactly ten entries; names unique and upper-case.
  sf(#data.COMBO_DATA == 10, "combos: expected 10 COMBO_DATA entries (got " .. #data.COMBO_DATA .. ")")
  local seen = {}
  for _, c in ipairs(data.COMBO_DATA) do
    sf(type(c.name) == "string" and c.name == string.upper(c.name),
       "combos: name not upper-case (" .. tostring(c.name) .. ")")
    sf(not seen[c.name], "combos: duplicate name " .. c.name)
    seen[c.name] = true
    sf(type(c.description) == "string" and #c.description > 0,
       "combos: empty description for " .. c.name)
    sf(type(c.short) == "string" and #c.short > 0 and #c.short <= 48,
       "combos: short missing or > 48 chars for " .. tostring(c.name))
  end
end
if begin_room() then
  -- C2. The panel body is exactly ten "NAME: short" lines, one per COMBO_DATA entry,
  -- in COMBO_DATA order (the shared builder the HUD uses).
  local body = combos_mod.panel_text()
  local lines = {}
  for line in body:gmatch("[^\n]+") do lines[#lines + 1] = line end
  sf(#lines == #data.COMBO_DATA,
     "combos: panel has " .. #lines .. " line(s) for " .. #data.COMBO_DATA .. " entries")
  for i, c in ipairs(data.COMBO_DATA) do
    sf(lines[i] == c.name .. ": " .. c.short,
       "combos: panel line " .. i .. " is \"" .. tostring(lines[i]) .. "\" expected \"" .. c.name .. ": " .. c.short .. "\"")
  end
end
if begin_room() then
  -- C3. FIRE CYCLONE banner reads from COMBO_DATA. Gale pool over an Inferno pool: the
  -- Inferno pool also reacts to the Gale area (FIRESTORM statuses) but the FIRE CYCLONE
  -- banner was announced first in section B, so the reaction banner must not overwrite it.
  for _, en in ipairs(self.enemies) do en.active = false end
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "fire", "fire")); cast1()   -- Inferno pool
  equip(mk("puddle", nil, "wind", "wind")); cast1()   -- Gale pool over it
  frames(15)
  sf(self.toast_text == data.COMBO_DATA[1].name, "combos: fire cyclone banner=" .. tostring(self.toast_text))
end
if begin_room() then
  -- C4. BURNING MUD banner reads from COMBO_DATA. Inferno pool over Mud: the Inferno pool
  -- also reacts to the Mud area (MOLTEN GROUND statuses) but the BURNING MUD banner was
  -- announced first in section A, so the reaction banner must not overwrite it.
  equip(mk("puddle", nil, "earth", "water")); cast1()
  equip(mk("puddle", nil, "fire", "fire")); cast1()   -- Inferno pool over Mud
  frames(25)
  sf(self.toast_text == data.COMBO_DATA[2].name, "combos: burning mud banner=" .. tostring(self.toast_text))
end
if begin_room() then
  -- C5. DENSE CLOUD banner reads from COMBO_DATA.
  for _, en in ipairs(self.enemies) do en.active = false end
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "fire", "water")); cast1()
  equip(mk("puddle", nil, "earth", "wind")); cast1()
  frames(15)
  sf(self.toast_text == data.COMBO_DATA[3].name, "combos: dense cloud banner=" .. tostring(self.toast_text))
end
if begin_room() then
  -- C6. combos from TITLE enters COMBOS.
  self.state = "TITLE"
  ui({ action = "combos" })
  sf(self.state == "COMBOS", "combos: action from TITLE did not enter COMBOS (state=" .. tostring(self.state) .. ")")
end
if begin_room() then
  -- C7. back returns to TITLE.
  self.state = "TITLE"
  ui({ action = "combos" })
  ui({ action = "back" })
  sf(self.state == "TITLE", "combos: back did not return to TITLE (state=" .. tostring(self.state) .. ")")
end
if begin_room() then
  -- C8a. combos ignored in ROOM.
  equip(mk("puddle", nil, "fire", "water")); cast1()  -- mixed pool: never reacts; banner only needs fire
  self.state = "ROOM"
  ui({ action = "combos" })
  sf(self.state == "ROOM", "combos: action leaked into ROOM (state=" .. tostring(self.state) .. ")")
end
if begin_room() then
  -- C8b. combos ignored in DEAD.
  self.state = "DEAD"
  ui({ action = "combos" })
  sf(self.state == "DEAD", "combos: action leaked into DEAD (state=" .. tostring(self.state) .. ")")
end
if begin_room() then
  -- C8c. combos ignored in WIN.
  self.state = "WIN"
  ui({ action = "combos" })
  sf(self.state == "WIN", "combos: action leaked into WIN (state=" .. tostring(self.state) .. ")")
end
if begin_room() then
  -- C9. CREDITS still opens from TITLE and back returns to TITLE.
  self.state = "TITLE"
  ui({ action = "credits" })
  sf(self.state == "CREDITS", "credits: action from TITLE did not open CREDITS (state=" .. tostring(self.state) .. ")")
  ui({ action = "back" })
  sf(self.state == "TITLE", "credits: back did not return to TITLE (state=" .. tostring(self.state) .. ")")
end

-- ===== Pool reactions (addendum): six combos, one generic rule ==================
-- Per-cell source puddle pairs. skillgen sorts each pair's elements alphabetically,
-- so the "listed order" rule picks elements[1] first. The source is mixed
-- {pool_element, spell_element} so the source pool itself is never eligible to react
-- (only pure pools react), its own element is skipped, and it carries no wind element
-- that could start a Fire Cyclone on a fire pool. spell_areas are cleared below so
-- cells never leak into each other (pool spell areas live 5 s).
local RXN_SRC = {
  ["fire>water"]  = { "fire", "water" },
  ["fire>earth"]  = { "fire", "earth" },
  ["water>fire"]  = { "water", "fire" },
  ["water>wind"]  = { "water", "wind" },
  ["water>earth"] = { "water", "earth" },
  ["wind>fire"]   = { "wind", "fire" },
  ["wind>water"]  = { "wind", "water" },
  ["wind>earth"]  = { "wind", "earth" },
  ["earth>fire"]  = { "earth", "fire" },
  ["earth>water"] = { "earth", "water" },
  ["earth>wind"]  = { "earth", "wind" },
}
local RXN_EXPECT = {
  fire  = { water = "steam_vent", earth = "molten_ground" },
  water = { fire = "steam_vent", wind = "squall", earth = "quagmire" },
  wind  = { fire = "firestorm", water = "squall", earth = "dust_devil" },
  earth = { fire = "molten_ground", water = "quagmire", wind = "dust_devil" },
}
local RXN_CELLS = {}
for p, row in pairs(RXN_EXPECT) do for s, id in pairs(row) do
  RXN_CELLS[#RXN_CELLS+1] = { p, s, id }
end end
table.sort(RXN_CELLS, function(a, b) if a[1] == b[1] then return a[2] < b[2] end return a[1] < b[1] end)
local function rxn_cast(pool_el, spell_el)
  local s = RXN_SRC[pool_el .. ">" .. spell_el]
  equip(mk("puddle", nil, s[1], s[2])); cast1()
end
-- Exact expected status adds per cell (pool, spell), pre-filtered against a fresh pure pool.
local RXN_ADD = {
  ["fire>water"]  = { "push", "blind" },
  ["fire>earth"]  = { "slow" },                -- Inferno already burns
  ["water>fire"]  = { "push", "blind" },
  ["water>wind"]  = { "blind" },               -- hide_self is never added
  ["water>earth"] = { "root" },
  ["wind>fire"]   = { "burn", "spread" },
  ["wind>water"]  = { "blind" },
  ["wind>earth"]  = { "confuse" },
  ["earth>fire"]  = { "burn", "slow" },
  ["earth>water"] = { "root" },
  ["earth>wind"]  = { "confuse" },
}
local RXN_TICK_WAIT = 35                     -- reaction lands at the first 0.15 s ticker tick
local RXN_TICK_FRAMES = 30                   -- pool tick interval is 0.5 s
local RXN_REVERT_FRAMES = 200                -- > REACTION_TIME (180 frames)
local reaction_cells_done = 0

for _, cell in ipairs(RXN_CELLS) do
  local pool_el, spell_el, combo_id = cell[1], cell[2], cell[3]
  local tag = "rx " .. pool_el .. "+" .. spell_el
  local added = RXN_ADD[pool_el .. ">" .. spell_el]
  if begin_room() then
    -- Pool spell areas live 5 s; clear them so reaction cells never leak into each other.
    self.spell_areas = {}
    local e = self.enemies[1]
    if e then
      calm_enemy(e)
      place_target(e, 120)                    -- enemy stands in the pool (pool cast at x+120)
      self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
      equip(mk("puddle", nil, pool_el, pool_el)); cast1()
      local pud = self.puddles[1]
      if pud then pud.duration = 30 end          -- outlive the whole test (5 s default would expire mid-suite)
      local base = {}
      if pud then for i, s in ipairs(pud.statuses) do base[i] = s end end
      local base_vis = pud and live[pud.vis] and live[pud.vis].tint_val
      local base_ring = pud and pud.ring and live[pud.ring] and live[pud.ring].tint_val
      rxn_cast(pool_el, spell_el)
      frames(RXN_TICK_WAIT)
      sf(pud and pud.reaction ~= nil, tag .. ": reaction did not start")
      sf(pud and pud.reaction and pud.reaction.id == combo_id,
         tag .. ": combo id " .. tostring(pud and pud.reaction and pud.reaction.id) .. " expected " .. combo_id)
      if pool_el == "wind" and spell_el == "fire" then
        -- The source pool (Ember, fire+wind) is a fire pool by is_fire_pool: section B
        -- cyclones it and announces FIRE CYCLONE in the same tick; section D's reaction
        -- banner is suppressed by the banner priority fix.
        sf(pud and self.toast_text == "FIRE CYCLONE",
           tag .. ": banner " .. tostring(self.toast_text) .. " expected FIRE CYCLONE (cyclone toast wins)")
      else
        sf(pud and self.toast_text == data.COMBO_BY_ID[combo_id].name,
           tag .. ": banner " .. tostring(self.toast_text) .. " expected " .. data.COMBO_BY_ID[combo_id].name)
      end
      if pud then
        local ok_count = 0
        for _, s in ipairs(added) do if list_has(pud.statuses, s) then ok_count = ok_count + 1 end end
        sf(ok_count == #added, tag .. ": added only " .. ok_count .. "/" .. #added .. " of the expected statuses")
        sf(#pud.statuses == #base + #added,
           tag .. ": statuses=" .. #pud.statuses .. " expected " .. (#base + #added) .. " (base " .. #base .. " + added " .. #added .. ")")
        if pud.vis and live[pud.vis] and live[pud.vis].tint_val and base_vis then
          local tv = live[pud.vis].tint_val
          local shifted = tv.r ~= base_vis.r or tv.g ~= base_vis.g or tv.b ~= base_vis.b
          sf(shifted, tag .. ": pool tint did not shift toward the source element")
        end
      end
      frames(RXN_TICK_FRAMES)                  -- let the pool tick with the added statuses
      if e then
        local missing = {}
        for _, s in ipairs(added) do
          if not (e.statuses and e.statuses[s] ~= nil) then missing[#missing + 1] = s end
        end
        sf(#missing == 0, tag .. ": enemy missing " .. table.concat(missing, ",") .. " on the pool tick")
      end
      frames(RXN_REVERT_FRAMES)               -- past REACTION_TIME
      if pud then
        sf(pud.reaction == nil, tag .. ": reaction did not revert")
        local same = #pud.statuses == #base
        if same then
          for i, s in ipairs(base) do if pud.statuses[i] ~= s then same = false break end end
        end
        sf(same, tag .. ": statuses not restored to the exact base list (got " .. table.concat(pud.statuses, ",") .. ")")
        if base_vis and live[pud.vis] and live[pud.vis].tint_val then
          local tv, bv = live[pud.vis].tint_val, base_vis
          sf(tv.r == bv.r and tv.g == bv.g and tv.b == bv.b and tv.a == bv.a,
             tag .. ": pool tint not restored EXACTLY to base (got " .. string.format("%.3f %.3f %.3f %.3f", tv.r, tv.g, tv.b, tv.a) .. ")")
        end
        if base_ring and pud.ring and live[pud.ring] and live[pud.ring].tint_val then
          local tr, br = live[pud.ring].tint_val, base_ring
          sf(tr.r == br.r and tr.g == br.g and tr.b == br.b and tr.a == br.a,
             tag .. ": ring tint not restored EXACTLY to base")
        end
        -- Latch: the same pair never fires twice on one pool.
        self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
        rxn_cast(pool_el, spell_el); frames(RXN_TICK_WAIT)
        sf(pud.reaction == nil, tag .. ": same pair reacted again (latch broken)")
        -- A different pair can still react after the first reverts.
        local others = {}
        for other in pairs(RXN_EXPECT[pool_el]) do if other ~= spell_el then others[#others + 1] = other end end
        table.sort(others)
        if #others > 0 then
          local other_el = others[1]
          local other_id = RXN_EXPECT[pool_el][other_el]
          self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
          rxn_cast(pool_el, other_el); frames(RXN_TICK_WAIT)
          sf(pud.reaction ~= nil and pud.reaction.id == other_id,
             tag .. ": different pair after revert id=" .. tostring(pud.reaction and pud.reaction.id) .. " expected " .. other_id)
        end
      end
      reaction_cells_done = reaction_cells_done + 1
    end
  end
end
sf(reaction_cells_done == 11, "reactions: only " .. reaction_cells_done .. "/11 reaction cells ran")

-- The Inferno + wind cell belongs to Fire Cyclone; it never fires a reaction.
if begin_room() then
  self.aim.x, self.aim.y = self.player_pos.x + 60, self.player_pos.y
  equip(mk("puddle", nil, "fire", "fire")); cast1()
  local pud = self.puddles[1]
  equip(mk("puddle", nil, "fire", "wind")); cast1()  -- Ember: mixed, never reacts; fire+wind is Cyclone's cell
  frames(15)
  sf(pud and pud.reaction == nil, "rx fire+wind: reacted (the Fire Cyclone cell)")
  sf(pud and pud.cyclone ~= nil, "rx fire+wind: Fire Cyclone did not start")
  sf(self.toast_text == "FIRE CYCLONE", "rx fire+wind: banner " .. tostring(self.toast_text) .. " expected FIRE CYCLONE")
end

-- A fire Bolt over a pure Gale pool: firestorm fires on the Gale pool, NO Fire Cyclone
-- competes (the bolt's element reacts directly through bolt_interactions).
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "wind", "wind")); cast1()   -- pure Gale pool
  local gale = self.puddles[1]
  if gale then gale.duration = 30 end
  self.spell_areas = {}                                -- no spell-area cross-talk from the Gale pool's own area
  self.aim.x, self.aim.y = gale.x, gale.y              -- fire bolt straight onto the pool
  equip(mk("projectile", nil, "fire", "fire")); cast1()
  local b = self.bolts[1]
  if b then b.x, b.y = gale.x, gale.y; b.vx, b.vy = 0, 0 end   -- park the bolt on the pool
  frames(4)
  sf(gale and gale.reaction and gale.reaction.id == "firestorm",
     "rx fire-bolt-over-gale: combo id " .. tostring(gale and gale.reaction and gale.reaction.id) .. " expected firestorm")
  sf(self.toast_text == "FIRESTORM",
     "rx fire-bolt-over-gale: banner " .. tostring(self.toast_text) .. " expected FIRESTORM")
  sf(gale and gale.cyclone == nil,
     "rx fire-bolt-over-gale: Fire Cyclone started on the Gale pool (should be absent)")
end

-- Dedicated test: pure Gale pool over pure Inferno pool.
-- Fire Cyclone starts on the Inferno pool (wind over fire), Inferno gains NO reaction
-- statuses (fire+wind is the excluded cell), and the Gale pool gains FIRESTORM statuses
-- (burn, spread) from the fire area -- the reaction applies but its banner is suppressed
-- by the Fire Cyclone banner already up (banner priority, requirement 1).
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.spell_areas = {}                                    -- no leakage from earlier cells
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "fire", "fire")); cast1()        -- Inferno pool (pure fire)
  local inferno = self.puddles[1]
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "wind", "wind")); cast1()         -- Gale pool over it (pure wind)
  frames(RXN_TICK_WAIT)
  sf(inferno and inferno.cyclone ~= nil, "pure gale+inferno: Inferno cyclone did not start")
  sf(self.toast_text == "FIRE CYCLONE", "pure gale+inferno: banner " .. tostring(self.toast_text) .. " expected FIRE CYCLONE (reaction banner suppressed)")
  local gale
  for _, pp in ipairs(self.puddles) do if pp.elements[1] == "wind" then gale = pp end end
  sf(gale and gale.reaction and gale.reaction.id == "firestorm",
     "pure gale+inferno: Gale did not gain FIRESTORM (got " .. tostring(gale and gale.reaction and gale.reaction.id) .. ")")
  -- Inferno pool gains no reaction statuses from the wind (fire+wind is the excluded cell).
  if inferno then
    local has_reaction_status = false
    for _, s in ipairs({ "push", "blind", "slow", "root", "confuse", "spread" }) do
      if list_has(inferno.statuses, s) then has_reaction_status = true end
    end
    sf(not has_reaction_status, "pure gale+inferno: Inferno pool gained reaction statuses from wind (fire+wind cell is excluded)")
  end
  -- Gale gained firestorm statuses (burn, spread).
  if gale then
    sf(list_has(gale.statuses, "burn"), "pure gale+inferno: Gale missing burn from FIRESTORM")
    sf(list_has(gale.statuses, "spread"), "pure gale+inferno: Gale missing spread from FIRESTORM")
  end
end

-- SQUALL adds blind and never hide_self.
if begin_room() then
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 120)                     -- enemy stands in the Tide pool
    self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
    equip(mk("puddle", nil, "water", "water")); cast1()      -- Tide
    equip(mk("puddle", nil, "water", "wind")); cast1()        -- Mist: water skipped (pool's own element), wind -> SQUALL
    frames(RXN_TICK_WAIT + RXN_TICK_FRAMES)
    sf(e.statuses and e.statuses.blind ~= nil, "squall: enemy not blinded by the pool tick")
    sf(not (e.statuses and e.statuses.hide_self), "squall: hide_self reached the enemy")
  end
end
-- A Steam spell over a Gale pool: listed first (fire) wins deterministically.
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "wind", "wind")); cast1()        -- Gale
  local gale = self.puddles[#self.puddles]
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "fire", "water")); cast1()       -- Steam: listed fire first
  frames(RXN_TICK_WAIT)
  sf(gale and gale.reaction and gale.reaction.id == "firestorm",
     "rx listed order: expected firestorm (fire first), got " .. tostring(gale and gale.reaction and gale.reaction.id))
end

-- Mixed pools never react; Burning Mud stays Burning Mud; trail patches never react.
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "water")); cast1()        -- Mud: mixed
  equip(mk("puddle", nil, "fire", "water")); cast1()         -- Steam: mixed, has fire
  frames(RXN_TICK_WAIT)
  local mud = self.puddles[1]
  sf(mud and mud.reaction == nil, "mixed: Mud reacted")
  sf(mud and mud.burning_mud == true, "mixed: Burning Mud did not fire")
  -- Trail patches never count as pools for reactions.
  equip(mk("projectile", "leaves_trail", "wind", "wind")); cast1()
  frames(60)
  for _, pp in ipairs(self.puddles) do
    if pp.is_trail then sf(pp.reaction == nil, "trail: patch reacted") end
  end
end

-- Two overlapping pure pools of different elements each react, one banner per tick.
if begin_room() then
  settle_pools(self)
  self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
  equip(mk("puddle", nil, "water", "water")); cast1()        -- Tide cast first
  equip(mk("puddle", nil, "wind", "wind")); cast1()          -- Gale overlapping
  frames(RXN_TICK_WAIT)
  local tide, gale
  for _, pp in ipairs(self.puddles) do
    if pp.elements[1] == "water" then tide = pp elseif pp.elements[1] == "wind" then gale = pp end
  end
  sf(tide and tide.reaction ~= nil, "pair: tide did not react to the gale area")
  sf(gale and gale.reaction ~= nil, "pair: gale did not react to the tide area")
  sf(self.toast_text == "SQUALL", "pair: banner " .. tostring(self.toast_text) .. " (expected SQUALL, one banner per tick)")
end

-- A pool's own area can never react against that same pool (source == pud guard).
-- Synthetic lookalike: a foreign-element "own" area is injected by hand.
if begin_room() then
  settle_pools(self)
  self.aim.x, self.aim.y = self.player_pos.x + 60, self.player_pos.y
  equip(mk("puddle", nil, "fire", "fire")); cast1()          -- Inferno pool, one pool only
  local pud = self.puddles[1]
  table.insert(self.spell_areas, {
    elements = { "earth", "earth" },                          -- foreign pair, would be MOLTEN GROUND
    x = pud.x, y = pud.y, radius = pud.radius + 60,
    remaining = 5, source = pud, handled = {},
  })
  frames(RXN_TICK_WAIT)
  sf(pud and pud.reaction == nil, "own-area: reaction fired through the pool's own area")
  sf(self.toast_text ~= "MOLTEN GROUND", "own-area: banner leaked from the pool's own area")
end

-- A bolt in flight triggers a reaction through bolt_interactions.
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "earth")); cast1()        -- Quake
  self.aim.x, self.aim.y = p.x + 400, p.y
  equip(mk("projectile", nil, "wind", "wind")); cast1()      -- Gale bolt through the pool
  frames(40)
  local pud = self.puddles[1]
  sf(pud and pud.reaction ~= nil and pud.reaction.id == "dust_devil",
     "bolt: Quake did not react through bolt_interactions (got " .. tostring(pud and pud.reaction and pud.reaction.id) .. ")")
end

-- A cyclone-grown pool still reacts; both can be active on the same pool.
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "fire", "fire")); cast1()          -- Inferno
  local pud = self.puddles[1]
  equip(mk("puddle", nil, "wind", "water")); cast1()         -- mixed wind source: cyclone only, never reacts
  frames(60)
  equip(mk("puddle", nil, "fire", "water")); cast1()         -- Steam source: fire + water
  frames(RXN_TICK_WAIT)
  sf(pud and pud.cyclone ~= nil, "cyclone+reaction: Fire Cyclone not active on the Inferno pool")
  sf(pud and pud.reaction ~= nil and pud.reaction.id == "steam_vent",
     "cyclone+reaction: steam_vent not active alongside the cyclone (got " .. tostring(pud and pud.reaction and pud.reaction.id) .. ")")
end

-- Infusion carries the reaction-scoped statuses into hits while the reaction is live.
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 180)                 -- on the bolt path, beyond both pools; never in a pool
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "earth")); cast1()     -- Quake (stun)
    equip(mk("puddle", nil, "fire", "water")); cast1()     -- Steam -> MOLTEN GROUND (burn+slow) on the Quake pool
    frames(RXN_TICK_WAIT)
    local pud = self.puddles[1]
    sf(pud and pud.reaction and pud.reaction.id == "molten_ground", "infusion: setup reaction did not fire (got " .. tostring(pud and pud.reaction and pud.reaction.id) .. ")")
    self.aim.x, self.aim.y = p.x + 400, p.y
    equip(mk("projectile", nil, "wind", "wind")); cast1()   -- Gale bolt: native push only, burn/slow come only from infusion
    frames(40)
    sf(e.statuses and e.statuses.burn ~= nil, "infusion: bolt missed molten_ground burn while the reaction was live")
    sf(e.statuses and e.statuses.slow ~= nil, "infusion: bolt missed molten_ground slow while the reaction was live")
    sf(e.statuses and e.statuses.blind ~= nil, "infusion: bolt not infused by the steam pool on the same line (test setup broken; blind lasts 2 s)")
  end
end
-- Infusion does NOT carry the reaction statuses after the reaction reverted (fresh room).
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 180)                 -- on the bolt path, beyond both pools; never in a pool
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "earth")); cast1()     -- Quake (stun)
    equip(mk("puddle", nil, "fire", "water")); cast1()     -- Steam -> MOLTEN GROUND (burn+slow) on the Quake pool
    frames(RXN_TICK_WAIT)
    frames(RXN_REVERT_FRAMES)                            -- reaction ends
    self.aim.x, self.aim.y = p.x + 400, p.y
    equip(mk("projectile", nil, "wind", "wind")); cast1()   -- Gale bolt: native push only, burn/slow come only from infusion
    frames(40)
    sf(e.statuses == nil or e.statuses.burn == nil, "infusion: bolt carried molten_ground burn after the reaction ended")
    sf(e.statuses == nil or e.statuses.slow == nil, "infusion: bolt carried molten_ground slow after the reaction ended")
    sf(e.statuses and e.statuses.stun ~= nil, "infusion: bolt missing the pool's native quake stun after the revert (infusion broke)")
    sf(e.statuses and e.statuses.blind ~= nil, "infusion: bolt not infused by the steam pool on the same line (test setup broken; blind lasts 2 s)")
  end
end

-- Pool expires mid-reaction: nothing crashes and nothing leaks.
if begin_room() then
  settle_pools(self)
  self.aim.x, self.aim.y = self.player_pos.x + 60, self.player_pos.y
  equip(mk("puddle", nil, "earth", "earth")); cast1()
  equip(mk("puddle", nil, "earth", "water")); cast1()
  frames(RXN_TICK_WAIT)
  local pud = self.puddles[1]
  local errs_before = #errors
  if pud then pud.duration = 0.01 end
  frames(3)
  local still = false
  for _, pp in ipairs(self.puddles) do if pp == pud then still = true end end
  sf(not still, "expiry: pool survived a forced expiry mid-reaction")
  sf(#errors == errs_before, "expiry: error produced while expiring a reacting pool")
end

-- Room reset clears everything the reaction touched.
if begin_room() then
  settle_pools(self)
  self.aim.x, self.aim.y = self.player_pos.x + 60, self.player_pos.y
  equip(mk("puddle", nil, "earth", "earth")); cast1()
  equip(mk("puddle", nil, "earth", "water")); cast1()
  frames(RXN_TICK_WAIT)
  local errs_before = #errors
  self.state = "DEAD"; ui({ action = "continue" })
  sf(#self.puddles == 0, "reset: pools survived a room reset during a reaction")
  frames(30)
  sf(#errors == errs_before, "reset: error after the room reset")
end

-- A control Pool with no overlap never reacts (same setup, pool placed beyond the source area).
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 400, p.y               -- control pool, out of the Mud area
  equip(mk("puddle", nil, "earth", "earth")); cast1()
  local ctrl = self.puddles[1]
  local base = {}
  if ctrl then for i, s in ipairs(ctrl.statuses) do base[i] = s end end
  self.aim.x, self.aim.y = p.x + 60, p.y                -- source area cast far away from it
  equip(mk("puddle", nil, "earth", "water")); cast1()   -- Mud -> QUAGMIRE would fire on overlap only
  frames(RXN_TICK_FRAMES)
  sf(ctrl and ctrl.reaction == nil, "control: pool with no overlap reacted")
  local same = ctrl ~= nil and #ctrl.statuses == #base
  if same then for i, s in ipairs(base) do if ctrl.statuses[i] ~= s then same = false break end end end
  sf(same, "control: statuses changed with no overlap (control pool corrupted)")
end

-- QUAGMIRE carries root into bolt infusion while the reaction is live...
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 180)
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "earth")); cast1()   -- Quake (stun)
    equip(mk("puddle", nil, "earth", "water")); cast1()   -- Mud -> QUAGMIRE (root) on the Quake pool
    frames(RXN_TICK_WAIT)
    local pud = self.puddles[1]
    sf(pud and pud.reaction and pud.reaction.id == "quagmire",
       "root infusion: setup reaction did not fire (got " .. tostring(pud and pud.reaction and pud.reaction.id) .. ")")
    self.aim.x, self.aim.y = p.x + 400, p.y
    equip(mk("projectile", nil, "wind", "wind")); cast1()   -- Gale bolt: native push only
    frames(40)
    sf(e.statuses and e.statuses.root ~= nil, "root infusion: bolt missed quagmire root while the reaction was live")
    sf(e.statuses and e.statuses.stun ~= nil, "root infusion: bolt missed the quake native stun while the reaction was live")
  end
end
-- ...and NOT after the revert. The Mud source pool natively roots anything infused from it,
-- so it is given duration = 2 s (dies before the revert) and NO longer infuses the bolt
-- once that happens. Then only the Quake pool can infuse: it carries stun always, root
-- only during the reaction.
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  local e = self.enemies[1]
  if e then
    calm_enemy(e)
    place_target(e, 180)
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "earth")); cast1()   -- Quake (stun), duration 5 s
    equip(mk("puddle", nil, "earth", "water")); cast1()   -- Mud -> QUAGMIRE (root), expires at 2 s
    if self.puddles[2] then self.puddles[2].duration = 2 end
    frames(RXN_TICK_WAIT)
    frames(RXN_REVERT_FRAMES)                            -- reaction reverts by clock; Mud is dead
    self.aim.x, self.aim.y = p.x + 400, p.y
    equip(mk("projectile", nil, "wind", "wind")); cast1()   -- fresh Gale bolt
    frames(40)
    sf(e.statuses == nil or e.statuses.root == nil, "root infusion: bolt carried quagmire root after the reaction ended")
    sf(e.statuses and e.statuses.stun ~= nil, "root infusion: bolt missing the quake native stun after the revert (infusion broke)")
  end
end

-- Room reset and run reset leave no pud.reaction records; live objects return to the
-- like-for-like pristine baseline (reset without casting), AGENTS #37 discipline.
local reset_probe = {}
if begin_room() then
  -- Like-for-like control: a room is reset without any casts, for a comparable baseline.
  self.state = "DEAD"; ui({ action = "continue" })
  frames(30)
  reset_probe.pristine = count()
end
if begin_room() then
  settle_pools(self)
  local p = self.player_pos
  self.aim.x, self.aim.y = p.x + 60, p.y
  equip(mk("puddle", nil, "earth", "earth")); cast1()     -- Quake
  equip(mk("puddle", nil, "earth", "water")); cast1()     -- Mud -> QUAGMIRE on the Quake pool
  frames(RXN_TICK_WAIT)
  local pud = self.puddles[1]
  sf(pud and pud.reaction and pud.reaction.id == "quagmire",
     "reset: reaction did not start (got " .. tostring(pud and pud.reaction and pud.reaction.id) .. ")")
  local errs_before = #errors
  self.state = "DEAD"; ui({ action = "continue" })        -- room reset: the run restarts
  frames(30)
  reset_probe.after = count()
  sf(#self.puddles == 0, "reset: pools (and pud.reaction records) survived a reset")
  sf(#self.spell_areas == 0, "reset: spell areas survived a reset with a live reaction")
  sf(#errors == errs_before, "reset: error after the reset with a live reaction")
  sf(reset_probe.after == reset_probe.pristine,
     "reset: live objects drifted (" .. tostring(reset_probe.after) .. " vs " .. tostring(reset_probe.pristine) .. ")")
end

-- ===== Phase B: UI layout (pure Lua; the harness never runs gui.*) ===========
local ui_layout = require "src.ui.layout"
for _, screen in ipairs({ "TITLE", "COMBOS", "CREDITS" }) do
  local scr = ui_layout.SCREENS[screen]
  for i, b in ipairs(scr.buttons) do
    sf(b.x >= 0 and b.y >= 0 and b.x + b.w <= ui_layout.DESIGN_W and b.y + b.h <= ui_layout.DESIGN_H,
       "layout " .. screen .. "." .. b.id .. ": rect leaves the design area")
    sf(b.h >= ui_layout.BUTTON_MIN_H and b.w >= ui_layout.BUTTON_MIN_W,
       "layout " .. screen .. "." .. b.id .. ": below minimum size (w=" .. b.w .. " h=" .. b.h .. ")")
    for j = i + 1, #scr.buttons do
      local o = scr.buttons[j]
      local overlap = b.x < o.x + o.w and o.x < b.x + b.w and b.y < o.y + o.h and o.y < b.y + b.h
      sf(overlap == false, "layout " .. screen .. "." .. b.id .. " overlaps " .. o.id)
    end
  end
end
do -- registry hit test and ordering (z = reverse insertion)
  local h = ui_layout.hit("TITLE", 480, 362)
  sf(h and h.id == "start_box", "layout: TITLE hit at START centre expected start_box, got " .. tostring(h and h.id))
  sf(ui_layout.hit("TITLE", 480, 362) and ui_layout.hit("TITLE", 480, 362).action == "start",
     "layout: TITLE start_box hit did not return the start action")
  sf(ui_layout.hit("TITLE", 0, 0) == nil, "layout: TITLE hit at (0,0) expected nil")
  sf(ui_layout.hit("COMBOS", 480, 58) and ui_layout.hit("COMBOS", 480, 58).action == "back",
     "layout: COMBOS back button hit failed")
  sf(ui_layout.hit("CREDITS", 480, 58) and ui_layout.hit("CREDITS", 480, 58).action == "back",
     "layout: CREDITS back button hit failed")
end
do -- text_width measures the widest line, not the whole multi-line blob
  local one = ui_layout.text_width("single line", 14)
  sf(one == #"single line" * 14 * ui_layout.MONO_ADVANCE, "layout text_width: single-line formula changed")
  local s128 = string.rep("b", 128)
  local multi = ui_layout.text_width("aaa\n" .. s128 .. "\ncc", 14)
  sf(multi == 128 * 14 * ui_layout.MONO_ADVANCE, "layout text_width: multi-line returned " .. tostring(multi))
  sf(ui_layout.text_width("", 14) == 0, "layout text_width: empty string expected 0 width")
  sf(ui_layout.text_width("l1\nl2\nl3\nliii", 14) == 4 * 14 * ui_layout.MONO_ADVANCE, "layout text_width: widest of 4 lines wrong")
end
do -- wrap determinism + no line longer than the limit
  local a = ui_layout.wrap("one two three four five six seven eight nine ten eleven twelve thirteen fourteen", 20)
  sf(#a == 5, "layout wrap: expected 5 lines got " .. #a)
  local longest = 0 for _, l in ipairs(a) do longest = math.max(longest, #l) end
  sf(longest <= 20, "layout wrap: line longer than limit (" .. longest .. ")")
  local b1 = ui_layout.wrap("COMBOS PANEL text wraps here", 20)
  local b2 = ui_layout.wrap("COMBOS PANEL text wraps here", 20)
  sf(table.concat(b1, "|") == table.concat(b2, "|"), "layout wrap: not deterministic")
  sf(#ui_layout.wrap("", 20) == 0, "layout wrap: empty text expected empty list")
end
do -- button actions match the proven game actions per screen
  local seen = {}
  for _, b in ipairs(ui_layout.SCREENS.TITLE.buttons) do seen[b.action] = true end
  sf(seen.start and seen.combos and seen.credits, "layout TITLE: missing start/combos/credits action")
  local s = {}
  for _, b in ipairs(ui_layout.SCREENS.COMBOS.buttons) do s[b.action] = true end
  sf(s.back == true, "layout COMBOS: missing back action")
  local s2 = {}
  for _, b in ipairs(ui_layout.SCREENS.CREDITS.buttons) do s2[b.action] = true end
  sf(s2.back == true, "layout CREDITS: missing back action")
end
do -- the ui_audit binding exists (debug-key row contract)
  local binding = io.open("input/game.input_binding", "r")
  local text = binding and binding:read("*a") or ""
  if binding then binding:close() end
  sf(text:find('input: KEY_F1', 1, true) ~= nil and text:find('action: "ui_audit"', 1, true) ~= nil,
     "layout ui_audit: KEY_F1 -> ui_audit binding missing")
end

-- No gameplay RNG consumed by the reaction path (identical rooms, reaction on/off).
do
  local PURITY_SEED = 0xB00B1E
  local real_random = math.random
  local seq_a = {}
  local function record()
    math.random = function(...) local v = real_random(...); seq_a[#seq_a + 1] = v; return v end
  end
  local function seq_str(t)
    local parts = {}
    for _, v in ipairs(t) do parts[#parts + 1] = string.format("%.10g", v) end
    return table.concat(parts, ",")
  end
  local got_a, got_b
  record()
  if begin_room(PURITY_SEED) then
    for _, en in ipairs(self.enemies) do en.active = false end
    self.motes = {}
    local p = self.player_pos
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "earth")); cast1()   -- Quake, reactionless
    local pool = self.puddles[1]
    if pool then pool.color = nil end
    frames(35)
  end
  got_a = seq_a
  seq_a = {}
  record()
  if begin_room(PURITY_SEED) then
    for _, en in ipairs(self.enemies) do en.active = false end
    self.motes = {}
    local p = self.player_pos
    self.aim.x, self.aim.y = p.x + 60, p.y
    equip(mk("puddle", nil, "earth", "earth")); cast1()   -- Quake
    local pool = self.puddles[1]
    if pool then pool.color = nil end
    equip(mk("puddle", nil, "earth", "water")); cast1()  -- Mud over it: QUAGMIRE fires
    if self.puddles[2] then self.puddles[2].color = nil end
    frames(35)
  end
  got_b = seq_a
  math.random = real_random
  sf(#got_a > 0, "reaction rng: room consumed no RNG at all (comparison is vacuous)")
  sf(seq_str(got_a) == seq_str(got_b), "reaction rng: the reaction path consumed gameplay RNG")
end

-- ===== Phase D: Relic v2 — offer schedule, echo progress, trigger toasts =====
do
  local rewards_mod = require "src.game.rewards"
  local function count_relics(opts)
    local n = 0
    for _, o in ipairs(opts) do if o.kind == "relic" then n = n + 1 end end
    return n
  end
  local function find_relic(opts)
    for _, o in ipairs(opts) do if o.kind == "relic" then return o end end
    return nil
  end
  local OWN = {
    {},
    { inferno_heart = true },
    { echoing_crystal = true, orbital_crown = true },
    { inferno_heart = true, echoing_crystal = true, ancient_catalyst = true, orbital_crown = true },
  }
  -- 500 seeded runs: relic exactly on milestones 3/6/9 while unowned remain,
  -- never elsewhere, never owned, at most one per screen, payload complete.
  for seed = 1, 500 do
    for _, owned in ipairs(OWN) do
      math.randomseed(seed)
      for room = 1, 10 do
        local opts = rewards_mod.offer(room, owned, math.random)
        sf(#opts == 3, "offer: must always return 3 options (room " .. room .. ")")
        sf(count_relics(opts) <= 1, "offer: at most one relic per screen (room " .. room .. ")")
        local milestone = (room == 3 or room == 6 or room == 9)
        local relic = find_relic(opts)
        if milestone then
          local unowned = 0
          for _, id in ipairs(relics_mod.ORDER) do if not owned[id] then unowned = unowned + 1 end end
          if unowned > 0 then
            sf(relic ~= nil, "offer: milestone room " .. room .. " must offer a relic (unowned remain)")
            sf(relic and not owned[relic.id], "offer: offered an owned relic (room " .. room .. ")")
            sf(relic and type(relic.name) == "string" and type(relic.desc) == "string" and type(relic.icon) == "string",
              "offer: relic payload must carry name/desc/icon (room " .. room .. ")")
          else
            sf(relic == nil, "offer: no unowned relics remain but one was offered (room " .. room .. ")")
          end
        else
          sf(relic == nil, "offer: relic offered on non-milestone room " .. room)
        end
      end
    end
  end
  sf(true, "relic offer schedule (500 seeds x 4 ownership sets x rooms 1..10)")
  -- determinism for a seed
  do
    math.randomseed(42)
    local a = rewards_mod.offer(6, {}, math.random)
    math.randomseed(42)
    local b = rewards_mod.offer(6, {}, math.random)
    local same = #a == #b
    if same then
      for i, o in ipairs(a) do
        if b[i] == nil or b[i].id ~= o.id or b[i].kind ~= o.kind then same = false end
      end
    end
    sf(same, "offer: same seed must produce the same screen")
  end
  -- echo_progress: done in [0, 5], wraps
  do
    local owned = { echoing_crystal = true }
    local cases = { { 0, 0 }, { 1, 1 }, { 2, 2 }, { 3, 3 }, { 4, 4 }, { 5, 5 }, { 6, 1 }, { 9, 4 }, { 10, 5 }, { 11, 1 }, { 25, 5 }, { 26, 1 } }
    for _, c in ipairs(cases) do
      local d, t = relics_mod.echo_progress(owned, c[1])
      sf(d == c[2] and t == 5, string.format("echo_progress: cast %d -> (%d, 5), expected (%d, 5)", c[1], d, c[2]))
    end
    local d0, t0 = relics_mod.echo_progress({}, 7)
    sf(d0 == 0 and t0 == 5, "echo_progress: no relic -> (0, 5)")
  end
  -- engine: player casts advance the counter; echo casts do not
  do
    begin_room()
    self.relics = { echoing_crystal = true }
    equip(mk("projectile", "", "water", "water"))   -- no quirk repeats to muddy the count
    for _ = 1, 12 do
      cast1()
      self.slot1_cooldown = 0                       -- reset CD so every cast lands (0.6 s > 2 frames)
      frames(2)
    end
    sf(self.cast_count == 12, "echo: 12 player casts -> cast_count 12 (got " .. tostring(self.cast_count) .. ")")
    frames(30)   -- let both echoes execute (0.25 s delay)
    sf(self.cast_count == 12, "echo: echo casts must not advance the counter (got " .. tostring(self.cast_count) .. ")")
    local d = relics_mod.echo_progress(self.relics, self.cast_count)
    sf(d == 2, "echo: cast 12 -> 2 pips filled")
  end
  -- trigger toasts: once per room, banner preserved, no gameplay RNG
  do
    begin_room()
    self.relics = { inferno_heart = true }
    self.toast_text, self.toast_t = "FIRE CYCLONE", 1.4
    equip(mk("projectile", "", "fire", "fire"))
    cast1()
    sf(self.toast_text == "FIRE CYCLONE", "inferno heart: never overwrites a live banner")
  end
  do
    begin_room()
    self.relics = { inferno_heart = true }
    equip(mk("projectile", "", "fire", "fire"))
    cast1()
    sf(self.toast_text == relics_mod.DEFS.inferno_heart.trigger_text,
      "inferno heart: first fire-affected cast shows the trigger toast")
    self.room_flags = { heart = self.room_flags and self.room_flags.heart }
    self.slot1_cooldown = 0
    self.toast_t = 0
    cast1()
    sf(self.toast_t == 0, "inferno heart: trigger toast is at most once per room")
  end
  do
    begin_room()
    self.relics = { ancient_catalyst = true }
    self.status_dur_mul = relics_mod.status_duration_mul(self.relics)
    -- put an enemy directly on the aim line so the hit (and its statuses) lands
    for _, e in ipairs(self.enemies) do
      if e.alive then e.telegraph = 0; e.x, e.y = self.player_pos.x + 120, self.player_pos.y break end
    end
    equip(mk("projectile", "", "fire", "water"))    -- Steam: applies statuses on hit
    cast1()
    frames(30)                                       -- let the bolt land on the enemy
    sf(self.toast_text == relics_mod.DEFS.ancient_catalyst.trigger_text,
      "catalyst: first catalyst-affected status application shows the trigger toast")
  end
  do
    begin_room()
    self.relics = { echoing_crystal = true }
    equip(mk("projectile", "", "water", "water"))
    for _ = 1, 5 do cast1(); self.slot1_cooldown = 0; frames(2) end
    frames(30)
    sf(self.toast_text == relics_mod.DEFS.echoing_crystal.trigger_text,
      "echoing crystal: the echo firing shows the trigger toast")
  end
  do
    begin_room()
    self.relics = { inferno_heart = true }
    equip(mk("projectile", "", "fire", "fire"))
    local draws = 0
    local real_random = math.random
    math.random = function(...) draws = draws + 1 return real_random(...) end
    act("cast1", true, false)
    act("cast1", false, true)
    math.random = real_random
    sf(draws == 0, "inferno heart: trigger toast consumed gameplay RNG")
  end
  -- room/run reset leaves no relic UI state or announced flags
  do
    begin_room()
    self.relics = { inferno_heart = true, echoing_crystal = true }
    self.cast_count = 7
    self.room_flags = { heart = true, echo = true, catalyst = true }
    self.toast_text, self.toast_t = "INFERNO HEART +15%", 1.4
    self.state = "DEAD"
    ui({ action = "continue" })   -- run reset -> TITLE
    sf(next(self.relics) == nil, "reset: relics cleared on run reset")
    sf(self.cast_count == 0, "reset: cast_count cleared on run reset")
    sf((self.room_flags or {}).heart == nil and (self.room_flags or {}).echo == nil and (self.room_flags or {}).catalyst == nil,
      "reset: per-room announced flags cleared on run reset")
    sf(self.toast_text == nil, "reset: toast cleared on run reset")
  end
  do
    begin_room()
    self.room_flags = { heart = true, echo = true }
    -- (begin_room no longer picks elements; the slot-1 skill comes from the default loadout)
    begin_room()
    sf((self.room_flags or {}).heart == nil and (self.room_flags or {}).echo == nil,
      "reset: per-room announced flags cleared on room transition")
  end
  -- milestone reward screens through the engine path
  do
    begin_room()
    self.room_number = 3
    self.relics = {}
    self.reward_options = rewards_mod.offer(self.room_number, self.relics, math.random)
    local relic = find_relic(self.reward_options)
    sf(relic ~= nil, "engine: milestone room 3 offers a relic")
    self.state = "REWARD"
    local relic_index = nil
    for i, o in ipairs(self.reward_options) do if o.kind == "relic" then relic_index = i end end
    ui({ action = "reward_pick", index = relic_index })
    sf(self.relics[relic.id] == true, "engine: picking the milestone relic stores it")
  end
  do
    begin_room()
    self.room_number = 6
    self.relics = {}
    local opts = rewards_mod.offer(self.room_number, self.relics, math.random)
    local relic = find_relic(opts)
    sf(relic ~= nil, "engine: milestone room 6 offers a relic")
  end
  do
    begin_room()
    self.room_number = 9
    self.relics = {}
    local opts = rewards_mod.offer(self.room_number, self.relics, math.random)
    local relic = find_relic(opts)
    sf(relic ~= nil, "engine: milestone room 9 offers a relic")
  end
  do
    begin_room()
    self.room_number = 4
    self.relics = {}
    local opts = rewards_mod.offer(self.room_number, self.relics, math.random)
    sf(find_relic(opts) == nil, "engine: room 4 offers no relic")
  end
end

-- ===== sfx wiring: real manifest, recorded backend =====
do
  local function count_hits_since(from)
    local n = 0
    for i = from + 1, #sfx_plays do
      local id = sfx_plays[i].id
      if id and id:match("^el_.*_hit$") then n = n + 1 end
    end
    return n
  end
  -- Pool ticks are silent: cast a puddle onto an enemy, tick it, no hit sfx.
  begin_room()
  local aim_x = self.aim.x
  for _, e in ipairs(self.enemies) do
    if e.alive then e.telegraph = 0; e.x, e.y = aim_x, self.player_pos.y break end
  end
  equip(mk("puddle", "", "water", "water"))
  local before = #sfx_plays
  for _ = 1, 4 do cast1(); self.slot1_cooldown = 0; frames(2) end
  frames(40)   -- let at least one pool tick land on the enemy
  sf(count_hits_since(before) == 0, "sfx: pool ticks must not play hit sounds")
  -- Cast sounds DID fire (proves cast -> bus -> sfx path).
  local heard_cast = false
  local heard_signature = false
  for i = before + 1, #sfx_plays do
    if sfx_plays[i].id == "cast_puddle" then heard_cast = true end
    if sfx_plays[i].id == "sig_tide" then heard_signature = true end
  end
  sf(heard_cast, "sfx: casting a Pool must play the cast sound")
  sf(heard_signature, "sfx: casting a Tide Pool must play its signature sound")
  sf(sfx_plays[1] ~= nil, "sfx: recorder captured plays (sanity)")
  -- Bolt hit path: an enemy on the aim line takes a hit with a hit sound.
  begin_room()
  aim_x = self.aim.x
  for _, e in ipairs(self.enemies) do
    if e.alive then e.telegraph = 0; e.x, e.y = aim_x, self.player_pos.y break end
  end
  equip(mk("projectile", "", "water", "water"))
  before = #sfx_plays
  cast1()
  frames(30)
  sf(count_hits_since(before) >= 1, "sfx: bolt hit must play a hit sound")
end

for i=1,300 do frame() end
-- flush leftover timers
for _, t in ipairs(timers) do t.fn() end
timers = {}
frame()

-- ===== Quirk registry (identity, labels, slot filtering, extension) =====
local quirks = require "src.core.quirks"
sf(table.concat(quirks.DEFAULT_IDS, ",") ==
   "split_in_two,leaves_trail,repeat_once,bigger_slower,health_cost",
   "quirks: DEFAULT_IDS order changed")
local WANT_LABEL = { "splits in two", "leaves a trail", "repeats once", "bigger but slower", "costs 5% health" }
for i, id in ipairs(quirks.DEFAULT_IDS) do
  local d = quirks.get(id)
  sf(d ~= nil, "quirks: no DEFS for " .. id)
  sf(d and d.id == id, "quirks: def id mismatch for " .. id)
  sf(d and d.label == WANT_LABEL[i], "quirks: label for " .. id .. " is not " .. WANT_LABEL[i])
  sf(d and type(d.short) == "string" and #d.short > 0 and #d.short <= 9,
     "quirks: short form must be 1-9 chars for " .. id)
  sf(d and type(d.desc) == "string" and #d.desc > 0, "quirks: empty desc for " .. id)
  sf(d and d.data ~= nil, "quirks: no tuning table for " .. id)
  sf(d and d.flags ~= nil, "quirks: no flags for " .. id)
  sf(d and ((d.flags.hp_cost == true) == (d.basic_ok == false)),
     "quirks: basic_ok must be false exactly for the hp-cost quirk (" .. id .. ")")
end
sf(#quirks.list() == 5, "quirks: list() is not 5")
sf(#quirks.list_for_slot("spell") == 5, "quirks: spell slot should see 5 quirks")
sf(#quirks.list_for_slot("basic") == 4, "quirks: basic slot should see 4 quirks")
for _, d in ipairs(quirks.list_for_slot("basic")) do
  sf(d.basic_ok == true, "quirks: disallowed quirk offered to the basic slot: " .. d.id)
end
sf(quirks.default_id(0) == "split_in_two", "quirks: default_id(0)")
sf(quirks.default_id(0.521085) == "repeat_once", "quirks: default_id(golden r2)")
sf(quirks.default_id(0.999999) == "health_cost", "quirks: default_id(high r2)")
sf(quirks.default_id(1.0) == "health_cost", "quirks: default_id(1.0) must clamp, not return nil")
sf(quirks.get("nope") == nil, "quirks: get(unknown) must be nil")
sf(quirks.by_label("bigger but slower").id == "bigger_slower", "quirks: by_label failed")
sf(quirks.by_label("nope") == nil, "quirks: by_label(unknown) must be nil")
-- extension contract: a new quirk never moves the default mapping
local fake = { id = "test_extra", label = "test only", short = "test",
               desc = "test-only quirk", basic_ok = true, default_pool = false,
               flags = { test_only = true }, data = {} }
sf(quirks.register(fake) == true, "quirks: register(fake) failed")
sf(quirks.register(fake) == false, "quirks: register must reject a duplicate id")
sf(quirks.register({ id = "test_bad_flags", label = "bad flags", short = "bad",
                     desc = "bad flags", basic_ok = true, flags = "split", data = {} }) == false,
   "quirks: register must reject a non-table flags field")
sf(quirks.register({ id = "test_bad_data", label = "bad data", short = "bad",
                     desc = "bad data", basic_ok = true, flags = {}, data = "nope" }) == false,
   "quirks: register must reject a non-table data field")
-- Complete def, so only the frozen-id guard can reject it.
sf(quirks.register({ id = "split_in_two", label = "x", short = "x", desc = "x",
                     flags = {}, data = {} }) == false,
   "quirks: register must reject a DEFAULT_IDS id")
sf(quirks.register({ id = "test_dup_label", label = "test only", short = "dup",
                     desc = "duplicate label", flags = {}, data = {} }) == false,
   "quirks: register must reject a duplicate label")
sf(quirks.register({ id = "test_incomplete" }) == false,
   "quirks: register must reject an incomplete def")
local bad_kind_ok = pcall(function() return quirks.list_for_slot("nope") end)
sf(bad_kind_ok == false, "quirks: list_for_slot(bad kind) must fail loudly")
sf(#quirks.list() == 6, "quirks: registered quirk missing from list()")
sf(#quirks.list_for_slot("spell") == 6, "quirks: registered quirk missing from the spell slot")
sf(quirks.get("test_extra") ~= nil, "quirks: registered quirk missing from get()")
sf(quirks.default_id(0.521085) == "repeat_once", "quirks: register moved default_id")
sf(quirks.unregister("split_in_two") == false, "quirks: unregister must refuse a DEFAULT_IDS id")
quirks.unregister("test_extra")
sf(#quirks.list() == 5, "quirks: unregister did not restore list()")
sf(quirks.get("test_extra") == nil, "quirks: unregister did not remove get()")

-- ===== Task 2: generator quirk override + identity moved out of data.lua =====
do
  local hash_mod = require "src.core.hash"
  local rng_mod = require "src.core.rng"
  local function sorted2(a, b) if a <= b then return a, b else return b, a end end
  -- Default path: every recipe still picks DEFAULT_IDS[floor(r2 * 5) + 1], computed
  -- here from the same hash + rng the generator uses (draw 1 = power, draw 2 = quirk).
  for _, r in ipairs(recipes) do
    local sa, sb = sorted2(r[1], r[2])
    local rr = rng_mod.new(hash_mod.hash(sa .. "+" .. sb .. "|" .. r[3]))
    rr()
    local expect = quirks.DEFAULT_IDS[math.floor(rr() * 5) + 1]
    local sk = skillgen.makeSkill(r[1], r[2], r[3])
    sf(sk.quirk_id == expect, "skillgen: default quirk drift for " .. sa .. "+" .. sb .. "|" .. r[3])
    sf(sk.quirk == quirks.get(expect).label, "skillgen: label drift for " .. sa .. "+" .. sb .. "|" .. r[3])
  end
  -- The three frozen results the generator must reproduce (MASTER_PROMPT 5.4, rows 1-2).
  local g1 = skillgen.makeSkill("fire", "water", "projectile")
  sf(g1.power == 7 and g1.quirk == "repeats once" and g1.quirk_id == "repeat_once",
     "skillgen: golden fire+water|projectile drifted")
  local g2 = skillgen.makeSkill("fire", "fire", "puddle")
  sf(g2.power == 14 and g2.quirk == "bigger but slower" and g2.quirk_id == "bigger_slower",
     "skillgen: golden fire+fire|puddle drifted")
  -- Override changes the quirk and nothing else.
  local base = skillgen.makeSkill("fire", "fire", "projectile")
  local over = skillgen.makeSkill("fire", "fire", "projectile", nil, "bigger_slower")
  sf(over.quirk_id == "bigger_slower", "skillgen: override quirk_id")
  sf(over.quirk == "bigger but slower", "skillgen: override label")
  sf(over.power == base.power, "skillgen: override changed power")
  sf(over.key == base.key, "skillgen: override changed the seed key")
  sf(over.compound == base.compound and over.elements[1] == base.elements[1] and over.shape == base.shape,
     "skillgen: override changed the compound/shape")
  sf(over.cooldown == base.cooldown and over.radius == base.radius, "skillgen: override changed shape data")
  sf(skillgen.makeSkill("fire", "fire", "projectile", nil, "nope").quirk_id == base.quirk_id,
     "skillgen: unknown override must fall back to the default quirk")
  -- A named player still overrides, and the player name still changes the seed.
  local named = skillgen.makeSkill("fire", "fire", "projectile", "Ash", "leaves_trail")
  sf(named.quirk_id == "leaves_trail" and named.quirk == "leaves a trail",
     "skillgen: override with a player name failed")
  sf(named.key ~= base.key, "skillgen: player name no longer reaches the seed key")
  -- A registered extra is overridable too (the editor will list registry entries).
  quirks.register({ id = "task2_extra", label = "task 2 only", short = "task2",
                    desc = "test-only quirk", basic_ok = true, default_pool = false,
                    flags = {}, data = {} })
  local extra = skillgen.makeSkill("fire", "fire", "projectile", nil, "task2_extra")
  sf(extra.quirk_id == "task2_extra" and extra.quirk == "task 2 only",
     "skillgen: registered extra cannot be overridden")
  sf(extra.power == base.power, "skillgen: extra override changed power")
  quirks.unregister("task2_extra")
  -- Identity lives in the registry now, not in data.lua.
  sf(data.QUIRKS == nil, "data: M.QUIRKS must be gone (identity lives in src.core.quirks)")
  sf(data.QUIRK_IDS == nil, "data: M.QUIRK_IDS must be gone (identity lives in src.core.quirks)")
  sf(data.QUIRK_DATA.health_cost ~= nil and data.QUIRK_DATA.leaves_trail ~= nil
     and data.QUIRK_DATA.bigger_slower ~= nil,
     "data: QUIRK_DATA tuning tables must survive")
end

-- ===== Loadout: three slots, MOUSE forced to Bolt, sanitised =====
do
  self.loadout = nil
  apply_loadout(self)                       -- creates defaults, then equips
  sf(self.loadout ~= nil, "loadout: not created")
  sf(#self.loadout == 3, "loadout: expected 3 slots")
  for i = 1, 3 do
    sf(type(self.loadout[i].ea) == "string", "loadout: slot " .. i .. " ea")
    sf(type(self.loadout[i].eb) == "string", "loadout: slot " .. i .. " eb")
    sf(type(self.loadout[i].quirk_id) == "string", "loadout: slot " .. i .. " quirk_id")
    sf(quirks.get(self.loadout[i].quirk_id) ~= nil, "loadout: slot " .. i .. " quirk_id unknown")
  end
  sf(self.loadout[3].shape == "projectile", "loadout: MOUSE must be Bolt")
  sf(self.slot3 ~= nil, "loadout: slot3 skill missing")
  sf(self.slot3.shape_key == "projectile", "loadout: slot3 not Bolt")
  sf(self.slot3_elem_a ~= nil and self.slot3_elem_b ~= nil, "loadout: slot3 elements missing")
  sf(self.slot3_cd_max == self.slot3.cooldown, "loadout: slot3 cd_max")
  sf(self.cooldown_ready[3] ~= nil, "loadout: cooldown_ready[3] missing")
  sf(self.slot1.quirk_id == self.loadout[1].quirk_id, "loadout: slot1 quirk not applied")
  sf(self.slot2.quirk_id == self.loadout[2].quirk_id, "loadout: slot2 quirk not applied")
  -- a named quirk is stamped on the slot it is equipped into
  local sk = skillgen.makeSkill("earth", "earth", "burst")
  equip_skill(self, 3, sk, "split_in_two")
  sf(self.slot3.quirk_id == "split_in_two", "equip_skill: quirk_id not stamped")
  sf(self.slot3.quirk == "splits in two", "equip_skill: label not stamped")
  sf(self.slot3.shape_key == "burst", "equip_skill: skill not installed")
  sf(self.slot3_cd_max == sk.cooldown, "equip_skill: cd_max not set")
  -- sanitisation: forged shape and a quirk the MOUSE slot may not have
  self.loadout[3].shape = "burst"
  self.loadout[3].quirk_id = "health_cost"
  apply_loadout(self)
  sf(self.loadout[3].shape == "projectile", "apply_loadout: MOUSE shape not forced to Bolt")
  sf(self.slot3.shape_key == "projectile", "apply_loadout: slot3 shape not Bolt")
  sf(self.slot3.quirk_id ~= "health_cost", "apply_loadout: MOUSE kept a disallowed quirk")
  sf(quirks.get(self.slot3.quirk_id).basic_ok == true, "apply_loadout: MOUSE got a non-basic quirk")
  -- a forged element falls back to the default too
  self.loadout[3].ea, self.loadout[3].eb = "plasma", "gold"
  apply_loadout(self)
  sf(self.loadout[3].ea == "fire" and self.loadout[3].eb == "fire",
     "apply_loadout: forged elements not repaired")
  -- slot 3 is an ordinary cast (driven through update's hold-fire path in a real room)
  begin_room()
  local b = #self.bolts
  self.slot3_cooldown = 0
  self.hold3 = true
  frame()
  self.hold3 = false
  sf(#self.bolts == b + 1, "slot3: hold-fire produced no bolt")
  sf(self.slot3_cooldown > 0, "slot3: cooldown not set")
  -- and it keeps its quirk across rooms
  local quirk3 = self.loadout[3].quirk_id
  sf(self.slot3.quirk_id == quirk3, "slot3: quirk changed after a room reset")
end

-- ===== Basic exemptions and quirk inheritance (flag-driven cast path) =====
if begin_room() then
  -- forged: a basic carrying the blood price still never pays
  local blood = mk("projectile", "health_cost")
  equip_skill(self, 3, blood, "health_cost")
  self.player.hp, self.player.max_hp = 100, 100
  self.player.alive, self.player.invuln = true, 0
  self.slot3_cooldown = 0
  self.hold3 = true; frame(); self.hold3 = false
  sf(self.player.hp == 100, "basic: paid the blood price")
  -- and it cannot be refused at 1 HP either (the hp gate is ignored for slot 3)
  local b1 = #self.bolts
  self.player.hp = 1
  self.slot3_cooldown = 0
  self.hold3 = true; frame(); self.hold3 = false
  sf(#self.bolts == b1 + 1, "basic: refused to cast at 1 HP")
  -- the echo counter never moves for basics
  self.player.hp, self.player.max_hp = 100, 100
  self.cast_count = 0
  for _ = 1, 10 do
    self.slot3_cooldown = 0
    self.hold3 = true; frame(); self.hold3 = false
  end
  sf(self.cast_count == 0, "basic: incremented cast_count")
  -- Q still pays and still counts (its cast counter feeds Echoing Crystal)
  self.loadout[1].quirk_id = "health_cost"
  apply_loadout(self)
  self.player.hp, self.player.max_hp = 100, 100
  self.slot1_cooldown = 0
  self.cast_count = 0
  cast1()
  sf(self.player.hp < 100, "Q: did not pay the blood price")
  sf(self.cast_count == 1, "Q: did not increment cast_count")
  -- craft keeps the slot's quirk
  self.loadout[1].quirk_id = "split_in_two"
  apply_loadout(self)
  self.state = "CAULDRON"
  self.cauldron = { ea = "fire", eb = "water", shape = "puddle" }
  self.inventory.elements = { fire = 2, water = 2, wind = 2, earth = 2 }
  self.inventory.shapes = { projectile = 2, puddle = 2, orbit = 2, cone = 2, burst = 2 }
  ui({ action = "craft", slot = 1 })
  sf(self.slot1.quirk_id == "split_in_two", "craft: recipe quirk overwrote the slot quirk")
  sf(self.slot1.compound == "Steam", "craft: slot skill was not replaced")
  -- cauldron payload carries each target slot's quirk short form
  self.state = "CAULDRON"
  frame()
  sf(type(last_ui and last_ui.slots and last_ui.slots[1]) == "table" and last_ui.slots[1].quirk == "splits",
     "cauldron: slot 1 quirk short form missing from the payload")
  sf(type(last_ui and last_ui.slots and last_ui.slots[2]) == "table" and last_ui.slots[2].quirk ~= nil,
     "cauldron: slot 2 quirk short form missing from the payload")
  -- debug shape key keeps it too (in a room, where the debug row is live)
  begin_room()
  act("2", true, false)
  act("2", false, true)
  sf(self.slot1.quirk_id == "split_in_two", "debug: shape key dropped the slot quirk")
  sf(self.slot1.shape_key == "puddle", "debug: shape key did not rebuild slot 1")
end

-- ===== Input map: Q/R spells, LMB basic, E interact, bracket debug cycle =====
do
  local bind = io.open(ROOT .. "input/game.input_binding", "r"):read("*a")
  local required = {
    { "KEY_Q", "cast1" }, { "KEY_R", "cast2" }, { "KEY_E", "interact" },
    { "KEY_LBRACKET", "dbg_prev" }, { "KEY_RBRACKET", "dbg_next" },
    { "KEY_SPACE", "dash" }, { "KEY_W", "up" }, { "KEY_1", "1" }, { "KEY_0", "0" },
    { "KEY_ESC", "pause" }, { "KEY_F1", "ui_audit" },
  }
  for _, p in ipairs(required) do
    sf(bind:find("input: " .. p[1] .. "%s+action: \"" .. p[2] .. "\"") ~= nil,
       "input: binding " .. p[1] .. " -> " .. p[2] .. " missing")
  end
  sf(bind:find('MOUSE_BUTTON_1%s+action: "basic"') ~= nil,
     "input: LMB is not the basic action")
  sf(bind:find('MOUSE_BUTTON_2%s+action: "basic_rmb"') ~= nil,
     "input: RMB must be bound to basic_rmb (LMB/RMB toggle for the basic)")
  -- Q and R cast their slots in ROOM (split_in_two fires two bolts, so compare relatively)
  if begin_room() then
    local b0 = #self.bolts
    self.slot1_cooldown = 0
    act("cast1", true, false); act("cast1", false, true)
    sf(#self.bolts > b0, "input: cast1 (Q) did not cast slot 1")
    local b1 = #self.bolts
    self.slot2_cooldown = 0
    act("cast2", true, false); act("cast2", false, true)
    sf(#self.bolts > b1, "input: cast2 (R) did not cast slot 2")
    local b2 = #self.bolts
    self.slot3_cooldown = 0
    act("basic", true, false); act("basic", false, true)
    sf(#self.bolts > b2, "input: basic (LMB) did not cast slot 3")
  end
  -- LMB outside ROOM forwards a click instead of casting
  self.state = "TITLE"
  local clicks = hud_clicks
  act("basic", true, false, 300, 200)
  sf(hud_clicks == clicks + 1, "input: LMB did not forward a click outside ROOM")
  -- the debug cycle lives on the brackets now
  if begin_room() then
    local c0 = self.slot1.compound
    act("dbg_prev", true, false); act("dbg_prev", false, true)
    sf(self.slot1.compound ~= c0, "input: dbg_prev did not cycle slot 1")
    local c1 = self.slot2.compound
    act("dbg_next", true, false); act("dbg_next", false, true)
    sf(self.slot2.compound ~= c1, "input: dbg_next did not cycle slot 2")
  end
  -- Q does nothing outside ROOM
  self.state = "TITLE"
  local c2 = self.slot1.compound
  act("cast1", true, false); act("cast1", false, true)
  sf(self.slot1.compound == c2, "input: cast1 acted outside ROOM")
end

-- ===== Home: TITLE -> HOME, stations, door starts the run =====
do
  local home_mod = require "src.levels.home"
  self.loadout = nil
  self.state = "DEAD"
  ui({ action = "continue" })                      -- clean reset; clears world, back to TITLE
  sf(self.state == "TITLE", "home: continue did not return to TITLE")
  self.state = "TITLE"
  ui({ action = "start" })
  sf(self.state == "HOME", "home: start did not enter HOME (got " .. tostring(self.state) .. ")")
  sf(self.level and self.level.name == "Lantern Hall", "home: wrong level loaded")
  sf(self.home_altar_pos and self.home_door_pos, "home: station positions missing")
  sf(self.level_tiles and #self.level_tiles > 0, "home: no tiles were built")
  sf(self.home_level == self.level, "home: level handle not recorded")
  sf(self.home_focus == nil, "home: focus should start unset")
  local function stand_at(c, r)
    local px, py = level_mod.cell_center(c, r)
    self.player_pos.x, self.player_pos.y = px, py
  end
  stand_at(home_mod.altar.c, home_mod.altar.r + 1)
  frame()
  sf(self.home_focus == "altar", "home: altar focus not detected")
  sf((self.home_prompt or ""):find("EDIT") ~= nil, "home: altar prompt lacks EDIT")
  stand_at(home_mod.door.c, home_mod.door.r + 1)
  frame()
  sf(self.home_focus == "door", "home: door focus not detected")
  sf((self.home_prompt or ""):find("BEGIN") ~= nil, "home: door prompt lacks BEGIN")
  stand_at(home_mod.altar.c, home_mod.altar.r + 3)
  frame()
  sf(self.home_focus == nil, "home: focus radius is too wide")
  -- the door starts the run
  stand_at(home_mod.door.c, home_mod.door.r + 1)
  frame()
  act("interact", true, false); act("interact", false, true)
  sf(self.state == "ROOM", "home: door did not start the run")
  sf(self.room_number == 1, "home: door did not enter room 1")
  sf(self.slot3.quirk_id == self.loadout[3].quirk_id, "home: slot 3 quirk not applied")
  sf(self.slot1.quirk_id == self.loadout[1].quirk_id, "home: slot 1 quirk not applied")
  sf(self.slot2.quirk_id == self.loadout[2].quirk_id, "home: slot 2 quirk not applied")
  local ea, eb = self.loadout[3].ea, self.loadout[3].eb
  if ea == eb then
    sf(self.inventory.elements[ea] == 2, "home: starter element doubled (same element twice), got " .. tostring(self.inventory.elements[ea]))
  else
    sf(self.inventory.elements[ea] == 1, "home: starter element A missing")
    sf(self.inventory.elements[eb] == 1, "home: starter element B missing")
  end
  sf(self.inventory.shapes.projectile == 1, "home: starter Bolt missing")
  -- no casting in HOME
  self.state = "HOME"
  local b = #self.bolts
  act("basic", true, false); act("basic", false, true)
  sf(#self.bolts == b, "home: LMB cast a spell in HOME")
  -- the loadout survives death -> TITLE -> HOME -> door
  local chosen = self.loadout[2].quirk_id
  self.state = "DEAD"; ui({ action = "continue" })
  sf(self.state == "TITLE", "home: continue did not return to TITLE")
  sf(self.loadout[2].quirk_id == chosen, "home: reset_run cleared the loadout")
  ui({ action = "start" })
  sf(self.state == "HOME", "home: start did not re-enter HOME")
  ui({ action = "begin_run" })
  sf(self.state == "ROOM", "home: begin_run did not enter ROOM")
  sf(self.slot2.quirk_id == chosen, "home: replayed run lost the slot quirk")
  frame()                          -- flush a ROOM ui message
  sf((ui_seen.HOME or 0) >= 1, "ui msg: no ui message posted in state HOME")
  sf(last_ui and last_ui.prompt == nil, "ui msg: prompt leaked outside HOME")
end

-- ===== Editor: tabs, cycling, MOUSE restrictions, preview, state guard =====
do
  self.loadout = nil
  self.state = "DEAD"
  ui({ action = "continue" })
  self.state = "TITLE"
  ui({ action = "start" })
  ui({ action = "edit" })
  sf(self.state == "HOME_EDIT", "editor: edit did not open")
  sf(self.loadout ~= nil, "editor: no loadout exists")
  sf((self.loadout_tab or 1) == 1, "editor: default tab is not Q (slot 1)")
  ui({ action = "tab", slot = 3 })
  sf(self.loadout_tab == 3, "editor: tab did not switch to MOUSE")
  local s3shape = self.loadout[3].shape
  ui({ action = "cycle", field = "shape", dir = 1 })
  sf(self.loadout[3].shape == s3shape, "editor: MOUSE shape must not change")
  -- cycling the MOUSE quirk stays inside basic_ok defs and wraps all the way round
  local s3q = self.loadout[3].quirk_id
  local seen = {}
  for _ = 1, #quirks.list_for_slot("basic") do
    ui({ action = "cycle", field = "quirk", dir = 1 })
    local d = quirks.get(self.loadout[3].quirk_id)
    sf(d and d.basic_ok == true, "editor: basic slot accepted a disallowed quirk")
    seen[self.loadout[3].quirk_id] = true
  end
  sf(self.loadout[3].quirk_id == s3q, "editor: cycling did not wrap to the starting quirk")
  sf(self.slot3.quirk_id == self.loadout[3].quirk_id, "editor: quirk change did not re-equip slot 3")
  ui({ action = "tab", slot = 1 })
  local ea0 = self.loadout[1].ea
  ui({ action = "cycle", field = "ea", dir = 1 })
  sf(self.loadout[1].ea ~= ea0, "editor: ea did not cycle")
  ui({ action = "cycle", field = "ea", dir = -1 })
  sf(self.loadout[1].ea == ea0, "editor: ea did not cycle back")
  local sidx = 1
  for i, shape in ipairs({ "projectile", "puddle", "orbit", "cone", "burst" }) do
    if self.loadout[1].shape == shape then sidx = i end
  end
  ui({ action = "cycle", field = "shape", dir = 1 })
  local nextf = ({ "projectile", "puddle", "orbit", "cone", "burst" })[sidx % 5 + 1]
  sf(self.loadout[1].shape == nextf, "editor: shape did not cycle")
  sf(self.slot1.quirk_id == self.loadout[1].quirk_id, "editor: change did not re-equip slot 1")
  ui({ action = "done" })
  sf(self.state == "HOME", "editor: done did not return to HOME")
  -- state guard: editor actions are inert outside HOME_EDIT
  local before = self.loadout[1].ea
  ui({ action = "cycle", field = "ea", dir = 1 })
  ui({ action = "tab", slot = 2 })
  sf(self.loadout[1].ea == before, "editor: action applied outside HOME_EDIT")
  sf(self.loadout_tab == 1, "editor: tab changed outside HOME_EDIT")
  -- the preview is the generator's answer for the same loadout
  ui({ action = "edit" })
  frame()
  local l = self.loadout[self.loadout_tab]
  local sk = skillgen.makeSkill(l.ea, l.eb, l.shape, nil, l.quirk_id)
  sf(last_ui and last_ui.editor and last_ui.editor.preview_name:find(sk.compound) ~= nil,
     "editor: preview name")
  sf(last_ui and last_ui.editor and last_ui.editor.preview_detail:find("Power " .. sk.power) ~= nil,
     "editor: preview power")
  sf(last_ui and last_ui.editor and last_ui.editor.quirk_label == quirks.get(l.quirk_id).label,
     "editor: quirk label")
  sf(last_ui and last_ui.editor and last_ui.editor.quirk_desc == quirks.get(l.quirk_id).desc,
     "editor: quirk desc")
  ui({ action = "done" })
  sf(self.state == "HOME", "editor: done did not return to HOME (2nd)")
end

-- ===== Pause from HOME_EDIT via ESC; resume returns to HOME_EDIT =====
do
  self.state = "DEAD"
  ui({ action = "continue" })
  ui({ action = "start" })
  ui({ action = "edit" })
  sf(self.state == "HOME_EDIT", "pause-edit: did not land in HOME_EDIT")
  act("pause", true, false); act("pause", false, true)
  sf(self.state == "PAUSED", "pause-edit: ESC in HOME_EDIT did not pause")
  ui({ action = "settings_open" })
  sf(self.state == "SETTINGS", "pause-edit: settings did not open from edit-pause")
  ui({ action = "back" })
  sf(self.state == "PAUSED", "pause-edit: back from settings did not return to PAUSED")
  ui({ action = "resume" })
  sf(self.state == "HOME_EDIT", "pause-edit: resume did NOT return to HOME_EDIT")
  act("pause", true, false); act("pause", false, true)
  ui({ action = "quit_main" })
  sf(self.state == "TITLE", "pause-edit: quit_main did not go to TITLE")
end

-- ===== Rebind engine: defaults, dispatch, collision, capture =====
-- slot1 is pinned to a known recipe (Earth Bolt, repeats once) so THIS section
-- does not inherit whatever the preceding suite left in self.loadout[1].
do
  local bind_defaults = { up = "k_w", left = "k_a", down = "k_s", right = "k_d",
      cast1 = "k_q", cast2 = "k_r", interact = "k_e", dash = "k_space", basic = "basic" }
  for k, v in pairs(bind_defaults) do
    sf(self.bind and self.bind[k] == v, "bind: default " .. k .. " is not " .. tostring(v))
    sf(self.bind_hash and self.bind_hash[k] == hash(v), "bind: hash for " .. k .. " mismatch")
  end
  self.loadout[1] = { ea = "earth", eb = "earth", shape = "projectile", quirk_id = "repeats once" }
  apply_loadout(self)
  begin_room()
  local b0 = #self.bolts
  self.slot1_cooldown = 0
  act("cast1", true, false); act("cast1", false, true)
  sf(#self.bolts > b0, "bind: default cast1 did not fire")
  ui({ action = "rebind", id = "cast1", key = "k_k" })
  sf(self.bind.cast1 == "k_k", "bind: rebind did not write")
  sf(self.bind_hash.cast1 == hash("k_k"), "bind: hash not rebuilt on rebind")
  begin_room()
  local b1 = #self.bolts
  self.slot1_cooldown = 0
  act("k_q", true, false); act("k_q", false, true)
  sf(#self.bolts == b1, "bind: old physical key still fired after rebind")
  begin_room()
  local b2 = #self.bolts
  self.slot1_cooldown = 0
  act("k_k", true, false); act("k_k", false, true)
  sf(#self.bolts > b2, "bind: rebound cast1 did not fire")
  ui({ action = "rebind", id = "cast2", key = "k_space" })
  begin_room()
  local b3 = #self.bolts
  self.slot2_cooldown = 0
  act("k_space", true, false); act("k_space", false, true)
  sf(#self.bolts > b3, "bind: duplicate key did not fire BOTH binds (cast2)")
  sf(self.dash_t > 0, "bind: dash lost its own key after a rebind collided into it")
  self.loadout[1] = { ea = "water", eb = "water", shape = "projectile", quirk_id = nil }
  apply_loadout(self)   -- put the session loadout back the way later tests read it
end

-- ===== Pause: freeze boundaries, resume, quit, quit-to-main =====
sys = { exit = function() sys_exit_calls = (sys_exit_calls or 0) + 1 end }
do
  begin_room()
  act("pause", true, false); act("pause", false, true)
  sf(self.state == "PAUSED", "pause: ESC did not pause in ROOM (state=" .. tostring(self.state) .. ")")
  local dt_probe = self.dash_cd
  for i = 1, 30 do frame() end
  sf(self.dash_cd == dt_probe, "pause: dash cooldown ticked while PAUSED")
  sf(self.state == "PAUSED", "pause: PAUSED drifted back to ROOM")
  ui({ action = "resume" })
  sf(self.state == "ROOM", "pause: resume did not return to ROOM")
  self.state = "TITLE"
  act("pause", true, false); act("pause", false, true)
  sf(self.state == "TITLE", "pause: ESC acted outside ROOM")
  begin_room()
  act("pause", true, false); act("pause", false, true)
  ui({ action = "quit_main" })
  sf(self.state == "TITLE", "pause: quit_to_main did not reset to TITLE")
  begin_room()
  act("pause", true, false); act("pause", false, true)
  ui({ action = "quit" })
  sf(sys_exit_calls == 1, "pause: quit did not route to the sys.exit stub")
  -- force ROOM first; the previous test intentionally left state == "PAUSED".
  self.state = "ROOM"
  ui({ action = "bind", id = "up" })   -- capture OPEN
  act("pause", true, false)
  sf(self.capture_pending == nil, "pause: ESC did not eat the capture")
  sf(self.bind.up == "k_w", "pause: ESC rebound move-up to itself (bind=" .. tostring(self.bind.up) .. ")")
  sf(self.state ~= "PAUSED", "pause: ESC paused during capture (should only cancel the capture)")
  -- escape is never bindable, no matter how the runtime dispatches the two actions
  ui({ action = "bind", id = "dash" })
  act("pause", true, false)
  sf(self.capture_pending == nil, "pause: ESC did not eat the dash capture")
  sf(self.bind.dash == "k_space", "pause: ESC rebound dash to ESC (bind=" .. tostring(self.bind.dash) .. ")")
end

-- ===== Settings: volume rows (live + clamped), binding rows, back, exit =====
do
  local sfx = require "src.core.sfx"

  self.state = "TITLE"
  ui({ action = "settings_open" })
  sf(self.state == "SETTINGS", "settings: TITLE did not open SETTINGS")
  ui({ action = "back" })
  sf(self.state == "TITLE", "settings: back from TITLE did not return to TITLE")
  ui({ action = "settings_open" })
  for i = 1, 20 do ui({ action = "volume_up", field = "music" }) end
  sf(math.abs(sfx.BUS.music - 1.0) < 0.01, "settings: music volume did not clamp at 1.0")
  for i = 1, 20 do ui({ action = "volume_down", field = "music" }) end
  sf(math.abs(sfx.BUS.music - 0) < 0.01, "settings: music volume did not clamp at 0")
  ui({ action = "volume_down", field = "master" })
  sf(math.abs(sfx.BUS.master - 0.9) < 0.01, "settings: master step is not 0.1")
  ui({ action = "volume_down", field = "master" })
  sf(math.abs(sfx.BUS.master - 0.8) < 0.01, "settings: second master step is not 0.1")
  -- back returns to where we came from
  ui({ action = "back" })
  sf(self.state == "TITLE", "settings: back from TITLE returned the wrong state")
  -- PAUSED route
  begin_room()
  act("pause", true, false)
  ui({ action = "settings_open" })
  sf(self.state == "SETTINGS", "settings: pause->settings did not open SETTINGS")
  ui({ action = "back" })
  sf(self.state == "PAUSED", "settings: back from PAUSED did not return to PAUSED")
  -- EXIT from TITLE routes to the sys.exit stub, never to reset_run
  self.state = "TITLE"
  local exits_before = sys_exit_calls or 0
  ui({ action = "exit" })
  sf(sys_exit_calls == exits_before + 1, "exit: TITLE quit did not route to the sys.exit stub")
end

-- ===== Training from the main menu =====
ui({ action = "training" })
sf(self.state == "ROOM", "menu: training button did not enter the training room")
sf(self.room_number == 10, "menu: training button did not load the training room (room=" .. tostring(self.room_number) .. ")")
-- The Training Room has no enemies to kill; ESC -> quit to main menu is the exit.
act("pause", true, false); act("pause", false, true)
sf(self.state == "PAUSED", "menu: ESC from training hall did not pause")
ui({ action = "quit_main" })
sf(self.state == "TITLE", "menu: quit_main from training did not return to TITLE")

-- ===== HUD message budget: every state's ui message must fit the 2 KB msg.post limit =====
-- Force each screen state with the heaviest payload the game can carry, then
-- check the posted message. ui_seen/ui_worst were recorded by the msg.post stub.
do
  local big_inventory = {
    elements = { fire = 9, water = 9, wind = 9, earth = 9 },
    shapes = { projectile = 9, puddle = 9, orbit = 9, cone = 9, burst = 9 },
  }
  local four_relics = { inferno_heart = true, echoing_crystal = true, ancient_catalyst = true, orbital_crown = true }
  local function force(state, setup)
    setup()
    self.state = state
    frame()                       -- update() ends in send_ui(), so exactly one message lands
  end
  force("TITLE", function() self.flash = 0 end)
  force("COMBOS", function() end)
  force("CREDITS", function() end)
  force("HOME", function() self.loadout_tab = 1 end)
  force("HOME_EDIT", function() self.loadout_tab = 1 end)
  force("PAUSED", function() self.dash_cd = 0.5 end)
  force("SETTINGS", function() end)
  force("ROOM", function()
    self.inventory = big_inventory
    self.relics = four_relics
    self.boss = { hp = 99, max_hp = 120 }
    self.boss_hp, self.boss_max_hp = 99, 120
    self.toast_text, self.toast_t = "BURNING MUD", 1.4
    self.flash = 0.8
  end)
  force("REWARD", function()
    self.inventory = big_inventory
    self.relics = four_relics
    self.reward_options = {
      { kind = "element", id = "fire" },
      { kind = "shape", id = "puddle" },
      { kind = "relic", id = "inferno_heart", name = "Inferno Heart", desc = "Fire spells +15% power", icon = "icon_fire" },
    }
  end)
  force("CAULDRON", function()
    self.inventory = big_inventory
    self.relics = four_relics
    self.cauldron = { ea = "fire", eb = "water", shape = "burst" }
    self.slot1 = { compound = "Magma", shape = "cone", quirk = "splits in two", power = 9, cooldown = 2.0, statuses = { "burn", "slow" } }
    self.slot2 = { compound = "Steam", shape = "projectile", quirk = "repeats once", power = 7, cooldown = 1.5, statuses = { "push", "blind" } }
  end)
  force("DEAD", function() self.relics = four_relics end)
  force("WIN", function() self.relics = four_relics end)
  local ORDER = { "TITLE", "COMBOS", "CREDITS", "HOME", "HOME_EDIT", "PAUSED", "SETTINGS", "ROOM", "REWARD", "CAULDRON", "DEAD", "WIN" }
  for _, st in ipairs(ORDER) do
    sf((ui_seen[st] or 0) >= 1, "ui msg: no ui message posted in state " .. st)
    local w = ui_worst[st] or 0
    sf(w > 0 and w <= 2048, string.format("ui msg: %s posts a ui message estimated at %d bytes (> 2048 engine limit)", st, w))
  end
  sf(ui_seen.REWARD and ui_worst.REWARD and math.floor(ui_worst.REWARD) == ui_worst.REWARD, "ui msg: REWARD worst-case not measured")
  -- the game's own best frame must be comfortably under the limit
  sf(ui_msg_max <= 2048, string.format("ui msg: worst ui message anywhere is %d bytes (> 2048 engine limit) [state=%s]", ui_msg_max, ui_msg_max_state))
end

-- return to the title screen (room 1 tiles) so the object count is comparable with the baseline
self.state = "WIN"; ui({action="continue"}); for i=1,5 do frame() end
sf(ui_msg_max > 0, "ui msg: no ui message ever sent (msg-size guards are vacuous)")
sf(not ui_big_str, "ui msg: >512B string leaked into a non-CREDITS frame: " .. tostring(ui_big_str))
sf(not ui_field_leak, "ui msg: heavy field attached to the wrong screen: " .. tostring(ui_field_leak))
local after = count()
local extras = {} for id,o in pairs(live) do if not base_ids[id] then local inp=false for _,p in ipairs(self.particles) do if p.id==id then inp=true end end extras[#extras+1]=id..' '..o.kind..' pos=('..string.format('%.0f,%.0f',o.pos.x,o.pos.y)..') inParticles='..tostring(inp)..' state='..self.state..' CREATED@'..tostring(o.tb) end end
local kills, heals = 0, 0
for _, l in ipairs(logs) do if l:find("Enemy died") then kills = kills + 1 end if l:find("Room cleared") then heals = heals + 1 end end
local state_lines = {}
for _, l in ipairs(logs) do if l:find("^State:") or l:find("^Room %d") then state_lines[#state_lines+1] = l end end
return {
  results = table.concat(results, ","), errors = errors, baseline = baseline, after = after, created = created,
  flip_true = flip_true or 0, flip_false = flip_false or 0,
  path = table.concat(path_report,'\n'), extras = table.concat(extras,' ; '), wall_viol = wall_viol, wall_first = wall_first or 'none', maxlive = stats.maxlive, maxparticles = stats.maxparticles, kills = kills, rooms_cleared = heals,
  fx_missing = fx_missing, fx_report = table.concat(fx_report, " | "), max_anims = max_anims,
  spell_fail = spell_fail, spell_pass = spell_pass, ui_msg_max = ui_msg_max, ui_worst = ui_worst,
  states = table.concat(state_lines, " | "):sub(1, 900), selfcheck = (function() for _, l in ipairs(logs) do if l:find("SELFCHECK") then return l end end end)(),
}
