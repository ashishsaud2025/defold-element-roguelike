-- /src/game/reaction.lua
-- Pool reactions (pool_reactions_addendum). Pure logic, no go.* calls, so the smoke
-- harness can drive it. Lua 5.1 only (AGENTS #12).
--
-- A pure Pool (fire/water/wind/earth only) overlapping a spell area of a different
-- element temporarily gains the statuses of the compound {pool, spell} — for
-- INTERACT.REACTION_TIME seconds. The combo name is the banner; statuses come from
-- data.COMPOUNDS, never hand-written.
--
-- One active reaction per Pool at a time. Each pair fires at most once per pool per
-- lifetime (pud.reacted[pair_key], never cleared). The fire-pool + wind-spell cell is
-- Fire Cyclone's and never yields a reaction.
local data = require "src.core.data"
local status_mod = require "src.core.status"
local M = {}

local function pair_key(a, b)
    if a <= b then return a .. "+" .. b else return b .. "+" .. a end
end

local function has_status(list, want)
    for _, s in ipairs(list or {}) do if s == want then return true end end
    return false
end

-- Only *pure* Pools react: same two elements listed, live, not trail patches.
-- (Mixed pools never react; mud + fire is Fire Cyclone's Burning Mud's own case,
-- kept separate; trail patches never react; Dense Clouds are not puddles here.)
function M.eligible(pud)
    if pud == nil then return false end
    if pud.alive ~= true or (pud.duration or 0) <= 0 then return false end
    if pud.is_trail == true or pud.skill_ref == nil then return false end
    if not pud.elements or #pud.elements < 2 then return false end
    return pud.elements[1] == pud.elements[2]
end

-- §3.2: for each element of the area with `e ~= pool_element`, in listed order, first
-- reaction cell wins. Returns { id, pair_key, source_element, added } or nil.
-- Empty `added` (Nothing to add) skips silently: no latch, no banner.
function M.reaction_for(pud, area_elements)
    if not M.eligible(pud) then return nil end
    if pud.reaction then return nil end                       -- one active at a time
    local pool_el = pud.elements[1]
    local seen = {}
    for _, e in ipairs(area_elements or {}) do
        if e ~= pool_el and not seen[e] then
            seen[e] = true
            -- The fire-Pool + wind-spell cell belongs to Fire Cyclone; never a reaction.
            if not (pool_el == "fire" and e == "wind") then
                local pk = pair_key(pool_el, e)
                local rid = data.REACTIONS[pk]
                if rid and not (pud.reacted or {})[pk] then
                    local com = data.COMPOUNDS[pk]
                    local added = {}
                    if com and com.statuses then
                        for _, st in ipairs(com.statuses) do
                            local def = status_mod.STATUS_DATA[st]
                            if def and not def.on_player and not has_status(pud.statuses, st) then
                                added[#added + 1] = st
                            end
                        end
                    end
                    if #added > 0 then
                        return { id = rid, pair_key = pk, source_element = e, added = added }
                    end
                end
            end
        end
    end
    return nil
end

-- §3.3: stamp the reaction onto the pool (record-and-patch pattern). Does no go.*
-- calls; the caller paints/announces (banner, tint, sparks).
function M.start(pud, r, now)
    pud.reacted = pud.reacted or {}
    pud.reacted[r.pair_key] = true
    for _, s in ipairs(r.added) do table.insert(pud.statuses, s) end
    local added_copy = {}
    for i, v in ipairs(r.added) do added_copy[i] = v end
    pud.reaction = {
        id = r.id,
        until_time = now + data.INTERACT.REACTION_TIME,
        added = added_copy,
        source = r.source_element,
    }
    return pud.reaction
end

-- Remove exactly the statuses this reaction added; nothing else moves. When the reaction
-- is over, the pool's statuses are back to what they were before it started.
function M.revert(pud)
    local rec = pud.reaction
    if not rec then return end
    for _, s in ipairs(rec.added) do
        for k = #pud.statuses, 1, -1 do
            if pud.statuses[k] == s then table.remove(pud.statuses, k) break end
        end
    end
    pud.reaction = nil
end

-- True while a reaction lasts (used by the caller for re-tint tracking).
function M.live(pud, now)
    return pud.reaction ~= nil and now < pud.reaction.until_time
end

return M
