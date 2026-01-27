open! Core

(** Name transformation utilities for code generation *)

(** Convert snake_case to PascalCase. Simple version that doesn't handle double
    underscores. *)
let to_pascal_case_simple (name : string) : string =
  String.split name ~on:'_' |> List.map ~f:String.capitalize |> String.concat ~sep:""
;;

(** Convert snake_case to PascalCase, preserving double underscores as single underscores
    in the output. For example: "some__name" -> "Some_Name". This is needed for C names
    where double underscores have special meaning. *)
let to_pascal_case (name : string) : string =
  (* Double underscores become single underscores in C names *)
  let s = String.substr_replace_all name ~pattern:"__" ~with_:"_UNDERSCORE_" in
  let parts = String.split s ~on:'_' in
  let parts =
    List.map parts ~f:(fun p ->
      if String.equal p "UNDERSCORE" then "_" else String.capitalize p)
  in
  String.concat parts
;;

(** Convert snake_case to camelCase *)
let to_camel_case (name : string) : string =
  match String.split name ~on:'_' with
  | [] -> ""
  | first :: rest -> first ^ String.concat ~sep:"" (List.map rest ~f:String.capitalize)
;;

(** Convert C name conventions for enum entries (e.g., discrete_GPU -> Discrete_gpu) *)
let normalize_enum_entry_name (name : string) : string =
  let s = String.lowercase name in
  let s = String.capitalize s in
  (* OCaml identifiers can't start with a digit, prefix with N *)
  if String.length s > 0 && Char.is_digit (String.get s 0) then "N" ^ s else s
;;

(** OCaml reserved words that need escaping *)
let ocaml_keywords =
  [ "and"
  ; "as"
  ; "assert"
  ; "asr"
  ; "begin"
  ; "class"
  ; "constraint"
  ; "do"
  ; "done"
  ; "downto"
  ; "else"
  ; "end"
  ; "exception"
  ; "external"
  ; "false"
  ; "for"
  ; "fun"
  ; "function"
  ; "functor"
  ; "if"
  ; "in"
  ; "include"
  ; "inherit"
  ; "initializer"
  ; "land"
  ; "lazy"
  ; "let"
  ; "lor"
  ; "lsl"
  ; "lsr"
  ; "lxor"
  ; "match"
  ; "method"
  ; "mod"
  ; "module"
  ; "mutable"
  ; "new"
  ; "nonrec"
  ; "object"
  ; "of"
  ; "open"
  ; "or"
  ; "private"
  ; "rec"
  ; "sig"
  ; "struct"
  ; "then"
  ; "to"
  ; "true"
  ; "try"
  ; "type"
  ; "val"
  ; "virtual"
  ; "when"
  ; "while"
  ; "with"
  ]
;;

(** Escape OCaml keywords by adding underscore suffix *)
let escape_keyword (name : string) : string =
  if List.mem ocaml_keywords name ~equal:String.equal then name ^ "_" else name
;;

(** Helper to indent lines by one level (2 spaces) *)
let indent_lines (s : string) : string =
  String.split_lines s |> List.map ~f:(fun line -> "  " ^ line) |> String.concat ~sep:"\n"
;;

(** Read a template file from the templates directory *)
let read_template (path : string) : string =
  let template_path = "../codegen/templates/" ^ path in
  In_channel.read_all template_path
;;

(** Filter out unhelpful doc strings like "TODO" *)
let useful_doc (doc : string) : string option =
  let doc = String.strip doc in
  if String.is_empty doc
     || String.equal doc "TODO"
     || String.is_prefix doc ~prefix:"TODO\n"
  then None
  else Some doc
;;
