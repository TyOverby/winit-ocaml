open! Core
open Sdf
module Ast = Ast
module Compile = Compile

val parse : ?filename:string -> string -> Ast.program Or_error.t

val compile
  :  ?oracle_names:String.Set.t
  -> ?filename:string
  -> string
  -> Expr_tree.t Or_error.t

val format_error : source:string -> Error.t -> string
