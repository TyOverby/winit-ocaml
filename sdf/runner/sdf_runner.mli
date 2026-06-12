open! Core
open Sdf

type t

val create : (module Executor.S) @ portable -> t
val add_oracle : t -> name:string -> (module Oracle.S) @ portable -> unit
val set_executor : t -> (module Executor.S) @ portable -> unit

(** Every [run*] function takes an optional [trace] writer (default: a no-op null writer).
    When given a live writer, the runner records coarse phases beneath the current span:
    [run]/[run-contour]/[run-tiled], with children [compile] (only when the source
    changed), [prepare-oracles] (one [oracle:<name>] child per oracle prepared), the
    evaluation phase ([eval-grid] / [extract-contour] / [tiled-eval]), and — for [run] —
    [consume], covering the caller's [~f] callback. Cache hits record only the outer span. *)
val run
  :  t
  -> ?trace:Phase_trace.t
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

(** The zero contour of the scene over [region] as marching-squares line segments (4
    floats per segment, cell-index coordinates), extracted sparsely: tiles the interval
    evaluator proves sign-uniform are never sampled. Bitwise identical to marching a dense
    evaluation of the grid. Cached across calls like [run]. *)
val run_contour
  :  t
  -> ?trace:Phase_trace.t
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
  -> ?trace:Phase_trace.t
  -> region:Sample_region.t
  -> filename:string
  -> string
  -> cull:Tile_scheduler.Cull.t
  -> Tiled_eval.Result.t
