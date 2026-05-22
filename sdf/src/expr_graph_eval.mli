open! Core

val run
  :  instructions:(Expr_graph.Register.t * Expr_graph.instr) list
  -> final_register:int
  -> register_count:int
  -> Value.t
