# wgpu-native-ocaml Progress

## 2026-01-26: Chained Struct Support Complete

### Accomplished
- Added chained struct support for WebGPU's extension pattern
- Extended IR with `Extension_in` and `Extension_out` variants that track what structs they extend
- Updated YAML parser to extract the `extends` field for extension structs
- Generated chain header functions for extension structs:
  - `set_chain_stype` - sets the sType in the chain header
  - `as_chained` - returns a pointer suitable for nextInChain
- Generated `set_next_in_chain` setter for base structs (Base_in, Base_out, Base_in_out)
- Removed the hardcoded `device_create_shader_module_wgsl` helper
- Updated high-level `Device.create_shader_module` to use auto-generated chain support

### Extension Structs Now Supported
All extension structs in webgpu.yml now have proper chain support:
- `Shader_source_spirv` (extends `shader_module_descriptor`)
- `Shader_source_wgsl` (extends `shader_module_descriptor`)
- `Render_pass_max_draw_count` (extends `render_pass_descriptor`)
- `Surface_source_*` variants for platform-specific windowing

### Files Changed
- `codegen/ir.ml` - Added Extension_in/Extension_out variants to struct_type
- `codegen/parse_yml.ml` - Parse `extends` field from YAML
- `codegen/gen_low.ml` - Generate chain header stubs for extensions, nextInChain setters for base structs
- `codegen/gen_high.ml` - Updated create_shader_module to use generated chain support

### Test Verification
All existing tests pass with the new auto-generated chain support:
- Compute shader test (uses create_shader_module with WGSL)
- Render clear test (uses create_shader_module)
- Triangle render test (uses create_shader_module)

---

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

---

## 2026-01-25: Method Validation for High-Level API

### Accomplished
- **Added method coverage validation** to the code generator
  - The generator now tracks all methods that aren't auto-generated
  - Methods must be explicitly listed in either:
    - `manual_implementations`: methods that will be hand-written
    - `intentionally_skipped`: methods that shouldn't be exposed
  - Build fails with helpful error message if any method is unaccounted for

### Validation Output Example
```
=== UNACCOUNTED METHODS ===
The following methods are not auto-generated and not listed in
manual_implementations or intentionally_skipped:

  UNACCOUNTED: device.get_lost_future (returns: non-simple)
  UNACCOUNTED: instance.wait_any (futures: Struct(future_wait_info))

Please add these methods to either:
  - manual_implementations (if you will implement them)
  - intentionally_skipped (if they should not be exposed)
```

### Benefits
- **No silent API gaps**: Every method in the WebGPU spec is explicitly accounted for
- **Clear documentation**: The `manual_implementations` list documents which methods need hand-written code
- **Future-proof**: When the WebGPU spec adds new methods, the build will fail until they're addressed

### Currently Tracked Methods
- **78 manually implemented methods** across all object types
- **6 intentionally skipped methods** (deprecated or internal APIs)
- Methods skipped for various reasons:
  - Async callbacks (e.g., `request_adapter`, `map_async`)
  - Struct input/output parameters (e.g., `create_buffer`, `get_limits`)
  - Array arguments with dynamic offsets (e.g., `set_bind_group`)
  - Pointer return types (e.g., `get_mapped_range`)

### Next Steps
1. ~~Extend generator to auto-generate struct-based methods~~ ✅
2. Add vertex buffer support for custom geometry
3. Add texture sampling support
4. Document the complete high-level API

---

## 2026-01-25: Struct-Based Method Auto-Generation

### Accomplished
- **Auto-generate methods with simple struct arguments**: The generator now automatically creates methods that take struct descriptors, expanding parameters from the struct's fields

- **Key additions to gen_high.ml**:
  - `is_simple_struct`: Detects input structs with only primitive/enum/object members
  - `method_has_simple_struct_arg`: Identifies methods with one simple struct arg
  - `gen_ml_method_with_struct`: Generates method implementation from struct fields
  - `gen_mli_method_with_struct`: Generates method signature from struct fields
  - Added check for `manual_implementations` to prevent duplicate generation
  - Cleaned up `manual_implementations` list, removing simple methods

- **Fixed module ordering**: `Texture_view` now defined before `Texture` since `Texture.create_view` returns `Texture_view.t`

### Auto-Generated Methods
Methods now auto-generated from struct descriptors:
- `Texture.create_view` - uses `texture_view_descriptor` with all fields as params
- `Command_encoder.finish` - uses `command_buffer_descriptor`
- `Render_bundle_encoder.finish` - uses `render_bundle_descriptor`
- Many simple methods removed from `manual_implementations`

### Enum Usage
**17 enum/bitflag types** now used in function signatures:
- `Texture_format` (5 uses)
- `Address_mode` (3 uses)
- `Filter_mode`, `Texture_dimension`, `Texture_aspect`, `Texture_view_dimension`, `Blend_factor`, `Backend_type` (2 uses each)
- `Load_op`, `Store_op`, `Compare_function`, `Query_type`, `Power_preference`, `Buffer_map_state`, `Texture_usage`, `Buffer_usage`, `Map_mode` (1 use each)

### Technical Details
- Only input structs (`Base_in`, `Standalone`) are auto-generated, not output structs
- Pointer must be immutable (input arg) for struct to be processed
- All struct fields become labeled parameters in the generated method
- Generated code creates descriptor, sets fields, calls low-level function, frees descriptor

### Code Statistics
- Total methods in high-level API: **241**
- Total enum/bitflag modules: **55**
- Enums used in API signatures: **17**

### Next Steps
1. Add vertex buffer support for custom geometry
2. Add texture sampling support
3. Document the complete high-level API
4. Consider expanding struct handling to more complex cases (nested structs)

---

## 2026-01-26: Advanced Method Auto-Generation

### Accomplished
- **Array argument support**: Methods with array parameters now auto-generate with list types
  - Updated `is_simple_arg_type` to handle arrays of simple types
  - Updated `high_level_arg_type` to return `elem_type list` for arrays
  - Updated `arg_to_low_level` to convert lists to arrays (Objects, Primitives, Enums)
  - Removed `set_bind_group`, `execute_bundles` from manual_implementations

- **Output struct support**: Methods with mutable pointer to output struct now auto-generate
  - Added `is_simple_output_struct` to detect output structs (`Base_out`, `Base_in_out`)
  - Added `method_has_output_struct_arg` to find output struct arguments
  - Added `gen_ml_method_with_output_struct` and MLI variant
  - Record types generated inside object modules (avoids circular dependencies)
  - `Surface.get_current_texture` now auto-generates with `surface_texture` record type

- **Array members in structs**: Structs with array members of simple types now work
  - Extended `is_simple_member_type` to allow arrays of simple types
  - Updated `member_to_low_level` to handle array conversion
  - Updated `high_level_member_type` for array member types
  - Arrays default to empty list

- **Multiple struct arguments**: Methods with multiple struct args now work
  - Replaced `method_has_simple_struct_arg` with `get_simple_struct_args` (returns list)
  - Added `method_has_simple_struct_args` for validation
  - Replaced `gen_ml_method_with_struct` with `gen_ml_method_with_structs`
  - Parameters prefixed with arg name when multiple structs (e.g., `source_texture`, `destination_buffer`)

### Methods Removed from manual_implementations
- `compute_pass_encoder.set_bind_group` - now auto-generates with array
- `render_pass_encoder.set_bind_group` - now auto-generates with array
- `render_pass_encoder.execute_bundles` - now auto-generates with array
- `render_bundle_encoder.set_bind_group` - now auto-generates with array
- `adapter.get_limits` - now auto-generates with output struct
- `device.get_limits` - now auto-generates with output struct

### Technical Details
- Fixed object ordering: Surface after Texture (surface_texture references Texture.t)
- Output struct record types placed inside object modules to avoid forward references
- Object field values from output structs properly converted (Enum.of_int, Object wrapping)

### Current Coverage
- **Auto-generated methods**: Majority of simple methods
- **Manual implementations remain for**:
  - Async/callback methods (request_adapter, map_async, etc.)
  - Chained struct patterns (shader module creation with WGSL chain)
  - "Special" objects (Instance, Adapter, Device, Queue) - hand-written for cleaner API

### Next Steps
1. Add vertex buffer support for custom geometry
2. Add texture sampling support
3. Document the complete high-level API

---

## 2026-01-26: Nested Struct Support Complete

### Accomplished
- **Nested struct support**: Structs containing nested struct members now fully auto-generate
  - Added `is_simple_member_type_with_nested` with circular reference detection
  - Added `is_simple_struct_aux` for recursive struct checking
  - Added `member_is_nested_struct` to detect struct-typed members
  - Added `collect_nested_structs` to recursively collect nested struct info
  - Added `collect_struct_params` to flatten nested struct parameters
  - Added `generate_struct_creates` to create all structs (nested first)
  - Added `generate_struct_sets` to set fields including nested struct assignments
  - Updated `gen_ml_method_with_structs` and `gen_mli_method_with_structs` to use new helpers
  - Fixed struct name handling (use original name, not lowercased)

### Methods Removed from manual_implementations
- `command_encoder.copy_buffer_to_texture` - uses nested structs
- `command_encoder.copy_texture_to_buffer` - uses nested structs
- `command_encoder.copy_texture_to_texture` - uses nested structs
- `render_pass_encoder.set_blend_constant` - uses simple struct (Color)

### Example Generated Code
The `copy_texture_to_buffer` method now auto-generates with flattened parameters:
```ocaml
let copy_texture_to_buffer t
    ~source_texture ~source_mip_level
    ~source_origin_x ~source_origin_y ~source_origin_z
    ~source_aspect
    ~destination_layout_offset ~destination_layout_bytes_per_row
    ~destination_layout_rows_per_image ~destination_buffer
    ~copy_size_width ~copy_size_height ~copy_size_depth_or_array_layers
    () =
  let source_origin_nested = Wgpu_low.Origin_3d.origin_3D_create () in
  let desc_source = Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_create () in
  let destination_layout_nested = Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_create () in
  let desc_destination = Wgpu_low.Texel_copy_buffer_info.texel_copy_buffer_info_create () in
  let desc_copy_size = Wgpu_low.Extent_3d.extent_3D_create () in
  (* ... set all fields including nested struct assignments ... *)
  Wgpu_low.command_encoder_copy_texture_to_buffer t.handle desc_source desc_destination desc_copy_size;
  (* ... free all structs in reverse order ... *)
```

### Technical Details
- Nested structs are created before parent structs
- Fields are set recursively: nested struct fields first, then nested struct assigned to parent
- Structs are freed in reverse order (parent first, then nested)
- Parameter names are prefixed: `source_origin_x` for `origin.x` in `source` argument
- Multiple levels of nesting are supported (recursive implementation)

### Next Steps
1. Add vertex buffer support for custom geometry
2. Add texture sampling support
3. Document the complete high-level API

---

## 2026-01-26: Obsolete Simple Helpers Removed

### Accomplished
- **Automatic object ordering**: Replaced hardcoded `object_order` list with dependency analysis
  - Added `extract_object_deps` to extract object references from type_ref
  - Added `get_object_dependencies` to find all object dependencies from methods
  - Updated `sort_objects` to use Kahn's algorithm with auto-computed dependencies
  - Dependencies now derived from both return types and parameter types

- **Removed all `_simple` C helper functions**: 5 hand-written helpers replaced with auto-generated struct-based versions
  - `copy_texture_to_buffer_simple` -> uses `Command_encoder.copy_texture_to_buffer`
  - `command_encoder_finish_simple` -> uses `Command_encoder.finish`
  - `compute_pass_encoder_set_bind_group_simple` -> uses `Compute_pass_encoder.set_bind_group`
  - `command_encoder_begin_compute_pass_simple` -> uses `Compute_pass_descriptor` struct
  - `device_create_command_encoder_simple` -> uses `Command_encoder_descriptor` struct
  - `device_create_compute_pipeline_simple` -> uses `Compute_pipeline_descriptor` + `Programmable_stage_descriptor` structs

### Code Reduction
- Removed 201 lines of C code
- Removed 57 lines of OCaml declarations
- High-level convenience functions now use auto-generated low-level struct APIs

### Technical Details
The auto-generated struct bindings have matured enough to handle the cases that
previously required hand-written C helpers:
- Simple descriptors (label only): `Command_encoder_descriptor`, `Compute_pass_descriptor`
- Nested structs: `Compute_pipeline_descriptor` with embedded `Programmable_stage_descriptor`
- Array arguments: `set_bind_group` with empty dynamic_offsets array

### Next Steps
1. Support descriptors with array members (bind group layout entries, etc.)
2. Add chained struct support (nextInChain pattern)

---

## 2026-01-26: Pointer-to-Array Support for Descriptors

### Accomplished
- **Pointer-to-array recognition**: Updated `is_simple_member_type` and `is_simple_member_type_with_nested`
  to recognize `Pointer { inner = Array _ }` as simple types
  - This is a common C idiom where arrays are passed as pointers
  - The low-level bindings already handle the pointer aspect

- **create_pipeline_layout supports multiple bind group layouts**:
  - Changed from `~bind_group_layout:Bind_group_layout.t` to `~bind_group_layouts:Bind_group_layout.t list`
  - Uses the auto-generated `Pipeline_layout_descriptor` struct with array setter
  - Removed `device_create_pipeline_layout_single` hardcoded C helper

### Technical Details
The YAML specification marks array members as `pointer: immutable`, which was causing the
IR parser to wrap the type in `Pointer { inner = Array _ }`. The `is_simple_member_type`
functions were rejecting all `Pointer` types, but pointer-to-array is semantically just
an array passed by reference, which we can handle.

### Remaining Work
The harder cases (`create_bind_group_layout`, `create_bind_group`) use arrays of structs
where each struct has nested struct members. This requires:
- Defining high-level OCaml record types for entry structs
- Generating code to convert lists of records to C struct arrays
- Handling nested struct creation/setting/freeing for each array element

### Next Steps
1. ~~Continue support for arrays of structs with nested struct members~~ ✅
2. Add chained struct support (nextInChain pattern)

---

## 2026-01-26: Array-of-Struct Support Complete

### Accomplished
- **Full array-of-struct support for descriptors**: Methods like `create_bind_group_layout` and `create_bind_group` can now use the full API with entry lists

- **Entry struct record types generated**:
  - `Bind_group_layout_entry.t` with nested struct fields for buffer/sampler/texture/storage_texture bindings
  - `Bind_group_entry.t` with optional object fields for buffer/sampler/texture_view
  - Nested struct modules: `Buffer_binding_layout`, `Sampler_binding_layout`, `Texture_binding_layout`, `Storage_texture_binding_layout`
  - All types properly handle optional fields (objects marked optional in spec become `option` types)

- **Key additions to gen_high.ml**:
  - `member_is_array_of_structs`: Detects array-of-struct member types
  - `get_array_entry_structs`: Finds entry structs used in arrays
  - `gen_entry_struct_module`: Generates OCaml record modules for entry structs
  - `gen_nested_struct_module`: Generates nested struct record modules
  - `entry_struct_member_type`: Handles type mapping for entry struct fields (including optional objects)
  - `entry_member_to_low_level`: Converts entry struct fields to low-level values
  - `generate_array_of_structs_conversion`: Generates code to convert record lists to C struct arrays
  - `collect_entry_structs`: Collects all entry structs from API for generation

- **New Device methods** (hand-written but using generated infrastructure):
  - `create_bind_group_layout`: Takes `entries:Bind_group_layout_entry.t list`
  - `create_bind_group_full`: Takes `entries:Bind_group_entry.t list`

### Generated Entry Struct Types
```ocaml
module Bind_group_layout_entry = struct
  module Buffer_binding_layout = struct
    type t = { type_ : Buffer_binding_type.t; has_dynamic_offset : bool; min_binding_size : int64 }
  end
  module Sampler_binding_layout = struct
    type t = { type_ : Sampler_binding_type.t }
  end
  module Texture_binding_layout = struct
    type t = { sample_type : Texture_sample_type.t; view_dimension : Texture_view_dimension.t; multisampled : bool }
  end
  module Storage_texture_binding_layout = struct
    type t = { access : Storage_texture_access.t; format : Texture_format.t; view_dimension : Texture_view_dimension.t }
  end
  type t = {
    binding : int;
    visibility : Shader_stage.t list;
    buffer : Buffer_binding_layout.t option;
    sampler : Sampler_binding_layout.t option;
    texture : Texture_binding_layout.t option;
    storage_texture : Storage_texture_binding_layout.t option
  }
end
```

### Usage Example
```ocaml
(* Create a bind group layout with full API *)
let layout = Wgpu.Device.create_bind_group_layout device
  ~entries:[
    { Wgpu.Bind_group_layout_entry.
      binding = 0;
      visibility = [Wgpu.Shader_stage.Compute];
      buffer = Some { type_ = Wgpu.Buffer_binding_type.Storage; has_dynamic_offset = false; min_binding_size = 0L };
      sampler = None;
      texture = None;
      storage_texture = None
    }
  ]
  ()
```

### Technical Details
- Entry struct modules are generated after object modules (to resolve object type dependencies)
- Optional object fields use match expressions: `(match entry.buffer with Some x -> x.Buffer.handle | None -> 0n)`
- Nested struct fields in entries use option types and are created conditionally
- Entry struct arrays are freed after the create call completes

### Next Steps
1. Write tests using the new full API methods
2. Add chained struct support (nextInChain pattern)
3. Document the complete high-level API

---

## 2026-01-26: Special Object Auto-Method Infrastructure

### Accomplished
- **Complete manual_implementations tracking**: Added all manually-implemented methods for special objects
  - Instance: `release`, `create_surface`, `process_events`, `request_adapter`, `get_WGSL_language_features`, `wait_any`
  - Adapter: `release`, `has_feature`, `get_info`, `request_device`, `get_features`
  - Device: 23 methods (release, destroy, has_feature, push_error_scope, set_label, poll, get_features, create_buffer, create_shader_module, create_command_encoder, create_texture, create_sampler, create_compute_pipeline, create_render_pipeline, create_bind_group_layout_for_storage_buffer, create_bind_group_layout, create_bind_group, create_bind_group_full, create_pipeline_layout, create_query_set, create_render_bundle_encoder, pop_error_scope, get_queue, get_lost_future, get_adapter_info)
  - Queue: `release`, `set_label`, `submit`, `write_buffer`, `write_texture`, `on_submitted_work_done`

- **Tuple return for auto-method generators**: `gen_special_object_auto_methods` and `gen_special_object_auto_methods_mli` now return `(output_struct_types, methods)` tuples
  - Output struct types placed inside Device module
  - Methods injected at the marked position

- **Triage tickets created** for methods that can't use standard generator:
  - `tasks/triage/async-methods.md`: Callback-based async methods (request_adapter, request_device, etc.)
  - `tasks/triage/output-struct-arrays.md`: Methods returning structs with dynamic arrays (get_features, get_capabilities)
  - `tasks/triage/pointer-data-methods.md`: Methods with raw pointer/size data patterns (write_buffer, get_mapped_range)
  - `tasks/triage/complex-descriptor-structs.md`: Methods with deeply nested descriptor structs (create_render_pipeline, begin_render_pass)

### Technical Details
The generator now has infrastructure to inject auto-generated methods into special object modules (Device, Queue, Adapter, Instance). While all methods are currently manually implemented for these objects, this infrastructure enables future migration of simpler methods to auto-generation.

### Next Steps
1. Write tests using the new full API methods
2. Add chained struct support (nextInChain pattern)
3. Document the complete high-level API
4. Gradually migrate simple special object methods to auto-generation

---

## 2026-01-26: Device Methods Migrated to Auto-Generation

### Accomplished
Migrated multiple Device methods from hardcoded implementations to auto-generation:

**Array-of-struct methods** (using entry struct infrastructure):
- `create_bind_group_layout` - takes `entries:Bind_group_layout_entry.t list`
- `create_bind_group` - takes `entries:Bind_group_entry.t list`
- `create_pipeline_layout` - takes `bind_group_layouts:Bind_group_layout.t list`

**Simple descriptor methods**:
- `create_query_set` - simple descriptor with label, type (enum), count
- `create_render_bundle_encoder` - descriptor with array of enums

**Simple methods** (no descriptors):
- `destroy` - no args, no return
- `has_feature` - enum arg, bool return
- `push_error_scope` - enum arg, no return
- `set_label` - string arg, no return

### Generator Improvements
- Fixed `default_value_for_type` to handle `Pointer { inner = Array _ }` as `[]`
- Fixed `generate_array_of_structs_conversion` to add type annotations on lambda parameters
- Fixed `member_to_low_level` to handle `Pointer { inner = Array { elem = Object/Enum } }`

### Code Reduction
- Removed ~200 lines of hardcoded implementations
- Methods now auto-generated from YAML specification
- Test updated to use new entries-based API for `create_bind_group`

### Methods Still Manual
- `release`, `get_queue`, `poll` - special return types or C helpers
- `create_buffer`, `create_texture`, `create_sampler` - complex descriptor handling
- `create_shader_module` - uses chained WGSL struct
- `create_compute_pipeline`, `create_render_pipeline` - deeply nested descriptors

### Next Steps
1. Consider migrating more descriptor-based methods
2. Add chained struct support (nextInChain pattern)
3. Document the complete high-level API

---

## 2026-01-27: Codegen Code Quality Report Complete

### Accomplished
- **Comprehensive code quality analysis** of the codegen library
- Created 10 detailed issue reports with proposed fixes
- Organized by implementation priority with effort/value assessment

### Report Location
`tasks/triage/code-quality/report.md` with individual issue files:

| File | Issue |
|------|-------|
| `01-hardcoded-templates.md` | Externalize ~500 lines of embedded code to template files |
| `02-split-large-files.md` | Break 2295+1882 line files into focused modules |
| `03-duplicated-logic.md` | Reduce ML/MLI generation duplication |
| `04-add-expect-tests.md` | Add Jane Street-style expect tests |
| `05-complex-return-types.md` | Replace tuple returns with named records |
| `06-configuration-extraction.md` | Move method config to dedicated module |
| `07-improve-naming.md` | Clarify vague names like "entry_struct", "simple" |
| `08-type-mapping-abstraction.md` | Centralize type mapping logic |
| `09-code-builder-abstraction.md` | Replace sprintf with structured code builder |
| `10-separate-concerns-in-method-gen.md` | Decompose 108-line method generation function |

### Recommended Priorities

**Phase 1 (Foundation):**
1. Add expect tests for utility functions
2. Extract configuration to dedicated module

**Phase 2 (Quick Wins):**
3. Externalize hardcoded templates
4. Improve naming clarity
5. Simplify complex return types

**Phase 3 (Major Refactoring):**
6. Create type mapping layer
7. Reduce ML/MLI duplication
8. Split large files

### Key Findings
- gen_high.ml (2295 lines) and gen_low.ml (1882 lines) need splitting
- ~500 lines of hardcoded OCaml/C code embedded as string literals
- No automated tests makes refactoring risky
- Significant duplication between ML and MLI generation
- Complex function signatures with opaque tuple return types

### Next Steps
1. Begin with Phase 1 items (tests and config extraction)
2. Address Phase 2 quick wins for immediate navigability improvement
3. Plan Phase 3 refactoring with test coverage in place
