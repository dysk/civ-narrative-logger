local t = require("tests.test_helper")
local congress = require("src.congress")

local function fakeCiv()
  local state = { turn = 1, snapshot = nil }
  local civ = {
    turn = function() return state.turn end,
    congressSnapshot = function() return state.snapshot end,
  }
  return civ, state
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

local function eventNames(lines)
  local names = {}
  for _, line in ipairs(lines) do
    table.insert(names, line:match('"event":"([%w_]+)"'))
  end
  return names
end

local function snapshot(fields)
  fields.proposals = fields.proposals or {}
  fields.active_resolutions = fields.active_resolutions or {}
  fields.delegates = fields.delegates or {}
  fields.united_nations = fields.united_nations or false
  fields.votes_needed_for_diplo_victory = fields.votes_needed_for_diplo_victory or 14
  return fields
end

t.test("no league means no output at all", function()
  local civ = fakeCiv()
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  t.assert_deep_equal({}, lines)
end)

t.test("a newly founded league emits congress_founded then congress_snapshot", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  t.assert_deep_equal({ "congress_founded", "congress_snapshot" }, eventNames(lines))
  t.assert_match('"host":"Poland"', lines[1])
end)

t.test("polling again in the same turn is a no-op, even for another player", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  poll(1)
  t.assert_deep_equal({ "congress_founded", "congress_snapshot" }, eventNames(lines))
end)

t.test("an unchanged league on a new turn only emits congress_snapshot", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "congress_snapshot" },
    eventNames(lines))
end)

t.test("a host change is reported before the snapshot", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Rome" })
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "congress_host_changed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"old_host":"Poland"', lines[3])
  t.assert_match('"new_host":"Rome"', lines[3])
end)

t.test("the United Nations forming is reported once", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland", united_nations = false })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Poland", united_nations = true })
  poll(0)
  state.turn = 3
  poll(0)
  t.assert_deep_equal({
    "congress_founded", "congress_snapshot",
    "united_nations_formed", "congress_snapshot",
    "congress_snapshot",
  }, eventNames(lines))
end)

t.test("a new proposal is reported", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({
    host = "Poland",
    proposals = {
      [5] = { id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false },
    },
  })
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "resolution_proposed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_EMBARGO"', lines[3])
  t.assert_match('"proposer":"Poland"', lines[3])
  t.assert_match('"repeal":false', lines[3])
end)

t.test("a proposal that becomes an active resolution has passed", function()
  local civ, state = fakeCiv()
  local proposal = { id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false }
  state.snapshot = snapshot({ host = "Poland", proposals = { [5] = proposal } })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({
    host = "Poland",
    active_resolutions = { [5] = { id = 5, type = "RESOLUTION_EMBARGO" } },
  })
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "resolution_passed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_EMBARGO"', lines[3])
end)

t.test("a proposal that just disappears has failed", function()
  local civ, state = fakeCiv()
  local proposal = { id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false }
  state.snapshot = snapshot({ host = "Poland", proposals = { [5] = proposal } })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Poland" })
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "resolution_failed", "congress_snapshot" },
    eventNames(lines))
end)

-- A repeal proposal carries the ID of the resolution it targets (the DLL's
-- CvRepealProposal takes pResolution->GetID()), so "is there an active
-- resolution under this ID" answers the opposite question for a repeal than
-- it does for an enactment.
t.test("a repeal proposal whose target survives has failed", function()
  local civ, state = fakeCiv()
  local proposal = { id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = true }
  state.snapshot = snapshot({
    host = "Poland",
    proposals = { [5] = proposal },
    active_resolutions = { [5] = { id = 5, type = "RESOLUTION_EMBARGO" } },
  })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({
    host = "Poland",
    active_resolutions = { [5] = { id = 5, type = "RESOLUTION_EMBARGO" } },
  })
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "resolution_failed", "congress_snapshot" },
    eventNames(lines))
end)

t.test("a repeal proposal that removes its target has passed", function()
  local civ, state = fakeCiv()
  local proposal = { id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = true }
  state.snapshot = snapshot({
    host = "Poland",
    proposals = { [5] = proposal },
    active_resolutions = { [5] = { id = 5, type = "RESOLUTION_EMBARGO" } },
  })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Poland" })
  poll(0)
  t.assert_deep_equal({
    "congress_founded", "congress_snapshot",
    "resolution_passed", "resolution_repealed", "congress_snapshot",
  }, eventNames(lines))
end)

t.test("an active resolution that disappears has been repealed", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({
    host = "Poland",
    active_resolutions = { [5] = { id = 5, type = "RESOLUTION_EMBARGO" } },
  })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Poland" })
  poll(0)
  t.assert_deep_equal(
    { "congress_founded", "congress_snapshot", "resolution_repealed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_EMBARGO"', lines[3])
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 1 end,
    congressSnapshot = function() error("boom") end,
  }
  local poll = congress.new(civ, sink)
  poll(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
