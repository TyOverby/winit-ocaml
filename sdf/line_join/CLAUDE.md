# `sdf/line_join` — segments → polylines

`march` emits an unordered flat list of line segments. `line_join` stitches
those segments into connected polylines, distinguishing closed loops from open
chains. (Compiles with `js_of_ocaml` for the browser build.)

## API

```
val f : float32# array -> length:int -> Connected.t list
```

The input is the raw `x1,y1,x2,y2,…` segment array produced by `March.run`
(`length` = segment count). Each result is a `Connected.t`:

- `Joined of Point.t list` — a closed loop (the chain returns to its start).
- `Disjoint of Point.t list` — an open polyline.

## How it works

- **`Point`** — a `(float, float)` coordinate, made hashable/comparable so
  segment endpoints can key a table. Joining relies on exact point equality,
  which holds because `march` emits bitwise-identical coordinates for shared
  edges.
- **`Line`** — a segment (`p1`, `p2`).
- **`Bi_map`** (`bi_map.ml`) — a bidirectional index of the segment set: a `dict`
  of id→line, plus `starts`/`ends` tables mapping a point to the ids that begin
  or end there. Supports `find_by_start` / `find_by_end` (pop a segment touching
  a point) and `remove`.
- **`line_join.ml`** — repeatedly pulls a seed segment and follows the chain
  both forward (matching `p1` to the current endpoint) and backward (matching
  `p2`), consuming segments from the `Bi_map` until no neighbor remains, then
  classifies the chain as `Joined` or `Disjoint`.
