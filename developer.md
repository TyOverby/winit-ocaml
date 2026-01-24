# Developer Documentation

This document explains the architecture, design decisions, and contribution
guidelines for winit-ocaml, a project that provides OCaml bindings for
pixel-based graphics programming using the Rust winit and softbuffer libraries.

## Table of Contents

- [Project Overview](#project-overview)
- [Architecture](#architecture)
- [Key Design Decisions](#key-design-decisions)
- [Build System](#build-system)
- [Contributing](#contributing)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)

## Project Overview

### What This Project Does

winit-ocaml provides safe, ergonomic OCaml bindings for creating graphical
applications with direct pixel buffer access. It bridges two distinct runtime
environments:

- **OCaml**: A functional programming language with garbage collection and
  a runtime that expects to control program flow
- **Rust**: A systems programming language with manual memory management, used
  here via the winit (windowing) and softbuffer (pixel rendering) libraries

The project enables OCaml developers to create window-based applications where
they have direct access to a pixel buffer for custom rendering, suitable for
games, visualizations, pixel art tools, and educational graphics applications.

### Library Split

The project provides **two separate OCaml libraries**:

- **`winit`**: Window creation and event handling
- **`softbuffer`**: Pixel buffer rendering (depends on winit)

This separation allows applications to use just the windowing functionality
without the softbuffer dependency, and enables future alternative rendering
backends.

## Architecture

### Three-Layer Design

The project uses a three-layer architecture to bridge OCaml and Rust:

```
┌─────────────────────────────────────────────────────┐
│              OCaml Application                       │
│   (User code in OCaml)                              │
└──────────────┬───────────────────┬──────────────────┘
               │                   │
               ↓                   ↓
┌──────────────────────┐  ┌──────────────────────────┐
│    Winit Library     │  │   Softbuffer Library     │
│  (winit/src/)        │  │  (softbuffer/src/)       │
│  - Window creation   │  │  - Pixel buffer access   │
│  - Event handling    │  │  - Present/damage        │
│  - All event types   │←─│  - Depends on Winit      │
└──────────┬───────────┘  └──────────┬───────────────┘
           │                         │
           ↓                         ↓
┌──────────────────────┐  ┌──────────────────────────┐
│   C Stubs Layer      │  │    C Stubs Layer         │
│   (winit_stubs.c)    │  │  (softbuffer_stubs.c)    │
│  - OCaml runtime     │  │  - Bigarray wrapping     │
│  - Custom blocks     │  │  - Damage rects          │
└──────────┬───────────┘  └──────────┬───────────────┘
           │                         │
           ↓                         ↓
┌──────────────────────┐  ┌──────────────────────────┐
│   Rust FFI Layer     │  │    Rust FFI Layer        │
│   (winit/ffi/)       │  │   (softbuffer/ffi/)      │
│   - WinitWindow      │  │   - SoftbufferSurface    │
│   - EventCollector   │  │   - Buffer management    │
│   - Shared types     │  │   - Uses winit_ffi types │
└──────────────────────┘  └──────────────────────────┘
```

### Why Three Layers?

**Why not OCaml → Rust directly?**
- The OCaml runtime requires specific C calling conventions and memory management integration
- OCaml's external declarations work through C stubs that understand OCaml's value representation
- Direct Rust FFI would bypass OCaml's GC, leading to memory safety issues

**Why not use existing Rust-OCaml FFI crates?**
- We initially considered using the `ocaml-rs` crate for type-safe OCaml FFI
  However, the C stub approach is simpler, more portable, and gives us complete
  control over memory management
- C stubs are the standard approach for OCaml FFI and are well-documented
- We can always refactor to `ocaml-rs` later if the safety benefits outweigh the added complexity

### Component Details

#### 1. Rust FFI Layer

The Rust layer is split into two separate crates:

**`winit/ffi/src/lib.rs`** - Shared types and window FFI:
```rust
// Shared C-compatible types
pub struct DamageRect { x: u32, y: u32, width: u32, height: u32 }
pub enum EventType { NoEvent, CloseRequested, SurfaceResized, ... }
pub struct Event { event_type: EventType, data: [i32; 16] }

pub struct WinitWindow {
    event_loop: Option<EventLoop>,
    collector: EventCollector,  // holds Arc<Box<dyn Window>>
}

// FFI functions
pub extern "C" fn winit_window_create() -> *mut WinitWindow;
pub extern "C" fn winit_window_pump_events(...) -> i32;
pub extern "C" fn winit_window_get_handle(...) -> *const c_void;
pub extern "C" fn winit_window_destroy(...);
```

**`softbuffer/ffi/src/lib.rs`** - Rendering surface (depends on winit_ffi):
```rust
use winit_ffi::DamageRect;

pub struct SoftbufferSurface {
    window_ref: Arc<Box<dyn Window>>,  // keeps window alive
    graphics: GraphicsState,            // context + surface
    buffer: Option<Buffer<'static>>,    // current pixel buffer
}

// FFI functions
pub extern "C" fn softbuffer_surface_create(handle: *const c_void) -> *mut SoftbufferSurface;
pub extern "C" fn softbuffer_surface_get_buffer(...);
pub extern "C" fn softbuffer_surface_present(...);
pub extern "C" fn softbuffer_surface_destroy(...);
```

**Critical Design Decision: The `pump_events` Pattern**

winit normally wants to own the main loop via `EventLoop::run()`, which takes
a callback and never returns. This is incompatible with OCaml, which needs to
control the main loop for its own runtime.

The solution is winit's `pump_events` API (via the `EventLoopExtPumpEvents` trait extension):

```rust
event_loop.pump_app_events(Some(Duration::ZERO), &mut self.collector);
```

This non-blocking call:
1. Polls the OS for new window events
2. Dispatches them to our `ApplicationHandler` implementation
3. Returns immediately, giving control back to OCaml
4. Returns a `PumpStatus` indicating if we should continue or exit

This is the **most critical architectural decision** in the entire project, as
it enables the OCaml-controlled event loop pattern.

**Memory Management: Window Handle Transfer**

The split architecture requires safely transferring window handles between
Winit and Softbuffer. The solution uses Arc reference counting:

1. WinitWindow stores `Arc<Box<dyn Window>>`
2. `winit_window_get_handle` clones the Arc (incrementing ref count)
3. `softbuffer_surface_create` takes ownership of that Arc reference
4. The window lives as long as either WinitWindow or SoftbufferSurface exists

**Lifetime Extension Hack: Buffer Safety**

The pixel buffer from softbuffer has a lifetime tied to the surface borrow:

```rust
let buffer: Buffer<'surface> = surface.buffer_mut()?;
```

But OCaml needs to hold onto this buffer across FFI calls. The solution is
a carefully controlled unsafe lifetime extension:

```rust
let buffer: Buffer<'static> = unsafe { std::mem::transmute(buffer) };
self.buffer = Some(buffer);
```

This is safe because:
1. We store the buffer inside `SoftbufferSurface`, ensuring it doesn't outlive the surface
2. OCaml must call `present()` before the next `get_buffer()`, consuming the old buffer
3. The surface is destroyed only when OCaml drops its handle, properly sequencing cleanup

#### 2. C Stubs Layer

**`winit/src/winit_stubs.c`** - Window stubs:
```c
// Custom block with finalizer for window
static struct custom_operations winit_window_ops = {
    "winit_window",
    winit_window_finalize,  // Calls winit_window_destroy
    ...
};

// Custom block WITHOUT finalizer for handle (non-owning)
static struct custom_operations winit_window_handle_ops = {
    "winit_window_handle",
    custom_finalize_default,  // No cleanup - ownership transfers
    ...
};
```

**`softbuffer/src/softbuffer_stubs.c`** - Surface stubs:
```c
// Custom block with finalizer for surface
static struct custom_operations softbuffer_surface_ops = {
    "softbuffer_surface",
    softbuffer_surface_finalize,  // Calls softbuffer_surface_destroy
    ...
};

// Bigarray wrapping for zero-copy pixel access
ba = caml_ba_alloc(CAML_BA_INT32 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL, 1, buffer, dims);
```

#### 3. OCaml API Layer

**`winit/src/winit.ml`** - Window API:
```ocaml
type window        (* Opaque - owns event loop and window *)
type window_handle (* Opaque - non-owning reference for softbuffer *)

val create : unit -> window
val pump_events : window -> event list
val get_handle : window -> window_handle  (* For passing to Softbuffer *)
```

**`softbuffer/src/softbuffer.ml`** - Rendering API:
```ocaml
type surface  (* Opaque - owns rendering surface *)

val create : Winit.window_handle -> surface
val resize : surface -> width:int -> height:int -> unit
val get_buffer : surface -> int * int * (int32, ...) Bigarray.Array1.t
val present : surface -> unit
val present_with_damage : surface -> damage_rect array -> unit
```

## Key Design Decisions

### 1. Library Split (Winit vs Softbuffer)

**Decision:** Split into two separate OCaml libraries with explicit dependency.

**Why:**
- Matches the Rust ecosystem design (winit and softbuffer are separate crates)
- Allows using winit without softbuffer
- Enables future alternative rendering backends (GPU, etc.)
- Clearer separation of concerns

**API Pattern:**
```ocaml
let window = Winit.create () in
let surface = Softbuffer.create (Winit.get_handle window) in

(* Event loop *)
while not !should_exit do
  List.iter (fun event ->
    match event with
    | Winit.SurfaceResized { width; height } ->
        Softbuffer.resize surface ~width ~height
    | Winit.CloseRequested -> should_exit := true
    | _ -> ()
  ) (Winit.pump_events window);

  let _, _, buffer = Softbuffer.get_buffer surface in
  (* draw to buffer *)
  Softbuffer.present surface
done
```

### 2. Pump Events Pattern (OCaml Controls the Loop)

**Decision:** Use winit's `pump_events` API instead of the callback-based `run()` API.

**Why:**
- OCaml applications expect to control their main loop
- OCaml's runtime has its own event handling and GC that must run on the main thread
- Callback-based APIs would invert control flow, making OCaml-side logic awkward
- The pump pattern allows OCaml to poll for events on its own schedule

**Trade-offs:**
- ✅ OCaml has complete control over frame timing
- ✅ Easy to integrate with other event sources (network, timers, etc.)
- ✅ Natural OCaml style with explicit loops
- ⚠️ Slightly less efficient than callback-based approach (negligible in practice)
- ⚠️ Must call `pump_events` regularly or UI becomes unresponsive

### 3. Three-Layer Architecture (Rust → C → OCaml)

**Decision:** Use C stubs as an intermediate layer instead of direct Rust-to-OCaml FFI.

**Why:**
- OCaml's FFI is designed around C calling conventions
- C stubs handle OCaml value representation and GC integration
- Proven, stable approach used by most OCaml FFI bindings
- Clear separation of concerns (Rust = logic, C = marshaling, OCaml = API)

### 4. Zero-Copy Buffer Access via Bigarray

**Decision:** Expose the pixel buffer as a Bigarray backed by Rust memory.

**Why:**
- Bigarrays are OCaml's mechanism for working with large external data
- Zero-copy means no performance overhead for buffer access
- Natural OCaml API for array-like operations
- Compatible with other numeric libraries

**Trade-offs:**
- ✅ Excellent performance (no copying)
- ✅ Familiar OCaml API
- ✅ Can use Array1.unsafe_get/set for maximum speed
- ⚠️ Buffer lifetime must be carefully managed
- ⚠️ Users must understand buffer invalidation rules

### 5. Explicit Resize

**Decision:** Require explicit `Softbuffer.resize` call when window is resized.

**Why:**
- Matches how most graphics applications work
- User must handle SurfaceResized events explicitly
- Clear control over when buffer reallocation happens
- Avoids hidden allocation in get_buffer

**Usage:**
```ocaml
| Winit.SurfaceResized { width; height } ->
    Softbuffer.resize surface ~width ~height
```

### 6. Tablet Support

**Implementation:** Full support for graphics tablets (Wacom, etc.) on X11/Linux with pressure and tilt data.

**How it works:**
- The vendored winit fork includes custom patches to properly handle tablet events on X11
- Tablet devices (pens, erasers) are detected by the presence of pressure and tilt valuators
- The Device struct stores which valuator index corresponds to pressure, tilt_x, and tilt_y
- When tablet events arrive, the data is extracted from valuators and encoded as PointerSource::TabletTool
- This is then passed through to OCaml as `Winit.Tablet` in PointerMoved events
- Pressure and tilt information is available in the tablet_data record

**Platform support:**
- ✅ **X11/Linux**: Full support with pressure and tilt
- ⚠️ **Wayland/Linux**: Depends on winit's upstream Wayland tablet support
- ⚠️ **macOS/Windows**: Not yet tested

### 7. Damage Tracking and Optimized Presentation

**Implementation:** Support for `present_with_damage` to optimize display updates by only
redrawing changed regions of the buffer.

**API Functions:**

1. **`Softbuffer.get_buffer_age : surface -> int`**
   - Returns the buffer age (0 = new buffer with unspecified contents, 1+ = reused buffer)
   - Applications should check age: if 0, must redraw everything; if >0, can use damage regions

2. **`Softbuffer.present_with_damage : surface -> damage_rect array -> unit`**
   - Presents only the specified damaged regions
   - `damage_rect` has fields: `x`, `y`, `width`, `height` (all integers)
   - Falls back to full present on unsupported platforms

**Platform support:**
- ✅ **Wayland**: Full support
- ✅ **X11**: Supported when XShm is available
- ✅ **Win32**: Supported
- ✅ **Web**: Supported
- ⚠️ Other platforms fall back to full present

## Build System

### Overview

The build process is fully integrated through Dune, which automatically handles:
1. **Cargo**: Builds the Rust FFI libraries (invoked automatically by Dune)
2. **C Compiler**: Compiles the C stubs (invoked by Dune)
3. **OCaml Compiler**: Builds the OCaml libraries and links everything together

### Unified Build Command

Simply run:

```bash
dune build
```

Or use the convenience script:

```bash
./build.sh
```

Dune will automatically:
- Detect changes in Rust source files
- Invoke `cargo build` (dev mode) or `cargo build --release` (release mode) when needed
- Copy the resulting libraries to the build directory
- Compile C stubs and OCaml code
- Link everything together

### Build Profiles

- **Development builds** (default):
  ```bash
  dune build
  ```
  Uses `cargo build` (debug mode, unoptimized, faster compilation)

- **Release builds**:
  ```bash
  dune build --profile release
  ```
  Uses `cargo build --release` (optimized, slower compilation, faster runtime)

### How It Works

The project is organized with each library containing both Rust FFI and OCaml code:
- `winit/ffi/` - Rust FFI crate for winit
- `winit/src/` - OCaml library with C stubs
- `softbuffer/ffi/` - Rust FFI crate for softbuffer (depends on winit_ffi)
- `softbuffer/src/` - OCaml library with C stubs

Each library's `dune` file builds its corresponding Rust FFI crate.

**Platform-Specific Linking:**

On Linux, winit needs:
- X11 libraries: `libxcb`, `libX11`, `libxkbcommon`
- Wayland libraries: `libwayland-client`, `libwayland-cursor`
- System libraries: `libdl`, `libpthread`

These are typically available via package manager:
```bash
# Debian/Ubuntu
apt install libxcb-dev libx11-dev libxkbcommon-dev libwayland-dev

# Arch Linux
pacman -S libxcb libx11 libxkbcommon wayland
```

### Building Examples

```bash
dune exec examples/hello_window.exe
dune exec examples/paint.exe
dune exec examples/test_ffi.exe
```

## Contributing

### Code Style

**Rust:**
- Follow Rust 2021 edition idioms
- Use `rustfmt` for formatting
- Prefer safe code; document all `unsafe` with safety invariants
- Add tests for FFI functions where possible

**C:**
- Follow OCaml FFI conventions
- Always use `CAMLparam`, `CAMLlocal`, `CAMLreturn` macros
- Check for NULL pointers before dereferencing
- Document memory ownership

**OCaml:**
- Follow OCaml community style guidelines
- Use `dune fmt` for formatting (ocamlformat)
- Prefer immutability and functional patterns
- Add .mli documentation for all public functions

**Formatting:**
Format all code (OCaml and Rust) with the convenience script:

```bash
./fmt.sh
```

### Adding New Features

#### Adding a New Event Type

1. Add variant to Rust enum (`winit/ffi/src/lib.rs`):
   ```rust
   pub enum EventType {
       // ...
       NewEvent = 21,
   }
   ```

2. Handle it in `winit/ffi/src/ffi.rs` `ApplicationHandler::window_event`:
   ```rust
   WindowEvent::SomeNewEvent { data } => {
       self.events.push(Event {
           event_type: EventType::NewEvent,
           data1: data,
           data2: 0,
       });
   }
   ```

3. Add to OCaml type (`winit/src/winit.mli` and `.ml`):
   ```ocaml
   type event =
     | (* ... *)
     | NewEvent of { ... }

   let event_of_raw event_type data =
     (* ... *)
     | 21 -> NewEvent { ... }
   ```

4. Document the event's data fields

#### Adding a New Softbuffer API Function

1. Implement in Rust `softbuffer/ffi/src/lib.rs` with `#[no_mangle]` and `extern "C"`:
   ```rust
   #[no_mangle]
   pub extern "C" fn softbuffer_surface_new_function(surface: *mut SoftbufferSurface) -> i32 {
       // Implementation
   }
   ```

2. Declare in `softbuffer/src/softbuffer_stubs.c` and create stub:
   ```c
   extern int softbuffer_surface_new_function(void* surface);

   CAMLprim value caml_softbuffer_surface_new_function(value surface_val) {
       CAMLparam1(surface_val);
       void* surface = softbuffer_surface_val(surface_val);
       int result = softbuffer_surface_new_function(surface);
       CAMLreturn(Val_int(result));
   }
   ```

3. Add external declaration and wrapper in `softbuffer/src/softbuffer.ml`:
   ```ocaml
   external new_function : surface -> int = "caml_softbuffer_surface_new_function"
   ```

4. Update `softbuffer/src/softbuffer.mli` with documentation

## Testing

Standard unit tests and headless integration tests can be run with `./test.sh`

### Manual testing

```bash
# FFI smoke test (works without display)
dune exec examples/test_ffi.exe

# Full graphical test (requires display)
dune exec examples/hello_window.exe

# Tablet/painting test
dune exec examples/paint.exe

# With Xvfb (headless)
Xvfb :99 & DISPLAY=:99 dune exec examples/hello_window.exe
```

### Memory Testing

Check for leaks with valgrind:

```bash
valgrind --leak-check=full --show-leak-kinds=all dune exec examples/hello_window.exe
```

Expected output: No leaks from our code (may see leaks from X11 drivers).

## Troubleshooting

### Build Issues

**Problem:** `undefined reference to 'winit_window_create'`

**Solution:**
- Clean and rebuild everything:
  ```bash
  ./clean.sh && ./build.sh
  ```
- Verify Rust sources are present in `winit/ffi/src/`
- Check that cargo is installed and accessible: `cargo --version`
- Verify symbols are exported: `nm target/debug/libwinit_ffi.a | grep winit_window`

### Runtime Issues

**Problem:** `NotSupported: neither WAYLAND_DISPLAY nor DISPLAY is set`

**Solution:**
- Running on a system without a display server
- Set `DISPLAY` for X11: `export DISPLAY=:0`
- Use Xvfb for headless: `Xvfb :99 & export DISPLAY=:99`

**Problem:** Segmentation fault

**Solution:**
- Check that buffer isn't used after `present()` (buffer is consumed)
- Verify surface isn't used after window is dropped
- Run with `gdb` or `valgrind` to find the issue

**Problem:** Window appears but is unresponsive

**Solution:**
- Ensure `pump_events()` is called regularly (every frame)
- Check that main loop isn't blocked

## Additional Resources

- [winit documentation](https://docs.rs/winit)
- [softbuffer documentation](https://docs.rs/softbuffer)
- [OCaml FFI manual](https://ocaml.org/manual/intfc.html)
- [Design docs in docs/old/](./docs/old/)

## Project Structure Reference

```
winit-ocaml/
├── Cargo.toml               # Rust workspace configuration
├── build.sh                 # Convenience script: build everything
├── clean.sh                 # Convenience script: clean all build artifacts
├── fmt.sh                   # Convenience script: format all code
├── test.sh                  # Convenience script: run tests
├── winit/                   # Winit library (window creation & events)
│   ├── ffi/                 # Rust FFI crate
│   │   ├── Cargo.toml
│   │   └── src/
│   │       ├── lib.rs       # Shared types + module exports
│   │       └── ffi.rs       # WinitWindow, EventCollector
│   └── src/                 # OCaml library
│       ├── dune             # Build config (includes Rust build)
│       ├── winit.ml         # OCaml implementation
│       ├── winit.mli        # Public API interface
│       └── winit_stubs.c    # C FFI bridge
├── softbuffer/              # Softbuffer library (pixel buffer rendering)
│   ├── ffi/                 # Rust FFI crate
│   │   ├── Cargo.toml
│   │   └── src/
│   │       └── lib.rs       # SoftbufferSurface, buffer management
│   └── src/                 # OCaml library
│       ├── dune             # Build config
│       ├── softbuffer.ml    # OCaml implementation
│       ├── softbuffer.mli   # Public API interface
│       └── softbuffer_stubs.c # C FFI bridge
├── vendor/                  # Vendored dependencies (git submodules)
│   ├── winit/               # Vendored winit library
│   └── softbuffer/          # Vendored softbuffer library
├── examples/                # Example applications
│   ├── dune                 # Example build config
│   ├── hello_window.ml      # Graphical demo
│   ├── paint.ml             # Tablet painting demo
│   ├── test_ffi.ml          # FFI test
│   └── prototype/           # Rust prototypes
├── image_buf/               # Image buffer utility library
├── docs/                    # Design documentation
├── issues/                  # Project issue tracking
├── dune-project             # Top-level Dune config
├── readme.md                # User-facing documentation
├── developer.md             # This file
└── CLAUDE.md                # Project instructions
```

The `vendor/` directory contains git submodule vendored copies of the `winit`
and `softbuffer` codebase. These submodules point to forks under the TyOverby GitHub
account (TyOverby/winit and TyOverby/softbuffer), allowing the project to make custom
modifications when needed. The project uses a Cargo workspace at the root to manage
all Rust crates, making it easy to explore the dependencies and make changes if necessary.
See CLAUDE.md for detailed instructions on working with vendored dependencies.
