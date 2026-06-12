# `sdf/oracles` — oracle implementations

An **oracle** is a named sub-field that a Neo scene references like a builtin
(e.g. `resample(...)`). Rather than being recomputed per pixel inside the main
expression, an oracle is *prepared* once over a sample region and then sampled.
The interface (`Sdf.Oracle.S` / `Prepared_oracle`) lives in `../src`; see
`../src/CLAUDE.md`. This directory holds the concrete implementations, each its
own dune library, registered with the runner by name.

## `passthrough`

`sdf_passthrough_oracle` — the trivial/reference oracle. Its prepared form just
holds a single-point evaluator for the inner tree and, on `sample ~x ~y`, runs
that tree directly and returns the float. Useful as an identity oracle and for
testing the oracle machinery without any precomputation.

## `resample`

`sdf_resample_oracle` — re-derives a clean signed-distance field from an
arbitrary inner pseudo-SDF. At `prepare` time it:

1. Evaluates the inner tree over the region (expanded by a 2-cell border) into a
   grid.
2. Runs `march` (marching squares) to extract that grid's zero-contour as line
   segments.
3. Builds a `nearest_seg` spatial index over the segments, with
   `~assume_level_set:true`: marching-squares output is a level-set contour, which
   lets `query_range` resolve sign ambiguities with a midpoint probe (see the
   `nearest_seg` mli). Without it, `sample_range` straddles zero for any box that
   overlaps the contour's extent in one axis, however far away, defeating tile
   culling.

Then `sample ~x ~y` maps world coordinates into the expanded grid's index space,
queries the nearest contour segment, and scales the index-space distance back to
world units. This turns a cheap-but-distorted distance estimate into an accurate
nearest-surface distance.

(`sdf/debug/debug_resample.ml` is a standalone harness that replicates this
pipeline to investigate sign bugs in the resampled field.)
