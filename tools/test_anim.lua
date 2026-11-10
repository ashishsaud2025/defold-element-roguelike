-- tools/test_anim.lua
-- Headless checks for src/game/anim.lua (run through tools/run_anim_test.py).
-- Returns { checks = n, failures = { ... } }. Lua 5.1 only.
local anim = dofile("src/game/anim.lua")

local failures = {}
local checks = 0

local function fail(msg)
    table.insert(failures, msg)
end

local function finite(v)
    return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function check_range(name, a)
    checks = checks + 1
    if not finite(a.sx) or a.sx < 0.5 or a.sx > 1.6 then fail(name .. ": sx out of range (" .. tostring(a.sx) .. ")") end
    checks = checks + 1
    if not finite(a.sy) or a.sy < 0.5 or a.sy > 1.6 then fail(name .. ": sy out of range (" .. tostring(a.sy) .. ")") end
    checks = checks + 1
    if not finite(a.rot) or a.rot < -0.36 or a.rot > 0.36 then fail(name .. ": rot out of range (" .. tostring(a.rot) .. ")") end
    checks = checks + 1
    if not finite(a.ox) or a.ox < -4.1 or a.ox > 4.1 then fail(name .. ": ox out of range (" .. tostring(a.ox) .. ")") end
    checks = checks + 1
    if not finite(a.oy) or a.oy < -4.1 or a.oy > 4.1 then fail(name .. ": oy out of range (" .. tostring(a.oy) .. ")") end
end

local function same(a, b)
    return a.sx == b.sx and a.sy == b.sy and a.rot == b.rot and a.ox == b.ox and a.oy == b.oy
end

-- 1. Every kind and every state combination stays inside the clamps for 10 s.
local kinds = { "wisp", "slinger", "charger", "brute", "splitter", "boss", "unknown" }
local states = {
    {},
    { moving = true },
    { charging = true },
    { windup = true },
    { stunned = true },
    { fire = true },
    { retreat = true },
    { fire = true, retreat = true, moving = true },
    { moving = true, charging = true, windup = true, stunned = true },
}
local t = 0
while t <= 10.0 do
    for _, kind in ipairs(kinds) do
        for _, s in ipairs(states) do
            check_range(kind .. "@" .. string.format("%.2f", t), anim.enemy(kind, s, t))
        end
    end
    for _, s in ipairs({ {}, { moving = true }, { dash = true, dx = 1, dy = 0 },
                         { dash = true, dx = 0, dy = -1 }, { dash = true, dx = 0, dy = 1 } }) do
        check_range("player@" .. string.format("%.2f", t), anim.player(s, t))
    end
    t = t + 0.05
end

-- 2. Missing / hostile state is tolerated.
check_range("enemy nil state", anim.enemy("wisp", nil, 1.0))
check_range("player nil state", anim.player(nil, 1.0))
check_range("player nil time", anim.player(nil, nil))
check_range("enemy nan time", anim.enemy("boss", { moving = true }, 0 / 0))

-- 3. Determinism: identical inputs give identical output.
checks = checks + 1
if not same(anim.enemy("charger", { moving = true }, 3.3), anim.enemy("charger", { moving = true }, 3.3)) then
    fail("enemy() is not deterministic")
end
checks = checks + 1
if not same(anim.player({ moving = true }, 2.2), anim.player({ moving = true }, 2.2)) then
    fail("player() is not deterministic")
end

-- 4. Behavioural expectations.
local idle = anim.player({}, 100.0)
checks = checks + 1
if math.abs(idle.sx - 1) > 0.05 or math.abs(idle.sy - 1) > 0.05 then fail("idle player should stay near scale 1") end

local dash = anim.player({ dash = true, dx = 1, dy = 0 }, 0.0)
checks = checks + 1
if not (dash.sx > dash.sy) then fail("dash should stretch horizontally (sx > sy)") end

local charging = anim.enemy("charger", { charging = true }, 0.0)
checks = checks + 1
if not (charging.sx > charging.sy) then fail("charging charger should stretch forward (sx > sy)") end

local p1 = anim.enemy("splitter", {}, 0.0)
local p2 = anim.enemy("splitter", {}, 0.2)
checks = checks + 1
if p1.sx == p2.sx and p1.sy == p2.sy then fail("splitter should squish over time") end

local w1 = anim.enemy("wisp", {}, 0.0)
local w2 = anim.enemy("wisp", {}, 1.0)
checks = checks + 1
if w1.oy == w2.oy then fail("wisp should bob over time") end

local boss = anim.enemy("boss", {}, 4.0)
checks = checks + 1
if boss.sx == 1 and boss.sy == 1 and boss.oy == 0 then fail("boss should breathe") end

-- 5. Spec numbers: dash stretch 1.3/0.8, brute stomp y 0.9, slinger recoil on fire.
local dash2 = anim.player({ dash = true, dx = 1, dy = 0 }, 0.0)
checks = checks + 1
if math.abs(dash2.sx - 1.30) > 0.001 or math.abs(dash2.sy - 0.80) > 0.001 then
    fail("dash should use 1.30 / 0.80 stretch")
end

local brute_min = 1
for i = 0, 40 do
    local a = anim.enemy("brute", { moving = true }, i * 0.02)
    if a.sy < brute_min then brute_min = a.sy end
end
checks = checks + 1
if brute_min > 0.91 then fail("brute stomp should squash to about y 0.9") end

local fire = anim.enemy("slinger", { fire = true }, 0.0)
local calm = anim.enemy("slinger", {}, 0.0)
checks = checks + 1
if not (fire.sx > calm.sx + 0.05) then fail("slinger should recoil-pop when it fires") end

local retreat = anim.enemy("slinger", { retreat = true }, 0.0)
checks = checks + 1
if retreat.rot >= calm.rot then fail("retreating slinger should lean away") end

-- 5. No NaN can leak from absurd inputs.
check_range("huge time", anim.enemy("brute", { moving = true }, 1e12))
check_range("huge state", anim.player({ moving = true, dx = 1e12, dy = -1e12 }, 1.0))

return { checks = checks, failures = failures }
