// WITH clause tests.

///|
fn wq(g : @mg.Graph, text : String) -> QueryResult {
  run(g, text) catch {
    _ => {
      println("FAILED TO PARSE: " + text)
      abort("bad query")
    }
  }
}

///|
test "with/projects-and-renames" {
  let result = wq(
    fixture(),
    "MATCH (p:Person) WITH p.name AS name, p.age AS age WHERE age > 30 RETURN name, age ORDER BY name",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Ada")
  assert_eq(result.columns, ["name", "age"])
}

///|
test "with/aggregate-then-filter" {
  let result = wq(
    fixture(),
    "MATCH (p:Person)-[:WORKS_AT]->(c:Company) WITH c, count(p) AS staff WHERE staff > 1 RETURN c.name AS company, staff",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Acme")
  assert_eq(result.rows[0][1].as_string(), "2")
}

///|
test "with/global-aggregate" {
  let result = wq(
    fixture(),
    "MATCH (p:Person) WITH count(p) AS people RETURN people",
  )
  assert_eq(result.rows[0][0].as_string(), "3")
}

///|
test "with/carries-node-then-matches" {
  let result = wq(
    fixture(),
    "MATCH (p:Person) WITH p WHERE p.age > 35 MATCH (p)-[:KNOWS]->(f) RETURN p.name AS a, f.name AS b ORDER BY a",
  )
  assert_eq(result.row_count(), 2)
  assert_eq(result.rows[0][0].as_string(), "Ada")
  assert_eq(result.rows[1][0].as_string(), "Bob")
}

///|
test "with/drops-unmentioned-variables" {
  // `f` is out of scope after WITH, so the post-MATCH introduces it fresh;
  // `a` was dropped and must not leak into the projection.
  let result = wq(
    fixture(),
    "MATCH (a:Person)-[:KNOWS]->(b:Person) WITH b MATCH (b)-[:WORKS_AT]->(c) RETURN b.name AS name, c.name AS company ORDER BY name",
  )
  assert_eq(result.row_count(), 1)
  assert_eq(result.rows[0][0].as_string(), "Bob")
}

///|
test "with/distinct" {
  let result = wq(
    fixture(),
    "MATCH (p:Person)-[:WORKS_AT]->(c:Company) WITH DISTINCT c RETURN c.name AS company",
  )
  assert_eq(result.row_count(), 1)
}

///|
test "with/scalar-sum-over-with" {
  // sum over a carried node's property, grouped by label value
  let result = wq(
    fixture(),
    "MATCH (p:Person) WITH p.age AS age RETURN sum(age) AS total",
  )
  assert_eq(result.rows[0][0].as_string(), "106")
}
