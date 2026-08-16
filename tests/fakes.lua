local M = {}

function M.modding(storedValue)
  return {
    OpenUserData = function(name, version)
      assert(name == "civ-narrative-logger" and version == 1)
      return { GetValue = function(key) return key == "enabled" and storedValue or nil end }
    end,
    GetActivatedMods = function()
      return { { ID = "b2be3c8b-5f00-4d3e-9c00-000000000000", Version = 34 } }
    end,
  }
end

-- Everything main.start needs from the game, small enough for one
-- player. Returns the globals plus the captured hook handlers and
-- printed lines.
function M.gameGlobals(storedFlag)
  local handlers, lines = {}, {}
  local g = {
    Modding = M.modding(storedFlag),
    GameEvents = setmetatable({}, {
      __index = function(_, name)
        return { Add = function(fn) handlers[name] = fn end }
      end,
    }),
    print = function(line) table.insert(lines, line) end,
    Game = {
      GetGameTurn = function() return 0 end,
      GetGameSpeedType = function() return 1 end,
      GetMaxTurns = function() return 330 end,
      GetStartEra = function() return 2 end,
    },
    PreGame = { GetMapScript = function() return "Lekmap.lua" end },
    Map = {
      GetWorldSize = function() return 1 end,
      GetGridSize = function() return 44, 26 end,
    },
    GameDefines = { MAX_CIV_PLAYERS = 1 },
    Players = {
      [0] = {
        IsAlive = function() return true end,
        IsMinorCiv = function() return false end,
        IsBarbarian = function() return false end,
        GetCivilizationShortDescription = function() return "Poland" end,
        GetName = function() return "dysk" end,
        IsHuman = function() return true end,
        GetHandicapType = function() return 5 end,
      },
    },
    GameInfo = {
      Worlds = { [1] = { Type = "WORLDSIZE_STANDARD" } },
      GameSpeeds = { [1] = { Type = "GAMESPEED_QUICK" } },
      Eras = { [2] = { Type = "ERA_CLASSICAL" } },
      HandicapInfos = { [5] = { Type = "HANDICAP_KING" } },
    },
  }
  return g, handlers, lines
end

return M
