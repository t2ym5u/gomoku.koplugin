-- ---------------------------------------------------------------------------
-- GomokuScreen — full-screen UI for Gomoku (five in a row), 15x15
-- ---------------------------------------------------------------------------

local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local ButtonTable     = require("ui/widget/buttontable")
local Device          = require("device")
local FrameContainer  = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan  = require("ui/widget/horizontalspan")
local Size            = require("ui/size")
local UIManager       = require("ui/uimanager")
local VerticalGroup   = require("ui/widget/verticalgroup")
local VerticalSpan    = require("ui/widget/verticalspan")
local _               = require("gettext")

local MenuHelper  = require("menu_helper")
local ScreenBase  = require("screen_base")

local GomokuBoard       = lrequire("board")
local GomokuBoardWidget = lrequire("board_widget")

local DeviceScreen = Device.screen

-- Difficulty → minimax depth (Gomoku AI is expensive on large boards, keep shallow)
local DIFF_DEPTH = { easy = 1, medium = 2, hard = 3 }

local GAME_RULES_EN = _([[
Gomoku — Rules

Two players alternate placing stones on the 15×15 board.
Black plays first.

The goal is to place 5 of your stones in an unbroken row
— horizontally, vertically, or diagonally.

The first player to achieve this wins.
]])

local GAME_RULES_FR = [[
Gomoku — Règles

Les deux joueurs placent alternativement des pierres sur le plateau 15×15.
Les Noirs jouent en premier.

Le but est de placer 5 pierres de sa couleur alignées sans interruption
— horizontalement, verticalement ou en diagonale.

Le premier joueur à y parvenir gagne.
]]

local GomokuScreen = ScreenBase:extend{}

-- ---------------------------------------------------------------------------
-- Lifecycle
-- ---------------------------------------------------------------------------

function GomokuScreen:init()
    local state = self.plugin:loadState()
    self.board  = GomokuBoard:new()
    if not self.board:load(state) then
        self.board:reset()
    end
    ScreenBase.init(self)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

function GomokuScreen:serializeState()
    return self.board:serialize()
end

-- ---------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------

function GomokuScreen:buildLayout()
    self.board_widget = GomokuBoardWidget:new{
        board        = self.board,
        onCellAction = function(r, c) self:onCellAction(r, c) end,
    }

    local is_landscape = self:isLandscape()
    local sw = DeviceScreen:getWidth()

    local board_frame = FrameContainer:new{
        padding = Size.padding.default,
        margin  = Size.margin.default,
        self.board_widget,
    }

    local board_frame_size = self.board_widget.size
        + (Size.padding.default + Size.margin.default) * 2

    local button_width
    if is_landscape then
        local right_w = sw - board_frame_size - Size.span.horizontal_default * 2
        button_width  = math.max(right_w - Size.span.horizontal_default, 100)
    else
        button_width = math.floor(sw * 0.92)
    end

    local buttons = ButtonTable:new{
        width                 = button_width,
        shrink_unneeded_width = true,
        buttons = {{
            { text = _("Nouveau"),
              callback = function() self:onNewGame() end },
            { text = self:_getPlayersButtonText(),
              callback = function() self:openPlayersMenu() end,
              id = "players_btn" },
            { text = self:_getDiffButtonText(),
              callback = function() self:openDifficultyMenu() end,
              id = "diff_btn" },
            { text = _("Annuler"),
              callback = function() self:onUndo() end },
            self:makeRulesButtonConfig(GAME_RULES_EN, GAME_RULES_FR),
            self:makeCloseButtonConfig(),
        }},
    }

    self.top_buttons = buttons

    if is_landscape then
        local right_panel = VerticalGroup:new{
            align = "center",
            buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
        }
        self.layout = HorizontalGroup:new{
            align = "center",
            board_frame,
            HorizontalSpan:new{ width = Size.span.horizontal_default },
            right_panel,
        }
    else
        self.layout = VerticalGroup:new{
            align = "center",
            VerticalSpan:new{ width = Size.span.vertical_large },
            buttons,
            VerticalSpan:new{ width = Size.span.vertical_large },
            board_frame,
            VerticalSpan:new{ width = Size.span.vertical_large },
            self.status_text,
            VerticalSpan:new{ width = Size.span.vertical_large },
        }
    end

    self[1] = self.layout
    self:updateStatus()
end

-- ---------------------------------------------------------------------------
-- AI helpers
-- ---------------------------------------------------------------------------

function GomokuScreen:_isAITurn()
    if self.board.status ~= "playing" then return false end
    local players = self.plugin:getSetting("players", 1)
    if players ~= 1 then return false end
    local player_stone = self.plugin:getSetting("player_stone", 1)
    return self.board.turn ~= player_stone
end

function GomokuScreen:_isHumanTurn()
    local players = self.plugin:getSetting("players", 1)
    if players ~= 1 then return true end
    local player_stone = self.plugin:getSetting("player_stone", 1)
    return self.board.turn == player_stone
end

-- ---------------------------------------------------------------------------
-- Cell interaction
-- ---------------------------------------------------------------------------

function GomokuScreen:onCellAction(r, c)
    local board = self.board
    if board.status ~= "playing" then return end
    if not self:_isHumanTurn() then return end

    local result = board:placeStone(r, c)
    if result == "occupied" then return end

    self.board_widget:refresh()
    self.plugin:saveState(self:serializeState())
    self:updateStatus()

    if result == "won" then
        self:onGameEnd()
    elseif result == "draw" then
        self:showMessage(_("Match nul !"), 3)
    elseif self:_isAITurn() then
        self:triggerAI()
    end
end

-- ---------------------------------------------------------------------------
-- Undo
-- ---------------------------------------------------------------------------

function GomokuScreen:onUndo()
    if self.board.status ~= "playing" then return end
    local players = self.plugin:getSetting("players", 1)
    local ok = self.board:undoMove()
    if ok and players == 1 then self.board:undoMove() end
    if ok then
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())
        self:updateStatus()
    end
end

-- ---------------------------------------------------------------------------
-- AI
-- ---------------------------------------------------------------------------

function GomokuScreen:triggerAI()
    if self.board.status ~= "playing" then return end
    if not self:_isAITurn() then return end

    self:updateStatus(_("L'IA réfléchit..."))
    local diff  = self.plugin:getSetting("difficulty", "medium")
    local depth = DIFF_DEPTH[diff] or 2

    UIManager:scheduleIn(0.05, function()
        if self.board.status ~= "playing" then return end
        local move = self.board:getAIMove(depth)
        if not move then return end

        local result = self.board:placeStone(move.r, move.c)
        self.board_widget:refresh()
        self.plugin:saveState(self:serializeState())
        self:updateStatus()

        if result == "won" then
            self:onGameEnd()
        elseif result == "draw" then
            self:showMessage(_("Match nul !"), 3)
        end
    end)
end

-- ---------------------------------------------------------------------------
-- New game
-- ---------------------------------------------------------------------------

function GomokuScreen:onNewGame()
    self.board = GomokuBoard:new()
    self.board:reset()
    self.plugin:saveState(self.board:serialize())
    self:buildLayout()
    UIManager:setDirty(self, function() return "ui", self.dimen end)
    if self:_isAITurn() then
        UIManager:scheduleIn(0.1, function() self:triggerAI() end)
    end
end

-- ---------------------------------------------------------------------------
-- Game end
-- ---------------------------------------------------------------------------

function GomokuScreen:onGameEnd()
    local winner = self.board.winner
    local msg = winner == 1 and _("Les Noirs gagnent !") or _("Les Blancs gagnent !")
    self:showMessage(msg, 4)
end

-- ---------------------------------------------------------------------------
-- Status bar
-- ---------------------------------------------------------------------------

function GomokuScreen:updateStatus(msg)
    local status
    if msg then
        status = msg
    elseif self.board.status == "ended" then
        local winner = self.board.winner
        if winner == 1 then
            status = _("Les Noirs gagnent !")
        elseif winner == 2 then
            status = _("Les Blancs gagnent !")
        else
            status = _("Match nul !")
        end
    else
        local turn = (self.board.turn == 1) and _("Noirs") or _("Blancs")
        local players = self.plugin:getSetting("players", 1)
        if players == 1 then
            local diff   = self.plugin:getSetting("difficulty", "medium")
            local dlabel = MenuHelper.DIFFICULTY_LABELS[diff] or diff
            status = string.format("%s joue  %s", turn, dlabel)
        else
            status = string.format("%s joue", turn)
        end
    end
    ScreenBase.updateStatus(self, status)
end

-- ---------------------------------------------------------------------------
-- Button helpers
-- ---------------------------------------------------------------------------

function GomokuScreen:_getPlayersButtonText()
    local players = self.plugin:getSetting("players", 1)
    return players == 1 and _("1 joueur") or _("2 joueurs")
end

function GomokuScreen:_getDiffButtonText()
    local diff = self.plugin:getSetting("difficulty", "medium")
    return MenuHelper.DIFFICULTY_LABELS[diff] or diff
end

-- ---------------------------------------------------------------------------
-- Menus
-- ---------------------------------------------------------------------------

function GomokuScreen:openPlayersMenu()
    MenuHelper.openPickerMenu{
        title      = _("Mode de jeu"),
        items      = {
            { id = 1, text = _("1 joueur (contre IA)") },
            { id = 2, text = _("2 joueurs") },
        },
        current_id = self.plugin:getSetting("players", 1),
        on_select  = function(id)
            self.plugin:saveSetting("players", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("players_btn")
            if btn then btn:setText(self:_getPlayersButtonText(), btn.width) end
            self:updateStatus()
            self:onNewGame()
        end,
        parent = self,
    }
end

function GomokuScreen:openDifficultyMenu()
    MenuHelper.openDifficultyMenu{
        current   = self.plugin:getSetting("difficulty", "medium"),
        on_select = function(id)
            self.plugin:saveSetting("difficulty", id)
            local btn = self.top_buttons and self.top_buttons:getButtonById("diff_btn")
            if btn then btn:setText(self:_getDiffButtonText(), btn.width) end
            self:updateStatus()
        end,
        parent = self,
    }
end

return GomokuScreen
