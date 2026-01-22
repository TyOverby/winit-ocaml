# Getting Started with Implementation

This guide provides step-by-step instructions for building the OCaml-Softbuffer bindings.

## Project Structure

```
winit-ocaml/
├── vendor/              # Vendored dependencies
│   ├── winit/          # Window creation library
│   └── softbuffer/     # Software rendering library
├── rust/               # Rust FFI layer (to be created)
│   ├── Cargo.toml
│   └── src/
│       └── lib.rs
├── ocaml/              # OCaml bindings (to be created)
│   ├── dune
│   ├── dune-project
│   ├── winit_softbuffer.ml
│   └── winit_softbuffer.mli
├── examples/           # Example programs (to be created)
│   ├── hello_window.ml
│   └── gradient.ml
├── prototype/          # Rust prototypes
├── IMPLEMENTATION_PLAN.md
├── FINDINGS.md
└── instructions.md
```

## Phase 1: Rust FFI Layer

### Step 1: Create Rust Library Crate

```bash
mkdir -p rust
cd rust
```

Create `Cargo.toml`:
```toml
[package]
name = "winit-ocaml-ffi"
version = "0.1.0"
edition = "2021"

[lib]
crate-type = ["staticlib", "cdylib"]

[dependencies]
softbuffer = { path = "../vendor/softbuffer" }
winit = { path = "../vendor/winit/winit" }
raw-window-handle = "0.6"
```

### Step 2: Implement Core FFI Functions

Create `src/lib.rs` with:
- App handle type
- Window creation
- Event polling
- Buffer access
- Cleanup

See `FINDINGS.md` for recommended API structure.

### Step 3: Build Rust Library

```bash
cd rust
cargo build --release
# Output: target/release/libwinit_ocaml_ffi.a
```

## Phase 2: OCaml Bindings

### Step 1: Set up OCaml Project

```bash
mkdir -p ocaml
cd ocaml
```

Create `dune-project`:
```scheme
(lang dune 3.0)
(name winit-softbuffer)
```

Create `dune`:
```scheme
(library
 (name winit_softbuffer)
 (public_name winit-softbuffer)
 (libraries unix bigarray)
 (foreign_stubs
  (language c)
  (names winit_stubs)
  (flags :standard -I../rust/target/release))
 (c_library_flags :standard -L../rust/target/release -lwinit_ocaml_ffi))
```

### Step 2: Create C Stubs

Create `winit_stubs.c` to:
- Call Rust FFI functions
- Convert between OCaml and C types
- Handle OCaml memory management

### Step 3: Create OCaml Interface

Create `winit_softbuffer.mli` with module signatures (see `IMPLEMENTATION_PLAN.md`).

Create `winit_softbuffer.ml` with:
- External declarations
- Type definitions
- High-level wrappers

### Step 4: Build OCaml Library

```bash
cd ocaml
dune build
```

## Phase 3: Example Programs

### Create hello_window.ml

```ocaml
open Winit_softbuffer

let () =
  let app = create () in
  for i = 1 to 180 do
    let events = pump_events app in
    List.iter (function
      | CloseRequested -> exit 0
      | _ -> ()
    ) events;

    let (width, height, buffer) = get_buffer app in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        Bigarray.Array1.set buffer (y * width + x)
          (Int32.of_int (0x00FF0000))  (* Red *)
      done
    done;

    present app;
    Unix.sleepf 0.016
  done;
  destroy app
```

### Build and Run

```bash
cd examples
dune build hello_window.exe
dune exec ./hello_window.exe
```

## Testing

### Unit Tests

Create `test/test_basic.ml`:
```ocaml
open Winit_softbuffer

let test_create_destroy () =
  let app = create () in
  destroy app;
  print_endline "Create/destroy: OK"

let test_pump_events () =
  let app = create () in
  let events = pump_events app in
  Printf.printf "Got %d events\n" (List.length events);
  destroy app

let () =
  test_create_destroy ();
  test_pump_events ()
```

### Visual Tests with Xvfb

```bash
# Start virtual framebuffer
Xvfb :99 -screen 0 800x600x24 &
export DISPLAY=:99

# Run test
dune exec ./examples/hello_window.exe &
PID=$!

# Wait a bit
sleep 1

# Capture screenshot
import -window root screenshot.png

# Kill test
kill $PID

# Check screenshot
file screenshot.png
```

## Debugging Tips

### Check Rust Library Exports

```bash
nm -D rust/target/release/libwinit_ocaml_ffi.so | grep winit
```

### Check OCaml Linking

```bash
dune build --verbose
```

### Run with Debug Output

```bash
RUST_LOG=debug dune exec ./examples/hello_window.exe
```

### Memory Leak Detection

```bash
valgrind --leak-check=full dune exec ./examples/hello_window.exe
```

## Common Issues

### Issue: "undefined reference to winit_create"
- Check that Rust library was built
- Verify library path in dune file
- Ensure symbols are exported with `#[no_mangle]`

### Issue: "Cannot open display"
- Make sure X server is running
- Set DISPLAY environment variable
- Try Xvfb for headless testing

### Issue: Segmentation fault
- Check for null pointers in FFI layer
- Verify handle is still valid
- Ensure cleanup order is correct

### Issue: Events not received
- Make sure pump_events is called regularly
- Check that window is in focus
- Verify event loop hasn't exited

## Performance Optimization

### Reduce FFI Overhead
- Batch event retrieval
- Use zero-copy buffer access
- Minimize allocations

### Optimize Drawing
- Use damage regions for partial updates
- Consider double buffering
- Profile with perf/cachegrind

### Frame Rate Control
- Implement adaptive vsync
- Add frame timing measurements
- Consider async rendering

## Next Features to Add

1. Window configuration (title, size, position)
2. More event types (touch, pen, gamepad)
3. Multiple windows
4. Fullscreen mode
5. DPI scaling
6. Cursor management
7. Clipboard integration

## Resources

- [winit documentation](https://docs.rs/winit)
- [softbuffer documentation](https://docs.rs/softbuffer)
- [OCaml FFI guide](https://ocaml.org/manual/intfc.html)
- [raw-window-handle](https://docs.rs/raw-window-handle)

## Getting Help

- Check FINDINGS.md for technical insights
- Review IMPLEMENTATION_PLAN.md for architecture
- Look at vendor/softbuffer/examples for patterns
- Consult vendor/winit/examples for event handling

Good luck with the implementation!
