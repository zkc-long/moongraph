// Execution tests over a small fixture graph.

///|
fn fixture() -> @mg.Graph {
  let g = @mg.Graph::new()
  let props = fn(pairs : Array[(String, @mg.Value)]) {
    let m : Map[String, @mg.Value] = Map([])
    for (k, v) in pairs {
      m[k] = v
    }
    m
  }
  let ada = g.add_node(["Person"], props([("name", @mg.VStr("Ada")), ("age", @mg.VInt(36L))]))
  let bob = g.add_node(["Person"], props([("name", @mg.VStr("Bob")), ("age", @mg.VInt(41L))]))
  let cy = g.add_node(["Person"], props([("name", @mg.VStr("Cy")), ("age", @mg.VInt(29L))]))
  let acme = g.add_node(["Company"], props([("name", @mg.VStr("Acme"))]))
  ignore(g.add_edge("KNOWS", ada, bob, props([])) catch { _ => -1 })
  ignore(g.add_edge("KNOWS", bob, cy, props([])) catch { _ => -1 })
  ignore(g.add_edge("WORKS_AT", ada, acme, props([])) catch { _ => -1 })
  ignore(g.add_edge("WORKS_AT", bob, acme, props([])) catch { _ => -1 })
  g
}

///|
fn query(g : @mg.Graph, text : String) -> QueryResult {
  run(g, text) catch {
    _ => {
      println("FAILED TO PARSE: " + text)
      abort("query failed to parse")
    }
  }
}

///|
test "exec/scan-by-label" {
  let result = query(fixture(), "MATCH (p:Person) RETURN p.name AS name")
  assert_eq(result.row_count(), 3)
  assert_eq(result.columns, ["name"])
  assert_eq(result.rows[0][0].as_string(), "Ada")
}

///|
test "exec/property-filter-in-pattern" {
  let result = query(fixture(), "MATCH (p:Person {name:'Bob'}) RETURN p.age AS age")
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "41")
}

///|
test "exec/single-hop-outgoing" {
  let result = query(
    fixture(),
    "MATCH (a:Person)-[:KNOWS]->(b:Person) RETURN a.name AS a, b.name AS b",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Ada")
  assert_eq(result.rows[0][1].as_string(), "Bob")
}

///|
test "exec/undirected-hop" {
  let result = query(
    fixture(),
    "MATCH (a:Person {name:'Bob'})-[:KNOWS]-(b:Person) RETURN b.name AS name ORDER BY name",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Ada")
  assert_eq(result.rows[1][0].as_string(), "Cy")
}

///|
test "exec/incoming-hop" {
  let result = query(
    fixture(),
    "MATCH (a:Person)<-[:KNOWS]-(b:Person) RETURN b.name AS src ORDER BY src",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Ada")
}

///|
test "exec/two-hop-chain" {
  let result = query(
    fixture(),
    "MATCH (a:Person {name:'Ada'})-[:KNOWS]->(b)-[:KNOWS]->(c) RETURN c.name AS name",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Cy")
}

///|
test "exec/variable-length" {
  let result = query(
    fixture(),
    "MATCH (a:Person {name:'Ada'})-[:KNOWS*1..2]->(b) RETURN b.name AS name ORDER BY name",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Bob")
  assert_eq(result.rows[1][0].as_string(), "Cy")
}

///|
test "exec/variable-length-unbounded" {
  let result = query(
    fixture(),
    "MATCH (a:Person {name:'Ada'})-[:KNOWS*]->(b) RETURN count(b) AS reachable",
  )
  assert_eq(result.rows[0][0].as_string(), "2")
}

///|
test "exec/where-numeric-and-string" {
  let result = query(
    fixture(),
    "MATCH (p:Person) WHERE p.age > 30 AND p.name STARTS WITH 'A' RETURN p.name AS n",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Ada")
}

///|
test "exec/where-in-list" {
  let result = query(
    fixture(),
    "MATCH (p:Person) WHERE p.name IN ['Ada','Cy'] RETURN count(p) AS c",
  )
  assert_eq(result.rows[0][0].as_string(), "2")
}

///|
test "exec/where-is-null" {
  let result = query(
    fixture(),
    "MATCH (p:Person) WHERE p.nickname IS NULL RETURN count(p) AS c",
  )
  assert_eq(result.rows[0][0].as_string(), "3")
}

///|
test "exec/comparison-with-null-is-null" {
  // null comparisons must not satisfy WHERE
  let result = query(
    fixture(),
    "MATCH (p:Person) WHERE p.nickname = 'x' RETURN count(p) AS c",
  )
  assert_eq(result.rows[0][0].as_string(), "0")
}

///|
test "exec/aggregates" {
  let result = query(
    fixture(),
    "MATCH (p:Person) RETURN count(p) AS c, sum(p.age) AS s, min(p.age) AS lo, max(p.age) AS hi",
  )
  assert_eq(result.rows[0][0].as_string(), "3")
  assert_eq(result.rows[0][1].as_string(), "106")
  assert_eq(result.rows[0][2].as_string(), "29")
  assert_eq(result.rows[0][3].as_string(), "41")
}

///|
test "exec/avg-and-collect" {
  let result = query(fixture(), "MATCH (p:Person) RETURN avg(p.age) AS a")
  assert_eq(result.rows[0][0].as_string(), "35.333333333333336")
  let collected = query(
    fixture(),
    "MATCH (p:Person) RETURN collect(p.name) AS names",
  )
  assert_eq(collected.rows[0][0].to_display(), "[Ada, Bob, Cy]")
}

///|
test "exec/group-by" {
  let result = query(
    fixture(),
    "MATCH (p:Person)-[:WORKS_AT]->(c:Company) RETURN c.name AS company, count(p) AS staff",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Acme")
  assert_eq(result.rows[0][1].as_string(), "2")
}

///|
test "exec/order-by-desc-and-limit" {
  let result = query(
    fixture(),
    "MATCH (p:Person) RETURN p.name AS n ORDER BY n DESC LIMIT 2",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Cy")
  assert_eq(result.rows[1][0].as_string(), "Bob")
}

///|
test "exec/order-by-numeric" {
  let result = query(
    fixture(),
    "MATCH (p:Person) RETURN p.name AS n ORDER BY p.age DESC",
  )
  assert_eq(result.rows[0][0].as_string(), "Bob")
  assert_eq(result.rows[1][0].as_string(), "Ada")
  assert_eq(result.rows[2][0].as_string(), "Cy")
}

///|
test "exec/skip" {
  let result = query(
    fixture(),
    "MATCH (p:Person) RETURN p.name AS n ORDER BY n SKIP 1 LIMIT 1",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Bob")
}

///|
test "exec/distinct" {
  let result = query(
    fixture(),
    "MATCH (p:Person)-[:WORKS_AT]->(c:Company) RETURN DISTINCT c.name AS company",
  )
  assert_eq(result.row_count(), 1)
}

///|
test "exec/arithmetic-and-concat" {
  let result = query(
    fixture(),
    "MATCH (p:Person {name:'Ada'}) RETURN p.age + 1 AS next, p.name + '!' AS shout",
  )
  assert_eq(result.rows[0][0].as_string(), "37")
  assert_eq(result.rows[0][1].as_string(), "Ada!")
}

///|
test "exec/functions" {
  let result = query(
    fixture(),
    "MATCH (p:Person {name:'Ada'}) RETURN size(p.name) AS len, toUpper(p.name) AS up, coalesce(p.nick, p.name) AS pick",
  )
  assert_eq(result.rows[0][0].as_string(), "3")
  assert_eq(result.rows[0][1].as_string(), "ADA")
  assert_eq(result.rows[0][2].as_string(), "Ada")
}

///|
test "exec/to-table" {
  let result = query(fixture(), "MATCH (p:Person {name:'Cy'}) RETURN p.name AS name")
  let table = result.to_table()
  assert_true(table.contains("name"))
  assert_true(table.contains("Cy"))
  assert_true(table.contains("1 row(s)"))
}

///|
test "exec/to-json" {
  let result = query(fixture(), "MATCH (p:Person {name:'Cy'}) RETURN p.name AS name")
  assert_eq(result.to_json(), "{\"columns\":[\"name\"],\"rows\":[[\"Cy\"]]}")
}

///|
test "exec/empty-result" {
  let result = query(fixture(), "MATCH (p:Person {name:'Nobody'}) RETURN p.name AS n")
  assert_eq(result.row_count(), 0)
  assert_eq(result.columns, ["n"])
}
