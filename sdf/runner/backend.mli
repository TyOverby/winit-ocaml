open! Core
open Sdf

module Contour_result : sig
  type t =
    { segments : float32# array
    ; length : int
    ; stats : Sdf_contour.Stats.t
    }
end

module type S = sig
  module E : Executor.S

  type t

  val create : unit -> t
  val add_oracle : t -> name:string -> (module Oracle.S) @ portable -> unit
  val scheduler : t -> Parallel_scheduler.t

  val run
    :  t
    -> region:Sample_region.t
    -> filename:string
    -> string
    -> E.Parallel.Result.t

  (** The zero contour of the scene over [region], via {!Sdf_contour.extract} (tiles the
      contour provably misses are never sampled). Cached like [run]'s output. *)
  val run_contour
    :  t
    -> region:Sample_region.t
    -> filename:string
    -> string
    -> Contour_result.t

  (** A sparse tiled evaluation of the scene over [region], via {!Sdf.Tiled_eval}. The
      cache key includes [cull], since the verdicts depend on it. *)
  val run_tiled
    :  t
    -> region:Sample_region.t
    -> filename:string
    -> string
    -> cull:Tile_scheduler.Cull.t
    -> Tiled_eval.Result.t
end

module Make (E : Executor.S @ portable) : S with module E = E
