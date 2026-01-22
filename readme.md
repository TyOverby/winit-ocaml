# winit-ocaml

Safe, ergonomic OCaml bindings for pixel-based graphics programming using the
Rust [winit](https://github.com/rust-windowing/winit) and
[softbuffer](https://github.com/rust-windowing/softbuffer) libraries.

## What is this?

winit-ocaml provides a simple, cross-platform way to create windows and draw pixels directly from OCaml. Perfect for:

- Games and simulations
- Pixel art tools and visualizations
- Educational graphics projects
- Custom rendering engines
- Creative coding

The library gives you direct access to a pixel buffer where every frame, you can set individual pixel colors. No scene graphs, no retained mode rendering—just raw, immediate-mode pixel manipulation with OCaml's functional elegance.

## Features

- **Simple API**: Create a window and start drawing in less than 30 lines of code
- **Direct pixel access**: Zero-copy buffer access via Bigarray for maximum performance
- **OCaml-controlled event loop**: Your code controls the main loop, not the windowing library
- **Cross-platform**: Works on Linux (X11/Wayland), with macOS and Windows support planned
- **Tablet support**: Full support for graphics tablets (Wacom, etc.) with pressure and tilt data on X11
- **Type-safe**: Rust's safety guarantees at the FFI boundary, OCaml's type safety in your code
- **Modern**: Built on the excellent Rust windowing ecosystem

## Quick Example

```ocaml
open Winit_softbuffer

let () =
  (* Create window *)
  let app = create () in

  (* Main loop *)
  let running = ref true in
  while !running do
    (* Handle events *)
    let events = pump_events app in
    List.iter (fun event ->
      match event.event_type with
      | CloseRequested -> running := false
      | _ -> ()
    ) events;

    (* Get pixel buffer *)
    let width, height, buffer = get_buffer app in

    (* Draw red pixels *)
    for i = 0 to width * height - 1 do
      Bigarray.Array1.set buffer i 0xFF0000l  (* ARGB format *)
    done;

    (* Display *)
    present app;
    Unix.sleepf 0.016  (* ~60 FPS *)
  done
```
