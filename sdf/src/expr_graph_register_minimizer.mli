@@ portable

open! Core

val minimize
  :  instructions:Expr_graph.t
  -> final_register:int
  -> instructions:Expr_graph.t * final_register:int * register_count:int
