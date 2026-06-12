@@ portable

open! Core

(** The reference interpreter: walks the [Sdf.Expr_tree] directly, scalar, one point at a
    time. It is the easiest evaluator to audit, which makes it the reference side of the
    bisimulation and differential test suites. Not used in production. *)

module Single : Executor.S_single
module Batch : Executor.S_batch
