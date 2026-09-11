-- Polls every major's spies and diffs them into events. Espionage fires
-- no hook at all - CvEspionageClasses.cpp calls LuaSupport::Call not
-- once - so nothing here is pushed and all of it is read.
--
-- The state cycle a spy runs after being posted is fixed by where it was
-- sent: travelling, surveillance, then gathering intel in a foreign
-- city, rigging elections in a city-state, or counter-intelligence at
-- home. Logging each of those turns would be four fifths of the records
-- to say what the destination already says, so the posting is written
-- and the cycle is not. The one turn in the cycle worth a record is when
-- surveillance goes true: from then on the spy's owner can see the city.
--
-- A session that resumes a game already under way has nothing to diff
-- against, so its first poll announces every spy it can see as a located
-- spy_created. Anything else swallows whatever was created or posted
-- inside the reload seam: two sessions of Run B produced none at all.
-- The agent id is stable for the whole game, so the analyst deduplicates
-- a spy it has already been told about.
--
-- Registered on PlayerDoTurn like the other stateful pollers and gated
-- on the turn: the whole board is read at once while PlayerDoTurn fires
-- once per living player.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (spies)", error = tostring(err) }
end

-- pairs() order is undefined, and the log is compared line by line.
local function sortedKeys(t)
  local keys = {}
  for key in pairs(t) do table.insert(keys, key) end
  table.sort(keys)
  return keys
end

-- Every record carries the agent id as well as the name, because the
-- DLL renames a spy when it revives it and the name alone would break a
-- career in half at exactly the death worth reading about.
local function record(event, turn, spy, extra)
  local out = { event = event, turn = turn, civ = spy.civ,
                agent = spy.agent, spy = spy.spy }
  for field, value in pairs(extra or {}) do out[field] = value end
  return out
end

local function at(spy)
  return { city = spy.city, city_civ = spy.city_civ }
end

local function posting(spy)
  return { city = spy.city, city_civ = spy.city_civ,
           x = spy.x, y = spy.y, state = spy.state }
end

local function completion(spy)
  return { city = spy.city, city_civ = spy.city_civ, state = spy.state }
end

local function moved(known, spy)
  return spy.x ~= nil and (known.x ~= spy.x or known.y ~= spy.y)
end

-- A counterspy sits in one of its owner's own cities and its progress is
-- always nil, so a completed mission can never surface it: spy_moved is
-- the only event it produces. When it was posted home to coordinates
-- that did not change, the move check misses it, and the transition into
-- counter_intel is the posting instead.
local function becameCounterspy(known, spy)
  return spy.state == "counter_intel" and known.state ~= "counter_intel"
    and spy.city ~= nil
end

-- A finished mission neither moves the spy nor changes its state: the
-- DLL resets the progress and sets the same activity going again
-- (CvEspionageClasses.cpp:807-810 for a stolen tech, :900-903 for a
-- rigged election). Progress otherwise only climbs, so a fall in place
-- is the completion. A fall that comes with a move is the new posting,
-- and a fall that comes with a state change is only the shared
-- travelling/surveillance/gathering-intel counter restarting.
local function completed(known, spy)
  return known.progress ~= nil and spy.progress ~= nil
    and known.state == spy.state
    and spy.progress < known.progress
end

local function diffSpy(sink, turn, known, spy)
  if known.state == "dead" then
    if spy.state ~= "dead" then
      sink(json.encode(record("spy_revived", turn, spy)))
      -- A revived spy is a fresh recruit with no prior position, so any
      -- city it already sits in is a new posting nothing else would see.
      -- The dead record it is diffed against carries no rank or progress
      -- worth trusting, so only the posting is read from it.
      if spy.x ~= nil then
        sink(json.encode(record("spy_moved", turn, spy, posting(spy))))
      end
    end
    return
  end
  if spy.state == "dead" then
    -- The DLL empties the location before setting SPY_STATE_DEAD, so the
    -- death site is the city the spy held on the last live poll.
    sink(json.encode(record("spy_killed", turn, spy, at(known))))
    return
  end
  if known.rank ~= spy.rank then
    sink(json.encode(record("spy_promoted", turn, spy, { rank = spy.rank })))
  end
  if moved(known, spy) or becameCounterspy(known, spy) then
    sink(json.encode(record("spy_moved", turn, spy, posting(spy))))
  elseif completed(known, spy) then
    sink(json.encode(record("spy_mission_completed", turn, spy, completion(spy))))
  end
  if not known.surveillance and spy.surveillance then
    sink(json.encode(record("spy_surveillance_established", turn, spy, at(spy))))
  end
end

local function diff(sink, turn, known, spies)
  for _, key in ipairs(sortedKeys(spies)) do
    if known[key] then
      diffSpy(sink, turn, known[key], spies[key])
    else
      sink(json.encode(record("spy_created", turn, spies[key], at(spies[key]))))
    end
  end
end

function M.new(civ, sink)
  local state = { turn = nil, spies = nil }

  local function poll()
    local turn = civ.turn()
    if turn == state.turn then return end
    state.turn = turn

    local spies = civ.spies()
    diff(sink, turn, state.spies or {}, spies)
    state.spies = spies
  end

  return function()
    local ok, err = pcall(poll)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
