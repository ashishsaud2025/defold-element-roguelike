-- /src/core/hash.lua
-- FNV-1a, 32-bit. Prime 16777619 = 2^24 + 2^8 + 2^7 + 2^4 + 2^1 + 2^0,
-- so h * prime = sum of shifted copies of h (mod 2^32).
-- Verified against LuaJIT 2.1. See MASTER_PROMPT section 5.3.
local bit = require "bit"
local M = {}
local TWO32 = 4294967296

function M.hash(s)
    local h = 2166136261
    for i = 1, #s do
        h = bit.bxor(h, s:byte(i))
        local t = bit.lshift(h, 24) % TWO32
                + bit.lshift(h, 8)  % TWO32
                + bit.lshift(h, 7)  % TWO32
                + bit.lshift(h, 4)  % TWO32
                + bit.lshift(h, 1)  % TWO32
                + (h % TWO32)
        h = t % TWO32
    end
    return h
end

return M
