# `sdf/march` — marching squares

A thin OCaml wrapper (`march.ml`) over a C implementation (`march.c`) of the
**marching squares** algorithm. Given a grid of sampled scalar values, it
extracts the line segments that approximate the field's zero-contour (the SDF
surface).

## API

```
val run : float32# array -> float32# array -> int -> int -> int
```

`run grid output width height` reads the `width`×`height` `grid` (row-major) and
writes contour segments into `output`, returning the number of segments emitted.
Each segment occupies 4 floats (`x1, y1, x2, y2`); `output` must therefore have
room for `width * height * 2 * 4` floats (up to 2 segments per cell). Emitted
coordinates are in **cell-index space**, not world space.

## Determinism

`march.c` is careful to compute each edge's zero-crossing from the *same*
expression in both cells that share the edge (corners are always passed in a
canonical per-edge order), so adjacent cells produce bitwise-identical endpoint
coordinates. This is what lets `line_join` stitch segments together by exact
point equality, and what keeps the `resample` oracle's contour watertight.

The C stub also has an `EMSCRIPTEN` path so it can compile to WASM for the
browser build.

## Consumers

- `sdf/line_join` joins the flat segment list into connected polylines.
- `sdf/oracles/resample` runs `march` to re-derive a clean distance field.
- `sdf/neon`'s `svg` exporter turns the contour into SVG paths.
