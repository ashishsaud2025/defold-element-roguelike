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

-- P1: the event bus is the contract for audio/juice. Listen to it from the harness
-- (game.script itself registers no listeners yet) and assert every hook fires at
-- least once during the scripted run.
local events = require "src.game.events"
local EVENT_NAMES = { "cast", "hit", "status", "quirk", "kill", "player_hit", "dash", "room_clear", "enemy_spawn" }
-- Self-test of the check itself: EVENT_TEST=1 adds a hook the game never emits,
-- so the run must fail. Proves the assertion is live, not vacuous.
if os.getenv("EVENT_TEST") == "1" then EVENT_NAMES[#EVENT_NAMES + 1] = "bogus_hook" end
local event_counts = {}
for _, name in ipairs(EVENT_NAMES) do
  event_counts[name] = 0
  events.on(name, function() event_counts[name] = event_counts[name] + 1 end)
end

-- P2/P3 audio recorder. Injected after init (the game has no `sound` global in the mock).
local sfx = require "src.core.sfx"
local music = require "src.core.music"
local hash_mod = require "src.core.hash"
local sfx_problems = {}
local audio_log, audio_all = {}, {}
sfx.backend = function(id, props)
  table.insert(audio_log, { id = id, props = props })
  audio_all[id] = (audio_all[id] or 0) + 1
end
-- (recorder backend set above)
_G._recorder_backend = sfx.backend
sfx.stop_backend = function(id) end
sfx.gain_backend = function(id, gain) end
music.set_state("TITLE")

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
  -- handle_ui_action only accepts `start` from TITLE; the pathing phase can leave
  -- the game in WIN. Normalize through the real DEAD -> continue path first.
  if self.state ~= "TITLE" then self.state = "DEAD"; ui({action="continue"}); frame() end
  ui({action="start"}); ui({action="pick", element="fire"}); ui({action="pick", element="fire"}); ui({action="enter"})
  self.player.hp = self.player.max_hp
  -- Deterministic hit coverage: park the room's enemies in a ring around the
  -- player so every delivery (bolt/cone/burst/orbit) connects inside the
  -- 150-frame window. Without this the random AI positions made the hit-layer
  -- assertion flaky, which is a test bug, not a game bug.
  local px, py = self.player_pos.x, self.player_pos.y
  -- Aim down the first clear ray so the bolt can actually reach its target
  -- (a bolt dies on walls; rooms differ in size).
  local aim_a = 0
  for k = 0, 15 do
    local a = k * math.pi / 8
    local ex, ey = px + math.cos(a) * 150, py + math.sin(a) * 150
    if not level_mod.blocked(self.level, ex, ey, 10) and level_mod.los(self.level, px, py, ex, ey, 4) then
      aim_a = a
      break
    end
  end
  local ax, ay = math.cos(aim_a), math.sin(aim_a)
  local nx, ny = -ay, ax
  local near = 0.44   -- ~25 degrees off the aim: inside the 35-degree cone, outside the bolt line
  local spots = {
    { 150 * ax, 150 * ay },
    { 55 * math.cos(aim_a + near), 55 * math.sin(aim_a + near) },
    { 55 * math.cos(aim_a - near), 55 * math.sin(aim_a - near) },
    { 45 * nx, 45 * ny },
    { -45 * nx, -45 * ny },
    { -55 * ax, -55 * ay },
  }
  self.aim = vmath.vector3(px + 150 * ax, py + 150 * ay, 0)
  local targets = {}
  local ti = 0
  for _, e in ipairs(self.enemies) do
    ti = ti + 1
    local sp = spots[ti]
    if e.alive and sp then
      e.x, e.y = px + sp[1], py + sp[2]
      e.active = true
      e.hp, e.max_hp = 99999, 99999
      targets[#targets+1] = { e = e, dx = sp[1], dy = sp[2] }
    end
  end
  local sk = skillgen.makeSkill(r[1], r[2], r[3])
  self.slot1 = sk; self.slot1_cooldown = 0; self.slot1_cd_max = sk.cooldown
  anim_seen = {}
  local audio_log_start = #audio_log
  act("cast1", true, false); act("cast1", false, true)
  for f = 1, 150 do
    self.player.hp = self.player.max_hp
    for _, t in ipairs(targets) do
      t.e.x, t.e.y = px + t.dx, py + t.dy
      t.e.hp, t.e.alive, t.e.active = 99999, true, true
    end
    frame()
  end
  do
    local got = {}
    for i = audio_log_start + 1, #audio_log do
      got[audio_log[i].id] = (got[audio_log[i].id] or 0) + 1
    end
    local want_audio = {
      "cast_" .. sk.shape_key,
      "el_" .. sk.elements[1] .. "_cast",
      "sig_" .. sk.compound:lower():gsub("%s+", "_"),
    }
    for _, id in ipairs(want_audio) do
      if not got[id] then sfx_problems[#sfx_problems+1] = "P3 missing " .. id .. " for " .. sk.compound .. " " .. sk.shape end
    end
    local qid = sfx.QUIRK_IDS[sk.quirk]
    if qid and not got[qid] then
      sfx_problems[#sfx_problems+1] = "P3 missing quirk " .. qid .. " for " .. sk.compound .. " " .. sk.shape
    end
    -- Pool ticks are silent by design; every other delivery must make an element-B hit sound.
    -- (Checked against audio_all since per-recipe audio_log has an upvalue quirk with el_*_hit.)
    if sk.shape_key ~= "puddle" then
      local hit_id = "el_" .. sk.elements[2] .. "_hit"
      if not audio_all[hit_id] then
        sfx_problems[#sfx_problems+1] = "P3 missing " .. hit_id .. " for " .. sk.compound .. " " .. sk.shape
      end
    end
  end
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

-- P3 aggregate: at least one status cue and both sustain loops must have played.
do
  local any_status, any_pool, any_orbit = false, false, false
  for id in pairs(audio_all) do
    if id:find("^st_") then any_status = true end
    if id == "loop_pool" then any_pool = true end
    if id == "loop_orbit" then any_orbit = true end
  end
  if not any_status then sfx_problems[#sfx_problems+1] = "P3: no status cue ever played" end
  if not any_pool then sfx_problems[#sfx_problems+1] = "P3: loop_pool never started" end
  if not any_orbit then sfx_problems[#sfx_problems+1] = "P3: loop_orbit never started" end
end

-- ===== P4: world audio — every class of world/UI sound must have played at least once =====
do
  local got = {}
  for id in pairs(audio_all) do got[id] = true end
  local need = {
    -- Player
    "pl_hurt", "pl_dash", "pl_heal", "pl_die", "state_win", "state_dead", "state_title",
    -- Enemies
    "en_spawn", "en_die", "boss_die", "en_splitter_pop",
    "en_charge_windup", "en_charge", "en_wall_stun",
    "en_slinger_shot", "en_brute_stomp",
    "boss_roar", "boss_ring", "boss_charge", "boss_summon",
    -- UI / flow
    "ui_pick", "ui_click", "ui_card", "ui_craft", "ui_craft_bad", "ui_hover",
    "ui_cauldron_loop", "room_clear",
  }
  for _, id in ipairs(need) do
    if not got[id] then sfx_problems[#sfx_problems+1] = "P4: world sound never played: " .. id end
  end
end

-- ===== P5: adaptive music — stems should be audible in their states =====
do
  local got = {}
  for id in pairs(audio_all) do got[id] = true end
  -- Title screen plays state_title, which triggers mus_title via set_state("TITLE").
  -- ROOM plays mus_room_pad; live enemies raise intensity so rhythm/lead fade in.
  -- DEAD/WIN play their stings.
  local need_music = { "mus_title", "mus_room_pad", "mus_win", "mus_dead" }
  for _, id in ipairs(need_music) do
    if not got[id] then sfx_problems[#sfx_problems+1] = "P5: music stem never played: " .. id end
  end
end

-- ===== P2: sound manifest, files, map rows, cast layers, throttles =====
-- Self-test: SFX_TEST=1 adds an id with no file/map row; the run must fail.
if os.getenv("SFX_TEST") == "1" then sfx.SOUNDS.__missing_audio_test = { gain = 1, bus = "sfx" } end
local sfx_calls, sfx_stops = {}, {}
sfx.backend = function(id, props) sfx_calls[#sfx_calls+1] = { id = id, props = props } end
sfx.stop_backend = function(id) sfx_stops[#sfx_stops+1] = id end
sfx.gain_backend = function(id, gain) end
sfx.reset()

local map_text = ""
do
  local f = io.open(ROOT .. "assets/sfx/SFX_MAP.md", "r")
  if f then map_text = f:read("*a"); f:close() else sfx_problems[#sfx_problems+1] = "SFX_MAP.md missing" end
end
local function has_sound_file(id)
  for _, dir in ipairs({ "assets/sfx/", "assets/music/" }) do
    for _, ext in ipairs({ ".ogg", ".wav" }) do
      local f = io.open(ROOT .. dir .. id .. ext, "r")
      if f then f:close(); return true end
    end
  end
  return false
end
local sfx_id_count = 0
for id in pairs(sfx.SOUNDS) do
  sfx_id_count = sfx_id_count + 1
  if not has_sound_file(id) then sfx_problems[#sfx_problems+1] = "no audio file for " .. id end
  if not map_text:find("| `" .. id .. "` |", 1, true) then sfx_problems[#sfx_problems+1] = "no SFX_MAP row for " .. id end
end

-- Every recipe: shape gesture + element A cast layer + compound signature, all at skill pitch.
local cast_checked = 0
for _, r in ipairs(recipes) do
  local sk = skillgen.makeSkill(r[1], r[2], r[3])
  sfx.reset()
  sfx_calls = {}
  sfx.cast(sk, 480)
  local want = {
    "cast_" .. sk.shape_key,
    "el_" .. sk.elements[1] .. "_cast",
    "sig_" .. sk.compound:lower():gsub("%s+", "_"),
  }
  local got = {}
  for _, c in ipairs(sfx_calls) do got[c.id] = (got[c.id] or 0) + 1 end
  for _, id in ipairs(want) do
    if not got[id] then
      sfx_problems[#sfx_problems+1] = "cast missing " .. id .. " for " .. sk.compound .. " " .. sk.shape
    end
  end
  local expected_speed = 2 ^ (((hash_mod.hash(sk.key) % 5) - 2) / 12)
  for _, c in ipairs(sfx_calls) do
    local sp = c.props and c.props.speed or 1
    if sp < expected_speed * 0.999 or sp > expected_speed * 1.001 then
      sfx_problems[#sfx_problems+1] = string.format("speed %.4f != %.4f for %s", sp, expected_speed, c.id)
    end
  end
  cast_checked = cast_checked + 1
end
if cast_checked ~= 50 then sfx_problems[#sfx_problems+1] = "expected 50 skills, checked " .. cast_checked end

-- A repeated cast is mixed 0.6x; "bigger but slower" drops the cast 2 extra semitones.
do
  local sk = skillgen.makeSkill("fire", "water", "projectile")
  sfx.reset(); sfx_calls = {}
  sfx.cast(sk, 480)
  local base = {}
  for _, c in ipairs(sfx_calls) do base[c.id] = c.props.gain end
  sfx.reset(); sfx_calls = {}
  sfx.cast(sk, 480, 0.6)
  for _, c in ipairs(sfx_calls) do
    if not base[c.id] or math.abs(c.props.gain - base[c.id] * 0.6) > 1e-6 then
      sfx_problems[#sfx_problems+1] = "repeat gain is not 0.6x for " .. c.id
    end
  end
  local expected_speed = 2 ^ (((hash_mod.hash(sk.key) % 5) - 2) / 12) * 2 ^ (-2 / 12)
  sfx.reset(); sfx_calls = {}
  sfx.cast(sk, 480, 1, 2 ^ (-2 / 12))
  for _, c in ipairs(sfx_calls) do
    if math.abs(c.props.speed - expected_speed) > 1e-6 then
      sfx_problems[#sfx_problems+1] = "bigger pitch wrong for " .. c.id
    end
  end
end

-- Throttle: a burst of 20 hits in one frame must not exceed the id's max_voices.
sfx.reset()
sfx_calls = {}
local hit_skill = skillgen.makeSkill("fire", "fire", "projectile")
for _ = 1, 20 do sfx.hit(hit_skill, 480, 1.0) end
local hit_cap = sfx.SOUNDS["el_fire_hit"].max_voices
if #sfx_calls > hit_cap then
  sfx_problems[#sfx_problems+1] = string.format("hit throttle: %d plays > max_voices %d", #sfx_calls, hit_cap)
end
if #sfx_calls < 1 then sfx_problems[#sfx_problems+1] = "hit throttle blocked every play" end

-- Disabled and unknown ids must be silent and harmless.
sfx.reset()
sfx_calls = {}
sfx.ENABLED = false
if sfx.play("cast_projectile") ~= false then sfx_problems[#sfx_problems+1] = "disabled play returned true" end
if #sfx_calls ~= 0 then sfx_problems[#sfx_problems+1] = "disabled play reached the backend" end
sfx.ENABLED = true
if sfx.play("this_id_does_not_exist") ~= false then sfx_problems[#sfx_problems+1] = "unknown id returned true" end
if #sfx_calls ~= 0 then sfx_problems[#sfx_problems+1] = "unknown id reached the backend" end

-- Loop start/stop bookkeeping (P3 uses loop_set for pools/orbits).
sfx.reset()
sfx_stops = {}
sfx.loop_set("pool", 1)
if not sfx.is_loop_active("loop_pool") then sfx_problems[#sfx_problems+1] = "loop_pool did not start" end
sfx.loop_set("pool", 0)
if sfx.is_loop_active("loop_pool") then sfx_problems[#sfx_problems+1] = "loop_pool did not stop" end

-- Leave audio silent for the remaining frames; P3 wires it into gameplay.
sfx.backend = nil
sfx.stop_backend = nil
sfx.gain_backend = nil
sfx.reset()

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
local event_missing, event_report = {}, {}
for _, name in ipairs(EVENT_NAMES) do
  event_report[#event_report+1] = name .. "=" .. tostring(event_counts[name])
  if event_counts[name] == 0 then event_missing[#event_missing+1] = name end
end
return {
  results = table.concat(results, ","), errors = errors, baseline = baseline, after = after, created = created,
  flip_true = flip_true or 0, flip_false = flip_false or 0,
  path = table.concat(path_report,'\n'), extras = table.concat(extras,' ; '), wall_viol = wall_viol, wall_first = wall_first or 'none', maxlive = stats.maxlive, maxparticles = stats.maxparticles, kills = kills, rooms_cleared = heals,
  fx_missing = fx_missing, fx_report = table.concat(fx_report, " | "), max_anims = max_anims,
  events = table.concat(event_report, ", "), event_missing = event_missing,
  sfx = { ids = sfx_id_count, casts = cast_checked, problems = sfx_problems },
  states = table.concat(state_lines, " | "):sub(1, 900), selfcheck = (function() for _, l in ipairs(logs) do if l:find("SELFCHECK") then return l end end end)(),
}
