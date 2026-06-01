@@ portable

open! Core

val run
  :  variables:Value.Array.t
  -> instructions:(int * Expr_graph.instr) iarray
  -> registers:Value.Array.t
  -> unit

val run_tree
  :  Expr_tree.t
  -> var_mapping:int String.Table.t * run:(variables:Value.Array.t -> Value.t)

module Batched : Batch_backend_intf.S

(** Grid-native ({!Batch_backend_intf.S_parallel}) wrapper over {!Batched}.

    [@@ nonportable] because [S_parallel.Batch.run] drives the scheduler and so cannot be
    portable; without it the enclosing [@@ portable] signature would demand a fully
    portable module. *)
module (Batch_parallel @@ nonportable) : Batch_backend_intf.S_parallel
