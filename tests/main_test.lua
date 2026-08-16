local t = require("tests.test_helper")
local fakes = require("tests.fakes")
local main = require("src.main")

t.test("enabled when the stored flag is 1", function()
  t.assert_equal(true, main.enabled(fakes.modding(1)))
end)

t.test("enabled when the stored flag is the string '1'", function()
  t.assert_equal(true, main.enabled(fakes.modding("1")))
end)

t.test("disabled when the flag is missing", function()
  t.assert_equal(false, main.enabled(fakes.modding(nil)))
end)

t.test("start does nothing when logging is not enabled", function()
  local g, handlers, lines = fakes.gameGlobals(nil)
  main.start(g)
  t.assert_deep_equal({ handlers = {}, lines = {} },
    { handlers = handlers, lines = lines })
end)

t.test("start attaches the hooks when enabled", function()
  local g, handlers = fakes.gameGlobals(1)
  main.start(g)
  t.assert_equal("function", type(handlers.DeclareWar[1]))
end)

t.test("start emits a prefixed session_started record when enabled", function()
  local g, _, lines = fakes.gameGlobals(1)
  main.start(g)
  t.assert_equal("CIVLOG|", lines[1]:sub(1, 7))
  t.assert_match('"event":"session_started"', lines[1])
end)

t.test("start registers the snapshot extractor plus the census and congress pollers", function()
  local g, handlers = fakes.gameGlobals(1)
  main.start(g)
  t.assert_equal(3, #handlers.PlayerDoTurn)
end)
