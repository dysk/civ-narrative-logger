local t = require("tests.test_helper")
local roster = require("src.roster")

local function fakeCiv(state)
  return {
    turn = function() return state.turn end,
    livingMajors = function() return state.majors end,
    capitalHolder = function(playerId) return (state.capitalHolders or {})[playerId] end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

t.test("logs nothing on the first poll, which is only a baseline", function()
  local lines, sink = captureSink()
  roster.new(fakeCiv({ turn = 10, majors = { [0] = "Poland" } }), sink)(0)
  t.assert_deep_equal({}, lines)
end)

t.test("logs nothing while every major is still standing", function()
  local lines, sink = captureSink()
  local state = { turn = 10, majors = { [0] = "Poland", [1] = "Rome" } }
  local poll = roster.new(fakeCiv(state), sink)
  poll(0)
  state.turn = 11
  poll(0)
  t.assert_deep_equal({}, lines)
end)

-- civ.playerStats returns nil for a dead player, so without this the
-- snapshot stream simply stops and nothing says why.
t.test("emits player_eliminated naming who holds the fallen capital", function()
  local lines, sink = captureSink()
  local state = {
    turn = 10,
    majors = { [0] = "Poland", [1] = "Rome" },
    capitalHolders = { [1] = "Poland" },
  }
  local poll = roster.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.majors = 11, { [0] = "Poland" }
  poll(0)
  t.assert_deep_equal({
    '{"capital_held_by":"Poland","civ":"Rome","event":"player_eliminated","turn":11}',
  }, lines)
end)

t.test("omits the holder when the fallen capital was razed", function()
  local lines, sink = captureSink()
  local state = { turn = 10, majors = { [0] = "Poland", [1] = "Rome" } }
  local poll = roster.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.majors = 11, { [0] = "Poland" }
  poll(0)
  t.assert_deep_equal({
    '{"civ":"Rome","event":"player_eliminated","turn":11}',
  }, lines)
end)

-- PlayerDoTurn fires once per living player; the roster is game-global.
t.test("polls once per turn, however many players take theirs", function()
  local lines, sink = captureSink()
  local state = { turn = 10, majors = { [0] = "Poland", [1] = "Rome" } }
  local poll = roster.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.majors = 11, { [0] = "Poland" }
  poll(0)
  poll(1)
  t.assert_equal(1, #lines)
end)

t.test("two civs falling on the same turn come out in a stable order", function()
  local lines, sink = captureSink()
  local state = {
    turn = 10,
    majors = { [0] = "Poland", [1] = "Rome", [2] = "Egypt" },
  }
  local poll = roster.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.majors = 11, { [0] = "Poland" }
  poll(0)
  t.assert_deep_equal({
    '{"civ":"Rome","event":"player_eliminated","turn":11}',
    '{"civ":"Egypt","event":"player_eliminated","turn":11}',
  }, lines)
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 10 end,
    livingMajors = function() error("boom") end,
    capitalHolder = function() return nil end,
  }
  roster.new(civ, sink)(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
