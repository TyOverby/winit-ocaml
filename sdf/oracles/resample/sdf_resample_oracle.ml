open! Core
open Sdf

type t = Expr_tree.t [@@deriving equal, compare, sexp_of]

include functor Comparator.Make [@mode portable]

module Prepared = struct
  type t : value mod contended portable =
    { segments : Nearest_seg.t
    ; offset_x : float32#
    ; offset_y : float32#
    }

  let sample { segments; offset_x; offset_y } ~x ~y =
    let open Float32_u in
    let x = x + offset_x
    and y = y + offset_y in
    Nearest_seg.query segments ~x ~y
  ;;
end

let create = function
  | [ tree ] -> tree
  | _ -> failwith "expected exactly one tree"
;;

let make
  (type (a : value mod contended portable) (b : value mod contended portable))
  tree
  ~par
  ~(exec : (module Executor.S with type Single.t = a and type Single.Variable_idx.t = b))
  ~oracles
  ~sample_region
  =
  let module E = (val exec) in
  let expand_by = 2 in
  let segments =
    let sample_region = Sample_region.expand sample_region ~by_:expand_by in
    let prepared = E.Parallel.Prepared.of_tree tree in
    let batch = E.Parallel.Batch.create prepared sample_region in
    let result = E.Parallel.Batch.run batch ~par ~oracles in
    let width, height = sample_region.samples_x, sample_region.samples_y in
    let grid = Array.create ~len:(width * height) #0.0s in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        grid.((y * width) + x) <- Sdf.Value.to_float (E.Parallel.Result.get result ~x ~y)
      done
    done;
    let march_output : float32# array =
      Array.create ~len:(width * height * 2 * 4) #0.0s
    in
    let length = March.run grid march_output width height in
    Nearest_seg.build march_output ~length
  in
  let open Float32_u in
  let offset_x = Sample_region.step_x sample_region * Float32_u.of_int expand_by
  and offset_y = Sample_region.step_y sample_region * Float32_u.of_int expand_by in
  Oracle.Prepared.wrap (module Prepared) { Prepared.segments; offset_x; offset_y }
;;

let prepare tree ~par ~(exec : (module Executor.S)) ~oracles ~sample_region =
  make tree ~par ~exec:(Obj.magic Obj.magic_portable exec) ~oracles ~sample_region
;;
