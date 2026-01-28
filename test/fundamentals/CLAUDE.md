# Porting WebGPU Fundamentals Lessons

This directory contains OCaml ports of lessons from
[webgpufundamentals.org](https://webgpufundamentals.org/). The JavaScript source
files are in `webgpu_fundamentals/<lesson-name>/`.

## Goals

The primary goal is **technical validation**: demonstrating API coverage and
stress-testing the bindings. The code should also be **readable**, since users
will reference these as examples of how to achieve things with the wgpu API.

These are not meant to be verbatim translations. Port the _spirit_ of the
lesson, adapting to the APIs we have available.

## Directory Structure

When starting a port, you'll be given a source directory
`./webgpu_fundamentals/%{lesson_name}`. From this, you'll infer the lesson name
and create a test directory in `./test/fundamentals/%{lesson_name}` Each
JavaScript file becomes its own OCaml test.  e.g.

```
test/fundamentals/
  rotation/
    dune
    rotation.ml                    <- from rotation.js
    rotation_via_unit_circle.ml    <- from rotation-via-unit-circle.js
    rotation.expected.png
    rotation_via_unit_circle.expected.png
```

Refer to `test/CLAUDE.md` for the dune file templates and test patterns,
especially for how to test and promote image files.

## Handling Headless Output

We render to PNG files, not interactive windows. This is fine for our purposes.
Default to 600x400 images unless there's a really good reason not to.

**For lessons with parameters or animation**: Output 4-5 representative frames
showing the range of behavior. For example, a rotation lesson might output:

```
rotation_0deg.png
rotation_45deg.png
rotation_90deg.png
rotation_180deg.png
```

Use descriptive suffixes that make it clear what each image demonstrates.

## Matrix Math with Gg

Use the `gg` library for vector and matrix operations. Add it to your dune file:

```dune
(libraries wgpu core core_unix test_util gg)
```

Key modules:
- `Gg.V2`, `Gg.V3`, `Gg.V4` - vectors
- `Gg.M3`, `Gg.M4` - matrices
- `Gg.Quat` - quaternions for rotations

Example usage:
```ocaml
(* Create a 4x4 identity matrix *)
let m = Gg.M4.id

(* Translation *)
let translate = Gg.M4.move3 (Gg.V3.v 1.0 2.0 3.0)

(* Rotation around Y axis (radians) *)
let rotate_y = Gg.M4.rot3_axis Gg.V3.oy angle

(* Scaling *)
let scale = Gg.M4.scale3 (Gg.V3.v 2.0 2.0 2.0)

(* Combine transformations: scale, then rotate, then translate *)
let combined = Gg.M4.(translate * rotate_y * scale)

(* Apply to a point *)
let transformed = Gg.V4.ltr combined (Gg.V4.v x y z 1.0)
```

Gg documentation: https://erratique.ch/software/gg/doc/Gg/index.html

## Loading Textures from Images

A test image is available at `test/assets/cat_in_tophat.png`.

Use `Test_util.load_png` to load images via ImageMagick:
```ocaml
let width, height, data = Test_util.load_png ~filename:"test/assets/cat_in_tophat.png" in
(* data is RGBA Bigarray, ready for Queue.write_texture *)
```

For simple test patterns, generate them procedurally:
```ocaml
let make_checkerboard ~width ~height ~cell_size =
  let data = Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout (width * height * 4) in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let cell_x = x / cell_size in
      let cell_y = y / cell_size in
      let is_white = (cell_x + cell_y) mod 2 = 0 in
      let color = if is_white then 255 else 0 in
      let offset = (y * width + x) * 4 in
      Bigarray.Array1.set data offset color;        (* R *)
      Bigarray.Array1.set data (offset + 1) color;  (* G *)
      Bigarray.Array1.set data (offset + 2) color;  (* B *)
      Bigarray.Array1.set data (offset + 3) 255;    (* A *)
    done
  done;
  data
```

## When You Need an Unimplemented API

If a lesson requires WebGPU functionality that isn't exposed in our bindings:

1. **Stop work on that lesson** - undo your changes
2. **File an issue** in `tasks/triage/` describing:
   - Which lesson needs the API
   - What WebGPU function/parameter is missing
   - Link to the relevant WebGPU spec if helpful
3. **Commit just the task file**, not the incomplete port
4. Revert all other changes

Do NOT attempt workarounds that require modifying the bindings. The lesson can
be completed after the API is added.

If some examples in a lesson are able to be ported but not others, file a task 
as described above, but commit the example code that is workable and proceed.

## Adapting to Available APIs

For things like automatic vs explicit vertex buffer layouts, or other API
design differences: adapt. You're porting the spirit of the lesson, not doing
a line-by-line translation.

If the JavaScript lesson uses a pattern that doesn't fit our API, find an
equivalent that achieves the same visual/computational result.

## Reference Materials

- **JavaScript sources**: `webgpu_fundamentals/<lesson-name>/`
- **Lesson text**: `webgpu_fundamentals/<lesson-name>/lesson.txt` contains the
  tutorial prose explaining the concepts
- **Existing tests**: `test/integration/` for working examples of the API
- **API docs**: `lib/wgpu.mli` is the high-level API interface

## Running Your Port

```bash
# Run all tests (will compare against expected PNGs)
dune runtest

# Promote new expected images after visual verification
dune promote test/fundamentals/rotation/rotation.expected.png

# Format code
dune fmt > /dev/null || true

# Check for warnings (must pass before committing)
dune build @check
```
