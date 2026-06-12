open! Core

module Result = struct
  (* [values] holds the sample patches of active tiles, concatenated in row-major tile
     order; [offsets.(k)] is the k-th active tile's start. The record is wrapped in
     [Modes.Portended.t] so it can cross back out of the parallel context that builds it
     (the same pattern as the parallel evaluator's result grid). *)
  type inner =
    { sched : Tile_scheduler.t
    ; values : Value.Array.t
    ; offsets : int array
    }

  type t = inner Modes.Portended.t

  let[@inline] uncontended (t : t) =
    Stdlib.Obj.magic_uncontended t.Modes.Portended.portended
  ;;

  let scheduler t = (uncontended t).sched

  let iter t ~fill ~draw =
    let { sched; values; offsets } = uncontended t in
    let k = ref 0 in
    for ty = 0 to Tile_scheduler.tiles_y sched - 1 do
      for tx = 0 to Tile_scheduler.tiles_x sched - 1 do
        let x0 = Tile_scheduler.tile_x0 sched ~tx
        and y0 = Tile_scheduler.tile_y0 sched ~ty in
        let samples_x = Tile_scheduler.tile_samples_x sched ~tx
        and samples_y = Tile_scheduler.tile_samples_y sched ~ty in
        match Tile_scheduler.verdict sched ~tx ~ty with
        | Culled interval -> fill ~x0 ~y0 ~samples_x ~samples_y interval
        | Active ->
          let base = offsets.(!k) in
          incr k;
          draw ~x0 ~y0 ~samples_x ~samples_y ~get:(fun px ->
            Value.Array.get values (base + px))
      done
    done
  ;;
end

let run
  ~exec:(module E : Executor.S)
  ~par
  ~oracles
  ~region
  ?(tile_cells = 32)
  ~cull
  (tree : Expr_tree.t)
  =
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
        ~cull
    | Bool -> Tile_scheduler.all_active ~region ~tile_cells
  in
  let tiles_x = Tile_scheduler.tiles_x sched
  and tiles_y = Tile_scheduler.tiles_y sched in
  let num_active = Tile_scheduler.num_active sched in
  let active_tx = Array.create ~len:num_active 0 in
  let active_ty = Array.create ~len:num_active 0 in
  let offsets = Array.create ~len:num_active 0 in
  let total = ref 0 in
  let k = ref 0 in
  for ty = 0 to tiles_y - 1 do
    for tx = 0 to tiles_x - 1 do
      match Tile_scheduler.verdict sched ~tx ~ty with
      | Culled _ -> ()
      | Active ->
        active_tx.(!k) <- tx;
        active_ty.(!k) <- ty;
        offsets.(!k) <- !total;
        total
        := !total
           + (Tile_scheduler.tile_samples_x sched ~tx
              * Tile_scheduler.tile_samples_y sched ~ty);
        incr k
    done
  done;
  let values = Value.Array.create ~len:!total in
  (* [Value.Array.t] is abstract, so unlike the plain int arrays it doesn't mode-cross on
     its own; the [Portended] wrapper carries it into the parallel tasks (each task writes
     a disjoint slice). *)
  let values_portended =
    { Modes.Portended.portended = Stdlib.Obj.magic_portable values }
  in
  let prepared = E.Batch.Prepared.of_tree tree in
  Parallel.for_ par ~start:0 ~stop:num_active ~f:(fun _par k ->
    let active_tx = Stdlib.Obj.magic_uncontended active_tx in
    let active_ty = Stdlib.Obj.magic_uncontended active_ty in
    let offsets = Stdlib.Obj.magic_uncontended offsets in
    let values =
      Stdlib.Obj.magic_uncontended values_portended.Modes.Portended.portended
    in
    let tx = active_tx.(k)
    and ty = active_ty.(k) in
    let x0 = Tile_scheduler.tile_x0 sched ~tx
    and y0 = Tile_scheduler.tile_y0 sched ~ty in
    let sx = Tile_scheduler.tile_samples_x sched ~tx
    and sy = Tile_scheduler.tile_samples_y sched ~ty in
    let batch =
      E.Batch.Batch.create_sub prepared region ~x0 ~y0 ~samples_x:sx ~samples_y:sy
    in
    let result = E.Batch.Batch.run batch ~oracles in
    let base = offsets.(k) in
    for i = 0 to (sx * sy) - 1 do
      Value.Array.set values (base + i) (E.Batch.Result.get_output result ~px:i)
    done);
  { Modes.Portended.portended =
      Stdlib.Obj.magic_portable { Result.sched; values; offsets }
  }
;;
