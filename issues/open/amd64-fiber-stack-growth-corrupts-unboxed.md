# amd64: fiber stack growth corrupts in-flight unboxed values (upstream OxCaml bug)

## Summary

On amd64 (x86-64), when an OCaml fiber's stack is reallocated (grown) while an
unboxed `float32#`/`int32#` value is live in a register, the value can come
back clobbered with leftover register contents from unrelated code. arm64 is
unaffected. Observed with the `parallel` scheduler
(`parallel.v0.18~preview.130.91+190`); plain `Domain.spawn` workers (which get
large stacks up front, so never grow) never reproduce it.

This is a bug in OxCaml's amd64 stack-growth path (or the scheduler's use of
it), **not** in this repository. This file documents the workaround so it can
be removed once the upstream fix lands.

## Symptom

The `contour/test` differential quickcheck suites failed on x86 for the
*scalar* backends (`Expr_tree_eval`, `Expr_graph_eval`): `Sdf_contour.extract`
returned one corrupted sample (or a wrongly culled tile), so the tiled segment
list disagreed with the dense reference. Run-to-run nondeterministic, but
biased to pixel 0 of tiles at fork-split boundaries of `Parallel.for_`.

## Diagnosis trail

- The corrupted output for the failing tree `sin(cos y) + sin(max(y,y))` was
  `0x3f576aa4 = sinf(1.0) = f(0.0)` — i.e. the evaluator ran with `y = 0.0`
  even though the batch's `y_coords` array was verified bitwise-correct both
  before and after the run. The per-pixel `float32#` `y` *argument* was
  clobbered in flight, not memory.
- Pixel 0's register bank afterwards held `[0x1; sinf(1.0); sinf(1.0)]` — the
  `Coord_y` register contained a stray `0x00000001`, and the rest of the
  evaluation was consistent with it. Other observed clobber values matched
  other tiles' intermediates (whatever the register last held).
- Same domain start/end per task (no migration); minor-heap size has no effect
  (`s=512M` with 6 total minor GCs still ~50% failure rate), no C-call needed
  (a trig-free `sqrt/mul/max` tree reproduces), batch SIMD evaluator and plain
  `Domain.spawn` never reproduce.
- **Pre-growing the fiber stack with ~4000 dummy frames at task start drops the
  failure rate from ~50-90% of runs to 0/300.** That pins it on stack
  reallocation: the first time the fiber reaches evaluator depth, the stack
  check at some function entry reallocates the stack and loses an unboxed
  argument register; afterwards the stack is big enough and every later pixel
  is computed correctly (matching the pixel-0-only signature).
- The same clobber hits the *interval scheduler* on the fiber that calls
  `extract` itself (unboxed `#{ lo; hi }` interval halves passed through
  `Tile_scheduler.schedule`'s recursion), which showed up as a deterministic
  wrongly-culled tile at high `QUICKCHECK_TRIALS`.

## Minimal reproduction (x86, before workaround)

Loop `Sdf_contour.extract` with a scalar backend against a dense reference;
~90/100 runs mismatch:

```ocaml
let tree = (* sin(cos y) + sin(max(y,y)) *) ... in
let region = { start_x = -27.78s; end_x = -38.31s; samples_x = 30
             ; start_y = 97.76s; end_y = 19.51s; samples_y = 26 } in
Parallel_scheduler.parallel scheduler ~f:(fun par ->
  Sdf_contour.extract ~exec:(module Expr_graph_eval) ~par ~oracles ~region
    ~tile_cells:2 tree)
(* compare segments against March.run over a dense grid *)
```

Equivalently, `Parallel.for_` tasks that fill an `int32#` coordinate array and
evaluate `Expr_graph_eval.Batch` over it (no marching needed) reproduce; the
same body under `Domain.spawn` does not.

## Workaround in this repo

`sdf/src/fiber_stack.ml` (`Fiber_stack.pre_grow`, a no-op on arm64) forces the
fiber's stack deep before any unboxed work. It is called at the top of:

- each tile task in `Sdf_contour.extract` and `Tiled_eval.run`, and
- the entry of `Sdf_contour.extract` / `Tiled_eval.run` themselves (they run on
  the caller's parallel fiber, where the interval scheduler recurses with
  unboxed bounds).

## To close this issue

Report upstream with the repro above; once a fixed compiler/runtime is in the
opam switch, delete `sdf/src/fiber_stack.ml(i)`, the `pre_grow` call sites, and
this file, then confirm `QUICKCHECK_TRIALS=5000 dune build @sdf/runtest` stays
green on x86.
