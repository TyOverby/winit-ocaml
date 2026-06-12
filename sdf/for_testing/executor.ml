open! Core
open Sdf

(* The evaluator "shapes" the differential/bisimulation test suites functorize over, plus
   the adapters that convert between them. Production code does not use these: it calls
   [Sdf.Expr_graph_batch_eval] (batches) and [Sdf.Expr_graph_eval.Single] (points)
   directly. The shapes exist so the same test suite can run against every evaluator —
   including the reference tree interpreter ({!Expr_tree_eval}) — and compare results. *)

module type S_single = sig @@ portable
  type t : value mod contended portable

  module Variable_idx : sig
    type t : value mod contended portable

    include Comparator.S [@mode portable] with type t := t
  end

  val of_tree : Expr_tree.t -> t
  val lookup_variable : t -> string -> Variable_idx.t

  val run
    :  t
    -> vars:Value.Boxed.t Map.M(Variable_idx).t
    -> oracles:Oracle.Prepared.t Map.M(Oracle.Key).t
    -> x:Float32_u.t
    -> y:Float32_u.t
    -> Value.t
end

module type S_batch = sig @@ portable
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
        [(x0, y0)]. Sample [(i, j)] (i.e. [px = j * samples_x + i]) is evaluated at
        exactly [(Sample_region.x_at region (x0 + i), Sample_region.y_at region (y0 + j))]
        — bitwise the same coordinates as the corresponding sample of a batch over the
        whole region, so samples shared by overlapping sub-rectangles evaluate
        identically. *)
    val create_sub
      :  Prepared.t
      -> Sample_region.t
      -> x0:int
      -> y0:int
      -> samples_x:int
      -> samples_y:int
      -> t

    val set_variable : t -> var:Variable_idx.t -> Value.t -> unit
    val run : t -> oracles:Oracle.Prepared.t Map.M(Oracle.Key).t -> Result.t
  end
end

module Single_to_batch (S : S_single) : S_batch = struct
  module Variable_idx = struct
    type t = S.Variable_idx.t
  end

  module Prepared = struct
    type t = S.t

    let of_tree = S.of_tree
    let lookup_variable = S.lookup_variable
  end

  module Result = struct
    type t = Value.Array.t

    let get_output t ~px = Value.Array.get t px
  end

  module Batch = struct
    type t =
      { prepared : S.t
      ; region : Sample_region.t
      ; x0 : int
      ; y0 : int
      ; samples_x : int
      ; samples_y : int
      ; mutable variables : Value.Boxed.t Map.M(S.Variable_idx).t
      }

    let create_sub prepared region ~x0 ~y0 ~samples_x ~samples_y =
      { prepared
      ; region
      ; x0
      ; y0
      ; samples_x
      ; samples_y
      ; variables = Map.empty (module S.Variable_idx)
      }
    ;;

    let create prepared (region : Sample_region.t) =
      create_sub
        prepared
        region
        ~x0:0
        ~y0:0
        ~samples_x:region.samples_x
        ~samples_y:region.samples_y
    ;;

    let set_variable t ~var value =
      let boxed = Value.box value in
      t.variables <- Map.set t.variables ~key:var ~data:boxed
    ;;

    let (run @ portable) t ~oracles =
      let { prepared; region; x0; y0; samples_x; samples_y; variables } = t in
      let len = samples_x * samples_y in
      let out = Value.Array.create ~len in
      for i = 0 to len - 1 do
        let col = i mod samples_x in
        let row = i / samples_x in
        let x = Sample_region.x_at region (x0 + col) in
        let y = Sample_region.y_at region (y0 + row) in
        Value.Array.set out i (S.run prepared ~vars:variables ~oracles ~x ~y)
      done;
      out
    ;;
  end
end

module Batch_to_single (B : S_batch) : S_single = struct
  module Variable_idx = String

  type t = B.Prepared.t

  let of_tree = B.Prepared.of_tree
  let lookup_variable _t name = name

  let run t ~vars ~oracles ~x ~y =
    let batch = B.Batch.create t (Sample_region.point ~x ~y) in
    Map.iteri vars ~f:(fun ~key ~data ->
      match B.Prepared.lookup_variable t key with
      | var -> B.Batch.set_variable batch ~var (Value.unbox data)
      | exception _ -> ());
    let result = B.Batch.run batch ~oracles in
    B.Result.get_output result ~px:0
  ;;
end
