# openCypher TCK subset

The vendored `.feature` files are taken unchanged from
[opencypher/openCypher](https://github.com/opencypher/openCypher) (Apache-2.0),
under `tck/features/clauses/**`.

## What the runner does

`cmd/tck` parses Gherkin and executes the step vocabulary the vendored files use:

| step | behaviour |
|---|---|
| `Given an empty graph` | fresh graph |
| `Given any graph` | **skipped**: the TCK standard fixture is built by the harness, not by this runner |
| `And having executed:` | runs the docstring as a write query |
| `When executing query:` | runs the docstring and captures the result |
| `Then the result should be:` / `, in any order:` | unordered multiset comparison |
| `Then the result should be, in order:` | ordered comparison |
| `And the result should be empty` | row count check |
| `And no side effects` | ignored |

A scenario is reported as **skipped** (never failed) when it needs something the
engine deliberately does not implement, so the pass rate is not inflated:

* steps the runner does not handle (side-effect tables, error assertions)
* Cypher outside the supported subset: `WITH`, `UNION`, `OPTIONAL`, `CALL`,
  `FOREACH`, parameters (`$x`), string predicates, exponentiation
* expected values that are whole nodes or relationships — the engine returns
  node ids, not structural values

## Running it

```bash
moon build --target native
./_build/native/debug/build/cmd/tck/tck.exe conformance/features/*.feature
```

`conformance/report.md` is rewritten on every run.

## Current numbers (2026-11-07)

| file | scenarios | passed | failed | skipped |
|---|---|---|---|---|
| Match1 | 11 | 5 | 0 | 6 |
| Match2 | 13 | 7 | 0 | 6 |
| Match3 | 30 | 20 | 6 | 4 |
| Return1 | 2 | 1 | 0 | 1 |
| Return2 | 18 | 10 | 3 | 5 |
| Create1 | 20 | 12 | 0 | 8 |
| Set1 | 11 | 3 | 3 | 5 |
| Delete1 | 8 | 3 | 0 | 5 |
| Merge1 | 17 | 7 | 6 | 4 |

**68 passed / 18 failed / 44 skipped**, i.e. 79.1% of the 86 scenarios the runner
evaluates. Five of the nine files pass every scenario they execute.

Side effects are measured with write counters on the graph (`+/- nodes`,
`relationships`, `properties`, `labels`), matching how the TCK accounts for
property overwrites (one `+properties` and one `-properties` per overwritten
key) rather than a before/after diff.

## What is still skipped or failing

Skips (44):

* error-assertion scenarios (`a SyntaxException should be raised`);
* `UNWIND`, `REMOVE`, `count(*)`, map literals in `RETURN`.

Failures (18):

* `Match3` / `Return2`: mixed directed/undirected patterns and some map
  projections over the fixture graph;
* `Set1`: remaining scenarios use `SET n = {...}` or `SET (n).prop`, which the
  parser rejects;
* `Merge1`: multi-element merges and `ON CREATE` on a freshly created node.