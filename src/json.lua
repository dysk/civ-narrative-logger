local M = {}

local ESCAPES = {
  ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f",
  ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t",
}

local function encodeString(s)
  local escaped = s:gsub('[%z\1-\31\\"]', function(c)
    return ESCAPES[c] or string.format("\\u%04x", c:byte())
  end)
  return '"' .. escaped .. '"'
end

local function sortedKeys(t)
  local keys = {}
  for k in pairs(t) do table.insert(keys, k) end
  table.sort(keys)
  return keys
end

local function encodeTable(t)
  local parts = {}
  if #t > 0 then
    for _, v in ipairs(t) do table.insert(parts, M.encode(v)) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  for _, k in ipairs(sortedKeys(t)) do
    table.insert(parts, encodeString(tostring(k)) .. ":" .. M.encode(t[k]))
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function M.encode(value)
  local kind = type(value)
  if kind == "string" then return encodeString(value) end
  if kind == "number" then return string.format("%.14g", value) end
  if kind == "boolean" then return tostring(value) end
  if kind == "table" then return encodeTable(value) end
  if kind == "nil" then return "null" end
  error("cannot encode a " .. kind)
end

return M
