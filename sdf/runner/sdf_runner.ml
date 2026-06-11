open! Core
open Sdf

type inner =
  | T :
      { vtable : (module Backend.S with type t = 'a)
      ; state : 'a
      }
      -> inner

type t =
  { mutable inner : inner
  ; mutable oracles : (string * (module Oracle.S) portable) list
  }

let create ((module E : Executor.S) @ portable) =
  let module Backend = Backend.Make (E) in
  let state = Backend.create () in
  { inner = T { vtable = (module Backend); state }; oracles = [] }
;;

let add_oracle ({ inner = T { vtable; state }; _ } as t) ~name oracle =
  let module B = (val vtable) in
  B.add_oracle state ~name oracle;
  t.oracles <- (name, { portable = oracle }) :: t.oracles
;;

let set_executor t ((module E : Executor.S) @ portable) =
  let module Backend = Backend.Make (E) in
  let state = Backend.create () in
  t.inner <- T { vtable = (module Backend); state };
  let old_oracles = t.oracles in
  t.oracles <- [];
  List.iter old_oracles ~f:(fun (name, { portable = oracle }) ->
    add_oracle t ~name oracle)
;;

let run
  :  _ -> region:_ -> filename:_ -> _
  -> f:
       ('a.
        Parallel.t @ local
        -> 'a @ contended portable
        -> ('a -> x:int -> y:int -> Value.t) @ portable
        -> unit)
     @ once shareable
  -> unit
  =
  fun { inner = T { vtable; state }; _ } ~region ~filename source ~f ->
  let module B = (val vtable) in
  let result = B.run state ~region ~filename source in
  let scheduler = B.scheduler state in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    f par result B.E.Parallel.Result.get)
;;

let run_contour { inner = T { vtable; state }; _ } ~region ~filename source =
  let module B = (val vtable) in
  let { Backend.Contour_result.segments; length; stats } =
    B.run_contour state ~region ~filename source
  in
  ~segments, ~length, ~stats
;;

let run_tiled { inner = T { vtable; state }; _ } ~region ~filename source ~cull =
  let module B = (val vtable) in
  B.run_tiled state ~region ~filename source ~cull
;;
