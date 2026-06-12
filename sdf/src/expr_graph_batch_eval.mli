@@ portable

open! Core

(** The SIMD register-VM evaluator: 4 pixels at a time over [float32x4#] lanes, with
    {!Expr_graph_eval.Private} as the scalar tail for widths not divisible by 4. This is
    the production evaluator — the tiled machinery ({!Tiled_eval}, [Sdf_contour]) runs one
    batch per active tile. *)

module Variable_idx : sig
  type t : value mod contended portable
end

module Prepared : sig
  type t : value mod contended portable

  val of_tree : Expr_tree.t -> t
  val lookup_variable : t -> string -> Variable_idx.t
end

module Result : sig
  type t

  val get_output : t -> px:int -> Value.t
end

module Batch : sig
  type t

  val create : Prepared.t -> Sample_region.t -> t

  (** A batch over the index-space sub-rectangle of [region] whose top-left sample is
      [(x0, y0)]. Sample [(i, j)] (i.e. [px = j * samples_x + i]) is evaluated at exactly
      [(Sample_region.x_at region (x0 + i), Sample_region.y_at region (y0 + j))] — bitwise
      the same coordinates as the corresponding sample of a batch over the whole region,
      so samples shared by overlapping sub-rectangles evaluate identically. *)
  val create_sub
    :  Prepared.t
    -> Sample_region.t
    -> x0:int
    -> y0:int
    -> samples_x:int
    -> samples_y:int
    -> t

  val set_variable : t -> var:Variable_idx.t -> Value.t -> unit
  val run : t -> oracles:Prepared_oracle.t Map.M(Oracle_key).t -> Result.t
end
