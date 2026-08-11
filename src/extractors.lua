-- Turn raw GameEvents hook arguments into narrative records.
-- Each extractor takes the civ adapter plus the arguments in the exact
-- order the Lekmod DLL pushes them, and returns a plain record table.
local M = {}

local function boughtWith(gold, faith)
  if gold then return "gold" end
  if faith then return "faith" end
end

function M.CityCaptureComplete(civ, oldOwner, capital, x, y, newOwner,
    population, conquest, greatWorks, greatWorksCaptured)
  return {
    event = "city_captured",
    turn = civ.turn(),
    city = civ.cityNameAt(x, y),
    x = x,
    y = y,
    old_owner = civ.civName(oldOwner),
    new_owner = civ.civName(newOwner),
    population = population,
    capital = capital,
    conquest = conquest,
    great_works = greatWorks,
    great_works_captured = greatWorksCaptured,
  }
end

function M.TeamTechResearched(civ, teamId, techId, change)
  return {
    event = "tech_researched",
    turn = civ.turn(),
    team = teamId,
    civs = civ.teamCivNames(teamId),
    tech = civ.techType(techId),
    change = change,
  }
end

function M.PlayerCityFounded(civ, playerId, x, y)
  return {
    event = "city_founded",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    city = civ.cityNameAt(x, y),
    x = x,
    y = y,
  }
end

function M.DeclareWar(civ, attackerTeam, defenderTeam)
  return {
    event = "war_declared",
    turn = civ.turn(),
    attacker_team = attackerTeam,
    attacker_civs = civ.teamCivNames(attackerTeam),
    defender_team = defenderTeam,
    defender_civs = civ.teamCivNames(defenderTeam),
  }
end

function M.CityConstructed(civ, ownerId, cityId, buildingId, gold, faith)
  return {
    event = "building_constructed",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    city = civ.cityName(ownerId, cityId),
    building = civ.buildingType(buildingId),
    wonder = civ.isWonder(buildingId),
    bought_with = boughtWith(gold, faith),
  }
end

function M.CityTrained(civ, ownerId, cityId, unitId, gold, faith)
  return {
    event = "unit_trained",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    city = civ.cityName(ownerId, cityId),
    unit = civ.unitType(ownerId, unitId),
    bought_with = boughtWith(gold, faith),
  }
end

function M.CityCreated(civ, ownerId, cityId, projectId)
  return {
    event = "project_completed",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    city = civ.cityName(ownerId, cityId),
    project = civ.projectType(projectId),
  }
end

return M
