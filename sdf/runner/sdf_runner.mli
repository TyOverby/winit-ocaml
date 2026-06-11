open! Core
open Sdf

type t

val create : (module Executor.S) @ portable -> t
val add_oracle : t -> name:string -> (module Oracle.S) @ portable -> unit
val set_executor : t -> (module Executor.S) @ portable -> unit

val run
  :  t
  -> region:Sample_region.t
  -> filename:string
  -> string
  -> f:
       ('a.
        Parallel.t @ local
        -> 'a @ contended portable
        -> ('a -> x:int -> y:int -> Value.t) @ portable
        -> unit)
     @ once shareable
  -> unit

(** The zero contour of the scene over [region] as marching-squares line segments
    (4 floats per segment, cell-index coordinates), extracted sparsely: tiles the
    interval evaluator proves sign-uniform are never sampled. Bitwise identical to
    marching a dense evaluation of the grid. Cached across calls like [run]. *)
val run_contour
  :  t
  -> region:Sample_region.t
  -> filename:string
  -> string
  -> segments:float32# array * length:int * stats:Sdf_contour.Stats.t

(** A sparse tiled evaluation of the scene over [region]: tiles culled by [cull] are
    recorded with just their value interval; the rest are densely evaluated. Replay the
    result with {!Sdf.Tiled_eval.Result.iter}. Cached across calls (keyed on region and
    [cull]). *)
val run_tiled
  :  t
  -> region:Sample_region.t
  -> filename:string
  -> string
  -> cull:Tile_scheduler.Cull.t
  -> Tiled_eval.Result.t
