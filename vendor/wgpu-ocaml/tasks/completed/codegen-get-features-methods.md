# Auto-generate get_features methods

## Problem

Both `adapter.get_features` and `device.get_features` are marked manual with reason "Output struct with array member". They likely have identical patterns and could be auto-generated.

## Analysis Needed

1. Look at the webgpu.yml definitions for these methods
2. Look at the current manual implementations (if any exist)
3. Understand what "output struct with array member" means in this context

## Expected Pattern

The `SupportedFeatures` struct likely contains an array of feature flags. The codegen needs to:
1. Create the output struct
2. Call the C function to populate it
3. Extract the array contents into an OCaml list or array

## Implementation

This is related to the struct-output-params task but specifically handles the case where the output struct contains array members that need to be converted to OCaml collections.

## Methods

- `adapter.get_features`
- `device.get_features`

## Analysis

### Investigation Summary (2026-01-27)

After thorough investigation, I found these methods **cannot be easily auto-generated** at this time. Here is why:

### 1. The SupportedFeatures struct has two blocking issues:

**Issue A: Struct type mismatch**
The `SupportedFeatures` struct is defined as type `standalone` with `free_members: true` in webgpu.yml:
```yaml
- name: supported_features
  type: standalone
  free_members: true
  members:
    - name: features
      type: array<enum.feature_name>
      pointer: immutable
```

The high-level codegen's `is_simple_output_struct` function (gen_high.ml:161-173) only considers structs that are `Base_out | Base_in_out | Extension_out` as valid output structs. The `Standalone` type does not qualify.

**Issue B: Missing C getter for array member**
The low-level C stub for `supported_features_get_features` (wgpu_low_stubs.c:6911-6916) is a TODO:
```c
CAMLprim value caml_wgpu_supported_features_get_features(value handle) {
  CAMLparam1(handle);
  WGPUSupportedFeatures *s = (WGPUSupportedFeatures *)Nativeint_val(handle);
  (void)s; /* TODO: getter for features */
  CAMLreturn(Val_unit);
}
```

There is no implementation to read the array back from the C struct into OCaml.

### 2. What would be needed to auto-generate:

1. **Low-level**: Implement array getters in gen_low.ml that can read arrays from C structs back to OCaml. This requires:
   - Reading `featureCount` and `features` pointer from the struct
   - Allocating an OCaml array
   - Converting each C enum value to OCaml int

2. **High-level**: Extend `is_simple_output_struct` to handle `Standalone` structs, OR create a special case for structs with array-of-enum members.

3. **Alternative**: The methods could use a pattern similar to how `adapter.get_info` works - manually call the low-level function, read the data, and return a high-level type.

### Decision: Keep as Manual

These methods should remain marked as Manual because:

1. The array getter infrastructure in the low-level bindings does not exist
2. The struct type system in gen_high.ml would need modification
3. There are no existing manual implementations in the template files that need fixing
4. The `has_feature` method already exists and provides the essential functionality (checking if a specific feature is supported)

If `get_features` is needed, it should be manually implemented in the adapter/device module prefixes similar to `get_info`.

## Validation Criteria

- Build passes with `dune build`
- No warnings from `dune build @check`
- Tests pass with `dune exec test/test_compute.exe`
- Task file moved to completed with this analysis
