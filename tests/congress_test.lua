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
  fields.projects = fields.projects or {}
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

-- The first poll of a session has no earlier snapshot to diff against,
-- whether that is the league being founded or the logger being restarted
-- into a league that has stood for a hundred turns. It cannot tell the
-- two apart, so it announces neither: the snapshot alone says the league
-- exists and who hosts it.
t.test("a league seen for the first time emits only congress_snapshot", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  t.assert_deep_equal({ "congress_snapshot" }, eventNames(lines))
  t.assert_match('"host":"Poland"', lines[1])
end)

t.test("polling again in the same turn is a no-op, even for another player", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  poll(1)
  t.assert_deep_equal({ "congress_snapshot" }, eventNames(lines))
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
    { "congress_snapshot", "congress_snapshot" },
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
    { "congress_snapshot", "congress_host_changed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"old_host":"Poland"', lines[2])
  t.assert_match('"new_host":"Rome"', lines[2])
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
    "congress_snapshot",
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
      [5] = {
        id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false,
        ongoing_effects = true,
      },
    },
  })
  poll(0)
  t.assert_deep_equal(
    { "congress_snapshot", "resolution_proposed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_EMBARGO"', lines[2])
  t.assert_match('"proposer":"Poland"', lines[2])
  t.assert_match('"repeal":false', lines[2])
end)

t.test("a proposal that becomes an active resolution has passed", function()
  local civ, state = fakeCiv()
  local proposal = {
    id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false,
    ongoing_effects = true,
  }
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
    { "congress_snapshot", "resolution_passed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_EMBARGO"', lines[2])
end)

t.test("a proposal that just disappears has failed", function()
  local civ, state = fakeCiv()
  local proposal = {
    id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = false,
    ongoing_effects = true,
  }
  state.snapshot = snapshot({ host = "Poland", proposals = { [5] = proposal } })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Poland" })
  poll(0)
  t.assert_deep_equal(
    { "congress_snapshot", "resolution_failed", "congress_snapshot" },
    eventNames(lines))
end)

-- A repeal proposal carries the ID of the resolution it targets (the DLL's
-- CvRepealProposal takes pResolution->GetID()), so "is there an active
-- resolution under this ID" answers the opposite question for a repeal than
-- it does for an enactment.
t.test("a repeal proposal whose target survives has failed", function()
  local civ, state = fakeCiv()
  local proposal = {
    id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = true,
    ongoing_effects = true,
  }
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
    { "congress_snapshot", "resolution_failed", "congress_snapshot" },
    eventNames(lines))
end)

t.test("a repeal proposal that removes its target has passed", function()
  local civ, state = fakeCiv()
  local proposal = {
    id = 5, type = "RESOLUTION_EMBARGO", proposer = "Poland", repeal = true,
    ongoing_effects = true,
  }
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
    "congress_snapshot",
    "resolution_passed", "resolution_repealed", "congress_snapshot",
  }, eventNames(lines))
end)

-- A resolution with only one-time effects never joins the active
-- resolutions (CvLeague::DoEnactResolution, CvVotingClasses.cpp:6160), so
-- the test above answers "failed" for it whatever the vote did. What an
-- enactment does leave behind is the league project it starts.
local worldFair = {
  id = 5, type = "RESOLUTION_WORLD_FAIR", proposer = "Poland", repeal = false,
  ongoing_effects = false, league_project = "LEAGUE_PROJECT_WORLD_FAIR",
}
local idle = { LEAGUE_PROJECT_WORLD_FAIR = { active = false, complete = false } }
local underway = { LEAGUE_PROJECT_WORLD_FAIR = { active = true, complete = false } }
local finished = { LEAGUE_PROJECT_WORLD_FAIR = { active = false, complete = true } }

local function pollOneShot(before, after, proposal)
  local civ, state = fakeCiv()
  state.snapshot = snapshot({
    host = "Poland", proposals = { [5] = proposal }, projects = before,
  })
  local lines, sink = captureSink()
  local poll = congress.new(civ, sink)
  poll(0)
  state.turn = 2
  state.snapshot = snapshot({ host = "Poland", projects = after })
  poll(0)
  return lines
end

t.test("a one-shot resolution whose project starts running has passed", function()
  t.assert_deep_equal(
    { "congress_snapshot", "resolution_passed", "congress_snapshot" },
    eventNames(pollOneShot(idle, underway, worldFair)))
end)

t.test("a one-shot resolution whose project already finished has passed", function()
  t.assert_deep_equal(
    { "congress_snapshot", "resolution_passed", "congress_snapshot" },
    eventNames(pollOneShot(idle, finished, worldFair)))
end)

t.test("a one-shot resolution whose project never starts has failed", function()
  t.assert_deep_equal(
    { "congress_snapshot", "resolution_failed", "congress_snapshot" },
    eventNames(pollOneShot(idle, idle, worldFair)))
end)

-- The game refuses to put a project resolution to the vote while its
-- project is already underway or complete (CvVotingClasses.cpp:2751), so
-- a project that was running before the vote leaves the vote unexplained
-- rather than decided.
t.test("a one-shot resolution whose project was already running is undetermined", function()
  t.assert_deep_equal({
    "congress_snapshot",
    "resolution_undetermined", "congress_snapshot",
  }, eventNames(pollOneShot(underway, underway, worldFair)))
end)

t.test("a one-shot resolution with no project leaves no trace to read", function()
  local lines = pollOneShot(idle, idle, {
    id = 5, type = "RESOLUTION_CHANGE_LEAGUE_HOST", proposer = "Poland",
    repeal = false, ongoing_effects = false,
  })
  t.assert_deep_equal({
    "congress_snapshot",
    "resolution_undetermined", "congress_snapshot",
  }, eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_CHANGE_LEAGUE_HOST"', lines[2])
  t.assert_match('"turn":2', lines[2])
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
    { "congress_snapshot", "resolution_repealed", "congress_snapshot" },
    eventNames(lines))
  t.assert_match('"resolution":"RESOLUTION_EMBARGO"', lines[2])
end)

-- A vote raised and decided entirely inside a reload seam was never in
-- a snapshot the resuming poller holds, so no diff can report it. The
-- proposals, the resolutions they act on and the projects an enactment
-- starts are what the outcome is read from, so the snapshot carries all
-- three and the analyst can settle the vote the poller could not see.
t.test("the snapshot carries the proposals in flight", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland", proposals = {
    [7] = { id = 7, type = "RESOLUTION_WORLD_RELIGION", proposer = "Rome",
      repeal = false, ongoing_effects = true },
  } })
  local lines, sink = captureSink()
  congress.new(civ, sink)(0)
  t.assert_match('"proposals":[{"id":7,"ongoing_effects":true,"proposer":"Rome",'
    .. '"repeal":false,"type":"RESOLUTION_WORLD_RELIGION"}]', lines[1])
end)

t.test("the snapshot carries the active resolutions and the league projects", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({
    host = "Poland",
    active_resolutions = { [3] = { id = 3, type = "RESOLUTION_EMBARGO" } },
    projects = { LEAGUE_PROJECT_WORLD_FAIR = { active = true, complete = false } },
  })
  local lines, sink = captureSink()
  congress.new(civ, sink)(0)
  t.assert_match('"active_resolutions":[{"id":3,"type":"RESOLUTION_EMBARGO"}]', lines[1])
  t.assert_match('"projects":{"LEAGUE_PROJECT_WORLD_FAIR":'
    .. '{"active":true,"complete":false}}', lines[1])
end)

-- Both lists are keyed by id, and pairs() hands them out in whatever
-- order it likes.
t.test("proposals come out ordered by id", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland", proposals = {
    [9] = { id = 9, type = "RESOLUTION_SCHOLARS", repeal = false },
    [2] = { id = 2, type = "RESOLUTION_EMBARGO", repeal = true },
  } })
  local lines, sink = captureSink()
  congress.new(civ, sink)(0)
  t.assert_match('"proposals":[{"id":2,"repeal":true,"type":"RESOLUTION_EMBARGO"},'
    .. '{"id":9,"repeal":false,"type":"RESOLUTION_SCHOLARS"}]', lines[1])
end)

-- A league with nothing before it is the common case; an empty list on
-- every one of those turns is weight the record does not need.
t.test("a league with nothing in flight carries no lists at all", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland" })
  local lines, sink = captureSink()
  congress.new(civ, sink)(0)
  t.assert_equal(nil, lines[1]:find("proposals", 1, true))
  t.assert_equal(nil, lines[1]:find("active_resolutions", 1, true))
  t.assert_equal(nil, lines[1]:find("projects", 1, true))
end)

-- united_nations_formed is a diff, and a diff is exactly what a resuming
-- session skips. The flag on the record survives the seam.
t.test("the snapshot says whether the league is the United Nations", function()
  local civ, state = fakeCiv()
  state.snapshot = snapshot({ host = "Poland", united_nations = true })
  local lines, sink = captureSink()
  congress.new(civ, sink)(0)
  t.assert_match('"united_nations":true', lines[1])
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
