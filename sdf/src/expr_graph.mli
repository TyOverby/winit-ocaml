@@ portable

open! Core

module Register : sig
  type t = int [@@deriving sexp_of, equal, compare, hash]
end

type instr =
  | Float_literal of Float32_u.t
  | Bool_literal of bool
  | Var of int
  | Read of Register.t
  | Add of Register.t * Register.t
  | Mul of Register.t * Register.t
  | Sub of Register.t * Register.t
  | Div of Register.t * Register.t
  | Sqrt of Register.t
  | Condition of
      { cond : Register.t
      ; then_ : t
      ; else_ : t
      }
  | Lt of Register.t * Register.t
  | Gt of Register.t * Register.t
  | Lte of Register.t * Register.t
  | Gte of Register.t * Register.t
  | And of Register.t * Register.t
  | Or of Register.t * Register.t
  | Xor of Register.t * Register.t

and t = (Register.t * instr) list [@@deriving sexp_of, equal, compare]

val from_tree
  :  Expr_tree.t
  -> instructions:t
     * final_register:int
     * register_count:int
     * var_mapping:int String.Table.t

val pp_instructions : t -> string
