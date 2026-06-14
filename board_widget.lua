-- ---------------------------------------------------------------------------
-- GomokuBoardWidget — renders a 15x15 Gomoku board
-- ---------------------------------------------------------------------------

local Blitbuffer = require("ffi/blitbuffer")
local Geom       = require("ui/geometry")

local gwb            = require("grid_widget_base")
local GridWidgetBase = gwb.GridWidgetBase
local drawLine       = gwb.drawLine

local C_BOARD  = Blitbuffer.COLOR_GRAY_B   -- board background
local C_LINE   = Blitbuffer.COLOR_GRAY_6   -- grid lines
local C_BORDER = Blitbuffer.COLOR_BLACK    -- outer border
local C_BLACK  = Blitbuffer.COLOR_BLACK    -- black stone
local C_WHITE  = Blitbuffer.COLOR_WHITE    -- white stone
local C_WB     = Blitbuffer.COLOR_BLACK    -- white stone border
local C_LAST   = Blitbuffer.COLOR_GRAY_4   -- last-move dot

-- ---------------------------------------------------------------------------
-- GomokuBoardWidget
-- ---------------------------------------------------------------------------

local GomokuBoardWidget = GridWidgetBase:extend{
    board        = nil,
    size_ratio   = 0.85,
    onCellAction = nil,
}

function GomokuBoardWidget:init()
    self.cols = 15
    self.rows = 15
    GridWidgetBase.init(self)
end

function GomokuBoardWidget:onCellTap(row, col)
    if self.onCellAction then self.onCellAction(row, col) end
end

function GomokuBoardWidget:paintTo(bb, x, y)
    self.paint_rect = Geom:new{ x = x, y = y, w = self.dimen.w, h = self.dimen.h }

    local board = self.board
    local grid  = board.grid
    local n     = 15
    local cw    = self.cell_w
    local ch    = self.cell_h

    -- Board background
    bb:paintRect(x, y, self.dimen.w, self.dimen.h, C_BOARD)

    -- Grid lines
    local thin  = 1
    local thick = math.max(2, math.floor(math.min(cw, ch) * 0.06))
    for i = 0, n do
        local lw    = (i == 0 or i == n) and thick or thin
        local color = (i == 0 or i == n) and C_BORDER or C_LINE
        drawLine(bb, x + math.floor(i * cw), y, lw, self.dimen.h, color)
        drawLine(bb, x, y + math.floor(i * ch), self.dimen.w, lw, color)
    end

    -- Draw stones
    local cew = self.cell_w_px
    local ceh = self.cell_h_px
    local pad = math.max(2, math.floor(math.min(cew, ceh) * 0.1))
    local pw  = cew - 2 * pad
    local ph  = ceh - 2 * pad
    local bw  = math.max(1, math.floor(math.min(cew, ceh) * 0.05))
    local dot = math.max(2, math.floor(math.min(pw, ph) * 0.25))

    for r = 1, n do
        for c = 1, n do
            local v = grid[r][c]
            if v ~= 0 then
                local cx = x + math.floor((c - 1) * cw)
                local cy = y + math.floor((r - 1) * ch)

                if v == 1 then
                    bb:paintRect(cx + pad, cy + pad, pw, ph, C_BLACK)
                else
                    bb:paintRect(cx + pad, cy + pad, pw, ph, C_WHITE)
                    bb:paintRect(cx + pad,           cy + pad,           pw, bw, C_WB)
                    bb:paintRect(cx + pad,           cy + pad + ph - bw, pw, bw, C_WB)
                    bb:paintRect(cx + pad,           cy + pad,           bw, ph, C_WB)
                    bb:paintRect(cx + pad + pw - bw, cy + pad,           bw, ph, C_WB)
                end

                -- Last-move indicator
                if board.last_r == r and board.last_c == c then
                    local mx = cx + pad + math.floor((pw - dot) / 2)
                    local my = cy + pad + math.floor((ph - dot) / 2)
                    bb:paintRect(mx, my, dot, dot, C_LAST)
                end
            end
        end
    end
end

return GomokuBoardWidget
