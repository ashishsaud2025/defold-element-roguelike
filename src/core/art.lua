-- /src/core/art.lua
-- Art manifest: which atlas animation draws what.
--
-- TILES   : how the level is drawn. The defaults are the generated placeholder tiles
--           (48px, grey, tinted by the room palette). To use a real pack set `scale`
--           (16px art -> 3) and `tint = false`, and point `anim` at your image's name.
-- ACTORS  : optional sprites for the player and enemies. Only used when ENABLED = true,
--           otherwise the game draws tinted circles/squares.
--
-- An atlas animation is named after its image file (square.png -> "square").
-- Add images to the atlas with:  python tools/add_to_atlas.py <png files...>
local M = {}

M.ENABLED = true   -- actor sprites exist in the atlas; false = tinted shapes

-- Animated spell effects (flipbooks from the downloaded packs, built by tools/build_fx_anim.py).
-- Set to false to compare against the old static-particle look; the game still runs without them.
M.ANIM_FX = true

M.TILES = {
    -- Kenney Tiny Dungeon (16 px art, tile cell is 48 px -> scale 3). Grey stone,
    -- so tint = true lets the per-room palette recolour it.
    floor_a   = { anim = "td_floor_a",   scale = 3, tint = true },
    floor_b   = { anim = "td_floor_b",   scale = 3, tint = true },
    wall_face = { anim = "td_wall_face", scale = 3, tint = true },
    wall_top  = { anim = "td_wall_top",  scale = 3, tint = true },
    pillar    = { anim = "td_pillar",    scale = 3, tint = true },
    torch     = { anim = "td_torch",     scale = 3, tint = false },   -- coloured art
    altar     = { anim = "altar",        scale = 1, tint = false },   -- Lantern Hall stations
    door      = { anim = "door",         scale = 1, tint = false },
    chest     = { anim = "chest",        scale = 1, tint = false },   -- boss-room reward
    bed       = { anim = "bed",          scale = 1, tint = false },   -- the sick wife
}

-- Player + enemies. Static 16 px sprites brought to life in code (src/game/anim.lua):
-- scale, a small visual y offset and rotation only, never collision or AI values.
-- `faces` is "right" for front-facing art; "left" flips the mirror direction.
M.ACTORS = {
    player   = { anim = "td_player",   scale = 3, faces = "right" },
    wisp     = { anim = "tc_wisp",     scale = 2, faces = "right" },
    slinger  = { anim = "tc_slinger",  scale = 2, faces = "right" },
    charger  = { anim = "tc_charger",  scale = 2, faces = "right" },
    brute    = { anim = "tc_brute",    scale = 3, faces = "right" },
    splitter = { anim = "tc_splitter", scale = 2, faces = "right" },
    dummy    = { anim = "target_dummy", scale = 3, faces = "right" },
    boss     = { anim = "tc_boss",     scale = 5, faces = "right" },
}

-- FX roles: which atlas animation is used for each effect. SPELL ART IS TINTED with the
-- skill's blended element colour, so these images must be WHITE / light grey with the
-- brightness in the alpha channel (see README section 13).
M.FX = {
    glow    = "glow",              -- soft orb, drawn additively: bolt glow, pool, orbit glow, torch light, motes
    core    = "circle",            -- solid disc, normal blend: bolt head, orbit orb, enemy bolts, placeholder player
    square  = "square",            -- solid square (wall accent lines)
    rune    = "icon_rune",         -- arena centre sigil
    spark   = "particle_spark", star  = "particle_star",  flare = "particle_flare",
    magic   = "particle_magic", twirl = "particle_twirl", smoke = "particle_smoke",
    flame   = "particle_flame", scorch = "particle_scorch", circle = "particle_circle",  -- circle = ring
    trace   = "particle_trace",
}

-- Per-element effect art (spec 6.3). Ids are atlas animations from assets/art/fx/.
-- Missing entries fall back to ELEMENT_FALLBACK. Element A is used for trails/rises,
-- element B for hits/spokes.
M.ELEMENT_FX = {
    fire  = { trail = "fx_flame", hit = "fx_scorch", rise = "fx_flame",  spoke = "fx_spark"  },
    water = { trail = "fx_drop",  hit = "fx_splash", rise = "fx_bubble", spoke = "fx_drop"   },
    wind  = { trail = "fx_streak",hit = "fx_swirl",  rise = "fx_swirl",  spoke = "fx_streak" },
    earth = { trail = "fx_debris",hit = "fx_scorch", rise = "fx_debris", spoke = "fx_debris" },
}

-- Generic fallback (kept in case an element gets removed from ELEMENT_FX or add a new element).
M.ELEMENT_FALLBACK = { trail = "glow", hit = "particle_star", rise = "glow", spoke = "particle_spark" }

-- HUD / card icons per element (white art, tinted with the element colour by the HUD).
M.ELEMENT_ICONS = { fire = "icon_fire", water = "icon_water", wind = "icon_wind", earth = "icon_earth" }

function M.actor(name)
    if not M.ENABLED then return nil end
    return M.ACTORS[name]
end

return M
