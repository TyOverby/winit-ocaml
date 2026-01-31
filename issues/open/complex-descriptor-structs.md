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
