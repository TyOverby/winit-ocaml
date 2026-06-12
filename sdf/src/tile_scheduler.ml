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

let make_grid ~(region : Sample_region.t) ~tile_cells ~(f @ local) =
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

(* The per-task state of the subdivision: a prepared {!Expr_graph_range_eval.Context}.
   [vars] and [oracles] are invariant across the whole subdivision recursion — only the
   coordinate box changes — so [create] resolves them (and allocates the lo/hi register
   buffers) once, and every [eval] is an allocation-free [run_with_context]. A context
   holds mutable scratch buffers, so it must not be shared across concurrent tasks: each
   parallel task creates its own state at its top and reuses it for every rectangle that
   task evaluates serially. *)
module Task_state = struct
  type t = { context : Expr_graph_range_eval.Context.t }

  let create range ~vars ~oracles =
    { context = Expr_graph_range_eval.Context.create range ~vars ~oracles }
  ;;

  let eval t ~x ~y = Expr_graph_range_eval.run_with_context t.context ~x ~y
end

(* Inclusive sample-index extent of the tile rectangle [t0, t1). The world box hulls the
   two extreme sample coordinates; [Sample_region.x_at] is monotone in the index (a
   monotone exact function composed with monotone float rounding), so the box contains
   every sample coordinate in between. *)
let sample_extent ~tile_cells ~t0 ~t1 ~last =
  let s0 = t0 * tile_cells in
  let s1 = Int.min (t1 * tile_cells) last in
  s0, Int.max s1 s0
;;

let box_x ~(region : Sample_region.t) ~tile_cells ~tx0 ~tx1 =
  let s0, s1 = sample_extent ~tile_cells ~t0:tx0 ~t1:tx1 ~last:(region.samples_x - 1) in
  Interval.create ~lo:(Sample_region.x_at region s0) ~hi:(Sample_region.x_at region s1)
;;

let box_y ~(region : Sample_region.t) ~tile_cells ~ty0 ~ty1 =
  let s0, s1 = sample_extent ~tile_cells ~t0:ty0 ~t1:ty1 ~last:(region.samples_y - 1) in
  Interval.create ~lo:(Sample_region.y_at region s0) ~hi:(Sample_region.y_at region s1)
;;

let fill ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0 ~ty1 (interval : Interval.t) =
  let #{ Interval.lo = ilo; hi = ihi } = interval in
  for ty = ty0 to ty1 - 1 do
    for tx = tx0 to tx1 - 1 do
      let i = (ty * tiles_x) + tx in
      lo.(i) <- Float32_u.to_float ilo;
      hi.(i) <- Float32_u.to_float ihi
    done
  done
;;

(* The serial subdivision: interval-evaluate the rectangle [tx0, tx1) x [ty0, ty1); fill
   it if the bound culls, otherwise split the longer axis and recurse (a single un-culled
   tile stays Active). [schedule] runs the levels of this same recursion above the grain
   as parallel tasks; the split choices below must stay in lockstep with the parallel
   driver so both evaluate exactly the same rectangles. *)
let rec descend state ~region ~tile_cells ~cull ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0 ~ty1 =
  let bound =
    Task_state.eval
      state
      ~x:(box_x ~region ~tile_cells ~tx0 ~tx1)
      ~y:(box_y ~region ~tile_cells ~ty0 ~ty1)
  in
  if Cull.culls cull bound
  then fill ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0 ~ty1 bound
  else (
    let w = tx1 - tx0
    and h = ty1 - ty0 in
    if w = 1 && h = 1
    then (* stays NaN = Active *) ()
    else if w >= h
    then (
      let mid = tx0 + (w / 2) in
      descend state ~region ~tile_cells ~cull ~tiles_x ~lo ~hi ~tx0 ~tx1:mid ~ty0 ~ty1;
      descend state ~region ~tile_cells ~cull ~tiles_x ~lo ~hi ~tx0:mid ~tx1 ~ty0 ~ty1)
    else (
      let mid = ty0 + (h / 2) in
      descend state ~region ~tile_cells ~cull ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0 ~ty1:mid;
      descend state ~region ~tile_cells ~cull ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0:mid ~ty1))
;;

(* One node of the subdivision run as its own parallel task: rectangles of more than
   [grain] tiles interval-evaluate themselves and, when they must split, fork their two
   halves as parallel tasks (they are independent: they write disjoint tile-index ranges
   of [lo]/[hi]); rectangles at or below the grain finish with the serial [descend] —
   without a grain the deep levels would drown in per-task scheduling overhead. [grain]
   targets ~128 leaf tasks on a square grid while never going below 4 tiles per leaf
   (measured on boxes.neo's 32x32 tile grid: coarser grains leave the deep levels too
   serial, finer ones pay more in task overhead than they recover).

   A child can only be evaluated after its parent's verdict, so the fork tree mirrors the
   recursion tree exactly: the same rectangles are evaluated, with the same split choices
   (which must stay in lockstep with [descend]); only the order changes.

   [inputs] is the evaluator inputs plus the verdict arrays; they don't all mode-cross on
   their own, so the [Portended] wrapper carries them into the tasks (the same pattern as
   the result grid in [Tiled_eval]). The maps are immutable and only ever read; [lo]/[hi]
   are written at disjoint indices, the same pattern as the tile arrays in [Tiled_eval]. *)
let rec descend_par
  (par @ local)
  inputs
  ~region
  ~tile_cells
  ~cull
  ~tiles_x
  ~grain
  ~tx0
  ~tx1
  ~ty0
  ~ty1
  =
  (* This may be the first thing to run on a fresh fiber; pre-grow its stack before any
     unboxed float32# bounds are in flight. See [Fiber_stack]. *)
  Fiber_stack.pre_grow ();
  (* Every task gets its own interval-evaluation state: the [Task_state] context holds
     mutable scratch buffers, so it is created here, inside the task, from the portable
     inputs — never shared across concurrent tasks. *)
  let range, vars, oracles, lo, hi =
    Stdlib.Obj.magic_uncontended inputs.Modes.Portended.portended
  in
  let state = Task_state.create range ~vars ~oracles in
  let w = tx1 - tx0
  and h = ty1 - ty0 in
  if w * h <= grain
  then descend state ~region ~tile_cells ~cull ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0 ~ty1
  else (
    let bound =
      Task_state.eval
        state
        ~x:(box_x ~region ~tile_cells ~tx0 ~tx1)
        ~y:(box_y ~region ~tile_cells ~ty0 ~ty1)
    in
    if Cull.culls cull bound
    then fill ~tiles_x ~lo ~hi ~tx0 ~tx1 ~ty0 ~ty1 bound
    else if (* w * h > grain >= 1, so the rectangle is splittable; same split choice as
               [descend]. *)
            w >= h
    then (
      let mid = tx0 + (w / 2) in
      let #((), ()) =
        Parallel.fork_join2
          par
          (fun par ->
            descend_par
              par
              inputs
              ~region
              ~tile_cells
              ~cull
              ~tiles_x
              ~grain
              ~tx0
              ~tx1:mid
              ~ty0
              ~ty1)
          (fun par ->
            descend_par
              par
              inputs
              ~region
              ~tile_cells
              ~cull
              ~tiles_x
              ~grain
              ~tx0:mid
              ~tx1
              ~ty0
              ~ty1)
      in
      ())
    else (
      let mid = ty0 + (h / 2) in
      let #((), ()) =
        Parallel.fork_join2
          par
          (fun par ->
            descend_par
              par
              inputs
              ~region
              ~tile_cells
              ~cull
              ~tiles_x
              ~grain
              ~tx0
              ~tx1
              ~ty0
              ~ty1:mid)
          (fun par ->
            descend_par
              par
              inputs
              ~region
              ~tile_cells
              ~cull
              ~tiles_x
              ~grain
              ~tx0
              ~tx1
              ~ty0:mid
              ~ty1)
      in
      ()))
;;

let schedule range ~(par @ local) ~vars ~oracles ~region ~tile_cells ~cull =
  (* [Nothing] never culls, so skip the subdivision (it would interval-evaluate every
     rectangle of the recursion tree just to mark everything active). *)
  match (cull : Cull.t) with
  | Nothing -> all_active ~region ~tile_cells
  | No_contour | Constant_outside _ ->
    (* Bound (not tail-called) so the closure below may be a local allocation (it captures
       the local [par]). *)
    let t =
      make_grid ~region ~tile_cells ~f:(fun ~tiles_x ~tiles_y ~lo ~hi ->
        if tiles_x > 0 && tiles_y > 0
        then (
          let grain = Int.max 4 (tiles_x * tiles_y / 128) in
          let inputs =
            { Modes.Portended.portended =
                Stdlib.Obj.magic_portable (range, vars, oracles, lo, hi)
            }
          in
          descend_par
            par
            inputs
            ~region
            ~tile_cells
            ~cull
            ~tiles_x
            ~grain
            ~tx0:0
            ~tx1:tiles_x
            ~ty0:0
            ~ty1:tiles_y))
    in
    t
;;
