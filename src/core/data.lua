-- /src/core/data.lua
-- All tuning numbers and static game data. See MASTER_PROMPT sections 4 and 7.
local M = {}

-- 4.1 Elements and colors (+ role lines: pick tiles and element cards read these)
M.ELEMENTS = {
    fire   = { r = 1.00, g = 0.30, b = 0.15, role = "Fire burns: damage over time" },
    water  = { r = 0.20, g = 0.50, b = 1.00, role = "Water slows and pulls" },
    wind   = { r = 0.85, g = 0.95, b = 0.90, role = "Wind pushes and carries" },
    earth  = { r = 0.65, g = 0.45, b = 0.20, role = "Earth stuns and roots" },
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

-- 4.3 Shapes (+ blurb lines: shape cards read these)
M.SHAPES = {
    projectile = { name = "Bolt",   cooldown = 0.6, radius = 10, duration = 0, blurb = "Fast single target" },
    puddle     = { name = "Pool",   cooldown = 4.0, radius = 60, duration = 5, blurb = "Area denial over time" },
    orbit      = { name = "Orbit",  cooldown = 5.0, radius = 14, duration = 6, blurb = "Orbs circle you" },
    cone       = { name = "Spray",  cooldown = 1.5, radius = 90, duration = 0.3, blurb = "Cone in a line" },
    burst      = { name = "Nova",   cooldown = 2.5, radius = 70, duration = 0, blurb = "Explosion all around" },
}

-- 4.5/4.6 Quirk tuning (keyed by stable id).
-- Quirk IDENTITY (ids, display labels, short forms, descriptions, behaviour flags,
-- default order) lives in `src/core/quirks.lua`. Only the tuning numbers stay here.
-- The generated skill carries both `quirk` (display text, unchanged) and `quirk_id`.
M.QUIRK_DATA = {
    -- Splits in two: two instances, each at 60% strength so the total is not 2x.
    split_in_two  = { count = 2, strength = 0.60, angle_deg = 15, pool_offset = 0.60, pool_scale = 0.72 },
    -- Leaves a trail: short-lived secondary patches, capped so it can never stream forever.
    leaves_trail  = { patch_life = 0.9, patch_radius = 18, patch_power = 0.5, cap = 24,
                      bolt_interval = 0.14, orbit_interval = 0.5, pool_patches = 3 },
    -- Repeats once: one extra execution of the same cast, same aim/position.
    repeat_once   = { delay = 0.25 },
    -- Bigger but slower: size +30%, delivery speed -20% (player speed untouched).
    bigger_slower = { size_mul = 1.30, speed_mul = 0.80, puddle_tick_mul = 1.25 },
    -- Costs 5% health: paid once per successful player cast; must keep at least 1 HP.
    health_cost   = { hp_frac = 0.05, min_hp = 1, power_mul = 1.5 },
}

-- 4.6b Combos reference (Phase C): the single source for the COMBOS panel and every
-- interaction banner name. Names are upper case so the existing banner lines
-- (FIRE CYCLONE, BURNING MUD, DENSE CLOUD) match byte for byte.
-- Each entry carries `short` (one line) used by the Combos panel.
M.COMBO_DATA = {
    { id = "fire_cyclone",  name = "FIRE CYCLONE",
      short = "Wind makes a fire pool grow.",
      description = "Wind over a fire pool makes it grow into a cyclone. It shrinks back when the wind ends." },
    { id = "burning_mud",  name = "BURNING MUD",
      short = "Fire makes a mud pool burn.",
      description = "Fire over a Mud pool: it burns for 3 s, then reverts to mud." },
    { id = "dense_cloud",  name = "DENSE CLOUD",
      short = "Steam + Dust blinds and confuses.",
      description = "Steam meeting Dust makes a cloud that blinds and confuses." },
    { id = "pool_infusion", name = "POOL INFUSION",
      short = "Spells absorb a pool's effects.",
      description = "Bolt, Orbit, Spray and Nova can absorb an active Pool. The spell keeps its own effects and also applies the Pool's." },
    { id = "steam_vent",    name = "STEAM VENT",
      short = "Fire meets water: pool pushes and blinds.",
      description = "Fire meets water, or water meets fire: a pure pool pushes and blinds for 3 s." },
    { id = "molten_ground", name = "MOLTEN GROUND",
      short = "Fire meets earth: pool burns and slows.",
      description = "Fire meets earth, or earth meets fire: a pure pool burns and slows for 3 s." },
    { id = "firestorm",     name = "FIRESTORM",
      short = "Fire on a wind pool: it burns.",
      description = "Fire meets a gale-pure pool: the pool burns for 3 s." },
    { id = "squall",        name = "SQUALL",
      short = "Water meets wind: pool blinds.",
      description = "Water meets wind, or wind meets water: a pure pool blinds for 3 s." },
    { id = "quagmire",      name = "QUAGMIRE",
      short = "Water meets earth: pool roots.",
      description = "Water meets earth, or earth meets water: a pure pool roots for 3 s." },
    { id = "dust_devil",    name = "DUST DEVIL",
      short = "Earth meets wind: pool confuses.",
      description = "Earth meets wind, or wind meets earth: a pure pool confuses for 3 s." },
}
M.COMBO_BY_ID = {}
for _, c in ipairs(M.COMBO_DATA) do M.COMBO_BY_ID[c.id] = c end

-- 4.7 Environmental spell interactions (Phase 3)
M.INTERACT = {
    BURNING_MUD_TIME = 3.0,      -- how long a Mud pool stays Burning Mud
    BURNING_MUD_BURN = 2.0,      -- burn refresh applied to enemies in Burning Mud
    DENSE_CLOUD_TIME = 2.0,      -- Steam + Dust cloud lifetime
    DENSE_CLOUD_RADIUS = 80,
    DENSE_CLOUD_TICK = 0.5,
    CYCLONE_GROW = 26,           -- px/s while wind time is live
    CYCLONE_MAX_RADIUS = 110,    -- absolute cap
    CYCLONE_DECAY = 45,          -- px/s back to the pre-cyclone radius
    CYCLONE_BOLT_WIND_TIME = 1.0, -- seconds of wind a flying wind bolt provides per overlap tick
    INTERACTION_TICK = 0.15,     -- controlled update interval (never per frame)
    MAX_SPELL_AREAS = 40,
    MAX_CLOUDS = 6,
    INFUSE_DAMAGE_MUL = 1.25,   -- infused spell hit/tick damage multiplier (once, never stacks)
    INFUSE_GRACE = 1.0,         -- seconds a Bolt/Orbit orb stays infused after leaving a Pool
    REACTION_TIME = 3.0,        -- seconds a Pool carries the reaction statuses
}

-- 4.7b Pool reactions (Phase B): pair key (as in COMPOUNDS, sorted alphabetically joined
-- with "+") -> combo id. Only when the Pool is *pure* (elements[1] == elements[2]) and the
-- overlapping spell element differs. The fire-Pool + wind-spell cell is Fire Cyclone's;
-- the reaction code never takes it.
M.REACTIONS = {
    ["fire+water"]  = "steam_vent",
    ["earth+fire"]  = "molten_ground",
    ["fire+wind"]   = "firestorm",     -- only when the Pool is wind (fire-Pool cell = Fire Cyclone)
    ["water+wind"]  = "squall",
    ["earth+water"] = "quagmire",
    ["earth+wind"]  = "dust_devil",
}

-- 3. Locked tuning numbers (all in one place)
M.TUNING = {
    DEBUG = false,              -- release builds ship this off; the smoke harness forces it on for its own checks (tools/smoke_test.lua).
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
