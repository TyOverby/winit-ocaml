# Review complex descriptor methods

## Problem

3 methods are marked manual due to complex/nested descriptors:

- `command_encoder.begin_compute_pass` - "Uses descriptor struct with arrays"
- `command_encoder.begin_render_pass` - "Uses descriptor struct with arrays"
- `device.create_render_pipeline` - "Deeply nested descriptors"

## Analysis Needed

1. Look at the current implementations in templates
2. Examine the descriptor struct definitions in webgpu.yml
3. Determine if codegen improvements could handle these

## Notes

`begin_compute_pass` and `begin_render_pass` are already in the Command_encoder module with injection points. They may have simpler versions that just set a label.

`create_render_pipeline` is likely the most complex descriptor in all of WebGPU with deeply nested vertex/fragment state, blend modes, depth-stencil, etc.

## Possible Outcomes

1. Keep all manual - document why
2. Simplify some (e.g., compute_pass with just label param)
3. Create builder patterns for complex ones

---

## Analysis Plan

1. Review the webgpu.yml descriptor definitions for each method
2. Examine current manual implementations in templates
3. Check what codegen produces for these methods via regression tests
4. Determine if codegen can handle any of these or if manual is appropriate
5. Document findings and recommendations

### Validation Criteria

- Understand why each method is marked manual
- Determine if any could be auto-generated with current or improved codegen
- Document the trade-offs for each approach
- Verify build passes after analysis

---

## Findings

### 1. `command_encoder.begin_compute_pass`

**webgpu.yml descriptor structure:**
```yaml
compute_pass_descriptor:
  - label: string_with_default_empty
  - timestamp_writes: struct.compute_pass_timestamp_writes (optional pointer)
```

**Current manual implementation** (in `adapter_module_prefix.ml`):
- Simple implementation that just sets the label
- Uses `Wgpu_low.Compute_pass_descriptor` struct accessors
- Ignores `timestamp_writes` (an optional advanced feature)

**Codegen output** (from regression tests):
- High-level: `(none)` - codegen cannot generate this

**Assessment:** The current manual implementation is appropriate and minimal. The codegen
cannot handle this because the descriptor contains an optional pointer to a nested struct
(`timestamp_writes`). The manual implementation provides a clean, simple API that covers
the common use case (just setting a label). The timestamp_writes feature is advanced and
rarely needed.

**Recommendation:** KEEP MANUAL - current implementation is clean and sufficient

### 2. `command_encoder.begin_render_pass`

**webgpu.yml descriptor structure:**
```yaml
render_pass_descriptor:
  - label: string_with_default_empty
  - color_attachments: array<struct.render_pass_color_attachment>  # ARRAY!
  - depth_stencil_attachment: struct (optional pointer)
  - occlusion_query_set: object (optional)
  - timestamp_writes: struct (optional pointer)
```

**render_pass_color_attachment contains:**
- view: texture_view (optional)
- depth_slice: uint32
- resolve_target: texture_view (optional)
- load_op: enum
- store_op: enum
- clear_value: struct.color (nested: r,g,b,a floats)

**Current manual implementation:**
- Uses a custom convenience C function `command_encoder_begin_render_pass_configurable`
- Handles single color attachment with configurable load/store ops and clear color
- Takes flattened parameters: label, color_view, load_op, store_op, clear_color (r,g,b,a)
- Creates the complex nested structure in C code

**Codegen output:**
- High-level: `(none)` - codegen cannot generate this

**Assessment:** The codegen cannot handle this because:
1. It has an ARRAY of nested structs (`color_attachments`)
2. Each color attachment has deeply nested fields (clear_value.r/g/b/a)
3. Multiple optional pointers to nested structs

The current manual implementation is a pragmatic simplification that handles the most
common case (single color attachment). The C helper function encapsulates all the
complexity of building the descriptor.

**Recommendation:** KEEP MANUAL - array of nested structs is beyond current codegen
capabilities, and the simplified API is actually more ergonomic for common use cases

### 3. `device.create_render_pipeline`

**webgpu.yml descriptor structure:**
```yaml
render_pipeline_descriptor:
  - label: string_with_default_empty
  - layout: pipeline_layout (optional)
  - vertex: struct.vertex_state      # Complex nested struct
  - primitive: struct.primitive_state
  - depth_stencil: struct (optional pointer)
  - multisample: struct.multisample_state
  - fragment: struct.fragment_state (optional pointer)  # Complex nested struct
```

**vertex_state contains:**
- module: shader_module
- entry_point: nullable_string
- constants: array<struct.constant_entry>  # ARRAY!
- buffers: array<struct.vertex_buffer_layout>  # ARRAY!

**fragment_state contains:**
- module: shader_module
- entry_point: nullable_string
- constants: array<struct.constant_entry>  # ARRAY!
- targets: array<struct.color_target_state>  # ARRAY! (contains blend state)

**Current manual implementation:**
- Uses custom C function `device_create_render_pipeline_full`
- Takes 17 flattened parameters covering common pipeline configuration
- Hardcodes empty vertex buffers, single color target, auto pipeline layout
- Supports blend state via optional tuple parameter
- Creates all nested structures in C code

**Codegen output:**
- High-level: `(none)` - codegen cannot generate this

**Assessment:** This is indeed the most complex descriptor in WebGPU. The codegen cannot
handle it because:
1. Multiple arrays of nested structs (buffers, constants, targets)
2. Deeply nested blend state (color and alpha blend components)
3. Optional pointer to complex fragment_state
4. Each nested struct has its own complexity

The current manual implementation is a reasonable simplification that handles common
rendering scenarios (single shader module, single color target, no vertex buffers for
fullscreen triangles). More complex use cases would require additional convenience
functions or a builder pattern.

**Recommendation:** KEEP MANUAL - deeply nested arrays of structs are well beyond
codegen capabilities, and the flattened API serves common use cases well

---

## Conclusions

All three methods should remain marked as Manual. The reasons are:

1. **Arrays of nested structs** - The codegen cannot handle descriptors containing
   arrays of complex structs. Both `begin_render_pass` (color_attachments) and
   `create_render_pipeline` (buffers, constants, targets) have this pattern.

2. **Deep nesting** - Multiple levels of nested structs (e.g., fragment_state ->
   targets -> color_target_state -> blend -> blend_component) cannot be flattened
   to parameters automatically.

3. **Practical API design** - The manual implementations provide ergonomic APIs
   for common use cases rather than exposing all the complexity. This is a
   feature, not a limitation.

### Future Improvements

If auto-generation is desired in the future, consider:

1. **Builder pattern** - Generate builder modules for complex descriptors that
   allow incremental construction

2. **Array-of-struct handling** - Extend codegen to convert arrays of structs
   to OCaml lists/arrays with helper functions for conversion

3. **Multiple convenience levels** - Generate both "full" versions (all params)
   and "simple" versions (common defaults) of methods

For now, the manual implementations are well-designed and working correctly.
