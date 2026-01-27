# Create Abstract Type Mapping Layer

## Problem

Type mapping logic is scattered throughout both gen_low.ml and gen_high.ml, with
different versions for different contexts:

### In gen_low.ml
- `c_type_of_type_ref`: IR type -> C type string
- `ml_type_of_type_ref`: IR type -> OCaml type string (for low-level)
- Inline mappings in setter/getter generation

### In gen_high.ml
- `high_level_arg_type`: IR type -> OCaml type string (for high-level args)
- `high_level_return_type`: IR type -> OCaml type string (for returns)
- `high_level_member_type`: IR type -> OCaml type string (for struct members)
- `high_level_member_type_of_type`: Another variant

These are similar but subtly different, making it hard to ensure consistency.

## Current Duplication Example

```ocaml
(* gen_low.ml *)
let rec ml_type_of_type_ref (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive Bool -> "bool"
  | Primitive (Uint32 | Int32) -> "int"
  ...

(* gen_high.ml *)
let rec high_level_arg_type (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive Bool -> "bool"
  | Primitive (Uint32 | Int32) -> "int"
  ...
  | Enum name -> ocaml_module_name name ^ ".t"  (* Different! *)
  ...
```

## Proposed Fix

### Create a Type_mapping Module

```ocaml
(* codegen/type_mapping.ml *)

(** Output context affects how types are rendered *)
type context =
  | C_code
  | Ocaml_low_level
  | Ocaml_high_level_arg
  | Ocaml_high_level_return
  | Ocaml_high_level_member

(** Get the string representation of a type in a given context *)
val type_string : context:context -> Ir.type_ref -> string

(** Get the C type name for a WGPU type (e.g., "texture_format" -> "WGPUTextureFormat") *)
val c_type_name : string -> string

(** Get the OCaml module name (e.g., "texture_format" -> "Texture_format") *)
val ocaml_module_name : string -> string
```

### Implementation

```ocaml
let type_string ~context (type_ref : Ir.type_ref) : string =
  match context, type_ref with
  (* Primitives are the same everywhere except C *)
  | C_code, Primitive Bool -> "bool"
  | (Ocaml_low_level | Ocaml_high_level_arg | Ocaml_high_level_return | Ocaml_high_level_member),
    Primitive Bool -> "bool"

  (* Strings differ between C and OCaml *)
  | C_code, Primitive String -> "WGPUStringView"
  | _, Primitive String -> "string"

  (* Enums: low-level uses int, high-level uses module type *)
  | C_code, Enum name -> c_type_name name
  | Ocaml_low_level, Enum _ -> "int"
  | _, Enum name -> ocaml_module_name name ^ ".t"

  (* Objects: low-level uses raw nativeint, high-level uses module type *)
  | C_code, Object name -> c_type_name name
  | Ocaml_low_level, Object name -> name  (* type alias *)
  | _, Object name -> ocaml_module_name name ^ ".t"

  (* Bitflags: returns need special handling *)
  | Ocaml_high_level_return, Bitflag _ -> "int"  (* Could be combo *)
  | Ocaml_high_level_arg, Bitflag name -> ocaml_module_name name ^ ".t list"
  | Ocaml_high_level_member, Bitflag name -> ocaml_module_name name ^ ".t list"
  | Ocaml_low_level, Bitflag _ -> "int"
  | C_code, Bitflag name -> c_type_name name

  ...
```

### Benefits of Centralization

1. **Single source of truth** for type mappings
2. **Explicit contexts** - clear what each variant is for
3. **Easier to add new types** - one place to update
4. **Testable** - can unit test all context/type combinations
5. **Documentation** - type mapping rules are all together

### Conversion Functions

Also centralize conversion logic:

```ocaml
(** Generate code to convert from high-level to low-level *)
val convert_to_low : var_name:string -> Ir.type_ref -> string

(** Generate code to convert from low-level to high-level *)
val convert_to_high : expr:string -> Ir.type_ref -> string
```

## Estimated Impact

- High value: Eliminates a major source of inconsistency
- Medium effort: Requires careful auditing of existing mappings
