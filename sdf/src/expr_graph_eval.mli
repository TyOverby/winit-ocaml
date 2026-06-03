@@ portable

open! Core

include Executor.S

val run
  :  variables:Value.Array.t
  -> instructions:(int * Expr_graph.instr) iarray
  -> registers:Value.Array.t
  -> oracles:Prepared_oracle.t iarray
  -> x_var_idx:int
  -> y_var_idx:int
  -> unit
