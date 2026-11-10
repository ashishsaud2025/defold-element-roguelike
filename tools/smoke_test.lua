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
  states = table.concat(state_lines, " | "):sub(1, 900), selfcheck = (function() for _, l in ipairs(logs) do if l:find("SELFCHECK") then return l end end end)(),
}
