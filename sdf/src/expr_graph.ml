open! Core
module Var_id = Unique_id.Int ()

type t = { sequence : (Var_id.t * Expr_tree.t) list }

let 