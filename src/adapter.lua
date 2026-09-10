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

  function civ.citySet(playerId)
    local cities = {}
    for city in g.Players[playerId]:Cities() do
      cities[city:GetID()] = { name = city:GetName(), x = city:GetX(), y = city:GetY() }
    end
    return cities
  end

  function civ.techType(techId)
    return g.GameInfo.Technologies[techId].Type
  end

  function civ.buildingType(buildingId)
    return g.GameInfo.Buildings[buildingId].Type
  end

  -- Whether a column is set at all: the game hands booleans back as
  -- booleans or as the 0/1 they are stored as, and a count of nothing
  -- reads the same way.
  local function isSet(value)
    return value ~= nil and value ~= false and value ~= 0
  end

  -- A wonder is whatever the ruleset caps, and it caps in three scopes,
  -- not two: Oxford University is one per team.
  local function wonderScope(class)
    local limits = g.GameInfo.BuildingClasses[class]
    if limits.MaxGlobalInstances > 0 then return "world" end
    if limits.MaxTeamInstances > 0 then return "team" end
    if limits.MaxPlayerInstances > 0 then return "national" end
  end

  function civ.wonderClass(buildingId)
    return wonderScope(g.GameInfo.Buildings[buildingId].BuildingClass)
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

  local function isLivingMinor(p)
    return p and p:IsAlive() and p:IsMinorCiv() and not p:IsBarbarian()
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

  -- The stocks behind the rates above: what a player has banked is a
  -- different decision from what they earn per turn.
  local function stocksOf(p)
    return {
      faith_stored = p:GetFaith(),
      culture_stored = p:GetJONSCulture(),
      next_policy_cost = p:GetNextPolicyCost(),
      policies = p:GetNumPolicies(),
      golden_age_turns = p:GetGoldenAgeTurns(),
      golden_age_progress = p:GetGoldenAgeProgressMeter(),
      golden_age_threshold = p:GetGoldenAgeProgressThreshold(),
      anarchy_turns = p:GetAnarchyNumTurns(),
      great_people = p:GetGreatPeopleCreated(),
      great_generals = p:GetGreatGeneralsCreated(),
    }
  end

  -- tech_researched says what landed, never what was aimed at. Between
  -- two techs there is nothing aimed at, and GetCurrentResearch answers
  -- NO_TECH (-1).
  local function researchOf(p)
    local techId = p:GetCurrentResearch()
    if not techId or techId < 0 then return {} end
    return {
      researching = civ.techType(techId),
      research_turns_left = p:GetResearchTurnsLeft(techId, true),
    }
  end

  -- PublicOpinionTypes is a global enum table in the mod environment,
  -- read here the way CultureOverview.lua reads it, so the log carries
  -- the game's own name rather than an integer we would have to decode.
  local function publicOpinionName(value)
    for name, id in pairs(g.PublicOpinionTypes) do
      if id == value then return name end
    end
  end

  local function ideologyOf(p)
    return {
      ideology = civ.policyBranchType(p:GetLateGamePolicyTree()),
      public_opinion = publicOpinionName(p:GetPublicOpinionType()),
      public_opinion_unhappiness = p:GetPublicOpinionUnhappiness(),
      preferred_ideology = civ.policyBranchType(p:GetPublicOpinionPreferredIdeology()),
    }
  end

  local function resourceEntry(p, row)
    local entry = {
      resource = row.Type,
      total = p:GetNumResourceTotal(row.ID, true),
      used = p:GetNumResourceUsed(row.ID),
      import = p:GetResourceImport(row.ID),
      export = p:GetResourceExport(row.ID),
    }
    local touched = entry.total ~= 0 or entry.used ~= 0
      or entry.import ~= 0 or entry.export ~= 0
    return touched and entry or nil
  end

  -- Imports and exports are the closest thing to a record of a trade
  -- deal, whose contents Lua cannot read: a luxury appearing in one
  -- player's imports and another's exports on the same turn is a deal.
  -- Bonus resources (usage 0) carry none of that, and an untouched
  -- resource would be a row of zeroes in every snapshot of the game.
  local function resourcesOf(p)
    local resources = {}
    for row in g.GameInfo.Resources() do
      if row.ResourceUsage > 0 then
        local entry = resourceEntry(p, row)
        if entry then table.insert(resources, entry) end
      end
    end
    return resources
  end

  local function addAll(target, extra)
    for key, value in pairs(extra) do target[key] = value end
    return target
  end

  local function baseStats(p, playerId)
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

  -- Two APIs answer "where did this yield come from", and they disagree.
  -- Science and faith never moved to the generic yield path, so their own
  -- getters are what their totals are built from; culture and tourism did
  -- move, and there the generic path is what the game runs. Reading a
  -- yield through the wrong one returns a number the game never uses.
  local SCIENCE_SOURCES = {
    { "cities", "GetScienceFromCitiesTimes100" },
    { "city_states", "GetScienceFromOtherPlayersTimes100" },
    { "happiness", "GetScienceFromHappinessTimes100" },
    { "gold", "GetScienceFromGoldTimes100" },
    { "research_agreements", "GetScienceFromResearchAgreementsTimes100" },
    { "deficit", "GetScienceFromBudgetDeficitTimes100" },
  }

  -- Faith alone answers in whole points; everything else is Times100.
  local FAITH_SOURCES = {
    { "cities", "GetFaithPerTurnFromCities" },
    { "minor_civs", "GetFaithPerTurnFromMinorCivs" },
    { "religion", "GetFaithPerTurnFromReligion" },
  }

  -- Split around religion because the DLL sums in this order and hands
  -- religion the running subtotal: its belief modifier applies to the
  -- four before it as well as to itself. The two after it are added once
  -- the golden-age modifier has been applied, so they stand outside it.
  local SOURCES_BEFORE_RELIGION = {
    { "cities", "GetYieldFromCitiesTimes100" },
    { "other_players", "GetYieldFromOtherPlayersTimes100" },
    { "happiness", "GetYieldFromHappinessTimes100" },
    { "traits", "GetYieldFromTraitsTimes100" },
  }

  local SOURCES_AFTER_RELIGION = {
    { "penalties", "GetYieldPenaltiesTimes100" },
    { "minor_civs", "GetYieldFromMinorCivsTimes100" },
  }

  -- A source that gives nothing is not news: most of them only ever
  -- apply to one yield, and writing the rest as zeroes would say nothing
  -- at several times the size.
  local function addSource(sources, field, value, scale)
    if value ~= 0 then sources[field] = value / scale end
  end

  -- Answers the named sources, and beside them their unscaled sum, which
  -- is what the generic path owes religion.
  local function readSources(p, definitions, scale, ...)
    local sources, subtotal = {}, 0
    for _, source in ipairs(definitions) do
      local value = p[source[2]](p, ...)
      subtotal = subtotal + value
      addSource(sources, source[1], value, scale)
    end
    return sources, subtotal
  end

  local function genericSources(p, yieldType)
    local yield = g.YieldTypes[yieldType]
    local sources, subtotal = readSources(p, SOURCES_BEFORE_RELIGION, 100, yield)
    addSource(sources, "religion",
      p.GetYieldFromReligionTimes100(p, yield, subtotal), 100)
    return addAll(sources, readSources(p, SOURCES_AFTER_RELIGION, 100, yield))
  end

  local function yieldSources(p)
    return {
      science = readSources(p, SCIENCE_SOURCES, 100),
      faith = readSources(p, FAITH_SOURCES, 1),
      culture = genericSources(p, "YIELD_CULTURE"),
      tourism = genericSources(p, "YIELD_TOURISM"),
    }
  end

  function civ.playerStats(playerId)
    local p = g.Players[playerId]
    if not isLivingMajor(p) then
      return nil
    end
    local stats = baseStats(p, playerId)
    addAll(stats, stocksOf(p))
    addAll(stats, researchOf(p))
    addAll(stats, ideologyOf(p))
    stats.resources = resourcesOf(p)
    stats.yield_sources = yieldSources(p)
    return stats
  end


  local CITY_YIELDS = {
    yield_food = "YIELD_FOOD",
    yield_production = "YIELD_PRODUCTION",
    yield_gold = "YIELD_GOLD",
    yield_science = "YIELD_SCIENCE",
    yield_culture = "YIELD_CULTURE",
    yield_faith = "YIELD_FAITH",
    yield_tourism = "YIELD_TOURISM",
  }

  local function cityYields(city)
    local yields = {}
    for field, yieldType in pairs(CITY_YIELDS) do
      yields[field] = city:GetYieldRateTimes100(g.YieldTypes[yieldType]) / 100
    end
    return yields
  end

  -- A city answers -1 from the getters for the kinds it is not building,
  -- so the queue takes naming both what is on it and which kind it is.
  local function cityProduction(city)
    local unitId = city:GetProductionUnit()
    if unitId >= 0 then return civ.unitTypeName(unitId), "unit" end
    local buildingId = city:GetProductionBuilding()
    if buildingId >= 0 then return civ.buildingType(buildingId), "building" end
    local projectId = city:GetProductionProject()
    if projectId >= 0 then return civ.projectType(projectId), "project" end
  end

  local function cityReligion(city)
    local religionId = city:GetReligiousMajority()
    if not religionId or religionId < 0 then return {} end
    return {
      religion = civ.religionName(religionId),
      religion_followers = city:GetNumFollowers(religionId),
    }
  end

  local function cityCore(city)
    local producing, kind = cityProduction(city)
    return {
      city = city:GetName(),
      x = city:GetX(),
      y = city:GetY(),
      population = city:GetPopulation(),
      food_stored = city:GetFood(),
      food_turns_left = city:GetFoodTurnsLeft(),
      producing = producing,
      producing_kind = kind,
      production_turns_left = city:GetProductionTurnsLeft(),
      production_stored = city:GetProduction(),
    }
  end

  local function cityCondition(city)
    return {
      buildings = city:GetNumBuildings(),
      damage = city:GetDamage(),
      defense = city:GetStrengthValue(),
      puppet = city:IsPuppet(),
      occupied = city:IsOccupied(),
      razing = city:IsRazing(),
      resistance_turns = city:GetResistanceTurns(),
      blockaded = city:IsBlockaded(),
      capital = city:IsCapital(),
      original_owner = civ.civName(city:GetOriginalOwner()),
    }
  end

  local function cityRecord(city)
    local record = cityCore(city)
    addAll(record, cityCondition(city))
    addAll(record, cityYields(city))
    addAll(record, cityReligion(city))
    return record
  end

  -- PlayerDoTurn fires for city-states and barbarians as well, and their
  -- cities would multiply the record count for a fraction of the value.
  function civ.cityStats(playerId)
    local p = g.Players[playerId]
    if not isLivingMajor(p) then return {} end
    local stats = {}
    for city in p:Cities() do
      table.insert(stats, cityRecord(city))
    end
    return stats
  end


  -- Every column through which a rule can hand a city a building, read
  -- from the schema rather than listed by hand, so a mod that adds a
  -- wonder granting something new is covered without a code change.
  local FREE_BUILDING_COLUMNS = {
    Buildings = { "FreeBuildingThisCity", "FreeBuilding" },
    Traits    = { "FreeBuilding", "FreeCapitalBuilding", "FreeBuildingOnConquest" },
    Policies  = { "FreeBuildingOnConquest" },
  }

  local function buildingIndex()
    local byClass, classOf = {}, {}
    for row in g.GameInfo.Buildings() do
      byClass[row.BuildingClass] = byClass[row.BuildingClass] or {}
      table.insert(byClass[row.BuildingClass], row.Type)
      classOf[row.Type] = row.BuildingClass
    end
    return byClass, classOf
  end

  -- A column names either a class or one civ's version of it. The grant
  -- always resolves to the owner's version (CvCity.cpp:7391), so the class
  -- is what a rule really points at.
  -- Policies that grant a building without naming one: the schema carries
  -- a count and the DLL picks the building (CvPlayer::AwardFreeBuildings).
  -- Each entry mirrors what that chooser can return. Free walls are
  -- missing on purpose - they are handed over as a real building
  -- (CvPlayer.cpp:8631), which no scan of free buildings can see.
  local COUNTED_COLUMNS = {
    NumCitiesFreeFoodBuilding      = { "BUILDINGCLASS_AQUEDUCT" },
    NumCitiesFreePietyGardens      = { "BUILDINGCLASS_GARDEN" },
    NumCitiesFreeAestheticsSchools = { "BUILDING_SCRIPTORIUM", "BUILDING_GALLERY",
                                       "BUILDING_CONSERVATORY" },
  }

  local function collectClasses(classes, rows, columns, classOf)
    for row in rows() do
      for _, column in ipairs(columns) do
        local value = row[column]
        if value then classes[classOf[value] or value] = true end
      end
    end
  end

  -- CvCity::ChooseFreeCultureBuilding weighs culture against cost across
  -- every non-wonder building, so any of them can be the one handed over.
  local function cultureClasses(classes, classOf)
    local rows = g.GameInfo.Building_YieldChanges
    if not rows then return end
    for row in rows() do
      local class = classOf[row.BuildingType]
      if row.YieldType == "YIELD_CULTURE" and row.Yield > 0
        and class and not wonderScope(class) then
        classes[class] = true
      end
    end
  end

  local function collectCounted(classes, classOf)
    local rows = g.GameInfo.Policies
    if not rows then return end
    for row in rows() do
      for column, chosen in pairs(COUNTED_COLUMNS) do
        if isSet(row[column]) then
          for _, value in ipairs(chosen) do classes[classOf[value] or value] = true end
        end
      end
      if isSet(row.NumCitiesFreeCultureBuilding) then cultureClasses(classes, classOf) end
    end
  end

  local function grantableClasses(classOf)
    local classes = {}
    for tableName, columns in pairs(FREE_BUILDING_COLUMNS) do
      local rows = g.GameInfo[tableName]
      if rows then collectClasses(classes, rows, columns, classOf) end
    end
    collectCounted(classes, classOf)
    return classes
  end

  local function sortedKeys(t)
    local keys = {}
    for key in pairs(t) do table.insert(keys, key) end
    table.sort(keys)
    return keys
  end

  -- The buildings worth asking a city about, with the classes they came
  -- from for the poller to announce. Every version of a grantable class is
  -- a candidate, which is what saves us from resolving class to building
  -- per player.
  -- A rule may point at something this ruleset does not define; the class
  -- list is what we will really scan, so those drop out of both.
  local function scannable(classes, byClass)
    local kept = {}
    for _, class in ipairs(classes) do
      if byClass[class] then table.insert(kept, class) end
    end
    return kept
  end

  function civ.grantableBuildings()
    local byClass, classOf = buildingIndex()
    local classes = scannable(sortedKeys(grantableClasses(classOf)), byClass)
    local types = {}
    for _, class in ipairs(classes) do
      for _, buildingType in ipairs(byClass[class]) do
        table.insert(types, buildingType)
      end
    end
    table.sort(types)

    local candidates = {}
    for _, buildingType in ipairs(types) do
      table.insert(candidates, { id = g.GameInfoTypes[buildingType], type = buildingType })
    end
    return candidates, classes
  end

  -- Every building the ruleset defines. Too many to ask a city about every
  -- turn, but a city founded this turn is worth one full look: it was
  -- built by nobody, so whatever stands in it was handed over.
  function civ.allBuildings()
    local types = {}
    for row in g.GameInfo.Buildings() do table.insert(types, row.Type) end
    table.sort(types)

    local buildings = {}
    for _, buildingType in ipairs(types) do
      table.insert(buildings, { id = g.GameInfoTypes[buildingType], type = buildingType })
    end
    return buildings
  end

  local function standing(city, buildings, count)
    local held = {}
    for _, building in ipairs(buildings) do
      if count(city, building.id) > 0 then table.insert(held, building.type) end
    end
    return held
  end

  local function freeCount(city, id) return city:GetNumFreeBuilding(id) end
  local function anyCount(city, id) return city:GetNumBuilding(id) end

  -- What each city was given rather than built. GetNumBuildings() counts
  -- only real buildings (ChangeNumBuildings is reached from
  -- SetNumRealBuilding alone), so there is no cheaper gate than asking.
  -- The two turns travel with the city: a captured one keeps the founding
  -- turn of whoever founded it (CvPlayer.cpp:2851), so they agree only for
  -- a city this player founded.
  function civ.freeBuildings(playerId, candidates)
    local p = g.Players[playerId]
    if not isLivingMajor(p) then return {} end
    local cities = {}
    for city in p:Cities() do
      table.insert(cities, {
        id = city:GetID(),
        name = city:GetName(),
        founded = city:GetGameTurnFounded(),
        acquired = city:GetGameTurnAcquired(),
        buildings = standing(city, candidates, freeCount),
      })
    end
    return cities
  end

  -- Everything one city holds, free or real. Mod scripts hand out real
  -- buildings through SetNumRealBuildingClass without firing any hook, so
  -- a free-building scan alone would miss them.
  function civ.cityBuildings(playerId, cityId, buildings)
    local city = g.Players[playerId]:GetCityByID(cityId)
    if not city then return {} end
    return standing(city, buildings, anyCount)
  end

  function civ.livingMajors()
    local majors = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      if isLivingMajor(g.Players[i]) then majors[i] = civ.civName(i) end
    end
    return majors
  end

  -- Who ended up with a fallen civ's original capital. The city outlives
  -- the player, so this answers after the elimination as well as before,
  -- which is the only moment the roster poll can ask.
  function civ.capitalHolder(playerId)
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local p = g.Players[i]
      if isLivingMajor(p) then
        for city in p:Cities() do
          if city:IsOriginalMajorCapital() and city:GetOriginalOwner() == playerId then
            return civ.civName(i)
          end
        end
      end
    end
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

  -- The trait is what an alliance pays out in. The personality is
  -- Lekmod's own layer over it (Minor_Civ_Personalities): it decides how
  -- fast influence decays, what a gift buys and whether the city-state
  -- takes tribute or quests at all. It is drawn at random once per game
  -- and kept only in the save, so nothing recovers it afterwards.
  --
  -- Where it sits decides who can reach it, and the map is not in the
  -- log anywhere else, so the plot travels with the identity.
  --
  -- Trait and personality are read as names rather than numbers: the
  -- empty string is how a build without personalities answers, and only
  -- militaristic city-states have a unit to gift. GetCapitalCity can
  -- answer nil; the entry then carries no plot rather than a made-up one.
  local function cityStateEntry(p)
    local personality = p:GetMinorCivPersonalityType()
    local capital = p:GetCapitalCity()
    return {
      civ = p:GetCivilizationShortDescription(),
      trait = typeOf(g.GameInfo.MinorCivTraits[p:GetMinorCivTrait()]),
      personality = personality ~= "" and personality or nil,
      unique_unit = p:IsMinorCivHasUniqueUnit()
        and civ.unitTypeName(p:GetMinorCivUniqueUnit()) or nil,
      x = capital and capital:GetX() or nil,
      y = capital and capital:GetY() or nil,
    }
  end

  function civ.cityStateRoster()
    local roster = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      if isLivingMinor(g.Players[i]) then
        table.insert(roster, cityStateEntry(g.Players[i]))
      end
    end
    return roster
  end

  local FRIENDSHIP_LEVELS = { [1] = "friend", [2] = "ally" }

  -- Where one major stands with one city-state. The three city_state_*
  -- hooks fire only when a threshold is crossed, so this is the only
  -- thing that says whether an alliance is held at 112 and sliding or at
  -- 61 and about to go. per_turn is what makes a sparse record enough:
  -- the curve between two snapshots is read back from the rate.
  --
  -- Protection is asked of the major, not of the city-state
  -- (CvLuaPlayer.cpp:8319). Nothing here is written when it is nothing -
  -- before contact every pair reads as zero, and most pairs never leave
  -- that state.
  local function cityStateRelation(minor, minorId, major, majorId)
    local influence = minor:GetMinorCivFriendshipWithMajor(majorId)
    local perTurn = minor:GetFriendshipChangePerTurnTimes100(majorId)
    local level = FRIENDSHIP_LEVELS[minor:GetMinorCivFriendshipLevelWithMajor(majorId)]
    local protected = major:IsProtectingMinor(minorId)
    if influence == 0 and perTurn == 0 and not level and not protected then
      return nil
    end
    return {
      civ = major:GetCivilizationShortDescription(),
      influence = influence ~= 0 and influence or nil,
      per_turn = perTurn ~= 0 and perTurn / 100 or nil,
      level = level,
      protected = protected or nil,
    }
  end

  local function cityStateRelations(minor, minorId)
    local relations = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      if isLivingMajor(g.Players[i]) then
        relations[i] = cityStateRelation(minor, minorId, g.Players[i], i)
      end
    end
    return relations
  end

  -- GetAlly answers NO_PLAYER when nobody holds it, which is -1.
  function civ.cityStateSnapshot()
    local snapshot = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local p = g.Players[i]
      if isLivingMinor(p) then
        local ally = p:GetAlly()
        snapshot[i] = {
          civ = p:GetCivilizationShortDescription(),
          ally = ally >= 0 and civ.civName(ally) or nil,
          relations = cityStateRelations(p, i),
        }
      end
    end
    return snapshot
  end

  local TRADE_CONNECTIONS = { [0] = "international", [1] = "food", [2] = "production" }

  -- DomainTypes is not a two-value enum: DOMAIN_AIR sits between sea and
  -- land, so land is 2 (CvEnums.h:1490-1497).
  local TRADE_DOMAINS = { [0] = "sea", [2] = "land" }

  local function nonZero(value)
    return value ~= 0 and value or nil
  end

  local function scaledNonZero(value)
    return value ~= 0 and value / 100 or nil
  end

  -- A caravan pushes each city's own majority religion at the other, so
  -- both directions are read. Nothing is answered when the source city
  -- has no majority, and also when the two cities sit within
  -- RELIGION_ADJACENT_CITY_DISTANCE (CvReligionClasses.cpp:3802-3812):
  -- proximity already spreads the faith and the route adds nothing on
  -- top, which is the usual case for a short domestic caravan.
  local function pressureOf(religionId, pressure)
    if pressure == 0 or religionId < 0 then return nil, nil end
    return civ.religionName(religionId), pressure
  end

  local function tradeRouteRecord(row)
    local toReligion, toPressure = pressureOf(row.ToReligion, row.ToPressure)
    local fromReligion, fromPressure = pressureOf(row.FromReligion, row.FromPressure)
    return {
      civ = civ.civName(row.FromID),
      from_city = row.FromCityName,
      to_civ = civ.civName(row.ToID),
      to_city = row.ToCityName,
      type = TRADE_CONNECTIONS[row.ConnectionType],
      domain = TRADE_DOMAINS[row.Domain],
      turns_left = row.TurnsLeft,
      from_gold = scaledNonZero(row.FromGPT),
      to_gold = scaledNonZero(row.ToGPT),
      to_food = scaledNonZero(row.ToFood),
      to_production = scaledNonZero(row.ToProduction),
      from_science = scaledNonZero(row.FromScience),
      to_science = scaledNonZero(row.ToScience),
      from_tourism = nonZero(row.FromTourism),
      to_tourism = nonZero(row.ToTourism),
      to_religion = toReligion,
      to_pressure = toPressure,
      from_religion = fromReligion,
      from_pressure = fromPressure,
    }
  end

  -- A route has no id Lua can see, so the poller diffs on this key. The
  -- two plots are exactly what the DLL forbids a second route with:
  -- CvGameTrade::CanCreateTradeRoute compares origin and destination
  -- coordinates and nothing else - not the domain, type or owner
  -- (CvTradeClasses.cpp:225-240). The arrow is directed because the same
  -- road running back the other way is its own route, earning its own
  -- side its own gold. Plots rather than names, because a city can be
  -- renamed or captured and keep carrying the route.
  local function tradeRouteKey(row)
    return row.FromCity:GetX() .. "," .. row.FromCity:GetY()
      .. ">" .. row.ToCity:GetX() .. "," .. row.ToCity:GetY()
  end

  -- GetTradeRoutes lists only what the player originates, so asking
  -- every major covers each route exactly once. GetTradeRoutesToYou is
  -- its mirror and would count them twice.
  function civ.tradeRoutes()
    local routes = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      if isLivingMajor(g.Players[i]) then
        for _, row in ipairs(g.Players[i]:GetTradeRoutes()) do
          routes[tradeRouteKey(row)] = tradeRouteRecord(row)
        end
      end
    end
    return routes
  end

  local SPY_RANKS = {
    TXT_KEY_SPY_RANK_0 = "recruit",
    TXT_KEY_SPY_RANK_1 = "agent",
    TXT_KEY_SPY_RANK_2 = "special_agent",
  }

  local SPY_STATES = {
    TXT_KEY_SPY_STATE_UNASSIGNED = "unassigned",
    TXT_KEY_SPY_STATE_TRAVELLING = "travelling",
    TXT_KEY_SPY_STATE_SURVEILLANCE = "surveillance",
    TXT_KEY_SPY_STATE_GATHERING_INTEL = "gathering_intel",
    TXT_KEY_SPY_STATE_RIGGING_ELECTION = "rigging_election",
    TXT_KEY_SPY_STATE_COUNTER_INTEL = "counter_intel",
    TXT_KEY_SPY_STATE_MAKING_INTRODUCTIONS = "making_introductions",
    TXT_KEY_SPY_STATE_SCHMOOZING = "schmoozing",
    TXT_KEY_SPY_STATE_DEAD = "dead",
  }

  -- Rank and state arrive as translation keys rather than numbers
  -- (CvLuaPlayer.cpp:11580-11630); the log carries names.
  --
  -- Progress and turns left are absent when negative, not when zero. A
  -- state with no end time - unassigned, counter-intel, schmoozing,
  -- dead - answers -1 (CvEspionageClasses.cpp:2504-2514), while zero is
  -- a spy that has just arrived and begun, which the poller has to be
  -- able to tell from a mission that finished and reset.
  --
  -- Both the name and the AgentID go out. The DLL redraws the name when
  -- it revives a spy into the same slot (CvEspionageClasses.cpp:928-936),
  -- so the name is a label for a reader and the id is the identity a
  -- career can be followed by.
  local function spyRecord(p, row)
    local record = {
      civ = p:GetCivilizationShortDescription(),
      agent = row.AgentID,
      spy = row.Name,
      rank = SPY_RANKS[row.Rank],
      state = SPY_STATES[row.State],
      turns_left = row.TurnsLeft >= 0 and row.TurnsLeft or nil,
      progress = row.PercentComplete >= 0 and row.PercentComplete or nil,
      surveillance = row.EstablishedSurveillance or nil,
      diplomat = row.IsDiplomat or nil,
    }
    if row.CityX >= 0 then
      record.city = civ.cityNameAt(row.CityX, row.CityY)
      record.city_civ = civ.cityOwnerAt(row.CityX, row.CityY)
      record.x, record.y = row.CityX, row.CityY
    end
    return record
  end

  -- Keyed on player and AgentID because that pair is stable for the
  -- whole game: AgentID is the index into m_aSpyList and the list only
  -- grows - a killed spy stays in it marked dead and later revives in
  -- the same slot under a new name (CvEspionageClasses.cpp:928-936).
  --
  -- Every major is asked, so this is the whole board including spies
  -- their targets never noticed. No era gate: before the Renaissance
  -- m_aSpyList is empty and the loop body never runs.
  function civ.spies()
    local spies = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local p = g.Players[i]
      if isLivingMajor(p) then
        for _, row in ipairs(p:GetEspionageSpies()) do
          spies[i .. ":" .. row.AgentID] = spyRecord(p, row)
        end
      end
    end
    return spies
  end

  -- Both are NO_TEAM/NO_VICTORY (-1) until the game is decided, and the
  -- game sets them together (CvGame::setWinner), so the team alone
  -- answers "is it over".
  function civ.victory()
    local team = g.Game.GetWinner()
    if not team or team < 0 then return nil end
    return {
      winner_team = team,
      winner_civs = civ.teamCivNames(team),
      victory = typeOf(g.GameInfo.Victories[g.Game.GetVictory()]),
      winning_turn = g.Game.GetWinningTurn(),
    }
  end


  -- Friendship is a player fact, the treaties and open borders are team
  -- facts, so one pair entry is assembled from both. Read for every
  -- ordered pair: open borders and embassies belong to the granting
  -- side, and the poller decides which facts are mutual.
  local function diplomacyPair(a, b)
    local teamA, teamB = g.Teams[g.Players[a]:GetTeam()], g.Players[b]:GetTeam()
    return {
      dof = g.Players[a]:IsDoF(b),
      open_borders = teamA:IsAllowsOpenBordersToTeam(teamB),
      embassy = teamA:HasEmbassyAtTeam(teamB),
      defensive_pact = teamA:IsDefensivePact(teamB),
      trade_agreement = teamA:IsHasTradeAgreement(teamB),
    }
  end

  function civ.diplomacySnapshot()
    local snapshot = {}
    for a = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      if isLivingMajor(g.Players[a]) then
        snapshot[a] = {}
        for b = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
          if a ~= b and isLivingMajor(g.Players[b]) then
            snapshot[a][b] = diplomacyPair(a, b)
          end
        end
      end
    end
    return snapshot
  end

  local function resolutionType(id)
    return typeOf(g.GameInfo.Resolutions[id])
  end

  -- The columns CvResolutionEffects::HasOngoingEffects tests
  -- (CvVotingClasses.cpp:245). A resolution with none of them set expires
  -- the moment it is enacted and never joins the active resolutions, so
  -- its outcome cannot be read from that list. Read here rather than
  -- hardcoded as a list of resolution types, which the mod can extend.
  local ongoingEffectColumns = {
    "GoldPerTurn",
    "ResourceQuantity",
    "EmbargoCityStates",
    "EmbargoPlayer",
    "NoResourceHappiness",
    "UnitMaintenanceGoldPercent",
    "MemberDiscoveredTechMod",
    "CulturePerWonder",
    "CulturePerNaturalWonder",
    "NoTrainingNuclearWeapons",
    "VotesForFollowingReligion",
    "HolyCityTourism",
    "ReligionSpreadStrengthMod",
    "VotesForFollowingIdeology",
    "OtherIdeologyRebellionMod",
    "ArtsyGreatPersonRateMod",
    "ScienceyGreatPersonRateMod",
    "GreatPersonTileImprovementCulture",
    "LandmarkCulture",
  }

  local function hasOngoingEffects(row)
    for _, column in ipairs(ongoingEffectColumns) do
      if isSet(row[column]) then return true end
    end
    return false
  end

  -- A proposal nobody raised answers ProposalPlayer -1, and Players has
  -- no such slot: calling a method on it is an error that costs the whole
  -- congress poll for that turn, not just this one field.
  local function proposalRecord(p, repeal)
    local row = g.GameInfo.Resolutions[p.Type]
    return {
      id = p.ID,
      type = typeOf(row),
      proposer = p.ProposalPlayer >= 0 and civ.civName(p.ProposalPlayer) or nil,
      repeal = repeal,
      ongoing_effects = row ~= nil and hasOngoingEffects(row),
      league_project = row and row.LeagueProjectEnabled or nil,
    }
  end

  local function leagueProjects(league)
    local projects = {}
    for row in g.GameInfo.LeagueProjects() do
      projects[row.Type] = {
        active = league:IsProjectActive(row.ID),
        complete = league:IsProjectComplete(row.ID),
      }
    end
    return projects
  end

  local function congressDelegates(league)
    local delegates = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      local p = g.Players[i]
      if isLivingMajor(p) then
        table.insert(delegates, {
          civ = p:GetCivilizationShortDescription(),
          votes = league:CalculateStartingVotesForMember(i),
          core_votes = league:GetCoreVotesForMember(i),
        })
      end
    end
    return delegates
  end

  function civ.congressSnapshot()
    local league = g.Game.GetActiveLeague()
    if not league then return nil end

    local proposals = {}
    for _, p in ipairs(league:GetEnactProposals()) do
      proposals[p.ID] = proposalRecord(p, false)
    end
    for _, p in ipairs(league:GetRepealProposals()) do
      proposals[p.ID] = proposalRecord(p, true)
    end

    local activeResolutions = {}
    for _, r in ipairs(league:GetActiveResolutions()) do
      activeResolutions[r.ID] = { id = r.ID, type = resolutionType(r.Type) }
    end

    local host = league:GetHostMember()
    return {
      host = host >= 0 and civ.civName(host) or nil,
      united_nations = league:IsUnitedNations(),
      votes_needed_for_diplo_victory = g.Game.GetVotesNeededForDiploVictory(),
      delegates = congressDelegates(league),
      proposals = proposals,
      active_resolutions = activeResolutions,
      projects = leagueProjects(league),
    }
  end

  -- LEKMOD's own multiplayer voting system. Its enums are handed on raw:
  -- the extractors name them, so both hooks name them the same way.
  function civ.proposalType(proposalId)
    return g.Game.GetProposalType(proposalId)
  end

  -- The vote hook announces only the votes a player casts: the owner's
  -- automatic yes and the noes filled in when a proposal expires never
  -- reach it, so a tally has to be read off the proposal itself.
  -- Unknown ids stop here, because GetNoVotes dereferences the proposal
  -- without a null check (CvVotingClasses.cpp:12236).
  function civ.proposalVotes(proposalId)
    if civ.proposalType(proposalId) < 0 then return nil end

    local voters = {}
    for i = 0, g.GameDefines.MAX_CIV_PLAYERS - 1 do
      if g.Game.GetProposalVoterEligibility(proposalId, i) then
        local voter = {
          civ = civ.civName(i),
          voted = g.Game.GetProposalVoterHasVoted(proposalId, i),
        }
        -- An unvoted slot is stored as false, which reads like a no.
        if voter.voted then
          voter.vote = g.Game.GetProposalVoterVote(proposalId, i)
        end
        table.insert(voters, voter)
      end
    end

    return {
      yes_votes = g.Game.GetYesVotes(proposalId),
      no_votes = g.Game.GetNoVotes(proposalId),
      max_votes = g.Game.GetMaxVotes(proposalId),
      voters = voters,
    }
  end

  return civ
end

return M
