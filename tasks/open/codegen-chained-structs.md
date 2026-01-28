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
