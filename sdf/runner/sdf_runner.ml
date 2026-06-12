open! Core
open Sdf

module Contour_result = struct
  type t =
    { segments : float32# array
    ; length : int
    ; stats : Sdf_contour.Stats.t
    }
end

type inner =
  { mutable source : string
  ; mutable tree : Expr_tree.t
  ; mutable contour : (Sample_region.t * Contour_result.t) option
  ; mutable tiled : (Sample_region.t * Tile_scheduler.Cull.t * Tiled_eval.Result.t) option
  ; mutable oracles : Oracle.Prepared.t Map.M(Oracle.Prepared.Key).t
  }

type t =
  { mutable dirty : bool
  ; mutable last_run : inner option
  ; mutable oracles : (string * (module Oracle.S)) list portable
  ; scheduler : Parallel_scheduler.t
  }

let create () =
  { dirty = true
  ; last_run = None
  ; oracles = { portable = [] }
  ; scheduler = Parallel_scheduler.create ()
  }
;;

let oracles t : (string * (module Oracle.S)) list = t.oracles.portable

let add_oracle t ~name oracle =
  t.dirty <- true;
  t.last_run <- None;
  t.oracles <- { portable = (name, oracle) :: t.oracles.portable }
;;

let compile_sdf_from_source ~trace ~filename ~oracles ~source =
  Phase_trace.span trace "compile" ~f:(fun () ->
    let oracle_names = List.map ~f:fst oracles |> String.Set.of_list in
    Phase_trace.span trace "neo-compile" ~f:(fun () ->
      Neo.compile ~oracle_names ~filename source |> Or_error.ok_exn))
;;

let update_source_code t ~trace ~filename source =
  match t.last_run with
  | None ->
    t.dirty <- true;
    let tree =
      compile_sdf_from_source ~trace ~filename ~oracles:t.oracles.portable ~source
    in
    let inner =
      { source
      ; tree
      ; contour = None
      ; tiled = None
      ; oracles = Map.empty (module Oracle.Prepared.Key)
      }
    in
    t.last_run <- Some inner;
    inner
  | Some last_run ->
    if String.equal last_run.source source
    then last_run
    else (
      last_run.source <- source;
      let tree =
        compile_sdf_from_source ~trace ~filename ~oracles:t.oracles.portable ~source
      in
      if Expr_tree.equal last_run.tree tree
      then last_run
      else (
        last_run.tree <- tree;
        t.dirty <- true;
        last_run))
;;

(* All cached outputs are derived from the same compiled tree, so a recompile invalidates
   every one of them, even though the caller is about to refresh only one kind. *)
let invalidate_caches_if_dirty t =
  match t.dirty, t.last_run with
  | true, Some last_run ->
    last_run.contour <- None;
    last_run.tiled <- None
  | _ -> ()
;;

(* Prepare every oracle the tree references, in dependency order, reusing oracles cached
   for the same region. Returns the prepared map plus the region-keyed map used for the
   next frame's cache. Runs inside a parallel context; [trace] is the lane writer of the
   surrounding [Phase_trace.with_fork]. *)
let prepare_oracles ~trace ~oracle_impls ~tree ~prev_oracles ~region ~(par @ local) =
  let result =
    Sdf.Oracle_dependencies.extract_deps tree
    (* perf: don't do this join, instead process all independent oracles in parallel *)
    |> List.join
    |> List.fold
         ~init:(Map.empty (module Oracle.Key), Map.empty (module Oracle.Prepared.Key))
         ~f:(fun (prepared, prepared_with_region) ((key, tree) as oracle_key) ->
           let p =
             match Map.find prev_oracles (region, oracle_key) with
             | Some oracle -> oracle
             | None ->
               Phase_trace.span trace ("oracle:" ^ key) ~f:(fun () ->
                 let module M =
                   (val (List.Assoc.find_exn
                           (Obj.magic Obj.magic oracle_impls)
                           ~equal:String.equal
                           key
                         : (module Oracle.S)))
                 in
                 M.create tree
                 |> M.prepare ~par ~trace ~oracles:prepared ~sample_region:region)
           in
           ( Map.set prepared ~key:oracle_key ~data:p
           , Map.set prepared_with_region ~key:(region, oracle_key) ~data:p ))
  in
  result
;;

let run_contour (t @ nonportable) ?(trace = Phase_trace.null ()) ~region ~filename source =
  Phase_trace.span trace "run-contour" ~f:(fun () ->
    let last_run = update_source_code t ~trace ~filename source in
    invalidate_caches_if_dirty t;
    let { Contour_result.segments; length; stats } =
      match t.dirty, last_run.contour with
      | false, Some (cached_region, result) when Sample_region.equal cached_region region
        -> result
      | _ ->
        let { tree; oracles = prev_oracles; _ } = last_run in
        let oracle_impls = oracles t in
        let fk = Phase_trace.fork trace in
        let result, oracles_with_region =
          Parallel_scheduler.parallel t.scheduler ~f:(fun par ->
            let traced =
              Phase_trace.with_fork fk ~f:(fun trace ->
                let oracles, oracles_with_region =
                  Phase_trace.span trace "prepare-oracles" ~f:(fun () ->
                    prepare_oracles ~trace ~oracle_impls ~tree ~prev_oracles ~region ~par)
                in
                let ~segments, ~length, ~stats =
                  Phase_trace.span trace "extract-contour" ~f:(fun () ->
                    Sdf_contour.extract ~par ~trace ~oracles ~region tree)
                in
                ( { Modes.Portended.portended =
                      Stdlib.Obj.magic_portable { Contour_result.segments; length; stats }
                  }
                , oracles_with_region ))
            in
            traced)
        in
        let result = Stdlib.Obj.magic_uncontended result.Modes.Portended.portended in
        last_run.oracles <- oracles_with_region;
        last_run.contour <- Some (region, result);
        t.dirty <- false;
        result
    in
    ~segments, ~length, ~stats)
;;

let run_tiled
  (t @ nonportable)
  ?(trace = Phase_trace.null ())
  ~region
  ~filename
  source
  ~cull
  =
  Phase_trace.span trace "run-tiled" ~f:(fun () ->
    let last_run = update_source_code t ~trace ~filename source in
    invalidate_caches_if_dirty t;
    match t.dirty, last_run.tiled with
    | false, Some (cached_region, cached_cull, result)
      when Sample_region.equal cached_region region
           && Tile_scheduler.Cull.equal cached_cull cull -> result
    | _ ->
      let { tree; oracles = prev_oracles; _ } = last_run in
      let oracle_impls = oracles t in
      let fk = Phase_trace.fork trace in
      let result, oracles_with_region =
        Parallel_scheduler.parallel t.scheduler ~f:(fun par ->
          let traced =
            Phase_trace.with_fork fk ~f:(fun trace ->
              let oracles, oracles_with_region =
                Phase_trace.span trace "prepare-oracles" ~f:(fun () ->
                  prepare_oracles ~trace ~oracle_impls ~tree ~prev_oracles ~region ~par)
              in
              let result =
                Phase_trace.span trace "tiled-eval" ~f:(fun () ->
                  Tiled_eval.run ~par ~trace ~oracles ~region ~cull tree)
              in
              result, oracles_with_region)
          in
          traced)
      in
      last_run.oracles <- oracles_with_region;
      last_run.tiled <- Some (region, cull, result);
      t.dirty <- false;
      result)
;;
