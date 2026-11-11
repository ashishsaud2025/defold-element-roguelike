-- /src/game/infusion.lua
-- Universal Pool -> spell infusion (addendum v2). Pure logic, no go.* calls, so the
-- headless harness can drive it directly. Lua 5.1 / LuaJIT only (AGENTS #12).
--
-- A Pool (puddle) infuses every NON-Pool spell that overlaps it. The spell keeps its
-- own statuses, additionally applies the Pool's statuses (minus on_player), and deals
-- x INFUSE_DAMAGE_MUL damage. The multiplier is applied in apply_hit and nowhere else.
local data = require "src.core.data"
local status_mod = require "src.core.status"

local M = {}

-- ===== 3.1 Eligible Pools ==========================================
-- Infuses only: alive, duration > 0, not a trail patch, and it belongs to a real skill.
-- Dense Clouds live in self.clouds, enemy effects are not in self.puddles, so they can
-- never infuse. Trail patches ("leaves a trail") get no free +25% from their own trail.
function M.eligible(pud)
    return pud ~= nil
        and pud.alive == true
        and (pud.duration or 0) > 0
        and pud.is_trail ~= true
        and pud.skill_ref ~= nil
end

-- ===== Geometry ======================================================
-- Circle (x, y, r) vs Pool circle.
function M.circle_hits_pool(x, y, r, pud)
    local dx, dy = pud.x - x, pud.y - y
    local rr = (r or 0) + pud.radius
    return dx * dx + dy * dy <= rr * rr
end

-- Segment (x0, y0) -> (x1, y1) vs Pool circle, inflated by the projectile radius r.
-- A single frames hitch can move a bolt 10-60 px; testing only endpoints would skip
-- small Pools, so the Pool is tested against the whole swept segment.
function M.segment_hits_pool(x0, y0, x1, y1, r, pud)
    local pr = pud.radius + (r or 0)
    local seg_x, seg_y = x1 - x0, y1 - y0
    local len2 = seg_x * seg_x + seg_y * seg_y
    local t
    if len2 <= 0 then
        t = 0
    else
        t = ((pud.x - x0) * seg_x + (pud.y - y0) * seg_y) / len2
        if t < 0 then t = 0 elseif t > 1 then t = 1 end
    end
    local cx, cy = x0 + seg_x * t, y0 + seg_y * t
    local dx, dy = pud.x - cx, pud.y - cy
    return dx * dx + dy * dy <= pr * pr
end

-- Cone sector vs Pool circle. Overlapping if the apex is inside the Pool, or the Pool
-- is within range and the angular gap between the aim axis and the Pool-centre
-- direction fits inside the arc plus asin(r / d). Slightly over-approximates near the
-- arc corners; that is acceptable (addendum 5.2). A Pool behind the caster never
-- infuses.
function M.sector_hits_pool(ax, ay, angle, half_arc, range, pud)
    local dx, dy = pud.x - ax, pud.y - ay
    local d2 = dx * dx + dy * dy
    local r = pud.radius
    if d2 <= r * r then return true end                 -- apex inside the Pool
    local d = math.sqrt(d2)
    if d > range + r then return false end
    if d <= 0 then return true end
    local to = math.atan2(dy, dx)
    local diff = to - angle
    while diff > math.pi do diff = diff - 2 * math.pi end
    while diff < -math.pi do diff = diff + 2 * math.pi end
    diff = math.abs(diff)
    local allow = half_arc + math.asin(math.min(1, r / d))
    return diff <= allow
end

-- ===== 3.3 Infusion record (lives on the spell object) ==============
-- spell.infuse = nil, or a table keyed by the Pool table:
--   entry = { statuses = <copy of pud.statuses>, color = <pud.color | skill colour>,
--             entered = <per-record order int>, expires = <clock + grace, or huge
--             while overlapping> }
-- Stores a COPY of the Pool's statuses each overlap, so the Pool dying mid-flight or a
-- Burning Mud revert cannot break an in-flight Bolt. Never mutates pud.statuses,
-- spell statuses or the compound table.
function M.touch(record, pud, now)
    record = record or {}
    local e = record[pud]
    if not e then
        record.next_order = (record.next_order or 0) + 1
        e = { entered = record.next_order }
        record[pud] = e
    end
    local st = {}
    for i, name in ipairs(pud.statuses or {}) do st[i] = name end
    e.statuses = st
    e.color = pud.color or (pud.skill_ref and pud.skill_ref.color) or { r = 1, g = 1, b = 1 }
    e.expires = math.huge                       -- living expiry while overlapping
    return record
end

-- The Pool stopped overlapping this frame: start the grace countdown from now.
-- Calling it every frame a Pool is out does not extend the grace.
function M.release(record, pud, now, grace)
    if not record then return end
    local e = record[pud]
    if e and e.expires == math.huge then
        e.expires = now + (grace or data.INTERACT.INFUSE_GRACE)
    end
end

-- List of live entries, oldest-entered first. Expired entries are pruned so a
-- long-lived spell cannot accumulate dead Pools.
function M.active(record, now)
    if not record then return nil end
    local live = {}
    for pud, e in pairs(record) do
        if type(e) == "table" then            -- skip the next_order counter field
            if now <= (e.expires or 0) then
                live[#live + 1] = e
            else
                record[pud] = nil
            end
        end
    end
    table.sort(live, function(a, b) return a.entered < b.entered end)
    return live
end

-- ===== 3.4 Merge rules (deterministic) ==============================
-- Native statuses first (their order), then each live entry's statuses in entry order.
-- Unknown names and on_player definitions are dropped. Returns a NEW array; never
-- touches the input lists. Note: `hide_self` is already stripped from spell lists by
-- do_cast; the on_player filter here is the safety net for pool lists that contain it.
function M.merge_statuses(native, entries)
    local out, seen = {}, {}
    local function add(name)
        local def = status_mod.STATUS_DATA[name]
        if not def or def.on_player then return end
        if seen[name] then return end
        seen[name] = true
        out[#out + 1] = name
    end
    for _, name in ipairs(native or {}) do add(name) end
    for _, e in ipairs(entries or {}) do
        for _, name in ipairs(e.statuses or {}) do add(name) end
    end
    return out
end

-- ===== 3.5 The one damage injection ==================================
-- Applied once per hit, never per Pool. `infused` is any non-empty entries list.
function M.damage(base, infused)
    if infused then
        return base * data.INTERACT.INFUSE_DAMAGE_MUL
    end
    return base
end

return M
