# `sdf/neon` — the Neon application

`neon` is the executable front-end for the SDF evaluator. It is a `Command.group`
(`neon.ml`) with two subcommands:

- **`ui`** (`ui.ml`) — an interactive windowed viewer built on `winit` +
  `softbuffer`. It renders a `.neo` scene to a canvas (`Image_buf`), supports
  click-and-drag panning (tracking an `offset_x`/`offset_y` into the scene), and
  has multiple render modes (`Grayscale`, `Rings`). It drives evaluation through
  `Sdf_runner`, so re-renders during a drag reuse the runner's caches.
- **`svg`** (`svg.ml`) — a batch exporter that evaluates a scene, extracts its
  zero-contour, and writes the result as an SVG file (`-o`, with `-x`/`-y`/
  `-width`/… framing flags).

Both subcommands register the available oracles (`passthrough`, `resample`) with
the runner so scenes can reference them.

## Relationship to the rest of `sdf`

`neon` is the top of the stack and wires everything together: `neo` (parse +
compile) → `sdf` (evaluate) via `sdf_runner`, plus `march` (marching squares)
and `line_join` (segment → polyline) for the contour/SVG path.

## Example scenes

`boxes.neo` and `squiggly_circles.neo` are sample Neo programs used for manual
testing of the UI and exporter.
