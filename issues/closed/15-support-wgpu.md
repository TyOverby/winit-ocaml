# Support wgpu

I just vendored the `wgpu-ocaml` project into `vendor/wgpu-ocaml`.  This
project adds high level bindings to the `wgpu-native` library.

The bindings work, and they've demonstrated their use by rendering out to image
files on disk, but so far we don't have a way to display anything on screen.

Your task is to connect our `winit` bindings with `wgpu-ocaml` and get a wgpu
"hello triangle" to draw to the screen.  This will likely involve getting a raw
surface handle from winit to pass to `wgpu-ocaml`.  If the `wgpu-ocaml`
bindings aren't sufficient to implement this, please extend them.

## Currently

The wgpu-ocaml project is vendored at `vendor/wgpu-ocaml/` and provides:
- **High-level API** (`wgpu` library): User-friendly wrappers around wgpu-native
- **Low-level API** (`wgpu_low` library): Direct bindings to the wgpu-native C API

The low-level API already has surface creation functions:
- `Wgpu_low.Surface_source_xlib_window` - for X11 (Xlib) windows
- `Wgpu_low.Surface_source_wayland_surface` - for Wayland windows
- `Wgpu_low.instance_create_surface` - creates a surface from a descriptor

The winit library already exports a `window_handle` type for use with softbuffer,
but it doesn't expose the raw X11/Wayland handles needed by wgpu.

## Notes

To create a wgpu Surface from a winit window:

1. **Extract raw window handles**: Use Rust's `raw-window-handle` crate (already a
   dependency in winit_ffi) to get platform-specific handles:
   - X11: Display pointer + Window ID
   - Wayland: wl_display pointer + wl_surface pointer

2. **Create wgpu surface descriptor**: Using wgpu-ocaml low-level API:
   - Create `Surface_source_xlib_window` or `Surface_source_wayland_surface`
   - Set the display and window/surface pointers
   - Chain it to a `Surface_descriptor`
   - Call `instance_create_surface`

3. **Platform detection**: Need to detect whether running on X11 or Wayland at
   runtime and use the appropriate surface source.

Implementation approach:
- Add FFI functions to winit_ffi to extract X11/Wayland handles
- Add OCaml bindings to expose these
- Create a helper library `winit_wgpu` that bridges winit and wgpu-ocaml
- Write a hello_triangle_wgpu.ml example

## Addressing

### Changes Made

1. **Extended winit bindings for raw window handles**:
   - Added `raw_handle_backend` type (X11, Wayland, Win32, AppKit, Unknown)
   - Added `raw_window_handle` record type containing platform-specific data
   - Added `get_raw_handle` function to extract X11/Wayland/Win32 handles
   - Modified Rust FFI (`winit/ffi/src/ffi.rs`) to use `raw-window-handle` crate

2. **Created winit_wgpu bridge library** (`winit_wgpu/`):
   - `winit_wgpu.ml` with `create_surface` function that:
     - Detects window backend (X11, Wayland, Win32)
     - Creates appropriate wgpu surface source struct
     - Sets the sType and platform-specific handles
     - Creates wgpu surface via `instance_create_surface`

3. **Extended wgpu-ocaml high-level API**:
   - Added `Instance.to_low_level` in codegen template (`instance_module.ml`)
   - Added `Surface.of_low_level` in codegen template (`adapter_module_suffix.ml`)
   - These functions enable bridging between high-level and low-level APIs

4. **Fixed wgpu-ocaml codegen for void* pointer fields**:
   - Modified `codegen/gen_low.ml` to handle `Pointer { inner = Primitive C_void }`
   - This fixes setters for `display`, `surface` fields in surface source structs
   - Previously these were TODO stubs that did nothing

5. **Integrated wgpu-ocaml into main dune workspace**:
   - Removed `vendor/wgpu-ocaml/dune-project` to make it part of main workspace
   - Added `wgpu` package to main `dune-project`

6. **Created hello_triangle_wgpu example** (`examples/hello_triangle_wgpu.ml`):
   - Demonstrates GPU-accelerated rendering to a winit window
   - Creates wgpu instance, adapter, device, queue
   - Creates surface from winit window via `Winit_wgpu.create_surface`
   - Renders a green triangle using WGSL shader
   - Handles window resize events

### Files Modified

- `winit/ffi/src/ffi.rs` - Added raw handle extraction
- `winit/src/winit.ml` and `winit/src/winit.mli` - Added raw handle types/functions
- `winit/src/winit_stubs.c` - Added C stubs for raw handle FFI
- `winit_wgpu/src/winit_wgpu.ml` and `.mli` - New bridge library
- `winit_wgpu/src/dune` - Build config for winit_wgpu
- `vendor/wgpu-ocaml/codegen/gen_low.ml` - Fixed void* pointer setters
- `vendor/wgpu-ocaml/codegen/templates/high/instance_module.ml{,i}` - Added to_low_level
- `vendor/wgpu-ocaml/codegen/templates/high/adapter_module_suffix.ml{,i}` - Added of_low_level
- `examples/hello_triangle_wgpu.ml` - New example
- `examples/dune` - Added hello_triangle_wgpu target
- `dune-project` - Added wgpu package
