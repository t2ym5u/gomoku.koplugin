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

-- ---------------------------------------------------------------------------
-- AI
--
-- Threat-based alpha-beta. Every empty cell near the stones is rated for
-- both players by the line shapes a stone there would make (five, open
-- four, four, open three, ...). The ratings are kept up to date
-- incrementally: a stone only changes the cells within four steps along its
-- four lines. They drive everything:
--   * terminal tests that know whose turn it is: a five to complete wins
--     now, two fives to block lose, an open four to make wins in two;
--   * forcing moves never stop the search: blocking a four is played out
--     even past the depth limit, and at the limit the side to move may
--     still try its fours (a short victory-by-continuous-fours search);
--   * against an open three only the blocks and our own fours are tried;
--   * move ordering by attack + defence at every node, keeping the best few.
-- ---------------------------------------------------------------------------

-- Line shapes, from the point of view of a stone just placed on a cell.
local P_FIVE, P_OPEN_FOUR, P_FOUR = 8, 7, 6
local P_OPEN_THREE = 5
-- 0 dead, 1 one (room for five), 2 closed two, 3 open two, 4 closed three.

-- PATTERN_STRING: one digit per line key. A key encodes the 8 cells around
-- the placed stone on one line (-4..-1, then 1..4), base 3, first cell =
-- lowest digit: 0 empty, 1 own stone, 2 opponent stone or board edge.
-- Generated by the reference classifier in test_board_spec.lua, which checks
-- every entry (computing it here would cost about a second on a Kobo).
local PATTERN_STRING = [[
121342111343564222111111111343564333565786444222222222111111111111111111111111111
333444333555666444333333333555666555777888666444444444222222222222222222222222222
120240000240460000000000000240460000460680000000000000000000000000000000000000000
333343333454564444333333333555565555676786666444444444222222222222222222222222222
555555555666666666555555555777777777888888888666666666444444444444444444444444444
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
333343333343564333333333333444565444565786444444444444222222222222222222222222222
555555555555666555555555555666777666777888666666666666444444444444444444444444444
120240000240460000000000000240460000460680000000000000000000000000000000000000000
555555555555565555555555555666676666676786666666666666444444444444444444444444444
777777777777777777777777777888888888888888888888888888666666666666666666666666666
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342111343564222000000000343564222565786444000000000000000000000000000000000000
333444222555666444000000000555666444777888666000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
232342222454564444000000000454564444676786666000000000000000000000000000000000000
444444444666666666000000000666666666888888888000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
222342222343564333222222222343564333565786444222222222222222222222222222222222222
444444444555666555444444444555666555777888666444444444444444444444444444444444444
120240000240460000000000000240460000460680000000000000000000000000000000000000000
444444444555565555444444444555565555676786666444444444444444444444444444444444444
666666666777777777666666666777777777888888888666666666666666666666666666666666666
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
444444444444565444444444444444565444565786444444444444444444444444444444444444444
666666666666777666666666666666777666777888666666666666666666666666666666666666666
120240000240460000000000000240460000460680000000000000000000000000000000000000000
666666666666676666666666666666676666676786666666666666666666666666666666666666666
888888888888888888888888888888888888888888888888888888888888888888888888888888888
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342111343564222000000000343564222565786444000000000000000000000000000000000000
333444222555666444000000000555666444777888666000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
232342222454564444000000000454564444676786666000000000000000000000000000000000000
444444444666666666000000000666666666888888888000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342111343564222111111111343564333565786444222222222000000000000000000000000000
333444333555666444222222222555666555777888666444444444000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
333343333454564444222222222555565555676786666444444444000000000000000000000000000
555555555666666666444444444777777777888888888666666666000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
222343222343564222222222222444565444565786444444444444000000000000000000000000000
444555444555666444444444444666777666777888666666666666000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
444454444454564444444444444666676666676786666666666666000000000000000000000000000
666666666666666666666666666888888888888888888888888888000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342111343564222000000000343564222565786444000000000000000000000000000000000000
333444222555666444000000000555666444777888666000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
232342222454564444000000000454564444676786666000000000000000000000000000000000000
444444444666666666000000000666666666888888888000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
121342000342564000000000000342564000564786000000000000000000000000000000000000000
222444000444666000000000000444666000666888000000000000000000000000000000000000000
120240000240460000000000000240460000460680000000000000000000000000000000000000000
]]

-- Per-direction weights for the positional score.
local WEIGHT = { [0] = 0, 1, 4, 12, 16, 60, 70, 1000, 10000 }

-- Cell threat levels, combining the four directions.
local L_FIVE, L_OPEN4, L_43, L_33, L_FOUR = 6, 5, 4, 3, 2
local LEVEL_BONUS = { [0] = 0, 0, 0, 2000, 10000, 100000, 1000000 }

local WIN = 10000000

local PAT, LEV, VAL, SUM   -- built on first use

local function buildTables()
    if PAT then return end
    PAT = {}
    local s = PATTERN_STRING:gsub("%s", "")
    for i = 1, #s do PAT[i - 1] = s:byte(i) - 48 end
    LEV, VAL, SUM = {}, {}, {}
    local c = {}
    for k = 0, 6560 do
        local x = k
        for d = 4, 1, -1 do c[d] = x % 9; x = (x - c[d]) / 9 end
        local sum, fives, open4, fours, open3 = 0, 0, 0, 0, 0
        for d = 1, 4 do
            local p = c[d]
            sum = sum + WEIGHT[p]
            if p == P_FIVE then fives = fives + 1
            elseif p == P_OPEN_FOUR then open4 = open4 + 1
            elseif p == P_FOUR then fours = fours + 1
            elseif p == P_OPEN_THREE then open3 = open3 + 1 end
        end
        local lev = 0
        if fives > 0 then lev = L_FIVE
        elseif open4 > 0 or fours >= 2 then lev = L_OPEN4
        elseif fours == 1 and open3 >= 1 then lev = L_43
        elseif open3 >= 2 then lev = L_33
        elseif fours == 1 then lev = L_FOUR
        elseif open3 == 1 then lev = 1 end
        LEV[k] = lev
        SUM[k] = sum
        VAL[k] = sum + LEVEL_BONUS[lev]
    end
end

function GomokuBoard._patternString()
    return (PATTERN_STRING:gsub("%s", ""))
end

-- Search state. The board is padded with four rings of wall (3) so no line
-- walk needs a bounds test.
local W, B, NEAR, STEP, CELLS, NBR
local PD = { {}, {} }          -- PD[player][dir][cell] = line shape code
local KEY = { {}, {} }         -- KEY[player][cell] = the four codes, base 9
local KMUL = { 729, 81, 9, 1 }
local CODE = { [1] = { [0] = 0, 1, 2, 2 }, [2] = { [0] = 0, 2, 1, 2 } }

local function recompute(j, d)
    local s = STEP[d]
    local c1, c2 = CODE[1], CODE[2]
    local k1, k2, m = 0, 0, 1
    for t = -4, 4 do
        if t ~= 0 then
            local v = B[j + t * s]
            k1 = k1 + c1[v] * m
            k2 = k2 + c2[v] * m
            m = m * 3
        end
    end
    local p1, p2 = PAT[k1], PAT[k2]
    local pd1, pd2 = PD[1][d], PD[2][d]
    local mul = KMUL[d]
    KEY[1][j] = KEY[1][j] + (p1 - pd1[j]) * mul
    KEY[2][j] = KEY[2][j] + (p2 - pd2[j]) * mul
    pd1[j], pd2[j] = p1, p2
end

local function setStone(i, v)
    B[i] = v
    local delta = (v ~= 0) and 1 or -1
    for k = 1, #NBR do
        local j = i + NBR[k]
        NEAR[j] = NEAR[j] + delta
    end
    for d = 1, 4 do
        local s = STEP[d]
        for t = -4, 4 do
            if t ~= 0 then
                local j = i + t * s
                if B[j] == 0 then recompute(j, d) end
            end
        end
    end
    if v == 0 then for d = 1, 4 do recompute(i, d) end end
end

local function initState(grid, n)
    buildTables()
    W = n + 8
    B, NEAR, CELLS, NBR = {}, {}, {}, {}
    STEP = { 1, W, W + 1, W - 1 }
    for i = -W, W * W + W do B[i] = 3; NEAR[i] = 0 end
    for dr = -2, 2 do
        for dc = -2, 2 do
            if dr ~= 0 or dc ~= 0 then NBR[#NBR + 1] = dr * W + dc end
        end
    end
    for p = 1, 2 do
        KEY[p] = {}
        for d = 1, 4 do PD[p][d] = {} end
    end
    for r = 1, n do
        for c = 1, n do
            local i = (r + 3) * W + c + 4
            CELLS[#CELLS + 1] = i
            B[i] = 0
            KEY[1][i], KEY[2][i] = 0, 0
            for d = 1, 4 do PD[1][d][i], PD[2][d][i] = 0, 0 end
        end
    end
    for r = 1, n do
        for c = 1, n do
            local v = grid[r][c]
            if v ~= 0 then
                local i = (r + 3) * W + c + 4
                B[i] = v
                for k = 1, #NBR do NEAR[i + NBR[k]] = NEAR[i + NBR[k]] + 1 end
            end
        end
    end
    for _, i in ipairs(CELLS) do
        if B[i] == 0 then for d = 1, 4 do recompute(i, d) end end
    end
end

local function cellOf(i)
    return { r = math.floor(i / W) - 3, c = i % W - 4 }
end

GomokuBoard.AI_LEVELS = {
    --  depth: deepest iteration (0 = no search, rates the cells only);
    --  budget: seconds on a Kobo-class CPU; width: moves tried per inner
    --  node; noise: chance of playing one of the `pick` best moves at random
    --  instead of the best; defence: weight of the opponent's threats when
    --  depth is 0.
    easy   = { depth = 0, budget = 0.5, noise = 0.8, pick = 5, defence = 0.5 },
    medium = { depth = 2, budget = 1.5, width = 8, noise = 0.15, pick = 2 },
    hard   = { depth = 10, budget = 2.3, width = 10 },
}
GomokuBoard.AI_TIME_SCALE = 1

local clock = os.clock
local AI_ABORT = {}
local ai_deadline = math.huge
local ai_nodes = 0
local ai_width = 8
local MAX_PLY = 24
local BUF = {}                 -- per-ply scratch tables
local QUIESCE_WIDTH, QUIESCE_DEPTH = 3, 4

-- Rates every candidate cell for the side to move (s) and the other (o).
-- Returns: winning cell for s (or nil), o's five cells (count, one of them),
-- best levels for s and o, positional sums, s's best cell and how many cells
-- give o an open four. Fills the move list: cells in `mv` (count in mv[0]),
-- ordering scores (attack + 0.9 defence) in `ms`, levels in `mt`.
local function scan(s, mv, ms, mt)
    local KS, KO = KEY[s], KEY[3 - s]
    local LEVt, VALt, SUMt = LEV, VAL, SUM
    local Bt, NEARt = B, NEAR
    local oFiveN, oFive, sMax, oMax, sumS, sumO, n = 0, nil, 0, 0, 0, 0, 0
    local sMaxCell, oOpen4N = nil, 0
    local cells = CELLS
    for k = 1, #cells do
        local i = cells[k]
        if Bt[i] == 0 and NEARt[i] > 0 then
            local ks, ko = KS[i], KO[i]
            local ls, lo = LEVt[ks], LEVt[ko]
            if ls == L_FIVE then return i end
            if lo == L_FIVE then oFiveN = oFiveN + 1; oFive = i end
            if ls > sMax then sMax = ls; sMaxCell = i end
            if lo > oMax then oMax = lo end
            if lo >= L_OPEN4 then oOpen4N = oOpen4N + 1 end
            sumS = sumS + SUMt[ks]
            sumO = sumO + SUMt[ko]
            n = n + 1
            mv[n] = i
            ms[n] = VALt[ks] + VALt[ko] * 0.9
            -- tag the cell with its levels for the defence filter
            mt[n] = ls * 8 + lo
        end
    end
    mv[0] = n
    return nil, oFiveN, oFive, sMax, oMax, sumS, sumO, sMaxCell, oOpen4N
end

-- Keeps the `width` best moves of the scan, best first. When the opponent
-- threatens an open four only blocks (cells where it would make a four or
-- better) and our own fours are kept.
local function pickMoves(mv, ms, mt, width, defend, out, oscore, attackOnly)
    local n, cnt = mv[0], 0
    oscore = oscore or {}
    for k = 1, n do
        local tag = mt[k]
        local ls, lo = math.floor(tag / 8), tag % 8
        if (not defend or lo >= L_FOUR or ls >= L_FOUR)
           and (not attackOnly or ls == L_FOUR or ls == L_43) then
            local sc, i = ms[k], mv[k]
            -- insertion into the top-`width` list
            if cnt < width or sc > oscore[cnt] then
                local pos = (cnt < width) and cnt + 1 or cnt
                while pos > 1 and oscore[pos - 1] < sc do
                    oscore[pos] = oscore[pos - 1]; out[pos] = out[pos - 1]
                    pos = pos - 1
                end
                oscore[pos] = sc; out[pos] = i
                if cnt < width then cnt = cnt + 1 end
            end
        end
    end
    return cnt
end

local function evaluate(sMax, oMax, sumS, sumO, oOpen4N)
    local v = sumS - sumO
    -- The side to move plays first: its 4-3 or 3-3 wins unless the
    -- opponent can interpose fours of its own.
    if oMax < L_FOUR then
        if sMax >= L_43 then v = v + 20000
        elseif sMax == L_33 then v = v + 5000 end
    end
    -- Two open threes (or more) against us and no four to answer with.
    if oOpen4N >= 3 and sMax < L_FOUR then v = v - 20000 end
    return v
end

local negamax
negamax = function(s, depth, alpha, beta, ply)
    ai_nodes = ai_nodes + 1
    if ai_nodes % 16 == 0 and clock() > ai_deadline then error(AI_ABORT, 0) end
    local buf = BUF[ply]
    if not buf then buf = { {}, {}, {}, {}, {} }; BUF[ply] = buf end
    local mv, ms, mt = buf[1], buf[2], buf[3]
    local win, oFiveN, oFive, sMax, oMax, sumS, sumO, _, oOpen4N = scan(s, mv, ms, mt)
    if win then return WIN - ply end
    if oFiveN >= 2 then return -(WIN - ply - 1) end
    local o = 3 - s
    if oFiveN == 1 then
        if ply >= MAX_PLY then return evaluate(sMax, oMax, sumS, sumO, oOpen4N) end
        -- Forced block: played even past the depth limit.
        setStone(oFive, s)
        local v = -negamax(o, depth, -beta, -alpha, ply + 1)
        setStone(oFive, 0)
        return v
    end
    if sMax >= L_OPEN4 then return WIN - ply - 2 end
    if ply >= MAX_PLY then return evaluate(sMax, oMax, sumS, sumO, oOpen4N) end
    local list = buf[4]
    local cnt
    local best = -math.huge
    if depth <= 0 then
        -- Quiescence: stand pat, or try our fours (a 4-3 included). A
        -- four's answer is forced, so this follows victories by continuous
        -- fours at little cost.
        best = evaluate(sMax, oMax, sumS, sumO, oOpen4N)
        if best >= beta or sMax < L_FOUR or depth < -QUIESCE_DEPTH then return best end
        if best > alpha then alpha = best end
        cnt = pickMoves(mv, ms, mt, QUIESCE_WIDTH, false, list, buf[5], true)
    else
        cnt = pickMoves(mv, ms, mt, ai_width, oMax >= L_OPEN4, list, buf[5])
        if cnt == 0 then return evaluate(sMax, oMax, sumS, sumO, oOpen4N) end
    end
    for k = 1, cnt do
        local i = list[k]
        setStone(i, s)
        local v = -negamax(o, depth - 1, -beta, -alpha, ply + 1)
        setStone(i, 0)
        if v > best then
            best = v
            if v > alpha then alpha = v end
            if alpha >= beta then break end
        end
    end
    return best
end

local ROOT_WIDTH = 14

-- Returns the AI's move. `depth`: deepest iteration; `budget`: seconds
-- (scaled by AI_TIME_SCALE; nil = no limit); `opts`: width / noise / pick
-- (see AI_LEVELS). Noise draws from math.random.
function GomokuBoard:getAIMove(depth, budget, opts)
    depth = depth or 1
    opts = opts or {}
    if self.status ~= "playing" then return nil end

    local grid, n = self.grid, self.n
    local player  = self.turn
    self.ai_depth_reached = 0

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

    initState(grid, n)
    local mv, ms, mt = {}, {}, {}
    local win, oFiveN, oFive, sMax, oMax, _, _, sMaxCell = scan(player, mv, ms, mt)
    if win then return cellOf(win) end
    if oFiveN >= 1 then return cellOf(oFive) end              -- must block
    -- An open four wins in two; a noisy level may still overlook it.
    if sMax >= L_OPEN4 and not (opts.noise and opts.noise > 0) then
        return cellOf(sMaxCell)
    end
    if mv[0] == 0 then return nil end

    if depth <= 0 then
        -- No search: a casual player. It takes a five and blocks one, but
        -- otherwise weighs the opponent's threats by `defence` only and,
        -- with probability `noise`, plays one of its `pick` favourites.
        local o, def = 3 - player, opts.defence or 0.9
        for k = 1, mv[0] do
            local i = mv[k]
            ms[k] = VAL[KEY[player][i]] + def * VAL[KEY[o][i]]
        end
        local list = {}
        local cnt = pickMoves(mv, ms, mt, math.max(opts.pick or 1, 1), false, list)
        local k = 1
        if opts.noise and math.random() < opts.noise then k = math.random(cnt) end
        return cellOf(list[k])
    end

    local roots = {}
    local cnt = pickMoves(mv, ms, mt, ROOT_WIDTH, oMax >= L_OPEN4, roots)
    if cnt == 0 then cnt = pickMoves(mv, ms, mt, ROOT_WIDTH, false, roots) end
    for k = cnt + 1, #roots do roots[k] = nil end

    ai_width = opts.width or 8
    ai_nodes = 0
    ai_deadline = budget and (clock() + budget * GomokuBoard.AI_TIME_SCALE) or math.huge
    local o = 3 - player
    local order = roots
    for d = 1, depth do
        local vals = {}
        local ok, err = pcall(function()
            local alpha = -math.huge
            for k = 1, #order do
                local i = order[k]
                setStone(i, player)
                local v = -negamax(o, d - 1, -math.huge, -alpha, 1)
                setStone(i, 0)
                vals[i] = v
                if v > alpha then alpha = v end
            end
        end)
        if not ok then
            if err ~= AI_ABORT then ai_deadline = math.huge; error(err, 0) end
            break
        end
        -- Best first for the next iteration (stable on ties).
        local idx = {}
        for k = 1, #order do idx[k] = k end
        table.sort(idx, function(a, b)
            local va, vb = vals[order[a]], vals[order[b]]
            if va ~= vb then return va > vb end
            return a < b
        end)
        local nxt = {}
        for k = 1, #idx do nxt[k] = order[idx[k]] end
        order = nxt
        self.ai_depth_reached = d
        local bv = vals[order[1]]
        self.ai_value = bv
        -- A forced win found, or every move loses: deeper will not change it.
        if bv >= WIN / 2 or bv <= -WIN / 2 then break end
    end
    ai_deadline = math.huge

    local choice = order[1]
    if opts.noise and opts.noise > 0 and math.random() < opts.noise then
        choice = order[math.random(math.min(opts.pick or 3, #order))]
    end
    return cellOf(choice)
end

-- Plays at a named level ("easy" / "medium" / "hard"), within its budget.
function GomokuBoard:getAIMoveForLevel(level)
    local L = GomokuBoard.AI_LEVELS[level] or GomokuBoard.AI_LEVELS.medium
    return self:getAIMove(L.depth, L.budget, L)
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
