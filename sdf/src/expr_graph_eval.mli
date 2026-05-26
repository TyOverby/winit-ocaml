@@ portable

open! Core

val run
  :  instructions:(Expr_graph.Register.t * Expr_graph.instr) list
  -> variables:Value.Array.t
  -> final_register:int
  -> register_count:int
  -> Value.t

val run_tree
  :  Expr_tree.t
  -> var_mapping:int String.Table.t * run:(variables:Value.Array.t -> Value.t)
