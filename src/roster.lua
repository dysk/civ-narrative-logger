-- Announces eliminations. Nothing pushes them: CvPlayer::setAlive calls
-- no hook, and a dead player takes no turn, so the only trace in the log
-- today is that civ.playerStats stops answering and the snapshot stream
-- quietly ends. This polls the roster of living majors once per turn and
-- reports whoever left it, together with who ended up holding their
-- original capital - the difference between a conquest and a collapse.
--
-- The first poll of a session records a baseline: a reload must not
-- report every civ that fell before it as newly eliminated.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (roster)", error = tostring(err) }
end

-- pairs() order is undefined, and the log is compared line by line.
local function sortedIds(majors)
  local ids = {}
  for id in pairs(majors) do table.insert(ids, id) end
  table.sort(ids)
  return ids
end

local function reportFallen(civ, sink, turn, known, majors)
  for _, id in ipairs(sortedIds(known)) do
    if not majors[id] then
      sink(json.encode({
        event = "player_eliminated",
        turn = turn,
        civ = known[id],
        capital_held_by = civ.capitalHolder(id),
      }))
    end
  end
end

function M.new(civ, sink)
  local state = { turn = nil, known = nil }

  local function poll()
    local turn = civ.turn()
    if turn == state.turn then return end
    state.turn = turn

    local majors = civ.livingMajors()
    if state.known then reportFallen(civ, sink, turn, state.known, majors) end
    state.known = majors
  end

  return function()
    local ok, err = pcall(poll)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
