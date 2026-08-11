local t = require("tests.test_helper")
local logger = require("src.logger")

-- Mimics GameEvents: accessing any hook name yields an object with Add.
local function fakeEvents()
  local handlers = {}
  local events = setmetatable({}, {
    __index = function(_, name)
      return { Add = function(fn) handlers[name] = fn end }
    end,
  })
  return events, handlers
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

local civ = { turn = function() return 42 end }

t.test("attach subscribes a handler for every extractor", function()
  local events, handlers = fakeEvents()
  logger.attach({
    events = events,
    extractors = {
      CityCaptureComplete = function() end,
      DeclareWar = function() end,
    },
    civ = civ,
    sink = function() end,
  })
  local names = {}
  for name in pairs(handlers) do table.insert(names, name) end
  table.sort(names)
  t.assert_deep_equal({ "CityCaptureComplete", "DeclareWar" }, names)
end)

t.test("a fired hook encodes the record and hands it to the sink", function()
  local events, handlers = fakeEvents()
  local lines, sink = captureSink()
  logger.attach({
    events = events,
    extractors = {
      PlayerCityFounded = function(c, playerId)
        return { event = "city_founded", turn = c.turn(), player = playerId }
      end,
    },
    civ = civ,
    sink = sink,
  })
  handlers.PlayerCityFounded(3)
  t.assert_deep_equal({ '{"event":"city_founded","player":3,"turn":42}' }, lines)
end)

t.test("hooks whose extractor returns nil log nothing", function()
  local events, handlers = fakeEvents()
  local lines, sink = captureSink()
  logger.attach({
    events = events,
    extractors = { CityConstructed = function() return nil end },
    civ = civ,
    sink = sink,
  })
  handlers.CityConstructed(0, 3, 5)
  t.assert_deep_equal({}, lines)
end)

t.test("an extractor error is logged instead of raised", function()
  local events, handlers = fakeEvents()
  local lines, sink = captureSink()
  logger.attach({
    events = events,
    extractors = { Broken = function() error("boom") end },
    civ = civ,
    sink = sink,
  })
  handlers.Broken()
  t.assert_match('"event":"logger_error"', lines[1])
  t.assert_match('"hook":"Broken"', lines[1])
end)
