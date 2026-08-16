-- Keeps a per-player city census between turns and emits city_destroyed
-- when a known city disappears. Razing fires no DLL hook (CvCity::
-- DoRazingTurn -> CvPlayer::disband contains no CallHook), so this is
-- polled once per player per turn via PlayerDoTurn rather than pushed
-- as an event. Registered directly on PlayerDoTurn (bypassing
-- logger.attach) since it needs cross-turn state and may emit zero or
-- more records per firing, unlike the one-hook-one-record extractors.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (census)", error = tostring(err) }
end

function M.new(civ, sink)
  local known = {}

  local function poll(playerId)
    local current = civ.citySet(playerId)
    for cityId, city in pairs(known[playerId] or {}) do
      if not current[cityId] then
        sink(json.encode({
          event = "city_destroyed",
          turn = civ.turn(),
          civ = civ.civName(playerId),
          city = city.name,
          x = city.x,
          y = city.y,
        }))
      end
    end
    known[playerId] = current
  end

  return function(playerId)
    local ok, err = pcall(poll, playerId)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
