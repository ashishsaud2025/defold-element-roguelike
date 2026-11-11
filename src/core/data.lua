-- /src/core/data.lua
-- All tuning numbers and static game data. See MASTER_PROMPT sections 4 and 7.
local M = {}

-- 4.1 Elements and colors
M.ELEMENTS = {
    fire   = { r = 1.00, g = 0.30, b = 0.15 },
    water  = { r = 0.20, g = 0.50, b = 1.00 },
    wind   = { r = 0.85, g = 0.95, b = 0.90 },
    earth  = { r = 0.65, g = 0.45, b = 0.20 },
}

-- 4.2 Compounds (key = two element names sorted alphabetically, joined by "+")
M.COMPOUNDS = {
    ["fire+fire"]   = { name = "Inferno",   power = 14, statuses = { "burn" } },
    ["water+water"] = { name = "Tide",      power = 6,  statuses = { "pull", "slow" } },
    ["wind+wind"]   = { name = "Gale",      power = 8,  statuses = { "push" } },
    ["earth+earth"] = { name = "Quake",     power = 12, statuses = { "stun" } },
    ["fire+water"]  = { name = "Steam",     power = 7,  statuses = { "push", "blind" } },
    ["fire+wind"]   = { name = "Ember",     power = 8,  statuses = { "burn", "spread" } },
    ["earth+fire"]  = { name = "Magma",     power = 9,  statuses = { "burn", "slow" } },
    ["water+wind"]  = { name = "Mist",      power = 3,  statuses = { "blind", "hide_self" } },
    ["earth+water"] = { name = "Mud",       power = 4,  statuses = { "root" } },
    ["earth+wind"]  = { name = "Dust",      power = 5,  statuses = { "confuse" } },
}

-- 4.3 Shapes
M.SHAPES = {
    projectile = { name = "Bolt",   cooldown = 0.6, radius = 10, duration = 0 },
    puddle     = { name = "Pool",   cooldown = 4.0, radius = 60, duration = 5 },
    orbit      = { name = "Orbit",  cooldown = 5.0, radius = 14, duration = 6 },
    cone       = { name = "Spray",  cooldown = 1.5, radius = 90, duration = 0.3 },
    burst      = { name = "Nova",   cooldown = 2.5, radius = 70, duration = 0 },
}

-- 4.5 Quirks
M.QUIRKS = { "splits in two", "leaves a trail", "repeats once", "bigger but slower", "costs 5% health" }

-- 3. Locked tuning numbers (all in one place)
M.TUNING = {
    DEBUG = true,               -- M3 debug key row (1-5 shape, Q/E compound). Turn off for release.
    USE_PLAYER_NAME = false,
    PLAYER_HP = 100,
    PLAYER_SPEED = 220,
    INVULN_TIME = 0.6,
    ARENA_W = 960,
    ARENA_H = 640,
    ARENA_MARGIN = 20,
    ROOM_COUNT = 8,
    DASH_SPEED = 620,
    DASH_TIME = 0.16,
    DASH_COOLDOWN = 1.0,
    HEAL_ON_CLEAR = 25,
}

-- 8.3a Art ids (animation names in shapes.atlas). Tinted at runtime.
-- Art ids come from the manifest (src/core/art.lua). Kept here so existing code can keep
-- using data.ART.particle.* / data.ART.elementIcon.
local art = require "src.core.art"
M.ART = {
    elementIcon = art.ELEMENT_ICONS,
    particle = {
        spark = art.FX.spark, star = art.FX.star, flare = art.FX.flare,
        magic = art.FX.magic, twirl = art.FX.twirl, smoke = art.FX.smoke,
        flame = art.FX.flame, scorch = art.FX.scorch, circle = art.FX.circle,
        trace = art.FX.trace,
    },
    projectileHead = art.FX.flare,
    burstFlash = art.FX.star,
    trailPuff = art.FX.smoke,
}

return M
