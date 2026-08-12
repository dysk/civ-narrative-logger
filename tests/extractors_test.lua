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
    return ({ [7] = "BUILDING_PYRAMIDS", [8] = "BUILDING_NATIONAL_COLLEGE" })[buildingId]
      or "BUILDING_GRANARY"
  end,
  wonderClass = function(buildingId)
    return ({ [7] = "world", [8] = "national" })[buildingId]
  end,
  unitType = function(playerId, unitId)
    if playerId ~= 0 then return nil end
    return ({ [9] = "UNIT_SETTLER", [14] = "UNIT_LANCER" })[unitId]
  end,
  projectType = function(projectId)
    return projectId == 2 and "PROJECT_APOLLO_PROGRAM" or nil
  end,
  religionName = function(religionId)
    return religionId == 4 and "Buddhism" or nil
  end,
  beliefType = function(beliefId)
    return ({
      [3] = "BELIEF_GOD_OF_WAR",
      [10] = "BELIEF_TITHE",
      [11] = "BELIEF_PAGODAS",
    })[beliefId]
  end,
  eraType = function(eraId)
    return eraId == 2 and "ERA_CLASSICAL" or nil
  end,
  policyType = function(policyId)
    return policyId == 6 and "POLICY_LIBERTY" or nil
  end,
  policyBranchType = function(branchId)
    return branchId == 2 and "POLICY_BRANCH_HONOR" or nil
  end,
  featureType = function(featureId)
    return featureId == 21 and "FEATURE_EL_DORADO" or nil
  end,
  unitTypeName = function(unitTypeId)
    return unitTypeId == 30 and "UNIT_GREAT_SCIENTIST" or nil
  end,
  promotionType = function(promotionId)
    return promotionId == 3 and "PROMOTION_MORALE" or nil
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
    wonder = "world",
  }, extractors.CityConstructed(civ, 0, 3, 7, false, false))
end)

t.test("CityConstructed marks national wonders", function()
  t.assert_deep_equal({
    event = "building_constructed",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    building = "BUILDING_NATIONAL_COLLEGE",
    wonder = "national",
  }, extractors.CityConstructed(civ, 0, 3, 8, false, false))
end)

t.test("CityConstructed records purchases with the currency used", function()
  t.assert_deep_equal({
    event = "building_constructed",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    building = "BUILDING_GRANARY",
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

t.test("CityCreated records purchases with the currency used", function()
  t.assert_deep_equal({
    event = "project_completed",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    project = "PROJECT_APOLLO_PROGRAM",
    bought_with = "gold",
  }, extractors.CityCreated(civ, 0, 3, 2, true, false))
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

-- DLL: MakePeace(teamId, otherTeamId)
t.test("MakePeace becomes a peace_made record", function()
  t.assert_deep_equal({
    event = "peace_made",
    turn = 142,
    team_a = 0,
    team_a_civs = { "Poland" },
    team_b = 1,
    team_b_civs = { "Rome" },
  }, extractors.MakePeace(civ, 0, 1))
end)

-- DLL: PantheonFounded(playerId, capitalCityId, religionId, beliefId)
-- religionId is always RELIGION_PANTHEON (-1)
t.test("PantheonFounded becomes a pantheon_founded record", function()
  t.assert_deep_equal({
    event = "pantheon_founded",
    turn = 142,
    civ = "Poland",
    city = "Warsaw",
    belief = "BELIEF_GOD_OF_WAR",
  }, extractors.PantheonFounded(civ, 0, 3, -1, 3))
end)

-- DLL: ReligionFounded(playerId, holyCityId, religionId,
--   pantheonBelief, belief1, belief2, belief3, belief4)
-- unused belief slots arrive as -1 (NO_BELIEF)
t.test("ReligionFounded becomes a religion_founded record", function()
  t.assert_deep_equal({
    event = "religion_founded",
    turn = 142,
    civ = "Poland",
    holy_city = "Warsaw",
    religion = "Buddhism",
    beliefs = { "BELIEF_GOD_OF_WAR", "BELIEF_TITHE", "BELIEF_PAGODAS" },
  }, extractors.ReligionFounded(civ, 0, 3, 4, 3, 10, 11, -1, -1))
end)

-- DLL: ReligionEnhanced(playerId, religionId, belief1, belief2)
t.test("ReligionEnhanced becomes a religion_enhanced record", function()
  t.assert_deep_equal({
    event = "religion_enhanced",
    turn = 142,
    civ = "Poland",
    religion = "Buddhism",
    beliefs = { "BELIEF_TITHE", "BELIEF_PAGODAS" },
  }, extractors.ReligionEnhanced(civ, 0, 4, 10, 11))
end)

-- DLL: GreatPersonExpended(playerId, unitTypeId) -- type, not instance
t.test("GreatPersonExpended becomes a great_person_expended record", function()
  t.assert_deep_equal({
    event = "great_person_expended",
    turn = 142,
    civ = "Poland",
    great_person = "UNIT_GREAT_SCIENTIST",
  }, extractors.GreatPersonExpended(civ, 0, 30))
end)

-- DLL: TeamSetEra(teamId, eraId)
t.test("TeamSetEra becomes an era_entered record", function()
  t.assert_deep_equal({
    event = "era_entered",
    turn = 142,
    team = 1,
    civs = { "Rome" },
    era = "ERA_CLASSICAL",
  }, extractors.TeamSetEra(civ, 1, 2))
end)

-- DLL: NuclearDetonation(attackerPlayerId, x, y, war, bystanderWar)
t.test("NuclearDetonation becomes a nuclear_detonation record", function()
  t.assert_deep_equal({
    event = "nuclear_detonation",
    turn = 142,
    civ = "Poland",
    x = 10,
    y = 20,
    city = "Warsaw",
    war = true,
    bystander_war = false,
  }, extractors.NuclearDetonation(civ, 0, 10, 20, true, false))
end)

-- DLL: PlayerAdoptPolicy(playerId, policyId)
t.test("PlayerAdoptPolicy becomes a policy_adopted record", function()
  t.assert_deep_equal({
    event = "policy_adopted",
    turn = 142,
    civ = "Poland",
    policy = "POLICY_LIBERTY",
  }, extractors.PlayerAdoptPolicy(civ, 0, 6))
end)

-- DLL: PlayerAdoptPolicyBranch(playerId, branchTypeId)
t.test("PlayerAdoptPolicyBranch becomes a policy_branch_adopted record", function()
  t.assert_deep_equal({
    event = "policy_branch_adopted",
    turn = 142,
    civ = "Poland",
    branch = "POLICY_BRANCH_HONOR",
  }, extractors.PlayerAdoptPolicyBranch(civ, 0, 2))
end)

-- DLL: PlayerPolicyBranchUnlocked(playerId, branchTypeId)
t.test("PlayerPolicyBranchUnlocked becomes a policy_branch_unlocked record", function()
  t.assert_deep_equal({
    event = "policy_branch_unlocked",
    turn = 142,
    civ = "Poland",
    branch = "POLICY_BRANCH_HONOR",
  }, extractors.PlayerPolicyBranchUnlocked(civ, 0, 2))
end)

-- DLL: CircumnavigatedGlobe(teamId)
t.test("CircumnavigatedGlobe becomes a globe_circumnavigated record", function()
  t.assert_deep_equal({
    event = "globe_circumnavigated",
    turn = 142,
    team = 1,
    civs = { "Rome" },
  }, extractors.CircumnavigatedGlobe(civ, 1))
end)

-- DLL: NaturalWonderDiscovered(teamId, featureId, x, y, first)
t.test("NaturalWonderDiscovered becomes a natural_wonder_discovered record", function()
  t.assert_deep_equal({
    event = "natural_wonder_discovered",
    turn = 142,
    team = 1,
    civs = { "Rome" },
    wonder = "FEATURE_EL_DORADO",
    x = 5,
    y = 6,
    first = true,
  }, extractors.NaturalWonderDiscovered(civ, 1, 21, 5, 6, true))
end)

civ.playerStats = function(playerId)
  return playerId == 0 and { score = 1200, gold = 340 } or nil
end

-- DLL: PlayerDoTurn(playerId)
t.test("PlayerDoTurn becomes a snapshot record with the player stats", function()
  t.assert_deep_equal({
    event = "snapshot",
    turn = 142,
    civ = "Poland",
    score = 1200,
    gold = 340,
  }, extractors.PlayerDoTurn(civ, 0))
end)

t.test("PlayerDoTurn skips players without stats", function()
  t.assert_nil(extractors.PlayerDoTurn(civ, 1))
end)

civ.gameSettings = function()
  return { map_script = "Lekmap.lua", map_size = "WORLDSIZE_STANDARD" }
end
civ.playerRoster = function()
  return {
    { civ = "Poland", name = "dysk", human = true, handicap = "HANDICAP_KING" },
    { civ = "Rome", name = "Augustus", human = false, handicap = "HANDICAP_KING" },
  }
end

-- Not a GameEvents hook: emitted once whenever the logger attaches
-- (game start, reload, pitboss restart).
t.test("sessionStarted merges settings, roster and turn", function()
  t.assert_deep_equal({
    event = "session_started",
    turn = 142,
    map_script = "Lekmap.lua",
    map_size = "WORLDSIZE_STANDARD",
    players = {
      { civ = "Poland", name = "dysk", human = true, handicap = "HANDICAP_KING" },
      { civ = "Rome", name = "Augustus", human = false, handicap = "HANDICAP_KING" },
    },
  }, extractors.sessionStarted(civ))
end)

-- DLL: UnitCreated(ownerId, unitInstanceId, x, y)
t.test("UnitCreated becomes a unit_created record", function()
  t.assert_deep_equal({
    event = "unit_created",
    turn = 142,
    civ = "Poland",
    unit = "UNIT_SETTLER",
    city = "Warsaw",
    x = 10,
    y = 20,
  }, extractors.UnitCreated(civ, 0, 9, 10, 20))
end)

-- DLL: UnitKilledInCombat(killerPlayerId, ownerPlayerId, unitTypeId)
t.test("UnitKilledInCombat becomes a unit_killed record", function()
  t.assert_deep_equal({
    event = "unit_killed",
    turn = 142,
    killer = "Poland",
    victim = "Rome",
    unit = "UNIT_GREAT_SCIENTIST",
  }, extractors.UnitKilledInCombat(civ, 0, 1, 30))
end)

-- DLL: UnitPrekill(ownerId, unitInstanceId, unitTypeId, x, y, bDelay,
--   killerPlayerId) -- fires twice on delayed deaths, bDelay=true first
t.test("UnitPrekill becomes a unit_lost record", function()
  t.assert_deep_equal({
    event = "unit_lost",
    turn = 142,
    civ = "Rome",
    unit = "UNIT_GREAT_SCIENTIST",
    city = "Warsaw",
    x = 10,
    y = 20,
    killed_by = "Poland",
  }, extractors.UnitPrekill(civ, 1, 22, 30, 10, 20, false, 0))
end)

t.test("UnitPrekill logs nothing on the delayed-death first fire", function()
  t.assert_nil(extractors.UnitPrekill(civ, 1, 22, 30, 10, 20, true, 0))
end)

t.test("UnitPrekill without a killer omits killed_by", function()
  t.assert_deep_equal({
    event = "unit_lost",
    turn = 142,
    civ = "Rome",
    unit = "UNIT_GREAT_SCIENTIST",
    x = 5,
    y = 6,
  }, extractors.UnitPrekill(civ, 1, 22, 30, 5, 6, false, -1))
end)

-- DLL: UnitPromoted(ownerId, unitInstanceId, promotionId)
t.test("UnitPromoted becomes a unit_promoted record", function()
  t.assert_deep_equal({
    event = "unit_promoted",
    turn = 142,
    civ = "Poland",
    unit = "UNIT_SETTLER",
    promotion = "PROMOTION_MORALE",
  }, extractors.UnitPromoted(civ, 0, 9, 3))
end)

-- DLL: UnitUpgraded(ownerId, oldUnitInstanceId, newUnitInstanceId,
--   bGoodyHut) -- fires before the old unit is converted, both resolvable
t.test("UnitUpgraded becomes a unit_upgraded record", function()
  t.assert_deep_equal({
    event = "unit_upgraded",
    turn = 142,
    civ = "Poland",
    from = "UNIT_SETTLER",
    to = "UNIT_LANCER",
  }, extractors.UnitUpgraded(civ, 0, 9, 14, false))
end)

t.test("UnitUpgraded marks goody hut upgrades", function()
  t.assert_deep_equal({
    event = "unit_upgraded",
    turn = 142,
    civ = "Poland",
    from = "UNIT_SETTLER",
    to = "UNIT_LANCER",
    goody_hut = true,
  }, extractors.UnitUpgraded(civ, 0, 9, 14, true))
end)

-- DLL: UnitPillaged(ownerId, unitInstanceId, x, y) -- from CvUnit::pillage
t.test("UnitPillaged becomes an improvement_pillaged record", function()
  t.assert_deep_equal({
    event = "improvement_pillaged",
    turn = 142,
    civ = "Poland",
    unit = "UNIT_SETTLER",
    x = 5,
    y = 6,
  }, extractors.UnitPillaged(civ, 0, 9, 5, 6))
end)

-- DLL: UnitPlundered(ownerId, unitInstanceId, x, y)
--   -- from CvUnit::plunderTradeRoute
t.test("UnitPlundered becomes a trade_route_plundered record", function()
  t.assert_deep_equal({
    event = "trade_route_plundered",
    turn = 142,
    civ = "Poland",
    unit = "UNIT_SETTLER",
    x = 5,
    y = 6,
  }, extractors.UnitPlundered(civ, 0, 9, 5, 6))
end)

-- DLL: ParadropAt(ownerId, unitInstanceId, fromX, fromY, toX, toY)
t.test("ParadropAt becomes a paradrop record", function()
  t.assert_deep_equal({
    event = "paradrop",
    turn = 142,
    civ = "Poland",
    unit = "UNIT_SETTLER",
    from_x = 5,
    from_y = 6,
    to_x = 7,
    to_y = 8,
  }, extractors.ParadropAt(civ, 0, 9, 5, 6, 7, 8))
end)

-- DLL: RebaseTo(ownerId, unitInstanceId, x, y)
t.test("RebaseTo becomes a unit_rebased record", function()
  t.assert_deep_equal({
    event = "unit_rebased",
    turn = 142,
    civ = "Poland",
    unit = "UNIT_SETTLER",
    city = "Warsaw",
    x = 10,
    y = 20,
  }, extractors.RebaseTo(civ, 0, 9, 10, 20))
end)
