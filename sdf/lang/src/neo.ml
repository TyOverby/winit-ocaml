open! Core
open Sdf
module Ast = Ast
module Compile = Compile

let parse ?(filename = "<string>") (source : string) : Ast.program Or_error.t =
  Or_error.try_with (fun () ->
    let lexbuf = Lexing.from_string source in
    lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
    Parser.program Lexer.token lexbuf)
;;

let compile ?(filename = "<string>") (source : string) : Expr_tree.t Or_error.t =
  let%bind.Or_error program = parse ~filename source in
  Compile.compile_program program
;;
