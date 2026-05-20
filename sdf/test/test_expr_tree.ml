open! Core
open Sdf

let here = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn
let f x = ok (Expr_tree.float_literal ~loc:here x)
let b x = ok (Expr_tree.bool_literal ~loc:here x)
let add a b = ok (Expr_tree.add ~loc:here a b)
let sub a b = ok (Expr_tree.sub ~loc:here a b)
let mul a b = ok (Expr_tree.mul ~loc:here a b)
let div a b = ok (Expr_tree.div ~loc:here a b)
let lt a b = ok (Expr_tree.lt ~loc:here a b)
let gt a b = ok (Expr_tree.gt ~loc:here a b)
let lte a b = ok (Expr_tree.lte ~loc:here a b)
let gte a b = ok (Expr_tree.gte ~loc:here a b)
let and_ a b = ok (Expr_tree.and_ ~loc:here a b)
let or_ a b = ok (Expr_tree.or_ ~loc:here a b)
let xor a b = ok (Expr_tree.xor ~loc:here a b)
let cond ~condition ~then_ ~else_ = ok (Expr_tree.cond ~loc:here ~condition ~then_ ~else_)
let eval t = print_s [%sexp (Expr_tree_eval.eval t : float Or_error.t)]

let%expect_test "float literal" =
  eval (f 3.14);
  [%expect {| (Ok 3.14) |}]
;;

let%expect_test "addition" =
  eval (add (f 1.) (f 2.));
  [%expect {| (Ok 3) |}]
;;

let%expect_test "subtraction" =
  eval (sub (f 5.) (f 3.));
  [%expect {| (Ok 2) |}]
;;

let%expect_test "multiplication" =
  eval (mul (f 4.) (f 2.5));
  [%expect {| (Ok 10) |}]
;;

let%expect_test "division" =
  eval (div (f 10.) (f 4.));
  [%expect {| (Ok 2.5) |}]
;;

let%expect_test "division by zero produces infinity" =
  eval (div (f 1.) (f 0.));
  [%expect {| (Ok INF) |}]
;;

let%expect_test "zero divided by zero is NaN" =
  eval (div (f 0.) (f 0.));
  [%expect {| (Ok NAN) |}]
;;

let%expect_test "nested arithmetic respects left-to-right composition" =
  (* (1 + 2) * (3 - 0.5) = 7.5 *)
  eval (mul (add (f 1.) (f 2.)) (sub (f 3.) (f 0.5)));
  [%expect {| (Ok 7.5) |}]
;;

let%expect_test "negative results" =
  eval (sub (f 1.) (f 4.));
  [%expect {| (Ok -3) |}]
;;

let%expect_test "cond selects then-branch when true" =
  eval (cond ~condition:(b true) ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Ok 1) |}]
;;

let%expect_test "cond selects else-branch when false" =
  eval (cond ~condition:(b false) ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Ok 2) |}]
;;

let%expect_test "cond with less-than" =
  eval (cond ~condition:(lt (f 1.) (f 2.)) ~then_:(f 10.) ~else_:(f 20.));
  [%expect {| (Ok 10) |}]
;;

let%expect_test "cond with greater-than (false)" =
  eval (cond ~condition:(gt (f 1.) (f 2.)) ~then_:(f 10.) ~else_:(f 20.));
  [%expect {| (Ok 20) |}]
;;

let%expect_test "cond with less-than-or-equal at boundary" =
  eval (cond ~condition:(lte (f 2.) (f 2.)) ~then_:(f 10.) ~else_:(f 20.));
  [%expect {| (Ok 10) |}]
;;

let%expect_test "cond with greater-than-or-equal at boundary" =
  eval (cond ~condition:(gte (f 2.) (f 2.)) ~then_:(f 10.) ~else_:(f 20.));
  [%expect {| (Ok 10) |}]
;;

let%expect_test "cond with and" =
  eval (cond ~condition:(and_ (b true) (b false)) ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Ok 2) |}]
;;

let%expect_test "cond with or" =
  eval (cond ~condition:(or_ (b true) (b false)) ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Ok 1) |}]
;;

let%expect_test "cond with xor (true xor true = false)" =
  eval (cond ~condition:(xor (b true) (b true)) ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Ok 2) |}]
;;

let%expect_test "cond with xor (true xor false = true)" =
  eval (cond ~condition:(xor (b true) (b false)) ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Ok 1) |}]
;;

let%expect_test "nested conditional condition" =
  (* if (1 < 2) && (3 > 2) then 10 else 20 *)
  eval
    (cond
       ~condition:(and_ (lt (f 1.) (f 2.)) (gt (f 3.) (f 2.)))
       ~then_:(f 10.)
       ~else_:(f 20.));
  [%expect {| (Ok 10) |}]
;;

let%expect_test "nested cond (cond inside then-branch)" =
  eval
    (cond
       ~condition:(b true)
       ~then_:(cond ~condition:(b false) ~then_:(f 1.) ~else_:(f 42.))
       ~else_:(f 100.));
  [%expect {| (Ok 42) |}]
;;

let%expect_test "unbound float variable" =
  let v = ok (Expr_tree.var ~loc:here "x" Float) in
  eval v;
  [%expect {| (Error ("unbound variable" (name x) (loc :0:-1))) |}]
;;

let%expect_test "unbound variable inside arithmetic propagates error" =
  let v = ok (Expr_tree.var ~loc:here "y" Float) in
  eval (add (f 1.) v);
  [%expect {| (Error ("unbound variable" (name y) (loc :0:-1))) |}]
;;

let%expect_test "unbound bool variable inside cond" =
  let v = ok (Expr_tree.var ~loc:here "c" Bool) in
  eval (cond ~condition:v ~then_:(f 1.) ~else_:(f 2.));
  [%expect {| (Error ("unbound variable" (name c) (loc :0:-1))) |}]
;;

let%expect_test "top-level bool expression is rejected" =
  eval (b true);
  [%expect
    {| (Error ("top-level expression has type bool, expected float" (loc :0:-1))) |}]
;;

let%expect_test "top-level comparison is rejected" =
  eval (lt (f 1.) (f 2.));
  [%expect
    {| (Error ("top-level expression has type bool, expected float" (loc :0:-1))) |}]
;;
