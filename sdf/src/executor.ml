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
      ; len : int
      ; variables : Value.Boxed.t S.Variable_idx.Map.t Int.Table.t
      }

    let create prepared ~len = { prepared; len; variables = Int.Table.create () }

    let set_variable t ~var ~px value =
      let boxed = Value.box value in
      Hashtbl.update t.variables px ~f:(function
        | None -> S.Variable_idx.Map.singleton var boxed
        | Some map -> Map.set map ~key:var ~data:boxed)
    ;;

    let (run @ portable) t ~oracles =
      let out = Value.Array.create ~len:t.len in
      for i = 0 to t.len - 1 do
        let vars = Hashtbl.find_exn t.variables i in
        Value.Array.set out i (S.run t.prepared ~vars ~oracles)
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

  let run t ~vars ~oracles =
    let batch = B.Batch.create t ~len:1 in
    Map.iteri vars ~f:(fun ~key ~data ->
      let var = B.Prepared.lookup_variable t key in
      B.Batch.set_variable batch ~var ~px:0 (Value.unbox data));
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

  (* How a single variable is bound across the whole grid. Payloads are boxed (and grid
     buffers wrapped in [Portended.t]) so that the binding list mode-crosses contention
     and can be shared with the worker domains. *)
  type binding =
    | Uniform of Variable_idx.t * int32
    | Affine of Variable_idx.t * float * float * float
    | Grid_input of
        Variable_idx.t
        * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
            Modes.Portended.t

  module Batch = struct
    type t =
      { prepared : Prepared.t
      ; width : int
      ; height : int
      ; mutable bindings : binding list
      }

    let create prepared ~width ~height = { prepared; width; height; bindings = [] }
    let add t binding = t.bindings <- binding :: t.bindings

    let set_uniform t ~var value =
      add t (Uniform (var, Int32_u.to_int32 (Value.to_int value)))
    ;;

    let set_affine t ~var ~base ~dx ~dy = add t (Affine (var, base, dx, dy))

    let set_grid t ~var data =
      add t (Grid_input (var, { Modes.Portended.portended = data }))
    ;;

    (* Apply [binding] across one row [y] of a freshly created [S] batch [b] of length
       [width]. *)
    let apply_binding b ~width ~y binding =
      match binding with
      | Uniform (var, bits) ->
        let value = Value.of_int (Int32_u.of_int32 bits) in
        for px = 0 to width - 1 do
          B.Batch.set_variable b ~var ~px value
        done
      | Affine (var, base, dx, dy) ->
        let row_term = dy *. Float.of_int y in
        for px = 0 to width - 1 do
          let v = base +. (dx *. Float.of_int px) +. row_term in
          B.Batch.set_variable b ~var ~px (Value.of_float (Float32_u.of_float v))
        done
      | Grid_input (var, data) ->
        let data = Stdlib.Obj.magic_uncontended data.Modes.Portended.portended in
        let row = y * width in
        for px = 0 to width - 1 do
          let bits = Int32_u.of_int32 (Bigarray.Array1.get data (row + px)) in
          B.Batch.set_variable b ~var ~px (Value.of_int bits)
        done
    ;;

    let (run @ portable) t ~par ~oracles =
      (* Snapshot the (immutable) binding list so the parallel closure captures it rather
         than the mutable [t], keeping the closure shareable across domains. *)
      let { prepared; width; height; bindings } = t in
      let result = Grid.create ~width ~height in
      Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
        let b = B.Batch.create prepared ~len:width in
        List.iter bindings ~f:(apply_binding b ~width ~y);
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
