# CI

`github-actions.yml` is the CI workflow for this repository. It lives here rather
than in `.github/workflows/` because pushing workflow files requires a GitHub
token with the `workflow` scope, which the automation used to build this
repository did not have.

## Enabling it

1. Create `.github/workflows/ci.yml` in the GitHub web UI
   (`Add file` → `Create new file`).
2. Paste the contents of `github-actions.yml`.
3. Commit to `main`.

The workflow installs the MoonBit toolchain, builds, runs the 92 tests, checks
that formatting is clean, runs the openCypher TCK subset and uploads
`conformance/report.md` as an artifact.

## What it proves

* the project builds from a clean checkout on a machine that has never seen
  MoonBit;
* the test suite is green outside the author's machine;
* `moon fmt` produces no diff, so the tree is formatted consistently;
* the TCK report is reproducible from CI, not only locally.
