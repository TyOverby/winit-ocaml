# Test Writing Guide

## Directory Structure

Tests live in `test/integration/<test_name>/` with:
- `<test_name>.ml` - The test implementation
- `dune` - Build configuration

The shared utility library is in `test/util/` and provides helpers for image output.

## Test Categories

### 1. Non-Graphical Tests
Tests that verify behavior without producing images (e.g., `buffer_creation`, `compute_shader`, `instance_and_adapter`).

**dune file:**
```dune
(executable
 (name my_test)
 (libraries wgpu core)
 (preprocess (pps ppx_jane)))

(rule
 (alias runtest)
 (action (run ./my_test.exe)))
```

### 2. Graphical Tests
Tests that render images and compare against expected baselines (e.g., `render_clear`, `render_triangle`).

**dune file:**
```dune
(executable
 (name render_foo)
 (libraries wgpu core core_unix test_util)
 (preprocess (pps ppx_jane)))

(rule
 (alias runtest)
 (action (run ./render_foo.exe))
 (targets render_foo.png))

(rule
 (alias runtest)
 (action (cmp render_foo.expected.png render_foo.png)))
```

## Image Generation

Use `test_util` for outputting images:

```ocaml
let ppm_file = Test_util.output_path "render_foo.ppm" in
let png_file = Test_util.output_path "render_foo.png" in
Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
if Test_util.ppm_to_png ~ppm_file ~png_file then Core_unix.unlink ppm_file
```

### Creating/Updating Baselines

The first time you run an image-generating test, it'll fail because there is no
"expected" file yet.  Look at the image file to see if it's what you expect, and if it's 
good, then run `dune promote test/path/to/image_file.expected.png` to promote it.

If the image expect-test fails, the error message should contain paths to both the 
"expected" and "actual" files.  Look at both of the files and evaluate the differences.
If the new version is better, run `dune promote test/path/to/image_file.expected.png`

## Code Style Guidelines

### Structure Pattern
Prefer separating initialization and cleanup into helper functions:

```ocaml
let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  instance, adapter, device

let cleanup ~instance ~adapter ~device ~buffer =
  Wgpu.Buffer.release buffer;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance

let () =
  let instance, adapter, device = init () in
  (* ... test body ... *)
  cleanup ~instance ~adapter ~device ~buffer
```

`init` should initialize things that _aren't_ primarily what the test is about.  For example,
in a test about buffer management, the main test body should include buffer creation, but 
if it was a test of the rendering pipeline, then it's fine to put buffer creation in `init`.

`cleanup` should handle the cleanup of everything. Always release resources in
reverse order of creation to avoid use-after-free.

### Output Style
- Only print on errors or for essential debugging info
- Use `[%message ...]` sexp-based output for structured data instead of `printf`:
  ```ocaml
  print_s [%message "" ~buffer_size:(buf_size : int64) ~buffer_usage:(buf_usage : int)]
  ```
- Minimize verbose "step complete" messages - they add noise

### Failure Handling
- Use `assert` for invariant checks
- For tests that can partially fail, exit with code 1:
  ```ocaml
  if not !all_correct then (
    print_endline "FAILURE: Some values incorrect.";
    exit 1)
  ```

## Running Tests

```bash
# Run all tests
dune runtest

# Run a specific test
# WARNING: for image-generating tests, this will write the `.png` files 
# next to the source code, which can be nice for debugging its output, 
# but might make dune unhappy as there's now two ways to get the png file
# (pull it from source, or generate it).  Resolve this conflict by deleting
# the file after you're done looking at it.
dune exec test/integration/buffer_creation/buffer_creation.exe

# Build and check for warnings
dune build @check

# Format the code
dune fmt 2> /dev/null || true
```
