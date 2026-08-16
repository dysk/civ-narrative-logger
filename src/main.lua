-- Entry point: gate on the local opt-in flag, then wire the logger
-- to the real game. Receives the game globals as a table so tests
-- (and the in-game loader) decide what "real" means.
local adapter = require("src.adapter")
local extractors = require("src.extractors")
local logger = require("src.logger")
local census = require("src.census")

local M = {}

function M.enabled(modding)
  local data = modding.OpenUserData("civ-narrative-logger", 1)
  local value = data.GetValue("enabled")
  return value == 1 or value == "1"
end

function M.start(g)
  if not M.enabled(g.Modding) then return end
  local deps = {
    events = g.GameEvents,
    extractors = extractors,
    civ = adapter.new(g),
    sink = function(line) g.print("CIVLOG|" .. line) end,
  }
  logger.attach(deps)
  logger.emit(deps, "sessionStarted", extractors.sessionStarted)
  g.GameEvents.PlayerDoTurn.Add(census.new(deps.civ, deps.sink))
end

return M
