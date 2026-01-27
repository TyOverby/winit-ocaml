# Create Code Builder Abstraction

## Problem

Code generation uses raw string concatenation with `sprintf` throughout, leading to:
- Hard-to-read generation code
- Inconsistent indentation
- Mixing of concerns (structure vs formatting)

## Current Pattern

```ocaml
sprintf
  "module %s = struct\n\
  \  type t =\n\
   %s\n\n\
   %s\n\n\
  \  let to_int = function\n\
   %s\n\n\
  \  let of_int = function\n\
   %s\n\
  \    | n -> failwith (Printf.sprintf \"%s.of_int: unknown value %%d\" n)\n\
   end\n"
  module_name
  variants
  externals
  to_int_cases
  of_int_cases
  module_name
```

This is:
- Hard to read (escaped newlines, manual indentation)
- Error-prone (easy to get indentation wrong)
- Difficult to modify (adding a line requires adjusting many escapes)

## Proposed Fix

### Create a Code Builder Module

```ocaml
(* codegen/code.ml *)

type t

(** Create an empty code builder *)
val empty : t

(** Add a line at the current indentation level *)
val line : string -> t -> t

(** Add a blank line *)
val blank : t -> t

(** Add lines from a string (splits on newlines) *)
val lines : string -> t -> t

(** Increase indentation for the given builder *)
val indent : t -> t

(** Build a module structure *)
val module_ : name:string -> (t -> t) -> t -> t

(** Build a module signature *)
val module_sig : name:string -> (t -> t) -> t -> t

(** Build a function definition *)
val let_ : name:string -> params:string list -> body:(t -> t) -> t -> t

(** Build a val declaration *)
val val_ : name:string -> type_:string -> t -> t

(** Build a type definition *)
val type_ : name:string -> def:string -> t -> t

(** Build a match expression *)
val match_ : expr:string -> cases:(string * string) list -> t -> t

(** Render to string *)
val to_string : t -> string

(** Render with a custom indentation string *)
val to_string_with_indent : indent:string -> t -> string
```

### Usage Example

```ocaml
(* Before *)
let gen_ml_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants = List.map enum.entries ~f:(fun entry ->
    sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n" in
  (* ... lots more sprintf ... *)
  sprintf "module %s = struct\n  type t =\n%s\n..." module_name variants

(* After *)
let gen_ml_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  Code.empty
  |> Code.module_ ~name:module_name (fun code ->
    code
    |> Code.type_ ~name:"t" ~def:(
      String.concat ~sep:"\n" (
        List.map enum.entries ~f:(fun entry ->
          "| " ^ normalize_enum_entry_name entry.name)))
    |> Code.blank
    |> Code.let_ ~name:"to_int" ~params:["x"] (fun code ->
      code |> Code.match_ ~expr:"x" ~cases:(
        List.map enum.entries ~f:(fun entry ->
          normalize_enum_entry_name entry.name,
          sprintf "%s_%s ()" (String.lowercase enum.name) (String.lowercase entry.name))))
    (* ... *)
  )
  |> Code.to_string
```

### C Code Builder

Similar abstraction for C code:

```ocaml
(* codegen/c_code.ml *)

val function_ :
  return_type:string ->
  name:string ->
  params:(string * string) list ->
  body:(t -> t) ->
  t -> t

val caml_prim :
  name:string ->
  params:string list ->
  body:(t -> t) ->
  t -> t

val if_ : condition:string -> then_:(t -> t) -> ?else_:(t -> t) -> t -> t

val for_loop :
  init:string ->
  condition:string ->
  increment:string ->
  body:(t -> t) ->
  t -> t
```

## Benefits

1. **Consistent indentation** - handled automatically
2. **Readable generation code** - structure mirrors output structure
3. **Composable** - can build complex structures from simple parts
4. **Reusable** - same patterns used across generators
5. **Testable** - can test code builders independently

## Estimated Impact

- Medium value: Improves readability of generation code
- Medium effort: Requires rewriting most generation functions
