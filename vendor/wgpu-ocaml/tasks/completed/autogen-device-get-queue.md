# Auto-generate device.get_queue Instead of Hardcoding

## Problem

The `device.get_queue` method is currently hardcoded in `codegen/templates/high/adapter_module_prefix.ml` and marked as `Manual` in `codegen/config.ml`. However, the code generator now produces identical code:

**Template version (adapter_module_prefix.ml:39):**
```ocaml
let get_queue t = { Queue.handle = Wgpu_low.device_get_queue t.handle }
```

**Codegen version (from regression test):**
```ocaml
let get_queue t = ({ Queue.handle = Wgpu_low.device_get_queue t.handle } : Queue.t)
```

These are functionally identical. The Device module already has an injection point for auto-generated methods (`(* AUTO-GENERATED DEVICE METHODS INJECTED HERE *)`), so this is a straightforward change.

## Task

1. Remove `("device", "get_queue")` from the `Manual` list in `codegen/config.ml`
2. Remove the `get_queue` implementation from `codegen/templates/high/adapter_module_prefix.ml`
3. Remove the `get_queue` signature from `codegen/templates/high/adapter_module_prefix.mli`
4. Rebuild and verify the generated code is correct

## Files to Modify

- `codegen/config.ml` - Remove `("device", "get_queue")` from `method_config`
- `codegen/templates/high/adapter_module_prefix.ml` - Remove `get_queue` function
- `codegen/templates/high/adapter_module_prefix.mli` - Remove `get_queue` signature

## Testing

1. Run `dune build` to regenerate code
2. Run `dune exec test/test_compute.exe` to verify the compute tests still work
3. Run `dune build @check` to ensure no warnings
4. Verify that `high/wgpu.ml` contains the auto-generated `get_queue` in the Device module

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. `dune exec test/test_compute.exe` passes
4. The generated `high/wgpu.ml` contains `get_queue` in the Device module (auto-generated, not from template)

## Implementation Plan

1. Remove `("device", "get_queue")` entry from line 44 of `codegen/config.ml`
2. Remove the `get_queue` function from line 39 of `codegen/templates/high/adapter_module_prefix.ml`
3. Remove the `get_queue` signature from line 26 of `codegen/templates/high/adapter_module_prefix.mli`
4. Rebuild and verify:
   - `dune build` to regenerate code
   - `dune fmt > /dev/null || true` to format
   - `dune build @check` for no warnings
   - `dune exec test/test_compute.exe` for tests
5. Verify that `high/wgpu.ml` contains `get_queue` in the Device module (should appear after the injection point comment)
6. Move task to completed and commit
