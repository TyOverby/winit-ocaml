# `sdf/runner` — stateful evaluation driver

The `sdf_runner` library ties the whole pipeline together behind a small,
caching API: hand it Neo source and a `Sample_region.t`, and it compiles,
prepares oracles, evaluates, and hands the result grid to a callback. It is the
entry point used by both the benchmarks (`sdf/bench`) and the `neon` app.

## Modules

- **`Backend`** (`backend.ml`) — `Make (E : Executor.S)` produces a runner
  specialized to one evaluator backend. It owns the mutable state: the last
  compiled `Expr_tree.t`, the prepared expression, the parallel scheduler, the
  registered oracles, and the cached output.
- **`Sdf_runner`** (`sdf_runner.ml`) — a dynamically-typed wrapper around
  `Backend` that lets the executor be swapped at runtime via `set_executor`
  (so the UI / bench can switch between `tree`, `graph`, and `batch` backends).

## What `run` does

On each call it:

1. Recompiles the source **only if it changed** (`Neo.compile` →
   `Expr_tree.t`), and skips re-preparing if the new tree is structurally equal
   to the last one.
2. Prepares every oracle the scene references, in dependency order
   (`Oracle_dependencies.extract_deps`), reusing prepared oracles cached from the
   previous frame when the region matches.
3. Returns the cached output grid when neither the source nor the region changed
   (dirty-bit + region-equality check); otherwise re-evaluates in parallel.
4. Passes `(par, result, get)` to the caller's `~f`, where `get` reads a
   `Value.t` at a pixel.

The caching (dirty tracking, per-region result cache, per-region oracle cache)
is what makes interactive panning in `neon` cheap.

See `../src/CLAUDE.md` for the `Executor` and `Oracle` abstractions this builds
on.
