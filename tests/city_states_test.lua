local t = require("tests.test_helper")
local cityStates = require("src.city_states")

-- Two city-states, two majors, nobody past neutral with either.
local function calm()
  return {
    [2] = { civ = "Geneva", relations = {
      [0] = { civ = "Poland", influence = 40 },
      [6] = { civ = "Rome", influence = 12 },
    } },
    [3] = { civ = "Sparta", relations = {
      [0] = { civ = "Poland", influence = 5 },
    } },
  }
end

local function befriended()
  local snapshot = calm()
  snapshot[2].relations[0].influence = 61
  snapshot[2].relations[0].level = "friend"
  return snapshot
end

local function withPledge(minor, from)
  local snapshot = calm()
  snapshot[minor].relations[from].protected = true
  return snapshot
end

local function fakeCiv(state)
  return {
    turn = function() return state.turn end,
    cityStateSnapshot = function() return state.snapshot end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

-- Drives one poll per listed turn through a single poller.
local function pollThrough(states)
  local lines, sink = captureSink()
  local state = { turn = states[1].turn, snapshot = states[1].snapshot }
  local poll = cityStates.new(fakeCiv(state), sink)
  for _, step in ipairs(states) do
    state.turn, state.snapshot = step.turn, step.snapshot
    poll(0)
  end
  return lines
end

-- The opening baseline is one line per city-state; this is what the
-- poller wrote after it.
local function changesAfter(states)
  local lines = pollThrough(states)
  for _ in pairs(states[1].snapshot) do table.remove(lines, 1) end
  return lines
end

-- A session opens with the standing state of every city-state, so a log
-- resumed mid-game is not blind until somebody happens to cross a
-- threshold - and a city-state nobody ever courts still appears.
t.test("opens with a baseline snapshot for every city-state", function()
  t.assert_deep_equal({
    '{"city_state":"Geneva","event":"city_state_snapshot",'
      .. '"relations":[{"civ":"Poland","influence":40},'
      .. '{"civ":"Rome","influence":12}],"turn":10}',
    '{"city_state":"Sparta","event":"city_state_snapshot",'
      .. '"relations":[{"civ":"Poland","influence":5}],"turn":10}',
  }, pollThrough({ { turn = 10, snapshot = calm() } }))
end)

-- Influence moves every turn on its own. Writing that would be four
-- fifths of the log to say that decay is decay, so after the baseline
-- only a crossed threshold is worth a record - and per_turn in each one
-- lets the curve between them be read back.
t.test("writes nothing while no level has changed", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, snapshot = calm() },
    { turn = 11, snapshot = calm() },
  }))
end)

t.test("writes a snapshot for the city-state whose level changed", function()
  t.assert_deep_equal({
    '{"city_state":"Geneva","event":"city_state_snapshot",'
      .. '"relations":[{"civ":"Poland","influence":61,"level":"friend"},'
      .. '{"civ":"Rome","influence":12}],"turn":11}',
  }, changesAfter({
    { turn = 10, snapshot = calm() },
    { turn = 11, snapshot = befriended() },
  }))
end)

t.test("carries the ally into the snapshot when one holds it", function()
  local held = calm()
  held[2].ally = "Poland"
  t.assert_match('"ally":"Poland"', pollThrough({ { turn = 10, snapshot = held } })[1])
end)

-- Pledging to protect fires no hook of any kind, so the poller is the
-- only thing that can report one. It is a discrete act rather than a
-- number, which is why it is an event and not left to the snapshot.
t.test("emits city_state_protected when a major pledges", function()
  t.assert_deep_equal({
    '{"city_state":"Geneva","civ":"Poland",'
      .. '"event":"city_state_protected","turn":11}',
  }, changesAfter({
    { turn = 10, snapshot = calm() },
    { turn = 11, snapshot = withPledge(2, 0) },
  }))
end)

t.test("emits city_state_protection_ended when a pledge lapses", function()
  t.assert_deep_equal({
    '{"city_state":"Geneva","civ":"Poland",'
      .. '"event":"city_state_protection_ended","turn":11}',
  }, changesAfter({
    { turn = 10, snapshot = withPledge(2, 0) },
    { turn = 11, snapshot = calm() },
  }))
end)

t.test("a pledge standing since before the session is not news", function()
  t.assert_equal(2, #pollThrough({ { turn = 10, snapshot = withPledge(2, 0) } }))
end)

-- PlayerDoTurn fires once per living player; the city-state state is
-- game-global, so the poll is gated on the turn like the congress poll.
t.test("polls once per turn, however many players take theirs", function()
  local lines, sink = captureSink()
  local state = { turn = 10, snapshot = calm() }
  local poll = cityStates.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.snapshot = 11, befriended()
  poll(0)
  poll(1)
  poll(6)
  t.assert_equal(3, #lines)
end)

t.test("city-states come out in a deterministic order", function()
  local three = calm()
  three[4] = { civ = "Venice", relations = {} }
  local seen = {}
  for _, line in ipairs(pollThrough({ { turn = 10, snapshot = three } })) do
    table.insert(seen, line:match('"city_state":"(%a+)"'))
  end
  t.assert_deep_equal({ "Geneva", "Sparta", "Venice" }, seen)
end)

t.test("a city-state falling out of the snapshot is not a lapsed pledge", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, snapshot = withPledge(2, 0) },
    { turn = 11, snapshot = {} },
  }))
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 10 end,
    cityStateSnapshot = function() error("boom") end,
  }
  cityStates.new(civ, sink)(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
