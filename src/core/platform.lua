-- /src/core/platform.lua
-- Platform capability detection. Pure functions, no engine calls at load time, so the
-- headless harness can test the rule directly instead of re-implementing it.
--
-- Why this is a module: the first version of this check lived inline in main/game.script as
-- `local TOUCH_ENABLED = ...` ~1200 lines BELOW init(). A Lua local is not in scope for a
-- function body compiled earlier, so init() read a global that was never assigned (nil) and
-- every Android build shipped with self.touch_enabled == nil: no virtual stick, no cast
-- buttons, and the multi-touch machine inert. Same class as AGENTS.md #76.
local M = {}

-- Values returned by sys.get_sys_info().system_name on the touch platforms we ship.
function M.is_touch_device(system_name)
    return system_name == "Android" or system_name == "iOS"
end

-- `tuning` is data.TUNING. FORCE_TOUCH exists so an HTML5 build can be driven from a
-- desktop browser's device-emulation mode (real touch events, real engine) instead of
-- guessing on a phone. Shipped value is false.
function M.detect(tuning)
    if tuning and tuning.FORCE_TOUCH then return true end
    if sys and sys.get_sys_info then
        local info = sys.get_sys_info()
        return M.is_touch_device(info and info.system_name)
    end
    return false
end

return M
