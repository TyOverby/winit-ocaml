# Separate Concerns in Method Generation

## Problem

Method generation functions in gen_high.ml mix multiple concerns:
1. Determining what kind of method this is
2. Collecting parameters
3. Generating struct creation code
4. Generating field setting code
5. Generating the method call
6. Generating cleanup code
7. Generating the return handling

`gen_ml_method_with_structs` is 108 lines and does all of these.

## Current Structure

```ocaml
let gen_ml_method_with_structs
  (structs : Ir.struct_ list)
  (obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_args : (Ir.arg * Ir.struct_) list)
  : string
  =
  (* 1. Setup - get method name, check prefix needs *)
  let method_name = escape_keyword method_.name in
  let use_prefix = List.length struct_args > 1 in

  (* 2. Collect non-struct args *)
  let other_args = List.filter method_.args ~f:(...) in

  (* 3. Build parameter list from struct members *)
  let struct_params = List.concat_map struct_args ~f:(...) in

  (* 4. Build function signature *)
  let param_strs = ... in

  (* 5. Generate struct creation for each arg *)
  let all_struct_vars, create_structs_lists = ... in

  (* 6. Generate field setting *)
  let set_fields, entry_struct_lists = ... in

  (* 7. Build call args *)
  let call_args = ... in
  let call = ... in

  (* 8. Generate cleanup code *)
  let free_entry_lists = ... in
  let free_structs = ... in

  (* 9. Generate result handling *)
  let result_and_free = ... in

  (* 10. Combine everything *)
  let body_lines = create_structs @ set_fields @ [ result_and_free ] in
  sprintf "  let %s %s =\n    %s\n" method_name param_list body
```

## Proposed Decomposition

### Step 1: Define Intermediate Types

```ocaml
(** Analyzed method structure *)
type method_analysis = {
  method_name : string;
  struct_params : struct_param list;
  other_params : other_param list;
  return_type : Ir.type_ref option;
}

and struct_param = {
  param_name : string;
  member : Ir.struct_member;
  is_optional : bool;
  parent_var : string option;  (* For nested structs *)
}

and other_param = {
  param_name : string;
  arg : Ir.arg;
  is_optional : bool;
}

(** Generated code components *)
type method_code = {
  signature : string;
  struct_creates : string list;
  field_sets : string list;
  method_call : string;
  cleanup : string list;
  result_handling : string;
}
```

### Step 2: Separate Analysis from Generation

```ocaml
(** Analyze a method to determine its structure *)
let analyze_method
  (structs : Ir.struct_ list)
  (obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_args : (Ir.arg * Ir.struct_) list)
  : method_analysis
  = ...

(** Generate the function signature *)
let gen_signature (analysis : method_analysis) : string = ...

(** Generate struct creation code *)
let gen_struct_creates
  (structs : Ir.struct_ list)
  (struct_args : (Ir.arg * Ir.struct_) list)
  : string list * (string * Ir.struct_) list
  = ...

(** Generate field setting code *)
let gen_field_sets
  (structs : Ir.struct_ list)
  (analysis : method_analysis)
  (struct_vars : (string * Ir.struct_) list)
  : string list * (string * Ir.struct_) list
  = ...

(** Generate the method call *)
let gen_method_call
  (obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_arg_names : Set.M(String).t)
  : string
  = ...

(** Generate cleanup code *)
let gen_cleanup
  (struct_vars : (string * Ir.struct_) list)
  (entry_lists : (string * Ir.struct_) list)
  : string list
  = ...

(** Assemble the complete method *)
let assemble_method (code : method_code) : string = ...
```

### Step 3: Main Function Becomes Orchestrator

```ocaml
let gen_ml_method_with_structs structs obj method_ struct_args =
  let analysis = analyze_method structs obj method_ struct_args in
  let signature = gen_signature analysis in
  let struct_creates, struct_vars = gen_struct_creates structs struct_args in
  let field_sets, entry_lists = gen_field_sets structs analysis struct_vars in
  let call = gen_method_call obj method_ (get_struct_arg_names struct_args) in
  let cleanup = gen_cleanup struct_vars entry_lists in
  let result = gen_result_handling method_.returns cleanup call in
  assemble_method { signature; struct_creates; field_sets; method_call = call; cleanup; result_handling = result }
```

## Benefits

1. **Testable components** - can test each step independently
2. **Readable flow** - main function shows high-level logic
3. **Reusable parts** - e.g., signature generation can be shared
4. **Easier debugging** - can inspect intermediate results
5. **Simpler modifications** - change one concern without touching others

## Estimated Impact

- High value: Makes the most complex code much more maintainable
- High effort: Significant restructuring required
