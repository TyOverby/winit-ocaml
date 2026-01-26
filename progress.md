# wgpu-native-ocaml Progress

## 2026-01-25: Rust/Cargo Integration Complete

### Accomplished
- Set up dune build rule to compile wgpu-native via Cargo
- The rule correctly navigates from the dune sandbox to the real source tree
- Successfully produces `libwgpu_native.a` (256MB static library)
- Library links correctly with OCaml code

### Verified Working
- Minimal test executable creates and releases a wgpu Instance
- No memory errors or crashes
- `dune build @check` passes with no warnings

### Files Changed
- `low/dune`: Added Cargo build rule, foreign_archives, c_library_flags
- `high/dune`: Added dependency on wgpu_low
- `codegen/gen_bindings.ml`: Updated to generate minimal working C stubs and OCaml bindings
- `test/test_compute.ml`: Added Instance creation/release test

### Next Steps
1. ~~Begin implementing YAML parser for webgpu.yml~~ ✅
2. ~~Define IR (intermediate representation) types~~ ✅
3. ~~Generate enum types from specification~~ ✅

---

## 2026-01-25: Code Generator Milestone 1 Complete

### Accomplished
- Created IR module (`codegen/ir.ml`) with types for the full webgpu API
- Implemented YAML parser (`codegen/parse_yml.ml`) that reads webgpu.yml
- Created low-level generator (`codegen/gen_low.ml`) producing:
  - C stubs with enum/bitflag constants (2346 lines)
  - OCaml external bindings (1721 lines)
  - OCaml interface (834 lines)
- Created high-level generator (`codegen/gen_high.ml`) producing:
  - Module re-exports for enums/bitflags
  - Object wrapper types
  - Instance module with create/release

### Generated Code Statistics
- **Total generated lines**: 6118
- **Enums**: 58 types with all variants
- **Bitflags**: 6 types with all entries
- **Objects**: 27 handle types with release functions

### Edge Cases Handled
- YAML boolean values parsed as strings (`name: true`)
- Numeric enum variants prefixed with `N` (`1d` -> `N1d`)
- Double underscores in YAML become single underscores in C (`unorm10__10__10__2` -> `Unorm10_10_10_2`)
- Unknown types gracefully degraded to c_void

### Test Verification
- Instance create/release still works
- `dune build @check` passes with no warnings

### Next Steps
1. ~~Add more function bindings (beyond just create_instance)~~ ✅
2. Generate struct types and accessors
3. ~~Implement request_adapter to get a working GPU pipeline~~ ✅

---

## 2026-01-25: Adapter and Device Bindings

### Accomplished
- Added synchronous wrappers for callback-based APIs:
  - `instance_request_adapter_sync` - request GPU adapter
  - `adapter_request_device_sync` - request GPU device
  - `device_get_queue` - get command queue
  - `adapter_get_info` - get adapter information
- Created high-level modules: `Adapter`, `Adapter_info`, `Device`, `Queue`
- Test successfully enumerates GPU adapter

### Test Output
```
Creating wgpu instance...
Requesting adapter...
Adapter obtained!
  Vendor: llvmpipe
  Device: llvmpipe (LLVM 20.1.8, 256 bits)
  Backend type: 6 (Vulkan)
  Adapter type: 3 (CPU/Software)
```

### Next Steps
1. Add buffer creation and data transfer
2. Implement compute shader execution
3. Create headless render-to-texture example

---

## 2026-01-25: Struct and Method Generation Complete

### Accomplished
- **Phase A (Struct Generation)**: Complete
  - Generate C stubs for struct allocation/deallocation
  - Generate setters and getters for all struct fields
  - Handle primitive types, enums, bitflags, objects, and pointers
  - Fixed YAML parsing issue where `y` and `n` were being parsed as booleans

- **Phase B (Object Method Generation)**: Complete
  - Generate C stubs for object methods
  - Generate OCaml external declarations
  - Handle various argument types (primitives, enums, structs, objects)
  - Handle return types (void, primitives, objects)
  - Skip async methods (with callbacks) for now
  - Skip methods with array arguments (need special handling)
  - Fixed type ordering issues in generated ML/MLI

- **Phase C (Buffer Operations)**: Partial
  - Successfully creating buffers via `device.createBuffer()`
  - Buffer size and usage can be queried

### Generated Code Statistics
- **Struct modules**: 82 types with create/free/getters/setters
- **Object methods**: ~200 sync methods generated
- **Total generated lines**: ~15,000+

### Test Verification
```
=== Testing Buffer Descriptor ===
Buffer descriptor created.
Buffer descriptor fields set.
  Label: test_buffer
  Size: 1024
  Usage: 0x0041
  Mapped at creation: false
All assertions passed!

=== Testing Buffer Creation ===
Device obtained.
Buffer created!
  Buffer size: 256
  Buffer usage: 0x008c
Buffer properties verified!
```

### Edge Cases Handled
- YAML boolean aliases (`y` -> `true`, `n` -> `false`) mapped back to single letters
- Type ordering in generated ML/MLI (all types declared before methods)
- Duplicate function definitions (manual vs generated)
- C keyword conflicts avoided

### Next Steps
1. ~~Implement array argument handling for methods like `queue.submit()`~~ ✅ (helper functions)
2. ~~Add shader module creation~~ ✅
3. ~~Create compute pipeline~~ ✅
4. ~~Execute compute shader and verify results~~ ✅

---

## 2026-01-25: Compute Shader Pipeline Complete! 🎉

### Accomplished
- **Full GPU Compute Pipeline**: Complete end-to-end compute shader execution
  - WGSL shader module creation
  - Bind group layout and bind group creation (with helper functions)
  - Pipeline layout and compute pipeline creation
  - Command recording (set pipeline, set bind group, dispatch, copy)
  - Submit and wait for completion
  - Map buffer and read back results

- **Helper Functions Added**:
  - `device_create_bind_group_layout_storage` - create layout for single storage buffer
  - `device_create_bind_group_buffer` - create bind group with single buffer entry
  - `device_create_pipeline_layout_single` - create pipeline layout with single bind group
  - `device_create_compute_pipeline_simple` - create compute pipeline from shader + layout

### Test Verification
```
=== Testing Compute Shader (Full Pipeline) ===
Device and queue obtained.
Shader module created!
Storage buffer created.
Readback buffer created.
Initial data written to storage buffer.
Bind group layout created.
Bind group created.
Pipeline layout created.
Compute pipeline created.
Compute pass recorded.
Copy command recorded.
Commands submitted.
Device polled.
Buffer mapped for reading.
SUCCESS: All values correctly doubled by compute shader!
All resources released.
```

### Technical Details
- Shader doubles each element: `data[i] = data[i] * 2`
- Input: [0, 1, 2, ..., 63]
- Output: [0, 2, 4, ..., 126]
- Uses software renderer (llvmpipe) for headless testing

### Code Architecture
- **Helper functions** bypass array argument complexity for common patterns
- Auto-generated methods work for simple cases (no arrays)
- Combination allows full pipeline construction

### Next Steps
1. ~~Implement texture creation and render pipelines~~ ✅
2. Add render-to-PNG example for visual verification
3. ~~Consider implementing full array argument support in generator~~ ✅
4. Document the high-level API

---

## 2026-01-25: Array Argument Support & Render Pipeline

### Accomplished
- **Array Argument Generation**: Complete
  - Added `gen_c_array_conversion` function in gen_low.ml
  - Methods with array arguments now auto-generate correctly
  - Arrays converted to (count, pointer) pairs for C API
  - Supports object arrays, enum arrays, and primitive arrays
  - `queue_submit` and other array methods now work automatically

- **Render Pipeline Basics**: Complete
  - Texture creation with `device_create_texture_2d` helper
  - Texture view creation with `texture_create_view_simple` helper
  - Render pass with `command_encoder_begin_render_pass_simple`
  - Texture-to-buffer copy with `command_encoder_copy_texture_to_buffer_simple`

### Helper Functions Added
- `device_create_texture_2d` - create 2D texture with format and usage
- `texture_create_view_simple` - create default texture view
- `command_encoder_begin_render_pass_simple` - begin render pass with single color attachment (clear)
- `command_encoder_copy_texture_to_buffer_simple` - copy texture to buffer for readback

### Test Verification
```
=== Testing Render Pass (Clear to Color) ===
Device and queue obtained.
Render target texture created.
Texture view created.
Readback buffer created.
Render pass started (clearing to red).
Render pass ended.
Copy texture to buffer command recorded.
Commands submitted.
Device polled.
Buffer mapped for reading.
  First pixel: R=255 G=0 B=0 A=255
SUCCESS: All pixels correctly cleared to red!
All resources released.
```

### Technical Details
- Created 64x64 RGBA8Unorm texture as render target
- Cleared to solid red (1.0, 0.0, 0.0, 1.0)
- Copied to readback buffer with 256-byte row alignment
- Verified all 4096 pixels are exactly (255, 0, 0, 255)
- Used `WGPU_DEPTH_SLICE_UNDEFINED` for 2D texture render pass
- Used `WGPU_MIP_LEVEL_COUNT_UNDEFINED` for texture view defaults

### Edge Cases Fixed
- `depthSlice` must be `WGPU_DEPTH_SLICE_UNDEFINED` for non-3D textures
- `mipLevelCount` = 0 is invalid; use `WGPU_MIP_LEVEL_COUNT_UNDEFINED` (UINT32_MAX)
- Texture usage flags: RenderAttachment (0x10) | CopySrc (0x01) = 0x11

### Next Steps
1. ~~Implement PNG output for visual verification~~ ✅
2. ~~Add full render pipeline (shaders, vertex buffers)~~ ✅
3. ~~Create triangle rendering example~~ ✅
4. Document the high-level API

---

## 2026-01-25: Triangle Rendering Complete

### Accomplished
- **PNG Output**: Added PPM writer + ImageMagick conversion for visual verification
- **Render Pipeline Helper**: `device_create_render_pipeline_simple` creates a basic render pipeline
  - No vertex buffers needed (uses vertex_index in shader)
  - Empty pipeline layout (no bind groups)
  - Triangle list topology, no culling
- **Triangle Test**: Full working triangle render example
  - WGSL vertex shader generates triangle from vertex index
  - Fragment shader outputs solid green
  - Blue clear color for background
  - Correctly verifies center (green) and corner (blue) pixels

### Test Verification
```
=== Testing Render Pipeline (Triangle) ===
Device and queue obtained.
Shader module created.
Render target texture created.
Texture view created.
Render pipeline created.
Readback buffer created.
Render pass started.
Triangle drawn.
Copy command recorded.
Commands submitted.
Buffer mapped for reading.
  Center pixel: R=0 G=255 B=0 A=255
  Corner pixel: R=0 G=0 B=255 A=255
SUCCESS: Triangle rendered correctly!
  Written to render_triangle.ppm
  Converted to render_triangle.png
All resources released.
```

### Helper Functions Added
- `device_create_render_pipeline_simple` - create render pipeline with vertex/fragment shaders
- `write_ppm` (OCaml) - write RGBA pixel data to PPM file
- `ppm_to_png` (OCaml) - convert PPM to PNG via ImageMagick

### Next Steps
1. Add vertex buffer support for custom geometry
2. Add texture sampling support
3. Document the high-level API
4. Consider adding more complex examples (textured quad, etc.)

---

## 2026-01-25: Improved Code Generator - Array and Struct Field Support

### Accomplished
- **Array field setters in structs**: Generator now produces proper setters for array fields
  - Computes count field name (e.g., `entries` -> `entryCount`)
  - Allocates C array with malloc
  - Copies elements from OCaml array
  - Sets both count and pointer fields
  - Handles arrays of objects, structs, enums, and primitives

- **Pointer-to-array fields**: Added special handling for fields with `pointer: immutable` wrapping an array type

- **OCaml type generation**: Array setters now have proper types (`nativeint array` for objects/structs, `int array` for enums)

### Test Verification
```
=== Testing Bind Group with Generated Struct APIs ===
Device obtained.
Buffer created.
Buffer binding layout created.
Layout entry created with buffer binding.
Layout descriptor with entries array set.
Bind group layout created!
Bind group entry created.
Bind group descriptor with entries array set.
Bind group created!
SUCCESS: All generated struct APIs worked correctly!
```

### Technical Details
- Added `array_count_field_name` function to compute count field from array field name
- Handles plural-to-singular conversion (entries -> entry, layouts -> layout)
- Array memory is allocated with `malloc` (caller responsible for cleanup via `struct_free`)
- Test demonstrates creating bind groups using only auto-generated APIs (no hand-coded helpers)

### Next Steps
1. Continue reducing hand-coded helpers
2. Consider generating high-level OCaml builder functions for common patterns
3. Document the struct API usage patterns

---

## 2026-01-25: Reducing Hand-Coded Helpers

### Accomplished
- **Auto-generated `device_get_queue`**: Removed hand-coded version, now fully auto-generated
  - Removed from `method_is_manual` list
  - Removed C function `caml_wgpu_device_get_queue` from sync helpers
  - Removed manual external/val declarations from ML/MLI helpers
  - Method is now auto-generated from YAML spec

### Generator State Analysis
The generator now produces working bindings for:
- **All enums and bitflags** (58 enums, 6 bitflags)
- **All structs** with create/free/setters/getters (82 struct types)
- **Most object methods** that don't use callbacks
- **Methods with array arguments** (converted to count+pointer pairs)

### Remaining Hand-Coded Helpers
1. **Async Wrappers** (required - callbacks not supported):
   - `instance_request_adapter_sync`
   - `adapter_request_device_sync`
   - `buffer_map_sync`

2. **Special Return Types** (required - complex conversion):
   - `adapter_get_info` - returns OCaml record from C struct

3. **Bigarray Integration** (required - special memory handling):
   - `buffer_get_mapped_range_bigarray`
   - `buffer_get_const_mapped_range_bigarray`
   - `queue_write_buffer_bigarray`

4. **Convenience Helpers** (optional - simplify common patterns):
   - `device_create_shader_module_wgsl` - handles chained WGSL struct
   - `device_create_command_encoder_simple` - label-only convenience
   - `command_encoder_begin_compute_pass_simple` - label-only convenience
   - `command_encoder_finish_simple` - label-only convenience
   - `queue_submit_single` - single command buffer convenience
   - `compute_pass_encoder_set_bind_group_simple` - no dynamic offsets
   - `device_poll` - poll with optional wait
   - Various `*_simple` render helpers

### Auto-Generated Alternatives
For convenience helpers, auto-generated struct-based alternatives exist:
```ocaml
(* Using convenience helper *)
let encoder = device_create_command_encoder_simple device "my_encoder"

(* Using auto-generated APIs *)
let desc = Command_Encoder_Descriptor.command_encoder_descriptor_create () in
Command_Encoder_Descriptor.command_encoder_descriptor_set_label desc "my_encoder";
let encoder = device_create_command_encoder device desc in
Command_Encoder_Descriptor.command_encoder_descriptor_free desc;
```

### Next Steps
1. Document which APIs are auto-generated vs helper-based
2. Consider adding builder pattern in high-level API for ergonomics
3. Add more examples using struct-based APIs

---

## 2026-01-25: High-Level API Improvements

### Accomplished
- **Added `Adapter.request_device`**: Returns typed `Device.t` instead of nativeint
- **Added `Device.get_queue`**: Returns typed `Queue.t` instead of nativeint
- **Fixed module ordering**: Queue -> Device -> Adapter (respects OCaml dependencies)

### High-Level API Flow
```ocaml
let instance = Instance.create () in
let adapter = Instance.request_adapter instance in
let device = Adapter.request_device adapter in
let queue = Device.get_queue device in
(* Now use queue, device for GPU operations *)
Queue.release queue;
Device.release device;
Adapter.release adapter;
Instance.release instance
```

### Current High-Level Modules
- **Instance**: `create`, `release`, `request_adapter`
- **Adapter**: `release`, `get_info`, `request_device`
- **Device**: `release`, `get_queue`
- **Queue**: `release`
- **All other objects**: `release` only (more methods planned)

### Next Steps
1. Add more methods to Device module (create_buffer, create_shader_module, etc.)
2. Add ergonomic descriptor builders
3. Document the full API

---

## 2026-01-25: High-Level API Method Generation

### Accomplished
- **Major expansion of high-level API**: 168 methods now generated across all object modules
- **Method filtering**: Only generates methods with simple signatures (no callbacks, no struct args)
- **Keyword escaping**: OCaml reserved words like `end` renamed to `end_`
- **Dependency ordering**: Objects sorted so dependencies come first (Buffer before Command_Encoder)
- **Type conversions**:
  - Objects use qualified field access: `source.Buffer.handle`
  - Enums converted with `(Enum.to_int arg)`
  - Bitflags converted with `(Flags.list_to_int arg)`
  - Return types properly typed: `({ Module.handle = result } : Module.t)`

### Generated Methods (examples)
```ocaml
module Buffer : sig
  val get_size : t -> int64
  val get_usage : t -> int
  val get_map_state : t -> int
  val unmap : t -> unit
  val destroy : t -> unit
  ...
end

module Command_Encoder : sig
  val copy_buffer_to_buffer : t -> source:Buffer.t -> source_offset:int64 ->
    destination:Buffer.t -> destination_offset:int64 -> size:int64 -> unit
  val clear_buffer : t -> buffer:Buffer.t -> offset:int64 -> size:int64 -> unit
  ...
end

module Compute_Pass_Encoder : sig
  val set_pipeline : t -> pipeline:Compute_Pipeline.t -> unit
  val dispatch_workgroups : t -> workgroupCountX:int -> workgroupCountY:int ->
    workgroupCountZ:int -> unit
  val end_ : t -> unit
  ...
end
```

### Methods Not Yet Generated
Methods with these signature patterns are currently skipped:
- Callbacks (async methods like `request_adapter`)
- Struct arguments (like `create_buffer` which takes `BufferDescriptor`)
- Array arguments (like `submit` which takes command buffer array)

### Next Steps
1. ~~Add descriptor builder functions for common create methods~~ ✅
2. Consider adding `of_int` to enums/bitflags for return type conversion
3. ~~Add the special-cased Instance/Adapter/Device/Queue methods~~ ✅

---

## 2026-01-25: Builder Functions for High-Level API

### Accomplished
- **Device builder functions**: Create GPU resources with idiomatic OCaml API
  - `create_buffer` - buffers with labeled size, usage, mapped_at_creation
  - `create_shader_module` - shader from WGSL source
  - `create_command_encoder` - command encoder
  - `create_texture` - textures with size, format, usage, dimension, mip_level_count
  - `create_sampler` - sampler (basic)
  - `create_compute_pipeline` - compute pipeline from layout and shader
  - `create_render_pipeline` - render pipeline from shader module
  - `create_bind_group_layout_for_storage_buffer` - layout for storage buffer binding
  - `create_bind_group` - bind group with buffer binding
  - `create_pipeline_layout` - pipeline layout from bind group layout
  - `poll` - poll device for completed work

- **Queue methods**:
  - `submit` - submit command buffers
  - `write_buffer` - write data to buffer

- **Convenience functions** for command encoding:
  - `begin_compute_pass`, `begin_render_pass`, `finish`
  - `set_bind_group`, `set_bind_group_render`
  - `copy_texture_to_buffer`
  - `map_buffer`, `get_mapped_range`

### API Example
```ocaml
(* Create a buffer with labeled arguments *)
let buffer = Device.create_buffer device
  ~size:1024L
  ~usage:[Buffer_Usage.Storage; Buffer_Usage.Copy_dst]
  ~mapped_at_creation:false
  ()

(* Create a texture *)
let texture = Device.create_texture device
  ~size:(64, 64, 1)
  ~format:Texture_Format.Rgba8unorm
  ~usage:[Texture_Usage.Render_attachment; Texture_Usage.Copy_src]
  ()

(* Record and submit commands *)
let encoder = Device.create_command_encoder device () in
let pass = begin_render_pass encoder ~color_view ~clear_color:(1.0, 0.0, 0.0, 1.0) () in
Render_Pass_Encoder.draw pass ~vertex_count:3 ~instance_count:1 ~first_vertex:0 ~first_instance:0;
Render_Pass_Encoder.end_ pass;
let cmd_buffer = finish encoder () in
Queue.submit queue ~command_buffers:[cmd_buffer]
```

### Technical Details
- Builder functions internally create descriptors, set fields, call low-level functions, then free descriptors
- Uses optional parameters with sensible defaults
- Bitflag usage parameters accept lists: `~usage:[Buffer_Usage.Storage; Buffer_Usage.Copy_dst]`
- Status codes from sync functions are properly ignored

### Next Steps
1. ~~Convert all tests to use high-level API~~ ✅
2. Add vertex buffer support for custom geometry
3. Add texture sampling support
4. Document the complete high-level API

---

## 2026-01-25: Tests Converted to High-Level API

### Accomplished
- **All tests now use only the Wgpu module** (high-level API)
- Removed low-level API tests that were specific to struct generation
- Added new convenience functions:
  - `create_texture_view` - create texture view from texture
  - `get_const_mapped_range` - get const mapped buffer data as bigarray

### Test Suite (all passing)
1. **test_instance_and_adapter** - Instance and adapter enumeration
2. **test_buffer_creation** - Buffer creation with typed usage flags
3. **test_compute_shader** - Complete compute pipeline with GPU execution
4. **test_render_clear** - Render pass that clears to solid color
5. **test_render_triangle** - Full render pipeline with vertex/fragment shaders

### API Demonstrated in Tests
```ocaml
(* High-level buffer creation with type-safe usage flags *)
let buffer = Wgpu.Device.create_buffer device
  ~size:256L
  ~usage:[ Wgpu.Buffer_Usage.Storage; Wgpu.Buffer_Usage.Copy_dst ]
  ()

(* Typed texture format enum *)
let texture = Wgpu.Device.create_texture device
  ~size:(64, 64, 1)
  ~format:Wgpu.Texture_Format.Rgba8_unorm
  ~usage:[ Wgpu.Texture_Usage.Render_attachment; Wgpu.Texture_Usage.Copy_src ]
  ()

(* Convenience function for texture views *)
let view = Wgpu.create_texture_view texture ()

(* Type-safe map mode *)
Wgpu.map_buffer buffer ~mode:[ Wgpu.Map_Mode.Read ] ~offset:0L ~size:256L
```

### Code Reduction
- Test file reduced from 705 lines to 537 lines (~24% reduction)
- Removed verbose descriptor creation/cleanup boilerplate
- All tests more readable and maintainable

### Next Steps
1. Add vertex buffer support for custom geometry
2. Add texture sampling support
3. Document the complete high-level API
4. Consider adding more complex examples (textured quad, etc.)
