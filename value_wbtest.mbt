// Tests for the property value model.

///|
test "value/null-and-numbers" {
  assert_true(VNull.is_null())
  assert_true(!VInt(1L).is_null())
  assert_true(VInt(3L).is_number())
  assert_true(VDouble(2.5).is_number())
  assert_true(!VStr("x").is_number())
}

///|
test "value/numeric-comparison-is-mixed" {
  // ints and doubles compare numerically even though their variants differ
  assert_eq(VInt(2L).compare(VDouble(2.0)), 0)
  assert_eq(VInt(2L).compare(VDouble(2.5)), -1)
  assert_eq(VDouble(3.5).compare(VInt(3L)), 1)
}

///|
test "value/type-ordering" {
  // null < bool < number < string < list
  assert_true(VNull.compare(VBool(false)) < 0)
  assert_true(VBool(true).compare(VInt(0L)) < 0)
  assert_true(VInt(999L).compare(VStr("")) < 0)
  assert_true(VStr("zzz").compare(VList([])) < 0)
}

///|
test "value/string-ordering" {
  assert_true(VStr("a").compare(VStr("b")) < 0)
  assert_eq(VStr("same").compare(VStr("same")), 0)
  assert_true(VStr("b").compare(VStr("a")) > 0)
}

///|
test "value/list-ordering-is-lexicographic" {
  let a : Value = VList([VInt(1L), VInt(2L)])
  let b : Value = VList([VInt(1L), VInt(3L)])
  assert_true(a.compare(b) < 0)
  let short : Value = VList([VInt(1L)])
  assert_true(short.compare(a) < 0)
}

///|
test "value/display" {
  assert_eq(VNull.to_display(), "null")
  assert_eq(VInt(42L).to_display(), "42")
  assert_eq(VStr("plain").to_display(), "plain")
  assert_eq(VList([VInt(1L), VStr("x")]).to_display(), "[1, x]")
}

///|
test "value/literal-quotes-strings" {
  assert_eq(VStr("a\"b").to_literal(), "\"a\\\"b\"")
  assert_eq(VInt(7L).to_literal(), "7")
}

///|
test "value/equal-value-uses-numeric-equality" {
  assert_true(VInt(4L).equal_value(VDouble(4.0)))
  assert_true(!VInt(4L).equal_value(VStr("4")))
}
