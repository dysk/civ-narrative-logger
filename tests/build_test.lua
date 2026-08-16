local t = require("tests.test_helper")
local fakes = require("tests.fakes")
local build = require("tools.build")

local function runBuilt(storedFlag)
  local g, handlers, lines = fakes.gameGlobals(storedFlag)
  local chunk = assert(loadstring(build.generate(), "built"))
  setfenv(chunk, setmetatable(g, { __index = _G }))
  chunk()
  return handlers, lines
end

t.test("the built file stays inert without the enabled flag", function()
  local handlers, lines = runBuilt(nil)
  t.assert_deep_equal({ handlers = {}, lines = {} },
    { handlers = handlers, lines = lines })
end)

t.test("the built file logs through the whole stack when enabled", function()
  local handlers, lines = runBuilt(1)
  t.assert_equal("CIVLOG|", lines[1]:sub(1, 7))
  t.assert_match('"event":"session_started"', lines[1])
  t.assert_equal("function", type(handlers.CityCaptureComplete[1]))
end)
