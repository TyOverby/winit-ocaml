(** Tests for the Perfetto exporter. Builds Captured.t by hand with fixed times for
    determinism. *)

open! Core

let ns = Time_ns.Span.of_int_ns

let span ?(args = []) ?(children = []) ?(lane = 0) ~start ~dur name =
  { Phase_trace.Captured.Span.name
  ; args
  ; start = ns start
  ; duration = ns dur
  ; lane
  ; children
  }
;;

let%expect_test "perfetto: write_file produces a non-empty file" =
  let captured : Phase_trace.Captured.t =
    { name = Some "test-trace"
    ; started_at = Time_ns.epoch
    ; duration = ns 5000
    ; roots =
        [ span
            "root"
            ~start:0
            ~dur:5000
            ~args:
              [ "int_arg", Int 42
              ; "float_arg", Float 1.5
              ; "str_arg", String "hello"
              ; "bool_arg", Bool false
              ]
            ~children:
              [ span "child-main" ~start:100 ~dur:1000 ~lane:0
              ; span "child-fork" ~start:200 ~dur:800 ~lane:1 ~args:[ "count", Int 8 ]
              ]
        ]
    }
  in
  let filename = Stdlib.Filename.temp_file "phase_trace_test" ".fxt" in
  Phase_trace_perfetto.write_file captured ~filename;
  (* Check the file exists and is non-empty *)
  let length = (Core_unix.stat filename).st_size in
  printf "(file length > 0) = %b\n" (Int64.( > ) length 0L);
  (* Read the first 8 bytes and render as hex — the FXT magic record *)
  let ic = Stdlib.open_in_bin filename in
  let buf = Bytes.create 8 in
  (try Stdlib.really_input ic buf 0 8 with
   | End_of_file -> ());
  Stdlib.close_in ic;
  let hex =
    Bytes.to_list buf
    |> List.map ~f:(fun c -> sprintf "%02x" (Char.to_int c))
    |> String.concat ~sep:" "
  in
  printf "first 8 bytes: %s\n" hex;
  (* Clean up *)
  Core_unix.unlink filename;
  [%expect
    {|
    (file length > 0) = true
    first 8 bytes: 10 00 04 46 78 54 16 00
    |}]
;;

let%expect_test "perfetto: write_file with two distinct lanes" =
  let captured : Phase_trace.Captured.t =
    { name = Some "two-lane"
    ; started_at = Time_ns.epoch
    ; duration = ns 2000
    ; roots =
        [ span
            "root"
            ~start:0
            ~dur:2000
            ~children:
              [ span "lane1-span" ~start:100 ~dur:500 ~lane:1
              ; span "lane2-span" ~start:700 ~dur:500 ~lane:2
              ]
        ]
    }
  in
  let filename = Stdlib.Filename.temp_file "phase_trace_test_2lane" ".fxt" in
  Phase_trace_perfetto.write_file captured ~filename;
  let length = (Core_unix.stat filename).st_size in
  printf "(file length > 0) = %b\n" (Int64.( > ) length 0L);
  Core_unix.unlink filename;
  [%expect {| (file length > 0) = true |}]
;;
