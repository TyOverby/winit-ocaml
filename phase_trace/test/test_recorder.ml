(** Tests for basic recording: create/span/finish, null writer, exception safety, finish
    semantics. *)

open! Core
open Expect_test_helpers_core

(* ------------------------------------------------------------------ *)
(* Structural printer — prints only names, lane category, child count. Avoids all
   timestamps so output is deterministic. *)

let rec print_span ?(indent = 0) (s : Phase_trace.Captured.Span.t) =
  let lane_tag = if s.lane = 0 then "lane=main" else "lane=fork" in
  printf
    "%s%s [%s, children=%d]\n"
    (String.make (indent * 2) ' ')
    s.name
    lane_tag
    (List.length s.children);
  List.iter s.children ~f:(print_span ~indent:(indent + 1))
;;

let print_captured (c : Phase_trace.Captured.t) =
  printf
    "name=%s roots=%d\n"
    (Option.value c.name ~default:"(none)")
    (List.length c.roots);
  List.iter c.roots ~f:(print_span ~indent:1)
;;

(* ------------------------------------------------------------------ *)
(* 1. Basic recording *)

let%expect_test "single span produces one root" =
  let t = Phase_trace.create () in
  Phase_trace.span t "alpha" ~f:(fun () -> ());
  let c = Phase_trace.finish t in
  print_captured c;
  [%expect {|
    name=(none) roots=1
      alpha [lane=main, children=0]
    |}]
;;

let%expect_test "nested spans produce nested children" =
  let t = Phase_trace.create () in
  Phase_trace.span t "outer" ~f:(fun () -> Phase_trace.span t "inner" ~f:(fun () -> ()));
  let c = Phase_trace.finish t in
  print_captured c;
  [%expect
    {|
    name=(none) roots=1
      outer [lane=main, children=1]
        inner [lane=main, children=0]
    |}]
;;

let%expect_test "siblings appear in recording order" =
  let t = Phase_trace.create () in
  Phase_trace.span t "a" ~f:(fun () -> ());
  Phase_trace.span t "b" ~f:(fun () -> ());
  Phase_trace.span t "c" ~f:(fun () -> ());
  let c = Phase_trace.finish t in
  print_captured c;
  [%expect
    {|
    name=(none) roots=3
      a [lane=main, children=0]
      b [lane=main, children=0]
      c [lane=main, children=0]
    |}]
;;

let%expect_test "span returns the body's value" =
  let t = Phase_trace.create () in
  let v = Phase_trace.span t "compute" ~f:(fun () -> 42) in
  let _c = Phase_trace.finish t in
  printf "%d\n" v;
  [%expect {| 42 |}]
;;

let%expect_test "trace name is carried through to Captured.t" =
  let t = Phase_trace.create ~name:"my-trace" () in
  let c = Phase_trace.finish t in
  printf "name=%s\n" (Option.value c.name ~default:"(none)");
  [%expect {| name=my-trace |}]
;;

let%expect_test "args are carried through to Captured.Span" =
  let t = Phase_trace.create () in
  Phase_trace.span
    t
    "compute"
    ~args:
      [ "int_arg", Int 7
      ; "float_arg", Float 3.14
      ; "str_arg", String "hello"
      ; "bool_arg", Bool true
      ]
    ~f:(fun () -> ());
  let c = Phase_trace.finish t in
  (match c.roots with
   | [ span ] ->
     List.iter span.args ~f:(fun (k, v) ->
       printf "%s=%s\n" k (Sexp.to_string (Phase_trace.Arg.sexp_of_t v)))
   | _ -> printf "unexpected roots count\n");
  [%expect
    {|
    int_arg=(Int 7)
    float_arg=(Float 3.14)
    str_arg=(String hello)
    bool_arg=(Bool true)
    |}]
;;

let%expect_test "time sanity: duration >= 0, child.start >= parent.start" =
  let t = Phase_trace.create () in
  Phase_trace.span t "outer" ~f:(fun () -> Phase_trace.span t "inner" ~f:(fun () -> ()));
  let c = Phase_trace.finish t in
  let outer = List.hd_exn c.roots in
  let inner = List.hd_exn outer.children in
  require
    ~here:[%here]
    ~if_false_then_print_s:(lazy (Sexp.of_string "outer duration < 0"))
    (Time_ns.Span.( >= ) outer.duration Time_ns.Span.zero);
  require
    ~here:[%here]
    ~if_false_then_print_s:(lazy (Sexp.of_string "inner duration < 0"))
    (Time_ns.Span.( >= ) inner.duration Time_ns.Span.zero);
  require
    ~here:[%here]
    ~if_false_then_print_s:(lazy (Sexp.of_string "inner.start < outer.start"))
    (Time_ns.Span.( >= ) inner.start outer.start);
  [%expect {||}]
;;

(* ------------------------------------------------------------------ *)
(* 2. null writer *)

let%expect_test "null: is_recording is false" =
  let t = Phase_trace.null () in
  printf "is_recording=%b\n" (Phase_trace.is_recording t);
  [%expect {| is_recording=false |}]
;;

let%expect_test "null: span body still runs" =
  let t = Phase_trace.null () in
  let ran = ref false in
  Phase_trace.span t "noop" ~f:(fun () -> ran := true);
  printf "ran=%b\n" !ran;
  [%expect {| ran=true |}]
;;

let%expect_test "null: span body returns its value" =
  let t = Phase_trace.null () in
  let v = Phase_trace.span t "noop" ~f:(fun () -> 99) in
  printf "v=%d\n" v;
  [%expect {| v=99 |}]
;;

let%expect_test "null: finish returns empty capture" =
  let t = Phase_trace.null () in
  Phase_trace.span t "ignored" ~f:(fun () -> ());
  let c = Phase_trace.finish t in
  printf
    "roots=%d duration=%s\n"
    (List.length c.roots)
    (Time_ns.Span.to_string_hum c.duration);
  [%expect {| roots=0 duration=0ns |}]
;;

let%expect_test "null: fork is inert, with_fork body still runs" =
  let t = Phase_trace.null () in
  let fk = Phase_trace.fork t in
  let ran = ref false in
  let v =
    Phase_trace.with_fork fk ~f:(fun _w ->
      ran := true;
      55)
  in
  printf "ran=%b v=%d\n" !ran v;
  [%expect {| ran=true v=55 |}]
;;

let%expect_test "null: fork of null produces inert lane writer with is_recording=false" =
  let t = Phase_trace.null () in
  let fk = Phase_trace.fork t in
  Phase_trace.with_fork fk ~f:(fun w ->
    printf "lane_is_recording=%b\n" (Phase_trace.is_recording w));
  [%expect {| lane_is_recording=false |}]
;;

(* ------------------------------------------------------------------ *)
(* 3. Exception safety *)

let%expect_test "exception in span body: span still appears in capture" =
  let t = Phase_trace.create () in
  (try Phase_trace.span t "will-raise" ~f:(fun () -> raise Exit) with
   | Exit -> ());
  let c = Phase_trace.finish t in
  print_captured c;
  [%expect {|
    name=(none) roots=1
      will-raise [lane=main, children=0]
    |}]
;;

let%expect_test "exception in span body: outer span also records correctly" =
  let t = Phase_trace.create () in
  (try
     Phase_trace.span t "outer" ~f:(fun () ->
       Phase_trace.span t "inner" ~f:(fun () -> raise Exit))
   with
   | Exit -> ());
  let c = Phase_trace.finish t in
  print_captured c;
  [%expect
    {|
    name=(none) roots=1
      outer [lane=main, children=1]
        inner [lane=main, children=0]
    |}]
;;

let%expect_test "exception in with_fork body: lane still joined" =
  let t = Phase_trace.create () in
  let fk = Phase_trace.fork t in
  (try
     Phase_trace.with_fork fk ~name:"lane" ~f:(fun w ->
       Phase_trace.span w "work" ~f:(fun () -> raise Exit))
   with
   | Exit -> ());
  let c = Phase_trace.finish t in
  (* There should be a "lane" span from the fork *)
  let all_names =
    let rec collect (s : Phase_trace.Captured.Span.t) =
      s.name :: List.concat_map s.children ~f:collect
    in
    List.concat_map c.roots ~f:collect
  in
  printf "spans: %s\n" (String.concat ~sep:", " all_names);
  [%expect {| spans: lane, work |}]
;;

(* ------------------------------------------------------------------ *)
(* 4. finish semantics *)

let%expect_test "is_recording is true before finish, false after" =
  let t = Phase_trace.create () in
  printf "before=%b\n" (Phase_trace.is_recording t);
  let _c = Phase_trace.finish t in
  printf "after=%b\n" (Phase_trace.is_recording t);
  [%expect {|
    before=true
    after=false
    |}]
;;

let%expect_test "second finish raises" =
  let t = Phase_trace.create () in
  let _c = Phase_trace.finish t in
  show_raise (fun () -> Phase_trace.finish t);
  [%expect {| (raised (Failure "Phase_trace.finish: trace already finished")) |}]
;;

let%expect_test "finish on a lane writer raises" =
  let t = Phase_trace.create () in
  let fk = Phase_trace.fork t in
  Phase_trace.with_fork fk ~f:(fun w -> show_raise (fun () -> Phase_trace.finish w));
  let _c = Phase_trace.finish t in
  [%expect
    {|
    (raised (
      Failure
      "Phase_trace.finish: called on a writer that did not come from [create]"))
    |}]
;;

let%expect_test "recording after finish is a no-op; body still runs and returns value" =
  let t = Phase_trace.create () in
  let _c = Phase_trace.finish t in
  let ran = ref false in
  let v =
    Phase_trace.span t "post-finish" ~f:(fun () ->
      ran := true;
      77)
  in
  printf "ran=%b v=%d\n" !ran v;
  [%expect {| ran=true v=77 |}]
;;
