local t = require("tests.test_helper")
local adapter = require("src.adapter")

local function fakePlayer(spec)
  return {
    IsAlive = function() return spec.alive ~= false end,
    IsMinorCiv = function() return spec.minor == true end,
    IsBarbarian = function() return spec.barbarian == true end,
    GetTeam = function() return spec.team or 0 end,
    GetCivilizationShortDescription = function() return spec.civ end,
    GetScore = function() return spec.score end,
    GetGold = function() return spec.gold end,
    CalculateGoldRateTimes100 = function() return spec.goldRate100 end,
    GetScienceTimes100 = function() return spec.science100 end,
    GetTotalJONSCulturePerTurn = function() return spec.culture end,
    GetTotalFaithPerTurn = function() return spec.faith end,
    GetExcessHappiness = function() return spec.happiness end,
    GetNumCities = function() return spec.cities end,
    GetTotalPopulation = function() return spec.population end,
    GetMilitaryMight = function() return spec.might end,
    GetNumMilitaryUnits = function() return spec.militaryUnits end,
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
  Game = {
    GetGameTurn = function() return 142 end,
    GetReligionName = function(religionId)
      return religionId == 4 and "Buddhism" or nil
    end,
  },
  GameDefines = { MAX_CIV_PLAYERS = 3 },
  Players = {
    [0] = fakePlayer({
      civ = "Poland", team = 0,
      cityId = 3, cityName = "Warsaw",
      unitId = 9, unitTypeId = 5,
      score = 1200, gold = 340, goldRate100 = 1250, science100 = 4800,
      culture = 30, faith = 10, happiness = 7, cities = 5,
      population = 41, might = 5600, militaryUnits = 14,
    }),
    [1] = fakePlayer({ civ = "Rome", team = 1 }),
    [2] = fakePlayer({ civ = "Carthage", team = 1, alive = false }),
    [3] = fakePlayer({ civ = "Venice", minor = true }),
    [4] = fakePlayer({ civ = "Barbarians", barbarian = true }),
  },
  Teams = {
    [0] = {
      GetTeamTechs = function()
        return { GetNumTechsKnown = function() return 24 end }
      end,
    },
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
    Beliefs = { [10] = { Type = "BELIEF_TITHE" } },
    Eras = { [2] = { Type = "ERA_CLASSICAL" } },
    Policies = { [6] = { Type = "POLICY_LIBERTY" } },
    Features = { [21] = { Type = "FEATURE_EL_DORADO" } },
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

t.test("religionName uses the in-game (possibly renamed) name", function()
  t.assert_equal("Buddhism", civ.religionName(4))
end)

t.test("beliefType resolves a belief id to its Type string", function()
  t.assert_equal("BELIEF_TITHE", civ.beliefType(10))
end)

t.test("beliefType is nil for NO_BELIEF (-1)", function()
  t.assert_nil(civ.beliefType(-1))
end)

t.test("eraType resolves an era id to its Type string", function()
  t.assert_equal("ERA_CLASSICAL", civ.eraType(2))
end)

t.test("policyType resolves a policy id to its Type string", function()
  t.assert_equal("POLICY_LIBERTY", civ.policyType(6))
end)

t.test("featureType resolves a feature id to its Type string", function()
  t.assert_equal("FEATURE_EL_DORADO", civ.featureType(21))
end)

t.test("unitTypeName resolves a unit type id to its Type string", function()
  t.assert_equal("UNIT_SETTLER", civ.unitTypeName(5))
end)

t.test("playerStats reads the full stat line of a living major civ", function()
  t.assert_deep_equal({
    score = 1200,
    gold = 340,
    gold_per_turn = 12.5,
    science = 48,
    culture = 30,
    faith = 10,
    happiness = 7,
    cities = 5,
    population = 41,
    military_might = 5600,
    military_units = 14,
    techs = 24,
  }, civ.playerStats(0))
end)

t.test("playerStats is nil for city-states", function()
  t.assert_nil(civ.playerStats(3))
end)

t.test("playerStats is nil for barbarians", function()
  t.assert_nil(civ.playerStats(4))
end)

t.test("playerStats is nil for dead players", function()
  t.assert_nil(civ.playerStats(2))
end)
