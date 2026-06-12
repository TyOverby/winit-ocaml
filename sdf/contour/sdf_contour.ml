open! Core
open Sdf

module Stats = struct
  type t =
    { tiles_total : int
    ; tiles_culled : int
    ; samples_evaluated : int
    }
  [@@deriving sexp_of]
end

let extract
  ~par
  ?(trace = Phase_trace.null ())
  ~oracles
  ~region
  ?(tile_cells = 32)
  (tree : Expr_tree.t)
  =
  (* [extract] runs on a parallel fiber (the [Parallel_scheduler.parallel] closure);
     pre-grow its stack before the interval scheduler starts juggling unboxed float32#
     bounds. See [Fiber_stack]. *)
  Fiber_stack.pre_grow ();
  let sched =
    Phase_trace.span trace "tile-schedule" ~f:(fun () ->
      let sched =
        match tree.type_ with
        | Float ->
          let range = Expr_graph_range_eval.of_tree tree in
          Tile_scheduler.schedule
            range
            ~vars:(Map.empty (module Expr_graph_range_eval.Variable_idx))
            ~oracles
            ~region
            ~tile_cells
            ~cull:No_contour
        | Bool -> Tile_scheduler.all_active ~region ~tile_cells
      in
      Phase_trace.add_args
        trace
        [ ( "tiles_total"
          , Phase_trace.Arg.Int
              (Tile_scheduler.tiles_x sched * Tile_scheduler.tiles_y sched) )
        ; "tiles_active", Phase_trace.Arg.Int (Tile_scheduler.num_active sched)
        ];
      sched)
  in
  let tiles_x = Tile_scheduler.tiles_x sched in
  let tiles_y = Tile_scheduler.tiles_y sched in
  let tiles_total = tiles_x * tiles_y in
  let num_active = Tile_scheduler.num_active sched in
  let active_tx = Array.create ~len:num_active 0 in
  let active_ty = Array.create ~len:num_active 0 in
  let samples_evaluated = ref 0 in
  let next = ref 0 in
  for ty = 0 to tiles_y - 1 do
    for tx = 0 to tiles_x - 1 do
      match Tile_scheduler.verdict sched ~tx ~ty with
      | Culled _ -> ()
      | Active ->
        active_tx.(!next) <- tx;
        active_ty.(!next) <- ty;
        incr next;
        samples_evaluated
        := !samples_evaluated
           + (Tile_scheduler.tile_samples_x sched ~tx
              * Tile_scheduler.tile_samples_y sched ~ty)
    done
  done;
  let prepared =
    Phase_trace.span trace "batch-prepare" ~f:(fun () ->
      Expr_graph_batch_eval.Prepared.of_tree tree)
  in
  (* Every active tile gets a fixed-size slot in [staging] (sized for the 2-segments-per-
     cell worst case over a full tile's sample patch), written by its own parallel task;
     [counts] records how many segments each tile actually emitted. Both arrays hold only
     unboxed/immediate values and each task writes a disjoint slice, so sharing them
     across domains with [magic_uncontended] is the same pattern the row-parallel grid
     evaluator uses. *)
  let slot_floats = (tile_cells + 1) * (tile_cells + 1) * 2 * 4 in
  let staging : float32# array = Array.create ~len:(num_active * slot_floats) #0.0s in
  let counts = Array.create ~len:num_active 0 in
  Phase_trace.span trace "march-tiles" ~f:(fun () ->
    let fk = Phase_trace.fork trace in
    Parallel.for_ par ~start:0 ~stop:num_active ~f:(fun _par k ->
      Fiber_stack.pre_grow ();
      Phase_trace.with_fork fk ~name:"tile" ~f:(fun _trace ->
        let active_tx = Stdlib.Obj.magic_uncontended active_tx in
        let active_ty = Stdlib.Obj.magic_uncontended active_ty in
        let staging = Stdlib.Obj.magic_uncontended staging in
        let counts = Stdlib.Obj.magic_uncontended counts in
        let tx = active_tx.(k)
        and ty = active_ty.(k) in
        let x0 = Tile_scheduler.tile_x0 sched ~tx
        and y0 = Tile_scheduler.tile_y0 sched ~ty in
        let sx = Tile_scheduler.tile_samples_x sched ~tx
        and sy = Tile_scheduler.tile_samples_y sched ~ty in
        let batch =
          Expr_graph_batch_eval.Batch.create_sub
            prepared
            region
            ~x0
            ~y0
            ~samples_x:sx
            ~samples_y:sy
        in
        let result = Expr_graph_batch_eval.Batch.run batch ~oracles in
        let patch : float32# array = Array.create ~len:(sx * sy) #0.0s in
        for i = 0 to (sx * sy) - 1 do
          patch.(i)
          <- Value.to_float (Expr_graph_batch_eval.Result.get_output result ~px:i)
        done;
        let scratch : float32# array = Array.create ~len:(sx * sy * 2 * 4) #0.0s in
        let count = March.run_offset patch scratch sx sy ~ox:x0 ~oy:y0 in
        let base = k * slot_floats in
        for i = 0 to (count * 4) - 1 do
          staging.(base + i) <- scratch.(i)
        done;
        counts.(k) <- count)));
  let total = Array.fold counts ~init:0 ~f:( + ) in
  let segments : float32# array = Array.create ~len:(total * 4) #0.0s in
  Phase_trace.span trace "stitch-segments" ~f:(fun () ->
    let pos = ref 0 in
    for k = 0 to num_active - 1 do
      let base = k * slot_floats in
      for i = 0 to (counts.(k) * 4) - 1 do
        segments.(!pos) <- staging.(base + i);
        incr pos
      done
    done);
  let stats =
    { Stats.tiles_total
    ; tiles_culled = tiles_total - num_active
    ; samples_evaluated = !samples_evaluated
    }
  in
  ~segments, ~length:total, ~stats
;;
