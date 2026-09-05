package.path = "./?.lua;" .. package.path
local t = require("tests.test_helper")

local files = {
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
  "tests.main_test",
  "tests.build_test",
  "tests.parser_test",
}

for _, file in ipairs(files) do
  local ok, err = pcall(require, file)
  if not ok then t.load_failure(file, err) end
end

t.run()
