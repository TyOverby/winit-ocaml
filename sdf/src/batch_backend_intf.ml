open! Core

module type S = sig @@ portable
  module Variable_idx : sig
    (* [Prepared.t] and [Variable_idx.t] mode-cross portability and contention so that a
       prepared program (and the variable indices looked up from it) can be shared across
       the worker domains of a parallel render. *)
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

    val create : Prepared.t -> len:int -> t
    val set_variable : t -> var:Variable_idx.t -> px:int -> Value.t -> unit
    val run : t -> Result.t
  end
end

(* A grid-native, bulk evaluation interface.

   Where {!S} evaluates a 1-D batch and is driven one pixel at a time (cheap for CPU/SIMD,
   pathological for a GPU), an [S_parallel] backend evaluates an entire [width] x [height]
   grid in one shot. It owns its own parallelism — CPU backends fan out over the supplied
   scheduler; a future GPU backend would ignore the scheduler and issue a single dispatch
   — and it accepts inputs in bulk:

   - {!Batch.set_uniform} for a value constant across the whole grid (e.g. time);
   - {!Batch.set_affine} for a value that is an affine function of the pixel coordinate,
     [base +. dx *. x +. dy *. y]. The SDF coordinates [x] and [y] are exactly this, so
     the common case uploads no per-pixel data at all;
   - {!Batch.set_grid} for a fully general per-pixel input supplied as a row-major buffer.

   Outputs are read back with {!Result.get}; after [run] the results are resident in host
   memory, so scalar reads are cheap.

   [run] is necessarily nonportable (it drives the scheduler), so the signature as a whole
   is not [@@ portable]. But [Result.t] mode-crosses contention and [Result.get] is
   portable, so a caller can read the result grid from its own parallel pass — e.g. to
   colour a shared image buffer across worker domains. *)
module type S_parallel = sig
  module Variable_idx : sig
    type t : value mod contended portable
  end

  module Prepared : sig
    type t : value mod contended portable

    val of_tree : Expr_tree.t -> t

    (* [None] if the program does not reference [name], so the caller can skip setting it. *)
    val lookup_variable : t -> string -> Variable_idx.t option
  end

  module Result : sig
    (* Mode-crosses contention so the result grid can be shared with worker domains for a
       parallel read-back. *)
    type t : value mod contended portable

    (* Row-major; valid for [0 <= x < width] and [0 <= y < height]. *)
    val get : t -> x:int -> y:int -> Value.t @@ portable
  end

  module Batch : sig
    type t

    val create : Prepared.t -> width:int -> height:int -> t

    (* A variable that is constant across the whole grid. *)
    val set_uniform : t -> var:Variable_idx.t -> Value.t -> unit

    (* A variable whose value at pixel [(x, y)] is [base +. dx *. x +. dy *. y]. *)
    val set_affine : t -> var:Variable_idx.t -> base:float -> dx:float -> dy:float -> unit

    (* A general per-pixel variable, supplied as a row-major buffer of raw {!Value.t} bits
       ([width * height] elements). *)
    val set_grid
      :  t
      -> var:Variable_idx.t
      -> (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
      -> unit

    (* Evaluate the whole grid and return a host-resident result. *)
    val run : t -> scheduler:Parallel_scheduler.t -> Result.t
  end
end

(* Builds an {!S_parallel} backend from any scalar {!S} backend using the scanline
   strategy: the grid is split into rows, each row is evaluated as an independent [S]
   batch of length [width] on a worker domain, and the per-pixel results are written back
   into a shared grid. This is the same approach the [neon] renderer drove inline before a
   grid-native backend existed. *)
module Make_parallel (B : S) : S_parallel = struct
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

    let run t ~scheduler =
      (* Snapshot the (immutable) binding list so the parallel closure captures it rather
         than the mutable [t], keeping the closure shareable across domains. *)
      let { prepared; width; height; bindings } = t in
      let result = Grid.create ~width ~height in
      Parallel_scheduler.parallel scheduler ~f:(fun par ->
        Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
          let b = B.Batch.create prepared ~len:width in
          List.iter bindings ~f:(apply_binding b ~width ~y);
          let row = B.Batch.run b in
          for x = 0 to width - 1 do
            Grid.set result ~x ~y (B.Result.get_output row ~px:x)
          done));
      result
    ;;
  end
end
