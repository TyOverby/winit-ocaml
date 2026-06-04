open! Core
open Sdf
open Helpers

let loc = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn

(* [nf x] builds a negative float literal: [nf #1.0s] is [-1.0s] *)
let nf x = f Float32_u.(neg x)

(* Well-typed expression tree generators. The derived [quickcheck] on [Expr_tree.t] is not
   exported (the types are private in the .mli) and would produce ill-typed trees anyway
   (e.g. [Add] of two bools). These generators produce only correctly-typed trees by
   construction, using the smart constructors. *)

let rec gen_float_expr ~depth =
  let open Quickcheck.Generator.Let_syntax in
  let leaf =
    Quickcheck.Generator.union
      [ (let%map f = Float.quickcheck_generator in
         ok (Expr_tree.float_literal ~loc (Float32_u.of_float f)))
      ; return (ok (Expr_tree.coord_x ~loc))
      ; return (ok (Expr_tree.coord_y ~loc))
      ]
  in
  if depth <= 0
  then leaf
  else (
    let d = depth - 1 in
    let binop op =
      let%bind a = gen_float_expr ~depth:d in
      let%map b = gen_float_expr ~depth:d in
      ok (op ~loc a b)
    in
    let unop op =
      let%map a = gen_float_expr ~depth:d in
      ok (op ~loc a)
    in
    Quickcheck.Generator.union
      [ leaf
      ; binop Expr_tree.add
      ; binop Expr_tree.sub
      ; binop Expr_tree.mul
      ; binop Expr_tree.div
      ; unop Expr_tree.sqrt
      ; unop Expr_tree.abs
      ; unop Expr_tree.neg
      ; unop Expr_tree.sign
      ; unop Expr_tree.sin
      ; unop Expr_tree.cos
      ; unop Expr_tree.round
      ; binop Expr_tree.min
      ; binop Expr_tree.max
      ; (let%bind condition = gen_bool_expr ~depth:d in
         let%bind then_ = gen_float_expr ~depth:d in
         let%map else_ = gen_float_expr ~depth:d in
         ok (Expr_tree.cond ~loc ~condition ~then_ ~else_))
      ])

and gen_bool_expr ~depth =
  let open Quickcheck.Generator.Let_syntax in
  let leaf =
    let%map b = Bool.quickcheck_generator in
    ok (Expr_tree.bool_literal ~loc b)
  in
  if depth <= 0
  then leaf
  else (
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
      ])
;;

let gen_expr ~depth (type_ : Expr_tree.Type.t) =
  match type_ with
  | Float -> gen_float_expr ~depth
  | Bool -> gen_bool_expr ~depth
;;

(* --- Shared bisimulation infrastructure --- *)

let backends : (string * (module Executor.S_single)) list =
  [ "tree", (module Expr_tree_eval.Single)
  ; "graph", (module Expr_graph_eval.Single)
  ; "batch", (module Expr_graph_batch_eval.Single)
  ]
;;

let eval_with_single (module S : Executor.S_single) tree ~x ~y =
  let t = S.of_tree tree in
  let vars = S.Variable_idx.Map.empty in
  S.run
    t
    ~vars
    ~oracles:Oracle.Key.Map.empty
    ~x:(Float32_u.of_float x)
    ~y:(Float32_u.of_float y)
;;

let format_value v (type_ : Expr_tree.Type.t) =
  match type_ with
  | Float -> Float32_u.to_string (Value.to_float v)
  | Bool -> Bool.to_string (Value.to_bool v)
;;

(** Evaluate [tree] with every backend and print the reference result. On mismatch with
    any backend, prints the mismatched value and label. *)
let check tree ~x ~y =
  let reference = eval_with_single (module Expr_tree_eval.Single) tree ~x ~y in
  let type_ = tree.type_ in
  printf "%s\n" (format_value reference type_);
  List.iter backends ~f:(fun (label, backend) ->
    let result = eval_with_single backend tree ~x ~y in
    if not (Value.equal reference result)
    then printf "MISMATCH: %s=%s\n" label (format_value result type_))
;;

(** Assert bisimulation holds across all backends. Raises on mismatch. For use in
    quickcheck. *)
let assert_bisimulation tree ~x ~y =
  let reference = eval_with_single (module Expr_tree_eval.Single) tree ~x ~y in
  let type_ = tree.type_ in
  List.iter backends ~f:(fun (label, backend) ->
    let result = eval_with_single backend tree ~x ~y in
    if not (Value.equal reference result)
    then (
      let ( ~instructions
          , ~final_register
          , ~register_count:_
          , ~var_mapping:_
          , ~oracle_keys:_ )
        =
        Expr_graph.from_tree tree
      in
      let graph_asm =
        sprintf "result: $%d\n%s" final_register (Expr_graph.pp_instructions instructions)
      in
      let ~instructions:minimized, ~final_register:min_final, ~register_count:_ =
        Expr_graph_register_minimizer.minimize ~instructions ~final_register
      in
      let minimized_asm =
        sprintf "result: $%d\n%s" min_final (Expr_graph.pp_instructions minimized)
      in
      Error.raise_s
        [%message
          "bisimulation failure"
            ~evaluator:(label : string)
            ~tree:(Expr_tree.sexp_of_t tree : Sexp.t)
            ~tree_result:(format_value reference type_ : string)
            ~other_result:(format_value result type_ : string)
            ~graph_asm:(graph_asm : string)
            ~minimized_asm:(minimized_asm : string)
            ~x:(x : float)
            ~y:(y : float)]))
;;

(* --- Hardcoded bisimulation tests --- *)

let%expect_test "literal" =
  check (f #1.0s) ~x:0.0 ~y:0.0;
  [%expect {| 1. |}]
;;

let%expect_test "variable" =
  check coord_x ~x:42.0 ~y:0.0;
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
  check (cond ~condition:(b true) ~then_:coord_x ~else_:(f #999.0s)) ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "nested cond in else, taking then branch" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:coord_x
      ~else_:(cond ~condition:(b true) ~then_:(f #1.0s) ~else_:(f #2.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "nested cond in else, taking else branch" =
  let tree =
    cond
      ~condition:(b false)
      ~then_:coord_x
      ~else_:(cond ~condition:(b true) ~then_:(f #1.0s) ~else_:(f #2.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 1. |}]
;;

let%expect_test "computed condition with nested else cond" =
  let tree =
    cond
      ~condition:(lt coord_x (f #0.0s))
      ~then_:(f #1.0s)
      ~else_:(cond ~condition:(b true) ~then_:(f #2.0s) ~else_:(f #3.0s))
  in
  check tree ~x:5.0 ~y:0.0;
  [%expect {| 2. |}]
;;

let%expect_test "shared var across both cond branches" =
  let tree = cond ~condition:(b true) ~then_:coord_x ~else_:(add coord_x (f #1.0s)) in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "shared var with nested cond in else" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:coord_x
      ~else_:(cond ~condition:(b true) ~then_:(mul coord_x (f #2.0s)) ~else_:(f #3.0s))
  in
  check tree ~x:42.0 ~y:0.0;
  [%expect {| 42. |}]
;;

let%expect_test "computed condition, var in then, nested cond with ops in else" =
  let tree =
    cond
      ~condition:(lt (f #1.0s) (f #2.0s))
      ~then_:coord_x
      ~else_:
        (cond ~condition:(b true) ~then_:(mul (nf #1.0s) (nf #1.0s)) ~else_:(f #999.0s))
  in
  check tree ~x:7.0 ~y:0.0;
  [%expect {| 7. |}]
;;

let%expect_test "div by zero in else branch, taking then branch" =
  let tree = cond ~condition:(b true) ~then_:coord_x ~else_:(div coord_y (f #0.0s)) in
  check tree ~x:7.0 ~y:1.0;
  [%expect {| 7. |}]
;;

let%expect_test "original quickcheck failure - simplified" =
  (* From the quickcheck counterexample: the outer cond's condition is true, so we should
     get the then branch (x), but the graph evaluator returned +infinity from the else
     branch. *)
  let tree =
    cond
      ~condition:
        (lt
           (add (nf #0.0s) (div coord_x coord_x))
           (sub
              (div coord_y (f #0.0s))
              (cond ~condition:(b false) ~then_:coord_x ~else_:(f #1.45220733s))))
      ~then_:coord_x
      ~else_:
        (cond
           ~condition:(b true)
           ~then_:
             (mul
                (div (nf #1.26763916s) coord_y)
                (cond
                   ~condition:(b false)
                   ~then_:(nf #0.0s)
                   ~else_:(f Float32_u.(-#1.0s / #0.0s))))
           ~else_:(add (div coord_y (nf #0.0s)) (mul coord_x (nf #0.0s))))
  in
  check tree ~x:(-0.267355561256) ~y:2.9582283945787943e-31;
  [%expect {| -0.267355561 |}]
;;

(* Regression test: CSE must distinguish -0.0 from +0.0. An expression using both -0.0 and
   +0.0 as literals must not have them merged by CSE, since they produce different results
   via division (1/+0 = +inf, 1/-0 = -inf). *)

let pp tree =
  let ~instructions, ~final_register, ~register_count:_, ~var_mapping:_, ~oracle_keys:_ =
    Expr_graph.from_tree tree
  in
  printf "result: $%d\n" final_register;
  print_string (Expr_graph.pp_instructions instructions)
;;

let%expect_test "CSE distinguishes -0.0 and +0.0: evaluation" =
  let tree =
    cond
      ~condition:(lt (add (nf #0.0s) (f #1.0s)) (div coord_y (f #0.0s)))
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
           (add (nf #0.0s) (div coord_x coord_x))
           (sub (div coord_y (f #0.0s)) (f #1.45220733s)))
      ~then_:(f #1.0s)
      ~else_:(f #2.0s)
  in
  pp tree;
  [%expect
    {|
    result: $0
    $3 <- -0.
    $5 <- coord_x
    $4 <- div $5 $5
    $2 <- add $3 $4
    $8 <- coord_y
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

(* Regression: an outer-scope variable used inside a cond branch must not be freed by the
   branch. This tree compiles into two sequential Condition instructions that both
   reference x's register:

   $x <- coord_x ... $r1 <- cond ... ← inner cond; then-branch uses $x then does more work
   $r0 <- cond $r1 ← outer cond; then-branch uses $x via neg

   Without the fix, the inner then-branch would free $x after its last local use, allowing
   later allocations inside the branch to clobber it. When the outer then-branch reads $x
   for [neg], it gets the wrong value. *)
let pp_minimized tree =
  let ~instructions, ~final_register, ~register_count:_, ~var_mapping:_, ~oracle_keys:_ =
    Expr_graph.from_tree tree
  in
  let ~instructions, ~final_register, ~register_count:_ =
    Expr_graph_register_minimizer.minimize ~instructions ~final_register
  in
  printf "result: $%d\n" final_register;
  print_string (Expr_graph.pp_instructions instructions)
;;

let%expect_test "outer var survives register pressure in cond branch (minimized)" =
  let x = coord_x in
  let tree =
    cond
      ~condition:
        (cond
           ~condition:(lt x (f #10.0s))
           ~then_:(lt (mul x (f #2.0s)) (mul (f #3.0s) (f #4.0s)))
           ~else_:(b false))
      ~then_:(neg x)
      ~else_:(f #0.0s)
  in
  (* The minimized graph should keep $0 (x) alive through both conditions. In the inner
     then-branch, $0 must NOT be freed and reused. *)
  pp_minimized tree;
  [%expect
    {|
    result: $2
    $0 <- coord_x
    $1 <- 10.
    $2 <- lt $0 $1
    $1 <- cond $2
      then:
        $3 <- 2.
        $4 <- mul $0 $3
        $3 <- 3.
        $5 <- 4.
        $6 <- mul $3 $5
        $5 <- lt $4 $6
        $1 <- $5
      else:
        $3 <- false
        $1 <- $3
    $2 <- cond $1
      then:
        $7 <- neg $0
        $2 <- $7
      else:
        $7 <- 0.
        $2 <- $7
    |}];
  check tree ~x:5.0 ~y:0.0;
  [%expect {| -5. |}]
;;

(* --- Quickcheck bisimulation test --- *)

let gen_test_case =
  let open Quickcheck.Generator.Let_syntax in
  let%bind depth = Int.gen_incl 0 4 in
  let%bind type_ = Quickcheck.Generator.of_list [ Expr_tree.Type.Bool; Float ] in
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
