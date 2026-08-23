local t = require("tests.test_helper")
local freeBuildings = require("src.free_buildings")

local CANDIDATES = {
  { id = 12, type = "BUILDING_LIBRARY" },
  { id = 13, type = "BUILDING_ROYAL_LIBRARY" },
  { id = 14, type = "BUILDING_HARBOR" },
}

local EVERY_BUILDING = {
  { id = 12, type = "BUILDING_LIBRARY" },
  { id = 13, type = "BUILDING_ROYAL_LIBRARY" },
  { id = 14, type = "BUILDING_HARBOR" },
  { id = 20, type = "BUILDING_WORKSHOP" },
  { id = 21, type = "BUILDING_GRANARY" },
}

local function fakeCiv(citiesByPlayer, turn, standingByCity)
  return {
    turn = function() return turn or 74 end,
    civName = function(playerId) return playerId == 0 and "Babylon" or "Assyria" end,
    grantableBuildings = function()
      return CANDIDATES, { "BUILDINGCLASS_HARBOR", "BUILDINGCLASS_LIBRARY" }
    end,
    allBuildings = function() return EVERY_BUILDING end,
    freeBuildings = function(playerId) return citiesByPlayer[playerId] or {} end,
    cityBuildings = function(_, cityId) return (standingByCity or {})[cityId] or {} end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

-- A city the poller has seen before: founded long ago, never changed hands.
local function city(id, name, buildings)
  return { id = id, name = name, buildings = buildings, founded = 10, acquired = 10 }
end

local function foundedNow(id, name, buildings, turn)
  return { id = id, name = name, buildings = buildings, founded = turn, acquired = turn }
end

local function captured(id, name, buildings, turn)
  return { id = id, name = name, buildings = buildings, founded = 10, acquired = turn }
end

t.test("announces both scan widths once, before anything is polled", function()
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv({}), sink)
  poll(0)
  poll(0)
  t.assert_deep_equal({
    '{"all_buildings":5,"buildings":3,"classes":["BUILDINGCLASS_HARBOR","BUILDINGCLASS_LIBRARY"],'
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
  local cities = { [0] = { foundedNow(3, "Babylon", { "BUILDING_HARBOR" }, 1) } }
  local standing = { [3] = { "BUILDING_HARBOR" } }
  local lines, sink = captureSink()
  freeBuildings.new(fakeCiv(cities, 1, standing), sink)(0)
  t.assert_match('"building":"BUILDING_HARBOR"', lines[2])
end)

t.test("reports everything standing in a city founded since the last poll", function()
  local cities, standing = { [0] = { city(3, "Babylon", {}) } }, {}
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities, 74, standing), sink)
  poll(0)
  table.insert(cities[0], foundedNow(4, "Akkad", {}, 74))
  standing[4] = { "BUILDING_GRANARY", "BUILDING_WORKSHOP" }
  poll(0)
  t.assert_deep_equal({
    '{"building":"BUILDING_GRANARY","city":"Akkad","civ":"Babylon","event":"building_granted",'
      .. '"source":"new_city","turn":74}',
    '{"building":"BUILDING_WORKSHOP","city":"Akkad","civ":"Babylon","event":"building_granted",'
      .. '"source":"new_city","turn":74}',
  }, { lines[2], lines[3] })
end)

t.test("a captured city is seeded, never reported as granted", function()
  local cities = { [0] = { city(3, "Babylon", {}) } }
  local standing = { [7] = { "BUILDING_LIBRARY", "BUILDING_WORKSHOP" } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities, 74, standing), sink)
  poll(0)
  table.insert(cities[0], captured(7, "Nineveh", { "BUILDING_LIBRARY" }, 74))
  poll(0)
  t.assert_nil(lines[2])
end)

t.test("a grant to a standing city says it came from a diff", function()
  local cities = { [0] = { city(3, "Babylon", {}) } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities), sink)
  poll(0)
  cities[0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }) }
  poll(0)
  t.assert_equal(
    '{"building":"BUILDING_LIBRARY","city":"Babylon","civ":"Babylon","event":"building_granted",'
      .. '"source":"diff","turn":74}',
    lines[2]
  )
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

t.test("a new city's grants are not repeated on the next turn", function()
  local cities = { [0] = { city(3, "Babylon", {}) } }
  local standing = { [4] = { "BUILDING_WORKSHOP" } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities, 74, standing), sink)
  poll(0)
  table.insert(cities[0], foundedNow(4, "Akkad", {}, 74))
  poll(0)
  poll(0)
  t.assert_equal(2, #lines)
end)

t.test("a recycled city id does not hide the new city's grants", function()
  local cities = { [0] = { city(3, "Babylon", { "BUILDING_LIBRARY" }) } }
  local standing = { [3] = { "BUILDING_LIBRARY" } }
  local lines, sink = captureSink()
  local poll = freeBuildings.new(fakeCiv(cities, 74, standing), sink)
  poll(0)
  cities[0] = { foundedNow(3, "Akkad", { "BUILDING_LIBRARY" }, 74) }
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
