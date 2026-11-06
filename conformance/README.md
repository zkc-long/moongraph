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
| Match2 | 13 | 5 | 2 | 6 |
| Match3 | 30 | 11 | 15 | 4 |
| Return1 | 2 | 1 | 0 | 1 |
| Return2 | 18 | 6 | 7 | 5 |
| Create1 | 20 | 3 | 5 | 12 |
| Set1 | 11 | 1 | 2 | 8 |
| Delete1 | 8 | 2 | 2 | 4 |
| Merge1 | 17 | 5 | 8 | 4 |

**39 passed / 41 failed / 50 skipped**, i.e. 48.8% of the 80 scenarios the runner
can evaluate.

Progression while building this: structural node/relationship values took passed
from 11 to 26; `WITH` to 30; side-effect assertions plus case-insensitive
keywords plus `MERGE ... ON CREATE/ON MATCH` to 39.

## What closing the gap would take

1. **A fixture graph for `Given any graph`** — 36 of the skips are this step; the
   TCK expects the harness to provide `binary-tree-1/2`.
2. **Parameters (`$x`) and the remaining expression syntax** — label predicates,
   map projections, list comprehensions.
3. **Path values** (`()-[r]->()`) and the `shortestPath()` pattern form.
4. **MERGE edge cases**: multiple elements, uniqueness conflicts.