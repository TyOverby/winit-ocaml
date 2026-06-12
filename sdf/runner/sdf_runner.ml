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

let run_contour
  { inner = T { vtable; state }; _ }
  ?(trace = Phase_trace.null ())
  ~region
  ~filename
  source
  =
  let module B = (val vtable) in
  let { Backend.Contour_result.segments; length; stats } =
    Phase_trace.span trace "run-contour" ~f:(fun () ->
      B.run_contour state ~trace ~region ~filename source)
  in
  ~segments, ~length, ~stats
;;

let run_tiled
  { inner = T { vtable; state }; _ }
  ?(trace = Phase_trace.null ())
  ~region
  ~filename
  source
  ~cull
  =
  let module B = (val vtable) in
  Phase_trace.span trace "run-tiled" ~f:(fun () ->
    B.run_tiled state ~trace ~region ~filename source ~cull)
;;
