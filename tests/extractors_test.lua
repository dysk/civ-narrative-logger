local t = require("tests.test_helper")
local extractors = require("src.extractors")

-- Fake of the adapter that wraps Game/Players/GameInfo in-game.
local civ = {
  turn = function() return 142 end,
  civName = function(playerId)
    return ({ [0] = "Poland", [1] = "Rome" })[playerId]
  end,
  teamCivNames = function(teamId)
    return ({ [0] = { "Poland" }, [1] = { "Rome" } })[teamId]
  end,
  cityNameAt = function(x, y)
    return (x == 10 and y == 20) and "Warsaw" or nil
  end,
  cityName = function(playerId, cityId)
    return (playerId == 0 and cityId == 3) and "Warsaw" or nil
  end,
  techType = function(techId)
    return techId == 12 and "TECH_POTTERY" or nil
  end,
  buildingType = function(buildingId)
    return buildingId == 7 and "BUILDING_PYRAMIDS" or "BUILDING_GRANARY"
  end,
  isWonder = function(buildingId) return buildingId == 7 end,
  unitType = function(playerId, unitId)
    return (playerId == 0 and unitId == 9) and "UNIT_SETTLER" or nil
  end,
  projectType = function(projectId)
    return projectId == 2 and "PROJECT_APOLLO_PROGRAM" or nil
  end,
}

-- DLL: CityCaptureComplete(oldOwner, isCapital, x, y, newOwner,
--   oldPopulation, isConquest, greatWorkCount, capturedGreatWorks)
t.test("CityCaptureComplete becomes a city_captured record", function()
  t.assert_deep_equal({
    event = "city_captured",
    turn = 142,
    city = "Warsaw",
    x = 10,
    y = 20,
    old_owner = "Poland",
    new_owner = "Rome",
    population = 8,
    capital = false,
    conquest = true,
    great_works = 3,
    great_works_captured = 2,
  }, extractors.CityCaptureComplete(civ, 0, false, 10, 20, 1, 8, true, 3, 2))
end)

-- DLL: TeamTechResearched(teamId, techId, change)
t.test("TeamTechResearched becomes a tech_researched record", function()
  t.assert_deep_equal({
    event = "tech_researched",
    turn = 142,
    team = 1,
    civs = { "Rome" },
    tech = "TECH_POTTERY",
    change = 1,
  }, extractors.TeamTechResearched(civ, 1, 12, 1))
end)

-- DLL: PlayerCityFounded(playerId, x, y)
t.test("PlayerCityFounded becomes a city_founded record", function()
  t.assert_deep_equal({
    event = "city_founded",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    x = 10,
    y = 20,
  }, extractors.PlayerCityFounded(civ, 0, 10, 20))
end)

-- DLL: DeclareWar(attackingTeamId, defendingTeamId)
t.test("DeclareWar becomes a war_declared record", function()
  t.assert_deep_equal({
    event = "war_declared",
    turn = 142,
    attacker_team = 0,
    attacker_civs = { "Poland" },
    defender_team = 1,
    defender_civs = { "Rome" },
  }, extractors.DeclareWar(civ, 0, 1))
end)

-- DLL: CityConstructed(ownerId, cityId, buildingId, boughtWithGold,
--   boughtWithFaithOrCulture)
t.test("CityConstructed becomes a building_constructed record", function()
  t.assert_deep_equal({
    event = "building_constructed",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    building = "BUILDING_PYRAMIDS",
    wonder = true,
  }, extractors.CityConstructed(civ, 0, 3, 7, false, false))
end)

t.test("CityConstructed records purchases with the currency used", function()
  t.assert_deep_equal({
    event = "building_constructed",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    building = "BUILDING_GRANARY",
    wonder = false,
    bought_with = "gold",
  }, extractors.CityConstructed(civ, 0, 3, 5, true, false))
end)

-- DLL: CityTrained(ownerId, cityId, unitInstanceId, boughtWithGold,
--   boughtWithFaithOrCulture) -- note: unit instance, not unit type
t.test("CityTrained becomes a unit_trained record", function()
  t.assert_deep_equal({
    event = "unit_trained",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    unit = "UNIT_SETTLER",
  }, extractors.CityTrained(civ, 0, 3, 9, false, false))
end)

-- DLL: CityCreated(ownerId, cityId, projectId, boughtWithGold,
--   boughtWithFaithOrCulture)
t.test("CityCreated becomes a project_completed record", function()
  t.assert_deep_equal({
    event = "project_completed",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    project = "PROJECT_APOLLO_PROGRAM",
  }, extractors.CityCreated(civ, 0, 3, 2, false, false))
end)

t.test("CityTrained records faith purchases", function()
  t.assert_deep_equal({
    event = "unit_trained",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    unit = "UNIT_SETTLER",
    bought_with = "faith",
  }, extractors.CityTrained(civ, 0, 3, 9, false, true))
end)
