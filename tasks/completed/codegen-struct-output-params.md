# Support struct output parameters in codegen

## Problem

Several methods use an "output struct" pattern where you pass a struct pointer that gets populated by the C function. Currently these are all manual:

- `instance.get_WGSL_language_features` - "Uses struct output parameter"
- `adapter.get_info` - "Uses special struct return"
- `device.get_adapter_info` - "Returns struct"
- `device.get_lost_future` - "Returns Future struct"

## Analysis Needed

1. Look at how these methods are defined in webgpu.yml - do they have a common pattern?
2. Look at the manual implementations in the templates to understand what they do
3. Determine if codegen can be extended to handle this pattern

## Expected Pattern

The C pattern is typically:
```c
void wgpuAdapterGetInfo(WGPUAdapter adapter, WGPUAdapterInfo* info);
```

The OCaml pattern should be:
```ocaml
let get_info t =
  let info = Wgpu_low.Adapter_info.adapter_info_create () in
  Wgpu_low.adapter_get_info t.handle info;
  (* convert info to high-level type or return as-is *)
  info
```

## Implementation

If a method has `returns: void` but has an output parameter (a struct pointer that gets populated), generate code that:
1. Creates the output struct
2. Calls the low-level function with the struct
3. Returns the populated struct (possibly wrapped)

## Notes

- Start with one method (e.g., `adapter.get_info`) to prove the pattern
- Some methods may need to wrap the raw struct in a high-level type

---

## Analysis Results (2026-01-27)

After examining the webgpu.yml definitions, regression test outputs, and codegen code:

### Method Signatures in webgpu.yml

1. **`adapter.get_info`**: Returns `enum.status`, has `struct.adapter_info` as mutable pointer arg
2. **`device.get_adapter_info`**: Returns `struct.adapter_info` directly (no args)
3. **`device.get_lost_future`**: Returns `struct.future` directly (no args)
4. **`instance.get_WGSL_language_features`**: Returns `enum.status`, has `struct.supported_WGSL_language_features` as mutable pointer arg

### Current Codegen Status

1. **`adapter.get_info`**: ALREADY AUTO-GENERATES correctly. The regression test shows it produces valid high-level code. The "manual" flag in config.ml is incorrect - this method can be removed from the manual list.

2. **`device.get_adapter_info`**: NOT auto-generated because `is_simple_return_type` returns false for `Struct _`. Needs new codegen support for methods returning structs directly.

3. **`device.get_lost_future`**: NOT auto-generated for same reason - returns `struct.future` directly.

4. **`instance.get_WGSL_language_features`**: NOT auto-generated because `supported_WGSL_language_features` has an array member (`features: array<enum.WGSL_language_feature_name>`), and `is_simple_output_struct` requires all members to be flat.

### Distinct Patterns Identified

**Pattern A: Output struct via mutable pointer (already supported)**
- `adapter.get_info` - works with current codegen

**Pattern B: Return struct directly (NOT supported)**
- `device.get_adapter_info`
- `device.get_lost_future`
- Would need to handle struct return types in `is_simple_return_type`

**Pattern C: Output struct with array member (NOT supported)**
- `instance.get_WGSL_language_features`
- Similar to `adapter.get_features`, `device.get_features`
- Would need significant work to handle array members in output structs

### Plan

1. Remove `adapter.get_info` from the manual list - it already auto-generates correctly
2. For `device.get_adapter_info` and `device.get_lost_future`: Keep as manual for now - these are a different pattern (struct return by value) that needs separate consideration
3. For `instance.get_WGSL_language_features`: Keep as manual - this is related to the `get_features` methods which need array handling in output structs (separate ticket: codegen-get-features-methods.md)

### Validation Criteria

- Build passes after removing `adapter.get_info` from manual list
- Tests continue to pass
- The manual `Adapter_info` module in templates can be removed since codegen produces the record type

---

## Deeper Analysis: Why These Methods Should Stay Manual

After further investigation, I found that the situation is more nuanced:

### `adapter.get_info` - Should Stay Manual

The codegen CAN produce code for this method, but:
1. The **low-level** has a custom manual implementation that returns an `adapter_info` record directly (not via struct pointer)
2. The C stub uses `WGPUAdapterInfo info = {0}; wgpuAdapterGetInfo(adapter, &info);` pattern internally
3. The high-level template has `Adapter_info.of_low` which converts from low-level record to high-level record

If we removed the manual flag:
- The high-level codegen would produce code that calls `Wgpu_low.adapter_get_info t.handle output`
- But the low-level signature is `adapter_get_info : adapter -> adapter_info` (no output param!)
- These don't match!

The current architecture with manual implementations is cleaner and more direct.

### `device.get_adapter_info` and `device.get_lost_future` - Need Low-Level Work First

These methods return structs BY VALUE in the C API. Looking at the generated C stubs:

```c
CAMLprim value caml_wgpu_device_get_lost_future(value self) {
  /* TODO: return type */
  wgpuDeviceGetLostFuture(c_self);  // Result is discarded!
  CAMLreturn(Val_unit);
}
```

The low-level codegen doesn't handle struct return types - it just ignores the return value. To fix this:
1. Low-level C needs to allocate memory and copy the returned struct
2. Low-level OCaml needs updated signatures
3. High-level needs support for struct returns

This is a multi-layer fix beyond the scope of this task.

### `instance.get_WGSL_language_features` - Related to get_features Methods

This has an output struct with an array member. Same pattern as `adapter.get_features` and `device.get_features`. These need special handling for array getters in output structs - tracked in separate ticket.

## Conclusion

**All four methods should remain manual.** The reasons are:
1. `adapter.get_info`: Works well with current manual implementation; codegen would produce incompatible code
2. `device.get_adapter_info`: Low-level codegen bug - doesn't handle struct returns
3. `device.get_lost_future`: Low-level codegen bug - doesn't handle struct returns
4. `instance.get_WGSL_language_features`: Output struct has array member - same issue as get_features

**No code changes needed.** This analysis documents why these methods are correctly marked as manual.
