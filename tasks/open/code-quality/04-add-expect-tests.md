# Add Expect Tests for Generator Functions

## Problem

The codegen library has no tests. This makes refactoring risky because:
1. Changes might subtly break output
2. No way to verify expected behavior
3. Hard to understand intended behavior from code alone
4. Regressions can go unnoticed

## Current State

All testing is done implicitly:
- `dune build` regenerates bindings
- Manual testing of test programs
- No automated verification of generator output

## Proposed Fix

Add Jane Street-style expect tests for key generator functions.

### Test Structure

```
codegen/
  test/
    dune
    test_names.ml       # Tests for name transformations
    test_types.ml       # Tests for type mapping
    test_enums.ml       # Tests for enum generation
    test_structs.ml     # Tests for struct generation
    test_methods.ml     # Tests for method generation
```

### Example: Integration Tests

```ocaml
(* test_enums.ml *)
open! Core


let%expect_test "enum" =
  let sample_enum = {yaml| ... the yaml for a type ... |yaml}

  (* low level *)
  print_endline (Gen_low.gen_c sample_enum);
  [%expect {| ... output ... |}];
  print_endline (Gen_low.gen_ml sample_enum);
  [%expect {| ... output ... |}];
  print_endline (Gen_low.gen_mli sample_enum);
  [%expect {| ... output ... |}];

  (* high level *)
  print_endline (Gen_high.gen_ml sample_enum);
  [%expect {| ... output ... |}];
  print_endline (Gen_high.gen_mli sample_enum);
  [%expect {| ... output ... |}];
```

## Benefits

1. Safe refactoring - tests catch regressions
2. Documentation - tests show expected behavior
3. Design feedback - hard-to-test code reveals design issues
4. Confidence - can make changes without fear

## Incremental Adoption

Start with the most foundational functions:
1. Name transformations (easy, pure functions)
2. Type mapping (still pure, but more complex)
3. Simple generators (enums, bitflags)
4. Complex generators (methods with structs)

## Estimated Impact

- High value: Enables safe refactoring of everything else
- Medium effort: Tests can be added incrementally

## Status Update (2026-01-27)

**Completion: ~40% - Partially Complete**

### What Has Been Done ✅

Steps 1-2 of the "Incremental Adoption" plan have been completed:

1. **Name transformation tests** - `codegen/test/test_names.ml` (114 lines)
   - Tests for: to_pascal_case, to_camel_case, c_type_name, c_function_name, ocaml_module_name, normalize_enum_entry_name, escape_keyword
   - All use proper Jane Street expect test format

2. **Type mapping tests** - `codegen/test/test_types.ml` (160 lines)
   - Tests for: c_type_of_type_ref, ml_type_of_type_ref
   - Coverage: primitives, enums, bitflags, structs, objects, arrays, optionals, pointers

3. **Helper function tests** - `codegen/test/test_helpers.ml` (188 lines)
   - Tests for: is_flat_member_type, is_directly_convertible_arg, method_is_async, get_inline_struct_name, member_is_array_of_structs, useful_doc

4. **Test infrastructure** - Proper dune configuration and all tests pass with `dune runtest`

### What Remains ❌

Steps 3-4 of the "Incremental Adoption" plan - the **critical integration tests** are missing:

1. **`test_enums.ml`** - Tests for full enum code generation:
   - Create sample `Ir.enum` structures
   - Test `Gen_low.gen_ml_enum`, `Gen_low.gen_mli_enum`, `Gen_low.gen_c_enum_constants`
   - Test `Gen_high.gen_ml_enum`, `Gen_high.gen_mli_enum`
   - Cover edge cases: empty enums, single entry, multiple entries, with/without explicit values

2. **`test_structs.ml`** - Tests for struct code generation:
   - Create sample `Ir.struct_` structures with different `struct_type` values
   - Test `Gen_low.gen_ml_struct`, `Gen_low.gen_mli_struct`, `Gen_low.gen_c_struct_stubs`
   - Cover: standalone structs, base structs with nextInChain, extension structs, nested structs, arrays

3. **`test_methods.ml`** - Tests for method code generation:
   - Create sample `Ir.method_` structures
   - Test `Gen_low.gen_ml_method`, `Gen_low.gen_mli_method`, `Gen_low.gen_c_method_stub`
   - Test `Gen_high.gen_ml_method`, `Gen_high.gen_mli_method`
   - Cover: sync vs async, methods with structs, methods with output structs, methods with arrays

4. **Optional: `test_bitflags.ml` and `test_objects.ml`** for comprehensive coverage

These integration tests are the highest value proposition - they verify the actual code generation and enable safe refactoring of the complex generator logic.
