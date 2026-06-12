@@ portable

(** Workaround for an OxCaml runtime/codegen bug on amd64 (observed with the [parallel]
    scheduler, compiler + parallel v0.18~preview): when a fiber's OCaml stack grows (is
    reallocated) while an unboxed [float32#]/[int32#] value is in flight — e.g. the
    per-pixel [x]/[y] arguments the scalar evaluators pass down — the value can come back
    clobbered with whatever the register held in another task, silently corrupting one
    sample. arm64 is unaffected.

    Calling [pre_grow] at the top of a parallel task forces the fiber's stack to grow past
    any depth the evaluators will reach *before* any unboxed values are live, so no
    reallocation happens mid-evaluation. A no-op on arm64.

    Repro and details: issues/open/amd64-fiber-stack-growth-corrupts-unboxed.md. Delete
    this module once the upstream fix lands. *)
val pre_grow : unit -> unit
