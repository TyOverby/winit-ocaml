# Format generated C code

The generated ocaml code is passed through ocamlformat, but the generated C code is currently not formatted at all.
Use `clang-format` to format the generated C code inside the dune rule that produces it.

## Plan

1. Locate the dune rule that generates C code (in `low/dune`)
2. Modify the rule to pipe the output through `clang-format` (similar to how OCaml code is piped through `ocamlformat`)
3. Build the project to verify the change works
4. Run tests to ensure functionality is preserved
5. Check the generated C code is properly formatted

## Validation Criteria

- The dune rule for generating `wgpu_low_stubs.c` should pipe through `clang-format`
- `dune build` completes successfully
- `dune build @check` passes with no warnings
- `dune exec test/test_compute.exe` runs successfully
- The generated C code in `low/wgpu_low_stubs.c` is properly formatted
