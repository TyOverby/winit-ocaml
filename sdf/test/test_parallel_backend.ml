open! Core
open Sdf
open Helpers

(* One scheduler shared by every test; the process exits when the inline-test runner is
   done, which joins the worker domains. *)
let scheduler = Parallel_scheduler.create ()

let print_grid ~width ~height ~get =
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      printf "%s " (Sexp.to_string (Float32_u.sexp_of_t (Value.to_float (get ~x ~y))))
    done;
    printf "\n"
  done
;;

(* Evaluate [tree] over a [width] x [height] grid, binding [x]/[y] to the pixel
   coordinates via [set_affine], and print the resulting grid. *)
let eval_xy (module B : Batch_backend_intf.S_parallel) tree ~width ~height =
  let prepared = B.Prepared.of_tree tree in
  let batch = B.Batch.create prepared ~width ~height in
  Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:0. ~dx:1. ~dy:0.);
  Option.iter (B.Prepared.lookup_variable prepared "y") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:0. ~dx:0. ~dy:1.);
  let result = B.Batch.run batch ~scheduler in
  print_grid ~width ~height ~get:(B.Result.get result)
;;

module Graph_parallel = Expr_graph_eval.Batch_parallel
module Simd_parallel = Expr_graph_batch_eval.Batch_parallel

(* x + (y * 2) *)
let sample = add (var "x" Float) (mul (var "y" Float) (f #2.s))

let%expect_test "scalar-graph backend: affine x/y coordinates" =
  eval_xy (module Graph_parallel) sample ~width:4 ~height:3;
  [%expect {|
    0 1 2 3
    2 3 4 5
    4 5 6 7
    |}]
;;

let%expect_test "simd backend: identical result to the scalar backend" =
  eval_xy (module Simd_parallel) sample ~width:4 ~height:3;
  [%expect {|
    0 1 2 3
    2 3 4 5
    4 5 6 7
    |}]
;;

let%expect_test "set_uniform binds a grid-constant variable" =
  let module B = Simd_parallel in
  (* x + t, with t held constant at 10 across the whole grid *)
  let tree = add (var "x" Float) (var "t" Float) in
  let prepared = B.Prepared.of_tree tree in
  let batch = B.Batch.create prepared ~width:4 ~height:3 in
  Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:0. ~dx:1. ~dy:0.);
  Option.iter (B.Prepared.lookup_variable prepared "t") ~f:(fun var ->
    B.Batch.set_uniform batch ~var (Value.of_float #10.s));
  let result = B.Batch.run batch ~scheduler in
  print_grid ~width:4 ~height:3 ~get:(B.Result.get result);
  [%expect {|
    10 11 12 13
    10 11 12 13
    10 11 12 13
    |}]
;;

let%expect_test "set_grid binds a per-pixel variable" =
  let module B = Simd_parallel in
  let width = 4
  and height = 3 in
  (* x + g, where g is a per-pixel buffer holding g(x, y) = x * y *)
  let tree = add (var "x" Float) (var "g" Float) in
  let prepared = B.Prepared.of_tree tree in
  let batch = B.Batch.create prepared ~width ~height in
  Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:0. ~dx:1. ~dy:0.);
  Option.iter (B.Prepared.lookup_variable prepared "g") ~f:(fun var ->
    let data = Bigarray.Array1.create Bigarray.Int32 Bigarray.C_layout (width * height) in
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let bits =
          Int32_u.to_int32
            (Value.to_int (Value.of_float (Float32_u.of_float (Float.of_int (x * y)))))
        in
        Bigarray.Array1.set data ((y * width) + x) bits
      done
    done;
    B.Batch.set_grid batch ~var data);
  let result = B.Batch.run batch ~scheduler in
  print_grid ~width ~height ~get:(B.Result.get result);
  [%expect {|
    0 1 2 3
    0 2 4 6
    0 3 6 9
    |}]
;;
