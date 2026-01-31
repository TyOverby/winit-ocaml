# Methods with Raw Pointer/Size Data

## Problem
Some methods take raw pointers and sizes for data transfer. The generator can't automatically handle the conversion between OCaml bigarrays and C pointers with separate size parameters.

## Affected Methods
- `queue.write_buffer` - writes data from pointer to GPU buffer
- `queue.write_texture` - writes texture data from pointer
- `buffer.get_mapped_range` - returns pointer to mapped memory
- `buffer.get_const_mapped_range` - returns const pointer to mapped memory

## Current Workaround
Manual implementations use bigarrays for safe memory handling and convert to/from raw pointers in C stubs.

## Possible Solutions
1. Add generator support for bigarray-to-pointer conversion patterns
2. Keep manual implementations for these performance-critical methods
3. Create a standard pattern for data transfer methods
