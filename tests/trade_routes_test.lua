local t = require("tests.test_helper")
local tradeRoutes = require("src.trade_routes")

local WARSAW_ANTIUM = {
  civ = "Poland", from_city = "Warsaw", to_civ = "Rome", to_city = "Antium",
  type = "international", domain = "sea", turns_left = 21,
  from_gold = 4.5, to_gold = 2.1, from_science = 1.5, to_science = 0.8,
  from_tourism = 2, to_tourism = 7,
  to_religion = "Christianity", to_pressure = 12,
  from_religion = "Islam", from_pressure = 9,
}

local KRAKOW_WARSAW = {
  civ = "Poland", from_city = "Krakow", to_civ = "Poland", to_city = "Warsaw",
  type = "food", domain = "land", turns_left = 30, to_food = 3,
}

-- Keyed by origin and destination plot, the way the adapter hands them
-- over: Warsaw(10,20) -> Antium(40,3) and Krakow(8,25) -> Warsaw.
local WARSAW_ANTIUM_KEY = "10,20>40,3"
local KRAKOW_WARSAW_KEY = "8,25>10,20"

local function fakeCiv(state)
  return {
    turn = function() return state.turn end,
    tradeRoutes = function() return state.routes end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

local function pollThrough(states)
  local lines, sink = captureSink()
  local state = { turn = states[1].turn, routes = states[1].routes }
  local poll = tradeRoutes.new(fakeCiv(state), sink)
  for _, step in ipairs(states) do
    state.turn, state.routes = step.turn, step.routes
    poll(0)
  end
  return lines
end

-- A reload must not re-announce sixty standing routes; every one of
-- them was announced when it opened.
t.test("logs nothing on the first poll, which is only a baseline", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, routes = { [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM } },
  }))
end)

t.test("logs nothing while the routes are unchanged", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, routes = { [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM } },
    { turn = 11, routes = { [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM } },
  }))
end)

-- What each side earns is the whole point: a route is a deal, and the
-- log has never said what either party got out of one.
t.test("emits trade_route_established with what each side earns", function()
  t.assert_deep_equal({
    '{"civ":"Poland","domain":"sea","event":"trade_route_established",'
      .. '"from_city":"Warsaw","from_gold":4.5,"from_pressure":9,'
      .. '"from_religion":"Islam","from_science":1.5,"from_tourism":2,'
      .. '"to_city":"Antium","to_civ":"Rome","to_gold":2.1,'
      .. '"to_pressure":12,"to_religion":"Christianity","to_science":0.8,'
      .. '"to_tourism":7,"turn":11,"turns_left":21,"type":"international"}',
  }, pollThrough({
    { turn = 10, routes = {} },
    { turn = 11, routes = { [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM } },
  }))
end)

t.test("emits a domestic caravan without the yields it does not carry", function()
  t.assert_deep_equal({
    '{"civ":"Poland","domain":"land","event":"trade_route_established",'
      .. '"from_city":"Krakow","to_city":"Warsaw","to_civ":"Poland",'
      .. '"to_food":3,"turn":11,"turns_left":30,"type":"food"}',
  }, pollThrough({
    { turn = 10, routes = {} },
    { turn = 11, routes = { [KRAKOW_WARSAW_KEY] = KRAKOW_WARSAW } },
  }))
end)

-- Ending says only which route ended. What it was worth was said when it
-- opened, and a plundered route is told apart by the trade_route_plundered
-- the same turn.
t.test("emits trade_route_ended with the route's identity alone", function()
  t.assert_deep_equal({
    '{"civ":"Poland","event":"trade_route_ended","from_city":"Warsaw",'
      .. '"to_city":"Antium","to_civ":"Rome","turn":11}',
  }, pollThrough({
    { turn = 10, routes = { [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM } },
    { turn = 11, routes = {} },
  }))
end)

t.test("events come out in a deterministic order", function()
  local seen = {}
  for _, line in ipairs(pollThrough({
    { turn = 10, routes = {} },
    { turn = 11, routes = { [KRAKOW_WARSAW_KEY] = KRAKOW_WARSAW, [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM } },
  })) do
    table.insert(seen, line:match('"from_city":"(%a+)"'))
  end
  t.assert_deep_equal({ "Warsaw", "Krakow" }, seen)
end)

-- PlayerDoTurn fires once per living player; the route list is
-- game-global, so the poll is gated on the turn.
t.test("polls once per turn, however many players take theirs", function()
  local lines, sink = captureSink()
  local state = { turn = 10, routes = {} }
  local poll = tradeRoutes.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.routes = 11, { [WARSAW_ANTIUM_KEY] = WARSAW_ANTIUM }
  poll(0)
  poll(1)
  t.assert_equal(1, #lines)
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 10 end,
    tradeRoutes = function() error("boom") end,
  }
  tradeRoutes.new(civ, sink)(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
