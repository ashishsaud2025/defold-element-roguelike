-- /src/game/player.lua
-- Player state: HP, invulnerability frames. See MASTER_PROMPT section 3 (locked).
local M = {}

function M.new()
    return {
        hp = 100,
        max_hp = 100,
        invuln = 0,            -- seconds remaining of invulnerability
        alive = true,
        radius = 12,           -- player collision radius (px)
    }
end

-- Call when player takes damage.
-- Returns died (true if HP hit 0) and applied (true if the hit actually landed).
function M.take_damage(player, amount)
    if player.invuln > 0 then
        return false, false
    end
    player.hp = player.hp - amount
    if player.hp <= 0 then
        player.hp = 0
        player.alive = false
        return true, true
    end
    player.invuln = 0.6        -- 0.6 s invulnerability after a hit
    return false, true
end

function M.update_invuln(player, dt)
    if player.invuln > 0 then
        player.invuln = player.invuln - dt
        if player.invuln < 0 then player.invuln = 0 end
    end
end

return M
