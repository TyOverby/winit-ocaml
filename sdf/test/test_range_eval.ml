open! Core
open Sdf
open Helpers

(* Shared infrastructure *)

let empty_vars = Map.empty (module Expr_graph_range_eval.Variable_idx)
let empty_oracles = Map.empty (module Oracle.Key)

(* Build a range evaluator and call [run] for Float-typed trees. *)
let eval_range tree ~x_lo ~x_hi ~y_lo ~y_hi =
  let t = Expr_graph_range_eval.of_tree tree in
  let x = Interval.create ~lo:(Float32_u.of_float x_lo) ~hi:(Float32_u.of_float x_hi) in
  let y = Interval.create ~lo:(Float32_u.of_float y_lo) ~hi:(Float32_u.of_float y_hi) in
  Expr_graph_range_eval.run t ~vars:empty_vars ~oracles:empty_oracles ~x ~y
;;

(* Build a range evaluator and call [run_bool] for Bool-typed trees. *)
let eval_range_bool tree ~x_lo ~x_hi ~y_lo ~y_hi =
  let t = Expr_graph_range_eval.of_tree tree in
  let x = Interval.create ~lo:(Float32_u.of_float x_lo) ~hi:(Float32_u.of_float x_hi) in
  let y = Interval.create ~lo:(Float32_u.of_float y_lo) ~hi:(Float32_u.of_float y_hi) in
  Expr_graph_range_eval.run_bool t ~vars:empty_vars ~oracles:empty_oracles ~x ~y
;;

(* Evaluate [tree] (Float-typed) with the scalar evaluator at a single point. *)
let eval_scalar tree ~x ~y =
  let t = Expr_graph_eval.Single.of_tree tree in
  let v =
    Expr_graph_eval.Single.run
      t
      ~vars:(Map.empty (module Expr_graph_eval.Single.Variable_idx))
      ~oracles:empty_oracles
      ~x:(Float32_u.of_float x)
      ~y:(Float32_u.of_float y)
  in
  Value.to_float v
;;

(* Evaluate [tree] (Bool-typed) with the scalar evaluator at a single point. *)
let eval_scalar_bool tree ~x ~y =
  let t = Expr_graph_eval.Single.of_tree tree in
  let v =
    Expr_graph_eval.Single.run
      t
      ~vars:(Map.empty (module Expr_graph_eval.Single.Variable_idx))
      ~oracles:empty_oracles
      ~x:(Float32_u.of_float x)
      ~y:(Float32_u.of_float y)
  in
  Value.to_bool v
;;

(* Sample the scalar evaluator on a 3x3 grid and check containment. *)
let check_containment_grid tree ~x_lo ~x_hi ~y_lo ~y_hi interval =
  let xs = [ x_lo; (x_lo +. x_hi) /. 2.0; x_hi ] in
  let ys = [ y_lo; (y_lo +. y_hi) /. 2.0; y_hi ] in
  List.iter xs ~f:(fun x ->
    List.iter ys ~f:(fun y ->
      let scalar = eval_scalar tree ~x ~y in
      if not (Interval.contains interval scalar)
      then
        Error.raise_s
          [%message
            "containment violation"
              ~x:(x : float)
              ~y:(y : float)
              ~scalar:(Float32_u.to_string scalar : string)
              ~interval:(Interval.to_string interval : string)]))
;;

let check_containment_grid_bool tree ~x_lo ~x_hi ~y_lo ~y_hi interval =
  let xs = [ x_lo; (x_lo +. x_hi) /. 2.0; x_hi ] in
  let ys = [ y_lo; (y_lo +. y_hi) /. 2.0; y_hi ] in
  List.iter xs ~f:(fun x ->
    List.iter ys ~f:(fun y ->
      let scalar = eval_scalar_bool tree ~x ~y in
      if not (Interval.Bool.contains interval scalar)
      then
        Error.raise_s
          [%message
            "bool containment violation"
              ~x:(x : float)
              ~y:(y : float)
              ~scalar:(Bool.to_string scalar : string)
              ~interval:(Interval.Bool.to_string interval : string)]))
;;

(* ===== Per-primitive expect tests ===== *)

let%expect_test "float_literal" =
  let tree = f #3.14s in
  let interval = eval_range tree ~x_lo:(-100.0) ~x_hi:100.0 ~y_lo:(-100.0) ~y_hi:100.0 in
  print_string (Interval.to_string interval);
  [%expect {| [3.1400001, 3.1400001] |}];
  check_containment_grid
    tree
    ~x_lo:(-100.0)
    ~x_hi:100.0
    ~y_lo:(-100.0)
    ~y_hi:100.0
    interval
;;

let%expect_test "bool_literal true" =
  let tree = b true in
  let interval =
    eval_range_bool tree ~x_lo:(-100.0) ~x_hi:100.0 ~y_lo:(-100.0) ~y_hi:100.0
  in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool
    tree
    ~x_lo:(-100.0)
    ~x_hi:100.0
    ~y_lo:(-100.0)
    ~y_hi:100.0
    interval
;;

let%expect_test "bool_literal false" =
  let tree = b false in
  let interval =
    eval_range_bool tree ~x_lo:(-100.0) ~x_hi:100.0 ~y_lo:(-100.0) ~y_hi:100.0
  in
  print_string (Interval.Bool.to_string interval);
  [%expect {| false |}];
  check_containment_grid_bool
    tree
    ~x_lo:(-100.0)
    ~x_hi:100.0
    ~y_lo:(-100.0)
    ~y_hi:100.0
    interval
;;

let%expect_test "coord_x" =
  let tree = coord_x in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:(-10.0) ~y_hi:10.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 5.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:(-10.0) ~y_hi:10.0 interval
;;

let%expect_test "coord_y" =
  let tree = coord_y in
  let interval = eval_range tree ~x_lo:(-10.0) ~x_hi:10.0 ~y_lo:2.0 ~y_hi:8.0 in
  print_string (Interval.to_string interval);
  [%expect {| [2., 8.] |}];
  check_containment_grid tree ~x_lo:(-10.0) ~x_hi:10.0 ~y_lo:2.0 ~y_hi:8.0 interval
;;

let%expect_test "add" =
  (* x in [1,2], y in [10,20]: x+y should be [11,22] *)
  let tree = add coord_x coord_y in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:10.0 ~y_hi:20.0 in
  print_string (Interval.to_string interval);
  [%expect {| [11., 22.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:10.0 ~y_hi:20.0 interval
;;

let%expect_test "sub" =
  (* x in [3,5], y in [1,2]: x-y should be [1,4] *)
  let tree = sub coord_x coord_y in
  let interval = eval_range tree ~x_lo:3.0 ~x_hi:5.0 ~y_lo:1.0 ~y_hi:2.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 4.] |}];
  check_containment_grid tree ~x_lo:3.0 ~x_hi:5.0 ~y_lo:1.0 ~y_hi:2.0 interval
;;

let%expect_test "mul: both positive" =
  (* x in [2,3], y in [4,5]: x*y should be [8,15] *)
  let tree = mul coord_x coord_y in
  let interval = eval_range tree ~x_lo:2.0 ~x_hi:3.0 ~y_lo:4.0 ~y_hi:5.0 in
  print_string (Interval.to_string interval);
  [%expect {| [8., 15.] |}];
  check_containment_grid tree ~x_lo:2.0 ~x_hi:3.0 ~y_lo:4.0 ~y_hi:5.0 interval
;;

let%expect_test "mul: spanning zero" =
  (* x in [-1,1], y in [-1,1]: x*y spans [-1,1] *)
  let tree = mul coord_x coord_y in
  let interval = eval_range tree ~x_lo:(-1.0) ~x_hi:1.0 ~y_lo:(-1.0) ~y_hi:1.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-1., 1.] |}];
  check_containment_grid tree ~x_lo:(-1.0) ~x_hi:1.0 ~y_lo:(-1.0) ~y_hi:1.0 interval
;;

let%expect_test "div: denominator positive" =
  (* x in [4,8], y in [2,4]: x/y in [1,4] *)
  let tree = div coord_x coord_y in
  let interval = eval_range tree ~x_lo:4.0 ~x_hi:8.0 ~y_lo:2.0 ~y_hi:4.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 4.] |}];
  check_containment_grid tree ~x_lo:4.0 ~x_hi:8.0 ~y_lo:2.0 ~y_hi:4.0 interval
;;

let%expect_test "div: denominator spans zero => unbounded both ways" =
  (* y in [-1,1] contains zero: quotients blow up on both sides of it (division is total,
     x / 0 = 0, so 0 is also included — but the hull is all of [-inf, inf]). *)
  let tree = div coord_x coord_y in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:(-1.0) ~y_hi:1.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-inf, inf] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:(-1.0) ~y_hi:1.0 interval
;;

let%expect_test "div: denominator touches zero from one side => half-bounded" =
  (* y in [0,4] with x in [1,2]: quotients are {0} (from y = 0) plus [1/4, +inf). *)
  let tree = div coord_x coord_y in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:0.0 ~y_hi:4.0 in
  print_string (Interval.to_string interval);
  [%expect {| [0., inf] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:0.0 ~y_hi:4.0 interval
;;

let%expect_test "div: denominator exactly zero => zero" =
  let tree = div coord_x (f #0.0s) in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [0., 0.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "div: min recovers a bound below a division by a zero-spanning range" =
  (* The motivation for total division: the divide yields [-inf, inf] rather than top, so
     a downstream min (the SDF union combinator) can still recover an upper bound. *)
  let tree = min (div coord_x coord_y) (f #7.0s) in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:(-1.0) ~y_hi:1.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-inf, 7.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:(-1.0) ~y_hi:1.0 interval
;;

let%expect_test "sqrt: all positive" =
  (* x in [1,4]: sqrt(x) in [1,2] *)
  let tree = sqrt coord_x in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:4.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 2.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:4.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sqrt: clamps negatives to zero" =
  (* x in [-1,4]: sqrt is total (sqrt of a negative is 0), so the range is [0, 2] *)
  let tree = sqrt coord_x in
  let interval = eval_range tree ~x_lo:(-1.0) ~x_hi:4.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [0., 2.] |}];
  check_containment_grid tree ~x_lo:(-1.0) ~x_hi:4.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sqrt: entirely negative => zero" =
  let tree = sqrt coord_x in
  let interval = eval_range tree ~x_lo:(-4.0) ~x_hi:(-1.0) ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [0., 0.] |}];
  check_containment_grid tree ~x_lo:(-4.0) ~x_hi:(-1.0) ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "abs: all positive" =
  let tree = abs coord_x in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 5.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "abs: all negative" =
  let tree = abs coord_x in
  let interval = eval_range tree ~x_lo:(-5.0) ~x_hi:(-1.0) ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 5.] |}];
  check_containment_grid tree ~x_lo:(-5.0) ~x_hi:(-1.0) ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "abs: spanning zero" =
  (* x in [-3,2]: |x| in [0,3] *)
  let tree = abs coord_x in
  let interval = eval_range tree ~x_lo:(-3.0) ~x_hi:2.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [0., 3.] |}];
  check_containment_grid tree ~x_lo:(-3.0) ~x_hi:2.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "neg" =
  (* x in [1,3]: -x in [-3,-1] *)
  let tree = neg coord_x in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-3., -1.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sign: all positive" =
  let tree = sign coord_x in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 1.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sign: all negative" =
  let tree = sign coord_x in
  let interval = eval_range tree ~x_lo:(-5.0) ~x_hi:(-1.0) ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-1., -1.] |}];
  check_containment_grid tree ~x_lo:(-5.0) ~x_hi:(-1.0) ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sign: spanning zero" =
  (* sign spans [-1,1] when lo < 0 < hi *)
  let tree = sign coord_x in
  let interval = eval_range tree ~x_lo:(-3.0) ~x_hi:3.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-1., 1.] |}];
  check_containment_grid tree ~x_lo:(-3.0) ~x_hi:3.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sin: basic interval" =
  (* x in [0, pi/2]: sin(x) in [0, 1]; endpoints padded by ~2e-5 *)
  let tree = sin coord_x in
  let half_pi = Float.pi /. 2.0 in
  let interval = eval_range tree ~x_lo:0.0 ~x_hi:half_pi ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-1.99999995e-05, 1.] |}];
  check_containment_grid tree ~x_lo:0.0 ~x_hi:half_pi ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "sin: interval wider than 2pi => [-1,1]" =
  let tree = sin coord_x in
  let interval = eval_range tree ~x_lo:0.0 ~x_hi:7.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-1., 1.] |}];
  check_containment_grid tree ~x_lo:0.0 ~x_hi:7.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "cos: basic interval" =
  (* x in [0, pi]: cos(x) goes from 1 down to -1; spans cos peak at 0 so hi=1 *)
  let tree = cos coord_x in
  let interval = eval_range tree ~x_lo:0.0 ~x_hi:Float.pi ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [-1., 1.] |}];
  check_containment_grid tree ~x_lo:0.0 ~x_hi:Float.pi ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "cos: interval away from peaks" =
  (* x in [pi/4, 3pi/4]: cos goes from sqrt(2)/2 down to -sqrt(2)/2; no critical point (0
     or 2pi) inside, so endpoints bound it *)
  let tree = cos coord_x in
  let interval =
    eval_range
      tree
      ~x_lo:(Float.pi /. 4.0)
      ~x_hi:(3.0 *. Float.pi /. 4.0)
      ~y_lo:0.0
      ~y_hi:0.0
  in
  print_string (Interval.to_string interval);
  [%expect {| [-0.707126796, 0.707126796] |}];
  check_containment_grid
    tree
    ~x_lo:(Float.pi /. 4.0)
    ~x_hi:(3.0 *. Float.pi /. 4.0)
    ~y_lo:0.0
    ~y_hi:0.0
    interval
;;

let%expect_test "round" =
  (* x in [1.3, 2.7]: round maps to {1.0, 2.0, 3.0}, so interval = [1, 3] *)
  let tree = round coord_x in
  let interval = eval_range tree ~x_lo:1.3 ~x_hi:2.7 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 3.] |}];
  check_containment_grid tree ~x_lo:1.3 ~x_hi:2.7 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "min" =
  (* x in [1,3], y in [2,4]: min(x,y) in [min(1,2), min(3,4)] = [1,3] *)
  let tree = min coord_x coord_y in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:2.0 ~y_hi:4.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 3.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:2.0 ~y_hi:4.0 interval
;;

let%expect_test "max" =
  (* x in [1,3], y in [2,4]: max(x,y) in [max(1,2), max(3,4)] = [2,4] *)
  let tree = max coord_x coord_y in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:2.0 ~y_hi:4.0 in
  print_string (Interval.to_string interval);
  [%expect {| [2., 4.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:2.0 ~y_hi:4.0 interval
;;

let%expect_test "lt: definitely true" =
  (* x in [1,2] < y in [3,4] always *)
  let tree = lt coord_x coord_y in
  let interval = eval_range_bool tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:3.0 ~y_hi:4.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:3.0 ~y_hi:4.0 interval
;;

let%expect_test "lt: definitely false" =
  (* x in [3,4] < y in [1,2] never *)
  let tree = lt coord_x coord_y in
  let interval = eval_range_bool tree ~x_lo:3.0 ~x_hi:4.0 ~y_lo:1.0 ~y_hi:2.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| false |}];
  check_containment_grid_bool tree ~x_lo:3.0 ~x_hi:4.0 ~y_lo:1.0 ~y_hi:2.0 interval
;;

let%expect_test "lt: overlapping => maybe" =
  let tree = lt coord_x coord_y in
  let interval = eval_range_bool tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:3.0 ~y_hi:7.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| maybe |}];
  check_containment_grid_bool tree ~x_lo:1.0 ~x_hi:5.0 ~y_lo:3.0 ~y_hi:7.0 interval
;;

let%expect_test "gt: definitely true" =
  let tree = gt coord_x coord_y in
  let interval = eval_range_bool tree ~x_lo:5.0 ~x_hi:10.0 ~y_lo:1.0 ~y_hi:3.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:5.0 ~x_hi:10.0 ~y_lo:1.0 ~y_hi:3.0 interval
;;

let%expect_test "lte: definitely true" =
  let tree = lte coord_x coord_y in
  let interval = eval_range_bool tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:3.0 ~y_hi:5.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:3.0 ~y_hi:5.0 interval
;;

let%expect_test "gte: definitely true" =
  let tree = gte coord_x coord_y in
  let interval = eval_range_bool tree ~x_lo:5.0 ~x_hi:10.0 ~y_lo:2.0 ~y_hi:5.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:5.0 ~x_hi:10.0 ~y_lo:2.0 ~y_hi:5.0 interval
;;

let%expect_test "and_: both true" =
  let tree = and_ (b true) (b true) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 interval
;;

let%expect_test "and_: one false" =
  let tree = and_ (b true) (b false) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| false |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 interval
;;

let%expect_test "and_: maybe and true => maybe" =
  (* x < 5 is maybe over [0,10], so (x < 5) && true = maybe *)
  let tree = and_ (lt coord_x (f #5.0s)) (b true) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:10.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| maybe |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:10.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "or_: one true" =
  let tree = or_ (b false) (b true) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 interval
;;

let%expect_test "or_: both false" =
  let tree = or_ (b false) (b false) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| false |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 interval
;;

let%expect_test "xor: true xor false = true" =
  let tree = xor (b true) (b false) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| true |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 interval
;;

let%expect_test "xor: true xor true = false" =
  let tree = xor (b true) (b true) in
  let interval = eval_range_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 in
  print_string (Interval.Bool.to_string interval);
  [%expect {| false |}];
  check_containment_grid_bool tree ~x_lo:0.0 ~x_hi:1.0 ~y_lo:0.0 ~y_hi:1.0 interval
;;

let%expect_test "cond: definitely-true condition" =
  (* condition is true everywhere: result = then_ = x *)
  let tree = cond ~condition:(b true) ~then_:coord_x ~else_:(f #999.0s) in
  let interval = eval_range tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [1., 3.] |}];
  check_containment_grid tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "cond: definitely-false condition" =
  let tree = cond ~condition:(b false) ~then_:(f #999.0s) ~else_:coord_x in
  let interval = eval_range tree ~x_lo:2.0 ~x_hi:4.0 ~y_lo:0.0 ~y_hi:0.0 in
  print_string (Interval.to_string interval);
  [%expect {| [2., 4.] |}];
  check_containment_grid tree ~x_lo:2.0 ~x_hi:4.0 ~y_lo:0.0 ~y_hi:0.0 interval
;;

let%expect_test "cond: maybe condition => hull of both branches" =
  (* x < 5 is maybe over [0,10]: result is hull of x and y *)
  let tree = cond ~condition:(lt coord_x (f #5.0s)) ~then_:coord_x ~else_:coord_y in
  let interval = eval_range tree ~x_lo:0.0 ~x_hi:10.0 ~y_lo:20.0 ~y_hi:30.0 in
  print_string (Interval.to_string interval);
  (* hull of [0,10] and [20,30] = [0,30] *)
  [%expect {| [0., 30.] |}];
  check_containment_grid tree ~x_lo:0.0 ~x_hi:10.0 ~y_lo:20.0 ~y_hi:30.0 interval
;;

(* ===== Oracle (passthrough) range tests ===== *)

(* Range-evaluate a tree that references passthrough oracles (preparing them first,
   following the recipe in test_executor_with_oracle.ml), print the resulting range, and
   check scalar samples at the box corners and center fall inside it. The printing happens
   inside the parallel closure; the [%expect] block sits outside it. *)
let run_oracle_range_test tree ~x_lo ~x_hi ~y_lo ~y_hi =
  let scheduler = Parallel_scheduler.create () in
  Fiber_stack.parallel scheduler ~f:(fun par ->
    let oracles =
      Oracle_dependencies.extract_deps tree
      |> List.join
      |> List.fold
           ~init:(Map.empty (module Oracle.Key))
           ~f:(fun prepared ((name, args) as oracle_key) ->
             assert (String.equal name "passthrough");
             let p =
               Sdf_passthrough_oracle.create args
               |> Sdf_passthrough_oracle.prepare
                    ~par
                    ~trace:(Phase_trace.null ())
                    ~oracles:prepared
                    ~sample_region:(Sample_region.point ~x:#0.0s ~y:#0.0s)
             in
             Map.set prepared ~key:oracle_key ~data:p)
    in
    let t = Expr_graph_range_eval.of_tree tree in
    let x = Interval.create ~lo:(Float32_u.of_float x_lo) ~hi:(Float32_u.of_float x_hi) in
    let y = Interval.create ~lo:(Float32_u.of_float y_lo) ~hi:(Float32_u.of_float y_hi) in
    let interval =
      Expr_graph_range_eval.run
        t
        ~vars:(Map.empty (module Expr_graph_range_eval.Variable_idx))
        ~oracles
        ~x
        ~y
    in
    print_string (Interval.to_string interval);
    (* Scalar samples through the same prepared oracles must land in the range. *)
    let single = Expr_graph_eval.Single.of_tree tree in
    let xs = [ x_lo; (x_lo +. x_hi) /. 2.0; x_hi ] in
    let ys = [ y_lo; (y_lo +. y_hi) /. 2.0; y_hi ] in
    List.iter xs ~f:(fun px ->
      List.iter ys ~f:(fun py ->
        let scalar =
          Expr_graph_eval.Single.run
            single
            ~vars:(Map.empty (module Expr_graph_eval.Single.Variable_idx))
            ~oracles
            ~x:(Float32_u.of_float px)
            ~y:(Float32_u.of_float py)
          |> Value.to_float
        in
        if not (Interval.contains interval scalar)
        then
          Error.raise_s
            [%message
              "oracle containment violation"
                ~x:(px : float)
                ~y:(py : float)
                ~scalar:(Float32_u.to_string scalar : string)
                ~interval:(Interval.to_string interval : string)])))
;;

let%expect_test "oracle: passthrough sample_range flows coordinate ranges through" =
  (* The oracle wraps x + y; the result range must match evaluating x + y directly. *)
  let tree = oracle "passthrough" [ add coord_x coord_y ] in
  run_oracle_range_test tree ~x_lo:1.0 ~x_hi:2.0 ~y_lo:10.0 ~y_hi:20.0;
  [%expect {| [11., 22.] |}]
;;

let%expect_test "oracle: passthrough sample_range through a chained oracle" =
  (* An oracle whose inner tree references another oracle: sample_range must recurse. *)
  let inner = oracle "passthrough" [ mul coord_x (f #2.0s) ] in
  let tree = oracle "passthrough" [ add inner coord_y ] in
  (* 2x + y over x in [1,3], y = 0.5: [2.5, 6.5] *)
  run_oracle_range_test tree ~x_lo:1.0 ~x_hi:3.0 ~y_lo:0.5 ~y_hi:0.5;
  [%expect {| [2.5, 6.5] |}]
;;

(* ===== Quickcheck property test ===== *)

(* Generate a random coordinate box (lo <= hi) per axis. *)
let gen_coord_box =
  let open Quickcheck.Generator.Let_syntax in
  let coord =
    Quickcheck.Generator.union [ Float.gen_incl (-1e6) 1e6; Float.quickcheck_generator ]
  in
  let%bind x1 = coord in
  let%bind x2 = coord in
  let%bind y1 = coord in
  let%map y2 = coord in
  let x_lo = Float.min x1 x2
  and x_hi = Float.max x1 x2
  and y_lo = Float.min y1 y2
  and y_hi = Float.max y1 y2 in
  x_lo, x_hi, y_lo, y_hi
;;

(* Interpolate between lo and hi with t in [0,1]. If the arithmetic overflows (extreme
   float64 inputs make [hi -. lo] infinite), fall back to [lo/2 + hi/2], which is finite
   for finite endpoints and always inside the box. *)
let interp lo hi t =
  let v = lo +. ((hi -. lo) *. t) in
  if Float.is_finite v then v else (lo /. 2.0) +. (hi /. 2.0)
;;

(* Sample 5 random points inside the box plus 4 corners and the center. *)
let box_sample_points x_lo x_hi y_lo y_hi rng =
  let corners =
    [ x_lo, y_lo
    ; x_lo, y_hi
    ; x_hi, y_lo
    ; x_hi, y_hi
    ; interp x_lo x_hi 0.5, interp y_lo y_hi 0.5
    ]
  in
  let random_pts =
    List.init 5 ~f:(fun _ ->
      let tx = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
      let ty = Splittable_random.float rng ~lo:0.0 ~hi:1.0 in
      interp x_lo x_hi tx, interp y_lo y_hi ty)
  in
  corners @ random_pts
;;

let%test_unit "quickcheck: range evaluator contains all scalar float results" =
  Quickcheck.test
    (Quickcheck.Generator.both (Test_bisimulation.gen_float_expr ~depth:4) gen_coord_box)
    ~sexp_of:[%sexp_of: Expr_tree.t * (float * float * float * float)]
    ~trials:Quickcheck_trials.trials
    ~f:(fun (tree, (x_lo, x_hi, y_lo, y_hi)) ->
      (* Skip degenerate / non-finite boxes *)
      if Float.is_finite x_lo
         && Float.is_finite x_hi
         && Float.is_finite y_lo
         && Float.is_finite y_hi
      then (
        let t = Expr_graph_range_eval.of_tree tree in
        let x =
          Interval.create ~lo:(Float32_u.of_float x_lo) ~hi:(Float32_u.of_float x_hi)
        in
        let y =
          Interval.create ~lo:(Float32_u.of_float y_lo) ~hi:(Float32_u.of_float y_hi)
        in
        let interval =
          Expr_graph_range_eval.run t ~vars:empty_vars ~oracles:empty_oracles ~x ~y
        in
        let rng = Splittable_random.of_int 42 in
        let pts = box_sample_points x_lo x_hi y_lo y_hi rng in
        List.iter pts ~f:(fun (px, py) ->
          let scalar = eval_scalar tree ~x:px ~y:py in
          if not (Interval.contains interval scalar)
          then
            Error.raise_s
              [%message
                "range eval: scalar result outside interval"
                  ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
                  ~x_lo:(x_lo : float)
                  ~x_hi:(x_hi : float)
                  ~y_lo:(y_lo : float)
                  ~y_hi:(y_hi : float)
                  ~point_x:(px : float)
                  ~point_y:(py : float)
                  ~scalar:(Float32_u.to_string scalar : string)
                  ~interval:(Interval.to_string interval : string)])))
;;

let%test_unit "quickcheck: range evaluator contains all scalar bool results" =
  Quickcheck.test
    (Quickcheck.Generator.both (Test_bisimulation.gen_bool_expr ~depth:4) gen_coord_box)
    ~sexp_of:[%sexp_of: Expr_tree.t * (float * float * float * float)]
    ~trials:Quickcheck_trials.trials
    ~f:(fun (tree, (x_lo, x_hi, y_lo, y_hi)) ->
      if Float.is_finite x_lo
         && Float.is_finite x_hi
         && Float.is_finite y_lo
         && Float.is_finite y_hi
      then (
        let t = Expr_graph_range_eval.of_tree tree in
        let x =
          Interval.create ~lo:(Float32_u.of_float x_lo) ~hi:(Float32_u.of_float x_hi)
        in
        let y =
          Interval.create ~lo:(Float32_u.of_float y_lo) ~hi:(Float32_u.of_float y_hi)
        in
        let interval =
          Expr_graph_range_eval.run_bool t ~vars:empty_vars ~oracles:empty_oracles ~x ~y
        in
        let rng = Splittable_random.of_int 42 in
        let pts = box_sample_points x_lo x_hi y_lo y_hi rng in
        List.iter pts ~f:(fun (px, py) ->
          let scalar = eval_scalar_bool tree ~x:px ~y:py in
          if not (Interval.Bool.contains interval scalar)
          then
            Error.raise_s
              [%message
                "range eval: scalar bool result outside interval"
                  ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
                  ~x_lo:(x_lo : float)
                  ~x_hi:(x_hi : float)
                  ~y_lo:(y_lo : float)
                  ~y_hi:(y_hi : float)
                  ~point_x:(px : float)
                  ~point_y:(py : float)
                  ~scalar:(Bool.to_string scalar : string)
                  ~interval:(Interval.Bool.to_string interval : string)])))
;;
