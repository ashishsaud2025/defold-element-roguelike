-- /src/core/crng.lua
-- Cosmetic RNG. Separate from src/core/rng.lua on purpose: gameplay determinism
-- (skillgen golden vectors, room composition, AI wander) must never be shifted by
-- a sound pitch wobble or a particle variation. Deterministic for a given seed.
--
-- LCG constants from Numerical Recipes. LuaJIT numbers are doubles, and
-- state * 1664525 stays below 2^53, so the modulo is exact.
local M = {}

local A = 1664525
local C = 1013904223
local MOD = 4294967296

local state = 0

function M.seed(s)
    state = math.floor(tonumber(s) or 0) % MOD
    if state < 0 then state = state + MOD end
    return state
end

-- Uniform in [0, 1).
function M.next()
    state = (state * A + C) % MOD
    return state / MOD
end

-- Uniform in [lo, hi).
function M.range(lo, hi)
    return lo + (hi - lo) * M.next()
end

-- Deterministic seed from a string, so a given sound id always wobbles the same
-- way within a run but different ids differ. Uses FNV-1a via hash.lua.
function M.seed_string(s)
    local ok, hash = pcall(require, "src.core.hash")
    if ok and hash and hash.hash then
        return M.seed(hash.hash(tostring(s)))
    end
    local h = 0
    s = tostring(s)
    for i = 1, #s do h = (h * 31 + s:byte(i)) % MOD end
    return M.seed(h)
end

return M
