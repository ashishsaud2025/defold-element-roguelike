-- /src/game/combat.lua
-- Projectiles and all shape deliveries. See MASTER_PROMPT sections 4.3, 4.4.
-- Pure logic: detects hits, returns hit events. Game script applies damage/status/visuals.
local status = require "src.core.status"

local M = {}

local ENEMY_RADIUS = 12

-- Apply flat damage to an enemy. Returns true if this hit killed it.
-- Safe to call on an already-dead enemy (returns false, no change).
-- Immortal enemies (training dummies) keep flashing but never lose HP.
function M.apply_damage(enemy, amount)
    if not enemy or not enemy.alive then return false end
    if enemy.immortal then
        enemy.flash_timer = 0.2
        return false
    end
    enemy.hp = enemy.hp - amount
    enemy.flash_timer = 0.2
    if enemy.hp <= 0 then
        enemy.hp = 0
        enemy.alive = false
        return true
    end
    return false
end


-- ===== Projectile (Bolt) =====
function M.new_bolt(source_x, source_y, target_x, target_y, power, speed)
    local dx = target_x - source_x
    local dy = target_y - source_y
    local dist = math.sqrt(dx * dx + dy * dy)
    local vx, vy
    if dist > 0 then
        vx = dx / dist * speed
        vy = dy / dist * speed
    else
        vx, vy = 0, 0
    end
    return {
        kind = "bolt",
        x = source_x, y = source_y,
        vx = vx, vy = vy,
        power = power,
        radius = 8,
        alive = true,
        ttl = 5.0,
        hit = false,
    }
end

function M.update_bolt(p, dt)
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.ttl = p.ttl - dt
    return p.ttl > 0 and not p.hit
end

function M.bolt_hits(p, ex, ey)
    local dx = p.x - ex
    local dy = p.y - ey
    local dist = math.sqrt(dx * dx + dy * dy)
    return dist < (p.radius + ENEMY_RADIUS)
end

-- ===== Puddle (Pool) =====
-- The status list is COPIED: a puddle can gain/lose statuses at runtime (Burning Mud),
-- and must never mutate the generated skill's status table.
function M.new_puddle(x, y, radius, duration, power, statuses)
    local st = {}
    for i, name in ipairs(statuses or {}) do st[i] = name end
    return {
        kind = "puddle",
        x = x, y = y, radius = radius,
        duration = duration,
        tick_timer = 0,
        tick_interval = 0.5,
        power = power,
        statuses = st,
        alive = true,
    }
end

-- Returns list of hit events: { enemy, damage, statuses }
function M.update_puddle(p, dt, enemies)
    p.duration = p.duration - dt
    p.tick_timer = p.tick_timer + dt
    local hits = {}

    if p.tick_timer >= p.tick_interval then
        p.tick_timer = p.tick_timer - p.tick_interval
        for _, e in ipairs(enemies) do
            if e.alive and M.puddle_contains(p, e.x, e.y) then
                table.insert(hits, { enemy = e, damage = p.power / 2, statuses = p.statuses })
            end
        end
    end

    if p.duration <= 0 then
        p.alive = false
    end
    return hits
end

function M.puddle_contains(p, ex, ey)
    local dx = p.x - ex
    local dy = p.y - ey
    return math.sqrt(dx * dx + dy * dy) < (p.radius + ENEMY_RADIUS)
end

-- ===== Orbit =====
function M.new_orbit(player_x, player_y, orbit_radius, num_orbs, duration, power, statuses)
    local orbs = {}
    for i = 1, num_orbs do
        local angle = (i - 1) * (2 * math.pi / num_orbs)
        table.insert(orbs, {
            angle = angle,
            x = player_x + math.cos(angle) * orbit_radius,
            y = player_y + math.sin(angle) * orbit_radius,
            hit_cooldown = 0,
        })
    end
    return {
        kind = "orbit",
        orbs = orbs,
        orbit_radius = orbit_radius,
        player_x = player_x,
        player_y = player_y,
        duration = duration,
        power = power,
        statuses = statuses,
        alive = true,
        rev_per_sec = 1.5,
        -- per-enemy hit cooldown (spec 4.3): any orb hitting that enemy resets it
        enemy_cooldowns = {},
    }
end

-- Returns list of hit events
function M.update_orbit(o, dt, player_x, player_y, enemies)
    o.duration = o.duration - dt
    o.player_x = player_x
    o.player_y = player_y

    -- Tick per-enemy cooldowns
    for e, t in pairs(o.enemy_cooldowns) do
        t = t - dt
        if t <= 0 then
            o.enemy_cooldowns[e] = nil
        else
            o.enemy_cooldowns[e] = t
        end
    end

    local angle_delta = dt * o.rev_per_sec * 2 * math.pi
    for _, orb in ipairs(o.orbs) do
        orb.angle = orb.angle + angle_delta
        orb.x = player_x + math.cos(orb.angle) * o.orbit_radius
        orb.y = player_y + math.sin(orb.angle) * o.orbit_radius
    end

    local hits = {}
    for _, orb in ipairs(o.orbs) do
        for _, e in ipairs(enemies) do
            if e.alive and (o.enemy_cooldowns[e] == nil) then
                local dx = orb.x - e.x
                local dy = orb.y - e.y
                local dist = math.sqrt(dx * dx + dy * dy)
                if dist < (14 + e.radius) then
                    table.insert(hits, { enemy = e, damage = o.power, statuses = o.statuses })
                    o.enemy_cooldowns[e] = 0.5
                    break
                end
            end
        end
    end

    if o.duration <= 0 then
        o.alive = false
    end
    return hits
end

-- ===== Cone (Spray) =====
function M.new_cone(x, y, angle, range, arc_degrees, power, statuses)
    return {
        kind = "cone",
        x = x, y = y, angle = angle, range = range,
        arc_degrees = arc_degrees,
        power = power,
        statuses = statuses,
        duration = 0.3,
        alive = true,
        hit_enemies = {},
    }
end

-- Returns list of hit events (instant, called once on cast)
function M.cone_hits(c, enemies)
    local hits = {}
    local half_arc = math.rad(c.arc_degrees / 2)
    for _, e in ipairs(enemies) do
        if e.alive and not c.hit_enemies[e] then
            local dx = e.x - c.x
            local dy = e.y - c.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < c.range then
                local to_angle = math.atan2(dy, dx)
                local diff = to_angle - c.angle
                while diff > math.pi do diff = diff - 2 * math.pi end
                while diff < -math.pi do diff = diff + 2 * math.pi end
                diff = math.abs(diff)
                if diff < half_arc then
                    table.insert(hits, { enemy = e, damage = c.power, statuses = c.statuses })
                    c.hit_enemies[e] = true
                end
            end
        end
    end
    c.duration = c.duration - 0.016
    if c.duration <= 0 then
        c.alive = false
    end
    return hits
end

-- ===== Burst (Nova) =====
function M.new_burst(x, y, radius, power, statuses)
    return {
        kind = "burst",
        x = x, y = y, radius = radius,
        power = power,
        statuses = statuses,
        duration = 0.3,
        alive = true,
        hit_enemies = {},
    }
end

-- Returns list of hit events (instant, called once on cast)
function M.burst_hits(b, enemies)
    local hits = {}
    for _, e in ipairs(enemies) do
        if e.alive and not b.hit_enemies[e] then
            local dx = e.x - b.x
            local dy = e.y - b.y
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist < (b.radius + e.radius) then
                table.insert(hits, { enemy = e, damage = b.power, statuses = b.statuses })
                b.hit_enemies[e] = true
            end
        end
    end
    b.duration = b.duration - 0.016
    if b.duration <= 0 then
        b.alive = false
    end
    return hits
end

-- ===== Knockback helpers =====
-- Apply instant knockback impulse to an enemy. Returns vx, vy to add to enemy velocity.
function M.knockback(ex, ey, sx, sy, strength, toward)
    local dx = ex - sx
    local dy = ey - sy
    local dist = math.sqrt(dx * dx + dy * dy)
    if dist == 0 then
        dx, dy = 1, 0
        dist = 1
    end
    if toward then
        dx, dy = -dx, -dy
    end
    return dx / dist * strength, dy / dist * strength
end

return M
