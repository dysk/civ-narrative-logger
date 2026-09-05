-- Polls where every major stands with every city-state and writes what
-- the three city_state_* hooks cannot say. Those fire only when a
-- threshold is crossed; between them the log never says whether an
-- alliance is held at 112 and sliding or at 61 and about to go.
--
-- A session opens with the standing state of every city-state, so a
-- resumed log is not blind until somebody happens to cross a threshold,
-- and a city-state nobody ever courts still appears. After that only a
-- crossed threshold is written: influence moves every turn on its own,
-- and recording that would be most of the log to say that decay is
-- decay. The per_turn rate in each record is what makes the gap
-- readable - the curve between two snapshots follows from it.
--
-- Pledges to protect are the exception, written whenever they change:
-- no hook covers them at all, and a discrete political act should not
-- wait for somebody else to cross a threshold.
--
-- Registered on PlayerDoTurn like the other stateful pollers and gated
-- on the turn, because the state is game-global while PlayerDoTurn
-- fires once per living player.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (city states)", error = tostring(err) }
end

-- pairs() order is undefined, and the log is compared line by line.
local function sortedIds(t)
  local ids = {}
  for id in pairs(t) do table.insert(ids, id) end
  table.sort(ids)
  return ids
end

local function relationList(relations)
  local list = {}
  for _, id in ipairs(sortedIds(relations)) do
    table.insert(list, relations[id])
  end
  return list
end

local function writeSnapshot(sink, turn, entry)
  local relations = relationList(entry.relations)
  sink(json.encode({
    event = "city_state_snapshot",
    turn = turn,
    city_state = entry.civ,
    ally = entry.ally,
    relations = #relations > 0 and relations or nil,
  }))
end

local function levelWith(entry, majorId)
  local relation = entry.relations[majorId]
  return relation and relation.level
end

local function levelChanged(known, current)
  for majorId in pairs(known.relations) do
    if levelWith(known, majorId) ~= levelWith(current, majorId) then return true end
  end
  for majorId in pairs(current.relations) do
    if levelWith(known, majorId) ~= levelWith(current, majorId) then return true end
  end
  return false
end

local function diffPledges(sink, turn, known, current)
  for _, majorId in ipairs(sortedIds(current.relations)) do
    local relation = current.relations[majorId]
    local was = (known.relations[majorId] or {}).protected
    if was ~= relation.protected then
      sink(json.encode({
        event = relation.protected and "city_state_protected"
          or "city_state_protection_ended",
        turn = turn,
        city_state = current.civ,
        civ = relation.civ,
      }))
    end
  end
end

local function diff(sink, turn, known, snapshot)
  for _, minorId in ipairs(sortedIds(snapshot)) do
    local entry, previous = snapshot[minorId], known[minorId]
    if not previous then
      writeSnapshot(sink, turn, entry)
    else
      diffPledges(sink, turn, previous, entry)
      if levelChanged(previous, entry) then writeSnapshot(sink, turn, entry) end
    end
  end
end

local function writeBaseline(sink, turn, snapshot)
  for _, minorId in ipairs(sortedIds(snapshot)) do
    writeSnapshot(sink, turn, snapshot[minorId])
  end
end

function M.new(civ, sink)
  local state = { turn = nil, snapshot = nil }

  local function poll()
    local turn = civ.turn()
    if turn == state.turn then return end
    state.turn = turn

    local snapshot = civ.cityStateSnapshot()
    if state.snapshot then
      diff(sink, turn, state.snapshot, snapshot)
    else
      writeBaseline(sink, turn, snapshot)
    end
    state.snapshot = snapshot
  end

  return function()
    local ok, err = pcall(poll)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
