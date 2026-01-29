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
