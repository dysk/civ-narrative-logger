local t = require("tests.test_helper")
local json = require("src.json")

t.test("json encodes strings with escaping", function()
  t.assert_equal('"he said \\"hi\\"\\n"', json.encode('he said "hi"\n'))
end)

t.test("json encodes integers without decimal point", function()
  t.assert_equal("42", json.encode(42))
end)

t.test("json encodes booleans", function()
  t.assert_equal("true", json.encode(true))
end)

t.test("json encodes objects with sorted keys", function()
  t.assert_equal('{"a":"x","b":1}', json.encode({ b = 1, a = "x" }))
end)

t.test("json encodes arrays", function()
  t.assert_equal("[1,2,3]", json.encode({ 1, 2, 3 }))
end)

t.test("json encodes nested tables", function()
  t.assert_equal('{"civs":["Poland","Rome"],"team":1}',
    json.encode({ civs = { "Poland", "Rome" }, team = 1 }))
end)

t.test("json encodes empty table as object", function()
  t.assert_equal("{}", json.encode({}))
end)
