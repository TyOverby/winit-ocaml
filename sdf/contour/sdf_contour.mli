@@ portable

open! Core
open Sdf

(** Tiled zero-contour extraction: equivalent to densely sampling an expression over a
    region and running marching squares on the whole grid, but skips sampling any tile
    that {!Sdf.Tile_scheduler} proves the contour cannot enter.

    Equivalence is exact, not approximate: active tiles are sampled at bitwise the same
    coordinates the dense grid would use ({!Executor.S_batch.Batch.create_sub}) and
    marched with global cell offsets ({!March.run_offset}), so the emitted segments are
    bitwise identical to a dense run's — including the shared endpoints at tile seams
    that [line_join] stitches by exact equality. Culled tiles are sign-uniform on every
    sample they cover, so the dense run would emit nothing there. *)

module Stats : sig
  type t =
    { tiles_total : int
    ; tiles_culled : int
    ; samples_evaluated : int (** dense sampling would evaluate the full grid *)
    }
  [@@deriving sexp_of]
end

(** Extract the zero contour of [tree] over [region]'s sample grid. Returns marching
    squares' segment array (4 floats per segment, coordinates in the region's cell-index
    space) and the segment count.

    [Bool]-typed trees skip interval scheduling and sample every tile (matching the dense
    pipeline's behavior of reinterpreting the bits).

    [tile_cells] is the cull granularity in grid cells (default 32). *)
val extract
  :  exec:(module Executor.S)
  -> par:Parallel.t @ local
  -> oracles:Oracle.Prepared.t Map.M(Oracle.Key).t
  -> region:Sample_region.t
  -> ?tile_cells:int
  -> Expr_tree.t
  -> segments:float32# array * length:int * stats:Stats.t
