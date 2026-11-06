local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("GomokuBoard", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    describe("new / reset", function()
        it("starts with an empty 15x15 board and player 1 to move", function()
            local b = Board:new()
            assert.are.equal(15, b.n)
            assert.are.equal(1, b.turn)
            assert.are.equal("playing", b.status)
            for r = 1, b.n do
                for c = 1, b.n do
                    assert.are.equal(0, b.grid[r][c])
                end
            end
        end)
    end)

    describe("placeStone", function()
        it("places a stone, records history and switches turn", function()
            local b = Board:new()
            assert.are.equal("ok", b:placeStone(8, 8))
            assert.are.equal(1, b.grid[8][8])
            assert.are.equal(2, b.turn)
            assert.are.equal(1, #b.history)
        end)

        it("refuses to place on an occupied cell", function()
            local b = Board:new()
            b:placeStone(8, 8)
            assert.are.equal("occupied", b:placeStone(8, 8))
        end)

        it("detects 5 in a row and ends the game", function()
            local b = Board:new()
            -- Black plays a horizontal run at row 1; white plays elsewhere.
            b:placeStone(1, 1); b:placeStone(2, 1)
            b:placeStone(1, 2); b:placeStone(2, 2)
            b:placeStone(1, 3); b:placeStone(2, 3)
            b:placeStone(1, 4); b:placeStone(2, 4)
            local result = b:placeStone(1, 5)
            assert.are.equal("won", result)
            assert.are.equal("ended", b.status)
            assert.are.equal(1, b.winner)
        end)
    end)

    describe("undoMove", function()
        it("removes the last stone and restores the turn", function()
            local b = Board:new()
            b:placeStone(8, 8)
            assert.is_true(b:undoMove())
            assert.are.equal(0, b.grid[8][8])
            assert.are.equal(1, b.turn)
            assert.are.equal("playing", b.status)
        end)

        it("returns false when there is no history", function()
            local b = Board:new()
            assert.is_false(b:undoMove())
        end)
    end)

    describe("getCandidates", function()
        it("returns the center on an empty board", function()
            local b = Board:new()
            local cands = b:getCandidates()
            assert.are.equal(1, #cands)
            assert.are.equal(8, cands[1].r)
            assert.are.equal(8, cands[1].c)
        end)

        it("returns only empty cells near existing stones", function()
            local b = Board:new()
            b:placeStone(8, 8)
            for _, cand in ipairs(b:getCandidates()) do
                assert.are.equal(0, b.grid[cand.r][cand.c])
                assert.is_true(math.abs(cand.r - 8) <= 2 and math.abs(cand.c - 8) <= 2)
            end
        end)
    end)

    describe("getAIMove", function()
        it("takes the winning move when four in a row are open", function()
            local b = Board:new()
            b:placeStone(1, 1); b:placeStone(5, 5)
            b:placeStone(1, 2); b:placeStone(5, 6)
            b:placeStone(1, 3); b:placeStone(5, 7)
            b:placeStone(1, 4); b:placeStone(5, 8)
            -- Black to move with an open four on row 1, cols 1-4.
            local move = b:getAIMove(1)
            assert.is_not_nil(move)
            assert.are.equal(1, move.r)
            assert.is_true(move.c == 5 or move.c == 0)
        end)
    end)

    describe("AI time budget", function()
        local function midgame()
            local b = Board:new()
            math.randomseed(7)
            for _ = 1, 14 do
                local c = b:getCandidates()
                local m = c[math.random(#c)]
                b:placeStone(m.r, m.c)
            end
            return b
        end

        it("still returns a legal move when the budget is already spent", function()
            local b = midgame()
            local scale = Board.AI_TIME_SCALE
            Board.AI_TIME_SCALE = 0
            local move = b:getAIMoveForLevel("hard")
            Board.AI_TIME_SCALE = scale
            assert.is_not_nil(move)
            assert.are.equal(0, b.grid[move.r][move.c])
            assert.is_true(b.ai_depth_reached <= 1)
        end)

        it("leaves the board untouched after an interrupted search", function()
            local b = midgame()
            local before = b:serialize()
            local scale = Board.AI_TIME_SCALE
            Board.AI_TIME_SCALE = 0
            b:getAIMoveForLevel("hard")
            Board.AI_TIME_SCALE = scale
            assert.are.same(before, b:serialize())
        end)

        it("keeps a hard move within its budget at Kobo speed", function()
            -- 0.04 ~ a Kobo Aura on a desktop: 2.3 s of Kobo is ~0.09 s here.
            local b = midgame()
            local scale = Board.AI_TIME_SCALE
            Board.AI_TIME_SCALE = 0.04
            local t0 = os.clock()
            local move = b:getAIMoveForLevel("hard")
            local dt = os.clock() - t0
            Board.AI_TIME_SCALE = scale
            assert.is_not_nil(move)
            assert.is_true(dt < 0.15)
            assert.is_true(b.ai_depth_reached >= 2)
        end)
    end)

    describe("AI levels", function()
        -- Builds a position from lists of black and white stones; black
        -- (player 1) to move unless `turn` says otherwise.
        local function position(black, white, turn)
            local b = Board:new()
            for _, p in ipairs(black) do b.grid[p[1]][p[2]] = 1 end
            for _, p in ipairs(white) do b.grid[p[1]][p[2]] = 2 end
            b.turn = turn or 1
            return b
        end
        local FAR_W = { {1, 1}, {1, 15}, {15, 1}, {15, 15} }

        it("are three distinct settings, Hard searching deepest", function()
            local L = Board.AI_LEVELS
            assert.are.equal(0, L.easy.depth)
            assert.is_true(L.easy.noise > 0)
            assert.is_true(L.medium.depth >= 2)
            assert.is_true(L.hard.depth > L.medium.depth)
            assert.is_true(L.hard.budget <= 2.5)
            assert.is_nil(L.hard.noise)
        end)

        it("line-shape table matches the reference classifier", function()
        local function classifyKey(key)
            local L = {}
            local k = key
            for j = 1, 9 do
                if j == 5 then L[j] = 1 else L[j] = k % 3; k = (k - k % 3) / 3 end
            end
            local function isFive()
                for s = 1, 5 do
                    local ok = true
                    for t = s, s + 4 do if L[t] ~= 1 then ok = false break end end
                    if ok then return true end
                end
                return false
            end
            local function winPoints()
                local n = 0
                for e = 1, 9 do
                    if L[e] == 0 then
                        L[e] = 1
                        if isFive() then n = n + 1 end
                        L[e] = 0
                    end
                end
                return n
            end
            local function threeLevel()   -- 5 open three, 4 closed three, 0 else
                local best = 0
                for e = 1, 9 do
                    if L[e] == 0 then
                        L[e] = 1
                        local w = winPoints()
                        L[e] = 0
                        if w >= 2 then return 5 end
                        if w == 1 then best = 4 end
                    end
                end
                return best
            end
            if isFive() then return 8 end
            local w = winPoints()
            if w >= 2 then return 7 end
            if w == 1 then return 6 end
            local t = threeLevel()
            if t > 0 then return t end
            local two = 0
            for e = 1, 9 do
                if L[e] == 0 then
                    L[e] = 1
                    local t2 = threeLevel()
                    L[e] = 0
                    if t2 == 5 then return 3 end
                    if t2 == 4 then two = 2 end
                end
            end
            if two > 0 then return two end
            for s = 1, 5 do
                local ok = true
                for t = s, s + 4 do if L[t] == 2 then ok = false break end end
                if ok then return 1 end
            end
            return 0
        end
            local s = Board._patternString()
            assert.are.equal(6561, #s)
            for key = 0, 6560 do
                assert.are.equal(classifyKey(key), s:byte(key + 1) - 48)
            end
        end)

        it("every level completes its own five", function()
            for _, lv in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, 10 do
                    math.randomseed(seed)
                    local b = position({ {8, 4}, {8, 5}, {8, 6}, {8, 7} },
                                       { {7, 4}, {7, 5}, {7, 6}, {7, 7} })
                    local m = b:getAIMoveForLevel(lv)
                    assert.are.equal(8, m.r)
                    assert.is_true(m.c == 3 or m.c == 8)
                end
            end
        end)

        it("every level blocks the opponent's four", function()
            for _, lv in ipairs({ "easy", "medium", "hard" }) do
                for seed = 1, 10 do
                    math.randomseed(seed)
                    -- White threatens (8,8) after a closed four 8,4..8,7.
                    local b = position({ {8, 3}, {2, 2}, {2, 13}, {13, 2} },
                                       { {8, 4}, {8, 5}, {8, 6}, {8, 7} })
                    local m = b:getAIMoveForLevel(lv)
                    assert.are.same({ 8, 8 }, { m.r, m.c })
                end
            end
        end)

        it("Medium and Hard block an open three", function()
            for _, lv in ipairs({ "medium", "hard" }) do
                math.randomseed(3)
                local b = position({ {2, 2}, {2, 13}, {13, 2} },
                                   { {8, 6}, {8, 7}, {8, 8} })
                local m = b:getAIMoveForLevel(lv)
                assert.are.equal(8, m.r)
                assert.is_true(m.c == 4 or m.c == 5 or m.c == 9 or m.c == 10)
            end
        end)

        it("Hard finds a four-three win", function()
            -- Row 8: a closed three (white at 8,3); column 7: two stones.
            -- 8,7 makes a four and an open three at once.
            local b = position({ {8, 4}, {8, 5}, {8, 6}, {6, 7}, {7, 7} },
                               { {8, 3}, FAR_W[1], FAR_W[2], FAR_W[3], FAR_W[4] })
            local m = b:getAIMoveForLevel("hard")
            assert.are.same({ 8, 7 }, { m.r, m.c })
            assert.is_true(b.ai_value >= 1000000)
        end)

        it("is reproducible for a given random seed", function()
            for _, lv in ipairs({ "easy", "medium" }) do
                local moves = {}
                for run = 1, 2 do
                    math.randomseed(42)
                    local b = Board:new()
                    local seq = {}
                    for _ = 1, 12 do
                        local m = b:getAIMoveForLevel(lv)
                        b:placeStone(m.r, m.c)
                        seq[#seq + 1] = m.r .. "," .. m.c
                    end
                    moves[run] = table.concat(seq, " ")
                end
                assert.are.equal(moves[1], moves[2])
            end
        end)
    end)

    describe("serialize / load", function()
        it("round-trips grid, turn and history", function()
            local b = Board:new()
            b:placeStone(8, 8)
            local data = b:serialize()

            local b2 = Board:new()
            assert.is_true(b2:load(data))
            assert.are.equal(b.turn, b2.turn)
            assert.are.equal(1, b2.grid[8][8])
            assert.are.equal(#b.history, #b2.history)
        end)

        it("load returns false for invalid data", function()
            local b = Board:new()
            assert.is_false(b:load(nil))
            assert.is_false(b:load({}))
        end)
    end)
end)
