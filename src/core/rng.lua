-- /src/core/rng.lua  (xorshift32, returns floats in [0, 1))
-- Verified against LuaJIT 2.1. See MASTER_PROMPT section 5.2.
local bit = require "bit"
local M = {}
local TWO32 = 4294967296

function M.new(seed)
    local x = bit.tobit(seed)
    if x == 0 then x = bit.tobit(0x9E3779B9) end
    return function()
        x = bit.bxor(x, bit.lshift(x, 13))
        x = bit.bxor(x, bit.rshift(x, 17))
        x = bit.bxor(x, bit.lshift(x, 5))
        return (x % TWO32) / TWO32
    end
end

return M
