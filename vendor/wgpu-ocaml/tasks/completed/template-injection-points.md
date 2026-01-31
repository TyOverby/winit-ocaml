# Restructure Templates to Use Injection Points Instead of Prefix/Suffix

## Problem

Currently, the high-level template system uses separate prefix and suffix files:
- `adapter_module_prefix.ml` - Contains Queue and Device modules (before auto-generated Device methods)
- `adapter_module_suffix.ml` - Contains Device.poll and Adapter module (after auto-generated Device methods)
- `instance_module.ml` - Contains Instance module and convenience functions

This prefix/suffix approach has limitations:
1. Only the Device module has an injection point for auto-generated methods
2. Queue, Adapter, and Instance modules are entirely template-defined with no way to inject auto-generated methods
3. Methods like `queue.set_label`, `adapter.has_feature`, and `instance.process_events` produce identical code to what the codegen would generate, but can't be auto-generated because there's no injection point

## Proposed Solution

Restructure templates to use inline injection point markers within each module, similar to how Device already works:

```ocaml
module Queue = struct
  type t = { handle : Wgpu_low.queue }

  (* Manual methods that need special handling *)
  let release t = Wgpu_low.queue_release t.handle
  let write_buffer t ~buffer ~offset ~data =
    Wgpu_low.queue_write_buffer_bigarray t.handle buffer.Buffer.handle offset data

  (* AUTO-GENERATED QUEUE METHODS INJECTED HERE *)
end

module Device = struct
  type t = { handle : Wgpu_low.device }

  (* Manual methods *)
  let release t = Wgpu_low.device_release t.handle
  let get_queue t = { Queue.handle = Wgpu_low.device_get_queue t.handle }
  (* ... other manual methods ... *)

  (* AUTO-GENERATED DEVICE METHODS INJECTED HERE *)

  (* Manual methods that need to come after auto-generated ones *)
  let poll t ?(wait = false) () = Wgpu_low.device_poll t.handle wait
end

module Adapter = struct
  type t = { handle : Wgpu_low.adapter }

  (* Manual methods *)
  let release t = Wgpu_low.adapter_release t.handle
  let get_info t = Adapter_info.of_low (Wgpu_low.adapter_get_info t.handle)
  let request_device t = ...

  (* AUTO-GENERATED ADAPTER METHODS INJECTED HERE *)
end

module Instance = struct
  type t = { handle : Wgpu_low.instance }

  let create () = { handle = Wgpu_low.create_instance () }
  let release t = Wgpu_low.instance_release t.handle
  let request_adapter t ... = ...

  (* AUTO-GENERATED INSTANCE METHODS INJECTED HERE *)
end
```

## Task

### Phase 1: Consolidate Templates

1. Merge `adapter_module_prefix.ml` and `adapter_module_suffix.ml` into a single `object_modules.ml` template
2. Add injection point markers to Queue, Adapter, and Instance modules
3. Update the corresponding `.mli` files

### Phase 2: Update Codegen

1. Modify `codegen/gen_high.ml` to:
   - Parse the template and find all injection point markers
   - Generate methods for each object type (not just Device)
   - Inject generated methods at the appropriate markers

2. Update the marker detection to handle multiple object types:
   - `(* AUTO-GENERATED QUEUE METHODS INJECTED HERE *)`
   - `(* AUTO-GENERATED DEVICE METHODS INJECTED HERE *)`
   - `(* AUTO-GENERATED ADAPTER METHODS INJECTED HERE *)`
   - `(* AUTO-GENERATED INSTANCE METHODS INJECTED HERE *)`

### Phase 3: Enable Auto-generation

Once injection points are in place, remove these from the `Manual` list in `config.ml`:
- `queue.set_label` - produces identical code
- `adapter.has_feature` - produces identical code
- `instance.process_events` - produces identical code

## Files to Modify

- `codegen/templates/high/adapter_module_prefix.ml` - Merge and add injection points
- `codegen/templates/high/adapter_module_suffix.ml` - Delete (merged into above)
- `codegen/templates/high/adapter_module_prefix.mli` - Merge and add injection points
- `codegen/templates/high/adapter_module_suffix.mli` - Delete (merged into above)
- `codegen/templates/high/instance_module.ml` - Add injection point to Instance module
- `codegen/templates/high/instance_module.mli` - Add injection point
- `codegen/gen_high.ml` - Update injection logic for multiple object types
- `codegen/config.ml` - Remove methods that can now be auto-generated

## Benefits

1. **More methods can be auto-generated**: Reduces template maintenance burden
2. **Single template file per concern**: Easier to understand and modify
3. **Consistent pattern**: All object modules work the same way
4. **Better regression testing**: Changes to codegen are immediately visible in more places

## Testing

1. Run `dune build` to regenerate code
2. Compare generated `high/wgpu.ml` before and after to ensure equivalent output
3. Run `dune exec test/test_compute.exe` to verify functionality
4. Run `dune build @check` to ensure no warnings

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. All tests pass
4. The generated `high/wgpu.ml` contains auto-generated methods in Queue, Adapter, and Instance modules
5. Template files are reduced in size (less duplicated code)

---

## Implementation Plan (by Claude)

Based on the user's simplified task description, I will implement only the targeted changes
for Adapter and Instance modules (not the full consolidation described above):

### Phase 1: Adapter Module Injection Point

1. Add injection point marker `(* AUTO-GENERATED ADAPTER METHODS INJECTED HERE *)` to
   `adapter_module_suffix.ml` inside the Adapter module
2. Add corresponding marker `(* AUTO-GENERATED ADAPTER METHOD SIGNATURES INJECTED HERE *)`
   to `adapter_module_suffix.mli`
3. Update `gen_high.ml` to:
   - Generate adapter auto-methods similar to device/queue
   - Inject them at the adapter marker
4. Remove `("adapter", "has_feature")` from Manual list in `config.ml`
5. Remove the manual `has_feature` implementation from `adapter_module_suffix.ml`

### Phase 2: Instance Module Injection Point

1. Add injection point marker `(* AUTO-GENERATED INSTANCE METHODS INJECTED HERE *)` to
   `instance_module.ml` inside the Instance module
2. Add corresponding marker `(* AUTO-GENERATED INSTANCE METHOD SIGNATURES INJECTED HERE *)`
   to `instance_module.mli`
3. Update `gen_high.ml` to:
   - Generate instance auto-methods
   - Inject them at the instance marker
4. Remove `("instance", "process_events")` from Manual list in `config.ml`

### Validation Criteria (Simplified)

1. `dune build` succeeds
2. `dune fmt > /dev/null || true` passes
3. `dune build @check` reports no warnings
4. `dune exec test/test_compute.exe` passes
5. The generated `high/wgpu.ml` contains auto-generated `has_feature` in Adapter module
6. The generated `high/wgpu.ml` contains auto-generated `process_events` in Instance module
