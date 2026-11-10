-- /src/game/level.lua
-- Level grid: parsing, collision, line of sight and path-flow towards the player.
-- Pure Lua (no go.*/gui.* calls) so it can be tested headlessly.
--
-- Legend used by src/levels/rooms.lua
--   #  wall            .  floor            O  pillar (round, blocks movement + bolts)
--   T  wall torch (a wall tile with a flame; needs floor to its south)
--   @  player start
--   w s c b p   wave-1 enemies: wisp, slinger, charger, brute, splitter
--   d           training dummy: never moves, never attacks, immortal (practice target)
--   W S C B Q   wave-2 enemies (appear when wave 1 is dead)
--   X  boss
local M = {}

M.TS = 48          -- tile size in world pixels
M.COLS = 20
M.ROWS = 13
M.X0 = 0
M.Y0 = 8           -- 13 rows * 48 = 624, centred vertically in a 640px window

local ENEMY_MARK = {
    w = { "wisp", 1 }, s = { "slinger", 1 }, c = { "charger", 1 }, b = { "brute", 1 }, p = { "splitter", 1 },
    d = { "dummy", 1 },
    W = { "wisp", 2 }, S = { "slinger", 2 }, C = { "charger", 2 }, B = { "brute", 2 }, Q = { "splitter", 2 },
    X = { "boss", 1 },
}
local SOLID = { ["#"] = true, ["O"] = true, ["T"] = true }
M.SOLID = SOLID

-- Cell (c = 1..COLS from the left, r = 1..ROWS from the TOP) -> world centre.
function M.cell_center(c, r)
    return M.X0 + (c - 0.5) * M.TS, M.Y0 + (M.ROWS - r + 0.5) * M.TS
end

-- World point -> cell (c, r). Returns nil outside the grid.
function M.cell_at(x, y)
    local c = math.floor((x - M.X0) / M.TS) + 1
    local r = M.ROWS - math.floor((y - M.Y0) / M.TS)
    if c < 1 or c > M.COLS or r < 1 or r > M.ROWS then return nil end
    return c, r
end

function M.char(lv, c, r)
    if c < 1 or c > M.COLS or r < 1 or r > M.ROWS then return "#" end
    return lv.grid[r][c]
end

function M.is_solid_cell(lv, c, r)
    return SOLID[M.char(lv, c, r)] == true
end

function M.is_solid(lv, x, y)
    local c, r = M.cell_at(x, y)
    if not c then return true end
    return SOLID[lv.grid[r][c]] == true
end

-- Parse an array of ROWS strings into a level table.
function M.parse(rows)
    assert(#rows == M.ROWS, "level needs " .. M.ROWS .. " rows, got " .. #rows)
    local lv = { grid = {}, spawns = {}, torches = {}, free_cells = {}, start = nil }
    for r = 1, M.ROWS do
        assert(#rows[r] == M.COLS, "row " .. r .. " must be " .. M.COLS .. " chars, got " .. #rows[r])
        lv.grid[r] = {}
        for c = 1, M.COLS do
            local ch = rows[r]:sub(c, c)
            local x, y = M.cell_center(c, r)
            local stored = ch
            if ch == "@" then
                lv.start = { x = x, y = y }
                stored = "."
            elseif ENEMY_MARK[ch] then
                table.insert(lv.spawns, { type = ENEMY_MARK[ch][1], wave = ENEMY_MARK[ch][2], x = x, y = y, c = c, r = r })
                stored = "."
            elseif ch == "T" then
                table.insert(lv.torches, { x = x, y = y, c = c, r = r })
            elseif ch ~= "#" and ch ~= "." and ch ~= "O" then
                error("unknown level character '" .. ch .. "' at row " .. r .. " col " .. c)
            end
            lv.grid[r][c] = stored
            if not SOLID[stored] then table.insert(lv.free_cells, { x = x, y = y, c = c, r = r }) end
        end
    end
    assert(lv.start, "level has no player start (@)")
    lv.flow_cell = nil
    lv.dist = nil
    return lv
end

-- Does a circle of radius `rad` at (x, y) overlap a solid cell?
function M.blocked(lv, x, y, rad)
    local c0 = math.floor((x - rad - M.X0) / M.TS) + 1
    local c1 = math.floor((x + rad - M.X0) / M.TS) + 1
    local r0 = M.ROWS - math.floor((y + rad - M.Y0) / M.TS)
    local r1 = M.ROWS - math.floor((y - rad - M.Y0) / M.TS)
    for r = r0, r1 do
        for c = c0, c1 do
            local ch = M.char(lv, c, r)
            if SOLID[ch] then
                local cx, cy = M.cell_center(c, r)
                if ch == "O" then
                    local d = M.TS * 0.38 + rad
                    local dx, dy = x - cx, y - cy
                    if dx * dx + dy * dy < d * d then return true end
                else
                    local half = M.TS * 0.5
                    local nx = math.max(cx - half, math.min(x, cx + half))
                    local ny = math.max(cy - half, math.min(y, cy + half))
                    local dx, dy = x - nx, y - ny
                    if dx * dx + dy * dy < rad * rad then return true end
                end
            end
        end
    end
    return false
end

-- Move from (x, y) towards (nx, ny), sliding along walls (axis-separated).
-- Returns the new position. If the start is already inside a wall, move freely
-- so nothing can ever get stuck.
function M.slide(lv, x, y, nx, ny, rad)
    if M.blocked(lv, x, y, rad) then return nx, ny end
    local fx, fy = x, y
    if not M.blocked(lv, nx, y, rad) then fx = nx end
    if not M.blocked(lv, fx, ny, rad) then fy = ny end
    return fx, fy
end

-- Is the straight line between two points free of walls (for a circle of radius rad)?
function M.los(lv, x0, y0, x1, y1, rad)
    local dx, dy = x1 - x0, y1 - y0
    local dist = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(dist / 16))
    for i = 1, steps do
        local t = i / steps
        if M.blocked(lv, x0 + dx * t, y0 + dy * t, rad) then return false end
    end
    return true
end

-- Last free point along the ray from (x0, y0) to (x1, y1) (used to keep puddles out of walls).
function M.last_free_on_ray(lv, x0, y0, x1, y1)
    if not M.is_solid(lv, x1, y1) then return x1, y1 end
    local dx, dy = x1 - x0, y1 - y0
    local dist = math.sqrt(dx * dx + dy * dy)
    local steps = math.max(1, math.floor(dist / 8))
    local lx, ly = x0, y0
    for i = 1, steps do
        local t = i / steps
        local px, py = x0 + dx * t, y0 + dy * t
        if M.is_solid(lv, px, py) then break end
        lx, ly = px, py
    end
    return lx, ly
end

-- A free point at or near (x, y) for a circle of radius rad.
function M.free_point_near(lv, x, y, rad)
    if not M.blocked(lv, x, y, rad) then return x, y end
    for _, d in ipairs({ 12, 24, 36, 48 }) do
        for k = 0, 7 do
            local a = k * math.pi / 4
            local px, py = x + math.cos(a) * d, y + math.sin(a) * d
            if not M.blocked(lv, px, py, rad) then return px, py end
        end
    end
    return x, y
end

-- ===== Flow field: BFS distance from the player's cell over free cells (8 neighbours) =====
local NB = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }

function M.update_flow(lv, px, py)
    local pc, pr = M.cell_at(px, py)
    if not pc then return end
    if lv.flow_cell and lv.flow_cell[1] == pc and lv.flow_cell[2] == pr then return end
    lv.flow_cell = { pc, pr }
    local dist = {}
    for r = 1, M.ROWS do dist[r] = {} end
    local queue, head = { { pc, pr } }, 1
    dist[pr][pc] = 0
    while head <= #queue do
        local cur = queue[head]; head = head + 1
        local cc, cr = cur[1], cur[2]
        local d = dist[cr][cc]
        for _, n in ipairs(NB) do
            local nc, nr = cc + n[1], cr + n[2]
            if nc >= 1 and nc <= M.COLS and nr >= 1 and nr <= M.ROWS
               and not SOLID[lv.grid[nr][nc]] and dist[nr][nc] == nil then
                local ok = true
                if n[1] ~= 0 and n[2] ~= 0 then   -- no cutting corners through walls
                    ok = not SOLID[lv.grid[cr][nc]] and not SOLID[lv.grid[nr][cc]]
                end
                if ok then
                    dist[nr][nc] = d + 1
                    queue[#queue + 1] = { nc, nr }
                end
            end
        end
    end
    lv.dist = dist
end

-- Unit direction from (x, y) towards the neighbouring cell that is closest to the player.
function M.flow_dir(lv, x, y)
    if not lv.dist then return nil end
    local c, r = M.cell_at(x, y)
    if not c then return nil end
    local best = lv.dist[r][c]
    if best == nil then return nil end
    local bc, br
    for _, n in ipairs(NB) do
        local nc, nr = c + n[1], r + n[2]
        if nc >= 1 and nc <= M.COLS and nr >= 1 and nr <= M.ROWS then
            local d = lv.dist[nr][nc]
            if d ~= nil and d < best then
                if n[1] == 0 or n[2] == 0 or (not SOLID[lv.grid[r][nc]] and not SOLID[lv.grid[nr][c]]) then
                    best, bc, br = d, nc, nr
                end
            end
        end
    end
    if not bc then return nil end
    local tx, ty = M.cell_center(bc, br)
    local dx, dy = tx - x, ty - y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.001 then return nil end
    return dx / len, dy / len
end

return M
