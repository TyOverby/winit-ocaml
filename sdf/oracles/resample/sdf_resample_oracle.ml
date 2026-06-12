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
     coordinates), so map world coordinates to grid indices before querying, and scale the
     resulting distance (measured in grid cells) back to world units. *)
  let sample { segments; inv_step_x; inv_step_y; offset_x; offset_y; dist_scale } ~x ~y =
    let open Float32_u in
    let x = (x * inv_step_x) + offset_x
    and y = (y * inv_step_y) + offset_y in
    Nearest_seg.query segments ~x ~y * dist_scale
  ;;

  (* The world -> grid-index map is affine and applied per-endpoint with the same float32
     arithmetic as [sample], so (after reordering for a negative step) the transformed box
     contains every transformed sample point. Likewise the final [dist_scale] multiply is
     monotone. Anything non-finite (an unbounded coordinate range would transform to an
     infinite grid box) falls back to the full range. *)
  let sample_range
    { segments; inv_step_x; inv_step_y; offset_x; offset_y; dist_scale }
    ~x
    ~y
    =
    if Interval.is_top x || Interval.is_top y
    then Interval.top
    else
      let open Float32_u in
      let #{ Interval.lo = xl; hi = xh } = x in
      let #{ Interval.lo = yl; hi = yh } = y in
      let gx0 = (xl * inv_step_x) + offset_x
      and gx1 = (xh * inv_step_x) + offset_x
      and gy0 = (yl * inv_step_y) + offset_y
      and gy1 = (yh * inv_step_y) + offset_y in
      let x_lo = min gx0 gx1
      and x_hi = max gx0 gx1
      and y_lo = min gy0 gy1
      and y_hi = max gy0 gy1 in
      if is_finite x_lo && is_finite x_hi && is_finite y_lo && is_finite y_hi
      then (
        let #{ Nearest_seg.Interval.lo; hi } =
          Nearest_seg.query_range segments ~x_lo ~y_lo ~x_hi ~y_hi
        in
        let a = lo * dist_scale
        and b = hi * dist_scale in
        Interval.create ~lo:(min a b) ~hi:(max a b))
      else Interval.top
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
  ~trace
  ~(exec : (module Executor.S with type Single.t = a and type Single.Variable_idx.t = b))
  ~oracles
  ~sample_region
  =
  let module E = (val exec) in
  let expand_by = 2 in
  let segments =
    let sample_region = Sample_region.expand sample_region ~by_:expand_by in
    let ~segments, ~length, ~stats:_ =
      Phase_trace.span trace "extract-contour" ~f:(fun () ->
        Sdf_contour.extract
          ~exec:(module E : Executor.S)
          ~par
          ~trace
          ~oracles
          ~region:sample_region
          tree)
    in
    (* Marching-squares output is a level-set contour, so the index may resolve
       range-query signs with the midpoint probe — without it, [sample_range] reports both
       signs for any box that overlaps the contour's extent in one axis, however far away,
       which defeats tile culling. *)
    Phase_trace.span
      trace
      "build-nearest-seg"
      ~args:[ "segments", Phase_trace.Arg.Int length ]
      ~f:(fun () -> Nearest_seg.build ~assume_level_set:true segments ~length)
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

let prepare tree ~par ~trace ~(exec : (module Executor.S)) ~oracles ~sample_region =
  make tree ~par ~trace ~exec:(Obj.magic Obj.magic_portable exec) ~oracles ~sample_region
;;
