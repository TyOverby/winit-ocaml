open! Core
open Sdf

val compile_program : oracle_names:String.Set.t -> Ast.program -> Expr_tree.t Or_error.t
