-- ---------------------------------------------------------------------------
-- GomokuBoard — game logic for Gomoku (free-style, 15x15)
--
-- grid[r][c]:
--   0 = empty
--   1 = black stone (goes first)
--   2 = white stone
--
-- r=1 is the top row, c=1 is the leftmost column.
-- ---------------------------------------------------------------------------

local GomokuBoard = {}
GomokuBoard.__index = GomokuBoard

local N = 15

-- ---------------------------------------------------------------------------
-- Constructor
-- ---------------------------------------------------------------------------

function GomokuBoard:new()
    local o = setmetatable({}, self)
    o.n       = N
    o.grid    = {}
    o.turn    = 1
    o.status  = "playing"
    o.winner  = nil
    o.last_r  = nil
    o.last_c  = nil
    o.history = {}
    for r = 1, N do
        o.grid[r] = {}
        for c = 1, N do
            o.grid[r][c] = 0
        end
    end
    return o
end

-- ---------------------------------------------------------------------------
-- Reset
-- ---------------------------------------------------------------------------

function GomokuBoard:reset()
    for r = 1, self.n do
        for c = 1, self.n do
            self.grid[r][c] = 0
        end
    end
    self.turn    = 1
    self.status  = "playing"
    self.winner  = nil
    self.last_r  = nil
    self.last_c  = nil
    self.history = {}
end

-- ---------------------------------------------------------------------------
-- placeStone — place a stone for self.turn at (r,c)
-- Returns: "ok" / "occupied" / "won" / "draw"
-- ---------------------------------------------------------------------------

function GomokuBoard:placeStone(r, c)
    if self.status ~= "playing" then return "occupied" end
    if self.grid[r][c] ~= 0 then return "occupied" end

    local player = self.turn
    self.grid[r][c] = player
    self.history[#self.history + 1] = { r = r, c = c, player = player }
    self.last_r = r
    self.last_c = c

    -- Check for win
    if self:checkWin(r, c, player) then
        self.status = "ended"
        self.winner = player
        return "won"
    end

    -- Check for draw (board full)
    local full = true
    for rr = 1, self.n do
        for cc = 1, self.n do
            if self.grid[rr][cc] == 0 then
                full = false
                break
            end
        end
        if not full then break end
    end
    if full then
        self.status = "ended"
        self.winner = nil
        return "draw"
    end

    -- Switch turn
    self.turn = (player == 1) and 2 or 1
    return "ok"
end

-- ---------------------------------------------------------------------------
-- checkWin — true if player has 5+ consecutive stones through (r,c)
-- Directions: horizontal, vertical, diag↗, diag↘
-- ---------------------------------------------------------------------------

function GomokuBoard:checkWin(r, c, player)
    local grid = self.grid
    local n    = self.n

    local function countDir(dr, dc)
        local count = 0
        local nr, nc = r + dr, c + dc
        while nr >= 1 and nr <= n and nc >= 1 and nc <= n and grid[nr][nc] == player do
            count = count + 1
            nr = nr + dr
            nc = nc + dc
        end
        return count
    end

    local dirs = { {0,1}, {1,0}, {1,1}, {1,-1} }
    for _, d in ipairs(dirs) do
        local total = 1 + countDir(d[1], d[2]) + countDir(-d[1], -d[2])
        if total >= 5 then return true end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- undoMove — remove last stone from history
-- ---------------------------------------------------------------------------

function GomokuBoard:undoMove()
    if #self.history == 0 then return false end
    local last = table.remove(self.history)
    self.grid[last.r][last.c] = 0
    self.turn   = last.player
    self.status = "playing"
    self.winner = nil
    local prev = self.history[#self.history]
    self.last_r = prev and prev.r or nil
    self.last_c = prev and prev.c or nil
    return true
end

-- ---------------------------------------------------------------------------
-- AI helpers
-- ---------------------------------------------------------------------------

-- Candidate cells: empty cells within 2 squares of existing stones
function GomokuBoard:getCandidates()
    local grid       = self.grid
    local n          = self.n
    local candidates = {}
    local seen       = {}

    for r = 1, n do
        for c = 1, n do
            if grid[r][c] ~= 0 then
                for dr = -2, 2 do
                    for dc = -2, 2 do
                        local nr = r + dr
                        local nc = c + dc
                        local key = nr * 20 + nc
                        if nr >= 1 and nr <= n and nc >= 1 and nc <= n
                            and grid[nr][nc] == 0 and not seen[key] then
                            seen[key] = true
                            candidates[#candidates + 1] = { r = nr, c = nc }
                        end
                    end
                end
            end
        end
    end

    -- Empty board: start in center
    if #candidates == 0 then
        candidates[1] = { r = 8, c = 8 }
    end
    return candidates
end

-- Score a sequence of count stones with open_ends open ends
local function scoreSequence(count, open_ends)
    if count >= 5 then return 1000000 end
    if count == 4 and open_ends == 2 then return 10000 end
    if count == 4 and open_ends == 1 then return 1000 end
    if count == 3 and open_ends == 2 then return 1000 end
    if count == 3 and open_ends == 1 then return 100 end
    if count == 2 and open_ends == 2 then return 10 end
    return 1
end

-- Evaluate the board from `player`s perspective
-- Scans all lines for sequences of player and opponent stones
local function evaluateForPlayer(grid, n, player)
    local opp  = (player == 1) and 2 or 1
    local score = 0

    local function scanDir(dr, dc)
        -- Walk through each "line start" that hasn't been visited
        -- We mark visited cells to avoid double-counting
        for r = 1, n do
            for c = 1, n do
                -- Only start a new sequence if we're at the beginning of a run
                -- (previous cell in this direction is outside bounds or different value)
                local pr = r - dr
                local pc = c - dc
                local prev_in_bounds = (pr >= 1 and pr <= n and pc >= 1 and pc <= n)
                local prev_val       = prev_in_bounds and grid[pr][pc] or 0

                local cell_val = grid[r][c]
                if cell_val ~= 0 and prev_val ~= cell_val then
                    -- Count consecutive cells
                    local count   = 1
                    local nr      = r + dr
                    local nc      = c + dc
                    while nr >= 1 and nr <= n and nc >= 1 and nc <= n
                            and grid[nr][nc] == cell_val do
                        count = count + 1
                        nr = nr + dr
                        nc = nc + dc
                    end

                    -- Check open ends
                    local open_ends = 0
                    -- Behind start: cell (r-dr, c-dc)
                    if not prev_in_bounds or prev_val == 0 then
                        open_ends = open_ends + 1
                    end
                    -- After end: cell (nr, nc)
                    local after_in_bounds = (nr >= 1 and nr <= n and nc >= 1 and nc <= n)
                    if after_in_bounds and grid[nr][nc] == 0 then
                        open_ends = open_ends + 1
                    end

                    local seq_score = scoreSequence(count, open_ends)
                    if cell_val == player then
                        score = score + seq_score
                    else
                        score = score - seq_score
                    end
                end
            end
        end
    end

    scanDir(0, 1)   -- horizontal
    scanDir(1, 0)   -- vertical
    scanDir(1, 1)   -- diagonal ↘
    scanDir(1, -1)  -- diagonal ↙

    return score
end

-- Evaluate placing a stone at (r,c) for a given player on a scratch grid
local function evalMove(grid, n, r, c, player)
    grid[r][c] = player
    local s = evaluateForPlayer(grid, n, player)
    grid[r][c] = 0
    return s
end

-- Simple minimax (no alpha-beta) over a tiny candidate set for depth > 1
-- Returns score from `maximizer` perspective
local function minimax(grid, n, depth, maximizer, current_player, alpha, beta)
    -- Collect candidates on the current grid state
    local candidates = {}
    local seen = {}
    for r = 1, n do
        for c = 1, n do
            if grid[r][c] ~= 0 then
                for dr = -2, 2 do
                    for dc = -2, 2 do
                        local nr = r + dr
                        local nc = c + dc
                        local key = nr * 20 + nc
                        if nr >= 1 and nr <= n and nc >= 1 and nc <= n
                                and grid[nr][nc] == 0 and not seen[key] then
                            seen[key] = true
                            candidates[#candidates + 1] = { r = nr, c = nc }
                        end
                    end
                end
            end
        end
    end
    if #candidates == 0 then
        return evaluateForPlayer(grid, n, maximizer)
    end

    -- At depth 0, return static evaluation
    if depth == 0 then
        return evaluateForPlayer(grid, n, maximizer)
    end

    local opp = (current_player == 1) and 2 or 1
    local is_max = (current_player == maximizer)

    if is_max then
        local best = -math.huge
        for _, m in ipairs(candidates) do
            -- Quick win check before recursing
            grid[m.r][m.c] = current_player
            -- Check immediate win
            local immediate_win = false
            do
                local function countDir2(dr, dc)
                    local count = 0
                    local nr, nc = m.r + dr, m.c + dc
                    while nr >= 1 and nr <= n and nc >= 1 and nc <= n
                            and grid[nr][nc] == current_player do
                        count = count + 1
                        nr = nr + dr
                        nc = nc + dc
                    end
                    return count
                end
                local dirs2 = { {0,1}, {1,0}, {1,1}, {1,-1} }
                for _, d in ipairs(dirs2) do
                    if 1 + countDir2(d[1], d[2]) + countDir2(-d[1], -d[2]) >= 5 then
                        immediate_win = true
                        break
                    end
                end
            end
            local val
            if immediate_win then
                val = 1000000 + depth * 10
            else
                val = minimax(grid, n, depth - 1, maximizer, opp, alpha, beta)
            end
            grid[m.r][m.c] = 0
            if val > best then best = val end
            if best > alpha then alpha = best end
            if alpha >= beta then break end
        end
        return best
    else
        local best = math.huge
        for _, m in ipairs(candidates) do
            grid[m.r][m.c] = current_player
            local immediate_win = false
            do
                local function countDir2(dr, dc)
                    local count = 0
                    local nr, nc = m.r + dr, m.c + dc
                    while nr >= 1 and nr <= n and nc >= 1 and nc <= n
                            and grid[nr][nc] == current_player do
                        count = count + 1
                        nr = nr + dr
                        nc = nc + dc
                    end
                    return count
                end
                local dirs2 = { {0,1}, {1,0}, {1,1}, {1,-1} }
                for _, d in ipairs(dirs2) do
                    if 1 + countDir2(d[1], d[2]) + countDir2(-d[1], -d[2]) >= 5 then
                        immediate_win = true
                        break
                    end
                end
            end
            local val
            if immediate_win then
                val = -(1000000 + depth * 10)
            else
                val = minimax(grid, n, depth - 1, maximizer, opp, alpha, beta)
            end
            grid[m.r][m.c] = 0
            if val < best then best = val end
            if best < beta then beta = best end
            if alpha >= beta then break end
        end
        return best
    end
end

-- ---------------------------------------------------------------------------
-- getAIMove — threat-based heuristic + optional shallow minimax
-- depth: 1 = single-ply, 2 = two-ply minimax over top candidates
-- ---------------------------------------------------------------------------

function GomokuBoard:getAIMove(depth)
    depth = depth or 1
    if self.status ~= "playing" then return nil end

    local player = self.turn
    local opp    = (player == 1) and 2 or 1
    local grid   = self.grid
    local n      = self.n

    local candidates = self:getCandidates()
    if #candidates == 0 then return nil end

    -- Single candidate: return it
    if #candidates == 1 then return candidates[1] end

    -- Score each candidate
    local scored = {}
    for _, m in ipairs(candidates) do
        local own_score = evalMove(grid, n, m.r, m.c, player)
        local opp_score = evalMove(grid, n, m.r, m.c, opp)
        scored[#scored + 1] = {
            r     = m.r,
            c     = m.c,
            score = own_score + opp_score * 0.9,
        }
    end

    -- Sort descending by heuristic score
    table.sort(scored, function(a, b) return a.score > b.score end)

    if depth <= 1 then
        return { r = scored[1].r, c = scored[1].c }
    end

    -- For depth >= 2: run minimax over top N candidates
    local top_n = math.min(12, #scored)
    local best_move  = { r = scored[1].r, c = scored[1].c }
    local best_val   = -math.huge

    for i = 1, top_n do
        local m = scored[i]
        -- Immediate win: take it now
        grid[m.r][m.c] = player
        local win = false
        do
            local function countDir(dr, dc)
                local count = 0
                local nr, nc = m.r + dr, m.c + dc
                while nr >= 1 and nr <= n and nc >= 1 and nc <= n
                        and grid[nr][nc] == player do
                    count = count + 1
                    nr = nr + dr
                    nc = nc + dc
                end
                return count
            end
            local dirs = { {0,1}, {1,0}, {1,1}, {1,-1} }
            for _, d in ipairs(dirs) do
                if 1 + countDir(d[1], d[2]) + countDir(-d[1], -d[2]) >= 5 then
                    win = true
                    break
                end
            end
        end
        if win then
            grid[m.r][m.c] = 0
            return { r = m.r, c = m.c }
        end
        -- Recurse
        local val = minimax(grid, n, depth - 1, player, opp, -math.huge, math.huge)
        grid[m.r][m.c] = 0
        if val > best_val then
            best_val  = val
            best_move = { r = m.r, c = m.c }
        end
    end

    return best_move
end

-- ---------------------------------------------------------------------------
-- Serialize / Load
-- ---------------------------------------------------------------------------

function GomokuBoard:serialize()
    local grid_copy = {}
    for r = 1, self.n do
        grid_copy[r] = {}
        for c = 1, self.n do
            grid_copy[r][c] = self.grid[r][c]
        end
    end
    local history_copy = {}
    for i, h in ipairs(self.history) do
        history_copy[i] = { r = h.r, c = h.c, player = h.player }
    end
    return {
        grid    = grid_copy,
        turn    = self.turn,
        status  = self.status,
        winner  = self.winner,
        last_r  = self.last_r,
        last_c  = self.last_c,
        history = history_copy,
    }
end

function GomokuBoard:load(data)
    if type(data) ~= "table" or type(data.grid) ~= "table" then
        return false
    end
    local n = self.n
    for r = 1, n do
        if type(data.grid[r]) ~= "table" then return false end
        for c = 1, n do
            local v = data.grid[r][c]
            if type(v) ~= "number" or v < 0 or v > 2 then return false end
            self.grid[r][c] = v
        end
    end
    self.turn   = (data.turn == 2) and 2 or 1
    self.status = (data.status == "ended") and "ended" or "playing"
    self.winner = data.winner
    self.last_r = data.last_r
    self.last_c = data.last_c
    self.history = {}
    if type(data.history) == "table" then
        for i, h in ipairs(data.history) do
            if type(h) == "table" and h.r and h.c and h.player then
                self.history[i] = { r = h.r, c = h.c, player = h.player }
            end
        end
    end
    return true
end

return GomokuBoard
