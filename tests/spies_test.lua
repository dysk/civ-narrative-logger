local t = require("tests.test_helper")
local spies = require("src.spies")

local function spy(overrides)
  local entry = {
    civ = "Poland", spy = "Alexis", rank = "recruit",
    state = "gathering_intel", city = "Antium", city_civ = "Rome",
    x = 40, y = 3, turns_left = 6, progress = 62, surveillance = true,
  }
  for field, value in pairs(overrides or {}) do entry[field] = value end
  return entry
end

local function fakeCiv(state)
  return {
    turn = function() return state.turn end,
    spies = function() return state.spies end,
  }
end

local function captureSink()
  local lines = {}
  return lines, function(line) table.insert(lines, line) end
end

local function pollThrough(states)
  local lines, sink = captureSink()
  local state = { turn = states[1].turn, spies = states[1].spies }
  local poll = spies.new(fakeCiv(state), sink)
  for _, step in ipairs(states) do
    state.turn, state.spies = step.turn, step.spies
    poll(0)
  end
  return lines
end

-- Nothing exists before somebody reaches the Renaissance, so the poll is
-- an empty list against an empty list for most of the game.
t.test("logs nothing while nobody has a spy", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, spies = {} },
    { turn = 11, spies = {} },
  }))
end)

-- The Renaissance grants one to everybody at once, so eight of these
-- landing on one turn is the rule firing, not the poller repeating
-- itself.
t.test("emits spy_created for a spy that was not there before", function()
  t.assert_deep_equal({
    '{"civ":"Poland","event":"spy_created","spy":"Alexis","turn":11}',
  }, pollThrough({
    { turn = 10, spies = {} },
    { turn = 11, spies = { ["0:0"] = spy({ state = "unassigned", city = nil,
        city_civ = nil, x = nil, y = nil, turns_left = nil, progress = nil,
        surveillance = nil }) } },
  }))
end)

t.test("logs nothing on the first poll, which is only a baseline", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy() } },
  }))
end)

-- Where a spy is sent is the decision; the state cycle that follows is
-- fixed by the destination, which is why it is not logged turn by turn.
t.test("emits spy_moved with the city it was sent to and whose it is", function()
  t.assert_deep_equal({
    '{"city":"Warsaw","city_civ":"Poland","civ":"Poland","event":"spy_moved",'
      .. '"spy":"Alexis","state":"counter_intel","turn":11,"x":10,"y":20}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy() } },
    { turn = 11, spies = { ["0:0"] = spy({ city = "Warsaw", city_civ = "Poland",
        x = 10, y = 20, state = "counter_intel" }) } },
  }))
end)

t.test("emits spy_promoted when the rank goes up", function()
  t.assert_deep_equal({
    '{"civ":"Poland","event":"spy_promoted","rank":"agent","spy":"Alexis","turn":11}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy() } },
    { turn = 11, spies = { ["0:0"] = spy({ rank = "agent" }) } },
  }))
end)

t.test("emits spy_killed when a spy turns up dead", function()
  t.assert_deep_equal({
    '{"city":"Antium","city_civ":"Rome","civ":"Poland","event":"spy_killed",'
      .. '"spy":"Alexis","turn":11}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy() } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "dead", city = "Antium",
        city_civ = "Rome" }) } },
  }))
end)

-- A killed spy comes back under a new name at the same agent id
-- (CvEspionageClasses.cpp:930-936), so without this the log would show
-- one agent silently renamed.
t.test("emits spy_revived when a dead spy returns under a new name", function()
  t.assert_deep_equal({
    '{"civ":"Poland","event":"spy_revived","spy":"Claudette","turn":11}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy({ state = "dead" }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "unassigned",
        spy = "Claudette", city = nil, city_civ = nil, x = nil, y = nil,
        turns_left = nil, progress = nil, surveillance = nil }) } },
  }))
end)

-- A finished heist does not change the spy's state or move it: the DLL
-- calls ResetProgress and SetActivity and leaves it gathering intel in
-- the same city (CvEspionageClasses.cpp:807-810). Progress only ever
-- climbs otherwise, so a drop is the completion.
t.test("emits spy_mission_completed when progress resets in place", function()
  t.assert_deep_equal({
    '{"city":"Antium","city_civ":"Rome","civ":"Poland",'
      .. '"event":"spy_mission_completed","spy":"Alexis",'
      .. '"state":"gathering_intel","turn":11}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy({ progress = 96 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ progress = 4 }) } },
  }))
end)

t.test("a rigged election completes the same way an intel theft does", function()
  t.assert_match('"state":"rigging_election"', pollThrough({
    { turn = 10, spies = { ["0:0"] = spy({ state = "rigging_election", progress = 90 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "rigging_election", progress = 0 }) } },
  })[1])
end)

t.test("climbing progress is not a completed mission", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy({ progress = 40 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ progress = 55 }) } },
  }))
end)

-- Progress restarts wherever a spy lands, so a reset that comes with a
-- move is the new posting, not a finished job.
t.test("progress falling because the spy moved is not a completed mission", function()
  t.assert_deep_equal({
    '{"city":"Warsaw","city_civ":"Poland","civ":"Poland","event":"spy_moved",'
      .. '"spy":"Alexis","state":"gathering_intel","turn":11,"x":10,"y":20}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy({ progress = 96 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ city = "Warsaw", city_civ = "Poland",
        x = 10, y = 20, progress = 0 }) } },
  }))
end)

-- PlayerDoTurn fires once per living player; the spy list is read for
-- every major at once, so the poll is gated on the turn.
t.test("polls once per turn, however many players take theirs", function()
  local lines, sink = captureSink()
  local state = { turn = 10, spies = {} }
  local poll = spies.new(fakeCiv(state), sink)
  poll(0)
  state.turn, state.spies = 11, { ["0:0"] = spy() }
  poll(0)
  poll(1)
  t.assert_equal(1, #lines)
end)

t.test("events come out in a deterministic order", function()
  local seen = {}
  for _, line in ipairs(pollThrough({
    { turn = 10, spies = {} },
    { turn = 11, spies = { ["1:0"] = spy({ civ = "Rome", spy = "Lucius" }),
                           ["0:0"] = spy() } },
  })) do
    table.insert(seen, line:match('"spy":"(%a+)"'))
  end
  t.assert_deep_equal({ "Alexis", "Lucius" }, seen)
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 10 end,
    spies = function() error("boom") end,
  }
  spies.new(civ, sink)(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
