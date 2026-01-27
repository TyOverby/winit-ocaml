# Regression Tests Using Real webgpu.yml

## Problem

The current integration tests use self-contained inline YAML snippets. While this is good for unit testing specific scenarios, it doesn't catch regressions when the real `webgpu.yml` file changes or when codegen changes affect actual API types.

We need regression tests that:
1. Pull from the real `vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml` file
2. Allow test authors to specify items by name (type, method, struct, enum, etc.)
3. Show the generated code for those specific items as expect test output

## Proposed Solution

Create a new test file (e.g., `codegen/test/test_regression.ml`) that:

1. Parses the real `webgpu.yml` at test time
2. Provides helper functions to look up items by name
3. Uses expect tests to snapshot the generated output

### Example Test Structure

```ocaml
let%expect_test "enum - texture_format" =
  let enum = lookup_enum "texture_format" in
  print_all_outputs_for_enum enum;
  [%expect {|
    === Low-level C ===
    ...
    === Low-level ML ===
    ...
    === High-level ML ===
    ...
  |}]
;;

let%expect_test "struct - buffer_descriptor" =
  let struct_ = lookup_struct "buffer_descriptor" in
  print_all_outputs_for_struct struct_;
  [%expect {| ... |}]
;;

let%expect_test "method - device.create_buffer" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_buffer" in
  print_all_outputs_for_method ~parent_object:obj method_;
  [%expect {| ... |}]
;;
```

### Helper Module

Create helpers to:
- Load and cache the parsed YAML (parse once, reuse across tests)
- Look up items by name with clear error messages if not found
- Print all generated outputs (C, low ML, low MLI, high ML, high MLI) in a consistent format

```ocaml
(* In test_regression.ml or a helper module *)

let ir = lazy (Parse_yml.parse_file "vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml")

let lookup_enum name =
  let ir = Lazy.force ir in
  List.find_exn ir.enums ~f:(fun e -> String.equal e.name name)

let lookup_struct name = ...
let lookup_object name = ...

let print_all_outputs_for_enum enum =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.gen_c_enum_constants enum);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.gen_mli_enum enum);
  (* ... etc ... *)
```

## Benefits

1. **Regression detection** - Changes to codegen that affect real API types are immediately visible in diffs
2. **Documentation** - Tests serve as examples of what the generated code looks like for real types
3. **Confidence** - Can add tests for complex/tricky types from the actual spec
4. **Complementary** - Works alongside unit tests with synthetic YAML for edge cases

## Implementation Steps

1. Add a mechanism to locate `webgpu.yml` relative to the test (may need dune rules or an environment variable)
2. Create lookup helpers that parse the YAML once and provide name-based access
3. Add initial regression tests for a representative set of:
   - Simple enum (e.g., `texture_format`)
   - Enum with value overrides
   - Simple struct (e.g., `limits`)
   - Struct with chained types
   - Struct with arrays
   - Method with simple args
   - Method with struct args
4. Run `dune runtest` to capture initial snapshots

## Validation Criteria

- `dune build @check` passes with no warnings
- Tests load the real `webgpu.yml` successfully
- Each test shows the full generated output for the named item
- Adding a new regression test is straightforward (just specify the name)
