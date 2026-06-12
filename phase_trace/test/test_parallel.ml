(** Tests for parallel forking — real parallelism via Parallel_scheduler. Structural
    printer only; sort children by name before printing to defeat nondeterministic
    completion order. *)

open! Core
open Expect_test_helpers_core

(* ------------------------------------------------------------------ *)
(* Structural printer *)

let rec span_names_sorted (s : Phase_trace.Captured.Span.t) =
  s.name
  :: List.concat_map
       (List.sort s.children ~compare:(fun a b -> String.compare a.name b.name))
       ~f:span_names_sorted
;;

let print_summary_counts (s : Phase_trace.Summary.t) =
  let rec go indent (node : Phase_trace.Summary.t) =
    printf "%s%s: count=%d\n" (String.make (indent * 2) ' ') node.name node.count;
    List.iter node.children ~f:(go (indent + 1))
  in
  go 0 s
;;

(* ------------------------------------------------------------------ *)
(* 6. Real parallelism test *)

let%expect_test "parallel fork: 16 tasks, each records row+work spans" =
  let trace = Phase_trace.create () in
  Phase_trace.span trace "outer" ~f:(fun () ->
    let fk = Phase_trace.fork trace in
    let scheduler = Parallel_scheduler.create () in
    Parallel_scheduler.parallel scheduler ~f:(fun par ->
      Parallel.for_ par ~start:0 ~stop:16 ~f:(fun _par i ->
        Phase_trace.with_fork fk ~name:"row" ~f:(fun w ->
          Phase_trace.span w "work" ~f:(fun () -> ignore (Sys.opaque_identity i))))));
  let captured = Phase_trace.finish trace in
  let summary = Phase_trace.Summary.of_captured captured in
  (* Summary should show outer > row(count=16) > work(count=16) *)
  (match summary with
   | [ outer ] ->
     printf "outer_count=%d\n" outer.count;
     (match outer.children with
      | [ row ] ->
        printf "row_count=%d\n" row.count;
        (match row.children with
         | [ work ] -> printf "work_count=%d\n" work.count
         | _ -> printf "unexpected work children count=%d\n" (List.length row.children))
      | _ -> printf "unexpected row children count=%d\n" (List.length outer.children))
   | _ -> printf "unexpected root count=%d\n" (List.length summary));
  [%expect {|
    outer_count=1
    row_count=16
    work_count=16
    |}]
;;

let%expect_test "parallel fork: all lane spans have lane > 0 in Captured" =
  let trace = Phase_trace.create () in
  Phase_trace.span trace "outer" ~f:(fun () ->
    let fk = Phase_trace.fork trace in
    let scheduler = Parallel_scheduler.create () in
    Parallel_scheduler.parallel scheduler ~f:(fun par ->
      Parallel.for_ par ~start:0 ~stop:8 ~f:(fun _par i ->
        Phase_trace.with_fork fk ~name:"row" ~f:(fun w ->
          Phase_trace.span w "work" ~f:(fun () -> ignore (Sys.opaque_identity i))))));
  let captured = Phase_trace.finish trace in
  (* Collect all spans with their lane id *)
  let rec collect_spans (s : Phase_trace.Captured.Span.t) =
    (s.name, s.lane) :: List.concat_map s.children ~f:collect_spans
  in
  let all = List.concat_map captured.roots ~f:collect_spans in
  (* "outer" should be on lane 0, all "row" and "work" spans should be on lane > 0 *)
  let outer_lane =
    List.filter_map all ~f:(fun (name, lane) ->
      if String.equal name "outer" then Some lane else None)
  in
  let row_lanes =
    List.filter_map all ~f:(fun (name, lane) ->
      if String.equal name "row" then Some lane else None)
  in
  let work_lanes =
    List.filter_map all ~f:(fun (name, lane) ->
      if String.equal name "work" then Some lane else None)
  in
  printf "outer lanes all=0: %b\n" (List.for_all outer_lane ~f:(fun l -> l = 0));
  printf "row lanes all>0: %b\n" (List.for_all row_lanes ~f:(fun l -> l > 0));
  printf "work lanes all>0: %b\n" (List.for_all work_lanes ~f:(fun l -> l > 0));
  printf "row count=%d work count=%d\n" (List.length row_lanes) (List.length work_lanes);
  [%expect
    {|
    outer lanes all=0: true
    row lanes all>0: true
    work lanes all>0: true
    row count=8 work count=8
    |}]
;;

(* ------------------------------------------------------------------ *)
(* 7. Nested forks: with_fork inside a with_fork lane *)

let%expect_test "nested forks: sub-lane attaches beneath right span" =
  let trace = Phase_trace.create () in
  Phase_trace.span trace "root" ~f:(fun () ->
    let fk = Phase_trace.fork trace in
    let scheduler = Parallel_scheduler.create () in
    Parallel_scheduler.parallel scheduler ~f:(fun par ->
      Parallel.for_ par ~start:0 ~stop:2 ~f:(fun _par i ->
        Phase_trace.with_fork fk ~name:"outer-lane" ~f:(fun w ->
          Phase_trace.span w "mid" ~f:(fun () ->
            let fk2 = Phase_trace.fork w in
            Phase_trace.with_fork fk2 ~name:"inner-lane" ~f:(fun w2 ->
              Phase_trace.span w2 "deep" ~f:(fun () -> ignore (Sys.opaque_identity i))))))));
  let captured = Phase_trace.finish trace in
  let summary = Phase_trace.Summary.of_captured captured in
  (* Print the full summary tree *)
  let rec print_summary indent (node : Phase_trace.Summary.t) =
    printf "%s%s: count=%d\n" (String.make (indent * 2) ' ') node.name node.count;
    List.iter node.children ~f:(print_summary (indent + 1))
  in
  List.iter summary ~f:(print_summary 0);
  [%expect
    {|
    root: count=1
      outer-lane: count=2
        mid: count=2
          inner-lane: count=2
            deep: count=2
    |}]
;;

(* ------------------------------------------------------------------ *)
(* Time sanity on parallel results *)

let%expect_test "parallel: all span durations are non-negative" =
  let trace = Phase_trace.create () in
  Phase_trace.span trace "root" ~f:(fun () ->
    let fk = Phase_trace.fork trace in
    let scheduler = Parallel_scheduler.create () in
    Parallel_scheduler.parallel scheduler ~f:(fun par ->
      Parallel.for_ par ~start:0 ~stop:8 ~f:(fun _par i ->
        Phase_trace.with_fork fk ~name:"row" ~f:(fun w ->
          Phase_trace.span w "work" ~f:(fun () -> ignore (Sys.opaque_identity i))))));
  let captured = Phase_trace.finish trace in
  let rec check (s : Phase_trace.Captured.Span.t) =
    require
      ~here:[%here]
      ~if_false_then_print_s:
        (lazy
          (Sexp.List
             [ Sexp.Atom (sprintf "negative duration on span %s" s.name)
             ; Time_ns.Span.sexp_of_t s.duration
             ]))
      (Time_ns.Span.( >= ) s.duration Time_ns.Span.zero);
    List.iter s.children ~f:check
  in
  List.iter captured.roots ~f:check;
  [%expect {||}]
;;
