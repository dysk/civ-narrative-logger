local t = require("tests.test_helper")
local freeBuildings = require("src.free_buildings")

local CANDIDATES = {
  { id = 12, type = "BUILDING_LIBRARY" },
  { id = 13, type = "BUILDING_ROYAL_LIBRARY" },
  { id = 14, type = "BUILDING_HARBOR" },
}

local function fakeCiv(citiesByPlayer, turn)
  return {
    turn = function() return turn or 74 end,
    civName = function(playerId) return playerId == 0 and "Babylon" or "Assyria" end,
    grantableBuildings = function()
      return CANDIDATES, { "BUILDINGCLASS_HARBOR", "BUILDINGCLASS_LIBRARY" }
    end,
    freeBuildings = function(playerId) return citiesByPlayer[playerId] or {} end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

local function city(id, name, buildings)
  return { id = id, name = name, buildings = buildings }
end

t.test("announces the candidate set once, before anything is polled", function()
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv({}), sink)
  poll(0)
  poll(0)
  t.assert_deep_equal({
    '{"buildings":3,"classes":["BUILDINGCLASS_HARBOR","BUILDINGCLASS_LIBRARY"],'
      .. '"event":"free_buildings_ready","turn":74}',
  }, lines)
end)

t.test("logs no grant on the first poll of a session that starts mid-game", function()
  local cities = { [0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }) } }
  local lines, sink = captureSink()
  freeBuildings.new(fakeCiv(cities), sink)(0)
  t.assert_nil(lines[2])
end)

t.test("logs what the opening turns hand out, having nothing to seed from", function()
  local cities = { [0] = { city(3, "Babylon", { "BUILDING_HARBOR" }) } }
  local lines, sink = captureSink()
  freeBuildings.new(fakeCiv(cities, 1), sink)(0)
  t.assert_match('"building":"BUILDING_HARBOR"', lines[2])
end)

t.test("emits building_granted when a city gains a building nobody built", function()
  local cities = { [0] = { city(3, "Babylon", {}) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  cities[0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }) }
  poll(0)
  t.assert_equal(
    '{"building":"BUILDING_LIBRARY","city":"Babylon","civ":"Babylon","event":"building_granted","turn":74}',
    lines[2]
  )
end)

t.test("reports a city founded with its free building already standing", function()
  local cities = { [0] = { city(3, "Babylon", {}) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  table.insert(cities[0], city(4, "Akkad", { "BUILDING_HARBOR" }))
  poll(0)
  t.assert_match('"city":"Akkad"', lines[2])
end)

t.test("names the unique the civ was actually given", function()
  local cities = { [1] = { city(8, "Nineveh", {}) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(1)
  cities[1] = { city(8, "Nineveh", { "BUILDING_ROYAL_LIBRARY" }) }
  poll(1)
  t.assert_match('"building":"BUILDING_ROYAL_LIBRARY"', lines[2])
end)

t.test("logs a granted building once, not every turn it stands", function()
  local cities = { [0] = { city(3, "Babylon", {}) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  cities[0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }) }
  poll(0)
  poll(0)
  t.assert_equal(2, #lines)
end)

t.test("a recycled city id does not hide the new city's grants", function()
  local cities = { [0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  cities[0] = { city(3, "Akkad", { "BUILDING_LIBRARY" }) }
  poll(0)
  t.assert_match('"city":"Akkad"', lines[2])
end)

t.test("tracks each city of a player separately", function()
  local cities = { [0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }), city(4, "Akkad", {}) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  cities[0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }), city(4, "Akkad", { "BUILDING_LIBRARY" }) }
  poll(0)
  t.assert_match('"city":"Akkad"', lines[2])
end)

t.test("tracks each player separately", function()
  local cities = {
    [0] = { city(3, "Babylon", {}) },
    [1] = { city(8, "Nineveh", {}) },
  }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  poll(1)
  cities[1] = { city(8, "Nineveh", { "BUILDING_ROYAL_LIBRARY" }) }
  poll(1)
  t.assert_match('"civ":"Assyria"', lines[2])
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = fakeCiv({})
  civ.freeBuildings = function() error("boom") end
  freeBuildings.new(civ, sink)(0)
  t.assert_match('"hook":"PlayerDoTurn (free_buildings)"', lines[2])
end)
