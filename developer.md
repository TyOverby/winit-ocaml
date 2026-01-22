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

## Architecture

### Three-Layer Design

The project uses a three-layer architecture to bridge OCaml and Rust:

```
┌─────────────────────────────────────┐
│         OCaml Application           │
│   (User code in OCaml)              │
└──────────────┬──────────────────────┘
               │ OCaml API (winit_softbuffer.ml/mli)
               │ - Type-safe OCaml types
               │ - Event conversion
               │ - Memory management via GC integration
               ↓
┌──────────────────────────────────────┐
│        C Stubs Layer                 │
│   (ocaml/winit_stubs.c)              │
│   - OCaml runtime integration        │
│   - Custom blocks & finalizers       │
│   - Bigarray wrapping                │
└──────────────┬───────────────────────┘
               │ C ABI
               │ - Raw pointers
               │ - C-compatible structs
               │ - #[repr(C)] enums
               ↓
┌──────────────────────────────────────┐
│        Rust FFI Layer                │
│   (rust/src/lib.rs)                  │
│   - Window management (winit)        │
│   - Pixel buffer (softbuffer)        │
│   - Event collection                 │
│   - Memory safety                    │
└──────────────────────────────────────┘
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

#### 1. Rust FFI Layer (`rust/src/lib.rs`)

**Responsibilities:**
- Create and manage winit event loop using `EventLoop`
- Handle window creation via `ApplicationHandler` trait
- Manage softbuffer `Context` and `Surface` for pixel buffer access
- Collect window events (keyboard, mouse, resize, close) into a simple C-compatible format
- Provide C-compatible FFI functions with `#[no_mangle]` and `extern "C"`

**Key Types:**

```rust
pub struct WinitOcamlApp {
    event_loop: Option<EventLoop>,        // Window system event loop
    collector: EventCollector,            // Accumulates events
    graphics: Option<GraphicsState>,      // softbuffer context/surface
    buffer: Option<softbuffer::Buffer<'static>>, // Current pixel buffer
}

struct EventCollector {
    window: Option<Arc<Box<dyn Window>>>,  // The window handle
    events: Vec<Event>,                     // Collected events
    should_exit: bool,                      // Exit flag
}

struct GraphicsState {
    context: softbuffer::Context<Arc<Box<dyn Window>>>,
    surface: softbuffer::Surface<Arc<Box<dyn Window>>, Arc<Box<dyn Window>>>,
    width: u32,
    height: u32,
}
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

**Memory Management Challenge: Window Handles**

winit's `Window` type is `dyn Window` (trait object) and can't be cloned.
However, softbuffer needs access to window handles to create its rendering
context. The solution:

1. Store the window as `Arc<Box<dyn Window>>` for reference counting
2. Pass the same Arc to both the EventCollector and GraphicsState
3. Use `Arc::clone()` to increment reference counts without cloning the window itself

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
1. We store the buffer inside `WinitOcamlApp`, ensuring it doesn't outlive the surface
2. OCaml must call `present()` before the next `get_buffer()`, consuming the old buffer
3. The app is destroyed only when OCaml drops its handle, properly sequencing cleanup

**FFI Functions:**

- `winit_create() -> *mut WinitOcamlApp`: Creates window and initializes graphics
- `winit_pump_events(app, events_out, max_events) -> i32`: Polls events, returns count
- `winit_get_buffer(app, width_out, height_out) -> *mut u32`: Gets pixel buffer pointer
- `winit_present(app) -> i32`: Presents buffer to screen
- `winit_destroy(app)`: Cleanup
- `winit_test_version() -> i32`: Test function for FFI validation

#### 2. C Stubs Layer (`ocaml/winit_stubs.c`)

**Responsibilities:**
- Convert between OCaml values and C types
- Manage custom blocks for opaque app handles
- Integrate with OCaml's GC via finalizers
- Wrap pixel buffers as Bigarrays for zero-copy access

**Key OCaml FFI Concepts:**

**Custom Blocks:**
OCaml uses tagged values where pointers need special treatment. Custom blocks
allow us to embed arbitrary C data into OCaml values with proper GC
integration:

```c
static struct custom_operations winit_app_ops = {
    "winit_app",
    winit_app_finalize,  // Called when OCaml GC collects this value
    // ... other operations
};

value alloc_winit_app(void* app) {
    value v = caml_alloc_custom(&winit_app_ops, sizeof(void*), 0, 1);
    *((void**)Data_custom_val(v)) = app;
    return v;
}
```

When OCaml's GC collects this value, `winit_app_finalize` is called, which
calls Rust's `winit_destroy()` to clean up resources.

**Bigarray Integration:**

For zero-copy pixel access, we wrap Rust's pixel buffer pointer in an OCaml Bigarray:

```c
intnat dims[1];
dims[0] = (intnat)(width * height);
ba = caml_ba_alloc(
    CAML_BA_INT32 | CAML_BA_C_LAYOUT | CAML_BA_EXTERNAL,
    1,
    buffer,  // Pointer from Rust
    dims
);
```

The `CAML_BA_EXTERNAL` flag means OCaml doesn't own this memory. The buffer remains valid until:
1. `present()` is called (consumes the buffer)
2. The app is destroyed
3. `get_buffer()` is called again (invalidates previous buffer)

**Event Conversion:**

Events from Rust are C structs with simple integer fields. The C layer converts
them to OCaml tuples:

```c
value event_tuple = caml_alloc_tuple(3);
Store_field(event_tuple, 0, Val_int(events[i].event_type));
Store_field(event_tuple, 1, Val_int(events[i].data1));
Store_field(event_tuple, 2, Val_int(events[i].data2));
```

#### 3. OCaml API Layer (`ocaml/winit_softbuffer.ml`)

**Responsibilities:**
- Provide type-safe, idiomatic OCaml API
- Convert raw event tuples into tagged union types
- Hide FFI complexity from user code

**Type Design:**

```ocaml
type app  (* Abstract type - hides the custom block *)

type event_type =
  | NoEvent
  | CloseRequested
  | Resized
  | RedrawRequested
  | KeyPressed
  | KeyReleased
  | MouseMoved
  | MouseButtonPressed
  | MouseButtonReleased

type event = {
  event_type : event_type;
  data1 : int;  (* Width, X coordinate, button ID, etc. *)
  data2 : int;  (* Height, Y coordinate, etc. *)
}
```

**API Functions:**

```ocaml
val create : unit -> app
val pump_events : app -> event list
val get_buffer : app -> int * int * (int32, ...) Bigarray.Array1.t
val present : app -> unit
```

The OCaml layer converts the raw C tuples into proper OCaml variant types:

```ocaml
let pump_events app =
  let raw_events = winit_pump_events_raw app in
  Array.to_list
    (Array.map
       (fun (et, d1, d2) ->
         { event_type = event_type_of_int et; data1 = d1; data2 = d2 })
       raw_events)
```

## Key Design Decisions

### 1. Pump Events Pattern (OCaml Controls the Loop)

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

**Alternative Considered:**
Running winit on a separate thread and using message passing to communicate with OCaml. Rejected because:
- winit must run on the main thread (platform requirement)
- Thread synchronization adds complexity
- OCaml's threading model is complex (systhreads vs. multicore)

### 2. Three-Layer Architecture (Rust → C → OCaml)

**Decision:** Use C stubs as an intermediate layer instead of direct Rust-to-OCaml FFI.

**Why:**
- OCaml's FFI is designed around C calling conventions
- C stubs handle OCaml value representation and GC integration
- Proven, stable approach used by most OCaml FFI bindings
- Clear separation of concerns (Rust = logic, C = marshaling, OCaml = API)

**Trade-offs:**
- ✅ Maximum compatibility and portability
- ✅ Well-documented pattern
- ✅ Easy to debug with standard tools (gdb, valgrind)
- ⚠️ Extra layer of code to maintain
- ⚠️ Manual memory management in C layer

**Alternative Considered:**
Using the `ocaml-rs` crate for type-safe Rust-to-OCaml FFI. Rejected because:
- Adds dependency complexity
- Still requires understanding OCaml's value representation
- C stubs are simpler for this use case
- Can refactor to `ocaml-rs` later if needed

### 3. Zero-Copy Buffer Access via Bigarray

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

**Alternative Considered:**
Copying the buffer to OCaml memory. Rejected because:
- Copying 800×600×4 = ~2MB per frame at 60fps = 120MB/s overhead
- Defeats the purpose of a high-performance graphics API
- Bigarray is designed exactly for this use case

### 4. Simplified Event Types

**Decision:** Use a simple C-compatible event structure with event type enum and two integer data fields.

**Why:**
- winit's events are complex Rust types with lifetimes and nested structures
- Marshaling complex types across FFI is error-prone
- Most graphics applications only need basic events
- Easy to extend later by adding new event types

**Trade-offs:**
- ✅ Simple, predictable FFI boundary
- ✅ Easy to understand and debug
- ✅ Covers 90% of use cases
- ⚠️ Advanced events (IME, touch gestures) not yet supported
- ⚠️ Some information is lost (e.g., physical vs. logical key codes)

### 5. Single Opaque App Handle

**Decision:** Bundle window, event loop, and graphics state into a single `WinitOcamlApp` struct.

**Why:**
- Simplifies lifetime management (everything lives together)
- Reduces number of FFI functions needed
- Prevents misuse (can't present without a valid window)
- Clear ownership model

**Trade-offs:**
- ✅ Simple, safe API
- ✅ Impossible to use freed resources
- ✅ Fewer FFI calls = less overhead
- ⚠️ Less flexibility (can't swap windows/surfaces)
- ⚠️ No support for multiple windows (yet)

**Alternative Considered:**
Separate handles for window, surface, and buffer. Rejected because:
- Complex lifetime relationships would need explicit management
- Easy to misuse (present with wrong surface)
- Opaque handle is extensible (can add multi-window support later)

### 6. Explicit Present Model

**Decision:** Require explicit `present()` call after drawing, consuming the buffer.

**Why:**
- Matches softbuffer's API design (buffer.present() consumes the buffer)
- Forces correct usage pattern (get buffer → draw → present → repeat)
- Prevents accidental use of stale buffers
- Clear API boundary for frame submission

**Trade-offs:**
- ✅ Explicit control over frame submission
- ✅ Matches Rust API semantics
- ✅ Prevents errors (can't forget to present)
- ⚠️ Must get new buffer after each present
- ⚠️ Can't incrementally update and present

**Alternative Considered:**
Auto-present on next `get_buffer()`. Rejected because:
- Hides frame boundaries
- Surprising behavior (side effect in getter)
- Harder to implement damage regions later

### 7. Tablet Support

**Implementation:** Full support for graphics tablets (Wacom, etc.) on X11/Linux with pressure and tilt data.

**How it works:**
- The vendored winit fork includes custom patches to properly handle tablet events on X11
- Tablet devices (pens, erasers) are detected by the presence of pressure and tilt valuators
- The Device struct stores which valuator index corresponds to pressure, tilt_x, and tilt_y
- When tablet events arrive, the data is extracted from valuators and encoded as PointerSource::TabletTool
- This is then passed through to OCaml as source type 2 (tablet) in PointerMoved events
- Pressure and tilt information is available in the event data fields

**Platform support:**
- ✅ **X11/Linux**: Full support with pressure and tilt
- ⚠️ **Wayland/Linux**: Depends on winit's upstream Wayland tablet support
- ⚠️ **macOS/Windows**: Not yet tested

**Key changes in vendored winit:**
- Modified `xinput2_mouse_motion` to handle Pen and Eraser device types
- Modified `xinput2_button_input` to handle Pen and Eraser device types
- Added `extract_tablet_data` helper to extract pressure and tilt from X11 valuators
- Extended Device struct to track tablet axis indices

See the closed issue `issues/closed/6-wacom-tablet-support.md` for implementation details.

## Build System

### Overview

The build process is fully integrated through Dune, which automatically handles:
1. **Cargo**: Builds the Rust FFI library (invoked automatically by Dune)
2. **C Compiler**: Compiles the C stubs (invoked by Dune)
3. **OCaml Compiler**: Builds the OCaml library and links everything together

### Unified Build Command

Simply run:

```bash
dune build
```

Dune will automatically:
- Detect changes in Rust source files
- Invoke `cargo build --release` when needed
- Copy the resulting library to the build directory
- Compile C stubs and OCaml code
- Link everything together

No manual cargo commands or cleaning is needed!

### How It Works

The `ocaml/dune` file uses a custom rule to build the Rust library:

```scheme
(rule
 (targets libwinit_ocaml_ffi.a)
 (deps
  (source_tree ../rust/src)
  (source_tree ../rust/vendor)
  ../rust/Cargo.toml
  ../rust/Cargo.lock)
 (action
  (progn
   (chdir
    ../rust
    (run cargo build --release))
   (run cp ../rust/target/release/libwinit_ocaml_ffi.a libwinit_ocaml_ffi.a))))

(library
 (name winit_softbuffer)
 (public_name winit-softbuffer)
 (libraries unix bigarray)
 (foreign_stubs
  (language c)
  (names winit_stubs)
  (flags :standard))
 (foreign_archives winit_ocaml_ffi)
 (c_library_flags
  :standard
  -lpthread
  -ldl
  -lm))
```

**Key Components:**

- `(rule)`: Defines how to build the Rust library
- `(deps)`: Tracks Rust sources, vendored dependencies, and Cargo files
- `(foreign_archives)`: Links the Rust static library into the OCaml library
- `(foreign_stubs)`: Compiles C stub file
- `(c_library_flags)`: System libraries required by winit and softbuffer

### Rust Build Details

The Cargo.toml specifies:

```toml
[lib]
crate-type = ["staticlib", "cdylib"]
```

- `staticlib`: For linking into the final OCaml executable
- `cdylib`: For dynamic loading if needed

Dune uses the static library (`libwinit_ocaml_ffi.a`) for linking.

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
# cd to project root
dune build ocaml/examples/hello_window.exe
dune exec ocaml/examples/hello_window.exe
```

### Build Order

When you run `dune build`, the following happens automatically:

1. Dune checks if Rust sources have changed (by tracking `rust/src/`, `rust/vendor/`, `Cargo.toml`, `Cargo.lock`)
2. If changes detected, Dune runs `cargo build --release` in the `rust/` directory
3. The resulting `libwinit_ocaml_ffi.a` is copied to the build directory
4. C stubs are compiled
5. OCaml code is compiled
6. Everything is linked together into the final library/executable

This is incremental: if Rust hasn't changed, cargo won't rebuild. If nothing has changed, dune does nothing.

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

### Adding New Features

#### Adding a New Event Type

1. Add variant to Rust enum (`rust/src/lib.rs`):
   ```rust
   pub enum EventType {
       // ...
       NewEvent = 9,
   }
   ```

2. Handle it in `ApplicationHandler::window_event`:
   ```rust
   WindowEvent::SomeNewEvent { data } => {
       self.events.push(Event {
           event_type: EventType::NewEvent,
           data1: data,
           data2: 0,
       });
   }
   ```

3. Add to OCaml type (`ocaml/winit_softbuffer.mli` and `.ml`):
   ```ocaml
   type event_type =
     | (* ... *)
     | NewEvent

   let event_type_of_int = function
     | (* ... *)
     | 9 -> NewEvent
   ```

4. Document the event's data1/data2 meaning

#### Adding a New API Function

1. Implement in Rust with `#[no_mangle]` and `extern "C"`:
   ```rust
   #[no_mangle]
   pub extern "C" fn winit_new_function(app: *mut WinitOcamlApp) -> i32 {
       // Implementation
   }
   ```

2. Declare in C stubs header:
   ```c
   extern int winit_new_function(void* app);
   ```

3. Create C stub function:
   ```c
   CAMLprim value caml_winit_new_function(value app_val) {
       CAMLparam1(app_val);
       void* app = winit_app_val(app_val);
       int result = winit_new_function(app);
       CAMLreturn(Val_int(result));
   }
   ```

4. Add external declaration and wrapper in OCaml:
   ```ocaml
   external new_function_impl : app -> int = "caml_winit_new_function"

   let new_function app =
     new_function_impl app
   ```

5. Update .mli with documentation

### Testing Guidelines

**Unit Tests:**
Test individual components in isolation:

```ocaml
(* ocaml/examples/test_ffi.ml *)
let test_version () =
  let v = Winit_softbuffer.test_version () in
  assert (v = 100);
  Printf.printf "Version check passed\n"
```

**Integration Tests:**
Test full workflows:

```ocaml
let test_create_and_destroy () =
  let app = create () in
  present app  (* Should not crash *)
```

**Visual Tests:**
For changes to rendering:

```bash
# cd to project root

# Use Xvfb for headless testing
Xvfb :99 -screen 0 800x600x24 &
export DISPLAY=:99

# Run visual test
dune exec ocaml/examples/hello_window.exe &
sleep 1

# Capture screenshot
import -window root screenshot.png
```

## Testing

### Running Tests

```bash
# cd to project root

# FFI smoke test (works without display)
dune exec ocaml/examples/test_ffi.exe

# Full graphical test (requires display)
dune exec ocaml/examples/hello_window.exe

# With Xvfb (headless)
Xvfb :99 & DISPLAY=:99 dune exec ocaml/examples/hello_window.exe
```

### Memory Testing

Check for leaks with valgrind:

```bash
valgrind --leak-check=full --show-leak-kinds=all dune exec ocaml/examples/hello_window.exe
```

Expected output: No leaks from our code (may see leaks from X11 drivers).

### FFI Verification

The `test_ffi.exe` example verifies the FFI chain works:

```bash
dune exec ocaml/examples/test_ffi.exe
```

Output:
```
Testing FFI without display...
Test 1: Calling test_version()... OK! Got version: 100
Test 2: Event type handling... [lists all event types]
=== FFI Tests Passed ===
```

## Troubleshooting

### Build Issues

**Problem:** `undefined reference to 'winit_create'`

**Solution:**
- Run `dune clean && dune build` to rebuild everything
- Verify Rust sources are present in `rust/src/`
- Check that cargo is installed and accessible: `cargo --version`
- Verify symbols are exported: `nm rust/target/release/libwinit_ocaml_ffi.a | grep winit_create`

### Runtime Issues

**Problem:** `NotSupported: neither WAYLAND_DISPLAY nor DISPLAY is set`

**Solution:**
- Running on a system without a display server
- Set `DISPLAY` for X11: `export DISPLAY=:0`
- Use Xvfb for headless: `Xvfb :99 & export DISPLAY=:99`

**Problem:** Segmentation fault

**Solution:**
- Check that buffer isn't used after `present()` (buffer is consumed)
- Verify app isn't used after cleanup
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
├── rust/
│   ├── Cargo.toml           # Rust FFI library dependencies
│   ├── src/
│   │   └── lib.rs           # Rust FFI implementation
│   ├── prototype/
│   │   ├── Cargo.toml       # Prototype binaries
│   │   └── src/             # Prototype source code
│   └── vendor/
│       ├── winit/           # Vendored winit library
│       └── softbuffer/      # Vendored softbuffer library
├── ocaml/
│   ├── dune                 # OCaml build configuration
│   ├── winit_stubs.c        # C FFI bridge
│   ├── winit_softbuffer.mli # Public API interface
│   ├── winit_softbuffer.ml  # OCaml implementation
│   └── examples/
│       ├── dune             # Example build config
│       ├── hello_window.ml  # Graphical demo
│       └── test_ffi.ml      # FFI test
├── docs/                    # Design documentation
├── issues/                  # Project issue tracking
├── dune-project             # Top-level Dune config
├── readme.md                # User-facing documentation
└── developer.md             # This file
```

The `rust/vendor` directory contains git submodule vendored copies of the `winit`
and `softbuffer` codebase. These submodules point to forks under the TyOverby GitHub
account (TyOverby/winit and TyOverby/softbuffer), allowing the project to make custom
modifications when needed. The project uses a Cargo workspace at the root to manage
all Rust crates, making it easy to explore the dependencies and make changes if necessary.
See CLAUDE.md for detailed instructions on working with vendored dependencies.
