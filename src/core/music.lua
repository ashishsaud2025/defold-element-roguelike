-- /src/core/music.lua
-- Adaptive music: state-driven stem mixing.
-- Pure logic + injected backend (same pattern as sfx.lua). game.script calls
-- music.set_state / music.set_intensity / music.update.
--
-- States:
--   TITLE      -> mus_title loop
--   ROOM       -> mus_room_pad + mus_room_rhythm + mus_room_lead (intensity mixed)
--   BOSS       -> mus_boss loop (crossfade from room stems)
--   CAULDRON   -> mus_room_pad only (calm)
--   REWARD     -> mus_room_pad only (calm)
--   WIN / DEAD -> one-shot sting, all loops stopped
--
-- ROOM intensity: pad always on; rhythm fades in above 0.25; lead above 0.60.
-- Gains are stepped each frame (about 0.8 s fade) so nothing clicks.
-- Music bus gain comes from sfx.BUS.music.

local sfx = require "src.core.sfx"

local M = {}
M.ENABLED = true

local FADE = 0.8   -- seconds to ramp stem gains / crossfade

-- Stems for the ROOM state. All generated at the same length so they layer.
local STEMS = {
    { id = "mus_room_pad",    base = 0.70, min_intensity = 0.00, always = true },
    { id = "mus_room_rhythm", base = 0.70, min_intensity = 0.25, always = false },
    { id = "mus_room_lead",   base = 0.70, min_intensity = 0.60,  always = false },
}

-- Looping music per state (one at a time)
local LOOP_BY_STATE = {
    TITLE = "mus_title",
    BOSS  = "mus_boss",
}

-- One-shot stings (non-looping)
local STING_BY_STATE = {
    WIN  = "mus_win",
    DEAD = "mus_dead",
}

-- Calm states: pad only
local CALM_STATES = { CAULDRON = true, REWARD = true, HOME = true }

local current_state = nil
local current_loop = nil      -- id of the active looping music
local active_stems = {}       -- [id] = true while a stem is playing
local stem_target = {}        -- [id] = target gain factor (0..1)
local stem_current = {}       -- [id] = current gain factor (0..1)

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

-- Gain factor (0..1) for a stem at the given intensity.
local function stem_factor(stem, intensity)
    if stem.always then return 1.0 end
    if intensity <= stem.min_intensity then return 0.0 end
    return clamp((intensity - stem.min_intensity) / (1.0 - stem.min_intensity), 0, 1)
end

local function stop_loop()
    if current_loop then
        sfx.stop(current_loop)
        current_loop = nil
    end
end

local function play_loop(id)
    if sfx.backend == nil then return end
    if current_loop == id then return end
    stop_loop()
    sfx.play(id, { gain = 1.0 })   -- manifest gain * music bus applied by sfx
    current_loop = id
end

local function stop_stem(id)
    if not active_stems[id] then return end
    active_stems[id] = nil
    stem_current[id] = nil
    stem_target[id] = nil
    sfx.stop(id)
end

local function start_stem(id)
    if sfx.backend == nil then return end
    active_stems[id] = true
    stem_current[id] = 0
    stem_target[id] = stem_target[id] or 0
    sfx.play(id, { gain = 0 })     -- start silent, faded in by update
end

-- Public API ---------------------------------------------------------------

function M.set_state(state, ctx)
    if not M.ENABLED then return end
    ctx = ctx or {}
    -- Don't skip if the loop never actually started (e.g. backend wasn't ready yet).
    if state == current_state and current_loop ~= nil then return end

    stop_loop()
    for id in pairs(active_stems) do stop_stem(id) end

    current_state = state

    if LOOP_BY_STATE[state] then
        play_loop(LOOP_BY_STATE[state])
    elseif state == "ROOM" then
        for _, s in ipairs(STEMS) do start_stem(s.id) end
        M.set_intensity(ctx.intensity or 0)
    elseif CALM_STATES[state] then
        start_stem("mus_room_pad")
        stem_target["mus_room_pad"] = 1.0
        stem_current["mus_room_pad"] = 1.0
        sfx.play("mus_room_pad", { gain = 1.0 })
    elseif STING_BY_STATE[state] then
        sfx.play(STING_BY_STATE[state], { gain = 0.8 })
    end
end

function M.set_intensity(intensity)
    if not M.ENABLED then return end
    intensity = clamp(intensity or 0, 0, 1)
    for _, s in ipairs(STEMS) do
        stem_target[s.id] = stem_factor(s, intensity)
    end
end

function M.update(dt)
    if not M.ENABLED then return end
    dt = dt or 0
    local step = dt / FADE

    for id in pairs(active_stems) do
        local cur = stem_current[id] or 0
        local tgt = stem_target[id] or 0
        local new = cur + (tgt - cur) * step
        if math.abs(new - tgt) < 0.001 then new = tgt end
        stem_current[id] = new
        sfx.set_gain(id, new)
    end

    -- Drop stems that have faded to silence and stay there
    for id in pairs(active_stems) do
        if (stem_current[id] or 0) <= 0 and (stem_target[id] or 0) <= 0 then
            stop_stem(id)
        end
    end
end

function M.reset()
    stop_loop()
    for id in pairs(active_stems) do stop_stem(id) end
    current_state = nil
end

return M
