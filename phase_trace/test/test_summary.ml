(** Tests for Summary.of_captured and Summary.to_string_hum. Uses hand-built Captured.t
    values with fixed literal times for determinism. *)

open! Core

let ns = Time_ns.Span.of_int_ns

(* Build a Captured.Span.t with a fixed clock *)
let span ?(args = []) ?(children = []) ?(lane = 0) ~start ~dur name =
  { Phase_trace.Captured.Span.name
  ; args
  ; start = ns start
  ; duration = ns dur
  ; lane
  ; children
  }
;;

let captured ?(name = None) ?(duration = 0) roots =
  { Phase_trace.Captured.name; started_at = Time_ns.epoch; duration = ns duration; roots }
;;

(* ------------------------------------------------------------------ *)
(* Basic summary from a single span *)

let%expect_test "single span: count=1, total=dur, self=total, max=total" =
  let c = captured [ span "work" ~start:0 ~dur:1000 ] in
  let s = Phase_trace.Summary.of_captured c in
  print_s [%sexp (s : Phase_trace.Summary.t list)];
  [%expect {| (((name work) (count 1) (total 1us) (self 1us) (max 1us) (children ()))) |}]
;;

(* ------------------------------------------------------------------ *)
(* Two siblings with the same name merge *)

let%expect_test "two same-named siblings merge: count=2, total=sum, max=longer" =
  let c = captured [ span "work" ~start:0 ~dur:400; span "work" ~start:500 ~dur:600 ] in
  let s = Phase_trace.Summary.of_captured c in
  print_s [%sexp (s : Phase_trace.Summary.t list)];
  [%expect
    {| (((name work) (count 2) (total 1us) (self 1us) (max 600ns) (children ()))) |}]
;;

(* ------------------------------------------------------------------ *)
(* self = total - sum-of-child-totals, clamped at 0 *)

let%expect_test "self = total - child total" =
  let c =
    captured
      [ span "outer" ~start:0 ~dur:1000 ~children:[ span "inner" ~start:10 ~dur:300 ] ]
  in
  let s = Phase_trace.Summary.of_captured c in
  print_s [%sexp (s : Phase_trace.Summary.t list)];
  [%expect
    {|
    (((name outer) (count 1) (total 1us) (self 700ns) (max 1us)
      (children
       (((name inner) (count 1) (total 300ns) (self 300ns) (max 300ns)
         (children ()))))))
    |}]
;;

let%expect_test "self is clamped at 0 when children total exceeds parent (parallel \
                 overcount)"
  =
  (* Parallel lanes: child total can exceed parent wall-clock duration *)
  let c =
    captured
      [ span
          "outer"
          ~start:0
          ~dur:500
          ~children:
            [ span "child" ~start:0 ~dur:300 ~lane:1
            ; span "child" ~start:0 ~dur:300 ~lane:2
            ]
      ]
  in
  let s = Phase_trace.Summary.of_captured c in
  let summary = List.hd_exn s in
  (* child total = 300 + 300 = 600 > parent 500; self clamped to 0 *)
  printf "self=%s\n" (Time_ns.Span.to_string_hum summary.self);
  printf "self_is_zero=%b\n" (Time_ns.Span.equal summary.self Time_ns.Span.zero);
  [%expect {|
    self=0ns
    self_is_zero=true
    |}]
;;

(* ------------------------------------------------------------------ *)
(* Children merged recursively *)

let%expect_test "children merged recursively: same-named grandchildren merge" =
  let c =
    captured
      [ span "a" ~start:0 ~dur:100 ~children:[ span "leaf" ~start:0 ~dur:30 ]
      ; span "a" ~start:200 ~dur:100 ~children:[ span "leaf" ~start:200 ~dur:50 ]
      ]
  in
  let s = Phase_trace.Summary.of_captured c in
  print_s [%sexp (s : Phase_trace.Summary.t list)];
  [%expect
    {|
    (((name a) (count 2) (total 200ns) (self 120ns) (max 100ns)
      (children
       (((name leaf) (count 2) (total 80ns) (self 80ns) (max 50ns) (children ()))))))
    |}]
;;

(* ------------------------------------------------------------------ *)
(* First-appearance order preserved from of_captured *)

let%expect_test "first-appearance order is preserved in Summary.of_captured" =
  let c =
    captured
      [ span "first" ~start:0 ~dur:100
      ; span "second" ~start:200 ~dur:100
      ; span "third" ~start:400 ~dur:100
      ]
  in
  let s = Phase_trace.Summary.of_captured c in
  List.iter s ~f:(fun node -> printf "%s\n" node.name);
  [%expect {|
    first
    second
    third
    |}]
;;

(* ------------------------------------------------------------------ *)
(* to_string_hum: children sorted by descending total *)

let%expect_test "to_string_hum: children sorted descending by total" =
  let c =
    captured
      [ span
          "root"
          ~start:0
          ~dur:1000
          ~children:[ span "slow" ~start:0 ~dur:600; span "fast" ~start:700 ~dur:100 ]
      ]
  in
  let s = Phase_trace.Summary.of_captured c in
  print_string (Phase_trace.Summary.to_string_hum s);
  [%expect
    {|
    root: count=1 total=1us self=300ns max=1us
      slow: count=1 total=600ns self=600ns max=600ns (60%)
      fast: count=1 total=100ns self=100ns max=100ns (10%)
    |}]
;;

let%expect_test "to_string_hum: percent-of-parent shown" =
  let c =
    captured
      [ span "root" ~start:0 ~dur:1000 ~children:[ span "child" ~start:0 ~dur:500 ] ]
  in
  let s = Phase_trace.Summary.of_captured c in
  print_string (Phase_trace.Summary.to_string_hum s);
  [%expect
    {|
    root: count=1 total=1us self=500ns max=1us
      child: count=1 total=500ns self=500ns max=500ns (50%)
    |}]
;;

let%expect_test "to_string_hum: max_depth truncates" =
  let c =
    captured
      [ span
          "l1"
          ~start:0
          ~dur:1000
          ~children:
            [ span "l2" ~start:0 ~dur:500 ~children:[ span "l3" ~start:0 ~dur:200 ] ]
      ]
  in
  let s = Phase_trace.Summary.of_captured c in
  print_string (Phase_trace.Summary.to_string_hum ~max_depth:1 s);
  [%expect {| l1: count=1 total=1us self=500ns max=1us |}]
;;

let%expect_test "to_string_hum: empty list produces empty string" =
  print_string (Phase_trace.Summary.to_string_hum []);
  [%expect {||}]
;;

let%expect_test "to_string_hum: no percent shown for root (no parent)" =
  let c = captured [ span "root" ~start:0 ~dur:1000 ] in
  let s = Phase_trace.Summary.of_captured c in
  let str = Phase_trace.Summary.to_string_hum s in
  (* Root line should not contain a % *)
  printf "contains_percent=%b\n" (String.is_substring str ~substring:"%");
  [%expect {| contains_percent=false |}]
;;
