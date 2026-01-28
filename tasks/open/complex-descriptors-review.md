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
