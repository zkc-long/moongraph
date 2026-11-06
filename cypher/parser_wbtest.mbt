// Parser tests: shape of the AST, not evaluation.

///|
test "parser/simple-match" {
  let q = parse_query("MATCH (n:Person) RETURN n") catch {
    _ => fail("should parse")
  }
  assert_eq(q.patterns.length(), 1)
  assert_eq(q.patterns[0].start.variable, "n")
  assert_eq(q.patterns[0].start.labels, ["Person"])
  assert_eq(q.patterns[0].hops.length(), 0)
  assert_eq(q.items.length(), 1)
  assert_eq(q.items[0].col, "n")
}

///|
test "parser/typed-relationship-direction" {
  let q = parse_query("MATCH (a)-[r:KNOWS]->(b) RETURN a") catch {
    _ => fail("should parse")
  }
  let hop = q.patterns[0].hops[0]
  assert_eq(hop.rel.types, ["KNOWS"])
  assert_eq(hop.rel.variable, "r")
  assert_true(hop.rel.dir is Out)
}

///|
test "parser/incoming-and-undirected" {
  let q = parse_query("MATCH (a)<-[:R]-(b)-[:S]-(c) RETURN a") catch {
    _ => fail("should parse")
  }
  let hops = q.patterns[0].hops
  assert_true(hops[0].rel.dir is In)
  assert_true(hops[1].rel.dir is Both)
}

///|
test "parser/variable-length-range" {
  let q = parse_query("MATCH (a)-[:R*2..4]->(b) RETURN a") catch {
    _ => fail("should parse")
  }
  let rel = q.patterns[0].hops[0].rel
  assert_eq(rel.min_hops, 2)
  assert_eq(rel.max_hops, 4)
}

///|
test "parser/unbounded-variable-length" {
  let q = parse_query("MATCH (a)-[:R*]->(b) RETURN a") catch {
    _ => fail("should parse")
  }
  let rel = q.patterns[0].hops[0].rel
  assert_eq(rel.min_hops, 1)
  assert_eq(rel.max_hops, -1)
}

///|
test "parser/where-precedence" {
  // a OR b AND c must parse as a OR (b AND c)
  let q = parse_query("MATCH (n) WHERE n.a = 1 OR n.b = 2 AND n.c = 3 RETURN n") catch {
    _ => fail("should parse")
  }
  match q.where_ {
    Some(EBin(op, _, EBin(op2, _, _))) => {
      assert_eq(op, "OR")
      assert_eq(op2, "AND")
    }
    _ => fail("unexpected where shape")
  }
}

///|
test "parser/return-alias-and-aggregate" {
  let q = parse_query("MATCH (n) RETURN count(n) AS c, n.name") catch {
    _ => fail("should parse")
  }
  assert_eq(q.items[0].col, "c")
  match q.items[0].expr {
    EFunc(name, args) => {
      assert_eq(name, "count")
      assert_eq(args.length(), 1)
    }
    _ => fail("expected function call")
  }
  assert_eq(q.items[1].col, "n.name")
}

///|
test "parser/order-skip-limit-distinct" {
  let q = parse_query(
    "MATCH (n) RETURN DISTINCT n.name AS name ORDER BY name DESC SKIP 2 LIMIT 5",
  ) catch {
    _ => fail("should parse")
  }
  assert_true(q.distinct)
  assert_eq(q.order.length(), 1)
  assert_true(q.order[0].descending)
  assert_eq(q.skip, Some(2))
  assert_eq(q.limit, Some(5))
}

///|
test "parser/properties-and-string-literals" {
  let q = parse_query("MATCH (n:Person {name: 'Ada', age: 36}) RETURN n") catch {
    _ => fail("should parse")
  }
  let props = q.patterns[0].start.props
  assert_eq(props.length(), 2)
  assert_eq(props[0].0, "name")
  assert_true(props[0].1 is ELit(@mg.VStr("Ada")))
}

///|
test "parser/rejects-incomplete-query" {
  let failed = try {
    ignore(parse_query("MATCH (n)"))
    false
  } catch {
    ParseError::UnexpectedToken(_, _) => true
    _ => true
  }
  assert_true(failed)
}

///|
test "parser/rejects-garbage" {
  let failed = try {
    ignore(parse_query("MATCH (n) RETURN %%%"))
    false
  } catch {
    _ => true
  }
  assert_true(failed)
}
