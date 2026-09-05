-- Polls the trade routes in play and diffs them into events. A route is
-- a deal, and the log has never said what either party got out of one:
-- today there is a single trade_route_plundered and no record of what
-- was plundered or who lost it.
--
-- Diffed rather than snapshotted because a route stands for tens of
-- turns and its terms are fixed when it opens. Two records over its life
-- say everything a per-turn stream would.
--
-- The first poll of a session is only a baseline: a reload must not
-- re-announce sixty routes that were each announced when they opened.
--
-- Registered on PlayerDoTurn like the other stateful pollers and gated
-- on the turn, because the route list is game-global while PlayerDoTurn
-- fires once per living player.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (trade routes)", error = tostring(err) }
end

-- pairs() order is undefined, and the log is compared line by line.
local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do table.insert(keys, key) end
  table.sort(keys)
  return keys
end

local function establishedRecord(turn, route)
  local record = { event = "trade_route_established", turn = turn }
  for field, value in pairs(route) do record[field] = value end
  return record
end

-- Only which route ended. What it was worth was said when it opened, and
-- a plundered route is told from an expired one by the
-- trade_route_plundered of the same turn.
local function endedRecord(turn, route)
  return {
    event = "trade_route_ended",
    turn = turn,
    civ = route.civ,
    from_city = route.from_city,
    to_civ = route.to_civ,
    to_city = route.to_city,
  }
end

local function diff(sink, turn, known, routes)
  for _, key in ipairs(sortedKeys(routes)) do
    if not known[key] then
      sink(json.encode(establishedRecord(turn, routes[key])))
    end
  end
  for _, key in ipairs(sortedKeys(known)) do
    if not routes[key] then
      sink(json.encode(endedRecord(turn, known[key])))
    end
  end
end

function M.new(civ, sink)
  local state = { turn = nil, routes = nil }

  local function poll()
    local turn = civ.turn()
    if turn == state.turn then return end
    state.turn = turn

    local routes = civ.tradeRoutes()
    if state.routes then diff(sink, turn, state.routes, routes) end
    state.routes = routes
  end

  return function()
    local ok, err = pcall(poll)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
