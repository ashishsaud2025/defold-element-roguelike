-- /src/core/selfcheck.lua
-- Verifies hash, rng, and skillgen against the golden test vectors in
-- MASTER_PROMPT section 5.4. Called once from game.script init.
-- Prints "SELFCHECK OK" or "SELFCHECK FAIL: <details>".
local hash = require "src.core.hash"
local rng = require "src.core.rng"
local skillgen = require "src.core.skillgen"

local M = {}

function M.run()
    local failures = {}

    -- 5.4 hash golden vectors
    local hashChecks = {
        { s = "", expected = 2166136261 },
        { s = "a", expected = 3826002220 },
        { s = "fire+water|projectile", expected = 1682648556 },
        { s = "fire+fire|puddle", expected = 2074461886 },
        { s = "Ashfire+wind|burst", expected = 3898178612 },
    }

    for _, c in ipairs(hashChecks) do
        local got = hash.hash(c.s)
        if got ~= c.expected then
            table.insert(failures, "hash(" .. c.s .. ") = " .. got .. ", expected " .. c.expected)
        end
    end

    -- 5.4 rng golden vectors (r1/r2 rounded to 6 decimals)
    local rngChecks = {
        { key = "fire+water|projectile", r1 = 0.246629, r2 = 0.521085 },
        { key = "fire+fire|puddle", r1 = 0.676735, r2 = 0.771629 },
        { key = "Ashfire+wind|burst", r1 = 0.235052, r2 = 0.655529 },
    }

    for _, c in ipairs(rngChecks) do
        local r = rng.new(hash.hash(c.key))
        local r1 = r()
        local r2 = r()
        local r1r = math.floor(r1 * 1e6 + 0.5) / 1e6
        local r2r = math.floor(r2 * 1e6 + 0.5) / 1e6
        if r1r ~= c.r1 then
            table.insert(failures, "rng r1 for " .. c.key .. " = " .. r1r .. ", expected " .. c.r1)
        end
        if r2r ~= c.r2 then
            table.insert(failures, "rng r2 for " .. c.key .. " = " .. r2r .. ", expected " .. c.r2)
        end
    end

    -- 5.4 skillgen golden vectors
    -- "Ashfire+wind|burst" = playerName "Ash" + elements fire+wind + shape burst
    local skillChecks = {
        { key = "fire+water|projectile", elemA = "fire", elemB = "water", shape = "projectile", playerName = "", name = "Steam Bolt", power = 7, quirk = "repeats once" },
        { key = "fire+fire|puddle", elemA = "fire", elemB = "fire", shape = "puddle", playerName = "", name = "Inferno Pool", power = 14, quirk = "bigger but slower" },
        { key = "Ashfire+wind|burst", elemA = "fire", elemB = "wind", shape = "burst", playerName = "Ash", name = "Ember Nova", power = 8, quirk = "bigger but slower" },
    }

    for _, c in ipairs(skillChecks) do
        local s = skillgen.makeSkill(c.elemA, c.elemB, c.shape, c.playerName)
        local sname = s.compound .. " " .. s.shape
        if sname ~= c.name then
            table.insert(failures, "skill name for " .. c.key .. " = " .. sname .. ", expected " .. c.name)
        end
        if s.power ~= c.power then
            table.insert(failures, "skill power for " .. c.key .. " = " .. s.power .. ", expected " .. c.power)
        end
        if s.quirk ~= c.quirk then
            table.insert(failures, "skill quirk for " .. c.key .. " = " .. s.quirk .. ", expected " .. c.quirk)
        end
        -- 6.1: skills describe their elements (sorted) and their shape key
        local sa, sb = c.elemA, c.elemB
        if sa > sb then sa, sb = sb, sa end
        if s.elements == nil or s.elements[1] ~= sa or s.elements[2] ~= sb then
            table.insert(failures, "skill elements for " .. c.key .. " = "
                .. tostring(s.elements and (s.elements[1] .. "+" .. s.elements[2])) .. ", expected " .. sa .. "+" .. sb)
        end
        if s.shape_key ~= c.shape then
            table.insert(failures, "skill shape_key for " .. c.key .. " = " .. tostring(s.shape_key) .. ", expected " .. c.shape)
        end
    end

    if #failures == 0 then
        print("SELFCHECK OK")
        return true
    else
        print("SELFCHECK FAIL: " .. table.concat(failures, "; "))
        return false
    end
end

return M
