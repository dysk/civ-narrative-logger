local t = require("tests.test_helper")
local adapter = require("src.adapter")

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
    Cities = function()
      local list = spec.citiesList or {}
      local i = 0
      return function()
        i = i + 1
        local c = list[i]
        if not c then return nil end
        return {
          IsOriginalMajorCapital = function() return c.capital == true end,
          GetOriginalOwner = function() return c.originalOwner end,
          GetID = function() return c.id end,
          GetName = function() return c.name end,
          GetX = function() return c.x end,
          GetY = function() return c.y end,
        }
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
  YieldTypes = { YIELD_FOOD = "YIELD_FOOD", YIELD_PRODUCTION = "YIELD_PRODUCTION" },
  GameInfoTypes = {
    PROJECT_APOLLO_PROGRAM = "PROJECT_APOLLO_PROGRAM",
    PROJECT_SS_BOOSTER = "PROJECT_SS_BOOSTER",
    PROJECT_SS_COCKPIT = "PROJECT_SS_COCKPIT",
    PROJECT_SS_STASIS_CHAMBER = "PROJECT_SS_STASIS_CHAMBER",
    PROJECT_SS_ENGINE = "PROJECT_SS_ENGINE",
  },
  GameDefines = { MAX_CIV_PLAYERS = 3 },
  Players = {
    [0] = fakePlayer({
      civ = "Poland", team = 0,
      name = "dysk", human = true, handicap = 5,
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
        { id = 3, name = "Warsaw", x = 10, y = 20, originalOwner = 0, capital = true },
        { id = 7, name = "Rome (captured)", x = 15, y = 22, originalOwner = 1, capital = true },
        { id = 9, name = "Krakow", x = 11, y = 21, originalOwner = 1, capital = false },
      },
    }),
    [1] = fakePlayer({ civ = "Rome", team = 1, name = "Augustus", handicap = 5 }),
    [2] = fakePlayer({ civ = "Carthage", team = 1, alive = false }),
    [3] = fakePlayer({ civ = "Venice", minor = true }),
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
    Buildings = {
      [7] = { Type = "BUILDING_PYRAMIDS", BuildingClass = "BUILDINGCLASS_PYRAMIDS" },
      [5] = { Type = "BUILDING_GRANARY", BuildingClass = "BUILDINGCLASS_GRANARY" },
      [8] = { Type = "BUILDING_NATIONAL_COLLEGE",
              BuildingClass = "BUILDINGCLASS_NATIONAL_COLLEGE" },
    },
    BuildingClasses = {
      BUILDINGCLASS_PYRAMIDS = { MaxGlobalInstances = 1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_GRANARY = { MaxGlobalInstances = -1, MaxPlayerInstances = -1 },
      BUILDINGCLASS_NATIONAL_COLLEGE = { MaxGlobalInstances = -1, MaxPlayerInstances = 1 },
    },
    Beliefs = { [10] = { Type = "BELIEF_TITHE" } },
    Eras = { [2] = { Type = "ERA_CLASSICAL" } },
    Policies = { [6] = { Type = "POLICY_LIBERTY" } },
    PolicyBranchTypes = { [2] = { Type = "POLICY_BRANCH_HONOR" } },
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
