# OCaml Softbuffer Bindings - Implementation Plan

## Overview
Create safe, ergonomic OCaml bindings for the `softbuffer` Rust crate, allowing OCaml developers to create pixel-based graphics applications with minimal overhead.

## Architecture

### FFI Strategy
- **Rust Side**: Use `ocaml-rs` crate for type-safe OCaml FFI
- **OCaml Side**: Abstract types hide Rust implementation details
- **Memory Management**: Rust owns all window/surface/buffer objects; OCaml holds opaque handles
- **Event Loop**: Use `pump_events` pattern to give OCaml control instead of winit

### Key Design Principles
1. **Safety First**: All FFI boundaries must be memory-safe and panic-safe
2. **Zero-Copy Where Possible**: Use Bigarrays for pixel buffer access
3. **Ergonomic API**: Hide complexity, expose simple functions
4. **Gradual Feature Addition**: Start minimal, expand iteratively

## Phase 1: Rust Prototype (CURRENT)

### Goals
- Validate the pump_events approach works with softbuffer
- Confirm redraw scheduling outside RedrawRequested callback
- Test buffer access patterns

### Tasks
1. Create a minimal Rust-only example that:
   - Uses `pump_events` instead of `run`
   - Creates a window and softbuffer surface
   - Draws to the buffer outside of RedrawRequested
   - Calls `window.request_redraw()` to schedule redraws
   - Pumps events in a loop with explicit control flow

2. Test edge cases:
   - Resizing behavior
   - Multiple present() calls per frame
   - Buffer age tracking

### Success Criteria
- Application runs smoothly
- No panics or undefined behavior
- Drawing works correctly outside RedrawRequested

## Phase 2: FFI Infrastructure

### Rust Dependencies
```toml
[dependencies]
ocaml = "1.0"
ocaml-derive = "1.0"
softbuffer = { path = "./vendor/softbuffer" }
winit = { path = "./vendor/winit" }
```

### Core Rust Types

```rust
// Opaque handles that OCaml will hold
pub struct OcamlEventLoop { /* wrapper around EventLoop */ }
pub struct OcamlWindow { /* wrapper around Window + ApplicationHandler state */ }
pub struct OcamlSurface { /* wrapper around Surface */ }
pub struct OcamlBuffer<'a> { /* wrapper around Buffer<'a> */ }
```

### Rust API Functions (exported to OCaml)

```rust
// Event loop management
fn event_loop_new() -> OcamlEventLoop
fn event_loop_pump(event_loop: &mut OcamlEventLoop) -> (PumpStatus, Vec<Event>)

// Window management
fn window_create(event_loop: &OcamlEventLoop, title: String, width: u32, height: u32) -> OcamlWindow
fn window_surface_size(window: &OcamlWindow) -> (u32, u32)
fn window_request_redraw(window: &OcamlWindow)
fn window_close(window: &mut OcamlWindow)

// Surface management
fn surface_create(window: &OcamlWindow) -> OcamlSurface
fn surface_resize(surface: &mut OcamlSurface, width: u32, height: u32)
fn surface_buffer_mut(surface: &mut OcamlSurface) -> OcamlBuffer

// Buffer operations
fn buffer_width(buffer: &OcamlBuffer) -> u32
fn buffer_height(buffer: &OcamlBuffer) -> u32
fn buffer_age(buffer: &OcamlBuffer) -> u8
fn buffer_pixels(buffer: &mut OcamlBuffer) -> &mut [u32]  // as Bigarray
fn buffer_present(buffer: OcamlBuffer)
fn buffer_present_with_damage(buffer: OcamlBuffer, rects: Vec<Rect>)
```

### Event Representation

Winit events are complex. Strategy:
1. Initially support subset of events (CloseRequested, RedrawRequested, Resized, KeyboardInput, PointerMoved, PointerButton)
2. Convert Rust events to OCaml variant types
3. Expand event coverage incrementally

## Phase 3: OCaml API Layer

### Module Structure

```ocaml
(* winit_softbuffer.mli *)

module Event : sig
  type keyboard_event = {
    key_code: int option;
    text: string option;
    state: [ `Pressed | `Released ];
  }

  type pointer_event = {
    x: float;
    y: float;
    button: int option;
  }

  type t =
    | CloseRequested
    | RedrawRequested
    | Resized of { width: int; height: int }
    | KeyboardInput of keyboard_event
    | PointerMoved of pointer_event
    | PointerButton of pointer_event * [ `Pressed | `Released ]
end

module Rect : sig
  type t = {
    x: int;
    y: int;
    width: int;
    height: int;
  }
end

module Buffer : sig
  type t

  val width : t -> int
  val height : t -> int
  val age : t -> int

  (* Access pixels as a bigarray for zero-copy manipulation *)
  val pixels : t -> (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t

  val present : t -> unit
  val present_with_damage : t -> Rect.t list -> unit
end

module Surface : sig
  type t

  val resize : t -> width:int -> height:int -> unit
  val buffer : t -> Buffer.t
end

module Window : sig
  type t

  val create :
    ?width:int ->
    ?height:int ->
    ?title:string ->
    unit -> t

  val surface_size : t -> int * int
  val request_redraw : t -> unit
  val surface : t -> Surface.t
  val close : t -> unit
end

module EventLoop : sig
  type t
  type pump_status = Continue | Exit of int

  val create : unit -> t
  val pump : t -> pump_status * Event.t list
end

(* High-level convenience API *)
val run :
  init:(Window.t -> 'state) ->
  update:('state -> Event.t list -> 'state) ->
  render:('state -> Buffer.t -> unit) ->
  unit
```

### Implementation Notes

1. **Bigarray for Pixels**: Use `Bigarray.Array1.t` to provide zero-copy access to pixel buffer
2. **Resource Cleanup**: Implement finalizers for automatic cleanup
3. **Error Handling**: Convert Rust Results to OCaml exceptions with good error messages
4. **Thread Safety**: Document that all operations must happen on the main thread

## Phase 4: Build System

### Rust Build (Cargo)
- Create a `rust/` directory with a library crate
- Build as staticlib or cdylib
- Link against vendored winit and softbuffer

### OCaml Build (Dune)
```scheme
(library
 (name winit_softbuffer)
 (public_name winit-softbuffer)
 (libraries bigarray)
 (foreign_stubs
  (language c)
  (names winit_softbuffer_stubs)
  (flags -I rust/target/release))
 (foreign_archives rust/target/release/libwinit_ocaml))
```

### Build Script
- Build Rust library first
- Then build OCaml library that links against it
- Handle platform differences (Linux/macOS/Windows)

## Phase 5: Testing

### Test Strategy
1. **Unit Tests**: Test individual FFI functions
2. **Integration Tests**: Test full workflows
3. **Visual Tests**: Use Xvfb + screenshot comparison

### Test Infrastructure
```bash
# Start virtual framebuffer
Xvfb :99 -screen 0 800x600x24 &
export DISPLAY=:99

# Run test
./test_app

# Capture screenshot
import -window root screenshot.png

# Compare against expected
compare expected.png screenshot.png diff.png
```

### Test Cases
1. Basic window creation and display
2. Drawing patterns (gradient, checkerboard)
3. Event handling (keyboard, mouse)
4. Resizing behavior
5. Multiple windows
6. Buffer age and damage regions

## Phase 6: Examples and Documentation

### Examples to Create
1. `hello_window.ml` - Minimal window creation
2. `color_grid.ml` - Draw a grid of colors
3. `interactive.ml` - Mouse and keyboard input
4. `animation.ml` - Smooth animation loop
5. `damage_regions.ml` - Efficient partial updates

### Documentation
1. API documentation (odoc)
2. Tutorial: "Your First Pixel App"
3. Architecture guide
4. Performance tips
5. Platform-specific notes

## Technical Challenges and Solutions

### Challenge 1: Event Loop Control
**Problem**: Winit wants to own the event loop, but OCaml needs control
**Solution**: Use `pump_events` API to poll for events instead of callbacks

### Challenge 2: Buffer Lifetime
**Problem**: Buffer borrows Surface mutably; must ensure safety across FFI
**Solution**:
- Make buffer_present() consume the buffer (move semantics)
- Return new buffer handle on each buffer_mut() call
- Use Rust's type system to enforce "one buffer at a time"

### Challenge 3: Event Conversion
**Problem**: Winit events are complex Rust types with lifetimes
**Solution**:
- Clone/copy all event data immediately
- Convert to owned OCaml values
- Simplify event types for initial version

### Challenge 4: Multi-platform Support
**Problem**: Different platforms have different requirements
**Solution**:
- Focus on Linux (X11/Wayland) first
- Add macOS and Windows incrementally
- Use conditional compilation

### Challenge 5: Error Handling
**Problem**: Rust uses Result types, OCaml uses exceptions
**Solution**:
- Catch all Rust panics at FFI boundary
- Convert Results to exceptions with descriptive messages
- Never let Rust unwind into OCaml code

## Success Metrics

1. **Safety**: No segfaults, memory leaks, or undefined behavior
2. **Performance**: <1ms overhead per frame for FFI calls
3. **Ergonomics**: Simple examples under 50 lines of code
4. **Reliability**: All tests pass on Linux X11 and Wayland
5. **Documentation**: Complete API docs and tutorials

## Future Enhancements (Post-MVP)

1. Support for multiple windows
2. Fullscreen mode
3. Cursor management
4. DPI scaling support
5. Clipboard integration
6. Drag-and-drop support
7. IME (Input Method Editor) support
8. Mobile platform support (Android/iOS)
9. WebAssembly support
10. Integration with existing OCaml graphics libraries

## Timeline

- Phase 1 (Prototype): 1-2 hours
- Phase 2 (FFI): 3-4 hours
- Phase 3 (OCaml API): 2-3 hours
- Phase 4 (Build System): 1-2 hours
- Phase 5 (Testing): 2-3 hours
- Phase 6 (Examples/Docs): 2-3 hours

**Total Estimated Time**: 11-17 hours of focused development

## Getting Started

1. Create Rust prototype to validate approach
2. Set up basic FFI with minimal functionality
3. Iterate on API design based on real usage
4. Add features incrementally
5. Document everything as we go
