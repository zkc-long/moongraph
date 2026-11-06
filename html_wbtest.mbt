// HTML export tests (root package, so types are unqualified).

///|
test "html/contains-structure" {
  let g = Graph::new()
  let a = g.add_node(["Person"], { "name": VStr("Ada") })
  let b = g.add_node(["Person"], { "name": VStr("Bob") })
  ignore(g.add_edge("KNOWS", a, b, Map([])) catch { _ => -1 })
  let html = to_html(g, "demo")
  assert_true(html.contains("<!doctype html>"))
  assert_true(html.contains("<svg id=\"g\">"))
  assert_true(html.contains("\"nodes\":["))
  assert_true(html.contains("\"Ada\""))
  assert_true(html.contains("\"type\":\"KNOWS\""))
}

///|
test "html/escapes-title" {
  let g = Graph::new()
  let html = to_html(g, "a \"quoted\" title")
  assert_true(html.contains("a \\\"quoted\\\" title"))
}

///|
test "html/renders-node-labels" {
  let g = Graph::new()
  ignore(g.add_node(["X"], { "name": VStr("only") }))
  let html = to_html(g, "t")
  assert_true(html.contains("\"label\":\"only\""))
  assert_true(html.contains("nodes \u00b7"))
}
