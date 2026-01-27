# Simplify Complex Function Signatures and Return Types

## Problem

Several functions have complex return types that are hard to understand and use correctly:

### Example 1: generate_struct_creates

```ocaml
let rec generate_struct_creates
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  (var_name : string)
  : (string * Ir.struct_) list * string list
```

The return type `(string * Ir.struct_) list * string list` is opaque. What does each
component represent? The caller has to read the implementation to understand.

### Example 2: generate_array_of_structs_conversion

```ocaml
let generate_array_of_structs_conversion
  (structs : Ir.struct_ list)
  (param_name : string)
  (entry_struct : Ir.struct_)
  (parent_var : string)
  (parent_struct : Ir.struct_)
  (member_name : string)
  : string list * (string * Ir.struct_) list
```

Six parameters and a tuple return type. Hard to call correctly.

### Example 3: gen_nested_struct_conversion

```ocaml
let gen_nested_struct_conversion ...
  : string list * string list * (string * Ir.struct_) list
```

Three-tuple of lists with no indication of what each means.

## Proposed Fix

### Define Explicit Record Types

```ocaml
(** Code generation result for struct creation *)
type struct_creation_result = {
  created_structs : (string * Ir.struct_) list;
  (** List of (variable_name, struct_definition) pairs for all created structs *)

  code_lines : string list;
  (** OCaml code lines that create the structs *)
}

(** Code generation result that includes resources to free *)
type code_with_cleanup = {
  code_lines : string list;
  (** The generated code *)

  structs_to_free : (string * Ir.struct_) list;
  (** List of (variable_name, struct_def) pairs for structs that need freeing *)
}

let generate_struct_creates ... : struct_creation_result = ...

let generate_array_of_structs_conversion ... : code_with_cleanup = ...
```

### Group Related Parameters

```ocaml
(** Context for code generation within a struct *)
type struct_context = {
  all_structs : Ir.struct_ list;
  (** All struct definitions for type lookups *)

  current_struct : Ir.struct_;
  (** The struct being processed *)

  var_prefix : string;
  (** Prefix for generated variable names *)

  var_name : string;
  (** Variable name for the current struct instance *)
}

let generate_struct_creates (ctx : struct_context) : struct_creation_result = ...
```

### Before/After Comparison

Before:
```ocaml
let vars, creates =
  generate_struct_creates structs base_prefix struct_ desc_var in
...
```

After:
```ocaml
let { created_structs; code_lines } =
  generate_struct_creates {
    all_structs = structs;
    current_struct = struct_;
    var_prefix = base_prefix;
    var_name = desc_var
  } in
...
```

## Additional Benefits

1. **Documentation**: Field names document what each component means
2. **Extensibility**: Can add new fields without changing all call sites
3. **Type Safety**: Can't accidentally swap list positions
4. **IDE Support**: Field names provide auto-completion hints

## Estimated Impact

- Medium value: Improves code clarity and reduces bugs
- Low effort: Mostly adding type definitions and updating call sites
