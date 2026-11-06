# Design notes

## Why a graph database

MoonBit has plenty of parsers and codecs but no query engine over connected
data. The registry itself is a dependency graph: "which packages would break if
this one is yanked" is a reachability question, and answering it with a Cypher
query is both a useful tool and a compact demonstration of what the language can
express.

## Storage layout

```
nodes : Array[Node]        // node id == position, dense
edges : Array[Edge]
out_edges : Array[Array[Int]]   // node -> edge ids
in_edges  : Array[Array[Int]]
label_index : Map[String, Array[Int]]
prop_index  : Map[String, Map[String, Array[Int]]]
```

Three decisions are worth calling out.

**Dense ids.** A node id is its index. No hash lookup on the expansion hot path,
and adjacency is an array index rather than a tree walk. Ids are remapped on
import from stable string ids.

**Adjacency over edge ids, not neighbour ids.** An expansion needs the
relationship type and its properties, so the adjacency list stores the edge id
and dereferences once. Storing neighbours directly would require a second,
parallel lookup for every hop.

**Secondary indexes answer equality only.** `{name: "x"}` in a pattern can be
answered from `prop_index`; ranges and inequality fall back to a scan. Indexing
everything would slow ingest for a workload that is overwhelmingly read-only
after load.

## Query pipeline

`source -> tokenize -> parse -> execute -> project -> render`

The executor is a materialising Volcano pipeline: each operator consumes and
produces arrays of bindings. A binding holds three maps (scalars, nodes,
relationships) because a variable can be bound to any of them.

Pattern matching walks left to right; every hop expands the current binding set.
Variable-length relationships are a bounded breadth-first search. `WHERE` filters
bindings, then projection either maps expressions directly or groups by the
non-aggregated columns and folds the aggregates.

## Semantics that are easy to get wrong

**Three-valued logic.** `null = null` is `null`, not `true`. Comparisons
involving `null` evaluate to `null`, and `WHERE` keeps only rows whose predicate
is `true`. `AND`/`OR` short-circuit with Kleene semantics: `false AND null` is
`false`, `true OR null` is `true`.

**Ordering across types.** `null < bool < number < string < list`. Numbers
compare numerically whether they arrived as integers or doubles, so
`ORDER BY n` does not produce the surprising "1, 10, 2" that string comparison
would.

**String ordering is ours.** `Value::compare` compares strings by code point
instead of delegating to a platform comparator. That keeps results identical on
native, wasm and js, which matters because the same engine is meant to compile
to a browser demo later.

## Known limitations

* read-only: no `CREATE`/`MERGE`/`SET`/`DELETE`
* no `OPTIONAL MATCH`, `UNION`, `CALL`, `WITH`, `FOREACH`
* a variable-length relationship variable binds the last relationship, not the
  full list
* aggregates are recognised only at the top level of a projection item
* single-threaded, single-writer, no transactions
* `ORDER BY` is a stable insertion sort: fine for the result sizes this engine
  targets, wrong choice for a million-row sort

## Where the complexity actually went

Half of the code is not graph traversal but the boring parts of a query language:
the lexer's relationship arrows, precedence in `WHERE`, alias resolution in
`ORDER BY`, grouping keys, and making `null` behave. The traversal itself is
about 150 lines.
