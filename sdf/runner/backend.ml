open! Core
open Sdf

module type S = sig
  module E : Executor.S

  type t

  val create : unit -> t

  val add_oracle : t -> name:string -> (module Oracle.S) @ portable  -> unit

  val run
    :  t
    -> region:Sample_region.t
    -> filename:string
    -> string
    -> E.Parallel.Result.t
end

module Make (E : Executor.S @ portable) : S with module E = E = struct
  module E = E 
  type inner =
    { mutable source : string
    ; mutable tree : Expr_tree.t
    ; mutable region : Sample_region.t
    ; mutable prepared : E.Parallel.Prepared.t
    ; mutable output : E.Parallel.Result.t option
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

  let compile_sdf_from_source ~filename ~oracles ~source =
    let oracle_names = List.map ~f:fst oracles |> String.Set.of_list in
    let tree = Neo.compile ~oracle_names ~filename source |> Or_error.ok_exn in
    let prepared = E.Parallel.Prepared.of_tree tree in
    ~tree, ~prepared
  ;;

  let update_source_code t ~filename source =
    match t.last_run with
    | None ->
      t.dirty <- true;
      let ~tree, ~prepared =
        compile_sdf_from_source ~filename ~oracles:t.oracles.portable ~source
      in
      let inner =
        { source
        ; region = Sample_region.point ~x:#0.0s ~y:#0.0s
        ; tree
        ; prepared
        ; output = None
        }
      in
      t.last_run <- Some inner;
      inner
    | Some last_run ->
      if String.equal last_run.source source
      then last_run
      else (
        last_run.source <- source;
        let ~tree, ~prepared =
          compile_sdf_from_source ~filename ~oracles:t.oracles.portable ~source
        in
        if Expr_tree.equal last_run.tree tree
        then last_run
        else (
          last_run.tree <- tree;
          last_run.prepared <- prepared;
          t.dirty <- true;
          last_run))
  ;;

  let run (t @ nonportable) ~region ~filename source =
    let last_run = update_source_code t ~filename source in
    match t.dirty, last_run with
    | false, { region = last_region; output = Some output; _ }
      when Sample_region.equal last_region region -> output
    | _, { tree; prepared; _ } ->
      last_run.region <- region;
      let oracles = oracles t in
      let result = 
      Parallel_scheduler.parallel t.scheduler ~f:(fun par ->
        let oracles =
          Sdf.Oracle_dependencies.extract_deps tree
          |> List.join
          |> List.fold
               ~init:(Sdf.Oracle.Key.Map.of_alist_exn [])
               ~f:(fun prepared ((key, tree) as oracle_key) ->
                 let module M =
                   (val (List.Assoc.find_exn
                           (Obj.magic Obj.magic oracles)
                           ~equal:String.equal
                           key
                         : (module Oracle.S)))
                 in
                 let p =
                   M.create tree
                   |> M.prepare
                        ~exec:(Obj.magic Obj.magic (module E : Sdf.Executor.S))
                        ~par
                        ~oracles:prepared
                        ~sample_region:region
                 in
                 Map.set prepared ~key:oracle_key ~data:p)
        in
        let batch = E.Parallel.Batch.create prepared region in
        let result = E.Parallel.Batch.run batch ~par ~oracles in
        result) in
        last_run.output <- Some result;
        result
  ;;
end
