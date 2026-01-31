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

---

## Plan

### Solution Approach

Add an optional `?layout:Pipeline_layout.t` parameter to `create_render_pipeline` in the
high-level API. This follows solution option #1 from the task description.

The implementation requires:

1. **C stub modification**: Update `caml_wgpu_device_create_render_pipeline_full` to accept
   an optional pipeline layout parameter. When provided, use it directly instead of creating
   an empty layout.

2. **Low-level OCaml bindings**: Add a new external function that accepts the pipeline layout.

3. **High-level OCaml API**: Add `?layout:Pipeline_layout.t` parameter to
   `Device.create_render_pipeline`.

4. **Test**: Create `test/integration/render_uniform_buffer/` demonstrating:
   - Creating a bind group layout for a uniform buffer
   - Creating a pipeline layout with that bind group layout
   - Creating a render pipeline with that pipeline layout
   - Creating a bind group with a uniform buffer
   - Setting the bind group on a render pass encoder
   - Verifying the uniform buffer values affect the rendered output

### Implementation Steps

1. Add `device_create_bind_group_layout_uniform` C stub for creating uniform buffer bind group layouts
2. Add corresponding OCaml binding
3. Create new C function `caml_wgpu_device_create_render_pipeline_with_layout` that accepts a pipeline layout
4. Add OCaml external for the new function
5. Update high-level `Device.create_render_pipeline` to accept optional `?layout`
6. Create integration test demonstrating uniform buffers with render pipelines

### Validation Criteria

1. `dune build` succeeds
2. `dune build @check` produces no warnings
3. `dune runtest` passes
4. New integration test `render_uniform_buffer` demonstrates:
   - A uniform buffer containing color values
   - The color values being read in the fragment shader
   - Different color values producing different rendered output
