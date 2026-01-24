# Project organization

Right now the project is organized by language first and then library:

```
ocaml/
  image_buf/
  softbuffer/
  winit/
  examples/
rust/
  src/
  vendor/
  prototype/
```

I'd like for you to make two big changes:
1. split the rust crate into two crates `softbuffer_ffi` and `winit_ffi`
3. reorganize the repo to be "library major", like so:

```
softbuffer/
  ffi/ # Rust code
  src/ # Ocaml code
winit/
  ffi/ # Rust code
  src/ # Ocaml code
vendor/
image_buf/
examples/
  # existing examples here
  prototype/
```

This will probably necessitate a more involved "cargo workspace" strategy.

Use `git mv` whenever possible.

## Currently

The project is organized as follows:

```
winit-ocaml/
├── rust/
│   ├── Cargo.toml           # Single crate "winit-ocaml-ffi" producing staticlib+cdylib
│   ├── src/
│   │   ├── lib.rs           # Shared types (Event, EventType, DamageRect)
│   │   ├── winit_ffi.rs     # Window/event FFI (~400 lines)
│   │   └── softbuffer_ffi.rs# Rendering FFI (~200 lines)
│   ├── vendor/              # Git submodules (winit, softbuffer)
│   └── prototype/           # Rust prototypes
│
├── ocaml/
│   ├── winit/               # Builds the Rust lib AND winit OCaml library
│   │   ├── dune             # Complex: invokes cargo, handles platform linking
│   │   ├── winit.ml/.mli
│   │   └── winit_stubs.c
│   ├── softbuffer/          # Depends on winit library
│   │   ├── dune
│   │   ├── softbuffer.ml/.mli
│   │   └── softbuffer_stubs.c
│   ├── image_buf/           # Standalone utility library
│   └── examples/
│
├── Cargo.toml               # (Does not exist at root - workspace not defined)
└── dune-project             # Defines winit & softbuffer packages
```

Key observations:
- Currently one Rust crate produces both winit and softbuffer FFI
- The `ocaml/winit/dune` file handles all Rust compilation
- `softbuffer/dune` just links against the winit library (reuses Rust build)
- There's no root Cargo.toml - the workspace is implied by `rust/Cargo.toml`

## Notes

### Files to reorganize

**Winit library:**
- `rust/src/lib.rs` → shared types needed by both (will need to split or duplicate)
- `rust/src/winit_ffi.rs` → `winit/ffi/src/lib.rs`
- `ocaml/winit/winit.ml` → `winit/src/winit.ml`
- `ocaml/winit/winit.mli` → `winit/src/winit.mli`
- `ocaml/winit/winit_stubs.c` → `winit/src/winit_stubs.c`
- `ocaml/winit/dune` → `winit/src/dune` (needs significant rewrite)

**Softbuffer library:**
- `rust/src/softbuffer_ffi.rs` → `softbuffer/ffi/src/lib.rs`
- `ocaml/softbuffer/softbuffer.ml` → `softbuffer/src/softbuffer.ml`
- `ocaml/softbuffer/softbuffer.mli` → `softbuffer/src/softbuffer.mli`
- `ocaml/softbuffer/softbuffer_stubs.c` → `softbuffer/src/softbuffer_stubs.c`
- `ocaml/softbuffer/dune` → `softbuffer/src/dune` (needs rewrite)

**Other moves:**
- `rust/vendor/` → `vendor/`
- `rust/prototype/` → `examples/prototype/`
- `ocaml/examples/` → `examples/`
- `ocaml/image_buf/` → `image_buf/`

### Cargo workspace strategy

Create a root `Cargo.toml` defining the workspace:
```toml
[workspace]
members = ["winit/ffi", "softbuffer/ffi"]
resolver = "2"
```

Each FFI crate will have its own Cargo.toml:
- `winit/ffi/Cargo.toml` - depends on vendor/winit
- `softbuffer/ffi/Cargo.toml` - depends on vendor/softbuffer AND winit_ffi

### Shared types consideration

The `lib.rs` currently contains shared types (`Event`, `EventType`, `DamageRect`, encoding helpers).
Options:
1. **Duplicate in both crates** - Simple but maintenance burden
2. **Create a shared crate** - Adds complexity
3. **Put in winit_ffi, re-export from softbuffer_ffi** - softbuffer already depends on winit

Going with option 3: shared types go in `winit_ffi`, softbuffer depends on it.

### Dune changes

Each library's dune file will need to:
1. Build its own Rust FFI library
2. Link the C stubs
3. Handle platform-specific linking

The softbuffer dune will need to link both Rust libraries.

## Addressing

Reorganized the project with the following changes:

### Directory Structure Changes

1. **Moved vendor to root**: `rust/vendor/` → `vendor/`
2. **Reorganized winit library**:
   - `rust/src/winit_ffi.rs` → `winit/ffi/src/ffi.rs`
   - `rust/src/lib.rs` (types) → `winit/ffi/src/lib.rs`
   - `ocaml/winit/*.{ml,mli,c}` → `winit/src/*.{ml,mli,c}`
3. **Reorganized softbuffer library**:
   - `rust/src/softbuffer_ffi.rs` → `softbuffer/ffi/src/lib.rs`
   - `ocaml/softbuffer/*.{ml,mli,c}` → `softbuffer/src/*.{ml,mli,c}`
4. **Moved examples**: `ocaml/examples/` → `examples/`
5. **Moved prototype**: `rust/prototype/` → `examples/prototype/`
6. **Moved image_buf**: `ocaml/image_buf/` → `image_buf/`
7. **Removed**: `rust/` and `ocaml/` directories

### Cargo Workspace Changes

1. Created root `Cargo.toml` with workspace configuration
2. Created `winit/ffi/Cargo.toml` for the winit FFI crate
3. Created `softbuffer/ffi/Cargo.toml` for the softbuffer FFI crate (depends on winit_ffi)
4. Added `workspace.package` and `workspace.dependencies` settings required by vendored winit
5. Added `rlib` to winit_ffi's crate-type so softbuffer_ffi can depend on it
6. Excluded vendor directories from workspace to avoid multiple workspace root conflicts

### Dune Changes

1. Updated `winit/src/dune` to build winit_ffi from source directory using `--manifest-path`
2. Updated `softbuffer/src/dune` to build softbuffer_ffi similarly
3. Updated build scripts to use new paths

### Key Technical Decisions

- **Shared types in winit_ffi**: The `DamageRect`, `Event`, `EventType` types are defined in
  `winit_ffi` and imported by `softbuffer_ffi` via `use winit_ffi::DamageRect`
- **Cargo workspace isolation**: Using `--manifest-path` to build from source directory rather
  than dune's `_build/default` to avoid conflicts with vendored workspace definitions
- **rlib crate type**: Added `rlib` to winit_ffi so it can be used as a Rust dependency
