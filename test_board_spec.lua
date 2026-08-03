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
