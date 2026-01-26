# wgpu-native-ocaml Implementation Plan

## Overview

This document outlines the implementation strategy for creating idiomatic OCaml bindings to wgpu-native. The approach uses code generation from the machine-readable `webgpu.yml` specification to produce both low-level C bindings and high-level OCaml APIs.

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        User OCaml Code                              │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    High-Level OCaml API                             │
│  (wgpu.mli / wgpu.ml - generated from webgpu.yml)                   │
│  - Type-safe modules: Device, Buffer, Texture, etc.                 │
│  - OCaml variants for enums                                         │
│  - Optional parameters, labeled arguments                           │
│  - Automatic memory management                                      │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Low-Level External Bindings                      │
│  (wgpu_low.{ml,mli}, wgpu_low_stubs.c - generated from webgpu.yml)  │
│  - `external` based C function bindings                             │
│  - Hand-written C stubs that call wgpu-native                       │
│  - Statically links against libwgpu_native.a                        │
│  - Includes webgpu.h                                                │
│  - Raw struct accessors                                             │
│  - Enum constants as OCaml ints                                     │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│               wgpu-native (Rust compiled to C library)              │
└─────────────────────────────────────────────────────────────────────┘
```

## Comprehensive Implementation Plan

### Phase A: Struct Generation (Foundation)
**Goal**: Generate C stubs and OCaml types for all structs

1. **A1**: Implement struct descriptor allocation in C
   - Generate `caml_wgpu_<struct>_create()` functions
   - Generate `caml_wgpu_<struct>_free()` functions
   - Handle `nextInChain` for extensible structs

2. **A2**: Implement struct field setters
   - Generate `caml_wgpu_<struct>_set_<field>()` for each field
   - Handle different field types: primitives, enums, objects, strings, arrays

3. **A3**: Implement struct field getters (for output structs)
   - Generate `caml_wgpu_<struct>_get_<field>()` functions

4. **A4**: Generate OCaml struct builder API
   - Create builder functions with optional labeled arguments
   - Test with `BufferDescriptor` and `TextureDescriptor`

**Test A**: Create a buffer descriptor, verify fields are set correctly

### Phase B: Object Method Generation
**Goal**: Generate bindings for all object methods

1. **B1**: Implement method stub generation
   - Parse method signatures from YAML
   - Generate C stubs that call wgpu functions
   - Handle `self` parameter (the object handle)

2. **B2**: Handle method parameters
   - Primitives: direct conversion
   - Enums: int conversion
   - Objects: nativeint handles
   - Structs: pointer to allocated struct
   - Arrays: convert OCaml arrays to C arrays

3. **B3**: Handle return types
   - Void methods: return unit
   - Primitives: convert to OCaml values
   - Objects: wrap in nativeint
   - Structs: copy to OCaml record

4. **B4**: Generate OCaml external declarations and wrappers

**Test B**: Call `buffer.getSize()`, `texture.getWidth()`, etc.

### Phase C: Buffer Operations
**Goal**: Complete buffer lifecycle

1. **C1**: `device.createBuffer()` with descriptor
2. **C2**: `buffer.getMappedRange()` to get data pointer
3. **C3**: Bigarray integration for zero-copy data access
4. **C4**: `buffer.unmap()` after writing
5. **C5**: `queue.writeBuffer()` for direct writes

**Test C**: Create buffer, write data, read it back, verify correctness

### Phase D: Shader and Compute Pipeline
**Goal**: Create and run compute shaders

1. **D1**: `device.createShaderModule()` with WGSL source
2. **D2**: `device.createBindGroupLayout()` with entries
3. **D3**: `device.createPipelineLayout()`
4. **D4**: `device.createComputePipeline()` with shader
5. **D5**: `device.createBindGroup()` to bind buffers

**Test D**: Create a compute pipeline that doubles numbers

### Phase E: Command Encoding and Dispatch
**Goal**: Execute GPU commands

1. **E1**: `device.createCommandEncoder()`
2. **E2**: `commandEncoder.beginComputePass()`
3. **E3**: `computePass.setPipeline()`, `setBindGroup()`, `dispatchWorkgroups()`
4. **E4**: `computePass.end()`
5. **E5**: `commandEncoder.finish()` → `CommandBuffer`
6. **E6**: `queue.submit()` with command buffers
7. **E7**: `device.poll()` or `instance.processEvents()` for sync

**Test E**: Complete compute shader that doubles an array of numbers

### Phase F: Texture and Render Pipeline
**Goal**: Render to texture for headless output

1. **F1**: `device.createTexture()` with format and usage
2. **F2**: `texture.createView()`
3. **F3**: `device.createRenderPipeline()` (minimal for clear)
4. **F4**: `commandEncoder.beginRenderPass()` with color attachment
5. **F5**: `renderPass.end()`
6. **F6**: `commandEncoder.copyTextureToBuffer()`

**Test F**: Render solid color to texture, copy to buffer, save as PPM

### Phase G: Polish and Documentation
**Goal**: Production-ready bindings

1. **G1**: Add finalizers for automatic resource cleanup
2. **G2**: Generate comprehensive `.mli` with documentation
3. **G3**: Error handling with Result types
4. **G4**: Example programs

## Current Status

**Phase 1 (Project Setup)**: Complete ✅
- ✅ Directory structure created
- ✅ Dune project configured with generation rules
- ✅ Rust/Cargo integration working (libwgpu_native.a builds and links)
- ✅ Minimal Instance create/release verified working

**Phase 2 (Code Generator)**: Milestone 2 Complete ✅
- ✅ YAML parsing (parse_yml.ml)
- ✅ IR definition (ir.ml)
- ✅ Low-level generator (gen_low.ml) - enums, bitflags, object handles
- ✅ High-level generator (gen_high.ml) - module wrappers
- ✅ Sync wrappers for async APIs (adapter/device request)
- ✅ Adapter info retrieval

**Current Phase**: Starting Phase A (Struct Generation)

## Implementation Order

The phases will be implemented in order A → B → C → D → E → F → G, with each phase building on the previous. Each phase has concrete tests to verify correctness before moving on.

## Key Design Decisions

1. **Sync over Async**: Using synchronous wrappers with internal callbacks for now
2. **Raw External**: Using `external` declarations with C stubs (not ctypes)
3. **Builder Pattern**: Structs created via builder functions with optional args
4. **Zero-Copy**: Bigarrays for buffer data to avoid copying
5. **PPM Output**: Simple PPM format for headless testing, convert to PNG via ImageMagick

---

*This plan is being actively executed. Progress is tracked in progress.md.*
