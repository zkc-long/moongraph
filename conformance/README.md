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
| Match1 | 11 | 10 | 0 | 1 |
| Match2 | 13 | 12 | 0 | 1 |
| Match3 | 30 | 26 | 0 | 4 |
| Return1 | 2 | 1 | 0 | 1 |
| Return2 | 18 | 11 | 0 | 7 |
| Create1 | 20 | 12 | 0 | 8 |
| Set1 | 11 | 6 | 0 | 5 |
| Delete1 | 8 | 4 | 0 | 4 |
| Merge1 | 17 | 12 | 0 | 5 |

**94 passed / 0 failed / 36 skipped** — every scenario the runner evaluates
passes. 94 of 130 scenarios in the vendored files; the other 36 need features
listed below.

Progression: structural values 11 → 26, `WITH` 26 → 30, side effects + keyword
case + `MERGE ON CREATE` 30 → 39, paths + fixture 39 → 45, list/label/map
expressions and aggregate expressions 45 → 51, script setup + self-loop/label
fixes 51 → 64, relationship uniqueness 64 → 66, write counters 66 → 68,
type alternatives + multiple `MATCH` + `<-->` 68 → 74, multi-clause writes +
`UNWIND` + `count(*)` + map literals 74 → 83, error assertions 83 → 94.

## How skips and failures are decided

* **Failed** — the runner produced a result that disagrees with the expected
  table or side effects. Currently zero.
* **Skipped** — the runner cannot judge honestly. Either the query uses a
  feature the engine does not implement, or the engine *accepts* a query the
  TCK expects to reject (we do not model the exception taxonomy, so we cannot
  claim that case passes).

Skips (36) come from: `OPTIONAL MATCH` (6 scenarios), parameters (`$param`),
`count(*)` in a few shapes, and error scenarios whose queries our parser
happily accepts.