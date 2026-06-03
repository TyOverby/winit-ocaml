open! Core
open Sdf
open Helpers
module Executor = Sdf.Expr_tree_eval
module Implementation = Executor.Single

let default_env t =
  Implementation.Variable_idx.Map.of_alist_exn
    [ Implementation.lookup_variable t "x", Value.Boxed.T (Value.of_float #1.0s)
    ; Implementation.lookup_variable t "y", Value.Boxed.T (Value.of_float #1.0s)
    ; Implementation.lookup_variable t "b", Value.Boxed.T (Value.of_bool true)
    ]
;;

let oracle_registry : (string * (module Oracle.S)) list =
  [ "passthrough", (module Sdf_oracles.Passthrough) ]
;;

let run tree =
  let oracles =
    Oracle_dependencies.extract_deps tree
    |> List.join
    |> List.fold
         ~init:Oracle.Key.Map.empty
         ~f:(fun prepared ((key, tree) as oracle_key) ->
           let module M =
             (val List.Assoc.find_exn oracle_registry ~equal:String.equal key)
           in
           let p =
             M.create tree
             |> M.prepare
                  ~exec:(module Executor)
                  ~oracles:prepared
                  ~range_x:#(#0.0s, #0.0s)
                  ~range_y:#(#0.0s, #0.0s)
           in
           Map.set prepared ~key:oracle_key ~data:p)
  in
  let t = Implementation.of_tree tree in
  let value =
    Or_error.try_with (fun () ->
      Value.box (Implementation.run ~vars:(default_env t) ~oracles t))
  in
  match value with
  | Ok v -> v |> Value.unbox |> Value.to_float |> Float32_u.sexp_of_t |> print_s
  | Error e -> print_s (Error.sexp_of_t e)
;;

let%expect_test "no oracles" =
  let tree = add (f #1.s) (f #2.s) in
  run tree;
  [%expect {||}]
;;

let%expect_test "single oracle with no dependencies" =
  let x = var "x" Float in
  let tree = oracle "passthrough" [ x ] in
  run tree;
  [%expect
    {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;

let%expect_test "two independent oracles" =
  let x = var "x" Float in
  let y = var "y" Float in
  let a = oracle "passthrough" [ x ] in
  let b = oracle "passthrough" [ y ] in
  let tree = add a b in
  run tree;
  [%expect
    {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
      sharpen(((loc :0:-1) (kind (Var y Float)) (type_ Float)))
    |}]
;;

let%expect_test "oracle depending on another oracle" =
  let x = var "x" Float in
  let blur_x = oracle "passthrough" [ x ] in
  let tree = oracle "passthrough" [ blur_x ] in
  run tree;
  [%expect
    {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    level 1:
      sharpen(((loc :0:-1)
     (kind (Oracle blur (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
     (type_ Float)))
    |}]
;;

let%expect_test "chain of three oracles" =
  let x = var "x" Float in
  let a = oracle "passthrough" [ x ] in
  let b = oracle "passthrough" [ a ] in
  let tree = oracle "passthrough" [ b ] in
  run tree;
  [%expect
    {|
    level 0:
      a(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    level 1:
      b(((loc :0:-1)
     (kind (Oracle a (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
     (type_ Float)))
    level 2:
      c(((loc :0:-1)
     (kind
      (Oracle b
       (((loc :0:-1)
         (kind (Oracle a (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
         (type_ Float)))))
     (type_ Float)))
    |}]
;;

let%expect_test "diamond dependency" =
  let x = var "x" Float in
  let base = oracle "passthrough" [ x ] in
  let left = oracle "passthrough" [ base ] in
  let right = oracle "passthrough" [ base ] in
  let tree = oracle "passthrough" [ left; right ] in
  run tree;
  [%expect
    {|
    level 0:
      base(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    level 1:
      left(((loc :0:-1)
     (kind (Oracle base (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
     (type_ Float)))
      right(((loc :0:-1)
     (kind (Oracle base (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
     (type_ Float)))
    level 2:
      top(((loc :0:-1)
     (kind
      (Oracle left
       (((loc :0:-1)
         (kind (Oracle base (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
         (type_ Float)))))
     (type_ Float)), ((loc :0:-1)
     (kind
      (Oracle right
       (((loc :0:-1)
         (kind (Oracle base (((loc :0:-1) (kind (Var x Float)) (type_ Float)))))
         (type_ Float)))))
     (type_ Float)))
    |}]
;;

let%expect_test "duplicate oracle appears once" =
  let x = var "x" Float in
  let blur_x = oracle "passthrough" [ x ] in
  (* Same oracle used in two places *)
  let tree = add blur_x blur_x in
  run tree;
  [%expect
    {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;

let%expect_test "same name different args are different oracles" =
  let x = var "x" Float in
  let y = var "y" Float in
  let blur_x = oracle "passthrough" [ x ] in
  let blur_y = oracle "passthrough" [ y ] in
  let tree = add blur_x blur_y in
  run tree;
  [%expect
    {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
      blur(((loc :0:-1) (kind (Var y Float)) (type_ Float)))
    |}]
;;

let%expect_test "oracle nested inside arithmetic" =
  let x = var "x" Float in
  let o = oracle "passthrough" [ x ] in
  let tree = mul (add o (f #1.s)) (sub o (f #2.s)) in
  run tree;
  [%expect
    {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;

let%expect_test "oracle inside cond branches" =
  let x = var "x" Float in
  let o1 = oracle "passthrough" [ x ] in
  let o2 = oracle "passthrough" [ x ] in
  let tree = cond ~condition:(lt o1 (f #0.s)) ~then_:o1 ~else_:o2 in
  run tree;
  [%expect
    {|
    level 0:
      a(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
      b(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;
