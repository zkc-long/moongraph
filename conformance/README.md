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

## Current numbers (2026-11-06)

| file | scenarios | passed | failed | skipped |
|---|---|---|---|---|
| Match1 | 11 | 2 | 0 | 9 |
| Match2 | 13 | 1 | 4 | 8 |
| Match3 | 30 | 0 | 11 | 19 |
| Return1 | 2 | 0 | 0 | 2 |
| Return2 | 18 | 6 | 7 | 5 |
| Create1 | 20 | 0 | 3 | 17 |
| Set1 | 11 | 0 | 3 | 8 |
| Delete1 | 8 | 0 | 2 | 6 |
| Merge1 | 17 | 2 | 8 | 7 |

11 passed / 38 failed / 81 skipped. The number is low and that is the honest
state: the runner, the Gherkin parser and the skip taxonomy are the work here,
and they turn "we implement a Cypher subset" into something measurable.

## What closing the gap would take

1. **Structural values** (node/relationship/map/path) — the single largest
   source of skips; needs value identity plus structural comparison.
2. `WITH` — required by most `RETURN` scenarios.
3. Parameters and the standard fixture graph, which unlocks the `any graph`
   scenarios.
4. `OPTIONAL MATCH` and null-row semantics.
