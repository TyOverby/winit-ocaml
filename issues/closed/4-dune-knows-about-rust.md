# Dune knows about cargo

Right now, the build steps involve manually building the rust project, cleaning the ocaml project, and then rebuilding the
ocaml project.  This is unfortunate, and I think we could make it so that `dune` rebuilds the rust stuff any time that
rust code changes.

## Currently

The build process currently requires two manual steps:
1. `cd rust && cargo build --release` - builds the Rust FFI library
2. `dune build` - builds the OCaml library, which links against the pre-built Rust static library

The `ocaml/dune` file currently:
- Hardcodes the path to the Rust static library: `/home/tyoverby/workspace/rust/winit-ocaml/rust/target/release/libwinit_ocaml_ffi.a`
- Has no dependency tracking on Rust source files
- Cannot detect when Rust code changes and needs rebuilding

This means developers must manually rebuild Rust and clean the OCaml build when making changes to Rust code.

## Notes

### Dune-Cargo Integration Approaches

Research into integrating Cargo builds with Dune reveals several approaches:

1. **dune-cargo-build package**: An OPAM package specifically designed for this (https://opam.ocaml.org/packages/dune-cargo-build/). Runs cargo in offline mode compatible with dune/opam sandboxing.

2. **Dune rule with source_tree**: The Dune FAQ (https://dune.readthedocs.io/en/latest/faq.html) shows the pattern:
   ```
   (rule
     (target foo.a)
     (deps (source_tree foo-rs))
     (action
       (progn
         (chdir foo-rs (run cargo build --release))
         (run mv foo-rs/target/release/%{target} %{target}))))
   ```

3. **Community discussion**: Active discussion on the OCaml forums about cargo/dune integration (https://discuss.ocaml.org/t/cargo-dune-integration/12484)

### Implementation Strategy

The simpler approach (option 2) should work well for this project:
- Add a `(rule)` stanza that builds the Rust library
- Use `(deps (source_tree ../rust/src))` to track Rust source changes
- Also track `../rust/Cargo.toml` and `../rust/Cargo.lock` as dependencies
- The rule runs cargo and copies the resulting library to a location dune expects
- The main library references this generated target instead of the hardcoded path

This approach:
- Works without additional dependencies
- Integrates naturally with dune's build model
- Automatically rebuilds when Rust sources change
- Doesn't require manual build steps

## Addressing

### Implementation

Added a `(rule)` stanza to `ocaml/dune` that:
1. Declares `libwinit_ocaml_ffi.a` as a build target
2. Tracks dependencies:
   - `(source_tree ../rust/src)` - all Rust source files
   - `(source_tree ../rust/vendor)` - vendored dependencies (winit and softbuffer)
   - `../rust/Cargo.toml` - main cargo configuration
   - `../rust/Cargo.lock` - dependency lock file
3. Runs `cargo build --release` in the rust directory when dependencies change
4. Copies the resulting static library to the build directory

Updated the `(library)` stanza to:
- Reference the generated `libwinit_ocaml_ffi.a` target instead of the absolute path
- Remove the hardcoded include path since it's no longer needed

This means developers can now simply run `dune build` and:
- Dune will automatically build the Rust library if Rust sources have changed
- The build is incremental (cargo only rebuilds what changed)
- No manual cargo commands or cleaning is needed
- The workflow is unified into a single command
