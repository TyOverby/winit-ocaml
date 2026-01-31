# Migrate image-based tests to use imgdiff.sh and mode promote

## Background

The `test/integration/render_uniform_buffer/dune` file has been updated with a
better pattern for image-based tests:

```dune
(rule
 (alias runtest)
 (action
  (run ./render_uniform_buffer.exe))
 (targets render_uniform_buffer.png)
 (mode promote))

(rule
 (alias runtest)
 (deps
  "%{workspace_root}/imgdiff.sh"
  render_uniform_buffer.expected.png
  render_uniform_buffer.png)
 (action
  (bash "%{deps}")))
```

Key changes from the old pattern:
1. **`(mode promote)`** - Generated `.png` files are automatically promoted to
   the source directory after each build
2. **`imgdiff.sh`** - Uses fuzzy image comparison with ImageMagick's `compare`
   and a threshold (0.01), rather than exact byte comparison with `cmp`
3. **Explicit deps** - Dependencies are properly declared

## Task

Update all other image-based test dune files to use this pattern:

- `test/integration/render_clear/dune`
- `test/integration/render_triangle/dune`
- `test/integration/vertex_buffer_layout/dune`
- `test/integration/bigarray_polymorphism/dune` (if it has image output)
- `test/fundamentals/rotation/dune`
- Any other image-generating tests

## Documentation Updates

Update `test/CLAUDE.md` to reflect the new workflow:

### Old workflow:
```bash
# Run test, see failure, manually promote
dune runtest
dune promote test/path/to/image.expected.png
```

### New workflow:
The generated `.png` files are automatically promoted to the source directory
via `(mode promote)`. To update expected images:

```bash
# Run the test - the .png file is generated and promoted automatically
dune runtest

# If the test fails (images differ), inspect the difference:
# - The generated .png is now in the source directory
# - Compare it visually with the .expected.png

# If the new image is correct, update the expected file:
cp test/path/to/image.png test/path/to/image.expected.png

# Run tests again to verify
dune runtest
```

### Creating new expected images:
```bash
# Run the test to generate the .png
dune build @runtest  # or just run the executable

# The .png is promoted to source directory
# Inspect it, then copy to expected:
cp test/path/to/image.png test/path/to/image.expected.png
```

## Notes

- The fuzzy comparison allows for minor rendering differences (e.g., from
  different GPU drivers or anti-aliasing) while still catching meaningful
  changes
- The threshold of 0.01 (1%) can be adjusted in `imgdiff.sh` if needed

## Plan

### Files to update:
1. `test/integration/render_clear/dune` - uses `cmp`, needs `imgdiff.sh` + `mode promote`
2. `test/integration/render_triangle/dune` - uses `cmp`, needs `imgdiff.sh` + `mode promote`
3. `test/integration/vertex_buffer_layout/dune` - uses `cmp`, needs `imgdiff.sh` + `mode promote`
4. `test/fundamentals/rotation/dune` - uses `diff`, has multiple images, needs `imgdiff.sh` + `mode promote`
5. `test/CLAUDE.md` - update documentation with new workflow

Note: `test/integration/bigarray_polymorphism/dune` does NOT produce images, so no changes needed.

### Pattern to apply:
For each image-generating test, transform:
```dune
(rule
 (alias runtest)
 (action (run ./test.exe))
 (targets test.png))

(rule
 (alias runtest)
 (action (cmp test.expected.png test.png)))
```

Into:
```dune
(rule
 (alias runtest)
 (action (run ./test.exe))
 (targets test.png)
 (mode promote))

(rule
 (alias runtest)
 (deps
  "%{workspace_root}/imgdiff.sh"
  test.expected.png
  test.png)
 (action (bash "%{deps}")))
```

### Validation criteria:
1. All dune files updated to use `mode promote` and `imgdiff.sh`
2. `dune build` succeeds
3. `dune runtest` passes (or at least runs the image comparison correctly)
4. `test/CLAUDE.md` updated with new workflow documentation
5. No warnings from `dune build @check`
