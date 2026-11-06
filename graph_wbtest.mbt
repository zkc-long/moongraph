// Tests for graph storage, adjacency and secondary indexes.

///|
fn props(pairs : Array[(String, Value)]) -> Map[String, Value] {
  let m : Map[String, Value] = Map([])
  for pair in pairs {
    m[pair.0] = pair.1
  }
  m
}

///|
test "graph/add-node-assigns-dense-ids" {
  let g = Graph::new()
  let a = g.add_node(["Person"], props([("name", VStr("ada"))]))
  let b = g.add_node(["Person"], props([("name", VStr("bob"))]))
  assert_eq(a, 0)
  assert_eq(b, 1)
  assert_eq(g.node_count(), 2)
  assert_eq(g.node(a).prop("name").as_string(), "ada")
}

///|
test "graph/label-index" {
  let g = Graph::new()
  ignore(g.add_node(["Person"], props([])))
  ignore(g.add_node(["Package"], props([])))
  ignore(g.add_node(["Person"], props([])))
  assert_eq(g.nodes_with_label("Person").length(), 2)
  assert_eq(g.nodes_with_label("Package").length(), 1)
  assert_eq(g.nodes_with_label("Nope").length(), 0)
}

///|
test "graph/property-index" {
  let g = Graph::new()
  ignore(g.add_node(["Person"], props([("name", VStr("ada"))])))
  ignore(g.add_node(["Person"], props([("name", VStr("bob"))])))
  match g.lookup_property("name", VStr("bob")) {
    Some(ids) => {
      assert_eq(ids.length(), 1)
      assert_eq(ids[0], 1)
    }
    None => fail("index should answer this lookup")
  }
  match g.lookup_property("name", VStr("nobody")) {
    Some(ids) => assert_eq(ids.length(), 0)
    None => fail("index should answer miss as empty")
  }
  // unknown key: no index, caller must scan
  assert_true(g.lookup_property("age", VInt(3L)) is None)
}

///|
test "graph/adjacency-is-directed" {
  let g = Graph::new()
  let a = g.add_node(["N"], props([]))
  let b = g.add_node(["N"], props([]))
  let e = g.add_edge("KNOWS", a, b, props([])) catch { _ => -1 }
  assert_eq(e, 0)
  assert_eq(g.out_neighbors(a).length(), 1)
  assert_eq(g.in_neighbors(a).length(), 0)
  assert_eq(g.out_neighbors(b).length(), 0)
  assert_eq(g.in_neighbors(b).length(), 1)
  assert_eq(g.out_neighbors(a)[0].0, b)
}

///|
test "graph/edge-endpoints-must-exist" {
  let g = Graph::new()
  ignore(g.add_node(["N"], props([])))
  let ok = try {
    ignore(g.add_edge("R", 0, 5, props([])))
    true
  } catch {
    GraphError::EdgeNodeMissing(_) => false
  }
  assert_true(!ok)
}

///|
test "graph/labels-are-sorted-and-distinct" {
  let g = Graph::new()
  ignore(g.add_node(["B"], props([])))
  ignore(g.add_node(["A"], props([])))
  ignore(g.add_node(["A"], props([])))
  assert_eq(g.labels(), ["A", "B"])
}

///|
test "graph/edge-types-distinct" {
  let g = Graph::new()
  let a = g.add_node(["N"], props([]))
  let b = g.add_node(["N"], props([]))
  ignore(g.add_edge("X", a, b, props([])) catch { _ => -1 })
  ignore(g.add_edge("X", b, a, props([])) catch { _ => -1 })
  ignore(g.add_edge("Y", a, a, props([])) catch { _ => -1 })
  assert_eq(g.edge_types(), ["X", "Y"])
}
