local t = require("tests.test_helper")
local parser = require("tools.parser")

local LOGGER_LINE = '[1350613.044] CivNarrativeLogger: CIVLOG|'
  .. '{"event":"session_started","turn":0}'

t.test("payload extracts the JSON after the logger prefix", function()
  t.assert_equal('{"event":"session_started","turn":0}',
    parser.payload(LOGGER_LINE))
end)

t.test("payload strips the trailing CR of Windows line endings", function()
  t.assert_equal('{"event":"snapshot","turn":20}',
    parser.payload('[1350719.001] CivNarrativeLogger: CIVLOG|'
      .. '{"event":"snapshot","turn":20}\r'))
end)

t.test("payload is nil for other mods' lines", function()
  t.assert_nil(parser.payload(
    '[1350719.002] MPList: {"event_type":RemotePlayerTurnEnd}'))
end)

t.test("payload is nil for CIVLOG text printed by another context", function()
  t.assert_nil(parser.payload('[1350719.003] SomeOtherMod: CIVLOG|{"x":1}'))
end)

t.test("parse keeps only logger payloads, in order", function()
  local text = table.concat({
    '[1.0] Lekmod_improvements: table does not exist, check the xml!',
    LOGGER_LINE,
    '[2.0] MPList: {"event_type":RemotePlayerTurnEnd}',
    '[3.0] CivNarrativeLogger: CIVLOG|{"event":"tech_researched","turn":5}\r',
    '',
  }, "\n")
  t.assert_deep_equal({
    '{"event":"session_started","turn":0}',
    '{"event":"tech_researched","turn":5}',
  }, parser.parse(text))
end)
