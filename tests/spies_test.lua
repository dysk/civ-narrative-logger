local t = require("tests.test_helper")
local spies = require("src.spies")

-- pairs() skips a key whose value is nil, so overrides use NONE to clear
-- a field the way a freshly granted or just-revived spy has none.
local NONE = {}

local function spy(overrides)
  local entry = {
    civ = "Poland", agent = 0, spy = "Alexis", rank = "recruit",
    state = "gathering_intel", city = "Antium", city_civ = "Rome",
    x = 40, y = 3, turns_left = 6, progress = 62, surveillance = true,
  }
  for field, value in pairs(overrides or {}) do
    entry[field] = value ~= NONE and value or nil
  end
  return entry
end

local function unassignedSpy(overrides)
  local cleared = { state = "unassigned", city = NONE, city_civ = NONE,
    x = NONE, y = NONE, turns_left = NONE, progress = NONE, surveillance = NONE }
  for field, value in pairs(overrides or {}) do cleared[field] = value end
  return spy(cleared)
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

-- The opening baseline is one spy_created per spy already in place;
-- this is what the poller wrote after it.
local function changesAfter(states)
  local lines = pollThrough(states)
  for _ in pairs(states[1].spies) do table.remove(lines, 1) end
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
    '{"agent":0,"civ":"Poland","event":"spy_created","spy":"Alexis","turn":11}',
  }, pollThrough({
    { turn = 10, spies = {} },
    { turn = 11, spies = { ["0:0"] = unassignedSpy() } },
  }))
end)

-- A spy first polled while already posted still carries a city, and the
-- creation is the only record that posting will get.
t.test("emits spy_created with the city when the spy is first seen posted", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Antium","city_civ":"Rome","civ":"Poland","event":"spy_created",'
      .. '"spy":"Alexis","state":"gathering_intel","turn":11}',
  }, pollThrough({
    { turn = 10, spies = {} },
    { turn = 11, spies = { ["0:0"] = spy({ city = "Antium", city_civ = "Rome" }) } },
  }))
end)

-- A session that resumes a game already under way has nothing to diff
-- against, and every spy it can see was created, and posted, inside the
-- reload seam. So the first poll announces them all rather than swallow
-- them: the record carries the agent id, which is stable for the whole
-- game, so the analyst drops the ones it has already seen.
t.test("the first poll announces every spy it can already see", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Antium","city_civ":"Rome","civ":"Poland","event":"spy_created",'
      .. '"spy":"Alexis","state":"gathering_intel","turn":10}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy() } },
  }))
end)

-- A counterspy that settled in before the reload has nothing left to
-- change, so the transition into counter_intel already happened and the
-- creation is the only record that garrison will ever get. The state is
-- what separates it from a spy merely passing through its own territory.
t.test("a spy first seen already posted says what it is doing there", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Krakow","city_civ":"Poland","civ":"Poland","event":"spy_created",'
      .. '"spy":"Alexis","state":"counter_intel","turn":10}',
  }, pollThrough({
    { turn = 10, spies = { ["0:0"] = spy({ city = "Krakow", city_civ = "Poland",
        state = "counter_intel" }) } },
  }))
end)

t.test("a spy the first poll announced is not announced again", function()
  t.assert_equal(1, #pollThrough({
    { turn = 10, spies = { ["0:0"] = spy() } },
    { turn = 11, spies = { ["0:0"] = spy() } },
  }))
end)

-- Where a spy is sent is the decision; the state cycle that follows is
-- fixed by the destination, which is why it is not logged turn by turn.
t.test("emits spy_moved with the city it was sent to and whose it is", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Warsaw","city_civ":"Poland","civ":"Poland","event":"spy_moved",'
      .. '"spy":"Alexis","state":"counter_intel","turn":11,"x":10,"y":20}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy() } },
    { turn = 11, spies = { ["0:0"] = spy({ city = "Warsaw", city_civ = "Poland",
        x = 10, y = 20, state = "counter_intel" }) } },
  }))
end)

-- A counterspy's progress is always nil, so spy_moved is the only event
-- it can ever produce. When the move that posted it home did not change
-- the coordinates, the transition into counter_intel is that posting.
t.test("emits spy_moved when a spy turns to counter-intelligence in place", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Warsaw","city_civ":"Poland","civ":"Poland","event":"spy_moved",'
      .. '"spy":"Alexis","state":"counter_intel","turn":11,"x":40,"y":3}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ state = "travelling",
        city = "Warsaw", city_civ = "Poland" }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "counter_intel",
        city = "Warsaw", city_civ = "Poland" }) } },
  }))
end)

-- The transition is the posting only the first time; a counterspy left
-- in place must not re-announce itself every poll.
t.test("does not repeat spy_moved while a counterspy sits still", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ state = "counter_intel",
        city = "Warsaw", city_civ = "Poland" }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "counter_intel",
        city = "Warsaw", city_civ = "Poland" }) } },
  }))
end)

t.test("emits spy_promoted when the rank goes up", function()
  t.assert_deep_equal({
    '{"agent":0,"civ":"Poland","event":"spy_promoted","rank":"agent","spy":"Alexis","turn":11}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy() } },
    { turn = 11, spies = { ["0:0"] = spy({ rank = "agent" }) } },
  }))
end)

-- The DLL empties a spy's location before it sets SPY_STATE_DEAD, so the
-- dead record carries no city. The death site is the city the spy held on
-- the last live poll.
t.test("emits spy_killed with the city from the last live poll", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Antium","city_civ":"Rome","civ":"Poland","event":"spy_killed",'
      .. '"spy":"Alexis","turn":11}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ city = "Antium", city_civ = "Rome" }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "dead", city = nil,
        city_civ = nil }) } },
  }))
end)

-- A city that changes hands or is razed throws every major's spy out of
-- it, the captor's own included (CvPlayer.cpp:2775-2829,
-- CvCity.cpp:2069-2073). ExtractSpyFromCity empties the position and
-- leaves the spy unassigned, and nothing else in the diff can see that:
-- the move check needs a destination and an unassigned spy answers -1
-- for progress. Without this the posting simply stops being mentioned
-- and a reader goes on believing the spy is still watching.
t.test("emits spy_evicted when a spy loses the city it was posted in", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Antium","city_civ":"Rome","civ":"Poland","event":"spy_evicted",'
      .. '"spy":"Alexis","turn":11}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ city = "Antium", city_civ = "Rome" }) } },
    { turn = 11, spies = { ["0:0"] = unassignedSpy() } },
  }))
end)

-- A spy is unassigned from the moment it is granted until it is sent
-- somewhere, which is most of a careful player's game.
t.test("says nothing about a spy that was never posted anywhere", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, spies = { ["0:0"] = unassignedSpy() } },
    { turn = 11, spies = { ["0:0"] = unassignedSpy() } },
  }))
end)

-- A killed spy comes back under a new name at the same agent id
-- (CvEspionageClasses.cpp:930-936), so without this the log would show
-- one agent silently renamed.
t.test("emits spy_revived when a dead spy returns under a new name", function()
  t.assert_deep_equal({
    '{"agent":0,"civ":"Poland","event":"spy_revived","spy":"Claudette","turn":11}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ state = "dead" }) } },
    { turn = 11, spies = { ["0:0"] = unassignedSpy({ spy = "Claudette" }) } },
  }))
end)

-- Names are the only thing a reader could stitch a career from, and the
-- DLL changes them at exactly the moment a career is hardest to follow.
-- The agent id runs through the death unchanged, so the two records
-- either side of it can still be recognised as one spy.
t.test("a death and the revival after it carry the same agent id", function()
  local lines = changesAfter({
    { turn = 10, spies = { ["0:5"] = spy({ agent = 5 }) } },
    { turn = 11, spies = { ["0:5"] = spy({ agent = 5, state = "dead",
        city = NONE, city_civ = NONE }) } },
    { turn = 12, spies = { ["0:5"] = unassignedSpy({ agent = 5,
        spy = "Claudette" }) } },
  })
  t.assert_deep_equal({
    '{"agent":5,"city":"Antium","city_civ":"Rome","civ":"Poland",'
      .. '"event":"spy_killed","spy":"Alexis","turn":11}',
    '{"agent":5,"civ":"Poland","event":"spy_revived","spy":"Claudette","turn":12}',
  }, lines)
end)

-- A spy that revives and is posted before the next poll would otherwise
-- lose the posting: the dead record it is diffed against carries no
-- position, so the move check never sees the arrival.
t.test("emits the posting when a spy revives already in a city", function()
  t.assert_deep_equal({
    '{"agent":0,"civ":"Poland","event":"spy_revived","spy":"Claudette","turn":11}',
    '{"agent":0,"city":"Kyoto","city_civ":"Japan","civ":"Poland","event":"spy_moved",'
      .. '"spy":"Claudette","state":"travelling","turn":11,"x":5,"y":9}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ state = "dead" }) } },
    { turn = 11, spies = { ["0:0"] = unassignedSpy({ spy = "Claudette",
        state = "travelling", city = "Kyoto", city_civ = "Japan",
        x = 5, y = 9 }) } },
  }))
end)

-- A finished heist does not change the spy's state or move it: the DLL
-- calls ResetProgress and SetActivity and leaves it gathering intel in
-- the same city (CvEspionageClasses.cpp:807-810). Progress only ever
-- climbs otherwise, so a drop is the completion.
t.test("emits spy_mission_completed when progress resets in place", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Antium","city_civ":"Rome","civ":"Poland",'
      .. '"event":"spy_mission_completed","spy":"Alexis",'
      .. '"state":"gathering_intel","turn":11}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ progress = 96 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ progress = 4 }) } },
  }))
end)

t.test("a rigged election completes the same way an intel theft does", function()
  t.assert_match('"state":"rigging_election"', changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ state = "rigging_election", progress = 90 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "rigging_election", progress = 0 }) } },
  })[1])
end)

-- Travelling, surveillance and gathering intel share one progress
-- counter and each state starts it at zero, so a state transition drops
-- progress in place without a mission having finished.
t.test("progress falling at a state transition is not a completed mission", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ state = "surveillance", progress = 88 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ state = "gathering_intel", progress = 0 }) } },
  }))
end)

t.test("climbing progress is not a completed mission", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ progress = 40 }) } },
    { turn = 11, spies = { ["0:0"] = spy({ progress = 55 }) } },
  }))
end)

-- Progress restarts wherever a spy lands, so a reset that comes with a
-- move is the new posting, not a finished job.
t.test("progress falling because the spy moved is not a completed mission", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Warsaw","city_civ":"Poland","civ":"Poland","event":"spy_moved",'
      .. '"spy":"Alexis","state":"gathering_intel","turn":11,"x":10,"y":20}',
  }, changesAfter({
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

-- The turn surveillance goes true is the turn the spy's owner can first
-- see into the city. Nothing else in the log marks it.
t.test("emits spy_surveillance_established when surveillance goes up in place", function()
  t.assert_deep_equal({
    '{"agent":0,"city":"Antium","city_civ":"Rome","civ":"Poland",'
      .. '"event":"spy_surveillance_established","spy":"Alexis","turn":11}',
  }, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ surveillance = false }) } },
    { turn = 11, spies = { ["0:0"] = spy({ surveillance = true }) } },
  }))
end)

t.test("surveillance dropping to false is not an event", function()
  t.assert_deep_equal({}, changesAfter({
    { turn = 10, spies = { ["0:0"] = spy({ surveillance = true }) } },
    { turn = 11, spies = { ["0:0"] = spy({ surveillance = false }) } },
  }))
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
