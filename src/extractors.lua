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
    wonder = civ.wonderClass(buildingId),
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

function M.CityCreated(civ, ownerId, cityId, projectId, gold, faith)
  return {
    event = "project_completed",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    city = civ.cityName(ownerId, cityId),
    project = civ.projectType(projectId),
    bought_with = boughtWith(gold, faith),
  }
end

local function beliefList(civ, ...)
  local beliefs = {}
  for _, beliefId in ipairs({ ... }) do
    local belief = civ.beliefType(beliefId)
    if belief then table.insert(beliefs, belief) end
  end
  return beliefs
end

function M.MakePeace(civ, teamA, teamB)
  return {
    event = "peace_made",
    turn = civ.turn(),
    team_a = teamA,
    team_a_civs = civ.teamCivNames(teamA),
    team_b = teamB,
    team_b_civs = civ.teamCivNames(teamB),
  }
end

function M.PantheonFounded(civ, playerId, cityId, _, beliefId)
  return {
    event = "pantheon_founded",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    city = civ.cityName(playerId, cityId),
    belief = civ.beliefType(beliefId),
  }
end

function M.ReligionFounded(civ, playerId, holyCityId, religionId, ...)
  return {
    event = "religion_founded",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    holy_city = civ.cityName(playerId, holyCityId),
    religion = civ.religionName(religionId),
    beliefs = beliefList(civ, ...),
  }
end

function M.ReligionEnhanced(civ, playerId, religionId, ...)
  return {
    event = "religion_enhanced",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    religion = civ.religionName(religionId),
    beliefs = beliefList(civ, ...),
  }
end

function M.GreatPersonExpended(civ, playerId, unitTypeId)
  return {
    event = "great_person_expended",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    great_person = civ.unitTypeName(unitTypeId),
  }
end

function M.TeamSetEra(civ, teamId, eraId)
  return {
    event = "era_entered",
    turn = civ.turn(),
    team = teamId,
    civs = civ.teamCivNames(teamId),
    era = civ.eraType(eraId),
  }
end

function M.NuclearDetonation(civ, playerId, x, y, war, bystanderWar)
  return {
    event = "nuclear_detonation",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    x = x,
    y = y,
    city = civ.cityNameAt(x, y),
    war = war,
    bystander_war = bystanderWar,
  }
end

function M.PlayerAdoptPolicy(civ, playerId, policyId)
  return {
    event = "policy_adopted",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    policy = civ.policyType(policyId),
  }
end

function M.PlayerAdoptPolicyBranch(civ, playerId, branchId)
  return {
    event = "policy_branch_adopted",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    branch = civ.policyBranchType(branchId),
  }
end

function M.PlayerPolicyBranchUnlocked(civ, playerId, branchId)
  return {
    event = "policy_branch_unlocked",
    turn = civ.turn(),
    civ = civ.civName(playerId),
    branch = civ.policyBranchType(branchId),
  }
end

function M.CircumnavigatedGlobe(civ, teamId)
  return {
    event = "globe_circumnavigated",
    turn = civ.turn(),
    team = teamId,
    civs = civ.teamCivNames(teamId),
  }
end

function M.PlayerDoTurn(civ, playerId)
  local record = civ.playerStats(playerId)
  if not record then return nil end
  record.event = "snapshot"
  record.turn = civ.turn()
  record.civ = civ.civName(playerId)
  return record
end

function M.NaturalWonderDiscovered(civ, teamId, featureId, x, y, first)
  return {
    event = "natural_wonder_discovered",
    turn = civ.turn(),
    team = teamId,
    civs = civ.teamCivNames(teamId),
    wonder = civ.featureType(featureId),
    x = x,
    y = y,
    first = first,
  }
end

function M.UnitCreated(civ, ownerId, unitId, x, y)
  return {
    event = "unit_created",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitType(ownerId, unitId),
    city = civ.cityNameAt(x, y),
    x = x,
    y = y,
  }
end

function M.UnitKilledInCombat(civ, killerId, ownerId, unitTypeId)
  return {
    event = "unit_killed",
    turn = civ.turn(),
    killer = civ.civName(killerId),
    victim = civ.civName(ownerId),
    unit = civ.unitTypeName(unitTypeId),
  }
end

local function civNameIfAny(civ, playerId)
  return playerId >= 0 and civ.civName(playerId) or nil
end

function M.UnitPrekill(civ, ownerId, unitId, unitTypeId, x, y, delay, killerId)
  if delay then return nil end
  return {
    event = "unit_lost",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitTypeName(unitTypeId),
    city = civ.cityNameAt(x, y),
    x = x,
    y = y,
    killed_by = civNameIfAny(civ, killerId),
  }
end

function M.UnitPromoted(civ, ownerId, unitId, promotionId)
  return {
    event = "unit_promoted",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitType(ownerId, unitId),
    promotion = civ.promotionType(promotionId),
  }
end

function M.UnitUpgraded(civ, ownerId, oldUnitId, newUnitId, goodyHut)
  return {
    event = "unit_upgraded",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    from = civ.unitType(ownerId, oldUnitId),
    to = civ.unitType(ownerId, newUnitId),
    goody_hut = goodyHut or nil,
  }
end

function M.UnitPillaged(civ, ownerId, unitId, x, y)
  return {
    event = "improvement_pillaged",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitType(ownerId, unitId),
    x = x,
    y = y,
  }
end

function M.UnitPlundered(civ, ownerId, unitId, x, y)
  return {
    event = "trade_route_plundered",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitType(ownerId, unitId),
    x = x,
    y = y,
  }
end

function M.ParadropAt(civ, ownerId, unitId, fromX, fromY, toX, toY)
  return {
    event = "paradrop",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitType(ownerId, unitId),
    from_x = fromX,
    from_y = fromY,
    to_x = toX,
    to_y = toY,
  }
end

function M.RebaseTo(civ, ownerId, unitId, x, y)
  return {
    event = "unit_rebased",
    turn = civ.turn(),
    civ = civ.civName(ownerId),
    unit = civ.unitType(ownerId, unitId),
    city = civ.cityNameAt(x, y),
    x = x,
    y = y,
  }
end

function M.TeamMeet(civ, teamA, teamB)
  return {
    event = "teams_met",
    turn = civ.turn(),
    team_a = teamA,
    team_a_civs = civ.teamCivNames(teamA),
    team_b = teamB,
    team_b_civs = civ.teamCivNames(teamB),
  }
end

function M.SetAlly(civ, minorId, oldAllyId, newAllyId)
  return {
    event = "city_state_ally_changed",
    turn = civ.turn(),
    city_state = civ.civName(minorId),
    old_ally = civNameIfAny(civ, oldAllyId),
    new_ally = civNameIfAny(civ, newAllyId),
  }
end

function M.MinorAlliesChanged(civ, minorId, playerId, add, oldValue, newValue)
  return {
    event = "city_state_alliance_changed",
    turn = civ.turn(),
    city_state = civ.civName(minorId),
    civ = civ.civName(playerId),
    allied = add,
    old_friendship = oldValue,
    new_friendship = newValue,
  }
end

function M.MinorFriendsChanged(civ, minorId, playerId, add, oldValue, newValue)
  return {
    event = "city_state_friendship_changed",
    turn = civ.turn(),
    city_state = civ.civName(minorId),
    civ = civ.civName(playerId),
    friends = add,
    old_friendship = oldValue,
    new_friendship = newValue,
  }
end

function M.UiDiploEvent(civ, eventTypeId, aiPlayerId, arg1, arg2)
  return {
    event = "diplo_event",
    turn = civ.turn(),
    type = eventTypeId,
    civ = civ.civName(aiPlayerId),
    arg1 = arg1,
    arg2 = arg2,
  }
end

function M.MPVotingSystemVote(civ, proposalId, voterId, vote)
  return {
    event = "mp_vote",
    turn = civ.turn(),
    proposal = proposalId,
    civ = civ.civName(voterId),
    vote = vote,
  }
end

function M.MPVotingSystemProposalResult(civ, proposalId, expiration,
    ownerId, subjectId, typeId, statusId)
  return {
    event = "mp_proposal_result",
    turn = civ.turn(),
    proposal = proposalId,
    expires_in = expiration,
    owner = civNameIfAny(civ, ownerId),
    subject = civNameIfAny(civ, subjectId),
    type = typeId,
    status = statusId,
  }
end

function M.sessionStarted(civ)
  local record = civ.gameSettings()
  record.event = "session_started"
  record.turn = civ.turn()
  record.players = civ.playerRoster()
  return record
end

return M
