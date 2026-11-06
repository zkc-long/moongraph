// Path value tests.

///|
test "path/binds-canonical-text" {
  let g = fixture()
  let result = wq(
    g, "MATCH p = (a:Person {name:'Ada'})-[:KNOWS]->(b) RETURN p, length(p) AS hops",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][1].as_string(), "1")
  let text = result.rows[0][0].as_string()
  assert_true(text.contains("(:Person {age: 36, name: 'Ada'})"))
  assert_true(text.contains("-[:KNOWS]->"))
}

///|
test "path/variable-length-length" {
  let g = fixture()
  let result = wq(
    g, "MATCH p = (a:Person {name:'Ada'})-[:KNOWS*1..2]->(b) RETURN length(p) AS hops ORDER BY hops",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "1")
  assert_eq(result.rows[1][0].as_string(), "2")
}

///|
test "path/shortestPath-pattern-picks-shortest" {
  let g = fixture()
  let result = wq(
    g, "MATCH (a:Person {name:'Ada'}), (c:Person {name:'Cy'}), p = shortestPath((a)-[:KNOWS*1..5]->(c)) RETURN length(p) AS hops",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "2")
}

///|
test "path/shortestPath-canonical-text" {
  let g = fixture()
  let result = wq(
    g, "MATCH (a:Person {name:'Ada'}), (c:Person {name:'Cy'}), p = shortestPath((a)-[:KNOWS*1..5]->(c)) RETURN p",
  )
  let text = result.rows[0][0].as_string()
  assert_true(text.contains("-[:KNOWS]->"))
  assert_true(text.contains("'Bob'"))
}

///|
test "path/unreachable-shortestPath-returns-no-row" {
  let g = @mg.Graph::new()
  let a = g.add_node(["N"], Map([]))
  let b = g.add_node(["N"], Map([]))
  ignore(g.add_edge("R", a, b, Map([])) catch { _ => -1 })
  // `a` and `b` are connected; ask for a type that does not exist
  let result = wq(
    g, "MATCH (x:N), (y:N), p = shortestPath((x)-[:MISSING*1..3]->(y)) RETURN p",
  )
  assert_eq(result.row_count(), 0)
  assert_eq(a, 0)
  assert_eq(b, 1)
}

///|
test "path/path-variable-in-where" {
  let g = fixture()
  let result = wq(
    g, "MATCH p = (a:Person {name:'Ada'})-[:KNOWS*1..2]->(b) WHERE length(p) = 2 RETURN b.name AS name",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Cy")
}
