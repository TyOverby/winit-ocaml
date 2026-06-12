(** Stress tests: high-volume parallel and random span-tree quickcheck. *)

open! Core
open Expect_test_helpers_core

(* ------------------------------------------------------------------ *)
(* 8a. Parallel stress: 200 tasks, 3 nested spans each *)

let%expect_test "parallel stress: 200 tasks with 3 nested spans, counts match" =
  let trace = Phase_trace.create () in
  Phase_trace.span trace "root" ~f:(fun () ->
    let fk = Phase_trace.fork trace in
    let scheduler = Parallel_scheduler.create () in
    Parallel_scheduler.parallel scheduler ~f:(fun par ->
      Parallel.for_ par ~start:0 ~stop:200 ~f:(fun _par i ->
        Phase_trace.with_fork fk ~name:"task" ~f:(fun w ->
          Phase_trace.span w "step1" ~f:(fun () ->
            Phase_trace.span w "step2" ~f:(fun () ->
              Phase_trace.span w "step3" ~f:(fun () -> ignore (Sys.opaque_identity i))))))));
  let captured = Phase_trace.finish trace in
  let summary = Phase_trace.Summary.of_captured captured in
  let find_node name (nodes : Phase_trace.Summary.t list) =
    List.find nodes ~f:(fun n -> String.equal n.name name)
  in
  (match find_node "root" summary with
   | None -> printf "no root\n"
   | Some root ->
     printf "root: count=%d\n" root.count;
     (match find_node "task" root.children with
      | None -> printf "no task\n"
      | Some task ->
        printf "task: count=%d\n" task.count;
        (match find_node "step1" task.children with
         | None -> printf "no step1\n"
         | Some step1 ->
           printf "step1: count=%d\n" step1.count;
           (match find_node "step2" step1.children with
            | None -> printf "no step2\n"
            | Some step2 ->
              printf "step2: count=%d\n" step2.count;
              (match find_node "step3" step2.children with
               | None -> printf "no step3\n"
               | Some step3 -> printf "step3: count=%d\n" step3.count)))));
  [%expect
    {|
    root: count=1
    task: count=200
    step1: count=200
    step2: count=200
    step3: count=200
    |}]
;;

(* ------------------------------------------------------------------ *)
(* 8b. Deterministic random span-tree: generate, record, assert counts match *)

(* We generate a random tree of spans described as (name, depth) pairs, record them into a
   live trace, then verify that the summary counts match the generated shape exactly. *)

type span_shape =
  { name : string
  ; children : span_shape list
  }

(* Count all instances of each name in a list of shapes *)
let count_names shapes =
  let tbl = Hashtbl.create (module String) in
  let rec count shape =
    Hashtbl.update tbl shape.name ~f:(function
      | None -> 1
      | Some n -> n + 1);
    List.iter shape.children ~f:count
  in
  List.iter shapes ~f:count;
  tbl
;;

(* Generate a random tree using a seeded RNG *)
let gen_shapes rng ~max_depth ~branching =
  let names = [| "alpha"; "beta"; "gamma"; "delta" |] in
  let rec gen depth =
    let name = names.(Random.State.int rng (Array.length names)) in
    let n_children =
      if depth >= max_depth then 0 else Random.State.int rng (branching + 1)
    in
    { name; children = List.init n_children ~f:(fun _ -> gen (depth + 1)) }
  in
  let n_roots = 1 + Random.State.int rng branching in
  List.init n_roots ~f:(fun _ -> gen 0)
;;

(* Record a list of shapes into a writer *)
let rec record_shape w (shape : span_shape) =
  Phase_trace.span w shape.name ~f:(fun () ->
    List.iter shape.children ~f:(record_shape w))
;;

(* Recursively collect (name -> count) from a Summary tree *)
let summary_counts (summary : Phase_trace.Summary.t list) =
  let tbl = Hashtbl.create (module String) in
  let rec collect (node : Phase_trace.Summary.t) =
    Hashtbl.update tbl node.name ~f:(function
      | None -> node.count
      | Some n -> n + node.count);
    List.iter node.children ~f:collect
  in
  List.iter summary ~f:collect;
  tbl
;;

let%expect_test "quickcheck-style: random span trees have exact counts in summary" =
  let rng = Random.State.make [| 42 |] in
  let n_trials = 20 in
  let all_ok = ref true in
  for trial = 0 to n_trials - 1 do
    let shapes = gen_shapes rng ~max_depth:3 ~branching:3 in
    let expected = count_names shapes in
    let t = Phase_trace.create () in
    List.iter shapes ~f:(record_shape t);
    let captured = Phase_trace.finish t in
    let summary = Phase_trace.Summary.of_captured captured in
    let got = summary_counts summary in
    (* Check every expected name has correct count *)
    Hashtbl.iteri expected ~f:(fun ~key:name ~data:expected_count ->
      let got_count = Hashtbl.find got name |> Option.value ~default:0 in
      if got_count <> expected_count
      then (
        all_ok := false;
        printf "trial=%d name=%s expected=%d got=%d\n" trial name expected_count got_count))
  done;
  require
    ~here:[%here]
    ~if_false_then_print_s:(lazy (Sexp.Atom "some counts wrong"))
    !all_ok;
  [%expect {||}]
;;
