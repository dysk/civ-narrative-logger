package.path = "./?.lua;" .. package.path
local t = require("tests.test_helper")

local files = {
  "tests.json_test",
  "tests.extractors_test",
  "tests.logger_test",
}

for _, file in ipairs(files) do
  local ok, err = pcall(require, file)
  if not ok then t.load_failure(file, err) end
end

t.run()
