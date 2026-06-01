open! Core
open Sdf
module Ast = Ast
module Compile = Compile

let pos_to_string (pos : Lexing.position) : string =
  sprintf "%s:%d:%d" pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol)
;;

let parse ?(filename = "<string>") (source : string) : Ast.program Or_error.t =
  let lexbuf = Lexing.from_string source in
  lexbuf.lex_curr_p <- { lexbuf.lex_curr_p with pos_fname = filename };
  try Ok (Parser.program Lexer.token lexbuf) with
  | Lexer.Syntax_error (msg, pos) ->
    let loc = pos_to_string pos in
    Or_error.error_s [%message msg ~loc]
  | Parser.Error ->
    let pos = lexbuf.lex_curr_p in
    let loc = pos_to_string pos in
    Or_error.error_s [%message "syntax error" ~loc]
;;

let compile ?(filename = "<string>") (source : string) : Expr_tree.t Or_error.t =
  let%bind.Or_error program = parse ~filename source in
  Compile.compile_program program
;;

let format_error ~source (error : Error.t) : string =
  let sexp = Error.sexp_of_t error in
  (* Extract the error message text *)
  let msg =
    match sexp with
    | Sexp.Atom s -> s
    | Sexp.List (Sexp.Atom s :: _) -> s
    | _ -> Sexp.to_string sexp
  in
  (* Try to find a loc field in the sexp *)
  let find_loc sexp =
    match sexp with
    | Sexp.List fields ->
      List.find_map fields ~f:(fun field ->
        match field with
        | Sexp.List [ Sexp.Atom "loc"; Sexp.Atom loc_str ] -> Some loc_str
        | _ -> None)
    | _ -> None
  in
  match find_loc sexp with
  | None -> sprintf "error: %s" (Error.to_string_hum error)
  | Some loc_str ->
    (* Parse location string like "<string>:1:8" *)
    (match String.rsplit2 loc_str ~on:':' with
     | Some (rest, col_str) ->
       (match String.rsplit2 rest ~on:':' with
        | Some (file, line_str) ->
          let line_num = Int.of_string_opt line_str |> Option.value ~default:0 in
          let col_num = Int.of_string_opt col_str |> Option.value ~default:0 in
          let source_lines = String.split_lines source in
          let source_line =
            if line_num >= 1 && line_num <= List.length source_lines
            then List.nth_exn source_lines (line_num - 1)
            else ""
          in
          let caret = if col_num >= 0 then String.make col_num ' ' ^ "^" else "" in
          sprintf
            "error: %s\n --> %s:%d:%d\n  |\n%d | %s\n  | %s"
            msg
            file
            line_num
            col_num
            line_num
            source_line
            caret
        | None -> sprintf "error: %s" (Error.to_string_hum error))
     | None -> sprintf "error: %s" (Error.to_string_hum error))
;;
