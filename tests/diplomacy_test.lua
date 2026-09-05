local t = require("tests.test_helper")
local diplomacy = require("src.diplomacy")

local NAMES = { [0] = "Poland", [1] = "Rome", [2] = "Egypt" }

local function pair(overrides)
  local entry = {
    dof = false, open_borders = false, embassy = false,
    defensive_pact = false, trade_agreement = false,
  }
  for k, v in pairs(overrides or {}) do entry[k] = v end
  return entry
end

-- Every ordered pair of the given players, all flags down.
local function calm(ids)
  local snapshot = {}
  for _, a in ipairs(ids) do
    snapshot[a] = {}
    for _, b in ipairs(ids) do
      if a ~= b then snapshot[a][b] = pair() end
    end
  end
  return snapshot
end

local function fakeCiv(state)
  return {
    turn = function() return state.turn end,
    civName = function(playerId) return NAMES[playerId] end,
    diplomacySnapshot = function() return state.snapshot end,
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
  local poll = diplomacy.new(fakeCiv(state), sink)
  for _, step in ipairs(states) do
    state.turn, state.snapshot = step.turn, step.snapshot
    poll(0)
  end
  return lines
end

t.test("logs nothing on the first poll, which is only a baseline", function()
  local snapshot = calm({ 0, 1 })
  snapshot[0][1].dof = true
  snapshot[1][0].dof = true
  t.assert_deep_equal({}, pollThrough({ { turn = 10, snapshot = snapshot } }))
end)

t.test("logs nothing while the diplomatic state is unchanged", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = calm({ 0, 1 }) },
  }))
end)

-- The DLL sets DoF on both players (CvDiplomacyAI.cpp:11038-11039), so a
-- friendship is one fact about a pair, not two facts about directions.
t.test("emits friendship_declared once for the pair, not once per direction", function()
  local after = calm({ 0, 1 })
  after[0][1].dof = true
  after[1][0].dof = true
  t.assert_deep_equal({
    '{"civs":["Poland","Rome"],"event":"friendship_declared","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = after },
  }))
end)

t.test("emits friendship_ended when a declaration lapses", function()
  local before = calm({ 0, 1 })
  before[0][1].dof = true
  before[1][0].dof = true
  t.assert_deep_equal({
    '{"civs":["Poland","Rome"],"event":"friendship_ended","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = before },
    { turn = 11, snapshot = calm({ 0, 1 }) },
  }))
end)

t.test("emits open_borders_granted for the side that opened its borders", function()
  local after = calm({ 0, 1 })
  after[0][1].open_borders = true
  t.assert_deep_equal({
    '{"civ":"Poland","event":"open_borders_granted","other_civ":"Rome","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = after },
  }))
end)

t.test("emits open_borders_revoked when the grant ends", function()
  local before = calm({ 0, 1 })
  before[0][1].open_borders = true
  t.assert_deep_equal({
    '{"civ":"Poland","event":"open_borders_revoked","other_civ":"Rome","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = before },
    { turn = 11, snapshot = calm({ 0, 1 }) },
  }))
end)

t.test("emits embassy_established for the side that placed the embassy", function()
  local after = calm({ 0, 1 })
  after[0][1].embassy = true
  t.assert_deep_equal({
    '{"civ":"Poland","event":"embassy_established","other_civ":"Rome","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = after },
  }))
end)

t.test("emits defensive_pact_signed once for the pair", function()
  local after = calm({ 0, 1 })
  after[0][1].defensive_pact = true
  after[1][0].defensive_pact = true
  t.assert_deep_equal({
    '{"civs":["Poland","Rome"],"event":"defensive_pact_signed","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = after },
  }))
end)

t.test("emits trade_agreement_signed once for the pair", function()
  local after = calm({ 0, 1 })
  after[0][1].trade_agreement = true
  after[1][0].trade_agreement = true
  t.assert_deep_equal({
    '{"civs":["Poland","Rome"],"event":"trade_agreement_signed","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = after },
  }))
end)

t.test("emits embassy_ended when the embassy is withdrawn", function()
  local before = calm({ 0, 1 })
  before[0][1].embassy = true
  t.assert_deep_equal({
    '{"civ":"Poland","event":"embassy_ended","other_civ":"Rome","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = before },
    { turn = 11, snapshot = calm({ 0, 1 }) },
  }))
end)

t.test("emits defensive_pact_ended when the pact lapses", function()
  local before = calm({ 0, 1 })
  before[0][1].defensive_pact = true
  before[1][0].defensive_pact = true
  t.assert_deep_equal({
    '{"civs":["Poland","Rome"],"event":"defensive_pact_ended","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = before },
    { turn = 11, snapshot = calm({ 0, 1 }) },
  }))
end)

t.test("emits trade_agreement_ended when the agreement lapses", function()
  local before = calm({ 0, 1 })
  before[0][1].trade_agreement = true
  before[1][0].trade_agreement = true
  t.assert_deep_equal({
    '{"civs":["Poland","Rome"],"event":"trade_agreement_ended","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = before },
    { turn = 11, snapshot = calm({ 0, 1 }) },
  }))
end)

-- PlayerDoTurn fires once per living player, but the pairwise state is
-- game-global, so the poll is gated on the turn like the congress poll.
t.test("polls once per turn, however many players take theirs", function()
  local lines, sink = captureSink()
  local state = { turn = 10, snapshot = calm({ 0, 1 }) }
  local poll = diplomacy.new(fakeCiv(state), sink)
  poll(0)
  local after = calm({ 0, 1 })
  after[0][1].dof, after[1][0].dof = true, true
  state.turn, state.snapshot = 11, after
  poll(0)
  poll(1)
  t.assert_equal(1, #lines)
end)

t.test("events come out in a deterministic order", function()
  local after = calm({ 0, 1, 2 })
  after[2][0].open_borders = true
  after[1][0].open_borders = true
  t.assert_deep_equal({
    '{"civ":"Rome","event":"open_borders_granted","other_civ":"Poland","turn":11}',
    '{"civ":"Egypt","event":"open_borders_granted","other_civ":"Poland","turn":11}',
  }, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1, 2 }) },
    { turn = 11, snapshot = after },
  }))
end)

t.test("a player leaving the snapshot is not a diplomatic event", function()
  t.assert_deep_equal({}, pollThrough({
    { turn = 10, snapshot = calm({ 0, 1 }) },
    { turn = 11, snapshot = calm({ 0 }) },
  }))
end)

t.test("a poll error is logged instead of raised", function()
  local lines, sink = captureSink()
  local civ = {
    turn = function() return 10 end,
    civName = function() return "Poland" end,
    diplomacySnapshot = function() error("boom") end,
  }
  diplomacy.new(civ, sink)(0)
  t.assert_match('"event":"logger_error"', lines[1])
end)
