-- Wires extractors to GameEvents hooks and streams encoded records
-- to a sink. A logging failure must never escape into the game, so
-- extractor errors become logger_error records instead of being raised.
local json = require("src.json")

local M = {}

local function errorRecord(hookName, err)
  return { event = "logger_error", hook = hookName, error = tostring(err) }
end

local function handler(deps, name, extractor)
  return function(...)
    local ok, record = pcall(extractor, deps.civ, ...)
    if ok and record == nil then return end
    if not ok then record = errorRecord(name, record) end
    deps.sink(json.encode(record))
  end
end

-- Extractors named in UpperCamelCase are GameEvents hooks; lowercase
-- names are helpers emitted explicitly (see docs/design-decisions.md).
function M.attach(deps)
  for name, extractor in pairs(deps.extractors) do
    if name:match("^%u") then
      deps.events[name].Add(handler(deps, name, extractor))
    end
  end
end

function M.emit(deps, name, extractor, ...)
  handler(deps, name, extractor)(...)
end

return M
