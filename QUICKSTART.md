# Quick Start Guide

## Prerequisites

- Rust toolchain (rustc, cargo)
- OCaml 5.2+ with opam
- X11 or Wayland display server
- Linux system (tested on Linux, should work on other platforms)

## Building from Source

### 1. Build the Rust FFI Library

```bash
cd rust
cargo build --release
```

This creates:
- `target/release/libwinit_ocaml_ffi.a` (static library)
- `target/release/libwinit_ocaml_ffi.so` (dynamic library)

### 2. Build the OCaml Bindings

```bash
cd ..
./opam exec -- dune build
```

This compiles the OCaml library and C stubs.

### 3. Build and Run Examples

```bash
./opam exec -- dune build examples/hello_window.exe
./opam exec -- dune exec examples/hello_window.exe
```

You should see:
- A window opens showing an animated gradient
- Events are printed to the console
- The window runs for 180 frames (~3 seconds) then exits

## Creating Your Own Program

Create a new file `examples/my_app.ml`:

```ocaml
open Winit_softbuffer

let () =
  let app = create () in
  let running = ref true in

  while !running do
    (* Handle events *)
    let events = pump_events app in
    List.iter (fun event ->
      match event.event_type with
      | CloseRequested -> running := false
      | KeyPressed -> Printf.printf "Key!\n%!"
      | _ -> ()
    ) events;

    (* Draw *)
    let (width, height, buffer) = get_buffer app in
    for i = 0 to width * height - 1 do
      Bigarray.Array1.set buffer i 0xFF0000l  (* Red *)
    done;
    present app;

    Unix.sleepf 0.016
  done
```

Add to `examples/dune`:

```scheme
(executable
 (name my_app)
 (libraries winit-softbuffer unix bigarray))
```

Build and run:

```bash
./opam exec -- dune build examples/my_app.exe
./opam exec -- dune exec examples/my_app.exe
```

## API Reference

### Creating a Window

```ocaml
val create : unit -> app
```

Creates a new window (800x600) and returns an app handle.

### Polling Events

```ocaml
val pump_events : app -> event list
```

Polls for window events. Non-blocking. Returns a list of events that occurred since the last call.

### Event Types

```ocaml
type event = {
  event_type : event_type;
  data1 : int;  (* Context-dependent *)
  data2 : int;  (* Context-dependent *)
}

type event_type =
  | CloseRequested      (* User wants to close window *)
  | Resized             (* data1=width, data2=height *)
  | RedrawRequested     (* Window needs redraw *)
  | KeyPressed          (* Key was pressed *)
  | KeyReleased         (* Key was released *)
  | MouseMoved          (* data1=x, data2=y *)
  | MouseButtonPressed  (* data1=button (1=left, 2=right, 3=middle) *)
  | MouseButtonReleased (* data1=button *)
```

### Drawing

```ocaml
val get_buffer : app -> (int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t)
```

Returns `(width, height, pixel_buffer)` where:
- `width`, `height`: Current window dimensions in pixels
- `pixel_buffer`: Bigarray of ARGB pixels (0xAARRGGBB format)

The buffer is laid out row-by-row: `pixel[y * width + x]`

### Presenting

```ocaml
val present : app -> unit
```

Displays the current buffer contents to the window. Call this after drawing.

## Tips

1. **Frame Rate**: Use `Unix.sleepf` to control frame rate
2. **Buffer Format**: Pixels are 32-bit ARGB (alpha in high byte, blue in low byte)
3. **Performance**: Bigarray access is fast - direct memory access with no copying
4. **Events**: Always check for `CloseRequested` to allow users to close the window
5. **Resizing**: Handle `Resized` events - buffer dimensions change!

## Example: Drawing a Gradient

```ocaml
let draw_gradient buffer width height frame =
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let r = Int32.of_int ((x * 255 / width + frame) mod 256) in
      let g = Int32.of_int ((y * 255 / height) mod 256) in
      let b = Int32.of_int (128) in
      let color = Int32.logor
        (Int32.logor b (Int32.shift_left g 8))
        (Int32.shift_left r 16) in
      Bigarray.Array1.set buffer (y * width + x) color
    done
  done
```

## Troubleshooting

**"NotSupported: neither WAYLAND_DISPLAY nor WAYLAND_SOCKET nor DISPLAY is set"**
- No display server available
- Set `DISPLAY` environment variable (for X11)
- Or set `WAYLAND_DISPLAY` (for Wayland)
- For headless testing, use Xvfb: `Xvfb :99 & export DISPLAY=:99`

**Linker errors about missing symbols**
- Make sure Rust library was built: `cd rust && cargo build --release`
- Check that dune points to correct library path

**Segmentation fault**
- Don't use the buffer after calling `present()`
- Get a fresh buffer with `get_buffer()` for each frame
- Don't use the app after the window closes

## Performance Tips

- Use `Bigarray.Array1.unsafe_get/set` for faster access (if you're sure about bounds)
- Minimize event processing overhead
- Consider damage regions for partial updates (future enhancement)
- Profile with `perf` if needed

## More Examples

See the `examples/` directory for more sample programs:
- `hello_window.ml`: Animated gradient demo
- (More examples coming soon!)

Happy coding!
