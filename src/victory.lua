-- Announces the end of the game exactly once. A per-turn poll cannot:
-- the game stops on the turn it is decided, so the last PlayerDoTurn
-- never comes. GameCoreTestVictory does, because CvGame::testVictory
-- fires it above its own "already decided" guard (CvGame.cpp:9943), and
-- keeps firing on player death, team change and concluded Congress
-- votes afterwards - hence the one-shot flag. The DLL calls this hook
-- "to allow a Lua script to set the victory state", so the handler
-- returns nothing: reading is safe, answering would not be.
local json = require("src.json")

local M = {}

local function errorRecord(err)
  return { event = "logger_error", hook = "GameCoreTestVictory", error = tostring(err) }
end

function M.new(civ, sink)
  local announced = false

  local function watch()
    if announced then return end
    local result = civ.victory()
    if not result then return end
    announced = true
    sink(json.encode({
      event = "game_ended",
      turn = civ.turn(),
      winner_team = result.winner_team,
      winner_civs = result.winner_civs,
      victory = result.victory,
      winning_turn = result.winning_turn,
    }))
  end

  return function()
    local ok, err = pcall(watch)
    if not ok then sink(json.encode(errorRecord(err))) end
  end
end

return M
