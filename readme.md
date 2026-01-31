# winit-ocaml

Safe, ergonomic OCaml bindings for  graphics programming using the
Rust [winit](https://github.com/rust-windowing/winit),
[softbuffer](https://github.com/rust-windowing/softbuffer),
and [wgpu-native](https://github.com/gfx-rs/wgpu-native)
libraries.

## Features

- **Simple API**: Create a window and start drawing in less than 30 lines of code
- **Direct pixel access**: Zero-copy buffer access via Bigarray for maximum performance
- **OCaml-controlled event loop**: Your code controls the main loop, not the windowing library
- **Cross-platform**: Works on Linux (X11/Wayland), with macOS and Windows support planned
- **Tablet support**: Full support for graphics tablets (Wacom, etc.) with pressure and tilt data on X11
- **Type-safe**: Rust's safety guarantees at the FFI boundary, OCaml's type safety in your code
- **Modern**: Built on the excellent Rust windowing ecosystem
- **Modular**: Separate `winit`, `softbuffer`, and `wgpu` libraries for flexibility

## Quick Example

```ocaml
let () =
  (* Create window and rendering surface *)
  let window = Winit.create () in
  let surface = Softbuffer.create (Winit.get_handle window) in

  (* Main loop *)
  let running = ref true in
  while !running do
    (* Handle events *)
    List.iter (fun event ->
      match event with
      | Winit.CloseRequested -> running := false
      | Winit.SurfaceResized { width; height } ->
          Softbuffer.resize surface ~width ~height
      | _ -> ()
    ) (Winit.pump_events window);

    (* Get pixel buffer *)
    let width, height, buffer = Softbuffer.get_buffer surface in

    (* Draw red pixels *)
    for i = 0 to width * height - 1 do
      Bigarray.Array1.set buffer i 0xFF0000l  (* ARGB format *)
    done;

    (* Display *)
    Softbuffer.present surface;
    Unix.sleepf 0.016  (* ~60 FPS *)
  done
```

## Libraries

This project provides three OCaml libraries:

- **`winit`**: Window creation and event handling
- **`softbuffer`**: Pixel buffer rendering (depends on winit)
- `wgpu`: Bindings to the webgpu API
- `wgpu_winit`: For attaching `wgpu` to a `winit` window

