-- /src/core/skillgen.lua
-- Deterministic skill generator. See MASTER_PROMPT section 5.
-- Uses hash.lua and rng.lua. Never uses math.random or Defold hash() here.
local hash = require "src.core.hash"
local rng = require "src.core.rng"
local data = require "src.core.data"

local QUIRKS = data.QUIRKS
local M = {}

local function sortElements(a, b)
    if a <= b then return a, b else return b, a end
end

-- 5.2 Generation order (must never change):
--   seed   = hash(key)
--   r      = rng(seed)
--   r1     = r()                                   -- power jitter
--   r2     = r()                                   -- quirk pick
--   power  = floor(compound.power * (0.9 + r1 * 0.2) + 0.5)
--   quirk  = QUIRKS[ floor(r2 * 5) + 1 ]
function M.makeSkill(elemA, elemB, shape, playerName)
    playerName = playerName or ""
    local sa, sb = sortElements(elemA, elemB)
    local key = playerName .. sa .. "+" .. sb .. "|" .. shape

    local seed = hash.hash(key)
    local r = rng.new(seed)
    local r1 = r()
    local r2 = r()

    local compound = data.COMPOUNDS[sa .. "+" .. sb]
    local shapeData = data.SHAPES[shape]

    local power = math.floor(compound.power * (0.9 + r1 * 0.2) + 0.5)
    local quirk_index = math.floor(r2 * 5) + 1
    local quirk = QUIRKS[quirk_index]

    -- Skill color = average of the two element colors (4.1)
    local ca = data.ELEMENTS[sa]
    local cb = data.ELEMENTS[sb]
    local color = {
        r = (ca.r + cb.r) / 2,
        g = (ca.g + cb.g) / 2,
        b = (ca.b + cb.b) / 2,
    }

    return {
        key = key,
        compound = compound.name,
        shape = shapeData.name,
        shape_key = shape,
        elements = { sa, sb },
        power = power,
        quirk = quirk,
        quirk_id = (data.QUIRK_IDS and data.QUIRK_IDS[quirk_index]) or nil,
        color = color,
        cooldown = shapeData.cooldown,
        radius = shapeData.radius,
        duration = shapeData.duration,
        statuses = compound.statuses or {},
    }
end

return M
