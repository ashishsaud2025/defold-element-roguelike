-- /src/game/events.lua
-- Tiny synchronous event bus. Pure Lua 5.1 (no engine calls).
--
-- game.script registers listeners once in init(); later phases (audio, reactions,
-- juice) hook the same names:
--   "cast"         { self, skill, slot, is_repeat, x, y }
--   "hit"          { self, enemy, damage, statuses, src, died }
--   "status"       { self, enemy, name, x, y, skill }
--   "quirk"        { self, quirk, raw, skill, x, y, is_repeat }
--   "kill"         { self, enemy, x, y, color }
--   "player_hit"   { self, x, y }
--   "dash"         { self, x, y }
--   "room_clear"   { self, room, boss }
--   "enemy_spawn"  { self, enemy }
--
-- Listeners run in registration order. There is no pcall: a broken listener is a
-- real bug and must surface in the smoke test, not be silently swallowed.
local M = {}

local handlers = {}

function M.on(name, fn)
    local list = handlers[name]
    if not list then
        list = {}
        handlers[name] = list
    end
    table.insert(list, fn)
    return fn
end

function M.off(name, fn)
    local list = handlers[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == fn then table.remove(list, i) end
    end
end

-- Remove all listeners for one event, or every listener when name is nil.
-- Called once at the start of init so a hot reload cannot double-register.
function M.clear(name)
    if name == nil then
        handlers = {}
    else
        handlers[name] = nil
    end
end

function M.emit(name, ctx)
    local list = handlers[name]
    if not list then return end
    for i = 1, #list do
        list[i](ctx)
    end
end

function M.count(name)
    local list = handlers[name]
    return list and #list or 0
end

return M
