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
