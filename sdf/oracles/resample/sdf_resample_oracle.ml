open! Core
open Sdf

type t = Expr_tree.t [@@deriving equal, compare, sexp_of]

include functor Comparator.Make [@mode portable]

module Prepared = struct
  type t : value mod contended portable =
    { segments : Nearest_seg.t
    ; inv_step_x : float32#
    ; inv_step_y : float32#
    ; offset_x : float32#
    ; offset_y : float32#
    ; dist_scale : float32#
    }

  (* The segments live in the expanded grid's index space (March emits cell-index
     coordinates), so map world coordinates to grid indices before querying, and scale
     the resulting distance (measured in grid cells) back to world units. *)
  let sample { segments; inv_step_x; inv_step_y; offset_x; offset_y; dist_scale } ~x ~y =
    let open Float32_u in
    let x = (x * inv_step_x) + offset_x
    and y = (y * inv_step_y) + offset_y in
    Nearest_seg.query segments ~x ~y * dist_scale
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
  let step_x = Sample_region.step_x sample_region
  and step_y = Sample_region.step_y sample_region in
  (* World x corresponds to grid index (x - start_x) / step_x + expand_by (the expanded
     grid adds [expand_by] rows/columns before the region start). Index-space distances
     are in units of [step_x]; scaling by it assumes square-ish samples. *)
  Oracle.Prepared.wrap
    (module Prepared)
    { Prepared.segments
    ; inv_step_x = #1.s / step_x
    ; inv_step_y = #1.s / step_y
    ; offset_x = of_int expand_by - (sample_region.Sample_region.start_x / step_x)
    ; offset_y = of_int expand_by - (sample_region.Sample_region.start_y / step_y)
    ; dist_scale = step_x
    }
;;

let prepare tree ~par ~(exec : (module Executor.S)) ~oracles ~sample_region =
  make tree ~par ~exec:(Obj.magic Obj.magic_portable exec) ~oracles ~sample_region
;;
