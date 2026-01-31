# Support chained structs in codegen

## Problem

`device.create_shader_module` is marked manual because it "Uses chained WGSL struct". WebGPU uses a chained struct pattern for extensions where structs have a `nextInChain` pointer.

## Background

WebGPU's extension mechanism uses struct chaining:
```c
typedef struct WGPUShaderModuleDescriptor {
    WGPUChainedStruct const * nextInChain;
    char const * label;
} WGPUShaderModuleDescriptor;

typedef struct WGPUShaderSourceWGSL {
    WGPUChainedStruct chain;  // For linking
    char const * code;
} WGPUShaderSourceWGSL;
```

## Current Manual Implementation

Look at how `create_shader_module` is currently implemented in the templates to understand the pattern.

## Analysis Needed

1. How many methods use chained structs?
2. Is there a consistent pattern that could be codegen'd?
3. Would it be better to handle this as special-case generation or keep manual?

## Possible Approach

For shader modules specifically, the high-level API could just take a `~wgsl:string` parameter and handle the chaining internally, which is what the manual implementation likely does.

---

## Investigation Results (2026-01-27)

### Current State

1. **Manual implementation exists**: `Device.create_shader_module'` is implemented in `codegen/templates/high/adapter_module_prefix.ml` with the signature:
   ```ocaml
   val create_shader_module' : t -> ?label:string -> wgsl:string -> unit -> Shader_module.t
   ```

2. **Auto-generated code is useless**: The codegen produces:
   ```ocaml
   val create_shader_module : t -> ?label:string -> unit -> Shader_module.t
   ```
   This only sets the label but has NO way to provide the actual shader source (WGSL code), making it unusable.

3. **Chained struct pattern**: The `shader_module_descriptor` is a `base_in` struct that needs a `nextInChain` pointer to a `shader_source_WGSL` extension struct. The current manual implementation correctly:
   - Creates the WGSL source extension struct
   - Sets the code on it
   - Sets the chain sType
   - Creates the descriptor and chains the extension
   - Calls the low-level API
   - Frees both structs

### Analysis

1. **How many methods use chained structs?**
   - 42 `base_in` structs exist in the API
   - 9 `extension_in` structs exist
   - However, only `create_shader_module` is commonly used with chained structs in typical applications

2. **Is there a consistent pattern that could be codegen'd?**
   - Yes, but it would require significant codegen changes:
     - Detecting which `base_in` structs have `extension_in` structs that extend them
     - Generating combined APIs that flatten the extension parameters
     - For shader modules specifically, this would mean detecting that `shader_source_WGSL` extends `shader_module_descriptor` and auto-generating a `~wgsl:string` parameter
   - This is complex because:
     - Some base structs have multiple possible extensions (e.g., WGSL or SPIRV)
     - The "right" API shape is domain-specific

3. **Should this stay manual?**
   - **Yes, but with improvements**:
     - The manual implementation is correct and provides the right API
     - Auto-generating this would require significant codegen complexity for limited benefit
     - The function name should be `create_shader_module` not `create_shader_module'`

### Resolution Plan

1. Rename `create_shader_module'` to `create_shader_module` in the manual implementation
2. Ensure the config marks this as Manual so no conflicting auto-generated version is created
3. Update the test code to use the new name
4. The method will remain manual because:
   - The auto-generated version would be useless (no way to provide shader source)
   - The correct API shape (just `~wgsl:string`) requires understanding the chained struct pattern
   - Implementing general chained struct support in codegen is disproportionate effort for this single use case

### Validation Criteria

1. Build succeeds with `dune build`
2. No warnings with `dune build @check`
3. Tests pass with `dune exec test/test_compute.exe`
4. `Device.create_shader_module` is the public API (not `create_shader_module'`)
