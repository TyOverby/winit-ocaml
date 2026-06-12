# `sdf/for_testing` — evaluators and shapes for tests/benchmarks only

The `sdf_for_testing` library holds evaluation machinery that production code
never touches; nothing under `sdf/src`, the runner, the UI, or the benchmarks
depends on it. Production evaluates exclusively through
`Sdf.Expr_graph_batch_eval` (grids) and `Sdf.Expr_graph_eval.Single` (points).

## Modules

- **`Executor`** (`executor.ml`) — the evaluator "shapes" the differential and
  bisimulation test suites functorize over:
  - `S_single` — evaluate one `(x, y)` point.
  - `S_batch` — evaluate a `Sample_region.t` grid single-threaded (this is the
    shape `Sdf.Expr_graph_batch_eval` satisfies).
  Plus the adapters `Single_to_batch` (loop over pixels) and `Batch_to_single`
  (1×1 region), used to fit every evaluator into whichever shape a test suite
  wants.
- **`Expr_tree_eval`** — the reference interpreter: walks the `Sdf.Expr_tree`
  directly, scalar, one point at a time. Easiest evaluator to audit, so it is
  the reference side of bisimulation (`sdf/test/test_bisimulation.ml`) and the
  contour differential quickchecks (`sdf/contour/test`).

## Why it exists

The SIMD/scalar bitwise-consistency contract (see `../CLAUDE.md`, "Arithmetic
Semantics") is enforced by comparing evaluators against each other. Those
comparisons need (a) an independent, simple reference implementation and (b) a
common module-type to write the test functors against — but neither belongs in
the production library, so they live here.
