# Debug rust build

Right now, the `dune` action that builds the  rust library build step always
builds it in optimized mode.  This makes for slow build times, so I'd rather
have it conditional on if `--profile release` is passed to `dune`.

## Currently

The `ocaml/dune` file has a rule that builds the Rust FFI library (lines 3-20):
- Always runs `cargo build --release` (line 15)
- Always copies from `target/release/` directory (lines 16-20)
- This means debug builds are slow during development

## Notes

Dune provides the `%{profile}` variable that can be used to determine the current build profile:
- Default profile: `dev`
- Release profile: `release`

The solution is to make the cargo command and copy paths conditional based on the profile:
1. Use a bash script within the dune action to check `%{profile}`
2. Run `cargo build --release` and copy from `target/release` when profile is `release`
3. Run `cargo build` and copy from `target/debug` when profile is `dev` (or any other profile)

This will speed up development builds significantly while keeping release builds optimized.

## Addressing

Modified `ocaml/dune` to use a bash script that conditionally builds based on the Dune profile:

- When `dune build` is run (default `dev` profile):
  - Runs `cargo build` (debug mode, unoptimized)
  - Copies from `target/debug/` directory

- When `dune build --profile release` is run:
  - Runs `cargo build --release` (optimized)
  - Copies from `target/release/` directory

The implementation uses a bash action with `%{profile}` variable interpolation to detect the current build profile and adjust the cargo command and copy paths accordingly.

**Testing:**
- ✅ Verified `dune build` compiles in dev mode (8.03s, unoptimized + debuginfo)
- ✅ Verified `dune build --profile release` compiles in release mode (23.67s, optimized)
- ✅ Both builds complete successfully with correct artifacts

The development build is now significantly faster as it skips optimizations, while release builds retain full optimization.
