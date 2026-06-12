open! Core

module Cull = struct
  type t =
    | Nothing
    | No_contour
    | Constant_outside of
        { below : float
        ; above : float
        }
  [@@deriving sexp_of, equal]

  let culls t (interval : Interval.t) =
    if Interval.is_top interval
    then false
    else (
      let #{ Interval.lo; hi } = interval in
      let open Float32_u.O in
      match t with
      | Nothing -> false
      | No_contour -> lo > #0.s || hi <= #0.s
      | Constant_outside { below; above } ->
        hi <= Float32_u.of_float below || lo > Float32_u.of_float above)
  ;;
end

module Verdict = struct
  type t =
    | Culled of Interval.t
    | Active
end

(* Verdicts are stored as one (lo, hi) float pair per tile, row-major. A NaN [lo] encodes
   [Active]; culled intervals are never [top] (see [Cull.culls]), so their [lo] is never
   NaN. Plain [float iarray]s keep the whole record immutable so it can cross into
   parallel tile-processing tasks. *)
type t =
  { tiles_x : int
  ; tiles_y : int
  ; tile_cells : int
  ; samples_x : int
  ; samples_y : int
  ; lo : float iarray
  ; hi : float iarray
  }

let tiles_x t = t.tiles_x
let tiles_y t = t.tiles_y
let tile_cells t = t.tile_cells
let num_tiles t = t.tiles_x * t.tiles_y

let verdict t ~tx ~ty : Verdict.t =
  let i = (ty * t.tiles_x) + tx in
  let lo = Iarray.get t.lo i in
  if Float.is_nan lo
  then Active
  else
    Culled
      (Interval.create
         ~lo:(Float32_u.of_float lo)
         ~hi:(Float32_u.of_float (Iarray.get t.hi i)))
;;

let tile_x0 t ~tx = tx * t.tile_cells
let tile_y0 t ~ty = ty * t.tile_cells

(* Sample count including the boundary column shared with the next tile: an interior tile
   covers [tile_cells + 1] samples; the last tile is clipped to the grid (and covers a
   single sample only in the degenerate one-sample-wide grid). *)
let tile_samples_x t ~tx =
  Int.min ((tx + 1) * t.tile_cells) (t.samples_x - 1) - tile_x0 t ~tx + 1
;;

let tile_samples_y t ~ty =
  Int.min ((ty + 1) * t.tile_cells) (t.samples_y - 1) - tile_y0 t ~ty + 1
;;

let num_active t =
  let count = ref 0 in
  for i = 0 to num_tiles t - 1 do
    if Float.is_nan (Iarray.get t.lo i) then incr count
  done;
  !count
;;

let to_string_hum t =
  let buf = Buffer.create ((t.tiles_x + 1) * t.tiles_y) in
  for ty = 0 to t.tiles_y - 1 do
    for tx = 0 to t.tiles_x - 1 do
      let c =
        match verdict t ~tx ~ty with
        | Active -> '.'
        | Culled #{ Interval.lo; hi } ->
          if Float32_u.O.(lo > #0.s)
          then '+'
          else if Float32_u.O.(hi <= #0.s)
          then '-'
          else 'o'
      in
      Buffer.add_char buf c
    done;
    if ty < t.tiles_y - 1 then Buffer.add_char buf '\n'
  done;
  Buffer.contents buf
;;

(* ceil ((samples - 1) / tile_cells) tiles cover the cell grid; a one-sample-wide axis
   still gets one (degenerate, zero-cell) tile so every sample belongs to some tile. *)
let tile_count ~samples ~tile_cells =
  if samples <= 0 then 0 else Int.max 1 ((samples - 1 + tile_cells - 1) / tile_cells)
;;

let make_grid ~(region : Sample_region.t) ~tile_cells ~f =
  if tile_cells < 1
  then raise_s [%message "Tile_scheduler: tile_cells must be >= 1" (tile_cells : int)];
  let samples_x = region.samples_x
  and samples_y = region.samples_y in
  let tiles_x = tile_count ~samples:samples_x ~tile_cells
  and tiles_y = tile_count ~samples:samples_y ~tile_cells in
  let n = tiles_x * tiles_y in
  let lo = Array.create ~len:n Float.nan in
  let hi = Array.create ~len:n Float.nan in
  f ~tiles_x ~tiles_y ~lo ~hi;
  { tiles_x
  ; tiles_y
  ; tile_cells
  ; samples_x
  ; samples_y
  ; lo = Iarray.unsafe_of_array__promise_no_mutation lo
  ; hi = Iarray.unsafe_of_array__promise_no_mutation hi
  }
;;

let all_active ~region ~tile_cells =
  make_grid ~region ~tile_cells ~f:(fun ~tiles_x:_ ~tiles_y:_ ~lo:_ ~hi:_ -> ())
;;

let schedule range ~vars ~oracles ~region ~tile_cells ~cull =
  (* [Nothing] never culls, so skip the subdivision (it would interval-evaluate every
     rectangle of the recursion tree just to mark everything active). *)
  match (cull : Cull.t) with
  | Nothing -> all_active ~region ~tile_cells
  | No_contour | Constant_outside _ ->
    (* [vars] and [oracles] are invariant across the whole subdivision recursion — only
       the coordinate box changes — so resolve them (and allocate the register buffers)
       once and share the context across every [descend] evaluation. *)
    let context = Expr_graph_range_eval.Context.create range ~vars ~oracles in
    make_grid ~region ~tile_cells ~f:(fun ~tiles_x ~tiles_y ~lo ~hi ->
      let last_sample_x = region.samples_x - 1
      and last_sample_y = region.samples_y - 1 in
      (* Inclusive sample-index extent of the tile rectangle [t0, t1). The world box hulls
       the two extreme sample coordinates; [Sample_region.x_at] is monotone in the index
       (a monotone exact function composed with monotone float rounding), so the box
       contains every sample coordinate in between. *)
      let sample_extent ~t0 ~t1 ~last =
        let s0 = t0 * tile_cells in
        let s1 = Int.min (t1 * tile_cells) last in
        s0, Int.max s1 s0
      in
      let box_x ~tx0 ~tx1 =
        let s0, s1 = sample_extent ~t0:tx0 ~t1:tx1 ~last:last_sample_x in
        Interval.create
          ~lo:(Sample_region.x_at region s0)
          ~hi:(Sample_region.x_at region s1)
      in
      let box_y ~ty0 ~ty1 =
        let s0, s1 = sample_extent ~t0:ty0 ~t1:ty1 ~last:last_sample_y in
        Interval.create
          ~lo:(Sample_region.y_at region s0)
          ~hi:(Sample_region.y_at region s1)
      in
      let fill ~tx0 ~tx1 ~ty0 ~ty1 (interval : Interval.t) =
        let #{ Interval.lo = ilo; hi = ihi } = interval in
        for ty = ty0 to ty1 - 1 do
          for tx = tx0 to tx1 - 1 do
            let i = (ty * tiles_x) + tx in
            lo.(i) <- Float32_u.to_float ilo;
            hi.(i) <- Float32_u.to_float ihi
          done
        done
      in
      let rec descend ~tx0 ~tx1 ~ty0 ~ty1 =
        let bound =
          Expr_graph_range_eval.run_with_context
            context
            ~x:(box_x ~tx0 ~tx1)
            ~y:(box_y ~ty0 ~ty1)
        in
        if Cull.culls cull bound
        then fill ~tx0 ~tx1 ~ty0 ~ty1 bound
        else (
          let w = tx1 - tx0
          and h = ty1 - ty0 in
          if w = 1 && h = 1
          then (* stays NaN = Active *) ()
          else if w >= h
          then (
            let mid = tx0 + (w / 2) in
            descend ~tx0 ~tx1:mid ~ty0 ~ty1;
            descend ~tx0:mid ~tx1 ~ty0 ~ty1)
          else (
            let mid = ty0 + (h / 2) in
            descend ~tx0 ~tx1 ~ty0 ~ty1:mid;
            descend ~tx0 ~tx1 ~ty0:mid ~ty1))
      in
      if tiles_x > 0 && tiles_y > 0 then descend ~tx0:0 ~tx1:tiles_x ~ty0:0 ~ty1:tiles_y)
;;
