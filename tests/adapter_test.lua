local t = require("tests.test_helper")
local adapter = require("src.adapter")

-- GameInfo tables answer both to an id and to a call that walks every
-- row; the fakes were only ever indexed, so the walk is added here.
local function queryable(rows)
  return setmetatable(rows, {
    __call = function(self)
      local keys = {}
      for key in pairs(self) do table.insert(keys, key) end
      table.sort(keys)
      local i = 0
      return function()
        i = i + 1
        return keys[i] and self[keys[i]] or nil
      end
    end,
  })
end

local function fakeCity(c)
  return {
        IsOriginalMajorCapital = function() return c.capital == true end,
        GetOriginalOwner = function() return c.originalOwner end,
        GetID = function() return c.id end,
        GetName = function() return c.name end,
        GetX = function() return c.x end,
        GetY = function() return c.y end,
        GetPopulation = function() return c.population end,
        GetFood = function() return c.foodStored end,
        GetFoodTurnsLeft = function() return c.foodTurnsLeft end,
        GetYieldRateTimes100 = function(_, yield) return (c.yields or {})[yield] or 0 end,
        GetProductionUnit = function() return c.productionUnit or -1 end,
        GetProductionBuilding = function() return c.productionBuilding or -1 end,
        GetProductionProject = function() return c.productionProject or -1 end,
        GetProductionTurnsLeft = function() return c.productionTurnsLeft end,
        GetProduction = function() return c.productionStored end,
        GetNumBuildings = function() return c.buildings end,
        GetNumFreeBuilding = function(_, id) return (c.freeBuildings or {})[id] or 0 end,
        GetNumBuilding = function(_, id)
          return ((c.freeBuildings or {})[id] or 0) + ((c.realBuildings or {})[id] or 0)
        end,
        GetGameTurnFounded = function() return c.founded end,
        GetGameTurnAcquired = function() return c.acquired end,
        GetDamage = function() return c.damage or 0 end,
        GetStrengthValue = function() return c.defense end,
        IsPuppet = function() return c.puppet == true end,
        IsOccupied = function() return c.occupied == true end,
        IsRazing = function() return c.razing == true end,
        GetResistanceTurns = function() return c.resistanceTurns or 0 end,
        IsBlockaded = function() return c.blockaded == true end,
        GetReligiousMajority = function() return c.religion or -1 end,
        GetNumFollowers = function(_, religion)
          return religion == c.religion and c.followers or 0
        end,
        IsCapital = function() return c.isCapital == true end,
  }
end

local function fakePlayer(spec)
  return {
    IsAlive = function() return spec.alive ~= false end,
    IsMinorCiv = function() return spec.minor == true end,
    IsBarbarian = function() return spec.barbarian == true end,
    GetTeam = function() return spec.team or 0 end,
    GetCivilizationShortDescription = function() return spec.civ end,
    GetName = function() return spec.name end,
    IsHuman = function() return spec.human == true end,
    GetHandicapType = function() return spec.handicap end,
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
    GetUnitByID = function(_, id)
      if id == spec.unitId then
        return { GetUnitType = function() return spec.unitTypeId end }
      end
    end,
    GetTourism = function() return spec.tourism end,
    GetNumCivsInfluentialOn = function() return spec.civsInfluentialOn end,
    GetInfluenceOn = function(_, otherId)
      return spec.influenceOn and spec.influenceOn[otherId]
    end,
    GetInfluenceLevel = function(_, otherId)
      return spec.influenceLevel and spec.influenceLevel[otherId]
    end,
    GetInfluenceTrend = function(_, otherId)
      return spec.influenceTrend and spec.influenceTrend[otherId]
    end,
    CalculateTotalYield = function(_, yieldTypeId)
      if yieldTypeId == "YIELD_PRODUCTION" then return spec.production end
      if yieldTypeId == "YIELD_FOOD" then return spec.food end
    end,
    CalculateGrossGold = function() return spec.grossGold end,
    GetNumPlots = function() return spec.plots end,
    GetFaith = function() return spec.faithStored end,
    GetJONSCulture = function() return spec.cultureStored end,
    GetNextPolicyCost = function() return spec.nextPolicyCost end,
    GetNumPolicies = function() return spec.policies end,
    GetCurrentResearch = function() return spec.researching end,
    GetResearchTurnsLeft = function(_, techId, overflow)
      if techId == spec.researching and overflow == true then
        return spec.researchTurnsLeft
      end
    end,
    GetGoldenAgeTurns = function() return spec.goldenAgeTurns end,
    GetGoldenAgeProgressMeter = function() return spec.goldenAgeProgress end,
    GetGoldenAgeProgressThreshold = function() return spec.goldenAgeThreshold end,
    GetAnarchyNumTurns = function() return spec.anarchyTurns end,
    GetLateGamePolicyTree = function() return spec.ideology end,
    GetPublicOpinionType = function() return spec.publicOpinion end,
    GetPublicOpinionUnhappiness = function() return spec.publicOpinionUnhappiness end,
    GetPublicOpinionPreferredIdeology = function() return spec.preferredIdeology end,
    GetGreatPeopleCreated = function() return spec.greatPeople end,
    GetGreatGeneralsCreated = function() return spec.greatGenerals end,
    GetNumResourceTotal = function(_, id) return (spec.resourceTotal or {})[id] or 0 end,
    GetNumResourceUsed = function(_, id) return (spec.resourceUsed or {})[id] or 0 end,
    GetResourceImport = function(_, id) return (spec.resourceImport or {})[id] or 0 end,
    GetResourceExport = function(_, id) return (spec.resourceExport or {})[id] or 0 end,
    Cities = function()
      local list = spec.citiesList or {}
      local i = 0
      return function()
        i = i + 1
        return list[i] and fakeCity(list[i]) or nil
      end
    end,
    GetCityByID = function(_, id)
      for _, c in ipairs(spec.citiesList or {}) do
        if c.id == id then return fakeCity(c) end
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
    GetGameSpeedType = function() return 1 end,
    GetMaxTurns = function() return 330 end,
    GetStartEra = function() return 2 end,
  },
  PreGame = {
    GetMapScript = function() return "Assets/Maps/Lekmap.lua" end,
  },
  Modding = {
    GetActivatedMods = function()
      return {
        { ID = "b2be3c8b-5f00-4d3e-9c00-000000000000", Version = 34 },
        { ID = "e1ccf71a-f248-498c-8f30-5ca6d851079d", Version = 1 },
      }
    end,
  },
  YieldTypes = {
    YIELD_FOOD = "YIELD_FOOD",
    YIELD_PRODUCTION = "YIELD_PRODUCTION",
    YIELD_GOLD = "YIELD_GOLD",
    YIELD_SCIENCE = "YIELD_SCIENCE",
    YIELD_CULTURE = "YIELD_CULTURE",
    YIELD_FAITH = "YIELD_FAITH",
  },
  PublicOpinionTypes = {
    NO_PUBLIC_OPINION = -1,
    PUBLIC_OPINION_CONTENT = 0,
    PUBLIC_OPINION_DISSIDENTS = 1,
    PUBLIC_OPINION_CIVIL_RESISTANCE = 2,
    PUBLIC_OPINION_REVOLUTIONARY_WAVE = 3,
  },
  GameInfoTypes = {
    PROJECT_APOLLO_PROGRAM = "PROJECT_APOLLO_PROGRAM",
    PROJECT_SS_BOOSTER = "PROJECT_SS_BOOSTER",
    PROJECT_SS_COCKPIT = "PROJECT_SS_COCKPIT",
    PROJECT_SS_STASIS_CHAMBER = "PROJECT_SS_STASIS_CHAMBER",
    PROJECT_SS_ENGINE = "PROJECT_SS_ENGINE",
    BUILDING_LIBRARY = 12,
    BUILDING_ROYAL_LIBRARY = 13,
    BUILDING_HARBOR = 14,
    BUILDING_COTHON = 15,
    BUILDING_AQUEDUCT = 16,
    BUILDING_GARDEN = 17,
    BUILDING_MONUMENT = 18,
    BUILDING_SCRIPTORIUM = 19,
    BUILDING_GRANARY = 5,
    BUILDING_PYRAMIDS = 7,
    BUILDING_NATIONAL_COLLEGE = 8,
    BUILDING_GREAT_LIBRARY = 11,
  },
  GameDefines = { MAX_CIV_PLAYERS = 3 },
  Players = {
    [0] = fakePlayer({
      civ = "Poland", team = 0,
      name = "dysk", human = true, handicap = 5,
      faithStored = 480, cultureStored = 1250,
      nextPolicyCost = 720, policies = 11,
      researching = 12, researchTurnsLeft = 4,
      goldenAgeTurns = 0, goldenAgeProgress = 310, goldenAgeThreshold = 500,
      anarchyTurns = 0, ideology = 9, preferredIdeology = 10,
      publicOpinion = 1, publicOpinionUnhappiness = 6,
      greatPeople = 3, greatGenerals = 2,
      resourceTotal = { [1] = 8, [2] = 6, [3] = 1 },
      resourceUsed = { [1] = 5 },
      resourceImport = { [3] = 1 },
      resourceExport = { [1] = 2 },
      cityId = 3, cityName = "Warsaw",
      unitId = 9, unitTypeId = 5,
      score = 1200, gold = 340, goldRate100 = 1250, science100 = 4800,
      culture = 30, faith = 10, happiness = 7, cities = 5,
      population = 41, might = 5600, militaryUnits = 14,
      tourism = 45, civsInfluentialOn = 1,
      influenceOn = { [1] = 320 },
      influenceLevel = { [1] = 4 },
      influenceTrend = { [1] = 1 },
      production = 62, food = 18, grossGold = 45, plots = 87,
      citiesList = {
        { id = 3, name = "Warsaw", x = 10, y = 20, originalOwner = 0, capital = true,
          isCapital = true, population = 12, foodStored = 34, foodTurnsLeft = 6,
          productionBuilding = 7, productionTurnsLeft = 9, productionStored = 140,
          yields = { YIELD_FOOD = 1450, YIELD_PRODUCTION = 980, YIELD_GOLD = 620,
                     YIELD_SCIENCE = 1130, YIELD_CULTURE = 400, YIELD_FAITH = 210 },
          buildings = 14, defense = 3200, religion = 4, followers = 9,
          founded = 1, acquired = 1, freeBuildings = { [12] = 1 } },
        { id = 7, name = "Rome (captured)", x = 15, y = 22, originalOwner = 1, capital = true,
          population = 8, foodStored = 12, foodTurnsLeft = 11,
          productionUnit = 5, productionTurnsLeft = 3, productionStored = 20,
          buildings = 9, defense = 1800, damage = 45,
          puppet = true, occupied = true, resistanceTurns = 3, blockaded = true,
          founded = 12, acquired = 88, realBuildings = { [18] = 1 } },
        { id = 9, name = "Krakow", x = 11, y = 21, originalOwner = 1, capital = false,
          population = 5, foodStored = 8, foodTurnsLeft = 14,
          productionTurnsLeft = 0, productionStored = 0, buildings = 4, defense = 900,
          founded = 40, acquired = 40, freeBuildings = { [14] = 1 } },
      },
    }),
    [1] = fakePlayer({ civ = "Rome", team = 1, name = "Augustus", handicap = 5,
                       goldRate100 = 0, science100 = 0, researching = -1 }),
    [2] = fakePlayer({ civ = "Carthage", team = 1, alive = false }),
    [3] = fakePlayer({ civ = "Venice", minor = true,
                       citiesList = { { id = 21, name = "Venice", x = 30, y = 8 } } }),
    [4] = fakePlayer({ civ = "Barbarians", barbarian = true }),
  },
  Teams = {
    [0] = {
      GetTeamTechs = function()
        return { GetNumTechsKnown = function() return 24 end }
      end,
      GetProjectCount = function(_, projectId)
        local counts = {
          PROJECT_APOLLO_PROGRAM = 1,
          PROJECT_SS_BOOSTER = 2,
          PROJECT_SS_COCKPIT = 1,
          PROJECT_SS_STASIS_CHAMBER = 0,
          PROJECT_SS_ENGINE = 1,
        }
        return counts[projectId] or 0
      end,
    },
    [1] = {
      GetTeamTechs = function()
        return { GetNumTechsKnown = function() return 19 end }
      end,
      GetProjectCount = function() return 0 end,
    },
  },
  Map = {
    GetWorldSize = function() return 1 end,
    GetGridSize = function() return 44, 26 end,
    GetPlot = function(x, y)
      return {
        GetPlotCity = function()
          if x == 10 and y == 20 then
            return {
              GetName = function() return "Warsaw" end,
              GetOwner = function() return 0 end,
            }
          end
        end,
      }
    end,
  },
  GameInfo = {
    Technologies = { [12] = { Type = "TECH_POTTERY" } },
    Units = { [5] = { Type = "UNIT_SETTLER" } },
    Projects = { [2] = { Type = "PROJECT_APOLLO_PROGRAM" } },
    Buildings = queryable({
      [7] = { Type = "BUILDING_PYRAMIDS", BuildingClass = "BUILDINGCLASS_PYRAMIDS" },
      [5] = { Type = "BUILDING_GRANARY", BuildingClass = "BUILDINGCLASS_GRANARY" },
      [8] = { Type = "BUILDING_NATIONAL_COLLEGE",
              BuildingClass = "BUILDINGCLASS_NATIONAL_COLLEGE" },
      [11] = { Type = "BUILDING_GREAT_LIBRARY", BuildingClass = "BUILDINGCLASS_GREAT_LIBRARY",
               FreeBuildingThisCity = "BUILDINGCLASS_LIBRARY" },
      [12] = { Type = "BUILDING_LIBRARY", BuildingClass = "BUILDINGCLASS_LIBRARY" },
      [13] = { Type = "BUILDING_ROYAL_LIBRARY", BuildingClass = "BUILDINGCLASS_LIBRARY" },
      [14] = { Type = "BUILDING_HARBOR", BuildingClass = "BUILDINGCLASS_HARBOR" },
      [15] = { Type = "BUILDING_COTHON", BuildingClass = "BUILDINGCLASS_HARBOR" },
      [16] = { Type = "BUILDING_AQUEDUCT", BuildingClass = "BUILDINGCLASS_AQUEDUCT" },
      [17] = { Type = "BUILDING_GARDEN", BuildingClass = "BUILDINGCLASS_GARDEN" },
      [18] = { Type = "BUILDING_MONUMENT", BuildingClass = "BUILDINGCLASS_MONUMENT" },
      [19] = { Type = "BUILDING_SCRIPTORIUM", BuildingClass = "BUILDINGCLASS_SCRIPTORIUM" },
    }),
    -- What ChooseFreeCultureBuilding weighs: culture per cost, wonders out.
    Building_YieldChanges = queryable({
      [1] = { BuildingType = "BUILDING_MONUMENT", YieldType = "YIELD_CULTURE", Yield = 2 },
      [2] = { BuildingType = "BUILDING_PYRAMIDS", YieldType = "YIELD_CULTURE", Yield = 3 },
      [3] = { BuildingType = "BUILDING_LIBRARY", YieldType = "YIELD_SCIENCE", Yield = 3 },
    }),
    -- Carthage's trait, which names a building rather than its class. The
    -- grant resolves per civ, so every version of that class is a candidate.
    Traits = queryable({
      [1] = { Type = "TRAIT_PHOENICIAN_HERITAGE", FreeBuilding = "BUILDING_HARBOR" },
      [2] = { Type = "TRAIT_NONE" },
    }),
    BuildingClasses = {
      BUILDINGCLASS_PYRAMIDS = { MaxGlobalInstances = 1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_GRANARY = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_NATIONAL_COLLEGE = { MaxGlobalInstances = -1, MaxPlayerInstances = 1 },
      BUILDINGCLASS_GREAT_LIBRARY = { MaxGlobalInstances = 1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_LIBRARY = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_HARBOR = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_AQUEDUCT = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_GARDEN = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_MONUMENT = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_SCRIPTORIUM = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
    },
    Beliefs = { [10] = { Type = "BELIEF_TITHE" } },
    Eras = { [2] = { Type = "ERA_CLASSICAL" } },
    Policies = queryable({
      [6] = { Type = "POLICY_LIBERTY" },
      [20] = { Type = "POLICY_TRADITION_FINISHER", NumCitiesFreeFoodBuilding = 4 },
      [21] = { Type = "POLICY_LEGALISM", NumCitiesFreeCultureBuilding = 4 },
      [22] = { Type = "POLICY_PIETY_FINISHER", NumCitiesFreePietyGardens = 4 },
      [23] = { Type = "POLICY_FINE_ARTS", NumCitiesFreeAestheticsSchools = 99 },
    }),
    PolicyBranchTypes = {
      [2] = { Type = "POLICY_BRANCH_HONOR" },
      [9] = { Type = "POLICY_BRANCH_FREEDOM" },
      [10] = { Type = "POLICY_BRANCH_ORDER" },
    },
    Resources = function()
      local rows = {
        { ID = 1, Type = "RESOURCE_IRON", ResourceUsage = 1 },
        { ID = 2, Type = "RESOURCE_WHEAT", ResourceUsage = 0 },
        { ID = 3, Type = "RESOURCE_SILK", ResourceUsage = 2 },
        { ID = 4, Type = "RESOURCE_HORSE", ResourceUsage = 1 },
      }
      local i = 0
      return function()
        i = i + 1
        return rows[i]
      end
    end,
    UnitPromotions = { [3] = { Type = "PROMOTION_MORALE" } },
    Improvements = { [17] = { Type = "IMPROVEMENT_FARM" } },
    Features = { [21] = { Type = "FEATURE_EL_DORADO" } },
    Worlds = { [1] = { Type = "WORLDSIZE_STANDARD" } },
    GameSpeeds = { [1] = { Type = "GAMESPEED_QUICK" } },
    HandicapInfos = { [5] = { Type = "HANDICAP_KING" } },
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

t.test("citySet maps a player's current cities by id", function()
  t.assert_deep_equal({
    [3] = { name = "Warsaw", x = 10, y = 20 },
    [7] = { name = "Rome (captured)", x = 15, y = 22 },
    [9] = { name = "Krakow", x = 11, y = 21 },
  }, civ.citySet(0))
end)

t.test("cityStats reads the full record for a city", function()
  t.assert_deep_equal({
    city = "Warsaw",
    x = 10,
    y = 20,
    population = 12,
    food_stored = 34,
    food_turns_left = 6,
    producing = "BUILDING_PYRAMIDS",
    producing_kind = "building",
    production_turns_left = 9,
    production_stored = 140,
    yield_food = 14.5,
    yield_production = 9.8,
    yield_gold = 6.2,
    yield_science = 11.3,
    yield_culture = 4,
    yield_faith = 2.1,
    buildings = 14,
    damage = 0,
    defense = 3200,
    puppet = false,
    occupied = false,
    razing = false,
    resistance_turns = 0,
    blockaded = false,
    religion = "Buddhism",
    religion_followers = 9,
    capital = true,
    original_owner = "Poland",
  }, civ.cityStats(0)[1])
end)

-- The three production getters answer -1 for the two kinds the city is
-- not building, so what is on the queue takes naming both halves.
t.test("cityStats names a unit under construction", function()
  local city = civ.cityStats(0)[2]
  t.assert_deep_equal({ producing = "UNIT_SETTLER", producing_kind = "unit" },
    { producing = city.producing, producing_kind = city.producing_kind })
end)

t.test("cityStats leaves production empty when the city builds nothing", function()
  local city = civ.cityStats(0)[3]
  t.assert_deep_equal({ producing = nil, producing_kind = nil },
    { producing = city.producing, producing_kind = city.producing_kind })
end)

t.test("cityStats omits the religion when no faith holds a majority", function()
  t.assert_nil(civ.cityStats(0)[3].religion)
end)

-- A captured city is the one place the log can show a siege in progress
-- and an empire it cannot govern.
t.test("cityStats records occupation, resistance and damage", function()
  local city = civ.cityStats(0)[2]
  t.assert_deep_equal({
    puppet = true, occupied = true, resistance_turns = 3,
    blockaded = true, damage = 45, original_owner = "Rome",
  }, {
    puppet = city.puppet, occupied = city.occupied,
    resistance_turns = city.resistance_turns, blockaded = city.blockaded,
    damage = city.damage, original_owner = city.original_owner,
  })
end)

-- PlayerDoTurn fires for city-states too, and their cities would double
-- the record count for a fraction of the value.
t.test("cityStats is empty for a city-state", function()
  t.assert_deep_equal({}, civ.cityStats(3))
end)

t.test("livingMajors maps the surviving major civs by player id", function()
  t.assert_deep_equal({ [0] = "Poland", [1] = "Rome" }, civ.livingMajors())
end)

-- The city outlives the player, so the holder of a fallen capital is
-- readable after the elimination, not only before it.
t.test("capitalHolder names who holds a fallen civ's original capital", function()
  t.assert_equal("Poland", civ.capitalHolder(1))
end)

t.test("capitalHolder is nil when nobody holds it", function()
  t.assert_nil(civ.capitalHolder(2))
end)

t.test("techType resolves a tech id to its Type string", function()
  t.assert_equal("TECH_POTTERY", civ.techType(12))
end)

t.test("buildingType resolves a building id to its Type string", function()
  t.assert_equal("BUILDING_PYRAMIDS", civ.buildingType(7))
end)

t.test("wonderClass is world for world wonders", function()
  t.assert_equal("world", civ.wonderClass(7))
end)

t.test("wonderClass is national for national wonders", function()
  t.assert_equal("national", civ.wonderClass(8))
end)

t.test("wonderClass is nil for ordinary buildings", function()
  t.assert_nil(civ.wonderClass(5))
end)

local function grantableClassSet()
  local _, classes = civ.grantableBuildings()
  local set = {}
  for _, class in ipairs(classes) do set[class] = true end
  return set
end

t.test("grantableBuildings expands every grantable class to all its versions", function()
  t.assert_deep_equal({
    { id = 16, type = "BUILDING_AQUEDUCT" },
    { id = 15, type = "BUILDING_COTHON" },
    { id = 17, type = "BUILDING_GARDEN" },
    { id = 14, type = "BUILDING_HARBOR" },
    { id = 12, type = "BUILDING_LIBRARY" },
    { id = 18, type = "BUILDING_MONUMENT" },
    { id = 13, type = "BUILDING_ROYAL_LIBRARY" },
    { id = 19, type = "BUILDING_SCRIPTORIUM" },
  }, (civ.grantableBuildings()))
end)

t.test("grantableBuildings also names the classes it covers", function()
  local _, classes = civ.grantableBuildings()
  t.assert_deep_equal({
    "BUILDINGCLASS_AQUEDUCT", "BUILDINGCLASS_GARDEN", "BUILDINGCLASS_HARBOR",
    "BUILDINGCLASS_LIBRARY", "BUILDINGCLASS_MONUMENT", "BUILDINGCLASS_SCRIPTORIUM",
  }, classes)
end)

t.test("grantableBuildings leaves out a wonder that happens to yield culture", function()
  t.assert_nil(grantableClassSet()["BUILDINGCLASS_PYRAMIDS"])
end)

t.test("grantableBuildings leaves out a chosen building the game does not define", function()
  t.assert_nil(grantableClassSet()["BUILDING_GALLERY"])
end)

t.test("freeBuildings reports what a city was given, never what it built", function()
  t.assert_deep_equal({
    { id = 3, name = "Warsaw", founded = 1, acquired = 1, buildings = { "BUILDING_LIBRARY" } },
    { id = 7, name = "Rome (captured)", founded = 12, acquired = 88, buildings = {} },
    { id = 9, name = "Krakow", founded = 40, acquired = 40, buildings = { "BUILDING_HARBOR" } },
  }, civ.freeBuildings(0, (civ.grantableBuildings())))
end)

t.test("allBuildings lists every building the game defines, id and type", function()
  t.assert_deep_equal({
    { id = 16, type = "BUILDING_AQUEDUCT" },
    { id = 15, type = "BUILDING_COTHON" },
    { id = 17, type = "BUILDING_GARDEN" },
    { id = 5, type = "BUILDING_GRANARY" },
    { id = 11, type = "BUILDING_GREAT_LIBRARY" },
    { id = 14, type = "BUILDING_HARBOR" },
    { id = 12, type = "BUILDING_LIBRARY" },
    { id = 18, type = "BUILDING_MONUMENT" },
    { id = 8, type = "BUILDING_NATIONAL_COLLEGE" },
    { id = 7, type = "BUILDING_PYRAMIDS" },
    { id = 13, type = "BUILDING_ROYAL_LIBRARY" },
    { id = 19, type = "BUILDING_SCRIPTORIUM" },
  }, civ.allBuildings())
end)

t.test("cityBuildings answers with what stands, built or given", function()
  t.assert_deep_equal(
    { "BUILDING_MONUMENT" },
    civ.cityBuildings(0, 7, civ.allBuildings())
  )
end)

t.test("cityBuildings is empty for a city the player does not hold", function()
  t.assert_deep_equal({}, civ.cityBuildings(0, 99, civ.allBuildings()))
end)

t.test("freeBuildings is empty for a city-state", function()
  t.assert_deep_equal({}, civ.freeBuildings(3, (civ.grantableBuildings())))
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

t.test("policyBranchType resolves a branch id to its Type string", function()
  t.assert_equal("POLICY_BRANCH_HONOR", civ.policyBranchType(2))
end)

t.test("promotionType resolves a promotion id to its Type string", function()
  t.assert_equal("PROMOTION_MORALE", civ.promotionType(3))
end)

t.test("improvementType resolves an improvement id to its Type string", function()
  t.assert_equal("IMPROVEMENT_FARM", civ.improvementType(17))
end)

t.test("cityOwnerAt names the civ owning the city on a plot", function()
  t.assert_equal("Poland", civ.cityOwnerAt(10, 20))
end)

t.test("cityOwnerAt is nil for a plot without a city", function()
  t.assert_nil(civ.cityOwnerAt(0, 0))
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
    tourism = 45,
    civs_influential_on = 1,
    influence = {
      { civ = "Rome", points = 320, level = "INFLUENCE_LEVEL_INFLUENTIAL",
        trend = "INFLUENCE_TREND_RISING" },
    },
    production = 62,
    food = 18,
    gross_gold = 45,
    plots = 87,
    faith_stored = 480,
    culture_stored = 1250,
    next_policy_cost = 720,
    policies = 11,
    researching = "TECH_POTTERY",
    research_turns_left = 4,
    golden_age_turns = 0,
    golden_age_progress = 310,
    golden_age_threshold = 500,
    anarchy_turns = 0,
    ideology = "POLICY_BRANCH_FREEDOM",
    public_opinion = "PUBLIC_OPINION_DISSIDENTS",
    public_opinion_unhappiness = 6,
    preferred_ideology = "POLICY_BRANCH_ORDER",
    great_people = 3,
    great_generals = 2,
    resources = {
      { resource = "RESOURCE_IRON", total = 8, used = 5, import = 0, export = 2 },
      { resource = "RESOURCE_SILK", total = 1, used = 0, import = 1, export = 0 },
    },
    capitals = { "Poland", "Rome" },
    spaceship = {
      apollo = 1,
      booster = 2,
      cockpit = 1,
      stasis_chamber = 0,
      engine = 1,
    },
  }, civ.playerStats(0))
end)

-- What a civ is aiming at is the one thing tech_researched never says,
-- and between two techs there is nothing to aim at.
t.test("playerStats leaves the research fields empty when nothing is queued", function()
  local stats = civ.playerStats(1)
  t.assert_deep_equal({ researching = nil, research_turns_left = nil },
    { researching = stats.researching, research_turns_left = stats.research_turns_left })
end)

-- Bonus resources say nothing about deals, and a resource nobody has
-- touched is a row of zeroes in every snapshot of the game.
t.test("playerStats lists only strategic and luxury resources in play", function()
  local names = {}
  for _, entry in ipairs(civ.playerStats(0).resources) do
    table.insert(names, entry.resource)
  end
  t.assert_deep_equal({ "RESOURCE_IRON", "RESOURCE_SILK" }, names)
end)

t.test("playerStats influence list excludes self, dead, minors and barbarians", function()
  local stats = civ.playerStats(0)
  t.assert_equal(1, #stats.influence)
  t.assert_equal("Rome", stats.influence[1].civ)
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

t.test("gameSettings reads map, size, speed, turn limit and start era", function()
  t.assert_deep_equal({
    map_script = "Assets/Maps/Lekmap.lua",
    map_size = "WORLDSIZE_STANDARD",
    map_width = 44,
    map_height = 26,
    game_speed = "GAMESPEED_QUICK",
    max_turns = 330,
    start_era = "ERA_CLASSICAL",
    mods = {
      { id = "b2be3c8b-5f00-4d3e-9c00-000000000000", version = 34 },
      { id = "e1ccf71a-f248-498c-8f30-5ca6d851079d", version = 1 },
    },
  }, civ.gameSettings())
end)

t.test("playerRoster lists living majors with identity and handicap", function()
  t.assert_deep_equal({
    { civ = "Poland", name = "dysk", human = true, handicap = "HANDICAP_KING" },
    { civ = "Rome", name = "Augustus", human = false, handicap = "HANDICAP_KING" },
  }, civ.playerRoster())
end)

local function fakeLeague(spec)
  return {
    GetHostMember = function() return spec.host end,
    IsUnitedNations = function() return spec.unitedNations == true end,
    CalculateStartingVotesForMember = function(_, playerId)
      return spec.votes[playerId]
    end,
    GetCoreVotesForMember = function(_, playerId)
      return spec.coreVotes[playerId]
    end,
    GetEnactProposals = function() return spec.enactProposals or {} end,
    GetRepealProposals = function() return spec.repealProposals or {} end,
    GetActiveResolutions = function() return spec.activeResolutions or {} end,
    IsProjectActive = function(_, projectId)
      return (spec.activeProjects or {})[projectId] == true
    end,
    IsProjectComplete = function(_, projectId)
      return (spec.completeProjects or {})[projectId] == true
    end,
  }
end

-- GameInfo tables are called to iterate them: for row in GameInfo.X() do
local function fakeGameInfoTable(rows)
  return setmetatable(rows, {
    __call = function()
      local i = 0
      return function()
        i = i + 1
        return rows[i]
      end
    end,
  })
end

local leagueProjects = fakeGameInfoTable({
  { ID = 12, Type = "LEAGUE_PROJECT_WORLD_FAIR" },
  { ID = 13, Type = "LEAGUE_PROJECT_INTERNATIONAL_GAMES" },
  { ID = 14, Type = "LEAGUE_PROJECT_INTERNATIONAL_SPACE_STATION" },
})

local noProjectsRunning = {
  LEAGUE_PROJECT_WORLD_FAIR = { active = false, complete = false },
  LEAGUE_PROJECT_INTERNATIONAL_GAMES = { active = false, complete = false },
  LEAGUE_PROJECT_INTERNATIONAL_SPACE_STATION = { active = false, complete = false },
}

local congressGlobals
congressGlobals = {
  Game = {
    GetActiveLeague = function() return congressGlobals._league end,
    GetVotesNeededForDiploVictory = function() return 14 end,
  },
  GameDefines = { MAX_CIV_PLAYERS = 3 },
  Players = globals.Players,
  GameInfo = {
    Resolutions = { [5] = { Type = "RESOLUTION_EMBARGO", EmbargoPlayer = 1 } },
    LeagueProjects = leagueProjects,
  },
}
local congressCiv = adapter.new(congressGlobals)

t.test("congressSnapshot is nil when no league has been founded", function()
  congressGlobals._league = nil
  t.assert_nil(congressCiv.congressSnapshot())
end)

t.test("congressSnapshot reads host, delegates and proposals", function()
  congressGlobals._league = fakeLeague({
    host = 0,
    unitedNations = false,
    votes = { [0] = 5, [1] = 2 },
    coreVotes = { [0] = 1, [1] = 1 },
    enactProposals = {
      { ID = 5, Type = 5, ProposerDecision = -1, VoterDecision = -1, ProposalPlayer = 0 },
    },
    repealProposals = {},
    activeResolutions = {},
  })
  t.assert_deep_equal({
    host = "Poland",
    united_nations = false,
    votes_needed_for_diplo_victory = 14,
    delegates = {
      { civ = "Poland", votes = 5, core_votes = 1 },
      { civ = "Rome", votes = 2, core_votes = 1 },
    },
    proposals = {
      [5] = {
        id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false,
        ongoing_effects = true,
      },
    },
    active_resolutions = {},
    projects = noProjectsRunning,
  }, congressCiv.congressSnapshot())
end)

-- Whether a resolution keeps existing after enactment decides how its
-- outcome can be observed at all: CvLeague::DoEnactResolution only pushes
-- a resolution onto m_vActiveResolutions when HasOngoingEffects() is true.
-- These are the columns that function reads (CvVotingClasses.cpp:245).
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

local function proposalFor(resolutionRow)
  congressGlobals.GameInfo.Resolutions[7] = resolutionRow
  congressGlobals._league = fakeLeague({
    host = 0,
    votes = { [0] = 5, [1] = 2 },
    coreVotes = { [0] = 1, [1] = 1 },
    enactProposals = { { ID = 1, Type = 7, ProposalPlayer = 0 } },
  })
  return congressCiv.congressSnapshot().proposals[1]
end

local function ongoingEffectsPerColumn(value)
  local result = {}
  for _, column in ipairs(ongoingEffectColumns) do
    local row = { Type = "RESOLUTION_UNDER_TEST" }
    row[column] = value
    result[column] = proposalFor(row).ongoing_effects
  end
  return result
end

local function everyColumn(value)
  local expected = {}
  for _, column in ipairs(ongoingEffectColumns) do expected[column] = value end
  return expected
end

t.test("a set effect column makes a resolution one with ongoing effects", function()
  t.assert_deep_equal(everyColumn(true), ongoingEffectsPerColumn(1))
end)

t.test("effect columns set to zero leave a resolution one-shot", function()
  t.assert_deep_equal(everyColumn(false), ongoingEffectsPerColumn(0))
end)

t.test("effect columns read as booleans count the same as 0 and 1", function()
  t.assert_deep_equal(everyColumn(true), ongoingEffectsPerColumn(true))
  t.assert_deep_equal(everyColumn(false), ongoingEffectsPerColumn(false))
end)

t.test("a resolution missing the effect columns entirely is one-shot", function()
  t.assert_equal(false, proposalFor({ Type = "RESOLUTION_UNDER_TEST" }).ongoing_effects)
end)

t.test("a World's Fair is one-shot and names the project it enables", function()
  local proposal = proposalFor({
    Type = "RESOLUTION_WORLD_FAIR",
    LeagueProjectEnabled = "LEAGUE_PROJECT_WORLD_FAIR",
  })
  t.assert_deep_equal({
    id = 1, type = "RESOLUTION_WORLD_FAIR", proposer = "Poland", repeal = false,
    ongoing_effects = false, league_project = "LEAGUE_PROJECT_WORLD_FAIR",
  }, proposal)
end)

t.test("congressSnapshot reports which league projects are running", function()
  congressGlobals._league = fakeLeague({
    host = 0,
    votes = { [0] = 5, [1] = 2 },
    coreVotes = { [0] = 1, [1] = 1 },
    activeProjects = { [12] = true },
    completeProjects = { [13] = true },
  })
  t.assert_deep_equal({
    LEAGUE_PROJECT_WORLD_FAIR = { active = true, complete = false },
    LEAGUE_PROJECT_INTERNATIONAL_GAMES = { active = false, complete = true },
    LEAGUE_PROJECT_INTERNATIONAL_SPACE_STATION = { active = false, complete = false },
  }, congressCiv.congressSnapshot().projects)
end)

-- Game.GetWinner is a team, Game.GetVictory a victory type, both NO_*
-- (-1) until the game is decided (CvLuaGame.cpp:201-202).
local victoryGlobals
victoryGlobals = {
  Game = {
    GetGameTurn = function() return 300 end,
    GetWinner = function() return victoryGlobals._winner end,
    GetVictory = function() return victoryGlobals._victory end,
    GetWinningTurn = function() return victoryGlobals._winningTurn end,
  },
  GameDefines = { MAX_CIV_PLAYERS = 3 },
  Players = globals.Players,
  GameInfo = { Victories = { [3] = { Type = "VICTORY_SPACE_RACE" } } },
}
local victoryCiv = adapter.new(victoryGlobals)

t.test("victory is nil while no team has won", function()
  victoryGlobals._winner, victoryGlobals._victory = -1, -1
  t.assert_nil(victoryCiv.victory())
end)

t.test("victory reports the winning team, its civs and the victory type", function()
  victoryGlobals._winner, victoryGlobals._victory = 1, 3
  victoryGlobals._winningTurn = 297
  t.assert_deep_equal({
    winner_team = 1,
    winner_civs = { "Rome" },
    victory = "VICTORY_SPACE_RACE",
    winning_turn = 297,
  }, victoryCiv.victory())
end)

-- Friendship hangs off the player (CvLuaPlayer.cpp), the treaties and
-- open borders off the team (CvLuaTeam.cpp), so one pair entry is
-- assembled from both.
local function diploPlayer(spec)
  return {
    IsAlive = function() return spec.alive ~= false end,
    IsMinorCiv = function() return spec.minor == true end,
    IsBarbarian = function() return spec.barbarian == true end,
    GetTeam = function() return spec.team end,
    GetCivilizationShortDescription = function() return spec.civ end,
    IsDoF = function(_, other) return (spec.dof or {})[other] == true end,
  }
end

local function diploTeam(spec)
  return {
    IsAllowsOpenBordersToTeam = function(_, other) return (spec.openBorders or {})[other] == true end,
    HasEmbassyAtTeam = function(_, other) return (spec.embassy or {})[other] == true end,
    IsDefensivePact = function(_, other) return (spec.defensivePact or {})[other] == true end,
    IsHasTradeAgreement = function(_, other) return (spec.tradeAgreement or {})[other] == true end,
  }
end

local diplomacyGlobals = {
  Game = { GetGameTurn = function() return 142 end },
  GameDefines = { MAX_CIV_PLAYERS = 5 },
  Players = {
    [0] = diploPlayer({ civ = "Poland", team = 0, dof = { [1] = true } }),
    [1] = diploPlayer({ civ = "Rome", team = 1, dof = { [0] = true } }),
    [2] = diploPlayer({ civ = "Carthage", team = 2, alive = false }),
    [3] = diploPlayer({ civ = "Venice", team = 3, minor = true }),
    [4] = diploPlayer({ civ = "Barbarians", team = 4, barbarian = true }),
  },
  Teams = {
    [0] = diploTeam({ openBorders = { [1] = true }, defensivePact = { [1] = true } }),
    [1] = diploTeam({ embassy = { [0] = true }, defensivePact = { [0] = true } }),
  },
}
local diplomacyCiv = adapter.new(diplomacyGlobals)

t.test("diplomacySnapshot covers only living majors, in both directions", function()
  local snapshot = diplomacyCiv.diplomacySnapshot()
  local seen = {}
  for a, others in pairs(snapshot) do
    for b in pairs(others) do table.insert(seen, a .. "->" .. b) end
  end
  table.sort(seen)
  t.assert_deep_equal({ "0->1", "1->0" }, seen)
end)

t.test("diplomacySnapshot reads friendship from the player, treaties from the team", function()
  t.assert_deep_equal({ dof = true, open_borders = false, embassy = true,
    defensive_pact = true, trade_agreement = false },
    diplomacyCiv.diplomacySnapshot()[1][0])
end)

t.test("diplomacySnapshot reads open borders as granted by the reading side", function()
  t.assert_deep_equal({ dof = true, open_borders = true, embassy = false,
    defensive_pact = true, trade_agreement = false },
    diplomacyCiv.diplomacySnapshot()[0][1])
end)
