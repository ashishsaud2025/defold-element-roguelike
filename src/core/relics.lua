-- /src/core/relics.lua
-- Phase 4: four small run-level relics. Pure data + effect helpers.
-- Relics are passive player/run state: they never change the recipe key and never
-- write into generated skill data, so skill generation stays deterministic.
local M = {}

-- Stable ids, display order for the reward pool.
M.ORDER = { "inferno_heart", "echoing_crystal", "ancient_catalyst", "orbital_crown" }

M.DEFS = {
    inferno_heart = {
        name = "Inferno Heart",
        desc = "Fire spells +15% power",
        power_mul = 1.15,
    },
    echoing_crystal = {
        name = "Echoing Crystal",
        desc = "Every 5th cast echoes at 50%",
        every = 5,
        echo_strength = 0.50,
        delay = 0.25,
    },
    ancient_catalyst = {
        name = "Ancient Catalyst",
        desc = "Statuses last 20% longer",
        duration_mul = 1.20,
    },
    orbital_crown = {
        name = "Orbital Crown",
        desc = "Orbit spells gain +1 orb",
        extra_orbs = 1,
    },
}

function M.has(owned, id)
    return owned ~= nil and owned[id] == true
end

-- Power multiplier for a generated skill's elements (Inferno Heart: Fire only).
function M.power_mul(owned, elements)
    if not M.has(owned, "inferno_heart") then return 1 end
    for _, el in ipairs(elements or {}) do
        if el == "fire" then return M.DEFS.inferno_heart.power_mul end
    end
    return 1
end

-- Status duration multiplier (Ancient Catalyst).
function M.status_duration_mul(owned)
    if M.has(owned, "ancient_catalyst") then return M.DEFS.ancient_catalyst.duration_mul end
    return 1
end

-- Extra orbiting particles (Orbital Crown).
function M.orb_extra(owned)
    if M.has(owned, "orbital_crown") then return M.DEFS.orbital_crown.extra_orbs end
    return 0
end

-- Echo strength for the Nth successful player cast, or nil when no echo happens.
-- Echoes themselves are never counted as casts by the caller, so this cannot chain.
function M.echo_strength(owned, cast_count)
    if not M.has(owned, "echoing_crystal") then return nil end
    local d = M.DEFS.echoing_crystal
    if cast_count > 0 and cast_count % d.every == 0 then
        return d.echo_strength
    end
    return nil
end

return M
