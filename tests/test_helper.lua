local M = { tests = {}, failures = 0 }

function M.test(name, fn)
  table.insert(M.tests, { name = name, fn = fn })
end

function M.load_failure(module_name, err)
  M.test(module_name .. " (load)", function() error(err, 0) end)
end

local function repr(value)
  if type(value) == "string" then return string.format("%q", value) end
  if type(value) ~= "table" then return tostring(value) end
  local parts = {}
  for k, v in pairs(value) do
    table.insert(parts, tostring(k) .. " = " .. repr(v))
  end
  table.sort(parts)
  return "{ " .. table.concat(parts, ", ") .. " }"
end

local function deep_equal(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    if not deep_equal(v, b[k]) then return false end
  end
  for k in pairs(b) do
    if a[k] == nil then return false end
  end
  return true
end

local function fail(expected, actual)
  error("expected " .. repr(expected) .. "\n      got      " .. repr(actual), 3)
end

function M.assert_equal(expected, actual)
  if expected ~= actual then fail(expected, actual) end
end

function M.assert_deep_equal(expected, actual)
  if not deep_equal(expected, actual) then fail(expected, actual) end
end

function M.assert_nil(actual)
  if actual ~= nil then fail(nil, actual) end
end

function M.run()
  for _, t in ipairs(M.tests) do
    local ok, err = pcall(t.fn)
    if ok then
      print("PASS  " .. t.name)
    else
      M.failures = M.failures + 1
      print("FAIL  " .. t.name .. "\n      " .. tostring(err))
    end
  end
  print(string.format("\n%d tests, %d failures", #M.tests, M.failures))
  os.exit(M.failures == 0 and 0 or 1)
end

return M
