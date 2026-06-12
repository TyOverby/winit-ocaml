external unbox : float -> float# @@ portable = "%unbox_float"
external box : float# -> float @@ portable = "%box_float"

(* Fiber needs to resize, so don't tail *)
let[@inline never] rec walk (x : float#) (n : int) : float# =
  if n = 0
  then x
  else (
    let r = walk x (n - 1) in
    if Stdlib.Sys.opaque_identity false then x else r)
;;

let check where =
  let v = 1.0 in
  let r = box (walk (unbox v) 1000) in
  Stdlib.print_endline
    (Printf.sprintf
       "%s: walk returned %h (expected %h) -- %s"
       where
       r
       v
       (if Float.equal r v then "ok" else "CORRUPTED"))
;;

let () =
  check "main stack";
  let scheduler = Parallel_scheduler.create () in
  Parallel_scheduler.parallel scheduler ~f:(fun _par -> check "parallel fiber")
;;
