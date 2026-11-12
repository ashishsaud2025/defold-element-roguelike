-- /src/game/rewards.lua
-- Reward-screen offer (Relic v2, Phase D). Pure logic, no go.* calls, so the
-- smoke harness can drive it headlessly. Lua 5.1 only (AGENTS #12).
--
-- Offer schedule: reward screens AFTER rooms 3, 6 and 9 show exactly ONE relic
-- card — one unowned relic, chosen via rng_draw (math.random in game) — plus two
-- normal (element/shape) cards. All other reward screens show no relic. If no
-- unowned relic remains, the screen is normal. Never more than one relic per
-- screen; never an owned relic. Deterministic for a seeded rng_draw.
--
-- Note: room 9 in the current build is the boss room and ends in WIN, so the
-- room-9 milestone cannot be reached yet; the function itself is schedule-exact.
local relics = require "src.core.relics"
local M = {}

local ELEMENT_ORDER = { "fire", "water", "wind", "earth" }
local SHAPE_ORDER = { "projectile", "puddle", "orbit", "cone", "burst" }
M.MILESTONES = { [3] = true, [6] = true, [9] = true }

local function normal_pool()
    local pool = {}
    for _, el in ipairs(ELEMENT_ORDER) do pool[#pool + 1] = { kind = "element", id = el } end
    for _, sh in ipairs(SHAPE_ORDER) do pool[#pool + 1] = { kind = "shape", id = sh } end
    return pool
end

-- Build the reward options for a reward screen.
--   room_index: the room that was just cleared (the caller advances afterwards)
--   owned:      self.relics
--   rng_draw:   function() -> number in [0, 1)   (math.random in game)
-- Returns a list of 3 option tables; a relic option carries name/desc/icon.
function M.offer(room_index, owned, rng_draw)
    local draw = rng_draw or math.random
    local opts = {}

    if M.MILESTONES[room_index] then
        local unowned = {}
        for _, id in ipairs(relics.ORDER) do
            if not relics.has(owned, id) then unowned[#unowned + 1] = id end
        end
        if #unowned > 0 then
            local pick = unowned[math.floor(draw() * #unowned) + 1]
            local def = relics.DEFS[pick]
            opts[#opts + 1] = { kind = "relic", id = pick, name = def.name, desc = def.desc, icon = def.icon }
        end
    end

    local pool = normal_pool()
    for i = #pool, 2, -1 do
        local j = math.floor(draw() * i) + 1
        pool[i], pool[j] = pool[j], pool[i]
    end
    for _, p in ipairs(pool) do
        if #opts >= 3 then break end
        local seen = false
        for _, o in ipairs(opts) do
            if o.kind == p.kind and o.id == p.id then seen = true break end
        end
        if not seen then opts[#opts + 1] = p end
    end
    return opts
end

return M
