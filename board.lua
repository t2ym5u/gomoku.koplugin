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

-- Would placing `player` at (r,c) complete a five-in-a-row? The grid must
-- already hold the stone. Was written out three times before; one copy is
-- enough, and it is the hottest test in the search.
local WIN_DIRS = { {0, 1}, {1, 0}, {1, 1}, {1, -1} }

local function completesFive(grid, n, r, c, player)
    for _, d in ipairs(WIN_DIRS) do
        local dr, dc = d[1], d[2]
        local count = 1
        local nr, nc = r + dr, c + dc
        while nr >= 1 and nr <= n and nc >= 1 and nc <= n and grid[nr][nc] == player do
            count = count + 1; nr = nr + dr; nc = nc + dc
        end
        nr, nc = r - dr, c - dc
        while nr >= 1 and nr <= n and nc >= 1 and nc <= n and grid[nr][nc] == player do
            count = count + 1; nr = nr - dr; nc = nc - dc
        end
        if count >= 5 then return true end
    end
    return false
end

-- Empty points within two of a stone, which is where anything relevant can
-- happen. Returned in no particular order -- callers that search deeper sort
-- them first (see orderedCandidates).
local function collectCandidates(grid, n)
    local candidates, seen = {}, {}
    for r = 1, n do
        for c = 1, n do
            if grid[r][c] ~= 0 then
                for dr = -2, 2 do
                    for dc = -2, 2 do
                        local nr, nc = r + dr, c + dc
                        if nr >= 1 and nr <= n and nc >= 1 and nc <= n and grid[nr][nc] == 0 then
                            local key = (nr - 1) * n + nc
                            if not seen[key] then
                                seen[key] = true
                                candidates[#candidates + 1] = { r = nr, c = nc }
                            end
                        end
                    end
                end
            end
        end
    end
    return candidates
end

-- Alpha-beta prunes in proportion to how well moves are ordered, and an
-- unordered list barely prunes at all. Scoring each candidate for both sides
-- (mine to build, theirs to deny) and taking the best few keeps the branching
-- factor low enough to be worth searching at all on an e-ink CPU.
-- Root only. Inside the search every candidate is kept: capping there was
-- measured as a clear loss (top-16 by proximity dropped the critical block
-- often enough to cost games), while capping the root costs nothing because
-- the root is scored with the full evaluation.
local SEARCH_WIDTH = 12

-- Counts stones within two squares. O(1) per candidate, where a full-board
-- evaluation is O(board) -- ordering every node the expensive way cost more
-- than the extra cutoffs it bought, measured at 0.039s per move against
-- 0.025s for the version that did not order inner nodes at all.
local function proximity(grid, n, r, c)
    local near = 0
    for dr = -2, 2 do
        for dc = -2, 2 do
            local nr, nc = r + dr, c + dc
            if nr >= 1 and nr <= n and nc >= 1 and nc <= n and grid[nr][nc] ~= 0 then
                near = near + (math.max(math.abs(dr), math.abs(dc)) == 1 and 2 or 1)
            end
        end
    end
    return near
end

local function orderedCandidates(grid, n, player, width, cheap)
    local raw = collectCandidates(grid, n)
    if #raw == 0 then return raw end
    local opp = (player == 1) and 2 or 1
    local scored = {}
    for i = 1, #raw do
        local m = raw[i]
        scored[i] = {
            r = m.r, c = m.c,
            score = cheap and proximity(grid, n, m.r, m.c)
                 or (evalMove(grid, n, m.r, m.c, player)
                     + evalMove(grid, n, m.r, m.c, opp) * 0.9),
        }
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        -- Ties broken by position so the search is reproducible.
        if a.r ~= b.r then return a.r < b.r end
        return a.c < b.c
    end)
    if not width then return scored end
    local limit = math.min(width, #scored)
    local out = {}
    for i = 1, limit do out[i] = scored[i] end
    return out
end

-- ---------------------------------------------------------------------------
-- Incremental evaluation for the search.
--
-- evaluateForPlayer() sums a score per run of stones along every row, column
-- and diagonal, and is antisymmetric (player 2's score is minus player 1's).
-- So it is a sum over lines, and a stone only changes the four lines through
-- it: the search keeps each line's contribution (for player 1) and rescans
-- just those four, about 60 cells instead of 900. lineScore() walks a line in
-- the same direction as scanDir() so the totals are identical, including the
-- quirk that the board edge counts as an open end before a run but a closed
-- one after it.
-- ---------------------------------------------------------------------------

local line_cache = {}   -- n -> { lines = {cells...}, at = cell -> {4 line ids} }

local function buildLines(n)
    if line_cache[n] then return line_cache[n] end
    local lines, at = {}, {}
    for idx = 1, n * n do at[idx] = {} end
    local function addLine(r, c, dr, dc)
        local cells = {}
        while r >= 1 and r <= n and c >= 1 and c <= n do
            cells[#cells + 1] = (r - 1) * n + c
            r = r + dr; c = c + dc
        end
        lines[#lines + 1] = cells
        for _, idx in ipairs(cells) do local t = at[idx]; t[#t + 1] = #lines end
    end
    for r = 1, n do addLine(r, 1, 0, 1) end                       -- horizontal
    for c = 1, n do addLine(1, c, 1, 0) end                       -- vertical
    for c = n, 1, -1 do addLine(1, c, 1, 1) end                   -- diagonal ↘
    for r = 2, n do addLine(r, 1, 1, 1) end
    for c = 1, n do addLine(1, c, 1, -1) end                      -- diagonal ↙
    for r = 2, n do addLine(r, n, 1, -1) end
    line_cache[n] = { lines = lines, at = at }
    return line_cache[n]
end

-- Score of one line for player 1. `flat` is the board as a flat array.
local function lineScore(flat, cells)
    local score, len, i = 0, #cells, 1
    local prev_val = 0          -- the board edge reads as empty
    while i <= len do
        local cell_val = flat[cells[i]]
        if cell_val ~= 0 and prev_val ~= cell_val then
            local count, j = 1, i + 1
            while j <= len and flat[cells[j]] == cell_val do
                count = count + 1; j = j + 1
            end
            local open_ends = (prev_val == 0) and 1 or 0
            if j <= len and flat[cells[j]] == 0 then open_ends = open_ends + 1 end
            local seq_score = scoreSequence(count, open_ends)
            if cell_val == 1 then score = score + seq_score else score = score - seq_score end
            prev_val = cell_val
            i = j
        else
            prev_val = cell_val
            i = i + 1
        end
    end
    return score
end

-- Search state: the grid, a flat copy, per-line scores and their total.
local S = { grid = nil, n = 0, flat = nil, lval = nil, total = 0, L = nil }

local function evalInit(grid, n)
    local L = buildLines(n)
    local flat = {}
    for r = 1, n do for c = 1, n do flat[(r - 1) * n + c] = grid[r][c] end end
    local lval, total = {}, 0
    for k, cells in ipairs(L.lines) do
        local v = lineScore(flat, cells)
        lval[k] = v; total = total + v
    end
    S.grid, S.n, S.flat, S.lval, S.total, S.L = grid, n, flat, lval, total, L
end

-- Sets (r, c) to v (0 = empty) and updates the cached evaluation.
local function setCell(r, c, v)
    S.grid[r][c] = v
    local idx = (r - 1) * S.n + c
    local flat, lval, lines = S.flat, S.lval, S.L.lines
    flat[idx] = v
    local total = S.total
    for _, k in ipairs(S.L.at[idx]) do
        local nv = lineScore(flat, lines[k])
        total = total + nv - lval[k]
        lval[k] = nv
    end
    S.total = total
end

-- evaluateForPlayer(S.grid, S.n, player), from the cache.
local function evalFast(player)
    return (player == 1) and S.total or -S.total
end

-- orderedCandidates(...) with the evaluation read from the cache (same
-- scores, same order).
local function orderedCandidatesFast(grid, n, player, cheap)
    if cheap then return orderedCandidates(grid, n, player, nil, true) end
    local raw = collectCandidates(grid, n)
    local opp = (player == 1) and 2 or 1
    local scored = {}
    for i = 1, #raw do
        local m = raw[i]
        setCell(m.r, m.c, player)
        local mine = evalFast(player)
        setCell(m.r, m.c, opp)
        local theirs = evalFast(opp)
        setCell(m.r, m.c, 0)
        scored[i] = { r = m.r, c = m.c, score = mine + theirs * 0.9 }
    end
    table.sort(scored, function(a, b)
        if a.score ~= b.score then return a.score > b.score end
        if a.r ~= b.r then return a.r < b.r end
        return a.c < b.c
    end)
    return scored
end

-- ---------------------------------------------------------------------------
-- Search budget. Each level has a maximum depth (the depth it always played
-- at) and a CPU budget in seconds of a Kobo-class e-reader; the root deepens
-- one ply at a time and, when the budget runs out, plays the best move of the
-- deepest finished iteration. AI_TIME_SCALE simulates a slower device in
-- tests and benchmarks (0.04 ≈ a Kobo on a fast laptop).
-- ---------------------------------------------------------------------------

GomokuBoard.AI_LEVELS = {
    easy   = { depth = 1, budget = 0.5 },
    medium = { depth = 2, budget = 1.5 },
    hard   = { depth = 3, budget = 2.5 },
}
GomokuBoard.AI_TIME_SCALE = 1

local clock = os.clock
local AI_ABORT = {}
local ai_deadline = math.huge
local ai_nodes = 0

-- Negamax-shaped alpha-beta: returns the score from `maximizer`'s point of
-- view for the side in `current_player` to move.
local function minimax(grid, n, depth, maximizer, current_player, alpha, beta)
    ai_nodes = ai_nodes + 1
    if ai_nodes % 64 == 0 and clock() > ai_deadline then error(AI_ABORT, 0) end
    if depth == 0 then
        return evalFast(maximizer)
    end
    local candidates = orderedCandidates(grid, n, current_player, nil, true)
    if #candidates == 0 then
        return evalFast(maximizer)
    end

    local opp    = (current_player == 1) and 2 or 1
    local is_max = (current_player == maximizer)
    local best   = is_max and -math.huge or math.huge

    for _, m in ipairs(candidates) do
        local val
        grid[m.r][m.c] = current_player
        if completesFive(grid, n, m.r, m.c, current_player) then
            grid[m.r][m.c] = 0
            -- Prefer winning sooner, and losing later.
            val = is_max and (1000000 + depth * 10) or -(1000000 + depth * 10)
        else
            grid[m.r][m.c] = 0
            setCell(m.r, m.c, current_player)
            val = minimax(grid, n, depth - 1, maximizer, opp, alpha, beta)
            setCell(m.r, m.c, 0)
        end

        if is_max then
            if val > best then best = val end
            if best > alpha then alpha = best end
        else
            if val < best then best = val end
            if best < beta then beta = best end
        end
        if alpha >= beta then break end
    end
    return best
end

-- One root iteration: the best of the `top_n` first candidates at `depth`.
local function searchRoot(grid, n, scored, top_n, depth, player)
    local best_move = { r = scored[1].r, c = scored[1].c }
    local best_val  = -math.huge
    for i = 1, top_n do
        local m = scored[i]
        -- Carrying best_val in as alpha is what makes the root prune at all:
        -- restarting each candidate at -inf (as this used to) throws away
        -- every cutoff between siblings, which is most of alpha-beta's value.
        setCell(m.r, m.c, player)
        local val = minimax(grid, n, depth - 1, player, (player == 1) and 2 or 1,
                            best_val, math.huge)
        setCell(m.r, m.c, 0)
        if val > best_val then
            best_val  = val
            best_move = { r = m.r, c = m.c }
        end
    end
    return best_move
end

-- Returns the AI's move, searching `depth` plies; `budget` (seconds, scaled
-- by AI_TIME_SCALE; nil = no limit) can stop it at a shallower depth.
function GomokuBoard:getAIMove(depth, budget)
    depth = depth or 1
    if self.status ~= "playing" then return nil end

    local grid, n = self.grid, self.n
    local player  = self.turn

    -- Opening move: nothing to react to yet.
    local occupied = false
    for r = 1, n do
        for c = 1, n do
            if grid[r][c] ~= 0 then occupied = true break end
        end
        if occupied then break end
    end
    if not occupied then
        local mid = math.floor((n + 1) / 2)
        return { r = mid, c = mid }
    end

    evalInit(grid, n)
    local scored = orderedCandidatesFast(grid, n, player)
    if #scored == 0 then return nil end
    self.ai_depth_reached = 1
    if #scored == 1 or depth <= 1 then
        return { r = scored[1].r, c = scored[1].c }
    end

    local top_n = math.min(SEARCH_WIDTH, #scored)
    for i = 1, top_n do
        local m = scored[i]
        grid[m.r][m.c] = player
        local wins = completesFive(grid, n, m.r, m.c, player)
        grid[m.r][m.c] = 0
        if wins then return { r = m.r, c = m.c } end
    end

    -- Iterative deepening: depth 1 is the ordering above; each deeper
    -- iteration replaces the choice only once it has finished.
    local best_move = { r = scored[1].r, c = scored[1].c }
    local saved = {}
    for r = 1, n do
        saved[r] = {}
        for c = 1, n do saved[r][c] = grid[r][c] end
    end
    ai_nodes = 0
    ai_deadline = budget and (clock() + budget * GomokuBoard.AI_TIME_SCALE) or math.huge
    for d = 2, depth do
        local ok, res = pcall(searchRoot, grid, n, scored, top_n, d, player)
        if not ok then
            if res ~= AI_ABORT then ai_deadline = math.huge; error(res, 0) end
            for r = 1, n do for c = 1, n do grid[r][c] = saved[r][c] end end
            break
        end
        best_move = res
        self.ai_depth_reached = d
    end
    ai_deadline = math.huge
    return best_move
end

-- Plays at a named level ("easy" / "medium" / "hard"), within its budget.
function GomokuBoard:getAIMoveForLevel(level)
    local L = GomokuBoard.AI_LEVELS[level] or GomokuBoard.AI_LEVELS.medium
    return self:getAIMove(L.depth, L.budget)
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
