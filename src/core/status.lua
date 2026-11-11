-- /src/core/status.lua
-- Status effect data and application. See MASTER_PROMPT section 4.4.
-- Pure logic: status definitions, application, expiry, and per-enemy state.
-- NOTE: Defold uses LuaJIT (Lua 5.1) -> no `goto`, no `::labels::`.
local M = {}

-- 4.4 Status effect definitions
M.STATUS_DATA = {
    burn      = { duration = 3.0,  dps = 3,          color = { r = 1.0, g = 0.4, b = 0.0 } },
    slow      = { duration = 2.0,  speed_mul = 0.5,  color = { r = 0.2, g = 0.4, b = 1.0 } },
    stun      = { duration = 1.2,  immobilize = true, color = { r = 1.0, g = 1.0, b = 0.0 } },
    root      = { duration = 2.0,  root = true,      color = { r = 0.6, g = 0.2, b = 0.8 } },
    blind     = { duration = 2.0,  wander = true,    color = { r = 0.5, g = 0.5, b = 0.5 } },
    confuse   = { duration = 3.0,  miss_chance = 0.5, color = { r = 0.8, g = 0.2, b = 0.8 } },
    push      = { duration = 0.25, knockback = 260,  color = { r = 0.9, g = 0.9, b = 0.2 } },
    pull      = { duration = 0.25, knockback = 260, toward = true, color = { r = 0.2, g = 0.9, b = 0.9 } },
    hide_self = { duration = 2.0,  on_player = true, color = { r = 0.4, g = 0.4, b = 0.4 } },
    spread    = { duration = 3.0,  color = { r = 1.0, g = 0.6, b = 0.2 } }, -- Ember; handled by cone/cast logic
}

-- Apply a list of statuses to a target.
-- Unknown names are ignored (e.g. "spread" has no per-enemy effect yet).
-- burn refreshes its timer rather than stacking.
-- `duration_mul` (optional, default 1) scales every applied duration, e.g. Ancient Catalyst.
function M.apply(target, status_names, now, duration_mul)
    if status_names == nil then return end
    if target.statuses == nil then target.statuses = {} end
    local mul = duration_mul or 1

    for _, name in ipairs(status_names) do
        local def = M.STATUS_DATA[name]
        if def then
            -- One entry per status name: a repeated hit refreshes the timer instead of
            -- creating a second timer/stack.
            target.statuses[name] = { expiry = def.duration * mul }
            if name == "burn" then
                target.burn_timer = 0
            end
        end
    end
end

-- Tick all statuses down by dt. Returns the list of names that expired this frame.
function M.update(target, dt)
    local expired = {}
    if target.statuses == nil then return expired end

    for name, st in pairs(target.statuses) do
        st.expiry = st.expiry - dt
        if st.expiry <= 0 then
            table.insert(expired, name)
            target.statuses[name] = nil
        end
    end

    return expired
end

function M.has(target, name)
    if target.statuses == nil then return false end
    return target.statuses[name] ~= nil
end

function M.def(name)
    return M.STATUS_DATA[name]
end

-- Damage to apply this burn tick (0 if not burning).
function M.burn_damage(target)
    if target.statuses and target.statuses.burn then
        return M.STATUS_DATA.burn.dps
    end
    return 0
end

return M
