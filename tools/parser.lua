-- Turns a Lua.log into events.jsonl: keeps only this logger's lines and
-- rewrites the "[timestamp] Context: CIVLOG|" prefix into a t_log field.
-- Run on the machine that logs (the pitboss server, or locally after a
-- test):
--   luajit tools/parser.lua path/to/Lua.log > events.jsonl
local M = {}

function M.payload(line)
  return line:match("%] CivNarrativeLogger: CIVLOG|(.-)%s*$")
end

-- The engine's seconds clock. Nothing in the game exposes real time to
-- Lua - Player:GetTotalTimePlayed is broken, see docs/lekmod-lua-api.md
-- - so this prefix is the only record of how long a turn took and when
-- a pitboss session actually ran. Discarding it loses it for good.
local function stampText(line)
  return line:match("^%[([%d%.]+)%]")
end

function M.timestamp(line)
  return tonumber(stampText(line))
end

-- Written in front of the payload's own keys rather than merged in
-- order: the parser has no JSON decoder, and this is a fact about the
-- log line, not about the game.
function M.record(line)
  local payload = M.payload(line)
  if not payload then return nil end
  local stamp = stampText(line)
  if not stamp then return payload end
  local body = payload:match("^{(.*)}$")
  if not body then return payload end
  local separator = body == "" and "" or ","
  return ('{"t_log":%s%s%s}'):format(stamp, separator, body)
end

function M.parse(text)
  local records = {}
  for line in text:gmatch("[^\n]+") do
    local record = M.record(line)
    if record then table.insert(records, record) end
  end
  return records
end

if arg and arg[0] and arg[0]:find("parser%.lua$") then
  local input = arg[1] and assert(io.open(arg[1], "r")) or io.stdin
  for line in input:lines() do
    local record = M.record(line)
    if record then
      io.write(record, "\n")
      io.flush()
    end
  end
end

return M
