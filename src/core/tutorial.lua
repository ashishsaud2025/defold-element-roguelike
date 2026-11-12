-- /src/core/tutorial.lua
-- Panel text for the TUTORIAL screen. Pure: no gui.* or go.* so the smoke harness can
-- check the exact string the HUD draws. Built from data.ELEMENTS and the STATUS_DATA
-- tables, so the tutorial can never drift from the real numbers.
local data = require "src.core.data"
local status = require "src.core.status"
local M = {}

local ELEMENT_ORDER = { "fire", "water", "wind", "earth" }

function M.panel_text()
    local SD = status.STATUS_DATA
    local L = {}
    L[#L + 1] = "THE FOUR ELEMENTS"
    for _, el in ipairs(ELEMENT_ORDER) do
        local def = data.ELEMENTS[el]
        L[#L + 1] = string.format("%-6s  %s", el:upper(), def.role)
    end
    L[#L + 1] = ""
    L[#L + 1] = "STATUS EFFECTS"
    L[#L + 1] = string.format("BURN     %.1fs  damage every second", SD.burn.duration)
    L[#L + 1] = string.format("SLOW     %.1fs  enemy speed halved", SD.slow.duration)
    L[#L + 1] = string.format("STUN     %.1fs  frozen: cannot move or attack", SD.stun.duration)
    L[#L + 1] = string.format("ROOT     %.1fs  cannot move, can still attack", SD.root.duration)
    L[#L + 1] = string.format("PUSH     %.2fs  knocked away from the hit", SD.push.duration)
    L[#L + 1] = string.format("PULL     %.2fs  pulled toward you", SD.pull.duration)
    L[#L + 1] = string.format("BLIND    %.1fs  enemy wanders randomly", SD.blind.duration)
    L[#L + 1] = string.format("CONFUSED %.1fs  misses half its shots", SD.confuse.duration)
    L[#L + 1] = string.format("SPREAD   %.1fs  burn spreads to nearby enemies", SD.spread.duration)
    L[#L + 1] = ""
    L[#L + 1] = "COMBINED MAGIC"
    L[#L + 1] = "Every spell mixes TWO elements. Same pair = the"
    L[#L + 1] = "same status twice (fire+fire = Inferno, always"
    L[#L + 1] = "burns). The shape - BOLT, POOL, ORBIT, SPRAY or"
    L[#L + 1] = "NOVA - decides how the compound is delivered."
    return table.concat(L, "\n")
end

return M
