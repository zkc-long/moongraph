# MoonGraph

A property-graph database with a Cypher subset query engine, written in **pure
MoonBit** with zero third-party dependencies.

MoonGraph stores nodes and relationships with typed properties, indexes them,
and answers `MATCH ... WHERE ... RETURN` queries. It is the first Cypher engine
in the MoonBit ecosystem: the only prior graph work on mooncakes is a Neo4j
*client* (query strings + Bolt), not a database.

```moonbit
let g = Graph::new()
let ada = g.add_node(["Person"], { "name": VStr("Ada") })
let bob = g.add_node(["Person"], { "name": VStr("Bob") })
ignore(g.add_edge("KNOWS", ada, bob, {}))
let result = @cypher.run(g, "MATCH (a:Person)-[:KNOWS]->(b) RETURN a.name, b.name")
```

## What is implemented

* dense-id node/edge store with forward and reverse adjacency lists
* label index and property equality index used by the planner
* a hand written Cypher lexer and recursive-descent parser
* a Volcano-style executor: scan, expand, filter, project, aggregate, sort
* `MATCH` (multi-hop, typed relationships, directed and undirected),
  variable-length paths (`*1..3`), `WHERE`, `RETURN` with `DISTINCT`,
  aggregations (`count`, `sum`, `avg`, `min`, `max`, `collect`),
  `ORDER BY`, `SKIP`, `LIMIT`
* JSON Lines / CSV import, JSON snapshot save/load
* a CLI (`moongraph query|import|info|bench`) that runs natively

## What is deliberately out of scope

`OPTIONAL MATCH`, `UNION`, `CALL`, `FOREACH`, `LOAD CSV`, write clauses
(`CREATE`/`MERGE`/`SET`/`DELETE`), multi-statement transactions and
concurrency. The engine is read-only and single-threaded by design; see
`docs/design.md` for the rationale.

## Quick start

```bash
moon build --target native
./_build/native/debug/build/cmd/main/main.exe query examples/mooncakes.mgdb \
  "MATCH (p:Package)-[:DEPENDS_ON*1..2]->(c:Package {name:'moonbitlang/core'}) \
   RETURN c.name, count(p) AS fan_in ORDER BY fan_in DESC LIMIT 5"
```

## License

Apache-2.0.
