# Reduce Duplicated Logic Between ML/MLI Generation

## Problem

Many generation functions come in pairs that are nearly identical:
- `gen_ml_enum` / `gen_mli_enum`
- `gen_ml_bitflag` / `gen_mli_bitflag`
- `gen_ml_struct` / `gen_mli_struct`
- `gen_ml_object` / `gen_mli_object`
- `gen_ml_method` / `gen_mli_method`
- `gen_ml_method_with_structs` / `gen_mli_method_with_structs`
- `gen_ml_method_with_output_struct` / `gen_mli_method_with_output_struct`
- `gen_entry_struct_module` / `gen_entry_struct_module_mli`
- `gen_nested_struct_module` / `gen_nested_struct_module_mli`

These pairs typically differ only in:
- Whether to include implementation bodies vs just signatures
- Whether to use `let` vs `val`
- Whether to include `external` declarations vs just type signatures

## Example: Duplicated Pattern

```ocaml
(* gen_ml_enum - 20 lines *)
let gen_ml_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants = ... in
  let to_int_cases = ... in
  let of_int_cases = ... in
  ...

(* gen_mli_enum - 15 lines, shares same structure *)
let gen_mli_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants = ... in  (* Same! *)
  sprintf "module %s : sig\n  type t =\n%s\n\n  val to_int : t -> int\n  ..."
```

## Proposed Fix

### Option A: Parameterized Generation

Use a variant to indicate output mode:

```ocaml
type output_mode =
  | Implementation
  | Interface

let gen_enum (mode : output_mode) (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants = ... in  (* Shared *)
  match mode with
  | Implementation ->
      sprintf "module %s = struct\n  type t = ...\n  let to_int = ...\n"
  | Interface ->
      sprintf "module %s : sig\n  type t = ...\n  val to_int : ...\n"
```

### Option B: Structured Intermediate Representation

Generate an intermediate structure, then render it:

```ocaml
type module_content = {
  name : string;
  type_decl : string;
  functions : (string * string * string option) list;  (* name, type, impl option *)
}

let enum_to_module_content (enum : Ir.enum) : module_content = ...

let render_ml (content : module_content) : string = ...
let render_mli (content : module_content) : string = ...
```

### Option C: Paired Generation

Return both at once:

```ocaml
let gen_enum (enum : Ir.enum) : string * string =
  let module_name = ... in
  let variants = ... in  (* Compute once *)
  let ml = sprintf "module %s = struct ..." in
  let mli = sprintf "module %s : sig ..." in
  ml, mli
```

## Recommendation

Option A is the simplest to implement and reduces duplication significantly. It's
particularly good for the common case where ML and MLI differ only in syntax.

Option B is more powerful but requires more upfront design work. It would be
valuable if we need to support additional output formats (e.g., documentation).

## Benefits

1. Single source of truth for type structures
2. Reduced risk of ML/MLI getting out of sync
3. Easier to add new features (add once, works for both)
4. ~30-40% reduction in code size

## Estimated Impact

- High value: Eliminates common source of bugs (mismatched ML/MLI)
- Medium effort: Requires careful refactoring
