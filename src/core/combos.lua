-- /src/core/combos.lua
-- Panel text for the COMBOS screen. Pure: no gui.* or go.* so the smoke harness can
-- check the exact string the HUD draws. The body lists every COMBO_DATA entry as
-- one line, "NAME: short text" (the `short` field, not the long description).
local data = require "src.core.data"
local M = {}

-- Build the credits-panel body: one line per entry, "NAME: short".
-- Ten lines total. Fit is UNVERIFIED: the panel cannot be rendered headlessly.
function M.panel_text()
    local lines = {}
    for _, c in ipairs(data.COMBO_DATA) do
        lines[#lines + 1] = c.name .. ": " .. c.short
    end
    return table.concat(lines, "\n")
end

return M
