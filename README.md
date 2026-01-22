# Winit-OCaml: OCaml Bindings for Softbuffer

Easy-to-use, safe OCaml bindings for the `softbuffer` Rust crate, enabling pixel-based graphics applications in OCaml.

## Project Status

**Planning and Research Phase Complete**

The project structure, API design, and implementation strategy have been thoroughly researched and documented. Ready to begin implementation.

## Quick Start

See `GETTING_STARTED.md` for detailed implementation instructions.

## Documentation

- **`IMPLEMENTATION_PLAN.md`**: Comprehensive plan with architecture, phases, and timeline
- **`FINDINGS.md`**: Technical findings from library exploration and prototyping
- **`GETTING_STARTED.md`**: Step-by-step guide to begin implementation
- **`instructions.md`**: Original project requirements

## Planned API

```ocaml
open Winit_softbuffer

(* Create a window and run an animation *)
let () =
  let app = create () in

  let rec loop frame =
    (* Get events *)
    let events = pump_events app in

    (* Handle close *)
    if List.mem CloseRequested events then exit 0;

    (* Get pixel buffer *)
    let (width, height, buffer) = get_buffer app in

    (* Draw something *)
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let idx = y * width + x in
        let color =
          let r = (x + frame) mod 256 in
          let g = (y + frame) mod 256 in
          let b = frame mod 256 in
          Int32.of_int (b lor (g lsl 8) lor (r lsl 16))
        in
        Bigarray.Array1.set buffer idx color
      done
    done;

    (* Present to window *)
    present app;

    (* Continue *)
    Unix.sleepf 0.016;
    loop ((frame + 1) mod 256)
  in
  loop 0
```

## Key Features (Planned)

- 🎨 **Direct pixel access** via Bigarray (zero-copy)
- ⚡ **Explicit control** over event loop and rendering
- 🛡️ **Memory safe** with proper resource management
- 🎯 **Simple API** designed for ease of use
- 🔧 **Cross-platform** (Linux/macOS/Windows)

## Architecture

```
┌─────────────────┐
│  OCaml App      │
│                 │
│  - Event loop   │
│  - Game logic   │
│  - Rendering    │
└────────┬────────┘
         │
    OCaml FFI
         │
┌────────┴────────┐
│  Rust FFI Layer │
│                 │
│  - winit        │  (window & events)
│  - softbuffer   │  (pixel buffer)
└─────────────────┘
```

## Implementation Approach

1. **Rust FFI Layer**: Exposes C-compatible API
2. **OCaml Bindings**: Safe wrappers around FFI
3. **High-level API**: Idiomatic OCaml interface

See `IMPLEMENTATION_PLAN.md` for detailed phases.

## Technical Highlights

- Uses `pump_events` pattern for OCaml-controlled event loop
- Handles complex ownership via owned window handles
- Zero-copy buffer access via Bigarray
- Proper resource cleanup with finalizers

## Project Structure

```
winit-ocaml/
├── vendor/              # Vendored winit & softbuffer
├── rust/               # Rust FFI layer (to be created)
├── ocaml/              # OCaml bindings (to be created)
├── examples/           # Example programs (to be created)
├── prototype/          # Rust prototypes
├── IMPLEMENTATION_PLAN.md
├── FINDINGS.md
├── GETTING_STARTED.md
└── instructions.md
```

## Building (Future)

```bash
# Build Rust FFI
cd rust && cargo build --release

# Build OCaml library
cd ocaml && dune build

# Run example
dune exec ./examples/hello_window.exe
```

## Testing (Future)

```bash
# Unit tests
dune test

# Visual tests with Xvfb
./scripts/test_visual.sh
```

## Dependencies

- **Rust**: 1.70+ (for vendored crates)
- **OCaml**: 4.14+ (for dune 3.0)
- **opam**: 2.0+ (provided in this directory)
- **dune**: 3.0+

## Platform Support (Planned)

- ✅ Linux (X11 & Wayland)
- 🔄 macOS
- 🔄 Windows

## Performance Goals

- < 1ms FFI overhead per frame
- Zero-copy pixel buffer access
- 60+ FPS for typical applications

## Safety

- No `unsafe` OCaml code
- Rust safety guarantees at FFI boundary
- Proper resource cleanup via finalizers
- Clear ownership model

## Contributing (Future)

Contributions welcome! Areas of interest:
- Platform support (macOS, Windows)
- Additional event types
- Performance optimizations
- Examples and documentation

## License

MIT OR Apache-2.0 (matching softbuffer)

## Acknowledgments

- **winit**: Cross-platform window creation
- **softbuffer**: Software buffer rendering
- **OCaml community**: For excellent FFI support

## Next Steps

1. Read `GETTING_STARTED.md`
2. Implement Phase 1 (Rust FFI layer)
3. Create simple OCaml bindings
4. Test with hello_window example
5. Iterate and expand

---

Built with ❤️ for the OCaml graphics community
