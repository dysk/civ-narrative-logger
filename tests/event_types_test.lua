local t = require("tests.test_helper")
local eventTypes = require("tools.event_types")

local function fakeJson()
  return { encode = function() return "{}" end }
end

t.test("an event is collected from the record an extractor returned", function()
  local collector = eventTypes.collector()
  local extractors = {
    CityCaptureComplete = function() return { event = "city_captured" } end,
  }
  eventTypes.watch(collector, extractors, fakeJson())
  extractors.CityCaptureComplete()
  t.assert_deep_equal({ "city_captured" }, collector.names())
end)

t.test("an event is collected from the record the encoder wrote", function()
  local collector, json = eventTypes.collector(), fakeJson()
  eventTypes.watch(collector, {}, json)
  json.encode({ event = "spy_created" })
  t.assert_deep_equal({ "spy_created" }, collector.names())
end)

t.test("a watched extractor still answers what it extracted", function()
  local collector = eventTypes.collector()
  local extractors = { PlayerCityFounded = function() return { event = "city_founded" } end }
  eventTypes.watch(collector, extractors, fakeJson())
  t.assert_deep_equal({ event = "city_founded" }, extractors.PlayerCityFounded())
end)

t.test("a watched encoder still answers what it encoded", function()
  local collector = eventTypes.collector()
  local json = { encode = function() return '{"event":"unit_lost"}' end }
  eventTypes.watch(collector, {}, json)
  t.assert_equal('{"event":"unit_lost"}', json.encode({ event = "unit_lost" }))
end)

t.test("a name is collected once, in alphabetical order", function()
  local collector, json = eventTypes.collector(), fakeJson()
  eventTypes.watch(collector, {}, json)
  json.encode({ event = "unit_lost" })
  json.encode({ event = "city_founded" })
  json.encode({ event = "unit_lost" })
  t.assert_deep_equal({ "city_founded", "unit_lost" }, collector.names())
end)

t.test("a record carrying no event contributes no name", function()
  local collector, json = eventTypes.collector(), fakeJson()
  local extractors = { PlayerDoTurn = function() return nil end }
  eventTypes.watch(collector, extractors, json)
  extractors.PlayerDoTurn()
  json.encode({ turn = 42 })
  t.assert_deep_equal({}, collector.names())
end)

t.test("the list is written one name per line", function()
  t.assert_equal('[\n  "city_founded",\n  "unit_lost"\n]\n',
    eventTypes.encode({ "city_founded", "unit_lost" }))
end)

t.test("a written list reads back as the names it holds", function()
  local path = os.tmpname()
  eventTypes.write(path, { "city_founded", "unit_lost" })
  local names = eventTypes.read(path)
  os.remove(path)
  t.assert_deep_equal({ "city_founded", "unit_lost" }, names)
end)

t.test("a list nobody has written yet reads back empty", function()
  t.assert_deep_equal({}, eventTypes.read("dist/no-such-file.json"))
end)
