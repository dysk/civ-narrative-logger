-- The test modules, in load order. Shared by the runner and by the
-- event-type generator, which exercises the same suite to see which
-- records the logger can write.
local FILES = {
  "tests.json_test",
  "tests.extractors_test",
  "tests.logger_test",
  "tests.adapter_test",
  "tests.census_test",
  "tests.cities_test",
  "tests.free_buildings_test",
  "tests.roster_test",
  "tests.congress_test",
  "tests.victory_test",
  "tests.diplomacy_test",
  "tests.city_states_test",
  "tests.trade_routes_test",
  "tests.spies_test",
  "tests.main_test",
  "tests.build_test",
  "tests.parser_test",
  "tests.event_types_test",
}

local M = {}

function M.load(t)
  for _, file in ipairs(FILES) do
    local ok, err = pcall(require, file)
    if not ok then t.load_failure(file, err) end
  end
end

return M
