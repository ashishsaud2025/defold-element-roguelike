-- /src/game/anim.lua
-- Code-driven animation for the static pack sprites.
--
-- The art packs ship one still image per character, so all motion is faked here:
-- a scale (sx, sy multipliers of the base scale), a rotation in radians and a small
-- pixel offset (ox, oy) for the sprite only. Collision, radii, positions and AI are
-- never touched: main/game.script applies the result to the visual game object.
--
-- Every function is pure and deterministic (no math.random, no time source) and every
-- output is clamped, so a bad dt or a missing state field can never produce NaN or a
-- wildly stretched sprite. Returns { sx, sy, rot, ox, oy }.
local M = {}

local MIN_S, MAX_S = 0.5, 1.6
local MAX_ROT = 0.35
local MAX_OFF = 4.0

local function num(v)
    v = tonumber(v)
    if v == nil or v ~= v or v == math.huge or v == -math.huge then return 0 end
    return v
end

local function clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function pack(sx, sy, rot, ox, oy)
    return {
        sx = clamp(num(sx), MIN_S, MAX_S),
        sy = clamp(num(sy), MIN_S, MAX_S),
        rot = clamp(num(rot), -MAX_ROT, MAX_ROT),
        ox = clamp(num(ox), -MAX_OFF, MAX_OFF),
        oy = clamp(num(oy), -MAX_OFF, MAX_OFF),
    }
end

-- Player. s = { moving = bool, dash = bool, dx, dy, lean }
--   idle    breathing bob (~2 px, 1.2 Hz)
--   moving  run bob + squash
--   dashing stretched along the dash, tilted up/down
--   lean    -1..1 aim direction, adds a tiny lean toward the cursor
function M.player(s, t)
    t = num(t)
    s = s or {}
    local sx, sy, rot, ox, oy = 1, 1, 0, 0, 0

    if s.dash then
        sx, sy = 1.30, 0.80
        local dy = num(s.dy)
        rot = (dy < -0.3) and -0.14 or ((dy > 0.3) and 0.14 or 0)
        oy = 1.0
    elseif s.moving then
        local step = math.abs(math.sin(t * 9))
        sx = 1 + 0.08 * step
        sy = 1 - 0.08 * step
        oy = 1.8 * step
        rot = 0.05 * math.sin(t * 9)
    else
        local breathe = math.sin(t * 7.54)          -- 1.2 Hz
        sx = 1 - 0.015 * breathe
        sy = 1 + 0.02 * breathe
        oy = 1.8 * breathe
    end

    rot = rot + 0.06 * clamp(num(s.lean), -1, 1)
    return pack(sx, sy, rot, ox, oy)
end

-- Enemy. kind = "wisp" | "slinger" | "charger" | "brute" | "splitter" | "boss".
-- s = { moving, charging, windup, stunned, fire, retreat }.
-- Unknown kinds get a neutral breathing idle.
function M.enemy(kind, s, t)
    t = num(t)
    s = s or {}
    local sx, sy, rot, ox, oy = 1, 1, 0, 0, 0

    if kind == "wisp" then
        -- slow float: the sprite hovers and swells slightly
        local bob = math.sin(t * 2.6)
        sx = 1 + 0.04 * bob
        sy = 1 - 0.04 * bob
        oy = 1.8 + 1.4 * math.sin(t * 1.9)
        rot = 0.05 * math.sin(t * 1.3)
        if s.windup then sx, sy = sx * 1.12, sy * 1.12 end
    elseif kind == "slinger" then
        -- robed caster: gentle sway; recoils when it fires, leans away when retreating
        rot = 0.07 * math.sin(t * 2.2)
        oy = 0.8 * math.sin(t * 3.1)
        sx = 1 + 0.02 * math.sin(t * 2.2)
        sy = 1 - 0.02 * math.sin(t * 2.2)
        if s.retreat then rot = rot - 0.10 end
        if s.fire then
            sx, sy = sx * 1.16, sy * 1.08
            oy = oy + 1.0
        elseif s.windup then
            sx, sy = sx * 1.10, sy * 1.10
        end
    elseif kind == "charger" then
        if s.charging then
            -- stretched forward, nose down
            sx, sy = 1.20, 0.86
            rot = -0.10
        elseif s.windup then
            -- crouched, shivering before the dash
            sx, sy = 1.10, 0.88
            rot = 0.08 * math.sin(t * 40)
        elseif s.moving then
            local step = math.abs(math.sin(t * 14))
            sx = 1 + 0.03 * step
            sy = 1 - 0.03 * step
            oy = 1.6 * step
        else
            sx = 1 + 0.02 * math.sin(t * 2.0)
            sy = 1 - 0.02 * math.sin(t * 2.0)
        end
    elseif kind == "brute" then
        -- heavy stomp: one squash every ~0.7 s while walking
        if s.moving then
            local step = math.abs(math.sin(t * 8.98))
            sx = 1 + 0.06 * step
            sy = 1 - 0.10 * step
            oy = 2.4 * step
        else
            local br = math.sin(t * 1.8)
            sx = 1 + 0.02 * br
            sy = 1 - 0.02 * br
        end
        if s.windup then sx, sy = sx * 1.08, sy * 1.08 end
    elseif kind == "splitter" then
        -- jelly bounce (x and y out of phase)
        local p = math.sin(t * 5.0)
        sx = 1 + 0.10 * p
        sy = 1 - 0.08 * p
        oy = 1.2 * math.abs(p)
    elseif kind == "boss" then
        -- huge slow breathing; swells when it winds up, charges or summons
        local br = math.sin(t * 1.5)
        sx = 1 + 0.05 * br
        sy = 1 - 0.04 * br
        oy = 1.5 + 1.5 * math.sin(t * 1.1)
        rot = 0.02 * math.sin(t * 0.8)
        if s.charging or s.windup then
            sx, sy = sx * 1.10, sy * 1.10
            rot = rot + 0.06 * math.sin(t * 22)
        end
    else
        local br = math.sin(t * 2.0)
        sx = 1 + 0.02 * br
        sy = 1 - 0.02 * br
        oy = 0.6 * math.sin(t * 2.6)
    end

    if s.stunned then
        rot = rot + 0.10 * math.sin(t * 22)
        ox = ox + 0.8 * math.sin(t * 30)
    end

    return pack(sx, sy, rot, ox, oy)
end

return M
