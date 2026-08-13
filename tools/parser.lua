-- Turns a Lua.log into events.jsonl: keeps only this logger's lines
-- and strips the "[timestamp] Context: CIVLOG|" prefix. Run on the
-- machine that logs (the pitboss server, or locally after a test):
--   luajit tools/parser.lua path/to/Lua.log > events.jsonl
local M = {}

function M.payload(line)
  return line:match("%] CivNarrativeLogger: CIVLOG|(.-)%s*$")
end

function M.parse(text)
  local payloads = {}
  for line in text:gmatch("[^\n]+") do
    local payload = M.payload(line)
    if payload then table.insert(payloads, payload) end
  end
  return payloads
end

if arg and arg[0] and arg[0]:find("parser%.lua$") then
  local input = arg[1] and assert(io.open(arg[1], "r")) or io.stdin
  for line in input:lines() do
    local payload = M.payload(line)
    if payload then
      io.write(payload, "\n")
      io.flush()
    end
  end
end

return M
