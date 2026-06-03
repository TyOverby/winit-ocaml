(* A grid-native SDF evaluator that compiles the expression tree down to a WGSL compute
   shader and evaluates the whole pixel grid on the GPU in a single dispatch (via the
   headless [wgpu] bindings).

   It conforms to {!Sdf.Batch_backend_intf.S_parallel} — the same interface the CPU
   parallel backends implement — so it is a drop-in alternative anywhere an [S_parallel]
   is expected (e.g. the [neon] renderer), and is checked against the CPU backends by the
   bisimulation tests.

   Unlike the CPU backends it ignores the supplied [Parallel_scheduler.t]: the GPU owns
   its own parallelism. {!Batch.run} uploads the inputs, issues one dispatch, and copies
   the results back to host memory, so the returned {!Result.t} is host-resident. *)
include Sdf.Batch_backend_intf.S_parallel

(* The WGSL source the backend would compile [tree] to. Exposed for tests/debugging. *)
val wgsl_of_tree : Sdf.Expr_tree.t -> string
