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
│                    Low-Level Ctypes Bindings                        │
│  (wgpu_raw.ml - generated from webgpu.yml)                          │
│  - Direct C function bindings                                       │
│  - Raw struct types                                                 │
│  - Enum constants                                                   │
└─────────────────────────────────────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│               wgpu-native (Rust compiled to C library)              │
└─────────────────────────────────────────────────────────────────────┘
```

## Phase 1: Project Setup and Build Infrastructure

### 1.1 Directory Structure
```
wgpu-native-ocaml/
├── vendor/
│   ├── wgpu-native/          # Vendored wgpu-native (existing)
│   └── wgpu-native-wiki/     # Wiki documentation (existing)
├── codegen/
│   ├── dune                  # Build file for generator
│   ├── parse_yml.ml          # YAML parser for webgpu.yml
│   ├── ir.ml                 # Intermediate representation types
│   ├── gen_raw.ml            # Low-level bindings generator
│   ├── gen_high.ml           # High-level bindings generator
│   └── main.ml               # Generator entry point
├── lib/
│   ├── dune                  # Library build file
│   ├── wgpu_raw.ml           # (generated) Low-level bindings
│   ├── wgpu_raw.mli          # (generated) Low-level interface
│   ├── wgpu.ml               # (generated) High-level bindings
│   └── wgpu.mli              # (generated) High-level interface
├── test/
│   ├── dune
│   ├── test_compute.ml       # Headless compute test
│   └── test_capture.ml       # Render-to-PNG test
├── examples/
│   ├── triangle/             # Triangle demo (requires display)
│   └── headless/             # Headless rendering example
├── dune-project
├── wgpu.opam
├── CLAUDE.md
└── plan.md
```

### 1.2 Build System Setup
- Set up dune-project with appropriate dependencies
- Configure wgpu-native compilation (static library)
- Create opam file with dependencies: ctypes, ctypes-foreign, yaml, etc.

### 1.3 Dependencies
```
depends: [
  "ocaml" {>= "4.14.0"}
  "dune" {>= "3.0"}
  "ctypes" {>= "0.20.0"}
  "ctypes-foreign"
  "yaml"              # For parsing webgpu.yml
  "stb_image"         # For PNG output in tests (or use camlimages)
]
```

## Phase 2: Code Generator Implementation

### 2.1 YAML Parsing and IR Definition

The `webgpu.yml` file contains these top-level sections that we need to parse:
- `constants`: Named constant values
- `enums`: Enumeration types with named variants
- `bitflags`: Bitmask flag types
- `structs`: C struct definitions
- `callbacks`: Callback function type definitions
- `functions`: Standalone C functions
- `objects`: Opaque handle types with their methods

The IR (intermediate representation) will model these:

```ocaml
(* ir.ml *)
type primitive =
  | Bool | Uint32 | Uint64 | Int32 | Int64
  | Float32 | Float64 | Usize | String | CVoid

type type_ref =
  | Primitive of primitive
  | Enum of string
  | Bitflag of string
  | Struct of string
  | Object of string
  | Callback of string
  | Array of type_ref
  | Optional of type_ref
  | Pointer of { mutable_: bool; inner: type_ref }

type constant = { name: string; value: string; doc: string }
type enum_entry = { name: string; doc: string; value: int option }
type enum = { name: string; doc: string; entries: enum_entry list }
type bitflag = { name: string; doc: string; entries: enum_entry list }

type struct_member = {
  name: string;
  type_: type_ref;
  optional: bool;
  doc: string;
}
type struct_ = {
  name: string;
  doc: string;
  type_: [`BaseIn | `BaseOut | `Standalone];
  free_members: bool;
  members: struct_member list;
}

type arg = { name: string; type_: type_ref; optional: bool; doc: string }
type return_type = { type_: type_ref; doc: string }
type method_ = {
  name: string;
  doc: string;
  args: arg list;
  returns: return_type option;
  callback: string option;
}

type callback = { name: string; doc: string; args: arg list; style: string }
type function_ = { name: string; doc: string; args: arg list; returns: return_type option }
type object_ = { name: string; doc: string; methods: method_ list }

type api = {
  constants: constant list;
  enums: enum list;
  bitflags: bitflag list;
  structs: struct_ list;
  callbacks: callback list;
  functions: function_ list;
  objects: object_ list;
}
```

### 2.2 Low-Level Bindings Generator

The low-level generator produces ctypes bindings:

```ocaml
(* Example generated output for wgpu_raw.ml *)

(* Opaque handle types *)
module Adapter = struct
  type t
  let t : t Ctypes.structure Ctypes.typ = Ctypes.structure "WGPUAdapterImpl"
  let t_ptr = Ctypes.ptr t
end

(* Enum types as integers with constants *)
module Adapter_type = struct
  type t = int
  let discrete_gpu = 0x0001
  let integrated_gpu = 0x0002
  let cpu = 0x0003
  let unknown = 0x0004
end

(* Struct types *)
module Adapter_info = struct
  type t
  let t : t Ctypes.structure Ctypes.typ = Ctypes.structure "WGPUAdapterInfo"
  let vendor = Ctypes.field t "vendor" String_view.t
  let architecture = Ctypes.field t "architecture" String_view.t
  (* ... more fields ... *)
  let () = Ctypes.seal t
end

(* Function bindings *)
let wgpu_create_instance =
  Ctypes.Foreign.foreign "wgpuCreateInstance"
    (Ctypes.ptr Instance_descriptor.t @-> returning Instance.t_ptr)

let wgpu_adapter_get_info =
  Ctypes.Foreign.foreign "wgpuAdapterGetInfo"
    (Adapter.t_ptr @-> Ctypes.ptr Adapter_info.t @-> returning Status.t)
```

### 2.3 High-Level Bindings Generator

The high-level generator produces idiomatic OCaml:

```ocaml
(* Example generated output for wgpu.mli *)

module Adapter_type : sig
  type t =
    | Discrete_gpu
    | Integrated_gpu
    | Cpu
    | Unknown
end

module Adapter_info : sig
  type t = {
    vendor: string;
    architecture: string;
    device: string;
    description: string;
    backend_type: Backend_type.t;
    adapter_type: Adapter_type.t;
    vendor_id: int;
    device_id: int;
  }
end

module Adapter : sig
  type t
  (** An adapter represents a physical GPU or software renderer. *)

  val get_info : t -> Adapter_info.t
  (** Get information about this adapter. *)

  val get_limits : t -> Limits.t
  (** Get the limits of this adapter. *)

  val has_feature : t -> Feature_name.t -> bool
  (** Check if this adapter supports a feature. *)

  val request_device :
    ?label:string ->
    ?required_features:Feature_name.t list ->
    ?required_limits:Limits.t ->
    t -> Device.t
  (** Request a device from this adapter. *)
end

module Instance : sig
  type t
  (** The root object for creating surfaces and adapters. *)

  val create : ?backends:Backend_type.t list -> unit -> t
  (** Create a new wgpu instance. *)

  val request_adapter :
    ?power_preference:Power_preference.t ->
    ?force_fallback_adapter:bool ->
    ?compatible_surface:Surface.t ->
    t -> Adapter.t
  (** Request an adapter from this instance. *)
end
```

Key generation strategies:

1. **Type Safety for Objects**: Each object type gets its own abstract type
2. **Enums as Variants**: C enums become OCaml variants
3. **Bitflags as Lists**: Bitflags become `type t list` for combining
4. **Descriptors as Optional Args**: Struct fields become optional labeled arguments
5. **Memory Management**: Objects get finalizers calling `wgpu{Type}Release`
6. **Callbacks to Sync**: Async callbacks are wrapped to appear synchronous where possible

### 2.4 Naming Conventions

Transform C names to OCaml conventions:
- `WGPUAdapterType` → `Adapter_type.t`
- `WGPUAdapterType_DiscreteGPU` → `Adapter_type.Discrete_gpu`
- `wgpuAdapterGetInfo` → `Adapter.get_info`
- `WGPUAdapterInfo` → `Adapter_info.t`

## Phase 3: Memory Safety Design

### 3.1 Object Lifetime Management

```ocaml
(* Internal tracking for parent-child relationships *)
module Handle : sig
  type 'a t
  val wrap : release:('a -> unit) -> parent:'b t option -> 'a -> 'a t
  val get : 'a t -> 'a
  val release : 'a t -> unit
end

(* Implementation uses weak references to track children *)
(* Children hold strong refs to parents to prevent premature release *)
```

### 3.2 Preventing Use-After-Free

Options (in order of preference):
1. **Explicit resource management with guards**: Resources are valid only within a scope
2. **Phantom types for validity**: Track validity in the type system
3. **Finalizers with weak parent refs**: GC-based cleanup (simplest, less control)

Recommended approach: Use finalizers for simplicity initially, document that explicit `release` is preferred for predictable cleanup.

### 3.3 Callback Safety

```ocaml
(* Callbacks need special handling to prevent OCaml closures from being GC'd *)
module Callback_registry : sig
  val register : ('a -> 'b) -> nativeint  (* Returns stable pointer *)
  val unregister : nativeint -> unit
end
```

## Phase 4: Implementation Milestones

### Milestone 1: Minimal Working Binding (Compute Example)
Goal: Run a headless compute shader, verify output

1. Manually write bindings for:
   - `Instance` (create, request_adapter)
   - `Adapter` (request_device)
   - `Device` (create_buffer, create_shader_module, create_compute_pipeline, get_queue)
   - `Queue` (submit, write_buffer)
   - `Buffer` (map_async, get_mapped_range, unmap)
   - `CommandEncoder`, `ComputePassEncoder`
   - `ComputePipeline`, `BindGroup`, `BindGroupLayout`

2. Port the `compute/main.c` example to OCaml
3. Verify output matches expected values

### Milestone 2: Code Generator for Enums and Constants
1. Parse webgpu.yml
2. Generate all enum types
3. Generate all constants
4. Generate all bitflag types

### Milestone 3: Code Generator for Structs
1. Generate low-level ctypes struct bindings
2. Generate high-level record types
3. Generate conversion functions (OCaml record ↔ C struct)

### Milestone 4: Code Generator for Objects and Methods
1. Generate object handle types
2. Generate method bindings
3. Add finalizers for automatic cleanup
4. Handle callbacks (sync wrappers)

### Milestone 5: Capture Example (Render to PNG)
1. Add texture, render pass, and surface types
2. Port `capture/main.c` to OCaml
3. Output PNG file, verify image

### Milestone 6: Polish and Documentation
1. Generate comprehensive `.mli` files with documentation
2. Add examples directory
3. Write user guide
4. Performance optimization (reduce allocations, batch operations)

## Phase 5: Testing Strategy

### 5.1 Headless Tests (CI-friendly)
```ocaml
(* test/test_compute.ml *)
let%test "compute shader doubles numbers" =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance in
  let device = Wgpu.Adapter.request_device adapter in
  let input = [| 1l; 2l; 3l; 4l |] in
  let output = run_compute_shader device ~shader:"..." input in
  output = [| 2l; 4l; 6l; 8l |]
```

### 5.2 Visual Tests (Manual verification)
```ocaml
(* test/test_capture.ml *)
let%test "render red rectangle" =
  (* Render to texture, copy to buffer, save as PNG *)
  let image_path = render_to_file ~width:100 ~height:100 ~color:red in
  (* Can be manually inspected or compared with reference image *)
  Sys.file_exists image_path
```

### 5.3 Memory Tests
Use Valgrind or AddressSanitizer to check for:
- Memory leaks
- Use-after-free
- Double-free

## Phase 6: API Design Decisions

### 6.1 Sync vs Async
The C API has async callbacks for:
- `requestAdapter`
- `requestDevice`
- `bufferMapAsync`
- Pipeline creation (async variants)

Options:
1. **Blocking wrappers** (recommended for v1): Call async, poll until complete
2. **Lwt/Async integration**: Return promises (future enhancement)
3. **Direct callbacks**: Expose raw callback API (escape hatch)

### 6.2 Error Handling
- Use `Result` types for operations that can fail
- Provide `_exn` variants that raise exceptions
- Log errors to stderr in debug mode

### 6.3 Builder Pattern for Descriptors
For complex descriptors, consider builder pattern:

```ocaml
let pipeline =
  Render_pipeline.create device
  |> Render_pipeline.vertex_shader shader ~entry_point:"vs_main"
  |> Render_pipeline.fragment_shader shader ~entry_point:"fs_main"
  |> Render_pipeline.primitive_topology Triangle_list
  |> Render_pipeline.build
```

## Risks and Mitigations

| Risk | Mitigation |
|------|------------|
| webgpu.yml format changes | Pin to specific wgpu-native version, generate during build |
| Complex callback semantics | Start with sync wrappers, document limitations |
| Platform-specific issues | Test on Linux first, add macOS/Windows later |
| Performance overhead | Profile after correctness, optimize hot paths |
| Memory leaks | Extensive testing with leak detectors |

## Success Criteria

1. **Compute example works**: Headless compute shader produces correct output
2. **Capture example works**: Renders to PNG correctly
3. **No memory leaks**: Valgrind clean
4. **Generated code is readable**: Developer can understand generated bindings
5. **Documentation exists**: Types and functions have doc comments
6. **Tests pass in CI**: Headless tests run without GPU

## Next Steps

1. Set up basic project structure with dune
2. Build wgpu-native as static library
3. Write minimal manual bindings for compute example
4. Verify manual bindings work
5. Begin implementing code generator

---

*This file (`./plan.md`) is a living document. It is critical that you update it as the project progresses and if the plan changes.*
