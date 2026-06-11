open! Core
include Executor_intf

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

module Batch_to_parallel (B : S_batch) : S_parallel = struct
  module Variable_idx = B.Variable_idx

  module Prepared = struct
    type t = B.Prepared.t

    let of_tree = B.Prepared.of_tree

    let lookup_variable t name =
      match B.Prepared.lookup_variable t name with
      | var -> Some var
      | exception _ -> None
    ;;
  end

  (* A mutable result grid that mode-crosses contention, so the parallel [run] can fill it
     from multiple worker domains (each writing disjoint pixels). This mirrors how
     [Image_buf] shares its backing buffer across the same scheduler: the [Portended.t]
     wrapper makes the grid [contended portable], and [magic_uncontended] recovers mutable
     access inside each task. *)
  module Grid = struct
    (* Backed by a [Bigarray] (rather than a plain [int32# array]) because, like
       [Image_buf]'s buffer, a bigarray mode-crosses portability and so can sit inside the
       [Portended.t] wrapper. Each element holds the raw bits of a {!Value.t}. *)
    type inner =
      { data : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
      ; width : int
      }

    type t = inner Modes.Portended.t

    let create ~width ~height : t =
      let data =
        Bigarray.Array1.create Bigarray.Int32 Bigarray.C_layout (width * height)
      in
      { Modes.Portended.portended = { data; width } }
    ;;

    let[@inline] uncontended (t : t) =
      Stdlib.Obj.magic_uncontended t.Modes.Portended.portended
    ;;

    let set t ~x ~y v =
      let inner = uncontended t in
      let bits @ local = Int32_u.to_int32 (Value.to_int v) in
      Bigarray.Array1.set inner.data ((y * inner.width) + x) bits
    ;;

    let get t ~x ~y =
      let inner = uncontended t in
      Value.of_int
        (Int32_u.of_int32 (Bigarray.Array1.get inner.data ((y * inner.width) + x)))
    ;;
  end

  module Result = struct
    type t = Grid.t

    let get = Grid.get
  end

  module Batch = struct
    type t =
      { prepared : Prepared.t
      ; region : Sample_region.t
      ; mutable variables : (Variable_idx.t * int32) list
      }

    let create prepared region = { prepared; region; variables = [] }

    let set_variable t ~var value =
      t.variables <- (var, Int32_u.to_int32 (Value.to_int value)) :: t.variables
    ;;

    let apply_variables b variables =
      List.iter variables ~f:(fun (var, bits) ->
        let value = Value.of_int (Int32_u.of_int32 bits) in
        B.Batch.set_variable b ~var value)
    ;;

    let (run @ portable) t ~par ~oracles =
      let { prepared; region; variables } = t in
      let width = region.samples_x in
      let height = region.samples_y in
      let result = Grid.create ~width ~height in
      Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
        let b = B.Batch.create prepared (Sample_region.row region y) in
        apply_variables b variables;
        let row = B.Batch.run b ~oracles in
        for x = 0 to width - 1 do
          Grid.set result ~x ~y (B.Result.get_output row ~px:x)
        done);
      result
    ;;
  end
end

module Parallel_to_single (S : S_single) : S_parallel =
  Batch_to_parallel (Single_to_batch (S))
