-- /src/core/quirks.lua
-- Quirk registry: identity for every quirk (stable id, display label, short form,
-- one-line description, tuning table, behaviour flags) plus the slot filter the
-- ability editor uses and the hook new quirks are added through.
--
-- This module OWNS quirk identity. `src/core/data.lua` still exports the legacy
-- parallel arrays (QUIRKS / QUIRK_IDS) and the tuning numbers (QUIRK_DATA); those
-- stay untouched so the existing skill generator keeps working. The tuning tables
-- are consumed here by reference, so every number still lives in exactly one place.
--
-- `flags` is the behaviour contract: a quirk adds one flag here and one read site
-- in `do_cast` (main/game.script). Nothing in the generator or the recipe key changes.
local data = require "src.core.data"

local M = {}

-- Display + default-grant order. FROZEN: default_id() indexes this list, so
-- reordering it would change which quirk a given roll produces.
M.DEFAULT_IDS = { "split_in_two", "leaves_trail", "repeat_once", "bigger_slower", "health_cost" }

-- `label` is the display text the generated skill carries (`skill.quirk`); it must
-- match data.QUIRKS[i] character for character while both exist.
-- `basic_ok` = legal on a left-click basic attack (no self-damaging quirks there).
-- `default_pool` = granted without any unlock step.
M.DEFS = {
    split_in_two = {
        id = "split_in_two",
        label = "splits in two",
        short = "splits",
        desc = "Two weaker casts, angled apart.",
        basic_ok = true,
        default_pool = true,
        flags = { split = true },
        data = data.QUIRK_DATA.split_in_two,
    },
    leaves_trail = {
        id = "leaves_trail",
        label = "leaves a trail",
        short = "trail",
        desc = "Leaves short-lived patches behind.",
        basic_ok = true,
        default_pool = true,
        flags = { trail = true },
        data = data.QUIRK_DATA.leaves_trail,
    },
    repeat_once = {
        id = "repeat_once",
        label = "repeats once",
        short = "repeats",
        desc = "Casts a second time from the same spot.",
        basic_ok = true,
        default_pool = false,
        flags = { repeat_delay = true },
        data = data.QUIRK_DATA.repeat_once,
    },
    bigger_slower = {
        id = "bigger_slower",
        label = "bigger but slower",
        short = "bigger",
        desc = "30% larger, 20% slower.",
        basic_ok = true,
        default_pool = false,
        flags = { bigger = true },
        data = data.QUIRK_DATA.bigger_slower,
    },
    health_cost = {
        id = "health_cost",
        label = "costs 5% health",
        short = "blood",
        desc = "Pays 5% health for 50% more power.",
        basic_ok = false,            -- a basic attack may never cost health
        default_pool = false,
        flags = { hp_cost = true },
        data = data.QUIRK_DATA.health_cost,
    },
}

-- Built-in ids, for O(1) "is this frozen?" checks.
local DEFAULT_SET = {}
for _, id in ipairs(M.DEFAULT_IDS) do DEFAULT_SET[id] = true end

-- Registered extras, in insertion order (extras never reorder the defaults).
local extras = {}
local extra_defs = {}

-- The def for `id`, built-in or registered; nil when unknown.
function M.get(id)
    if type(id) ~= "string" then return nil end
    return M.DEFS[id] or extra_defs[id]
end

-- Look a quirk up by its display label (the text a generated skill carries).
function M.by_label(text)
    if type(text) ~= "string" then return nil end
    for _, id in ipairs(M.DEFAULT_IDS) do
        local def = M.DEFS[id]
        if def.label == text then return def end
    end
    for _, def in ipairs(extras) do
        if def.label == text then return def end
    end
    return nil
end

-- Display order: DEFAULT_IDS first, then registered extras in insertion order.
function M.list()
    local out = {}
    for _, id in ipairs(M.DEFAULT_IDS) do
        out[#out + 1] = M.DEFS[id]
    end
    for _, def in ipairs(extras) do
        out[#out + 1] = def
    end
    return out
end

-- Quirks legal for one loadout slot. `kind` is "spell" or "basic". A bad kind is a
-- call-site bug, so it asserts instead of silently rendering an empty editor.
function M.list_for_slot(kind)
    assert(kind == "spell" or kind == "basic", "list_for_slot: bad kind " .. tostring(kind))
    local all = M.list()
    if kind == "spell" then return all end
    local out = {}
    for _, def in ipairs(all) do
        if def.basic_ok then out[#out + 1] = def end
    end
    return out
end

-- Deterministic default for a uniform roll r2 in [0, 1). Indexes DEFAULT_IDS only,
-- so registering a quirk can never move the mapping. r2 == 1.0 (a producer that
-- rounds up) clamps to the last entry instead of returning nil.
function M.default_id(r2)
    local n = #M.DEFAULT_IDS
    local i = math.floor((r2 or 0) * n) + 1
    if i < 1 then i = 1 elseif i > n then i = n end
    return M.DEFAULT_IDS[i]
end

local function valid_def(def)
    return type(def) == "table"
        and type(def.id) == "string" and #def.id > 0
        and type(def.label) == "string" and #def.label > 0
        and type(def.short) == "string" and #def.short > 0 and #def.short <= 9
        and type(def.desc) == "string" and #def.desc > 0
end

-- Add an extra quirk. False (never a crash) when the def is incomplete, the id is
-- already taken (built-in or registered) or the label is already used (by_label
-- must stay unambiguous). Scalar fields and `flags` are copied (a shallow copy), so
-- a caller that mutates its own table afterwards cannot corrupt the registry.
-- `data` is deliberately stored by reference: it is the shared tuning table.
function M.register(def)
    if not valid_def(def) then return false end
    if DEFAULT_SET[def.id] or extra_defs[def.id] then return false end
    if M.by_label(def.label) then return false end
    local flags = {}
    for k, v in pairs(def.flags or {}) do flags[k] = v end
    local entry = {
        id = def.id,
        label = def.label,
        short = def.short,
        desc = def.desc,
        basic_ok = def.basic_ok == true,
        default_pool = def.default_pool == true,
        flags = flags,
        data = def.data or {},
    }
    extras[#extras + 1] = entry
    extra_defs[entry.id] = entry
    return true
end

-- Remove a registered quirk. Built-ins are frozen (always false); an unknown id
-- is false too.
function M.unregister(id)
    if type(id) ~= "string" then return false end
    if DEFAULT_SET[id] then return false end
    if not extra_defs[id] then return false end
    extra_defs[id] = nil
    for i = 1, #extras do
        if extras[i].id == id then
            table.remove(extras, i)
            break
        end
    end
    return true
end

return M
