local t = require("tests.test_helper")
local victory = require("src.victory")

local function fakeCiv(state)
  return {
    turn = function() return state.turn end,
    victory = function() return state.victory end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

local function decided()
  return {
    winner_team = 1,
    winner_civs = { "Rome" },
    victory = "VICTORY_SPACE_RACE",
    winning_turn = 300,
  }
end

t.test("logs nothing while the game is undecided", function()
  local lines, sink = captureSink()
  local watch = victory.new(fakeCiv({ turn = 142 }), sink)
  watch()
  t.assert_deep_equal({}, lines)
end)

t.test("emits game_ended once the game has a winner", function()
  local lines, sink = captureSink()
  local watch = victory.new(fakeCiv({ turn = 300, victory = decided() }), sink)
  watch()
  t.assert_deep_equal({
    '{"event":"game_ended","turn":300,"victory":"VICTORY_SPACE_RACE",' ..
      '"winner_civs":["Rome"],"winner_team":1,"winning_turn":300}',
  }, lines)
end)

-- testVictory runs once per game turn and again on player death, team
-- change and a concluded Congress vote, so the hook keeps firing after
-- the game is over (CvGame.cpp:9943 sits above the getVictory() guard).
t.test("emits game_ended only once, however often the hook fires", function()
  local lines, sink = captureSink()
  local watch = victory.new(fakeCiv({ turn = 300, victory = decided() }), sink)
  watch()
  watch()
  watch()
  t.assert_equal(1, #lines)
end)

-- The DLL calls this hook "to allow a Lua script to set the victory
-- state" (CvGame.cpp:9937), so the watcher must stay a pure observer.
t.test("the watcher returns nothing, so it cannot set the victory state", function()
  local _, sink = captureSink()
  local watch = victory.new(fakeCiv({ turn = 300, victory = decided() }), sink)
  t.assert_nil(watch())
end)

t.test("a read error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = { turn = function() return 142 end, victory = function() error("boom") end }
  local watch = victory.new(civ, sink)
  watch()
  t.assert_match('"event":"logger_error"', lines[1])
end)
