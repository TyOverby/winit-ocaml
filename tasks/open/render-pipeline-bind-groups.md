# High-level `create_render_pipeline` should support bind group layouts

## Problem

The current `Device.create_render_pipeline` function creates a pipeline with an
empty layout, which prevents binding uniform buffers or other resources to the
pipeline.

When porting the WebGPU Fundamentals "rotation" lesson, this limitation required
a workaround: embedding rotation parameters as shader constants and recompiling
the shader for each frame, rather than using uniform buffers as the original
lesson demonstrates.

## Expected Behavior

Users should be able to:
1. Create a bind group layout with uniform buffer entries
2. Create a pipeline layout referencing those bind group layouts
3. Pass the pipeline layout to `create_render_pipeline`
4. Create bind groups and set them on the render pass encoder

## Current Behavior

`create_render_pipeline` appears to use an empty/auto pipeline layout, so
`Render_pass_encoder.set_bind_group` has no effect (or the bind group doesn't
match the pipeline's expected layout).

## Affected Lessons

- `rotation` - worked around by embedding values in shader
- Likely affects: `uniforms`, `storage-buffers`, `translation`, `scale`,
  `matrix-math`, and most other rendering lessons that use uniform buffers

## Possible Solutions

1. Add optional `?layout:Pipeline_layout.t` parameter to `create_render_pipeline`
2. Add optional `?bind_group_layouts:Bind_group_layout.t list` parameter that
   creates the pipeline layout internally

## References

- WebGPU spec: https://www.w3.org/TR/webgpu/#dom-gpudevice-createrenderpipeline
- Affected port: `test/fundamentals/rotation/rotation.ml`

## Demonstrating a fix

Make a new test executable under `test/integration/` demonstrating that the
issue has been fixed.
