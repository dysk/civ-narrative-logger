local t = require("tests.test_helper")
local adapter = require("src.adapter")

local function fakePlayer(spec)
  return {
    IsAlive = function() return spec.alive ~= false end,
    GetTeam = function() return spec.team or 0 end,
    GetCivilizationShortDescription = function() return spec.civ end,
    GetCityByID = function(_, id)
      if id == spec.cityId then
        return { GetName = function() return spec.cityName end }
      end
    end,
    GetUnitByID = function(_, id)
      if id == spec.unitId then
        return { GetUnitType = function() return spec.unitTypeId end }
      end
    end,
  }
end

local globals = {
  Game = { GetGameTurn = function() return 142 end },
  GameDefines = { MAX_CIV_PLAYERS = 3 },
  Players = {
    [0] = fakePlayer({
      civ = "Poland", team = 0,
      cityId = 3, cityName = "Warsaw",
      unitId = 9, unitTypeId = 5,
    }),
    [1] = fakePlayer({ civ = "Rome", team = 1 }),
    [2] = fakePlayer({ civ = "Carthage", team = 1, alive = false }),
  },
  Map = {
    GetPlot = function(x, y)
      return {
        GetPlotCity = function()
          if x == 10 and y == 20 then
            return { GetName = function() return "Warsaw" end }
          end
        end,
      }
    end,
  },
  GameInfo = {
    Technologies = { [12] = { Type = "TECH_POTTERY" } },
    Units = { [5] = { Type = "UNIT_SETTLER" } },
    Projects = { [2] = { Type = "PROJECT_APOLLO_PROGRAM" } },
    Buildings = {
      [7] = { Type = "BUILDING_PYRAMIDS", BuildingClass = "BUILDINGCLASS_PYRAMIDS" },
      [5] = { Type = "BUILDING_GRANARY", BuildingClass = "BUILDINGCLASS_GRANARY" },
    },
    BuildingClasses = {
      BUILDINGCLASS_PYRAMIDS = { MaxGlobalInstances = 1 },
      BUILDINGCLASS_GRANARY = { MaxGlobalInstances = -1 },
    },
  },
}

local civ = adapter.new(globals)

t.test("turn comes from Game.GetGameTurn", function()
  t.assert_equal(142, civ.turn())
end)

t.test("civName resolves a player id to the civ name", function()
  t.assert_equal("Poland", civ.civName(0))
end)

t.test("teamCivNames lists living civs on the team", function()
  t.assert_deep_equal({ "Rome" }, civ.teamCivNames(1))
end)

t.test("cityNameAt finds the city on a plot", function()
  t.assert_equal("Warsaw", civ.cityNameAt(10, 20))
end)

t.test("cityNameAt is nil for a plot without a city", function()
  t.assert_nil(civ.cityNameAt(0, 0))
end)

t.test("cityName resolves a city id on its owner", function()
  t.assert_equal("Warsaw", civ.cityName(0, 3))
end)

t.test("techType resolves a tech id to its Type string", function()
  t.assert_equal("TECH_POTTERY", civ.techType(12))
end)

t.test("buildingType resolves a building id to its Type string", function()
  t.assert_equal("BUILDING_PYRAMIDS", civ.buildingType(7))
end)

t.test("isWonder is true for world wonders", function()
  t.assert_equal(true, civ.isWonder(7))
end)

t.test("isWonder is false for ordinary buildings", function()
  t.assert_equal(false, civ.isWonder(5))
end)

t.test("unitType resolves a unit instance to its Type string", function()
  t.assert_equal("UNIT_SETTLER", civ.unitType(0, 9))
end)

t.test("projectType resolves a project id to its Type string", function()
  t.assert_equal("PROJECT_APOLLO_PROGRAM", civ.projectType(2))
end)
