package.path = "./?.lua;" .. package.path
local t = require("tests.test_helper")
local suite = require("tests.suite")
local eventTypes = require("tools.event_types")

-- Watch before the suite loads: the committed event type list is only
-- honest if every record the tests produce is seen.
local collector = eventTypes.collector()
eventTypes.watch(collector, require("src.extractors"), require("src.json"))

suite.load(t)

-- Registered last, so every other test has run by the time it looks.
t.test("the committed event type list is what the suite emits today", function()
  t.assert_deep_equal(collector.names(), eventTypes.read(eventTypes.PATH))
end)

t.run()
