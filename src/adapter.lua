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

  function civ.wonderClass(buildingId)
    local class = g.GameInfo.Buildings[buildingId].BuildingClass
    local limits = g.GameInfo.BuildingClasses[class]
    if limits.MaxGlobalInstances > 0 then return "world" end
    if limits.MaxPlayerInstances > 0 then return "national" end
  end

  function civ.unitType(playerId, unitId)
    local unit = g.Players[playerId]:GetUnitByID(unitId)
    return unit and g.GameInfo.Units[unit:GetUnitType()].Type or nil
  end

  function civ.projectType(projectId)
    return g.GameInfo.Projects[projectId].Type
  end

  function civ.religionName(religionId)
    return g.Game.GetReligionName(religionId)
  end

  local function typeOf(row)
    return row and row.Type or nil
  end

  function civ.beliefType(beliefId)
    return typeOf(g.GameInfo.Beliefs[beliefId])
  end

  function civ.eraType(eraId)
    return typeOf(g.GameInfo.Eras[eraId])
  end

  function civ.policyType(policyId)
    return typeOf(g.GameInfo.Policies[policyId])
  end

  function civ.policyBranchType(branchId)
    return typeOf(g.GameInfo.PolicyBranchTypes[branchId])
  end

  function civ.promotionType(promotionId)
    return typeOf(g.GameInfo.UnitPromotions[promotionId])
  end

  function civ.improvementType(improvementId)
    return typeOf(g.GameInfo.Improvements[improvementId])
  end

  function civ.cityOwnerAt(x, y)
    local city = g.Map.GetPlot(x, y):GetPlotCity()
    return city and civ.civName(city:GetOwner()) or nil
  end

  function civ.featureType(featureId)
    return typeOf(g.GameInfo.Features[featureId])
  end

  function civ.unitTypeName(unitTypeId)
    return typeOf(g.GameInfo.Units[unitTypeId])
  end

  local influenceLevelNames = {
    [-1] = "NO_INFLUENCE_LEVEL",
    [0] = "INFLUENCE_LEVEL_UNKNOWN",
    [1] = "INFLUENCE_LEVEL_EXOTIC",
    [2] = "INFLUENCE_LEVEL_FAMILIAR",
    [3] = "INFLUENCE_LEVEL_POPULAR",
    [4] = "INFLUENCE_LEVEL_INFLUENTIAL",
    [5] = "INFLUENCE_LEVEL_DOMINANT",
  }

  local influenceTrendNames = {
    [-1] = "INFLUENCE_TREND_FALLING",
    [0] = "INFLUENCE_TREND_STATIC",
    [1] = "INFLUENCE_TREND_RISING",
  }

  local function isLivingMajor(p)
    return p and p:IsAlive() and not p:IsMinorCiv() and not p:IsBarbarian()
  end

  local function influenceList(p, selfId)
    local list = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local other = g.Players[i]
      if i ~= selfId and isLivingMajor(other) then
        table.insert(list, {
          civ = other:GetCivilizationShortDescription(),
          points = p:GetInfluenceOn(i),
          level = influenceLevelNames[p:GetInfluenceLevel(i)],
          trend = influenceTrendNames[p:GetInfluenceTrend(i)],
        })
      end
    end
    return list
  end

  local function projectId(projectType)
    return g.GameInfoTypes[projectType]
  end

  local function capitalsOf(p)
    local capitals = {}
    for city in p:Cities() do
      if city:IsOriginalMajorCapital() then
        table.insert(capitals, civ.civName(city:GetOriginalOwner()))
      end
    end
    return capitals
  end

  local function spaceshipOf(team)
    return {
      apollo = team:GetProjectCount(projectId("PROJECT_APOLLO_PROGRAM")),
      booster = team:GetProjectCount(projectId("PROJECT_SS_BOOSTER")),
      cockpit = team:GetProjectCount(projectId("PROJECT_SS_COCKPIT")),
      stasis_chamber = team:GetProjectCount(projectId("PROJECT_SS_STASIS_CHAMBER")),
      engine = team:GetProjectCount(projectId("PROJECT_SS_ENGINE")),
    }
  end

  function civ.playerStats(playerId)
    local p = g.Players[playerId]
    if not isLivingMajor(p) then
      return nil
    end
    return {
      score = p:GetScore(),
      gold = p:GetGold(),
      gold_per_turn = p:CalculateGoldRateTimes100() / 100,
      science = p:GetScienceTimes100() / 100,
      culture = p:GetTotalJONSCulturePerTurn(),
      faith = p:GetTotalFaithPerTurn(),
      happiness = p:GetExcessHappiness(),
      cities = p:GetNumCities(),
      population = p:GetTotalPopulation(),
      military_might = p:GetMilitaryMight(),
      military_units = p:GetNumMilitaryUnits(),
      techs = g.Teams[p:GetTeam()]:GetTeamTechs():GetNumTechsKnown(),
      tourism = p:GetTourism(),
      civs_influential_on = p:GetNumCivsInfluentialOn(),
      influence = influenceList(p, playerId),
      production = p:CalculateTotalYield(g.YieldTypes.YIELD_PRODUCTION),
      food = p:CalculateTotalYield(g.YieldTypes.YIELD_FOOD),
      gross_gold = p:CalculateGrossGold(),
      plots = p:GetNumPlots(),
      capitals = capitalsOf(p),
      spaceship = spaceshipOf(g.Teams[p:GetTeam()]),
    }
  end

  local function activatedMods()
    local mods = {}
    for _, mod in ipairs(g.Modding.GetActivatedMods()) do
      table.insert(mods, { id = mod.ID, version = mod.Version })
    end
    return mods
  end

  function civ.gameSettings()
    local width, height = g.Map.GetGridSize()
    return {
      map_script = g.PreGame.GetMapScript(),
      map_size = typeOf(g.GameInfo.Worlds[g.Map.GetWorldSize()]),
      map_width = width,
      map_height = height,
      game_speed = typeOf(g.GameInfo.GameSpeeds[g.Game.GetGameSpeedType()]),
      max_turns = g.Game.GetMaxTurns(),
      start_era = civ.eraType(g.Game.GetStartEra()),
      mods = activatedMods(),
    }
  end

  local function rosterEntry(p)
    return {
      civ = p:GetCivilizationShortDescription(),
      name = p:GetName(),
      human = p:IsHuman(),
      handicap = typeOf(g.GameInfo.HandicapInfos[p:GetHandicapType()]),
    }
  end

  function civ.playerRoster()
    local roster = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local p = g.Players[i]
      if p and p:IsAlive() and not p:IsMinorCiv() and not p:IsBarbarian() then
        table.insert(roster, rosterEntry(p))
      end
    end
    return roster
  end

  return civ
end

return M
