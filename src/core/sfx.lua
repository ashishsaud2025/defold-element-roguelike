-- /src/core/sfx.lua
-- Sound manifest + throttling + high-level event helpers.
-- Pure Lua 5.1: no engine calls. game.script injects the backend:
--   sfx.backend      = function(id, props)  -> sound.play("/sfx#" .. id, props)
--   sfx.stop_backend = function(id)         -> sound.stop("/sfx#" .. id)
--   sfx.gain_backend = function(id, gain)   -> sound.set_gain("/sfx#" .. id, gain)
-- Tests inject a recorder and inspect the calls.
--
-- Rules (MASTER_PROMPT 2.2):
--   * unknown id -> do nothing, return false, log once (never error)
--   * per-id min_gap + max_voices, plus a global voice cap (16)
--   * pan = (x - 480) / 480 * 0.6, clamped to +-0.6
--   * pitch is the Defold `speed` property: semitone s -> 2^(s/12)
--   * skill pitch = (hash(skill.key) % 5) - 2 semitones, so a recipe always
--     sounds the same and a different recipe sounds slightly different.
local crng = require "src.core.crng"

local M = {}

M.ENABLED = true
M.GLOBAL_MAX_VOICES = 16
M.BUS = { master = 1.0, sfx = 1.0, music = 0.7 }
M.SOUNDS = {}

-- Injected by game.script / tests.
M.backend = nil
M.stop_backend = nil
M.gain_backend = nil

M.clock = 0
local last_play = {}
local voices = {}   -- non-loop voices: { id = ..., until_t = ... }
local loops = {}    -- active loop id -> current gain
local warned = {}

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function define(ids, spec)
    for _, id in ipairs(ids) do
        local e = {}
        for k, v in pairs(spec) do e[k] = v end
        M.SOUNDS[id] = e
    end
end

-- ===== Manifest (every id in MASTER_PROMPT 2.3) =====

-- Shape gestures
define({ "cast_projectile", "cast_puddle", "cast_orbit", "cast_cone", "cast_burst" },
    { gain = 0.78, min_gap = 0.04, max_voices = 2, pitch_var = 0, bus = "sfx", dur = 0.55 })

-- Element cast layers (A) and hit layers (B)
define({ "el_fire_cast", "el_water_cast", "el_wind_cast", "el_earth_cast" },
    { gain = 0.55, min_gap = 0.03, max_voices = 2, pitch_var = 0, bus = "sfx", dur = 0.5 })
define({ "el_fire_hit", "el_water_hit", "el_wind_hit", "el_earth_hit" },
    { gain = 0.60, min_gap = 0.03, max_voices = 3, pitch_var = 0.03, bus = "sfx", dur = 0.2 })

-- Compound signatures (two-note chords)
define({ "sig_inferno", "sig_tide", "sig_gale", "sig_quake", "sig_steam",
         "sig_ember", "sig_magma", "sig_mist", "sig_mud", "sig_dust" },
    { gain = 0.58, min_gap = 0.02, max_voices = 2, pitch_var = 0, bus = "sfx", dur = 0.65 })

-- Status cues; min_gap 0.15 so a nova hitting 10 enemies is one sound
define({ "st_burn", "st_slow", "st_stun", "st_root", "st_blind", "st_confuse",
         "st_push", "st_pull", "st_hide" },
    { gain = 0.68, min_gap = 0.15, max_voices = 2, pitch_var = 0.02, bus = "sfx", dur = 0.45 })

-- Quirks
define({ "qk_split", "qk_repeat", "qk_trail", "qk_big", "qk_cost" },
    { gain = 0.62, min_gap = 0.05, max_voices = 1, pitch_var = 0, bus = "sfx", dur = 0.35 })

-- Sustain loops (one per type); gain 1.0 so loop_set's gain is the final level
define({ "loop_pool", "loop_orbit" },
    { gain = 1.0, min_gap = 0, max_voices = 1, pitch_var = 0, bus = "sfx", loop = true })

-- Player
define({ "pl_hurt", "pl_dash", "pl_die", "pl_heal" },
    { gain = 0.78, min_gap = 0.05, max_voices = 2, pitch_var = 0, bus = "sfx", dur = 0.5 })
define({ "pl_lowhp" },
    { gain = 0.55, min_gap = 0, max_voices = 1, pitch_var = 0, bus = "sfx", loop = true })

-- Enemies
define({ "en_spawn", "en_hit", "en_die", "en_charge_windup", "en_charge",
         "en_slinger_shot", "en_brute_stomp", "en_splitter_pop", "en_wall_stun" },
    { gain = 0.65, min_gap = 0.05, max_voices = 3, pitch_var = 0.02, bus = "sfx", dur = 0.45 })
define({ "boss_roar", "boss_ring", "boss_charge", "boss_summon", "boss_die" },
    { gain = 0.88, min_gap = 0.12, max_voices = 1, pitch_var = 0, bus = "sfx", dur = 1.2 })

-- UI / flow (centred: no x is passed)
define({ "ui_hover", "ui_click", "ui_card", "ui_pick", "ui_craft", "ui_craft_bad" },
    { gain = 0.52, min_gap = 0.06, max_voices = 2, pitch_var = 0, bus = "sfx", dur = 0.3 })
define({ "room_clear", "state_win", "state_dead", "state_title" },
    { gain = 0.75, min_gap = 0.2, max_voices = 1, pitch_var = 0, bus = "sfx", dur = 1.6 })
define({ "ui_cauldron_loop" },
    { gain = 0.45, min_gap = 0, max_voices = 1, pitch_var = 0, bus = "sfx", loop = true })

-- Generated now so later phases only have to wire them
define({ "rx_steam", "rx_shatter", "rx_flare", "rx_bog", "rx_whirl",
         "combo_up", "fusion", "hit_weak", "hit_resist", "crit_streak",
         "relic_get", "shrine", "shop_buy" },
    { gain = 0.72, min_gap = 0.08, max_voices = 2, pitch_var = 0.01, bus = "sfx", dur = 0.6 })

-- Music stems
define({ "mus_room_pad", "mus_room_rhythm", "mus_room_lead", "mus_boss", "mus_title" },
    { gain = 0.70, min_gap = 0, max_voices = 1, pitch_var = 0, bus = "music", loop = true })
define({ "mus_win", "mus_dead" },
    { gain = 0.80, min_gap = 0, max_voices = 1, pitch_var = 0, bus = "music", dur = 5.0 })

-- Quirk display text (skill.quirk, frozen) -> sound id
M.QUIRK_IDS = {
    ["splits in two"] = "qk_split",
    ["leaves a trail"] = "qk_trail",
    ["repeats once"] = "qk_repeat",
    ["bigger but slower"] = "qk_big",
    ["costs 5% health"] = "qk_cost",
}

-- ===== Internals =====

local function warn_unknown(id)
    if warned[id] then return end
    warned[id] = true
    print("sfx: unknown sound id '" .. tostring(id) .. "' (ignored)")
end

local function bus_gain(name)
    local bus = M.BUS[name or "sfx"] or 1
    return (M.BUS.master or 1) * bus
end

local function prune()
    local n = #voices
    for i = n, 1, -1 do
        if voices[i].until_t <= M.clock then table.remove(voices, i) end
    end
end

local function total_voices()
    prune()
    local n = #voices
    for _ in pairs(loops) do n = n + 1 end
    return n
end

local function count_id(id)
    prune()
    local n = 0
    for i = 1, #voices do if voices[i].id == id then n = n + 1 end end
    if loops[id] then n = n + 1 end
    return n
end

-- ===== Public API =====

function M.pan_for_x(x)
    if not x then return 0 end
    return clamp((x - 480) / 480 * 0.6, -0.6, 0.6)
end

function M.set_bus(name, gain)
    if M.BUS[name] == nil then return false end
    M.BUS[name] = clamp(gain or 1, 0, 2)
    return true
end

function M.volume(bus)
    return bus_gain(bus)
end

function M.play(id, opts)
    if not M.ENABLED then return false end
    local s = M.SOUNDS[id]
    if not s then warn_unknown(id) return false end
    if M.backend == nil then return false end
    opts = opts or {}

    if s.loop then
        -- Loops are owned by loop_set/music; a second play only adjusts gain.
        if loops[id] then
            M.set_gain(id, opts.gain or 1)
            return true
        end
    else
        local gap = s.min_gap or 0
        if last_play[id] and (M.clock - last_play[id]) < gap then return false end
    end

    if count_id(id) >= (s.max_voices or 1) then return false end
    if total_voices() >= M.GLOBAL_MAX_VOICES then return false end

    local gain = clamp(s.gain * (opts.gain or 1) * bus_gain(s.bus), 0, 1.5)
    local pan = opts.pan
    if pan == nil then pan = M.pan_for_x(opts.x) end
    local speed = opts.speed or 1
    if (s.pitch_var or 0) > 0 then
        speed = speed * (1 + crng.range(-1, 1) * s.pitch_var)
    end

    local props = { gain = gain, pan = clamp(pan, -0.6, 0.6), speed = speed }
    if opts.delay then props.delay = opts.delay end
    M.backend(id, props)

    last_play[id] = M.clock
    if s.loop then
        loops[id] = gain
    else
        table.insert(voices, { id = id, until_t = M.clock + (s.dur or 0.75) })
    end
    return true
end

function M.stop(id)
    if not M.SOUNDS[id] then warn_unknown(id) return false end
    local was = loops[id] ~= nil
    loops[id] = nil
    for i = #voices, 1, -1 do
        if voices[i].id == id then table.remove(voices, i) end
    end
    if was and M.stop_backend then M.stop_backend(id) end
    return was
end

function M.set_gain(id, gain)
    if not loops[id] then return false end
    local s = M.SOUNDS[id]
    local final = clamp((gain or 1) * s.gain * bus_gain(s.bus), 0, 1.5)
    loops[id] = final
    if M.gain_backend then M.gain_backend(id, final) end
    return true
end

function M.is_loop_active(id)
    return loops[id] ~= nil
end

function M.update(dt)
    M.clock = M.clock + (dt or 0)
    prune()
end

function M.active_voices(id)
    prune()
    local n = 0
    for i = 1, #voices do
        if id == nil or voices[i].id == id then n = n + 1 end
    end
    if id ~= nil and loops[id] then n = n + 1 end
    if id == nil then for _ in pairs(loops) do n = n + 1 end end
    return n
end

-- Stop every loop and forget pending voices. Used on run reset / hot reload.
function M.reset()
    for id in pairs(loops) do
        if M.stop_backend then M.stop_backend(id) end
    end
    loops = {}
    voices = {}
    last_play = {}
    M.clock = 0
end

-- ===== High-level helpers (pure: they only call M.play) =====

function M.skill_speed(skill)
    if not skill or not skill.key then return 1 end
    local ok, hash = pcall(require, "src.core.hash")
    if not ok or not hash or not hash.hash then return 1 end
    local semitones = (hash.hash(skill.key) % 5) - 2   -- -2..+2
    return 2 ^ (semitones / 12)
end

function M.cast(skill, x, gain_mul, pitch_mul)
    if not skill then return false end
    local speed = M.skill_speed(skill) * (pitch_mul or 1)
    local gain = gain_mul or 1
    local shape = skill.shape_key or "projectile"
    M.play("cast_" .. shape, { x = x, speed = speed, gain = gain })
    local a = skill.elements and skill.elements[1]
    if a then M.play("el_" .. a .. "_cast", { x = x, gain = 0.6 * gain, speed = speed }) end
    local compound = tostring(skill.compound or ""):lower():gsub("%s+", "_")
    if compound ~= "" then
        M.play("sig_" .. compound, { x = x, speed = speed, gain = gain, delay = 0.02 })
    end
    return true
end

function M.hit(skill, x, strength)
    if not skill or not skill.elements then return false end
    local b = skill.elements[2]
    local gain = clamp(strength or 1, 0.5, 1.0)
    return M.play("el_" .. b .. "_hit", { x = x, gain = gain })
end

function M.status(name, x)
    if not name then return false end
    return M.play("st_" .. name, { x = x })
end

function M.quirk(quirk, x)
    local id = M.QUIRK_IDS[quirk]
    if not id then return false end
    return M.play(id, { x = x })
end

-- kind = "pool" | "orbit"; gain rises with the number of active effects.
function M.loop_set(kind, count)
    local id = "loop_" .. kind
    if not M.SOUNDS[id] then warn_unknown(id) return false end
    count = count or 0
    if count <= 0 then
        if loops[id] then M.stop(id) end
        return false
    end
    local gain = math.min(1, 0.4 + 0.2 * count)
    if loops[id] then
        M.set_gain(id, gain)
    else
        M.play(id, { gain = gain })
    end
    return true
end

function M.ids()
    local ids = {}
    for id in pairs(M.SOUNDS) do ids[#ids + 1] = id end
    table.sort(ids)
    return ids
end

return M
