# Multisampling Support

## Summary

The multisampling lesson from webgpufundamentals.org cannot be ported because the
bindings are missing support for two critical multisampling parameters.

## Missing Functionality

### 1. Multisample count on render pipelines

**What's needed**: The `create_render_pipeline` function needs an optional
`?multisample_count:int` parameter (default 1, valid values are 1 or 4).

**Current state**: In `codegen/templates/low/sync_helpers.c`, the
`caml_wgpu_device_create_render_pipeline_with_depth` function hardcodes
`.multisample.count = 1` at lines 1017-1022.

**WebGPU API reference**:
```javascript
const pipeline = device.createRenderPipeline({
  // ...
  multisample: {
    count: 4,  // <-- This needs to be configurable
  },
});
```

### 2. Resolve target on render pass color attachments

**What's needed**: The `begin_render_pass` function needs an optional
`?resolve_target:Texture_view.t` parameter. When rendering to a multisample
texture, the resolve target is the non-multisampled texture that receives the
final resolved image.

**Current state**: In `codegen/templates/low/sync_helpers.c`, the
`caml_wgpu_command_encoder_begin_render_pass_with_depth` function hardcodes
`.resolveTarget = NULL` at line 1085.

**WebGPU API reference**:
```javascript
const pass = encoder.beginRenderPass({
  colorAttachments: [{
    view: multisampleTexture.createView(),
    resolveTarget: canvasTexture.createView(),  // <-- This needs to be configurable
    loadOp: 'clear',
    storeOp: 'store',
    clearValue: [0.3, 0.3, 0.3, 1],
  }],
});
```

## Implementation Notes

The low-level binding infrastructure already supports `resolve_target` on
`Render_pass_color_attachment` (see `high/wgpu.mli` line 396), but the high-level
convenience function `begin_render_pass` does not expose it.

Two approaches are possible:
1. Add parameters to the existing `begin_render_pass` helper function
2. Create a new `begin_render_pass_msaa` helper or allow users to use the
   lower-level API directly

For the pipeline, the C helper function needs to accept a sample count parameter
and pass it through to the descriptor.

## Files to Modify

1. `codegen/templates/low/sync_helpers.c`:
   - Add `sample_count` parameter to `caml_wgpu_device_create_render_pipeline_with_depth`
   - Add `resolve_target` parameter to `caml_wgpu_command_encoder_begin_render_pass_with_depth`

2. `codegen/templates/low/convenience_functions.ml{,i}`:
   - Update OCaml external declarations

3. `high/wgpu.ml`:
   - Add `?multisample_count` parameter to `Device.create_render_pipeline`
   - Add `?resolve_target` parameter to `Command_encoder.begin_render_pass`

4. `high/wgpu.mli`:
   - Update signatures

## Blocked Lesson

`webgpu_fundamentals/multisampling/` - All three examples require this functionality:
- `multisample-simple.js`
- `multisample-center-issue.js`
- `multisample-centroid.js`

## References

- WebGPU spec on multisampling: https://www.w3.org/TR/webgpu/#multisample-state
- wgpu-native wiki getting started
- Existing multisampled texture creation is supported via `Device.create_texture`
  with `~sample_count:4`
