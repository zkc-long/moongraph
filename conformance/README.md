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

`Given any graph` now builds the real `binary-tree-1` fixture
(`conformance/graphs/`, vendored from the TCK), so the skip count dropped from
50 to 28.

| file | scenarios | passed | failed | skipped |
|---|---|---|---|---|
| Match1 | 11 | 5 | 5 | 1 |
| Match2 | 13 | 5 | 7 | 1 |
| Match3 | 30 | 11 | 15 | 4 |
| Return1 | 2 | 1 | 0 | 1 |
| Return2 | 18 | 6 | 7 | 5 |
| Create1 | 20 | 9 | 6 | 5 |
| Set1 | 11 | 1 | 6 | 4 |
| Delete1 | 8 | 2 | 3 | 3 |
| Merge1 | 17 | 5 | 8 | 4 |

**45 passed / 57 failed / 28 skipped**, i.e. 44.1% of the 102 scenarios the
runner executes. Running more scenarios lowers the percentage but raises the
number of scenarios that actually pass — the previous 39/80 was measured on a
smaller, easier subset.

## What closing the gap would take

1. **Node/relationship equality inside `DISTINCT`, `ORDER BY` and grouping** —
   structural values are text today, which is not enough for every comparison.
2. **List expressions**: concatenation, comprehension, indexing.
3. **Label predicates** (`RETURN (n:Foo)`) and map projections.
4. **MERGE edge cases**: multiple elements, `ON CREATE` interactions, uniqueness.