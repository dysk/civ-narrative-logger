local t = require("tests.test_helper")
local main = require("src.main")

local function fakeModding(storedValue)
  return {
    OpenUserData = function(name, version)
      assert(name == "civ-narrative-logger" and version == 1)
      return { GetValue = function(key) return key == "enabled" and storedValue or nil end }
    end,
  }
end

t.test("enabled when the stored flag is 1", function()
  t.assert_equal(true, main.enabled(fakeModding(1)))
end)

t.test("enabled when the stored flag is the string '1'", function()
  t.assert_equal(true, main.enabled(fakeModding("1")))
end)

t.test("disabled when the flag is missing", function()
  t.assert_equal(false, main.enabled(fakeModding(nil)))
end)

local function fakeGameGlobals(storedFlag)
  local handlers, lines = {}, {}
  local g = {
    Modding = fakeModding(storedFlag),
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
    Map = { GetWorldSize = function() return 1 end },
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

t.test("start does nothing when logging is not enabled", function()
  local g, handlers, lines = fakeGameGlobals(nil)
  main.start(g)
  t.assert_deep_equal({ handlers = {}, lines = {} },
    { handlers = handlers, lines = lines })
end)

t.test("start attaches the hooks when enabled", function()
  local g, handlers = fakeGameGlobals(1)
  main.start(g)
  t.assert_equal("function", type(handlers.DeclareWar))
end)

t.test("start emits a prefixed session_started record when enabled", function()
  local g, _, lines = fakeGameGlobals(1)
  main.start(g)
  t.assert_equal("CIVLOG|", lines[1]:sub(1, 7))
  t.assert_match('"event":"session_started"', lines[1])
end)
