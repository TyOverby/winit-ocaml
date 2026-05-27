open! Core

val minimize
  :  instructions:Expr_graph.t
  -> final_register:int
  -> register_count:int
  -> instructions:Expr_graph.t * final_register:int * register_count:int
