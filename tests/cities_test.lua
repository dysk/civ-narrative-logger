local t = require("tests.test_helper")
local cities = require("src.cities")

local function fakeCiv(statsByPlayer)
  return {
    turn = function() return 142 end,
    civName = function(playerId) return playerId == 0 and "Poland" or "Rome" end,
    cityStats = function(playerId) return statsByPlayer[playerId] or {} end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

t.test("emits one city_snapshot per city, carrying turn and owner", function()
  local lines, sink = captureSink()
  local poll = cities.new(fakeCiv({ [0] = {
    { city = "Warsaw", population = 12 },
    { city = "Krakow", population = 5 },
  } }), sink)
  poll(0)
  t.assert_deep_equal({
    '{"city":"Warsaw","civ":"Poland","event":"city_snapshot","population":12,"turn":142}',
    '{"city":"Krakow","civ":"Poland","event":"city_snapshot","population":5,"turn":142}',
  }, lines)
end)

t.test("logs nothing for a player without cities", function()
  local lines, sink = captureSink()
  cities.new(fakeCiv({ [0] = {} }), sink)(0)
  t.assert_deep_equal({}, lines)
end)

-- Unlike the census and the congress, this poll is per player and holds
-- no state: every city is written every turn, and nothing is diffed.
t.test("writes the same cities again on the next turn", function()
  local lines, sink = captureSink()
  local poll = cities.new(fakeCiv({ [0] = { { city = "Warsaw" } } }), sink)
  poll(0)
  poll(0)
  t.assert_equal(2, #lines)
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 142 end,
    civName = function() return "Poland" end,
    cityStats = function() error("boom") end,
  }
  cities.new(civ, sink)(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
