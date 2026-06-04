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
      ; mutable variables : Value.Boxed.t S.Variable_idx.Map.t
      ; x_coords : float32# array
      ; y_coords : float32# array
      }

    let create prepared ~len =
      { prepared
      ; len
      ; variables = S.Variable_idx.Map.of_alist_exn []
      ; x_coords = Array.create ~len #0.0s
      ; y_coords = Array.create ~len #0.0s
      }
    ;;

    let set_variable t ~var value =
      let boxed = Value.box value in
      t.variables <- Map.set t.variables ~key:var ~data:boxed
    ;;

    let set_x t ~px value = Array.set t.x_coords px (Value.to_float value)
    let set_y t ~px value = Array.set t.y_coords px (Value.to_float value)

    let (run @ portable) t ~oracles =
      let out = Value.Array.create ~len:t.len in
      for i = 0 to t.len - 1 do
        let x = Array.get t.x_coords i in
        let y = Array.get t.y_coords i in
        Value.Array.set out i (S.run t.prepared ~vars:t.variables ~oracles ~x ~y)
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
    let batch = B.Batch.create t ~len:1 in
    B.Batch.set_x batch ~px:0 (Value.of_float x);
    B.Batch.set_y batch ~px:0 (Value.of_float y);
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

  type xy_affine =
    { base : float
    ; dx : float
    ; dy : float
    }

  module Batch = struct
    type t =
      { prepared : Prepared.t
      ; width : int
      ; height : int
      ; mutable variables : (Variable_idx.t * int32) list
      ; mutable x_affine : xy_affine
      ; mutable y_affine : xy_affine
      }

    let create prepared ~width ~height =
      { prepared
      ; width
      ; height
      ; variables = []
      ; x_affine = { base = 0.0; dx = 0.0; dy = 0.0 }
      ; y_affine = { base = 0.0; dx = 0.0; dy = 0.0 }
      }
    ;;

    let set_x_affine t ~base ~dx ~dy = t.x_affine <- { base; dx; dy }
    let set_y_affine t ~base ~dx ~dy = t.y_affine <- { base; dx; dy }

    let set_variable t ~var value =
      t.variables <- (var, Int32_u.to_int32 (Value.to_int value)) :: t.variables
    ;;

    let apply_variables b variables =
      List.iter variables ~f:(fun (var, bits) ->
        let value = Value.of_int (Int32_u.of_int32 bits) in
        B.Batch.set_variable b ~var value)
    ;;

    let apply_xy_coords b ~width ~y ~x_affine ~y_affine =
      let x_row_term = x_affine.dy *. Float.of_int y in
      let y_row_term = y_affine.dy *. Float.of_int y in
      for px = 0 to width - 1 do
        let fpx = Float.of_int px in
        let xv = x_affine.base +. (x_affine.dx *. fpx) +. x_row_term in
        B.Batch.set_x b ~px (Value.of_float (Float32_u.of_float xv));
        let yv = y_affine.base +. (y_affine.dx *. fpx) +. y_row_term in
        B.Batch.set_y b ~px (Value.of_float (Float32_u.of_float yv))
      done
    ;;

    let (run @ portable) t ~par ~oracles =
      let { prepared; width; height; variables; x_affine; y_affine } = t in
      let result = Grid.create ~width ~height in
      Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
        let b = B.Batch.create prepared ~len:width in
        apply_xy_coords b ~width ~y ~x_affine ~y_affine;
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
