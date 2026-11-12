-- /src/core/relics.lua
-- Phase 4: four small run-level relics. Pure data + effect helpers.
-- Relics are passive player/run state: they never change the recipe key and never
-- write into generated skill data, so skill generation stays deterministic.
local M = {}

-- Stable ids, display order for the reward pool.
M.ORDER = { "inferno_heart", "echoing_crystal", "ancient_catalyst", "orbital_crown" }

-- `icon` is an atlas image id from assets/art/shapes.atlas (no new art).
-- `trigger_text` is the D4 banner text; orbital_crown's is unused (it has no trigger).
M.DEFS = {
    inferno_heart = {
        name = "Inferno Heart",
        desc = "Fire spells +15% power",
        icon = "icon_fire",
        trigger_text = "INFERNO HEART +15%",
        power_mul = 1.15,
    },
    echoing_crystal = {
        name = "Echoing Crystal",
        desc = "Every 5th cast echoes at 50%",
        icon = "particle_circle",
        trigger_text = "ECHO",
        every = 5,
        echo_strength = 0.50,
        delay = 0.25,
    },
    ancient_catalyst = {
        name = "Ancient Catalyst",
        desc = "Statuses last 20% longer",
        icon = "icon_cauldron",
        trigger_text = "CATALYST +20%",
        duration_mul = 1.20,
    },
    orbital_crown = {
        name = "Orbital Crown",
        desc = "Orbit spells gain +1 orb",
        icon = "particle_twirl",
        trigger_text = "ORBITAL CROWN +1 ORB",
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

-- Echo pip state: (done, total) for the relic bar. done is in [0, total] and
-- wraps after `every` casts. Player casts only — callers must not count echoes
-- or repeats. Without the relic: (0, total).
function M.echo_progress(owned, cast_count)
    local every = M.DEFS.echoing_crystal.every
    if not M.has(owned, "echoing_crystal") then return 0, every end
    local done = (cast_count or 0) % every
    if cast_count and cast_count > 0 and done == 0 then done = every end
    return done, every
end

-- "Name — desc" single line for hover tooltips. Pure.
function M.describe(id)
    local def = M.DEFS[id]
    if not def then return tostring(id) end
    return def.name .. " — " .. def.desc
end

return M
