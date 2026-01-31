# Methods with Complex Descriptor Structs
subproject: `winit` code generator

## Problem
Several methods take descriptor structs that are too complex for the current generator to handle automatically. These structs may have:
- Deeply nested structs
- Multiple array members
- Pointer-to-struct members requiring special allocation
- Conditional/optional nested structs

## Affected Methods
- `device.create_render_pipeline` - complex descriptor with vertex/fragment stages, blend states
- `device.create_compute_pipeline` - descriptor with programmable stage
- `device.create_render_bundle_encoder` - descriptor with color/depth formats
- `device.create_query_set` - descriptor with query type config
- `command_encoder.begin_render_pass` - descriptor with color/depth attachments
- `command_encoder.begin_compute_pass` - descriptor with timestamp writes
- `surface.configure` - descriptor with usage, format, present mode

## Current Workaround
Manual implementations that carefully handle struct allocation/deallocation.

## Solution
Extend generator to handle more complex struct patterns.

## Task completion
This task will be considered "done" when at minimum, `create_render_pipeline` is fully autogenenerated.

## Currently

The current code generator can handle:
1. Simple (flat) structs with only primitive/enum/object members
2. Structs with inline nested structs (non-pointer, non-optional)
3. Arrays of flat structs as parameters
4. Nested structs within array element structs

The `create_render_pipeline` method is marked as `Manual` in `config.ml` because its
`render_pipeline_descriptor` has these complex features:
- **vertex**: inline `vertex_state` struct with array members (`buffers`, `constants`)
- **primitive**: inline `primitive_state` struct (flat - already handled)
- **depth_stencil**: **optional pointer** to `depth_stencil_state`
- **multisample**: inline `multisample_state` struct (flat - already handled)
- **fragment**: **optional pointer** to `fragment_state` with array members

The key missing capabilities in the codegen are:
1. Optional pointer-to-struct members (like `depth_stencil` and `fragment`)
2. Inline structs with array members (like `vertex_state.buffers`)
3. Nested structs within optional pointer structs

## Notes

Looking at the `render_pipeline_descriptor` structure hierarchy:

```
render_pipeline_descriptor
  - label: string
  - layout: object.pipeline_layout (optional)
  - vertex: struct.vertex_state (inline)
      - module: object.shader_module
      - entry_point: nullable_string
      - constants: array<struct.constant_entry> (pointer)
      - buffers: array<struct.vertex_buffer_layout> (pointer)
          - step_mode: enum
          - array_stride: uint64
          - attributes: array<struct.vertex_attribute> (pointer)
  - primitive: struct.primitive_state (inline, flat - all enums/primitives)
  - depth_stencil: struct.depth_stencil_state (optional pointer)
      - format, depth_write_enabled, depth_compare: enums
      - stencil_front, stencil_back: struct.stencil_face_state (inline, flat)
      - stencil_read_mask, stencil_write_mask, depth_bias: primitives
      - depth_bias_slope_scale, depth_bias_clamp: floats
  - multisample: struct.multisample_state (inline, flat - all primitives/bools)
  - fragment: struct.fragment_state (optional pointer)
      - module: object.shader_module
      - entry_point: nullable_string
      - constants: array<struct.constant_entry> (pointer)
      - targets: array<struct.color_target_state> (pointer)
          - format: enum
          - blend: struct.blend_state (optional pointer)
              - color, alpha: struct.blend_component (inline, flat)
          - write_mask: bitflag
```

The complexity levels:
1. `primitive_state` and `multisample_state` - already supported (flat inline structs)
2. `depth_stencil_state` - needs: optional pointer + nested flat structs
3. `vertex_state` and `fragment_state` - needs: arrays of structs, which themselves
   may contain arrays of structs or optional pointer-to-struct members

## Plan

### Strategy
Rather than trying to fully generalize the codegen to handle all possible nesting
patterns, I will extend it to handle the specific patterns needed for
`create_render_pipeline`:

1. **Optional pointer-to-struct members**: The codegen already handles inline nested
   structs. Extend to also handle optional pointer-to-struct by:
   - Checking for `Optional (Struct name)` or `Pointer { inner = Struct name; ... }`
     when the member is optional
   - Generating code that creates the nested struct only when the value is `Some`
   - Passing the struct pointer (or null) to the setter

2. **Inline structs with array members**: Currently `collect_struct_params` returns
   early when hitting an array-of-structs. Extend to also descend into inline nested
   structs that contain arrays.

3. **Deep nested structure handling**: The key insight is that the existing codegen
   already has most of the pieces - it just needs to be more recursive and handle
   the optional pointer case.

### Implementation Steps

1. Modify `is_flat_member_type_with_nested` and `is_auto_generable_struct_aux` to
   also accept optional pointer-to-struct members pointing to auto-generable structs

2. Modify `collect_struct_params` to handle:
   - Optional pointer-to-struct members (treat similarly to inline structs)
   - Continue recursing into nested structs even if they have array members

3. Modify `generate_struct_creates` to handle optional pointer-to-struct:
   - Create the nested struct conditionally based on whether the optional is Some
   - Handle the case where we need to create a struct only if parameters are provided

4. Modify `generate_struct_sets` to handle optional pointer-to-struct setters

5. Remove `create_render_pipeline` from the Manual list in config.ml

6. Test that the generated code compiles and works correctly

### Validation Criteria

1. `dune build` succeeds with no warnings
2. `./test.sh` passes
3. The generated `create_render_pipeline` function in `wgpu.ml` has the expected
   signature with flattened parameters for all nested structs
4. An integration test using `create_render_pipeline` works correctly

## Addressing

### Implementation Summary

Extended the codegen to handle complex nested structs with optional pointer members
and arrays of structs. The key changes were:

1. **Modified `is_auto_generable_struct_aux` in `gen_high.ml`**: Added support for
   optional pointer-to-struct members by checking if the pointed-to struct is itself
   auto-generable.

2. **Extended `is_flat_member_type_with_nested`**: Added case for optional pointers
   to structs, treating them as nested when the inner struct is flat or has nested
   auto-generable members.

3. **Updated `collect_struct_params`**: Now properly recurses into optional pointer-to-struct
   members and handles structs with array members by stopping at the array level.

4. **Enhanced `generate_struct_creates`**: Added handling for optional struct creation,
   generating conditional code that only creates nested structs when the optional value
   is `Some`.

5. **Updated `generate_struct_sets`**: Added support for optional pointer-to-struct setters
   that pass null when the value is `None`.

6. **Removed `create_render_pipeline` from Manual list**: Changed from `Manual` to
   `Auto` in `config.ml`.

### Files Updated

All 45 test files using `create_render_pipeline` were migrated to the new API:
- Changed from old API with individual parameters like `~fragment_entry_point`,
  `~color_format`, `~vertex_buffer_layouts`, `~depth_format`, etc.
- To new API with structured parameters: `~fragment` record, `~vertex_buffers`,
  `~depth_stencil` record, `~primitive_*` params, `~multisample_*` params

Key patterns in the migration:
- Fragment state now uses a `Fragment_state.t` record
- Depth stencil state uses a `Depth_stencil_state.t` record with nested `Stencil_face_state.t`
- Vertex buffer layouts passed via `~vertex_buffers`
- Primitive state uses individual `~primitive_topology`, `~primitive_cull_mode` params
- Multisample state uses `~multisample_count` param

### Validation

All validation criteria met:
- `dune build` succeeds with no warnings
- `./test.sh` passes (all integration tests and regression tests)
- Generated function has proper flattened signature
- All existing tests using `create_render_pipeline` work correctly
