-- /src/core/combos.lua
-- Panel text for the COMBOS screen. Pure: no gui.* or go.* so the smoke harness can
-- check the exact string the HUD draws. Descriptions come from data.COMBO_DATA verbatim;
-- only line wrapping is applied here (no word ever changes).
local data = require "src.core.data"
local M = {}

local WRAP = 58

local function wrap_line(s)
    local out, cur = {}, ""
    for word in s:gmatch("%S+") do
        if #cur == 0 then
            cur = word
        elseif #cur + #word + 1 <= WRAP then
            cur = cur .. " " .. word
        else
            out[#out + 1] = cur
            cur = word
        end
    end
    if #cur > 0 then out[#out + 1] = cur end
    return out
end

-- Build the credits-panel body: NAME line, description lines (wrapped, never reworded),
-- one blank line between entries.
function M.panel_text()
    local lines = {}
    for _, c in ipairs(data.COMBO_DATA) do
        lines[#lines + 1] = c.name
        for _, line in ipairs(wrap_line(c.description)) do
            lines[#lines + 1] = line
        end
        lines[#lines + 1] = ""
    end
    return table.concat(lines, "\n")
end

return M
