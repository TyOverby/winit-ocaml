# `sdf/runner` — stateful evaluation driver

The `sdf_runner` library ties the whole pipeline together behind a small,
caching API: hand it Neo source and a `Sample_region.t`, and it compiles,
prepares oracles, and evaluates — sparsely tiled (`run_tiled`, where
`Cull.Nothing` gives a dense every-sample evaluation) or as a zero contour
(`run_contour`). It is the entry point used by both the benchmarks (`sdf/bench`)
and the `neon` app.

## Module

- **`Sdf_runner`** (`sdf_runner.ml`) — the whole library is this one concrete
  module. It owns the mutable state: the last compiled `Expr_tree.t`, the
  parallel scheduler, the registered oracles, and the cached outputs.
  Evaluation always uses the SIMD batch evaluator
  (`Sdf.Expr_graph_batch_eval`), via `Tiled_eval` / `Sdf_contour`.

## What `run_tiled` / `run_contour` do

On each call they:

1. Recompile the source **only if it changed** (`Neo.compile` →
   `Expr_tree.t`), and skip re-evaluating if the new tree is structurally equal
   to the last one.
2. Prepare every oracle the scene references, in dependency order
   (`Oracle_dependencies.extract_deps`), reusing prepared oracles cached from the
   previous frame when the region matches.
3. Return the cached output when neither the source nor the region (nor, for
   `run_tiled`, the cull predicate) changed; otherwise re-evaluate in parallel,
   one tile per task.

The caching (dirty tracking, per-region result cache, per-region oracle cache)
is what makes interactive panning in `neon` cheap.

See `../src/CLAUDE.md` for the evaluators and the `Oracle` interface this
builds on.
