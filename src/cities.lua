-- Writes one city_snapshot per city per turn. Cities are where the
-- decisions happen and the log has only ever described them through the
-- events that befall them: nothing has ever carried what a city is
-- building, how much damage it is taking, or whether it can be governed
-- at all. Registered directly on PlayerDoTurn like the other pollers,
-- since it emits many records per firing; unlike them it keeps no state
-- and diffs nothing - every city is written every turn, and the
-- filtering belongs downstream.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (cities)", error = tostring(err) }
end

function M.new(civ, sink)
  local function poll(playerId)
    local turn, name = civ.turn(), civ.civName(playerId)
    for _, record in ipairs(civ.cityStats(playerId)) do
      record.event = "city_snapshot"
      record.turn = turn
      record.civ = name
      sink(json.encode(record))
    end
  end

  return function(playerId)
    local ok, err = pcall(poll, playerId)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
