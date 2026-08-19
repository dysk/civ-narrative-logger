-- Polls the World Congress once per turn and diffs it into events. No
-- GameEvents hook covers the Congress (mp_vote/mp_proposal_result are
-- Lekmod's own multiplayer voting, unrelated), so the league state is
-- read via Game.GetActiveLeague() and compared turn to turn. Registered
-- directly on PlayerDoTurn (bypassing logger.attach) since it needs
-- cross-turn state, may emit zero or more records per firing, and must
-- emit congress_snapshot once per turn even though PlayerDoTurn fires
-- once per player.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (congress)", error = tostring(err) }
end

local function diffProposed(sink, turn, known, current)
  for id, proposal in pairs(current) do
    if not known[id] then
      sink(json.encode({
        event = "resolution_proposed",
        turn = turn,
        resolution = proposal.type,
        proposer = proposal.proposer,
        repeal = proposal.repeal,
      }))
    end
  end
end

-- A repeal proposal carries the ID of the resolution it targets (the DLL's
-- CvRepealProposal is constructed with pResolution->GetID()), so an active
-- resolution still sitting under the proposal's ID means the opposite for a
-- repeal than it does for an enactment: the target survived the vote.
local function diffResolved(sink, turn, known, current, activeResolutions)
  for id, proposal in pairs(known) do
    if not current[id] then
      local targetActive = activeResolutions[id] ~= nil
      local passed = (proposal.repeal == true) ~= targetActive

      sink(json.encode({
        event = passed and "resolution_passed" or "resolution_failed",
        turn = turn,
        resolution = proposal.type,
      }))
    end
  end
end

local function diffRepealed(sink, turn, known, current)
  for id, resolution in pairs(known) do
    if not current[id] then
      sink(json.encode({
        event = "resolution_repealed", turn = turn, resolution = resolution.type,
      }))
    end
  end
end

local function diff(sink, turn, known, snapshot)
  if known.host ~= snapshot.host then
    sink(json.encode({
      event = "congress_host_changed", turn = turn,
      old_host = known.host, new_host = snapshot.host,
    }))
  end
  if snapshot.united_nations and not known.united_nations then
    sink(json.encode({ event = "united_nations_formed", turn = turn }))
  end
  diffProposed(sink, turn, known.proposals, snapshot.proposals)
  diffResolved(sink, turn, known.proposals, snapshot.proposals, snapshot.active_resolutions)
  diffRepealed(sink, turn, known.active_resolutions, snapshot.active_resolutions)
end

function M.new(civ, sink)
  local state = { turn = nil, snapshot = nil }

  local function poll()
    local turn = civ.turn()
    if turn == state.turn then return end
    state.turn = turn

    local snapshot = civ.congressSnapshot()
    if not snapshot then
      state.snapshot = nil
      return
    end

    if not state.snapshot then
      sink(json.encode({ event = "congress_founded", turn = turn, host = snapshot.host }))
    else
      diff(sink, turn, state.snapshot, snapshot)
    end

    sink(json.encode({
      event = "congress_snapshot",
      turn = turn,
      host = snapshot.host,
      delegates = snapshot.delegates,
      votes_needed_for_diplo_victory = snapshot.votes_needed_for_diplo_victory,
    }))

    state.snapshot = snapshot
  end

  return function(playerId)
    local ok, err = pcall(poll, playerId)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
