# Changelog

All notable changes to MoonGraph are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-11-07

### Added

- `WITH` clause: projection/aggregation stage followed by an optional `MATCH`
- path values (`MATCH p = (a)-[:R*1..3]->(b)`) with `length(p)`
- `shortestPath((a)-[:T*]-(b))` pattern form and the `shortestPath(a, b)` scalar
- list concatenation, indexing, slicing and comprehensions
- label predicates (`(n:Label)`), map projection (`n {.name}`), aggregates inside
  expressions (`count(x) > 0`)
- `MERGE ... ON CREATE SET / ON MATCH SET`
- multi-statement scripts with bindings carried across statements
- standalone HTML visualisation (`html` subcommand)
- Graphviz DOT export (`dot` subcommand)
- openCypher TCK subset runner with a real `binary-tree-1` fixture and an
  explicit skip/fail taxonomy
- relationship uniqueness inside a pattern, self-loop de-duplication
- side-effect counters (`+/- nodes, relationships, properties, labels`)

### Changed

- nodes and relationships are returned as canonical Cypher text rather than ids
- keywords are matched case-insensitively (`true`, `match`, `merge`, ...)
- `CREATE` drops null-valued properties, matching Cypher map semantics
- string ordering is implemented on code points instead of the platform
  comparator, so results are identical on every backend

### Fixed

- `length(p)` counted pattern hops instead of relationships walked
- undirected expansion returned a self-loop twice
- `Graph::labels` reported labels of tombstoned nodes
- list cells in the TCK runner swallowed the closing bracket

## [0.1.0] - 2026-11-06

### Added

- property graph store: dense ids, forward/reverse adjacency, label index,
  property equality index
- Cypher subset: `MATCH`, `WHERE`, `RETURN`, aggregations, `ORDER BY`, `SKIP`,
  `LIMIT`
- write clauses: `CREATE`, `MERGE`, `SET`, `DELETE`, `DETACH DELETE`
- JSON Lines import/export, mooncakes registry ingestion
- CLI: `query`, `info`, `import`, `registry`, `bench`
- 73 tests and a JSON reader/writer with no third-party dependencies
