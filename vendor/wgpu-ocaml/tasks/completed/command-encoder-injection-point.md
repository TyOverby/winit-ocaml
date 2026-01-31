# Add Command Encoder Injection Point

## Problem

The `command_encoder.begin_compute_pass` and `command_encoder.begin_render_pass` methods are marked as Manual because they "use descriptor struct with arrays". However, looking at the regression test output:

**begin_compute_pass codegen output:**
```
=== High-level MLI ===
(none)
=== High-level ML ===
(none)
```

The codegen currently returns `(none)` for these methods, likely because the descriptor structs have complex array fields (like `timestamp_writes`).

However, the Command_encoder module is already auto-generated with many working methods (copy_buffer_to_buffer, copy_texture_to_buffer, etc.). Adding an injection point would allow manual methods to coexist with auto-generated ones.

## Current State

Looking at `wgpu.ml`, Command_encoder module has these auto-generated methods:
- finish
- copy_buffer_to_buffer
- copy_buffer_to_texture
- copy_texture_to_buffer
- copy_texture_to_texture
- clear_buffer
- insert_debug_marker
- pop_debug_group
- push_debug_group
- resolve_query_set
- write_timestamp
- set_label

The `begin_compute_pass` and `begin_render_pass` are currently only available via top-level convenience functions in `instance_module.ml`.

## Task

1. Add an injection point to Command_encoder module (similar to Device, Queue, etc.)
2. Move the manual `begin_compute_pass` and `begin_render_pass` implementations into the template
3. This allows both manual complex methods and auto-generated simple methods to coexist

## Implementation

The Command_encoder module is auto-generated, so we need to:

1. Create a template for Command_encoder with the injection point marker
2. Include manual implementations for `begin_compute_pass` and `begin_render_pass`
3. Update `gen_high.ml` to inject auto-generated methods at the marker

**Template structure:**
```ocaml
module Command_encoder = struct
  type t = { handle : Wgpu_low.command_encoder }

  let release t = Wgpu_low.command_encoder_release t.handle

  (* Manual methods for complex descriptors *)
  let begin_compute_pass t ?(label = "") () =
    (* existing implementation *)

  let begin_render_pass t ?(label = "") ~color_attachment ... () =
    (* existing implementation *)

  (* AUTO-GENERATED COMMAND_ENCODER METHODS INJECTED HERE *)
end
```

## Alternative

Keep the current structure where:
- Command_encoder module is auto-generated with simple methods
- `begin_compute_pass` and `begin_render_pass` are top-level convenience functions

This works but is inconsistent with how other modules handle manual methods.

## Files to Modify

- Create `codegen/templates/high/command_encoder_module.ml` with injection point
- Create `codegen/templates/high/command_encoder_module.mli`
- `codegen/gen_high.ml` - Skip Command_encoder in auto-generation, include template
- `codegen/templates/high/instance_module.ml` - Keep convenience functions or move to module

## Testing

1. Run `dune build`
2. Verify Command_encoder module has both auto-generated and manual methods
3. Run tests
4. Run `dune build @check`

## Priority

Low - the current structure works fine. This is more about consistency than functionality.

---

## Implementation Plan

### Approach
Since Command_encoder is currently fully auto-generated, I will:

1. Add "command_encoder" to the `special_objects` list in `gen_high.ml` (like device, queue, adapter, instance, surface)
2. Create a Command_encoder module prefix template in `adapter_module_prefix.ml` (before Queue) with:
   - The type `t = { handle : Wgpu_low.command_encoder }`
   - The `release` function
   - Manual implementations for `begin_compute_pass` and `begin_render_pass`
   - An injection point marker: `(* AUTO-GENERATED COMMAND_ENCODER METHODS INJECTED HERE *)`
3. Update `gen_high.ml` to generate and inject Command_encoder auto-generated methods at the marker
4. Update the corresponding `.mli` template
5. Keep the top-level convenience functions in `instance_module.ml` that delegate to `Command_encoder.begin_compute_pass` etc. (for backward compatibility)

### Validation Criteria
1. `dune build` succeeds (regenerates code)
2. `dune fmt > /dev/null || true` runs without issues
3. `dune build @check` shows no warnings
4. `dune exec test/test_compute.exe` passes all tests
5. The generated `wgpu.ml` has Command_encoder module with both:
   - Manual methods: `begin_compute_pass`, `begin_render_pass`
   - Auto-generated methods: `finish`, `copy_buffer_to_buffer`, etc.
6. Tests can use either `Wgpu.begin_compute_pass encoder` (convenience) or `Wgpu.Command_encoder.begin_compute_pass encoder` (module method)
