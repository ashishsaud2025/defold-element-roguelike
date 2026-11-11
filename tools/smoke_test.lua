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
msg = { url = function(sock, path, frag) return {path=path, frag=frag} end, post = function() end }
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
local chunk = assert(loadfile(ROOT.."main/game.script"))
chunk()
local skillgen = require "src.core.skillgen"
local data = require "src.core.data"

local self = {}
init(self)
local baseline = 0 local base_ids = {} for id in pairs(live) do baseline = baseline + 1 base_ids[id]=true end

local function ui(a) on_message(self, "ui_action", a, nil) end
local function act(id, pressed, released) on_input(self, id, {pressed=pressed, released=released}) end
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
local stats = { rooms=0, wins=0, deaths=0, maxlive=0, maxparticles=0, casts=0 }
local function play_run(allow_death, label)
  ui({action="start"}); ui({action="pick", element="fire"}); ui({action="pick", element=ELEM[math.random(4)]}); ui({action="enter"})
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
  ui({action="start"}); ui({action="pick", element="fire"}); ui({action="pick", element="fire"}); ui({action="enter"})
  self.player.hp = 1; self.player.max_hp = 1
  local g=0 while self.state ~= "DEAD" and g < 60*60 do g=g+1 frame() end
  results[#results+1] = self.state
  ui({action="continue"}); frame()
end

-- ===== Pathing test: stationary player, does every enemy find a way to them? =====
local path_report = {}
for k = 1, 9 do
  ui({action="start"}); ui({action="pick", element="fire"}); ui({action="pick", element="fire"}); ui({action="enter"})
  self.room_number = k - 1; self.state = "CAULDRON"; ui({action="done"})
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
  ui({action="start"}); ui({action="pick", element="fire"}); ui({action="pick", element="fire"}); ui({action="enter"})
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
local function begin_room()
  self.state = "DEAD"                        -- force reset_run from any prior state
  ui({ action = "continue" })
  ui({ action = "start" })
  ui({ action = "pick", element = "fire" })
  ui({ action = "pick", element = "fire" })
  ui({ action = "enter" })
  self.player.hp, self.player.max_hp = 100, 100
  self.player.alive, self.player.invuln = true, 0
  self.aim.x, self.aim.y = self.player_pos.x + 120, self.player_pos.y
  self.slot1_cooldown, self.slot2_cooldown = 0, 0
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
  equip(mk("puddle", nil, "fire", "fire")); cast1()
  frames(15)
  sf(mud ~= nil and mud.burning_mud == true, "burning mud: not ignited")
  sf(self.toast_text == "BURNING MUD" and (self.toast_t or 0) > 0,
     "burning mud: no readable banner")
  if mud then
    sf(list_has(mud.statuses, "burn"), "burning mud: no burn status")
    frames(200)
    sf(mud.burning_mud == false, "burning mud: did not revert")
    sf(not list_has(mud.statuses, "burn"), "burning mud: burn was not removed on revert")
    sf((self.toast_t or 0) == 0, "burning mud: banner never expired")
    frames(30)
    sf(mud.burning_mud == false, "burning mud: re-ignited forever while the fire area lived")
  end
end
-- B. Wind over a lingering fire pool -> one spread, 60% duration.
if begin_room() then
  equip(mk("puddle", nil, "fire", "fire")); cast1()
  local fire = self.puddles[1]
  local fire_dur = fire and fire.duration
  equip(mk("puddle", nil, "wind", "wind")); cast1()
  frames(15)
  sf(fire ~= nil and fire.spread_done == true, "fire spread: original pool did not spread")
  sf(self.toast_text == "FIRE SPREAD" and (self.toast_t or 0) > 0,
     "fire spread: no readable banner")
  local spread = nil
  for _, p in ipairs(self.puddles) do
    if p ~= fire and p.compound ~= "Gale" then spread = p end
  end
  sf(spread ~= nil, "fire spread: no new pool")
  if spread and fire_dur then
    sf(spread.spread_done == true, "fire spread: new pool is not marked as a spread")
    sf(near(spread.duration, fire_dur * 0.6, 0.25), "fire spread: duration=" .. spread.duration)
  end
  frames(120)
  sf(#self.puddles == 3, "fire spread: spread again, pools=" .. #self.puddles)
end
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

for i=1,300 do frame() end
-- flush leftover timers
for _, t in ipairs(timers) do t.fn() end
timers = {}
frame()
-- return to the title screen (room 1 tiles) so the object count is comparable with the baseline
self.state = "WIN"; ui({action="continue"}); for i=1,5 do frame() end
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
  spell_fail = spell_fail, spell_pass = spell_pass,
  states = table.concat(state_lines, " | "):sub(1, 900), selfcheck = (function() for _, l in ipairs(logs) do if l:find("SELFCHECK") then return l end end end)(),
}
