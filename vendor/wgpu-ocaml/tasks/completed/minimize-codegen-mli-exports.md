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

---

## Implementation Plan

Based on code analysis, here is the plan:

### Analysis Summary

**gen_bindings.ml** (the main entry point) uses:
- `Gen_high.gen_ml`, `Gen_high.gen_mli`, `Gen_high.check_method_coverage`
- `Gen_high.gen_enums_ml`, `Gen_high.gen_enums_mli`, `Gen_high.gen_bitsets_ml`, `Gen_high.gen_bitsets_mli`
- `Gen_low.gen_ml`, `Gen_low.gen_mli`, `Gen_low.gen_c_stubs`
- `Parse_yml.load_file`

**Test files** use many additional functions for unit testing.

### Changes for gen_high.mli

**Keep public:**
- `gen_ml`, `gen_mli` (main API)
- `gen_enums_ml`, `gen_enums_mli`, `gen_bitsets_ml`, `gen_bitsets_mli` (used by gen_bindings)
- `check_method_coverage`, `validate_method_coverage` (validation)

**Move to For_testing:**
- `gen_ml_enum`, `gen_mli_enum`, `gen_ml_bitflag`, `gen_mli_bitflag` (tested individually)
- `gen_ml_method`, `gen_mli_method` (tested individually)
- `gen_ml_method_with_output_struct`, `gen_mli_method_with_output_struct` (tested)
- `is_flat_member_type`, `is_directly_convertible_arg` (tested)
- `method_is_async`, `get_inline_struct_name`, `member_is_array_of_structs` (tested)
- `escape_keyword`, `useful_doc` (tested)

**Remove from .mli (internal only):**
- `output_mode` type
- `struct_parameter`, `struct_creation_result`, `code_with_cleanup`, `inline_struct_conversion` types
- `method_is_high_level_simple`, `method_is_high_level`, `is_auto_generable_struct`
- `gen_enum`, `gen_bitflag`, `gen_object`, `gen_method`
- `gen_ml_object`, `gen_mli_object`
- `gen_array_element_struct_module`, `collect_array_element_structs`
- `gen_special_object_auto_methods`, `gen_special_object_auto_methods_mli`
- `sort_objects`

### Changes for gen_low.mli

**Keep public:**
- `gen_c_stubs`, `gen_ml`, `gen_mli` (main API)

**Move to For_testing:**
- `gen_ml_enum`, `gen_mli_enum` (tested)
- `gen_ml_struct`, `gen_mli_struct` (tested)
- `gen_ml_method`, `gen_mli_method` (tested)
- `gen_c_enum_constants`, `gen_c_bitflag_constants`, `gen_c_struct_stubs`, `gen_c_method_stub` (tested)
- `c_type_of_type_ref`, `ml_type_of_type_ref` (tested)
- `to_pascal_case`, `to_camel_case`, `c_type_name`, `c_function_name`, `ocaml_module_name`, `normalize_enum_entry_name` (tested)

**Remove from .mli (internal only):**
- `output_mode` type
- `gen_ml_bitflag`, `gen_mli_bitflag` (not tested directly)
- `gen_ml_object`, `gen_mli_object` (not tested directly)
- `gen_c_function_stubs` (not tested)
- `c_method_name` (not tested)
- `gen_c_object_stubs` (not tested)

### Changes for names.mli

All functions here are used by other modules (gen_low, gen_high), so they should remain public.
No changes needed.

### Changes for config.mli, type_mapping.mli, predicates.mli, parse_yml.mli

These are used by gen_low.ml and gen_high.ml internally, and by tests.
- `type_mapping.mli`: Most functions tested directly, move to For_testing
- `predicates.mli`: Only has `method_is_async`, used internally - keep as is
- `config.mli`: Used internally, no tests - keep as is
- `parse_yml.mli`: Only `load_file` used - keep as is

### Validation Criteria

1. `dune build` succeeds
2. `dune build @check` shows no warnings
3. `dune exec test/test_compute.exe` passes
4. All expect tests pass (`dune runtest codegen`)
5. Generated code is unchanged (build output files should be identical)
