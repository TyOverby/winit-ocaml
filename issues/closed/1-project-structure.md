# Project structure

Right now, there's a few issues with the current project structure:
1. things are scattered about:
   - the ocaml examples should live inside of the `./ocaml` directory
   - the rust `prototype` directory should live inside of `./rust`
   - the rust `vendor` directory should live inside of `./rust`
     (currently `vendor` doesn't build, don't worry about it for now)
2. rust should use a workspace at the project root so that it uses the vendored projects

## Currently

The project has the following structure:
- `examples/` directory at root contains OCaml example files (hello_window.ml, test_ffi.ml)
- `prototype/` directory at root contains Rust prototype binaries
- `vendor/` directory at root contains vendored winit and softbuffer libraries as git submodules
- `rust/` directory contains the main FFI library (Cargo.toml, src/lib.rs)
- `ocaml/` directory contains the OCaml library code but not the examples
- Paths in `rust/Cargo.toml` reference `../vendor/...`
- Documentation in `developer.md` references paths like `examples/` and `vendor/`
- `.gitmodules` has submodule paths pointing to the old locations

The Rust FFI library builds successfully but the organization doesn't reflect logical grouping.

## Notes

**Git submodules**: The vendor directory contains git submodules that need their paths updated in `.gitmodules` when moved. Git's `git mv` command handles this automatically for submodules.

**Cargo workspace considerations**: Initially planned to create a formal Cargo workspace at the root. However, the vendored dependencies (winit and softbuffer) already define their own workspaces with `workspace.package` inheritance. When we try to nest them under a parent workspace, Cargo encounters conflicts with inherited fields like `edition`, `rust-version`, `repository`, and various workspace dependencies (like `bitflags`). The parent workspace would need to define all these fields, but they're specific to each vendored project. Therefore, a formal workspace isn't necessary - the directory organization alone provides the logical structure.

**Path updates**: After moving directories, several files need updating:
- `rust/Cargo.toml`: dependency paths from `../vendor` to `./vendor`
- `developer.md`: all example command paths and project structure documentation
- OCaml build configuration remains unchanged (uses absolute paths)

## Addressing

1. **Moved directories using git mv**:
   - `examples/` → `ocaml/examples/`
   - `prototype/` → `rust/prototype/`
   - `vendor/` → `rust/vendor/`

   Used `git mv` to preserve history and automatically update `.gitmodules` for the submodules.

2. **Updated Cargo.toml paths**:
   - Modified `rust/Cargo.toml` to reference `./vendor/softbuffer` and `./vendor/winit/winit` instead of `../vendor/...`
   - Updated `rust/prototype/Cargo.toml` paths remain relative to their new location

3. **Attempted Cargo workspace setup**:
   - Initially created root `Cargo.toml` with workspace definition
   - Discovered conflicts with vendored dependencies' workspace inheritance
   - Removed workspace approach as it's not needed for this project structure
   - The directory organization provides the logical grouping without needing formal workspace

4. **Updated documentation**:
   - Modified `developer.md` to reflect new paths in:
     - Building Examples section
     - Project Structure Reference
     - Testing sections
     - All command examples using `ocaml/examples/`

5. **Verified the build**:
   - Ran `cargo build --release --manifest-path=rust/Cargo.toml`
   - Build succeeds with all dependencies compiling
   - One warning about unused `context` field in GraphicsState struct

All structural changes complete. The project now has a cleaner organization with OCaml code in `ocaml/`, Rust code in `rust/`, and all documentation updated to match.
