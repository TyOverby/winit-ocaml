open! Core
open Sdf

val compile_program : Ast.program -> Expr_tree.t Or_error.t
