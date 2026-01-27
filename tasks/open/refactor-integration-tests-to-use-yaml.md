# Refactor Integration Tests to Use Inline YAML

## Problem

The current integration tests in `codegen/test/` define IR values (e.g., `Ir.enum`, `Ir.struct_`, `Ir.method_`) as OCaml record literals at the top of each test file. These are then reused across multiple `%expect_test` blocks, with each test asserting only a single output type (e.g., low-level ML, high-level MLI).

This approach has several drawbacks:
1. **Test fragmentation** - Understanding what a given YAML input produces requires reading multiple separate tests
2. **IR vs YAML gap** - Tests use hand-crafted IR records, but the actual system parses YAML; bugs in YAML parsing won't be caught
3. **Maintenance burden** - Adding a new enum/struct requires adding OCaml records, not just copying YAML snippets from the spec

## Current State

Example from `test_enums.ml`:
```ocaml
let simple_enum : Ir.enum =
  { name = "texture_format"
  ; doc = "Texture pixel formats"
  ; entries = [ ... ]
  }

let%expect_test "Gen_low.gen_ml_enum - simple enum" =
  print_endline (Gen_low.gen_ml_enum simple_enum);
  [%expect {| ... |}]

let%expect_test "Gen_low.gen_mli_enum - simple enum" =
  print_endline (Gen_low.gen_mli_enum simple_enum);
  [%expect {| ... |}]

(* ... 3 more tests for the same enum ... *)
```

## Proposed Solution

Restructure each test to:
1. Define the input as an inline YAML string
2. Parse the YAML using `Parse_yml`
3. Assert all generated outputs in a single test

### New Test Structure

```ocaml
let%expect_test "enum - texture_format" =
  let yaml = {|
name: texture_format
doc: Texture pixel formats
entries:
  - name: rgba8_unorm
    doc: RGBA 8-bit unsigned normalized
  - name: bgra8_unorm
    doc: BGRA 8-bit unsigned normalized
|} in
  let enum = Parse_yml.parse_enum (Yaml.of_string_exn yaml) in

  print_endline "=== Low-level C ===";
  print_endline (Gen_low.gen_c_enum_constants enum);
  [%expect {| ... |}];

  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.gen_mli_enum enum);
  [%expect {| ... |}];

  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.gen_ml_enum enum);
  [%expect {| ... |}];

  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.gen_mli_enum enum);
  [%expect {| ... |}];

  print_endline "=== High-level ML ===";
  print_endline (Gen_high.gen_ml_enum enum);
  [%expect {| ... |}]
;;
```

## Implementation Steps

1. **Update `codegen/test/dune`** to add `yaml` as a dependency:
   ```
   (libraries yaml core codegen_lib)
   ```

2. **Update `codegen_lib.ml`** (or dune) to expose `Parse_yml` if not already exposed

3. **Refactor `test_enums.ml`**:
   - Replace OCaml IR definitions with inline YAML strings
   - Consolidate per-output tests into single per-input tests
   - Each test asserts: C code, low-level MLI, low-level ML, high-level MLI, high-level ML

4. **Refactor `test_structs.ml`**:
   - Same pattern: YAML string → parse → assert all 5 outputs
   - Include tests for different struct types (standalone, base_in, extension_in, base_out)

5. **Refactor `test_methods.ml`**:
   - More complex since methods require parent object context
   - May need to define minimal object YAML with the method under test
   - Assert all 5 outputs per method

6. **Keep `test_types.ml`, `test_helpers.ml`, `test_names.ml` as-is**:
   - These test pure functions and helper logic, not end-to-end codegen
   - They don't need YAML input

## Benefits

1. **End-to-end testing** - Tests exercise YAML parsing through code generation
2. **Single source of truth** - Each test shows input YAML and all expected outputs together
3. **Easier maintenance** - Can copy YAML snippets directly from `webgpu.yml` to create tests
4. **Better documentation** - Tests serve as examples of YAML → generated code

## Validation Criteria

- All existing expect tests still pass (output unchanged, just reorganized)
- `dune build @check` passes with no warnings
- Each integration test (enum, struct, method) follows the pattern:
  - Define YAML string
  - Parse YAML
  - Assert C code output
  - Assert low-level MLI output
  - Assert low-level ML output
  - Assert high-level MLI output
  - Assert high-level ML output
