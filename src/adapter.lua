-- The civ adapter: the only place that touches the game's API.
-- Takes the game globals (Game, Players, Map, GameInfo, GameDefines)
-- so tests can substitute fakes.
local M = {}

function M.new(g)
  local civ = {}

  function civ.turn()
    return g.Game.GetGameTurn()
  end

  function civ.civName(playerId)
    return g.Players[playerId]:GetCivilizationShortDescription()
  end

  function civ.teamCivNames(teamId)
    local names = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local player = g.Players[i]
      if player and player:IsAlive() and player:GetTeam() == teamId then
        table.insert(names, player:GetCivilizationShortDescription())
      end
    end
    return names
  end

  function civ.cityNameAt(x, y)
    local city = g.Map.GetPlot(x, y):GetPlotCity()
    return city and city:GetName() or nil
  end

  function civ.cityName(playerId, cityId)
    local city = g.Players[playerId]:GetCityByID(cityId)
    return city and city:GetName() or nil
  end

  function civ.techType(techId)
    return g.GameInfo.Technologies[techId].Type
  end

  function civ.buildingType(buildingId)
    return g.GameInfo.Buildings[buildingId].Type
  end

  function civ.isWonder(buildingId)
    local class = g.GameInfo.Buildings[buildingId].BuildingClass
    return g.GameInfo.BuildingClasses[class].MaxGlobalInstances > 0
  end

  function civ.unitType(playerId, unitId)
    local unit = g.Players[playerId]:GetUnitByID(unitId)
    return unit and g.GameInfo.Units[unit:GetUnitType()].Type or nil
  end

  function civ.projectType(projectId)
    return g.GameInfo.Projects[projectId].Type
  end

  return civ
end

return M
