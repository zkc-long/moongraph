// Write clause tests.

///|
fn wquery(g : @mg.Graph, text : String) -> QueryResult {
  run(g, text) catch {
    _ => {
      println("FAILED TO PARSE: " + text)
      abort("bad query")
    }
  }
}

///|
test "write/create-single-node" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "CREATE (n:Person {name: 'Ada'})"))
  assert_eq(g.alive_node_count(), 1)
  let result = wquery(g, "MATCH (p:Person) RETURN p.name AS name")
  assert_eq(result.rows[0][0].as_string(), "Ada")
}

///|
test "write/create-relationship" {
  let g = @mg.Graph::new()
  ignore(
    wquery(
      g, "CREATE (a:Person {name:'Ada'})-[:KNOWS]->(b:Person {name:'Bob'})",
    ),
  )
  assert_eq(g.alive_node_count(), 2)
  assert_eq(g.alive_edge_count(), 1)
  let result = wquery(
    g, "MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a.name AS a, b.name AS b",
  )
  assert_eq(result.rows[0][0].as_string(), "Ada")
  assert_eq(result.rows[0][1].as_string(), "Bob")
}

///|
test "write/create-between-bound-nodes" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "CREATE (a:Person {name:'Ada'})"))
  ignore(wquery(g, "CREATE (b:Person {name:'Bob'})"))
  ignore(
    wquery(
      g, "MATCH (a:Person {name:'Ada'}), (b:Person {name:'Bob'}) CREATE (a)-[:KNOWS]->(b)",
    ),
  )
  assert_eq(g.alive_edge_count(), 1)
}

///|
test "write/merge-creates-when-absent" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "MERGE (n:Person {name:'Ada'})"))
  assert_eq(g.alive_node_count(), 1)
}

///|
test "write/merge-matches-when-present" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "MERGE (n:Person {name:'Ada'})"))
  ignore(wquery(g, "MERGE (n:Person {name:'Ada'})"))
  assert_eq(g.alive_node_count(), 1)
}

///|
test "write/merge-binds-existing-node" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "CREATE (n:Person {name:'Ada', age: 36})"))
  let result = wquery(g, "MERGE (n:Person {name:'Ada'}) RETURN n.age AS age")
  assert_eq(result.rows[0][0].as_string(), "36")
}

///|
test "write/set-property" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "CREATE (n:Person {name:'Ada'})"))
  ignore(wquery(g, "MATCH (n:Person) SET n.age = 37"))
  let result = wquery(g, "MATCH (n:Person) RETURN n.age AS age")
  assert_eq(result.rows[0][0].as_string(), "37")
}

///|
test "write/set-indexed-property-is-queryable" {
  let g = @mg.Graph::new()
  ignore(wquery(g, "CREATE (n:Person {name:'Ada'})"))
  ignore(wquery(g, "MATCH (n:Person) SET n.city = 'Paris'"))
  let result = wquery(
    g, "MATCH (n:Person {city:'Paris'}) RETURN n.name AS name",
  )
  assert_eq(result.row_count(), 1)
}

///|
test "write/delete-node-removes-incident-edges" {
  let g = @mg.Graph::new()
  ignore(
    wquery(
      g, "CREATE (a:Person {name:'Ada'})-[:KNOWS]->(b:Person {name:'Bob'})",
    ),
  )
  ignore(wquery(g, "MATCH (n:Person {name:'Ada'}) DELETE n"))
  assert_eq(g.alive_node_count(), 1)
  assert_eq(g.alive_edge_count(), 0)
  let result = wquery(g, "MATCH (a)-[:KNOWS]->(b) RETURN a.name AS a")
  assert_eq(result.row_count(), 0)
}

///|
test "write/delete-edge" {
  let g = @mg.Graph::new()
  ignore(
    wquery(
      g, "CREATE (a:Person {name:'Ada'})-[r:KNOWS]->(b:Person {name:'Bob'})",
    ),
  )
  ignore(wquery(g, "MATCH (:Person)-[r:KNOWS]->(:Person) DELETE r"))
  assert_eq(g.alive_edge_count(), 0)
  assert_eq(g.alive_node_count(), 2)
}

///|
test "write/detach-delete-is-accepted" {
  let g = @mg.Graph::new()
  ignore(
    wquery(
      g, "CREATE (a:Person {name:'Ada'})-[:KNOWS]->(b:Person {name:'Bob'})",
    ),
  )
  ignore(wquery(g, "MATCH (n:Person {name:'Ada'}) DETACH DELETE n"))
  assert_eq(g.alive_node_count(), 1)
}

///|
test "write/query-without-return-has-no-columns" {
  let g = @mg.Graph::new()
  let result = wquery(g, "CREATE (n:Thing)")
  assert_eq(result.column_count(), 0)
  assert_eq(result.row_count(), 0)
}

///|
test "write/create-then-return" {
  let g = @mg.Graph::new()
  let result = wquery(g, "CREATE (n:Thing {v: 1}) RETURN n.v AS v")
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "1")
}
