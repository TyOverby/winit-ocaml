# Auto-generate queue.submit Instead of Hardcoding

## Problem

The `queue.submit` method is currently hardcoded in `codegen/templates/high/adapter_module_prefix.ml` and marked as `Manual` in `codegen/config.ml`. The code generator produces functionally equivalent code with a slightly different parameter name:

**Template version (adapter_module_prefix.ml):**
```ocaml
let submit t ~command_buffers =
  let handles = List.map (fun (cb : Command_buffer.t) -> cb.handle) command_buffers in
  Wgpu_low.queue_submit t.handle (Array.of_list handles)
```

**Codegen version (from regression test):**
```ocaml
let submit t ~commands =
  Wgpu_low.queue_submit t.handle (Array.of_list (List.map (fun x -> x.Command_buffer.handle) commands))
```

The only difference is the parameter name: `~command_buffers` vs `~commands`. The codegen version uses the name from the webgpu.yml spec. This signature change is acceptable.

## Challenge

The Queue module is entirely defined in the template (`adapter_module_prefix.ml`) with no injection point for auto-generated methods. To auto-generate `queue.submit`, we need to either:

1. Add an injection point to the Queue module in the template, OR
2. Wait for the "template injection points" task to restructure templates

This task depends on one of those approaches being implemented first, OR can restructure the Queue module to have an injection point.

## Task

1. Add an injection point comment to the Queue module in `adapter_module_prefix.ml`:
   ```ocaml
   module Queue = struct
     type t = { handle : Wgpu_low.queue }

     (* Methods that must stay manual *)
     let release t = Wgpu_low.queue_release t.handle
     let write_buffer t ~buffer ~offset ~data =
       Wgpu_low.queue_write_buffer_bigarray t.handle buffer.Buffer.handle offset data

     (* AUTO-GENERATED QUEUE METHODS INJECTED HERE *)
   end
   ```

2. Update the high-level codegen to inject Queue methods at this marker

3. Remove `("queue", "submit")` from the `Manual` list in `codegen/config.ml`

4. Remove `("queue", "set_label")` from the `Manual` list (also produces identical code)

5. Remove the `submit` and `set_label` implementations from the template

6. Update the `.mli` template accordingly

## Files to Modify

- `codegen/config.ml` - Remove `("queue", "submit")` and `("queue", "set_label")` from `method_config`
- `codegen/templates/high/adapter_module_prefix.ml` - Add injection point, remove `submit` and `set_label`
- `codegen/templates/high/adapter_module_prefix.mli` - Update Queue signature
- `codegen/gen_high.ml` - Update to inject Queue methods at the marker (similar to Device)

## API Change

The parameter name changes from `~command_buffers` to `~commands`. This is a breaking change for users, but aligns with the webgpu spec naming.

## Testing

1. Run `dune build` to regenerate code
2. Update `test/test_compute.ml` if it uses `~command_buffers` (change to `~commands`)
3. Run `dune exec test/test_compute.exe` to verify tests still work
4. Run `dune build @check` to ensure no warnings

## Validation Criteria

1. `dune build` succeeds
2. `dune build @check` reports no warnings
3. `dune exec test/test_compute.exe` passes
4. The generated `high/wgpu.ml` contains auto-generated `submit` and `set_label` in Queue module

## Implementation Plan

1. **Modify `codegen/templates/high/adapter_module_prefix.ml`**:
   - Remove the `submit` and `set_label` method implementations from Queue module
   - Add `(* AUTO-GENERATED QUEUE METHODS INJECTED HERE *)` comment for injection

2. **Modify `codegen/templates/high/adapter_module_prefix.mli`**:
   - Remove the `submit` and `set_label` signatures from Queue module
   - Add `(* AUTO-GENERATED QUEUE METHOD SIGNATURES INJECTED HERE *)` comment for injection

3. **Modify `codegen/config.ml`**:
   - Remove `("queue", "submit")` from the Manual list
   - Remove `("queue", "set_label")` from the Manual list

4. **Modify `codegen/gen_high.ml`**:
   - Add Queue method generation similar to how Device methods are generated
   - Inject Queue methods into the adapter_module_prefix at the marker
   - Do the same for the .mli file

5. **Modify `test/test_compute.ml`**:
   - Update calls from `~command_buffers` to `~commands` (3 occurrences)

6. **Run validation**:
   - `dune build` - regenerate code
   - `dune fmt > /dev/null || true` - format
   - `dune build @check` - check for warnings
   - `dune exec test/test_compute.exe` - run tests
