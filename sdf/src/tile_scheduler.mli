@@ portable

open! Core

(** Plans a sparse evaluation of a sample grid by proving, with the interval evaluator
    ({!Expr_graph_range_eval}), that whole tiles of the grid cannot affect the consumer's
    output and so need not be sampled.

    The grid's cells are partitioned into square tiles of [tile_cells] x [tile_cells]
    cells (smaller at the right/bottom edges). A tile's {e sample} footprint is one wider
    and taller than its cell footprint, so adjacent tiles share a boundary row/column of
    samples; a tile's verdict covers every sample in that footprint.

    [schedule] recursively subdivides the tile grid (splitting the longer axis), asking
    the interval evaluator for a bound over each rectangle's sample coordinates. When the
    bound satisfies the cull predicate the whole rectangle is marked culled; otherwise it
    descends, and an un-culled single tile is marked active. The result is a flat verdict
    grid — the recursion tree itself is never materialized.

    Verdicts are conservative: a culled tile's interval is guaranteed to contain the value
    the scalar evaluator produces at {e every} sample in the tile's footprint (regardless
    of backend, since all backends bisimulate). Overestimation only ever turns culled into
    active, never the reverse. *)

module Cull : sig
  (** The reason a tile may be skipped. Comparable (not a closure) so that schedules can
      be cached keyed on it. A [top] interval never satisfies any predicate. *)
  type t =
    | No_contour
    (** Cull tiles that the zero contour provably misses: every sample is strictly
        positive (marching squares treats a corner as inside iff [v <= 0]) or every
        sample is [<= 0]. *)
    | Constant_outside of
        { below : float
        ; above : float
        }
    (** Cull tiles whose values are provably all [<= below] or all [> above] — for
        consumers whose rendering is constant outside [(below, above]], e.g. the
        grayscale ramp with [below = 0.] and [above = 1.]. *)
  [@@deriving sexp_of, equal]

  (** [culls t interval] is true iff a tile bounded by [interval] may be skipped. *)
  val culls : t -> Interval.t -> bool
end

module Verdict : sig
  type t =
    | Culled of Interval.t
    (** The interval that satisfied the cull predicate. Never [top]. *)
    | Active
end

type t : value mod contended portable

(** Tile-grid dimensions. [tiles_x t = 0] (or [tiles_y]) iff the region has no samples in
    that axis. *)
val tiles_x : t -> int

val tiles_y : t -> int
val tile_cells : t -> int
val verdict : t -> tx:int -> ty:int -> Verdict.t

(** Index of the first sample covered by tile [tx] (the tile's cell origin). *)
val tile_x0 : t -> tx:int -> int

val tile_y0 : t -> ty:int -> int

(** Number of samples covered by tile [tx] in x, including the boundary column shared
    with tile [tx + 1]. The tile spans [tile_samples_x - 1] cells (0 for a degenerate
    one-sample-wide grid). *)
val tile_samples_x : t -> tx:int -> int

val tile_samples_y : t -> ty:int -> int

val schedule
  :  Expr_graph_range_eval.t
  -> vars:Value.Boxed.t Map.M(Expr_graph_range_eval.Variable_idx).t
  -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
  -> region:Sample_region.t
  -> tile_cells:int
  -> cull:Cull.t
  -> t

(** A schedule with every tile active — the degenerate fallback when interval evaluation
    is unavailable (e.g. a [Bool]-typed program). *)
val all_active : region:Sample_region.t -> tile_cells:int -> t

val num_tiles : t -> int
val num_active : t -> int

(** An ASCII map of the verdict grid, one character per tile: ['.'] active, ['+'] culled
    all-positive, ['-'] culled all-[<= 0], ['o'] culled for another reason (only possible
    under [Constant_outside]). *)
val to_string_hum : t -> string
