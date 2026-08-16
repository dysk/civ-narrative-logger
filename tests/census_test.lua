local t = require("tests.test_helper")
local census = require("src.census")

local function fakeCiv(citySetsByPlayer)
  return {
    turn = function() return 42 end,
    civName = function(playerId) return playerId == 0 and "Poland" or "Rome" end,
    citySet = function(playerId) return citySetsByPlayer[playerId] end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

t.test("logs nothing the first time a player is polled", function()
  local sets = { [0] = { [3] = { name = "Warsaw", x = 10, y = 20 } } }
  local lines, sink = captureSink()
  local poll = census.new(fakeCiv(sets), sink)
  poll(0)
  t.assert_deep_equal({}, lines)
end)

t.test("logs nothing while the known cities are unchanged", function()
  local sets = { [0] = { [3] = { name = "Warsaw", x = 10, y = 20 } } }
  local lines, sink = captureSink()
  local poll = census.new(fakeCiv(sets), sink)
  poll(0)
  poll(0)
  t.assert_deep_equal({}, lines)
end)

t.test("emits city_destroyed when a known city vanishes", function()
  local sets = { [0] = { [3] = { name = "Warsaw", x = 10, y = 20 } } }
  local lines, sink = captureSink()
  local poll = census.new(fakeCiv(sets), sink)
  poll(0)
  sets[0] = {}
  poll(0)
  t.assert_deep_equal({
    '{"city":"Warsaw","civ":"Poland","event":"city_destroyed","turn":42,"x":10,"y":20}',
  }, lines)
end)

t.test("tracks each player's census independently", function()
  local sets = {
    [0] = { [3] = { name = "Warsaw", x = 10, y = 20 } },
    [1] = { [7] = { name = "Rome", x = 15, y = 22 } },
  }
  local lines, sink = captureSink()
  local poll = census.new(fakeCiv(sets), sink)
  poll(0)
  poll(1)
  sets[1] = {}
  poll(1)
  t.assert_deep_equal({
    '{"city":"Rome","civ":"Rome","event":"city_destroyed","turn":42,"x":15,"y":22}',
  }, lines)
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 42 end,
    civName = function() return "Poland" end,
    citySet = function() error("boom") end,
  }
  local poll = census.new(civ, sink)
  poll(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
