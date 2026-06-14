local _dir = debug.getinfo(1, "S").source:sub(2):match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;" .. _dir .. "common/?.lua;" .. package.path

local function lrequire(name)
    local key = _dir .. name
    if not package.loaded[key] then
        package.loaded[key] = assert(loadfile(_dir .. name .. ".lua"))()
    end
    return package.loaded[key]
end

local PluginBase = require("plugin_base")
local _          = require("gettext")

local GomokuScreen = lrequire("screen")

-- ---------------------------------------------------------------------------
-- GomokuPlugin
-- ---------------------------------------------------------------------------

local GomokuPlugin = PluginBase:extend{
    name      = "gomoku",
    menu_text = _("Gomoku"),
    menu_hint = "tools",
}

function GomokuPlugin:createScreen()
    return GomokuScreen:new{ plugin = self }
end

return GomokuPlugin
