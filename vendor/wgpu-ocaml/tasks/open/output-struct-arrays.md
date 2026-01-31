# Methods with Output Struct Arrays

## Problem
Some methods return structs containing arrays whose size is determined at runtime. The generator doesn't currently support converting these C structs with dynamic arrays back to OCaml types.

## Affected Methods
- `adapter.get_features` - returns struct with array of features
- `device.get_features` - returns struct with array of features
- `surface.get_capabilities` - returns struct with arrays of formats, present modes, etc.
- `instance.get_WGSL_language_features` - returns struct with array of features

## Current Workaround
These methods are listed in `manual_implementations` and not exposed in the high-level API.

## Possible Solutions
1. Add generator support for output structs with dynamic arrays
2. Manually implement these methods with proper array handling
3. Use a different API pattern (e.g., separate count + fetch calls)
