@@ portable

open! Core

val run
  :  variables:Value.Array.t
  -> instructions:(int * Expr_graph.instr) array
  -> registers:Value.Array.t
  -> unit

val run_tree
  :  Expr_tree.t
  -> var_mapping:int String.Table.t * run:(variables:Value.Array.t -> Value.t)
