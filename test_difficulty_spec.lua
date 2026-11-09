-- Difficulty guarantees of the Gomoku computer opponent: the level table is
-- ordered, every level plays legal moves, completes its own five and blocks
-- the opponent's four, Medium and Hard block an open three, Hard finds a
-- four-three, the same seed gives the same game, and each level stays
-- within its think time at Kobo speed. No full matches.
local DIR = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = DIR .. "?.lua;" .. package.path

describe("Gomoku difficulty", function()
    local Board

    setup(function()
        Board = require("board")
    end)

    after_each(function()
        Board.AI_TIME_SCALE = 1
    end)

    local IDS = { "easy", "medium", "hard" }

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

    -- Seeded random positions of `stones` stones, still in play.
    local function randomPosition(seed, stones)
        local b = Board:new()
        math.randomseed(seed)
        for _ = 1, stones do
            if b.status ~= "playing" then break end
            local c = b:getCandidates()
            local m = c[math.random(#c)]
            b:placeStone(m.r, m.c)
        end
        return b
    end

    it("are three distinct settings, Hard searching deepest", function()
        local L = Board.AI_LEVELS
        assert.are.equal(0, L.easy.depth)
        assert.is_true(L.easy.noise > 0)
        assert.is_true(L.medium.depth >= 2)
        assert.is_true(L.hard.depth > L.medium.depth)
        assert.is_true(L.hard.budget <= 2.5)
        assert.is_nil(L.hard.noise)
        assert.is_true(L.easy.noise > L.medium.noise)
        assert.is_true(L.easy.budget <= L.medium.budget and L.medium.budget <= L.hard.budget)
    end)

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

    it("every level completes its own five", function()
        for _, lv in ipairs(IDS) do
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
        for _, lv in ipairs(IDS) do
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

    it("every level plays legal moves in random positions", function()
        Board.AI_TIME_SCALE = 0.04
        for seed = 1, 6 do
            local b = randomPosition(seed, 6 + 4 * seed)
            if b.status == "playing" then
                for _, lv in ipairs(IDS) do
                    local m = b:getAIMoveForLevel(lv)
                    assert.is_not_nil(m)
                    assert.are.equal(0, b.grid[m.r][m.c])
                end
            end
        end
    end)

    it("keeps a hard move within its budget at Kobo speed", function()
        -- 0.04 ~ a Kobo Aura on a desktop: 2.3 s of Kobo is ~0.09 s here.
        local b = randomPosition(7, 14)
        Board.AI_TIME_SCALE = 0.04
        local t0 = os.clock()
        local move = b:getAIMoveForLevel("hard")
        local dt = os.clock() - t0
        assert.is_not_nil(move)
        assert.is_true(dt < 0.15)
        assert.is_true(b.ai_depth_reached >= 2)
    end)

    it("keeps every level within its budget at Kobo speed", function()
        Board.AI_TIME_SCALE = 0.04
        local worst = 0
        for seed = 11, 14 do
            local b = randomPosition(seed, 2 + 6 * (seed - 10))
            if b.status == "playing" then
                for _, lv in ipairs(IDS) do
                    local t0 = os.clock()
                    b:getAIMoveForLevel(lv)
                    local dt = (os.clock() - t0) * 25
                    if dt > worst then worst = dt end
                end
            end
        end
        assert.is_true(worst <= 2.5, string.format("slowest Kobo move %.2f s", worst))
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

    it("Easy varies with the seed", function()
        local seen, distinct = {}, 0
        for seed = 1, 4 do
            math.randomseed(seed)
            local b = Board:new()
            local seq = {}
            for _ = 1, 8 do
                local m = b:getAIMoveForLevel("easy")
                b:placeStone(m.r, m.c)
                seq[#seq + 1] = m.r .. "," .. m.c
            end
            local s = table.concat(seq, " ")
            if not seen[s] then seen[s] = true; distinct = distinct + 1 end
        end
        assert.is_true(distinct >= 2, "Easy played the same line for every seed")
    end)
end)
