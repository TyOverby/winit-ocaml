@@ portable

open! Core

type register_bank
type variable_bank

val create_register_bank : register_count:int -> width:int -> register_bank
val create_variable_bank : num_vars:int -> width:int -> variable_bank

(** Fill variable [var] for pixel [px] *)
val set_variable : variable_bank -> var:int -> px:int -> Value.t -> unit

(** Get result from register [reg] at pixel [px] *)
val get_result : register_bank -> reg:int -> px:int -> Value.t

(** Run all instructions across [width] pixels in one pass *)
val run
  :  variable_bank:variable_bank
  -> instructions:Expr_graph.t
  -> register_bank:register_bank
  -> width:int
  -> unit
