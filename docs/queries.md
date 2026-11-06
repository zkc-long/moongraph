# Governance queries over the mooncakes dependency graph

Regenerate the dataset first:

```bash
node scripts/fetch_registry.js 120 > examples/mooncakes.registry.jsonl
moongraph registry examples/mooncakes.registry.jsonl > examples/mooncakes.jsonl
```

## 1. Most depended-upon packages

```cypher
MATCH (d:Package)-[:DEPENDS_ON]->(p:Package)
RETURN p.name AS package, count(d) AS dependents
ORDER BY dependents DESC LIMIT 10
```

## 2. Blast radius of a yank

If `mizchi/json` disappears, which packages break transitively?

```cypher
MATCH (victim:Package {name:'mizchi/json'})<-[:DEPENDS_ON*1..3]-(broken:Package)
RETURN DISTINCT broken.name AS affected ORDER BY affected
```

## 3. Direct dependents of one package

```cypher
MATCH (d:Package)-[:DEPENDS_ON]->(p:Package {name:'bobzhang/toml'})
RETURN d.name AS dependent, d.version AS version ORDER BY dependent
```

## 4. Two-hop neighbourhood of a package

```cypher
MATCH (a:Package {name:'yuzhiblue/moon-watermark'})-[:DEPENDS_ON*1..2]->(b:Package)
RETURN DISTINCT b.name AS reachable ORDER BY reachable
```

Note: the registry API exposes *dependents* (who depends on a module), not the
module's own dependency list, so outgoing edges only exist for modules that were
themselves fetched as someone else's dependent. Nodes with no outgoing edges are
"no data", not "no dependencies".

## 5. Who depends on what (grouped, readable)

```cypher
MATCH (d:Package)-[:DEPENDS_ON]->(p:Package)
RETURN p.name AS package, collect(d.name) AS dependents
ORDER BY package LIMIT 10
```

## 6. Size of the graph

```cypher
MATCH (p:Package) RETURN count(p) AS packages
```

## 7. Machine readable output

Any query accepts `--json`:

```bash
moongraph query examples/mooncakes.jsonl \
  "MATCH (p:Package) RETURN count(p) AS packages" --json
```

## Not expressible yet

`WHERE NOT (p)<-[:DEPENDS_ON]-(:Package)` (pattern predicates) and
`OPTIONAL MATCH` are outside the supported subset, so "isolated packages" and
"leaf packages" need a second pass over the exported edges. See
`docs/design.md` for the full list of limitations.
