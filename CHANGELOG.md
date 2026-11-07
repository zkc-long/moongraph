# Changelog

All notable changes to Quiver are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - 2026-11-07

### Changed

- **Renamed the project to Quiver.** The module is now `quiver`, the CLI is
  `quiver`, and every package path moved from `moongraph/...` to `quiver/...`.
  The reason is naming clarity: mooncakes already hosts a graph *algorithm*
  package called `moongraph`, and two different things under one word costs
  readers more than the rename costs us. `quiver` is the mathematical term for
  a directed multigraph, which is exactly the data model here.
- Repository moved to https://github.com/zkc-long/quiver

## [0.3.0] - 2026-11-07

### Added

- `UNWIND expr AS name`, including several `UNWIND` clauses in one query
- `count(*)`, map literals (`RETURN {a: 1}`) and map assignment (`SET n = {…}`,
  `SET n += {…}`)
- sequences of write clauses in one query (`MATCH … DELETE … MERGE …`), with a
  single `MATCH`/`WHERE`/`CREATE`/`MERGE`/`SET`/`DELETE` pipeline per query
- multiple `MATCH` clauses, `<-->` arrows, and `[:T|:T]` type alternatives
- `SET (n).prop`
- error-assertion steps in the TCK runner: a query the engine rejects counts as
  a pass, a query it accepts is reported as skipped instead of silently passed
- path variables bound by `MERGE`/`CREATE` (`MERGE p = (a)-[:R]->(b)`)

### Changed

- side effects are counted from write counters on the graph rather than a
  before/after diff; `+labels` counts label names new to the graph, and an
  overwritten property counts as one `+properties` and one `-properties`
- label-less nodes render as `({k: v})` instead of `(: {k: v})`
- TCK doubles (`1.0`) are parsed as doubles rather than strings

### Fixed

- `DELETE` no longer drops the bindings, so `RETURN type(r)` after deleting a
  relationship still produces a row
- multi-statement TCK blocks are run as a script whether they appear in the
  setup or in the query under test
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
