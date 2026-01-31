# High-level `create_render_pipeline` should support vertex buffer layouts

## Problem

The current `Device.create_render_pipeline` function does not support specifying
vertex buffer layouts. This prevents users from using proper vertex buffers with
`@location` attributes in their shaders.

When porting the WebGPU Fundamentals "rotation" lesson, this limitation required
a workaround: passing vertex data via a storage buffer instead of a vertex
buffer, and accessing vertices by index rather than using vertex attributes.

## Expected Behavior

Users should be able to:
1. Define vertex buffer layouts with attributes (format, offset, shader_location)
2. Pass these layouts to `create_render_pipeline`
3. Use `Render_pass_encoder.set_vertex_buffer` to bind vertex data
4. Access vertex data in shaders via `@location(N)` attributes

Example usage pattern:
```ocaml
let vertex_buffer_layout =
  { array_stride = 8L  (* 2 floats * 4 bytes *)
  ; step_mode = Vertex
  ; attributes =
      [ { format = Float32x2; offset = 0L; shader_location = 0 } ]
  }
in
let pipeline =
  Device.create_render_pipeline device
    ~vertex_buffer_layouts:[ vertex_buffer_layout ]
    (* ... other params ... *)
    ()
```

## Current Behavior

`create_render_pipeline` has no parameter for vertex buffer layouts. The only
way to pass per-vertex data is via storage buffers, which is less efficient
and doesn't match the standard WebGPU vertex input pattern.

## Affected Lessons

- `rotation` - worked around using storage buffer for vertices
- Will affect: `vertex-buffers`, `translation`, `scale`, and most rendering
  lessons that use vertex attributes

## Implementation Notes

The low-level bindings likely already support vertex buffer layouts in the
raw pipeline descriptor. The high-level API needs to expose this.

Required types:
- `Vertex_step_mode.t` (Vertex | Instance)
- `Vertex_attribute.t` (format, offset, shader_location)
- `Vertex_buffer_layout.t` (array_stride, step_mode, attributes)

## Demonstrating a fix

Add a new integration test under `test/integration/` (e.g.,
`test/integration/vertex_buffer_layout/`) that:
1. Creates a vertex buffer with position data
2. Defines a vertex buffer layout with a Float32x2 attribute at location 0
3. Creates a render pipeline with the vertex buffer layout
4. Binds the vertex buffer and renders geometry
5. Verifies the output is correct

## References

- WebGPU spec: https://www.w3.org/TR/webgpu/#dictdef-gpuvertexbufferlayout
- Affected port: `test/fundamentals/rotation/rotation.ml`

## Implementation Plan

### Analysis

The types `Vertex_attribute`, `Vertex_buffer_layout`, `Vertex_step_mode`, and `Vertex_format`
already exist in the high-level bindings (wgpu.ml/wgpu.mli). The low-level C stubs for
`device_create_render_pipeline_full` and `device_create_render_pipeline_with_layout` currently
hard-code `.bufferCount = 0` and `.buffers = NULL` in the vertex state.

### Approach

Since the low-level bindings are auto-generated and should not be modified directly, I will:

1. Add new convenience C stubs that accept vertex buffer layout data as OCaml arrays
2. Add OCaml external declarations for these new stubs
3. Update `Device.create_render_pipeline` to use the new stubs when `vertex_buffer_layouts` is provided

### Steps

1. Add C stub `caml_wgpu_device_create_render_pipeline_with_vertex_buffers` that:
   - Takes additional parameters for vertex buffer layouts (as OCaml values)
   - Iterates over the OCaml list to build C `WGPUVertexBufferLayout` array
   - Sets `.bufferCount` and `.buffers` in the vertex state

2. Add corresponding OCaml external declaration in `low/wgpu_low.ml` and `.mli`

3. Update `Device.create_render_pipeline` in `high/wgpu.ml` and `.mli` to:
   - Accept optional `?vertex_buffer_layouts:Vertex_buffer_layout.t list`
   - Call the new low-level function when vertex buffer layouts are provided

4. Create integration test `test/integration/vertex_buffer_layout/` that:
   - Creates a vertex buffer with Float32x2 position data for a triangle
   - Uses `@location(0)` in the vertex shader
   - Renders and verifies the result

### Validation Criteria

1. `dune build` succeeds
2. `dune build @check` has no warnings
3. `dune runtest` passes (including new integration test)
4. The new integration test renders a triangle using vertex buffer data with `@location` attributes
