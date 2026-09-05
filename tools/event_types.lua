-- Builds the list of event types the logger can write, for the
-- downstream analyst to read instead of keeping its own copy.
--
-- The list cannot be read off the source. An event name reaches a
-- record in four different shapes - a literal field, one side of a
-- conditional, a value in a table of transitions, an argument to a
-- helper - and no pattern separates "friendship_declared" from the
-- plain strings sitting next to it ("gold", "ally", "land"). What
-- every record does have is an event field, so the names are collected
-- by watching records go past while the tests run: whatever an
-- extractor returns, and whatever a poller encodes. Nothing reaches
-- the log by a third route.
--
-- A type therefore appears here exactly when a test produces it. An
-- untested emitter is a hole in the suite, not a hole in this list.
local M = {}

M.PATH = "dist/event-types.json"

function M.collector()
  local seen = {}
  local self = {}

  function self.note(record)
    if type(record) == "table" and type(record.event) == "string" then
      seen[record.event] = true
    end
  end

  function self.names()
    local names = {}
    for name in pairs(seen) do table.insert(names, name) end
    table.sort(names)
    return names
  end

  return self
end

function M.watch(collector, extractors, json)
  local encode = json.encode
  json.encode = function(record)
    collector.note(record)
    return encode(record)
  end

  for name, extractor in pairs(extractors) do
    if type(extractor) == "function" then
      extractors[name] = function(...)
        local record = extractor(...)
        collector.note(record)
        return record
      end
    end
  end
end

-- One name per line, so a new event type is a one-line diff.
function M.encode(names)
  local lines = {}
  for _, name in ipairs(names) do
    table.insert(lines, ("  %q"):format(name))
  end
  return "[\n" .. table.concat(lines, ",\n") .. "\n]\n"
end

function M.read(path)
  local file = io.open(path, "r")
  if not file then return {} end
  local text = file:read("*a")
  file:close()
  local names = {}
  for name in text:gmatch('"([%w_]+)"') do table.insert(names, name) end
  return names
end

function M.write(path, names)
  local file = assert(io.open(path, "w"))
  file:write(M.encode(names))
  file:close()
end

function M.collect()
  local t = require("tests.test_helper")
  local collector = M.collector()
  M.watch(collector, require("src.extractors"), require("src.json"))
  require("tests.suite").load(t)
  for _, test in ipairs(t.tests) do pcall(test.fn) end
  return collector.names()
end

if arg and arg[0] and arg[0]:find("event_types%.lua$") then
  package.path = "./?.lua;" .. package.path
  -- The suite requires this module back; without claiming the slot the
  -- file loads a second time and runs itself again.
  package.loaded["tools.event_types"] = M
  local names = M.collect()
  M.write(M.PATH, names)
  print(("wrote %s (%d event types)"):format(M.PATH, #names))
end

return M
