-- Polls the state between every pair of living majors once per turn and
-- diffs it into events. Only war and peace have hooks (DeclareWar,
-- MakePeace); friendships, pacts, open borders and embassies are state
-- nobody announces, so they are read and compared turn to turn.
-- Registered directly on PlayerDoTurn like the other stateful pollers,
-- and gated on the turn because the pairwise state is game-global while
-- PlayerDoTurn fires once per living player.
--
-- The first poll of a session only records a baseline: a reload must not
-- re-announce friendships that have stood for fifty turns.
local json = require("src.json")

local M = {}

-- The DLL sets DoF, defensive pacts and trade agreements on both sides,
-- so those are one fact about a pair and are read from the lower player
-- id only. Open borders and embassies belong to the side that granted
-- them and are reported per direction.
local MUTUAL = {
  { flag = "dof", up = "friendship_declared", down = "friendship_ended" },
  { flag = "defensive_pact", up = "defensive_pact_signed", down = "defensive_pact_ended" },
  { flag = "trade_agreement", up = "trade_agreement_signed", down = "trade_agreement_ended" },
}

local ONE_SIDED = {
  { flag = "open_borders", up = "open_borders_granted", down = "open_borders_revoked" },
  { flag = "embassy", up = "embassy_established", down = "embassy_ended" },
}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (diplomacy)", error = tostring(err) }
end

-- pairs() order is undefined, and the log is compared line by line.
local function sortedIds(snapshot)
  local ids = {}
  for id in pairs(snapshot) do table.insert(ids, id) end
  table.sort(ids)
  return ids
end

local function changed(known, current, flag)
  if not known or not current then return nil end
  if known[flag] == current[flag] then return nil end
  return current[flag]
end

local function diffMutual(civ, sink, turn, known, current, a, b)
  for _, fact in ipairs(MUTUAL) do
    local now = changed(known, current, fact.flag)
    if now ~= nil then
      sink(json.encode({
        event = now and fact.up or fact.down,
        turn = turn,
        civs = { civ.civName(a), civ.civName(b) },
      }))
    end
  end
end

local function diffOneSided(civ, sink, turn, known, current, a, b)
  for _, fact in ipairs(ONE_SIDED) do
    local now = changed(known, current, fact.flag)
    if now ~= nil then
      sink(json.encode({
        event = now and fact.up or fact.down,
        turn = turn,
        civ = civ.civName(a),
        other_civ = civ.civName(b),
      }))
    end
  end
end

local function diffPair(civ, sink, turn, known, current, a, b)
  if a < b then diffMutual(civ, sink, turn, known, current, a, b) end
  diffOneSided(civ, sink, turn, known, current, a, b)
end

local function diff(civ, sink, turn, known, snapshot)
  for _, a in ipairs(sortedIds(snapshot)) do
    for _, b in ipairs(sortedIds(snapshot[a])) do
      diffPair(civ, sink, turn, (known[a] or {})[b], snapshot[a][b], a, b)
    end
  end
end

function M.new(civ, sink)
  local state = { turn = nil, snapshot = nil }

  local function poll()
    local turn = civ.turn()
    if turn == state.turn then return end
    state.turn = turn

    local snapshot = civ.diplomacySnapshot()
    if state.snapshot then diff(civ, sink, turn, state.snapshot, snapshot) end
    state.snapshot = snapshot
  end

  return function()
    local ok, err = pcall(poll)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
