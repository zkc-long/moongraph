// Tests for the JSON reader/writer.

///|
test "json/parse-scalars" {
  assert_true(Json::parse("null") is JNull)
  assert_true(Json::parse("true") is JBool(true))
  assert_true(Json::parse("123") is JInt(123L))
  assert_true(Json::parse("-4.5") is JDouble(-4.5))
  assert_true(Json::parse("\"hi\"") is JStr("hi"))
}

///|
test "json/parse-nested" {
  let json = Json::parse("{\"a\":[1,2,{\"b\":null}],\"c\":true}")
  match json {
    JObj(map) => {
      assert_eq(map.length(), 2)
      match map["a"] {
        JList(items) => {
          assert_eq(items.length(), 3)
          assert_true(items[2] is JObj(_))
        }
        _ => fail("a should be a list")
      }
    }
    _ => fail("root should be an object")
  }
}

///|
test "json/parse-escapes" {
  match Json::parse("\"line\\nbreak\\t\\\"q\\\"\"") {
    JStr(s) => assert_eq(s, "line\nbreak\t\"q\"")
    _ => fail("expected string")
  }
}

///|
test "json/parse-unicode-escape" {
  match Json::parse("\"\\u0041\\u0042\"") {
    JStr(s) => assert_eq(s, "AB")
    _ => fail("expected string")
  }
}

///|
test "json/reject-trailing-garbage" {
  let ok = try {
    ignore(Json::parse("1 2"))
    true
  } catch {
    JsonError::JsonUnexpected(_, _) => false
    _ => false
  }
  assert_true(!ok)
}

///|
test "json/reject-unterminated" {
  let ok = try {
    ignore(Json::parse("{\"a\":1"))
    true
  } catch {
    _ => false
  }
  assert_true(!ok)
}

///|
test "json/roundtrip" {
  let src = "{\"name\":\"moon\",\"n\":3,\"ok\":true,\"xs\":[1,2]}"
  let printed = Json::parse(src).to_string()
  let reparsed = Json::parse(printed).to_string()
  assert_eq(printed, reparsed)
}

///|
test "json/escape-string" {
  assert_eq(escape_json_string("a\"b\\c"), "a\\\"b\\\\c")
  assert_eq(escape_json_string("\n"), "\\n")
}

///|
test "json/to-value" {
  assert_true(json_to_value(JNull) is VNull)
  assert_true(json_to_value(JInt(5L)) is VInt(5L))
  assert_true(json_to_value(JStr("x")) is VStr("x"))
  assert_true(json_to_value(JList([JInt(1L)])) is VList(_))
}

///|
test "json/value-roundtrip" {
  let v : Value = VList([VInt(1L), VStr("a"), VBool(false), VNull])
  let back = json_to_value(value_to_json(v))
  assert_true(v.equal_value(back))
}
