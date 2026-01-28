# Auto-generate get_features methods

## Problem

Both `adapter.get_features` and `device.get_features` are marked manual with reason "Output struct with array member". They likely have identical patterns and could be auto-generated.

## Analysis Needed

1. Look at the webgpu.yml definitions for these methods
2. Look at the current manual implementations (if any exist)
3. Understand what "output struct with array member" means in this context

## Expected Pattern

The `SupportedFeatures` struct likely contains an array of feature flags. The codegen needs to:
1. Create the output struct
2. Call the C function to populate it
3. Extract the array contents into an OCaml list or array

## Implementation

This is related to the struct-output-params task but specifically handles the case where the output struct contains array members that need to be converted to OCaml collections.

## Methods

- `adapter.get_features`
- `device.get_features`
