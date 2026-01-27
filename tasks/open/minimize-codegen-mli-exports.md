# Minimize Code Generator .mli Exports

The `.mli` files in `codegen/` currently export many internal helper functions that are not part of the true public API. This makes the interfaces harder to understand and clutters the API surface.

## Goal

Go through each `.mli` file in `codegen/` and:

1. **Remove exports** for functions that aren't used outside their module
2. **Move test-only functions** to a `For_testing` submodule

## Files to Review

### `gen_high.mli`

Currently exports many internal helpers that should be hidden or moved to `For_testing`:
- `is_flat_member_type`
- `is_directly_convertible_arg`
- `get_inline_struct_name`
- `member_is_array_of_structs`
- `escape_keyword` (re-exported from Names)
- `useful_doc` (re-exported from Names)
- Individual generators like `gen_ml_enum`, `gen_mli_enum`, `gen_ml_bitflag`, etc.
- Various type definitions (`struct_parameter`, `struct_creation_result`, etc.)

The core public API should probably just be:
```ocaml
val gen_ml : Ir.api -> string
val gen_mli : Ir.api -> string
val check_method_coverage : Ir.api -> unit
```

### `gen_low.mli`

Similar issue - exports many individual generators that are likely only used for testing:
- `gen_c_enum_constants`
- `gen_c_bitflag_constants`
- `gen_c_struct_stubs`
- `gen_c_object_stubs`
- `gen_ml_enum`, `gen_mli_enum`, etc.
- Type mapping utilities (`c_type_of_type_ref`, `ml_type_of_type_ref`)
- Re-exported naming utilities

Core public API should be:
```ocaml
val gen_c_stubs : Ir.api -> string
val gen_ml : Ir.api -> string
val gen_mli : Ir.api -> string
```

### `names.mli`

Review whether `ocaml_keywords`, `indent_lines`, `read_template`, and `useful_doc` need to be exported at the top level or should be in `For_testing`.

### Other files

Review `config.mli`, `type_mapping.mli`, `predicates.mli`, and `parse_yml.mli` for similar issues.

## Implementation

For each module:
1. Search the codebase for uses of each exported function
2. If only used internally, remove from `.mli`
3. If only used in tests, move to `For_testing` submodule
4. Update test files to use `Module.For_testing.function_name`
5. Run `dune build @check` to verify no warnings
6. Run tests to ensure nothing broke

## Example For_testing Pattern

```ocaml
(** Primary public API *)
val gen_ml : Ir.api -> string
val gen_mli : Ir.api -> string

(** Functions exposed for testing only *)
module For_testing : sig
  val gen_ml_enum : Ir.enum -> string
  val is_flat_member_type : Ir.type_ref -> bool
end
```
