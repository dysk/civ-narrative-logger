-- Emits building_granted when a city acquires a building nobody built.
-- The DLL hands out free buildings without firing CityConstructed:
-- CvCity.cpp:7391 takes the FreeBuildingThisCity path straight to
-- SetNumFreeBuilding, well clear of the three hook call sites, and the
-- trait and policy grants at CvCity.cpp:486 and 525 do the same. Angkor
-- Wat's University, Hagia Sophia's Temple and Carthage's harbours have
-- therefore always been invisible to the log. Polled and diffed like
-- src/census.lua, for the same reason: nothing pushes them.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "PlayerDoTurn (free_buildings)", error = tostring(err) }
end

local function setOf(list)
  local set = {}
  for _, item in ipairs(list) do set[item] = true end
  return set
end

function M.new(civ, sink)
  local known, candidates, everything = {}, nil, nil

  local function announce(turn)
    local classes
    candidates, classes = civ.grantableBuildings()
    everything = civ.allBuildings()
    sink(json.encode({
      event = "free_buildings_ready",
      turn = turn,
      buildings = #candidates,
      all_buildings = #everything,
      classes = classes,
    }))
  end

  -- Nothing stands in the opening turns, so a fresh game has nothing to
  -- seed from and everything to report. A session resumed from a save
  -- starts with a Lua state that knows nothing, and reporting there would
  -- date every free building in the empire to the turn of the reload.
  local function seeding(playerId, turn)
    return known[playerId] == nil and turn > 1
  end

  -- City ids come back from a free list, so an id alone does not say the
  -- city is the one we saw last turn. Nothing means we have never looked
  -- at this city.
  local function heldLastTurn(playerId, city)
    local previous = (known[playerId] or {})[city.id]
    if previous and previous.name == city.name then return previous.buildings end
  end

  -- A captured city keeps the founding turn of whoever founded it
  -- (CvPlayer.cpp:2851), so the two turns agree only for a city this
  -- player founded. A city founded during the last turn is first seen now.
  local function foundedSincePoll(city, turn)
    return city.founded == city.acquired and city.founded >= turn - 1
  end

  local function grant(turn, name, city, building, source)
    sink(json.encode({
      event = "building_granted", turn = turn, civ = name,
      city = city, building = building, source = source,
    }))
  end

  -- A city founded since the last poll was built by nobody, so everything
  -- standing in it was handed over - including the real buildings mod
  -- scripts add through SetNumRealBuildingClass, which fire no hook and
  -- never show up as free. Every other city is a diff, and a city first
  -- seen without having just been founded is somebody else's work.
  local function report(playerId, city, turn, name)
    local before = heldLastTurn(playerId, city)
    if before then
      for _, building in ipairs(city.buildings) do
        if not before[building] then grant(turn, name, city.name, building, "diff") end
      end
    elseif foundedSincePoll(city, turn) then
      for _, building in ipairs(civ.cityBuildings(playerId, city.id, everything)) do
        grant(turn, name, city.name, building, "new_city")
      end
    end
  end

  local function poll(playerId)
    local turn, name = civ.turn(), civ.civName(playerId)
    if not candidates then announce(turn) end
    local silent, current = seeding(playerId, turn), {}

    for _, city in ipairs(civ.freeBuildings(playerId, candidates)) do
      if not silent then report(playerId, city, turn, name) end
      current[city.id] = { name = city.name, buildings = setOf(city.buildings) }
    end
    known[playerId] = current
  end

  return function(playerId)
    local ok, err = pcall(poll, playerId)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
