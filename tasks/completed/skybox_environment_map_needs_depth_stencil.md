# Skybox + Environment Map Port Blocked: Needs Depth-Stencil Support

## Summary

The `skybox-plus-environment-map.js` example from WebGPU Fundamentals cannot be
ported because the high-level API lacks depth-stencil support.

## What's Missing

1. **Render Pipeline Depth-Stencil State**: The `Device.create_render_pipeline`
   function does not accept depth-stencil configuration parameters like:
   - `depth_write_enabled`
   - `depth_compare` (e.g., `Less_equal` for skybox, `Less` for objects)
   - `depth_format` (e.g., `Depth24plus`)

2. **Render Pass Depth-Stencil Attachment**: The `begin_render_pass` helper
   function only accepts a color attachment. It needs optional parameters for:
   - `depth_view` (the depth texture view)
   - `depth_load_op` / `depth_store_op`
   - `depth_clear_value`

## Why This Matters

The environment map example renders:
1. A reflective cube (with `depthCompare: 'less'`, depth write enabled)
2. A skybox (with `depthCompare: 'less-equal'`, rendered at z=1)

Without depth testing, the skybox would overdraw the cube. The skybox needs
`less-equal` because it renders exactly at the far plane (z=1.0), and the depth
buffer is cleared to 1.0.

## Low-Level API Support

The low-level API (`Wgpu_low`) has all the necessary primitives:
- `Depth_stencil_state` module with setters for format, compare, write enable
- `Render_pass_depth_stencil_attachment` module
- `Render_pass_descriptor.render_pass_descriptor_set_depth_stencil_attachment`
- `Render_pipeline_descriptor.render_pipeline_descriptor_set_depth_stencil`

## Suggested High-Level API Changes

### Option 1: Add Optional Parameters

```ocaml
val create_render_pipeline
  :  t
  -> ...existing params...
  -> ?depth_format:Texture_format.t
  -> ?depth_write_enabled:bool
  -> ?depth_compare:Compare_function.t
  -> unit
  -> Render_pipeline.t

val begin_render_pass
  :  Command_encoder.t
  -> ...existing params...
  -> ?depth_view:Texture_view.t
  -> ?depth_load_op:Load_op.t
  -> ?depth_store_op:Store_op.t
  -> ?depth_clear_value:float
  -> unit
  -> Render_pass_encoder.t
```

### Option 2: Alternative Function Names

Create separate functions like `create_render_pipeline_with_depth` and
`begin_render_pass_with_depth` to avoid changing existing signatures.

## Workaround

The basic skybox example (without the reflective cube) was successfully ported
by skipping depth testing entirely, since it's the only object rendered.

## Related Lessons

This also blocks porting other 3D examples that require depth testing:
- Any scene with multiple objects at different depths
- Shadow mapping examples
- Deferred rendering examples

---

## Implementation Plan

### Approach

We will follow **Option 1: Add Optional Parameters** since it is the cleanest
API design and maintains backward compatibility. All new parameters are optional
so existing code continues to work unchanged.

### Changes Required

#### 1. High-level API: Add depth parameters to `create_render_pipeline`

Add optional parameters:
- `?depth_format:Texture_format.t` - The format of the depth texture
- `?depth_write_enabled:bool` - Whether to write to depth buffer (default: true)
- `?depth_compare:Compare_function.t` - Depth comparison function (default: Less)

#### 2. Low-level C stubs: Create a new render pipeline function with depth

Create `caml_wgpu_device_create_render_pipeline_with_depth` that extends
`caml_wgpu_device_create_render_pipeline_with_vertex_buffers` with depth-stencil
parameters.

#### 3. High-level API: Add depth parameters to `begin_render_pass`

Add optional parameters:
- `?depth_view:Texture_view.t` - The depth texture view
- `?depth_load_op:Load_op.t` - How to handle depth at pass start (default: Clear)
- `?depth_store_op:Store_op.t` - How to handle depth at pass end (default: Discard)
- `?depth_clear_value:float` - Value to clear depth to (default: 1.0)

#### 4. Low-level C stubs: Create a new begin_render_pass function with depth

Create `caml_wgpu_command_encoder_begin_render_pass_with_depth` that extends
`caml_wgpu_command_encoder_begin_render_pass_configurable` with depth-stencil
attachment.

#### 5. Integration test

Create `test/integration/depth_test/depth_test.ml` demonstrating:
- Creating a depth texture
- Creating two pipelines with different depth comparison functions
- Rendering overlapping geometry to verify correct depth ordering

### Validation Criteria

1. `dune build` succeeds without errors
2. `dune build @check` reports no warnings
3. All existing tests continue to pass (`dune runtest`)
4. New depth test renders overlapping geometry with correct occlusion
5. API is backward compatible (existing code unchanged)
