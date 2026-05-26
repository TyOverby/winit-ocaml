open! Core
open Sdf
open Helpers

let loc = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn

(* [nf x] builds a negative float literal: [nf #1.0s] is [-1.0s] *)
let nf x = f Float32_u.(neg x)

let value_failwith msg =
  if true then failwith msg;
  Value.of_bool false
;;

(* Well-typed expression tree generators.
   The derived [quickcheck] on [Expr_tree.t] is not exported (the types are private
   in the .mli) and would produce ill-typed trees anyway (e.g. [Add] of two bools).
   These generators produce only correctly-typed trees by construction, using the
   smart constructors. *)

let rec gen_float_expr ~depth =
  let open Quickcheck.Generator.Let_syntax in
  let leaf =
    Quickcheck.Generator.union
      [ (let%map f = Float.quickcheck_generator in
         ok (Expr_tree.float_literal ~loc (Float32_u.of_float f)))
      ; return (ok (Expr_tree.var ~loc "x" Float))
      ; return (ok (Expr_tree.var ~loc "y" Float))
      ]
  in
  if depth <= 0
  then leaf
  else
    let d = depth - 1 in
    let binop op =
      let%bind a = gen_float_expr ~depth:d in
      let%map b = gen_float_expr ~depth:d in
      ok (op ~loc a b)
    in
    Quickcheck.Generator.union
      [ leaf
      ; binop Expr_tree.add
      ; binop Expr_tree.sub
      ; binop Expr_tree.mul
      ; binop Expr_tree.div
      ; (let%bind condition = gen_bool_expr ~depth:d in
         let%bind then_ = gen_float_expr ~depth:d in
         let%map else_ = gen_float_expr ~depth:d in
         ok (Expr_tree.cond ~loc ~condition ~then_ ~else_))
      ]

and gen_bool_expr ~depth =
  let open Quickcheck.Generator.Let_syntax in
  let leaf =
    let%map b = Bool.quickcheck_generator in
    ok (Expr_tree.bool_literal ~loc b)
  in
  if depth <= 0
  then leaf
  else
    let d = depth - 1 in
    let float_cmp op =
      let%bind a = gen_float_expr ~depth:d in
      let%map b = gen_float_expr ~depth:d in
      ok (op ~loc a b)
    in
    let bool_binop op =
      let%bind a = gen_bool_expr ~depth:d in
      let%map b = gen_bool_expr ~depth:d in
      ok (op ~loc a b)
    in
    Quickcheck.Generator.union
      [ leaf
      ; float_cmp Expr_tree.lt
      ; float_cmp Expr_tree.gt
      ; float_cmp Expr_tree.lte
      ; float_cmp Expr_tree.gte
      ; bool_binop Expr_tree.and_
      ; bool_binop Expr_tree.or_
      ; bool_binop Expr_tree.xor
      ; (let%bind condition = gen_bool_expr ~depth:d in
         let%bind then_ = gen_bool_expr ~depth:d in
         let%map else_ = gen_bool_expr ~depth:d in
         ok (Expr_tree.cond ~loc ~condition ~then_ ~else_))
      ]
;;

let gen_expr ~depth (type_ : Expr_tree.Type.t) =
  match type_ with
  | Float -> gen_float_expr ~depth
  | Bool -> gen_bool_expr ~depth
;;

(* --- Shared bisimulation infrastructure --- *)

let make_env ~x ~y =
  String.Map.of_alist_exn
    [ "x", Value.Boxed.T (Value.of_float (Float32_u.of_float x))
    ; "y", Value.Boxed.T (Value.of_float (Float32_u.of_float y))
    ]
;;

let eval_with_graph tree ~x ~y =
  let ~var_mapping, ~run = Expr_graph_eval.run_tree tree in
  let variables = Value.Array.create ~len:(Hashtbl.length var_mapping) in
  Hashtbl.iteri var_mapping ~f:(fun ~key ~data:idx ->
    let value =
      match key with
      | "x" -> Value.of_float (Float32_u.of_float x)
      | "y" -> Value.of_float (Float32_u.of_float y)
      | other -> value_failwith ("unexpected variable: " ^ other)
    in
    Value.Array.set variables idx value);
  run ~variables
;;

let format_value v (type_ : Expr_tree.Type.t) =
  match type_ with
  | Float -> Float32_u.to_string (Value.to_float v)
  | Bool -> Bool.to_string (Value.to_bool v)
;;

(** Print the results of both evaluators. On mismatch, prints both values. *)
let check tree ~x ~y =
  let graph_result = eval_with_graph tree ~x ~y in
  match Expr_tree_eval.eval ~env:(make_env ~x ~y) tree with
  | Error err -> printf !"tree eval error: %{Error#hum}\n" err
  | Ok tree_value ->
    let type_ = tree.type_ in
    printf "%s\n" (format_value tree_value type_);
    if not (Value.equal tree_value graph_result)
    then printf "MISMATCH: graph=%s\n" (format_value graph_result type_)
;;

(** Assert bisimulation holds. Raises on mismatch. For use in quickcheck. *)
let assert_bisimulation tree ~x ~y =
  let graph_result = eval_with_graph tree ~x ~y in
  match Expr_tree_eval.eval ~env:(make_env ~x ~y) tree with
  | Error err -> Error.raise err
  | Ok tree_value ->
    if not (Value.equal tree_value graph_result)
    then (
      let type_ = tree.type_ in
      let ~instructions, ~final_register, ~register_count:_, ~var_mapping:_ =
        Expr_graph.from_tree tree
      in
      let graph_asm =
        sprintf
          "result: $%d\n%s"
          final_register
          (Expr_graph.pp_instructions instructions)
      in
      Error.raise_s
        [%message
          "bisimulation failure"
            ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
            ~tree_result:(format_value tree_value type_ : string)
            ~graph_result:(format_value graph_result type_ : string)
            ~graph_asm:(graph_asm : string)
            ~x:(x : float)
            ~y:(y : float)])
;;

(* --- Hardcoded bisimulation tests --- *)

let%expect_test "literal" =
  check (f #1.0s) ~x:0.0 ~y:0.0;
  [%expect {| 1. |}]
;;

let%expect_test "variable" =
  check (var "x" Float) ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "simple cond, true branch" =
  check (cond ~condition:(b true) ~then_:(f #1.0s) ~else_:(f #2.0s)) ~x:0.0 ~y:0.0;
  [%expect {| 1. |}]
;;

let%expect_test "simple cond, false branch" =
  check (cond ~condition:(b false) ~then_:(f #1.0s) ~else_:(f #2.0s)) ~x:0.0 ~y:0.0;
  [%expect {| 2. |}]
;;

let%expect_test "cond with var in then branch" =
  check
    (cond ~condition:(b true) ~then_:(var "x" Float) ~else_:(f #999.0s))
    ~x:42.0
    ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "nested cond in else, taking then branch" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:(var "x" Float)
      ~else_:(cond ~condition:(b true) ~then_:(f #1.0s) ~else_:(f #2.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "nested cond in else, taking else branch" =
  let tree =
    cond
      ~condition:(b false)
      ~then_:(var "x" Float)
      ~else_:(cond ~condition:(b true) ~then_:(f #1.0s) ~else_:(f #2.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 1. |}]
;;

let%expect_test "computed condition with nested else cond" =
  let tree =
    cond
      ~condition:(lt (var "x" Float) (f #0.0s))
      ~then_:(f #1.0s)
      ~else_:(cond ~condition:(b true) ~then_:(f #2.0s) ~else_:(f #3.0s))
  in
  check tree ~x:5.0 ~y:0.0;
  [%expect {| 2. |}]
;;

let%expect_test "shared var across both cond branches" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:(var "x" Float)
      ~else_:(add (var "x" Float) (f #1.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "shared var with nested cond in else" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:(var "x" Float)
      ~else_:
        (cond
           ~condition:(b true)
           ~then_:(mul (var "x" Float) (f #2.0s))
           ~else_:(f #3.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "computed condition, var in then, nested cond with ops in else" =
  let tree =
    cond
      ~condition:(lt (f #1.0s) (f #2.0s))
      ~then_:(var "x" Float)
      ~else_:
        (cond
           ~condition:(b true)
           ~then_:(mul (nf #1.0s) (nf #1.0s))
           ~else_:(f #999.0s))
  in
  check tree ~x:7.0 ~y:0.0;
  [%expect {| 7. |}]
;;

let%expect_test "div by zero in else branch, taking then branch" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:(var "x" Float)
      ~else_:(div (var "y" Float) (f #0.0s))
  in
  check tree ~x:7.0 ~y:1.0;
  [%expect {| 7. |}]
;;

let%expect_test "original quickcheck failure - simplified" =
  (* From the quickcheck counterexample: the outer cond's condition is true,
     so we should get the then branch (x), but the graph evaluator returned
     +infinity from the else branch. *)
  let tree =
    cond
      ~condition:(lt (add (nf #0.0s) (div (var "x" Float) (var "x" Float)))
                     (sub (div (var "y" Float) (f #0.0s))
                        (cond ~condition:(b false) ~then_:(var "x" Float) ~else_:(f #1.45220733s))))
      ~then_:(var "x" Float)
      ~else_:
        (cond
           ~condition:(b true)
           ~then_:
             (mul
                (div (nf #1.26763916s) (var "y" Float))
                (cond ~condition:(b false) ~then_:(nf #0.0s) ~else_:(f Float32_u.(neg_infinity ()))))
           ~else_:
             (add
                (div (var "y" Float) (nf #0.0s))
                (mul (var "x" Float) (nf #0.0s))))
  in
  check tree ~x:(-0.267355561256) ~y:2.9582283945787943e-31;
  [%expect {| -0.267355561 |}]
;;

(* Regression test: CSE must distinguish -0.0 from +0.0.
   An expression using both -0.0 and +0.0 as literals must not have them
   merged by CSE, since they produce different results via division
   (1/+0 = +inf, 1/-0 = -inf). *)

let pp tree =
  let ~instructions, ~final_register, ~register_count:_, ~var_mapping:_ =
    Expr_graph.from_tree tree
  in
  printf "result: $%d\n" final_register;
  print_string (Expr_graph.pp_instructions instructions)
;;

let%expect_test "CSE distinguishes -0.0 and +0.0: evaluation" =
  let tree =
    cond
      ~condition:(lt (add (nf #0.0s) (f #1.0s)) (div (var "y" Float) (f #0.0s)))
      ~then_:(f #1.0s)
      ~else_:(f #2.0s)
  in
  (* y=1, so div(y, +0) = +inf, and lt(1, +inf) = true → should return 1 *)
  check tree ~x:0.0 ~y:1.0;
  [%expect {| 1. |}]
;;

let%expect_test "CSE distinguishes -0.0 and +0.0: graph has separate registers" =
  let tree =
    cond
      ~condition:
        (lt
           (add (nf #0.0s) (div (var "x" Float) (var "x" Float)))
           (sub (div (var "y" Float) (f #0.0s)) (f #1.45220733s)))
      ~then_:(f #1.0s)
      ~else_:(f #2.0s)
  in
  pp tree;
  [%expect {|
    result: $0
    $3 <- -0.
    $5 <- var(0)
    $4 <- div $5 $5
    $2 <- add $3 $4
    $8 <- var(1)
    $9 <- 0.
    $7 <- div $8 $9
    $10 <- 1.45220733
    $6 <- sub $7 $10
    $1 <- lt $2 $6
    $0 <- cond $1
      then:
        $11 <- 1.
        $0 <- $11
      else:
        $12 <- 2.
        $0 <- $12
    |}]
;;

(* --- Quickcheck bisimulation test --- *)

let gen_test_case =
  let open Quickcheck.Generator.Let_syntax in
  let%bind depth = Int.gen_incl 0 4 in
  let%bind type_ =
    Quickcheck.Generator.of_list [ Expr_tree.Type.Bool; Float ]
  in
  let%bind tree = gen_expr ~depth type_ in
  let%bind x = Float.quickcheck_generator in
  let%map y = Float.quickcheck_generator in
  tree, x, y
;;

let%test_unit "bisimulation: tree and graph evaluators produce identical results" =
  Quickcheck.test
    gen_test_case
    ~sexp_of:[%sexp_of: Expr_tree.t * float * float]
    ~f:(fun (tree, x, y) -> assert_bisimulation tree ~x ~y)
;;
