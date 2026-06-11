open! Core
open Sdf
open Helpers

module Make_tests (Implementation : Executor.S_single) = struct
  let default_env t =
    let add_var name value map =
      match Implementation.lookup_variable t name with
      | idx -> Map.set map ~key:idx ~data:value
      | exception _ -> map
    in
    Map.empty (module Implementation.Variable_idx)
    |> add_var "b" (Value.Boxed.T (Value.of_bool true))
  ;;

  let eval_float tree =
    let t = Implementation.of_tree tree in
    let value =
      Or_error.try_with (fun () ->
        Value.box
          (Implementation.run
             ~vars:(default_env t)
             ~oracles:(Map.empty (module Oracle.Key))
             ~x:#1.0s
             ~y:#1.0s
             t))
    in
    match value with
    | Ok v -> v |> Value.unbox |> Value.to_float |> Float32_u.sexp_of_t |> print_s
    | Error e -> print_s (Error.sexp_of_t e)
  ;;

  let eval_bool tree =
    let t = Implementation.of_tree tree in
    let value =
      Or_error.try_with (fun () ->
        Value.box
          (Implementation.run
             ~vars:(default_env t)
             ~oracles:(Map.empty (module Oracle.Key))
             ~x:#1.0s
             ~y:#1.0s
             t))
    in
    match value with
    | Ok v -> v |> Value.unbox |> Value.to_bool |> Bool.sexp_of_t |> print_s
    | Error e -> print_s (Error.sexp_of_t e)
  ;;

  let%expect_test "float literal" =
    eval_float (f #3.14s);
    [%expect {| 3.1400001 |}]
  ;;

  let%expect_test "addition" =
    eval_float (add (f #1.s) (f #2.s));
    [%expect {| 3 |}]
  ;;

  let%expect_test "subtraction" =
    eval_float (sub (f #5.s) (f #3.s));
    [%expect {| 2 |}]
  ;;

  let%expect_test "multiplication" =
    eval_float (mul (f #4.s) (f #2.5s));
    [%expect {| 10 |}]
  ;;

  let%expect_test "division" =
    eval_float (div (f #10.s) (f #4.s));
    [%expect {| 2.5 |}]
  ;;

  let%expect_test "sqrt" =
    eval_float (sqrt (f #9.s));
    [%expect {| 3 |}]
  ;;

  let%expect_test "abs positive" =
    eval_float (abs (f #3.s));
    [%expect {| 3 |}]
  ;;

  let%expect_test "abs negative" =
    eval_float (abs (f Float32_u.(neg #3.s)));
    [%expect {| 3 |}]
  ;;

  let%expect_test "neg" =
    eval_float (neg (f #3.s));
    [%expect {| -3 |}]
  ;;

  let%expect_test "sign positive" =
    eval_float (sign (f #5.s));
    [%expect {| 1 |}]
  ;;

  let%expect_test "sign negative" =
    eval_float (sign (f Float32_u.(neg #5.s)));
    [%expect {| -1 |}]
  ;;

  let%expect_test "sign zero" =
    eval_float (sign (f #0.s));
    [%expect {| 0 |}]
  ;;

  let%expect_test "sin" =
    eval_float (sin (f #0.s));
    [%expect {| 0 |}]
  ;;

  let%expect_test "cos" =
    eval_float (cos (f #0.s));
    [%expect {| 1 |}]
  ;;

  let%expect_test "round" =
    eval_float (round (f #2.7s));
    [%expect {| 3 |}]
  ;;

  let%expect_test "min" =
    eval_float (min (f #3.s) (f #5.s));
    [%expect {| 3 |}]
  ;;

  let%expect_test "max" =
    eval_float (max (f #3.s) (f #5.s));
    [%expect {| 5 |}]
  ;;

  (* Division is total: x / 0 = 0, including 0 / 0 and division by -0. *)
  let%expect_test "division by zero produces zero" =
    eval_float (div (f #1.s) (f #0.s));
    [%expect {| 0 |}]
  ;;

  let%expect_test "zero divided by zero is zero" =
    eval_float (div (f #0.s) (f #0.s));
    [%expect {| 0 |}]
  ;;

  let%expect_test "division by negative zero is zero" =
    eval_float (div (f #1.s) (f Float32_u.(neg #0.s)));
    [%expect {| 0 |}]
  ;;

  (* Sqrt is total: sqrt of a negative is 0. *)
  let%expect_test "sqrt of a negative produces zero" =
    eval_float (sqrt (f Float32_u.(neg #4.s)));
    [%expect {| 0 |}]
  ;;

  let%expect_test "nested arithmetic respects left-to-right composition" =
    (* (1 + 2) * (3 - 0.5) = 7.5 *)
    eval_float (mul (add (f #1.s) (f #2.s)) (sub (f #3.s) (f #0.5s)));
    [%expect {| 7.5 |}]
  ;;

  let%expect_test "negative results" =
    eval_float (sub (f #1.s) (f #4.s));
    [%expect {| -3 |}]
  ;;

  let%expect_test "cond selects then-branch when true" =
    eval_float (cond ~condition:(b true) ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| 1 |}]
  ;;

  let%expect_test "cond selects else-branch when false" =
    eval_float (cond ~condition:(b false) ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| 2 |}]
  ;;

  let%expect_test "cond with less-than" =
    eval_float (cond ~condition:(lt (f #1.s) (f #2.s)) ~then_:(f #10.s) ~else_:(f #20.s));
    [%expect {| 10 |}]
  ;;

  let%expect_test "cond with greater-than (false)" =
    eval_float (cond ~condition:(gt (f #1.s) (f #2.s)) ~then_:(f #10.s) ~else_:(f #20.s));
    [%expect {| 20 |}]
  ;;

  let%expect_test "cond with less-than-or-equal at boundary" =
    eval_float (cond ~condition:(lte (f #2.s) (f #2.s)) ~then_:(f #10.s) ~else_:(f #20.s));
    [%expect {| 10 |}]
  ;;

  let%expect_test "cond with greater-than-or-equal at boundary" =
    eval_float (cond ~condition:(gte (f #2.s) (f #2.s)) ~then_:(f #10.s) ~else_:(f #20.s));
    [%expect {| 10 |}]
  ;;

  let%expect_test "cond with and" =
    eval_float (cond ~condition:(and_ (b true) (b false)) ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| 2 |}]
  ;;

  let%expect_test "cond with or" =
    eval_float (cond ~condition:(or_ (b true) (b false)) ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| 1 |}]
  ;;

  let%expect_test "cond with xor (true xor true = false)" =
    eval_float (cond ~condition:(xor (b true) (b true)) ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| 2 |}]
  ;;

  let%expect_test "cond with xor (true xor false = true)" =
    eval_float (cond ~condition:(xor (b true) (b false)) ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| 1 |}]
  ;;

  let%expect_test "nested conditional condition" =
    (* if (1 < 2) && (3 > 2) then 10 else 20 *)
    eval_float
      (cond
         ~condition:(and_ (lt (f #1.s) (f #2.s)) (gt (f #3.s) (f #2.s)))
         ~then_:(f #10.s)
         ~else_:(f #20.s));
    [%expect {| 10 |}]
  ;;

  let%expect_test "nested cond (cond inside then-branch)" =
    eval_float
      (cond
         ~condition:(b true)
         ~then_:(cond ~condition:(b false) ~then_:(f #1.s) ~else_:(f #42.s))
         ~else_:(f #100.s));
    [%expect {| 42 |}]
  ;;

  let%expect_test "float variable" =
    eval_float coord_x;
    [%expect {| 1 |}]
  ;;

  let%expect_test "multiple bound variables" =
    let v = add coord_y coord_x in
    eval_float (add (f #1.s) v);
    [%expect {| 3 |}]
  ;;

  let%expect_test "top-level bool expression " =
    eval_bool (b true);
    [%expect {| true |}]
  ;;

  let%expect_test "top-level comparison " =
    eval_bool (lt (f #1.s) (f #2.s));
    [%expect {| true |}]
  ;;
end

module _ = Make_tests (Expr_tree_eval.Single)
module _ = Make_tests (Expr_graph_eval.Single)
module _ = Make_tests (Expr_graph_batch_eval.Single)

(* Error-behavior tests specific to the tree evaluator (the graph evaluator does not
   produce errors for unbound variables; it silently returns zero). *)
module Tree_eval_error_tests = struct
  module Implementation = Expr_tree_eval.Single

  let default_env t =
    let add_var name value map =
      match Implementation.lookup_variable t name with
      | idx -> Map.set map ~key:idx ~data:value
      | exception _ -> map
    in
    Map.empty (module Implementation.Variable_idx)
    |> add_var "b" (Value.Boxed.T (Value.of_bool true))
  ;;

  let eval_float tree =
    let t = Implementation.of_tree tree in
    let value =
      Or_error.try_with (fun () ->
        Value.box
          (Implementation.run
             ~vars:(default_env t)
             ~oracles:(Map.empty (module Oracle.Key))
             ~x:#1.0s
             ~y:#1.0s
             t))
    in
    match value with
    | Ok v -> v |> Value.unbox |> Value.to_float |> Float32_u.sexp_of_t |> print_s
    | Error e -> print_s (Error.sexp_of_t e)
  ;;

  let%expect_test "unbound float variable" =
    let v = ok (Expr_tree.var ~loc:here "sdf" Float) in
    eval_float v;
    [%expect {| ("unbound variable" (name sdf) (loc :0:-1)) |}]
  ;;

  let%expect_test "unbound variable inside arithmetic propagates error" =
    let v = ok (Expr_tree.var ~loc:here "sdf" Float) in
    eval_float (add (f #1.s) v);
    [%expect {| ("unbound variable" (name sdf) (loc :0:-1)) |}]
  ;;

  let%expect_test "unbound bool variable inside cond" =
    let v = ok (Expr_tree.var ~loc:here "c" Bool) in
    eval_float (cond ~condition:v ~then_:(f #1.s) ~else_:(f #2.s));
    [%expect {| ("unbound variable" (name c) (loc :0:-1)) |}]
  ;;
end
