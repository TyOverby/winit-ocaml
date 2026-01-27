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

### Example: Name Transformation Tests

```ocaml
(* test_names.ml *)
open! Core

let%expect_test "to_pascal_case basic" =
  print_endline (Gen_low.to_pascal_case "texture_format");
  [%expect {| TextureFormat |}]

let%expect_test "to_pascal_case with double underscore" =
  print_endline (Gen_low.to_pascal_case "extent_3D");
  [%expect {| Extent3D |}]

let%expect_test "to_pascal_case already pascal" =
  print_endline (Gen_low.to_pascal_case "Device");
  [%expect {| Device |}]

let%expect_test "normalize_enum_entry_name with leading digit" =
  print_endline (Gen_low.normalize_enum_entry_name "2d");
  [%expect {| N2d |}]

let%expect_test "normalize_enum_entry_name GPU" =
  print_endline (Gen_low.normalize_enum_entry_name "discrete_GPU");
  [%expect {| Discrete_gpu |}]
```

### Example: Type Mapping Tests

```ocaml
(* test_types.ml *)
open! Core

let%expect_test "c_type_of_type_ref primitives" =
  List.iter [Ir.Primitive Bool; Ir.Primitive Uint32; Ir.Primitive String]
    ~f:(fun t -> print_endline (Gen_low.c_type_of_type_ref t));
  [%expect {|
    bool
    uint32_t
    WGPUStringView
  |}]

let%expect_test "high_level_arg_type enum" =
  print_endline (Gen_high.high_level_arg_type (Ir.Enum "texture_format"));
  [%expect {| Texture_format.t |}]
```

### Example: Integration Tests

```ocaml
(* test_enums.ml *)
open! Core

let sample_enum : Ir.enum = {
  name = "load_op";
  doc = "Defines how a render pass loads data from an attachment.";
  entries = [
    { name = "undefined"; doc = ""; value = None };
    { name = "clear"; doc = "Clear the attachment"; value = None };
    { name = "load"; doc = "Load existing content"; value = None };
  ]
}

let%expect_test "gen_ml_enum simple" =
  print_endline (Gen_low.gen_ml_enum sample_enum);
  [%expect {|
    module Load_op = struct
      type t =
      | Undefined
      | Clear
      | Load

    external load_op_undefined : unit -> int = "caml_wgpu_load_op_undefined"
    ...
  |}]
```

### Snapshot Testing for Larger Outputs

For larger generated outputs, use file-based snapshots:

```ocaml
let%expect_test "full low-level enum generation" =
  let api = (* minimal API with one enum *) in
  let output = Gen_low.gen_ml api in
  (* Check key structural elements rather than exact output *)
  assert (String.is_substring output ~substring:"module Load_op");
  assert (String.is_substring output ~substring:"let to_int = function");
  [%expect {| |}]
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
