# Split winit from softbuffer

In both the Rust bindings and the OCaml library, softbuffer and winit are bundled together.
I'd like you to split them into separate libraries that can be used together.  Adjust all the
demos to take advantage of this new split.

## Currently

The codebase has a single bundled architecture:

**Rust layer** (`rust/src/lib.rs`):
- `WinitOcamlApp` struct bundles everything: `EventLoop`, `EventCollector`, `GraphicsState`, and `Buffer`
- Single set of FFI functions: `winit_create`, `winit_pump_events`, `winit_get_buffer`, `winit_present`, etc.

**C stubs** (`ocaml/winit_stubs.c`):
- Single C file with all stubs
- Single custom block type for the bundled app

**OCaml layer** (`ocaml/winit_softbuffer.ml`):
- Single library `winit-softbuffer`
- Single opaque `app` type that does everything
- All examples use `open Winit_softbuffer`

**Examples**:
- `hello_window.ml` - uses combined library for window + drawing
- `paint.ml` - uses combined library for tablet drawing
- `test_ffi.ml` - tests the combined FFI

## Notes

**Key architectural insight**: Softbuffer requires a window handle to create its context and surface.
The dependency is: `Softbuffer.surface` depends on `Winit.window`.

**Rust ownership considerations**:
- The window is stored as `Arc<Box<dyn Window>>` for reference counting
- Softbuffer's `Context` and `Surface` hold references to the window
- The buffer lifetime is already managed with an unsafe transmute to `'static`
- We need to ensure the window outlives any softbuffer surfaces

**Target architecture**:

```
Winit library (windowing only):
  - create() -> window
  - pump_events(window) -> event list
  - Event types (keyboard, mouse, tablet, etc.)

Softbuffer library (pixel rendering only):
  - create(window) -> surface
  - get_buffer(surface) -> buffer
  - present(surface)
  - present_with_damage(surface, rects)
  - get_buffer_age(surface)
```

**Implementation plan**:

1. **Rust layer**: Split into two modules but keep in single crate
   - `winit_ffi.rs` - EventLoop, Window, Events
   - `softbuffer_ffi.rs` - Surface, Buffer, Present
   - Keep shared types in `lib.rs`

2. **C stubs**: Split into two files
   - `winit_stubs.c` - window/event handling
   - `softbuffer_stubs.c` - buffer/present handling

3. **OCaml layer**: Two separate libraries
   - `Winit` library with `window` type and event handling
   - `Softbuffer` library with `surface` type that takes a `Winit.window`

4. **Dune configuration**: Build two libraries that share the Rust FFI

5. **Examples**: Update to show explicit separation

## Addressing

Successfully split the monolithic `winit-softbuffer` library into two separate OCaml libraries:

### Rust Layer Changes
- Created `rust/src/winit_ffi.rs` with `WinitWindow` struct containing `EventLoop` and `EventCollector`
- Created `rust/src/softbuffer_ffi.rs` with `SoftbufferSurface` struct containing `GraphicsState` and buffer
- Modified `rust/src/lib.rs` to contain shared types (`Event`, `EventType`, `DamageRect`) and re-export modules
- Key design: `winit_window_get_handle` clones the `Arc<Box<dyn Window>>` for safe transfer to softbuffer

### C Stubs Changes
- Created `ocaml/winit/winit_stubs.c` with:
  - Custom block `winit_window_ops` with finalizer for window
  - Custom block `winit_window_handle_ops` without finalizer (non-owning reference)
  - Stubs for `create`, `pump_events`, `get_handle`, `test_version`
- Created `ocaml/softbuffer/softbuffer_stubs.c` with:
  - Custom block `softbuffer_surface_ops` with finalizer
  - Stubs for `create`, `resize`, `get_buffer`, `get_buffer_age`, `present`, `present_with_damage`

### OCaml Library Structure
- `ocaml/winit/` directory with `Winit` library:
  - `winit.ml/mli` - window type, all event types, `pump_events`, `get_handle`
  - `dune` - includes Rust build rule and library definition
- `ocaml/softbuffer/` directory with `Softbuffer` library:
  - `softbuffer.ml/mli` - surface type, `damage_rect`, buffer/present functions
  - `dune` - depends on winit library, no Rust linking needed

### Examples Updated
- `hello_window.ml` - uses `Winit.create`, `Softbuffer.create`, explicit `Softbuffer.resize` on window resize
- `paint.ml` - updated to use split API with Winit and Softbuffer modules
- `test_ffi.ml` - uses Winit module directly

### Files Removed
- `ocaml/winit_softbuffer.ml`, `ocaml/winit_softbuffer.mli`
- `ocaml/winit_stubs.c`, `ocaml/dune`
- `winit-softbuffer.opam`

### Documentation
- Updated `developer.md` with new architecture diagrams and descriptions
- Updated `readme.md` with new example code and features

### Verification
All tests pass:
- `./build.sh` - builds without warnings
- `test_ffi.exe` - FFI test returns version 100
- `hello_window.exe` - window displays and handles events
- `paint.exe` - tablet drawing works
- `./fmt.sh` - formatting passes
