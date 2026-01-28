# Fix Optional Object Parameter Codegen Bug

## Problem

The code generator incorrectly handles optional object parameters. When a method has an optional parameter that should be an object type (like `Pipeline_layout.t`), the codegen generates a string default instead of a proper object default.

**Example from `device.create_compute_pipeline` regression test:**

```ocaml
(* Generated MLI - correct *)
val create_compute_pipeline : t -> ?label:string -> ?layout:Pipeline_layout.t -> ...

(* Generated ML - incorrect! *)
let create_compute_pipeline t ?(label = "") ?(layout = "") ~compute_module ...
  ...
  Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_layout
    desc_descriptor layout.Pipeline_layout.handle;  (* This fails! *)
```

The `?(layout = "")` is wrong because:
1. The type should be `Pipeline_layout.t`, not `string`
2. Later code tries to access `layout.Pipeline_layout.handle` which fails on a string
3. For optional object params, we need either a nullable handle or to skip setting the field entirely

## Root Cause

In `codegen/gen_high.ml`, when generating optional parameters for descriptor struct fields that are object types, the code uses the same string default logic as for label fields.

## Solution Options

### Option A: Use Nullable Handles
For optional object parameters, use `?layout:Pipeline_layout.t` and pass `0n` (null) when not provided:

```ocaml
let create_compute_pipeline t ?(label = "") ?layout ~compute_module ...
  ...
  (match layout with
   | Some l -> Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_layout
                 desc_descriptor l.Pipeline_layout.handle
   | None -> ());  (* Don't set it, or set to 0n for null *)
```

### Option B: Make Required with Default
Change the signature to require a layout but provide a helper:

```ocaml
let create_compute_pipeline t ?(label = "") ~layout ~compute_module ...
```

Option A is preferred as it matches the webgpu spec where layout is optional.

## Files to Modify

- `codegen/gen_high.ml` - Fix optional parameter handling for object types in method generation

## Testing

1. Run `dune build` to regenerate code
2. Check that `device.create_compute_pipeline` in wgpu.ml has correct optional parameter handling
3. Run `dune exec test/test_compute.exe` - tests should still pass
4. Run `dune build @check` - no warnings

## Related Methods

This fix would also affect any other methods with optional object parameters. Check the regression tests for similar patterns.

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. Generated code for `create_compute_pipeline` has proper `?layout:Pipeline_layout.t option` handling
4. If the codegen is fixed, consider removing `device.create_compute_pipeline` from the Manual list in config.ml

## Implementation Plan

The fix involves two main changes to `codegen/gen_high.ml`:

1. **Modify `default_value_for_type`**: For `Optional (Object _)` types, we should NOT provide a default value. Instead, we need to generate `?param` without a default (meaning the parameter becomes `'a option`).

2. **Modify `build_param_list`**: When detecting an optional object parameter, generate `?param_name` instead of `?(param_name = default)`.

3. **Modify `generate_struct_sets`**: When setting fields for optional object parameters, wrap the setter call in a `match` statement that only calls the setter when `Some value` is provided.

The key insight is that when the member type is `Optional (Object name)`, we need to:
- In the signature (MLI): already generates `?layout:Pipeline_layout.t` (correct)
- In the implementation (ML): generate `?layout` (no default) and wrap the setter in pattern matching

### Implementation Steps

1. Modify `default_value_for_type` to return a special marker or use a different approach for optional objects
2. Update `build_param_list` to handle optional object parameters specially (no default value)
3. Update `generate_struct_sets` to wrap optional object setters in `match` statements

### Expected Output

```ocaml
let create_compute_pipeline t ?(label = "") ?layout ~compute_module ~compute_entry_point ?(compute_constants = []) () =
  ...
  (match layout with
   | Some l -> Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_layout
                 desc_descriptor l.Pipeline_layout.handle
   | None -> ());
  ...
```
