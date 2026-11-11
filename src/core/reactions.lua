-- /src/core/reactions.lua
-- Elemental reactions: data-driven interactions between statuses and incoming elements.
-- Pure logic: no engine calls. game.script applies results through apply_reaction.
--
-- reactions.check(enemy, skill) -> list of reactions that trigger.
-- Each enemy has per-reaction cooldowns (enemy.reaction_cd[rx.id] = remaining).
local M = {}

M.REACTIONS = {
    {
        id = "steam_burst",
        name = "Steam Burst",
        needs = { "burn" },
        element = "water",
        consume = { "burn" },
        effect = "aoe",
        radius = 60,
        damage_mul = 0.6,
        min_damage = 4,
        apply = { "blind" },
        apply_time = 1.0,
        sound = "rx_steam",
        fx_family = "steam",
    },
    {
        id = "shatter",
        name = "Shatter",
        needs = { "stun", "root" },
        element = "earth",
        consume = { "stun", "root" },
        effect = "bonus",
        bonus_mul = 0.75,
        sound = "rx_shatter",
        fx_family = "earth",
    },
    {
        id = "flare_up",
        name = "Flare-up",
        needs = { "burn" },
        element = "wind",
        consume = {},
        effect = "flare",
        burn_mul = 2.0,
        spread_radius = 60,
        duration = 3.0,
        sound = "rx_flare",
        fx_family = "fire",
    },
    {
        id = "bog",
        name = "Bog",
        needs = { "slow" },
        element = "earth",
        consume = { "slow" },
        effect = "convert",
        convert_to = "root",
        convert_duration = 2.0,
        sound = "rx_bog",
        fx_family = "earth",
    },
    {
        id = "whirl",
        name = "Whirl",
        needs = { "blind" },
        element = "wind",
        consume = { "blind" },
        effect = "knockback",
        knockback_dist = 140,
        apply = { "confuse" },
        apply_duration = 2.0,
        sound = "rx_whirl",
        fx_family = "wind",
    },
}

-- Helper: does enemy have ANY of the needed statuses?
local function has_any(enemy, names)
    if not enemy or not enemy.statuses then return false end
    for _, name in ipairs(names) do
        if enemy.statuses[name] then return true end
    end
    return false
end

-- Helper: does skill contain the required element?
local function skill_has_element(skill, elem)
    if not skill or not skill.elements then return false end
    for _, e in ipairs(skill.elements) do
        if e == elem then return true end
    end
    return false
end

-- Helper: is a reaction on cooldown for this enemy?
local function on_cooldown(enemy, rx_id)
    if not enemy.reaction_cd then return false end
    return (enemy.reaction_cd[rx_id] or 0) > 0
end

-- M.check(enemy, skill) -> list of reactions that trigger.
-- Evaluated before the new hit applies its own statuses.
-- Per-enemy cooldown of 0.5s per reaction.
-- At most 3 reactions per call.
-- AoE reactions cannot chain (handled by caller via frame flag).
function M.check(enemy, skill)
    local result = {}
    if not enemy or not skill then return result end

    enemy.reaction_cd = enemy.reaction_cd or {}

    for _, rx in ipairs(M.REACTIONS) do
        if #result >= 3 then break end
        if on_cooldown(enemy, rx.id) then
            -- skip, still on cooldown
        elseif has_any(enemy, rx.needs) and skill_has_element(skill, rx.element) then
            table.insert(result, rx)
            enemy.reaction_cd[rx.id] = 0.5
        end
    end

    return result
end

-- Tick reaction cooldowns down by dt.
function M.update(enemy, dt)
    if not enemy or not enemy.reaction_cd then return end
    for id, cd in pairs(enemy.reaction_cd) do
        enemy.reaction_cd[id] = cd - dt
        if enemy.reaction_cd[id] <= 0 then
            enemy.reaction_cd[id] = nil
        end
    end
end

-- Consume statuses from enemy (remove them after reaction).
function M.consume(enemy, rx)
    if not enemy or not rx or not rx.consume then return end
    if not enemy.statuses then return end
    for _, name in ipairs(rx.consume) do
        enemy.statuses[name] = nil
        if name == "burn" then enemy.burn_timer = 0 end
    end
end

-- Find a reaction by id.
function M.by_id(id)
    for _, rx in ipairs(M.REACTIONS) do
        if rx.id == id then return rx end
    end
    return nil
end

return M
