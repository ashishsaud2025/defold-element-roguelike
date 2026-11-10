-- /src/game/enemies.lua
-- Enemy types, spawning, and per-frame update. See MASTER_PROMPT section 7.
-- All logic is pure Lua (no go.* calls); returns data the game script applies to visuals.
local data = require "src.core.data"

local M = {}

-- 7. Enemy stats (HP, speed, behavior, contact damage)
M.ENEMY_TYPES = {
    wisp     = { hp = 20,  speed = 90,  contact_damage = 8,  color = { r=0.78, g=0.64, b=0.95 }, shape = "circle", radius = 12 },
    slinger  = { hp = 15,  speed = 60,  contact_damage = 4,  color = { r=0.3, g=0.6, b=1.0 }, shape = "circle", radius = 12 },
    charger  = { hp = 25,  speed = 120, contact_damage = 12, color = { r=1.0, g=0.55, b=0.2 }, shape = "square", rot = 45, radius = 14 },
    brute    = { hp = 60,  speed = 40,  contact_damage = 15, color = { r=0.7, g=0.25, b=0.2 }, shape = "square", radius = 18 },
    splitter = { hp = 10,  speed = 100, contact_damage = 6,  color = { r=0.3, g=0.85, b=0.4 }, shape = "circle", radius = 12 },
    dummy    = { hp = 9999, speed = 0,  contact_damage = 0,  color = { r=0.85, g=0.85, b=0.9 }, shape = "square", radius = 16, immortal = true },
    boss     = { hp = 300, speed = 50,  contact_damage = 20, color = { r=0.7, g=0.3, b=0.9 }, shape = "circle", radius = 32 },
}


-- Spawn a wisp at a random point along the arena edge, chasing the player.
function M.spawn_wisp(player_pos, arena_w, arena_h)
    -- Pick a random edge
    local edge = math.random(4)
    local x, y
    if edge == 1 then        -- top
        x = math.random(0, arena_w); y = arena_h
    elseif edge == 2 then    -- right
        x = arena_w; y = math.random(0, arena_h)
    elseif edge == 3 then    -- bottom
        x = math.random(0, arena_w); y = 0
    else                     -- left
        x = 0; y = math.random(0, arena_h)
    end

    local enemy = {
        id = nil,
        x = x, y = y,
        hp = M.ENEMY_TYPES.wisp.hp,
        max_hp = M.ENEMY_TYPES.wisp.hp,
        speed = M.ENEMY_TYPES.wisp.speed,
        contact_damage = M.ENEMY_TYPES.wisp.contact_damage,
        radius = M.ENEMY_TYPES.wisp.radius,
        alive = true,
        type = "wisp",
    }
    return enemy
end

-- Generic spawn for any enemy type
function M.spawn(etype, player_pos, arena_w, arena_h)
    local t = M.ENEMY_TYPES[etype] or M.ENEMY_TYPES.wisp
    local edge = math.random(4)
    local x, y
    if edge == 1 then x = math.random(0, arena_w); y = arena_h
    elseif edge == 2 then x = arena_w; y = math.random(0, arena_h)
    elseif edge == 3 then x = math.random(0, arena_w); y = 0
    else x = 0; y = math.random(0, arena_h) end
    -- boss spawns at center-ish top
    if etype == "boss" then x = arena_w * 0.5; y = arena_h * 0.8 end
    local enemy = {
        id = nil,
        x = x, y = y,
        hp = t.hp, max_hp = t.hp,
        speed = t.speed,
        contact_damage = t.contact_damage,
        radius = t.radius,
        alive = true,
        type = etype,
        immortal = t.immortal == true,
        -- type-specific state
        shoot_timer = 2.0,
        charge_timer = 1.5,
        charging = false,
        charge_vx = 0, charge_vy = 0,
        charge_time = 0,
        pattern_timer = 3.0,
        pattern = 1,
        summon_timer = 4.0,
    }
    return enemy
end

-- Move one enemy toward the player (chase). Returns new x, y.
function M.update_wisp(enemy, player_x, player_y, dt)
    local dx = player_x - enemy.x
    local dy = player_y - enemy.y
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist > 0 then
        dx = dx / dist
        dy = dy / dist
        enemy.x = enemy.x + dx * enemy.speed * dt
        enemy.y = enemy.y + dy * enemy.speed * dt
    end
    return enemy.x, enemy.y
end

-- Circle-vs-circle contact check
function M.is_touching(enemy_x, enemy_y, enemy_radius, player_x, player_y, player_radius)
    local dx = enemy_x - player_x
    local dy = enemy_y - player_y
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist < (enemy_radius + player_radius)
end

return M
