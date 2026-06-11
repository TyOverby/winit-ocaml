@@ portable

open! Core

(** Sparse tiled evaluation for rendering consumers: tiles culled by a
    {!Tile_scheduler.Cull} predicate are never sampled, and only their verdict interval
    is reported; the remaining (active) tiles are densely evaluated in parallel — at
    bitwise the same coordinates a dense whole-grid evaluation would use — and their
    sample values retained. *)

module Result : sig
  type t : value mod contended portable

  val scheduler : t -> Tile_scheduler.t

  (** Sequential replay of the evaluation. [fill] is called once per culled tile with the
      interval that justified the cull; [draw] once per active tile with a getter for the
      tile's sample patch ([px = j * samples_x + i], row-major, [samples_x * samples_y]
      entries). Tile rectangles are in sample-index space; adjacent tiles share their
      boundary sample row/column, so rectangles overlap by one sample (verdicts of
      overlapping tiles are always mutually consistent, so writing the shared pixels
      twice is harmless). Together the rectangles cover every sample of the region.

      Replay is cheap (no expression evaluation), can be repeated, and the callbacks need
      not be portable. *)
  val iter
    :  t
    -> fill:(x0:int -> y0:int -> samples_x:int -> samples_y:int -> Interval.t -> unit)
    -> draw:
         (x0:int
          -> y0:int
          -> samples_x:int
          -> samples_y:int
          -> get:(int -> Value.t)
          -> unit)
    -> unit
end

(** Evaluate [tree] over [region]'s sample grid, skipping tiles that [cull] proves
    uninteresting. [Bool]-typed trees skip interval scheduling and evaluate every tile.
    [tile_cells] defaults to 32. *)
val run
  :  exec:(module Executor.S)
  -> par:Parallel.t @ local
  -> oracles:Prepared_oracle.t Map.M(Oracle_key).t
  -> region:Sample_region.t
  -> ?tile_cells:int
  -> cull:Tile_scheduler.Cull.t
  -> Expr_tree.t
  -> Result.t
