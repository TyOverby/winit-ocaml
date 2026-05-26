open! Core
open Sdf
open Helpers

let default_env =
  String.Map.of_alist_exn
    [ "x", Value.Boxed.T (Value.of_float #1.0s)
    ; "y", Value.Boxed.T (Value.of_float #1.0s)
    ; "b", Value.Boxed.T (Value.of_bool true)
    ]
;;

let eval_generic tree =
  let ~var_mapping, ~run = Expr_graph_eval.run_tree tree in
  let variables = Value.Array.create ~len:(Hashtbl.length var_mapping) in
  Hashtbl.iteri var_mapping ~f:(fun ~key ~data ->
    let (T value) = Map.find_exn default_env key in
    Value.Array.set variables data value);
  run ~variables
;;

let eval_float tree = print_s (Float32_u.sexp_of_t (Value.to_float (eval_generic tree)))

let%expect_test "addition" =
  eval_float (add (f #1.s) (f #2.s));
  [%expect {| 3 |}]
;;

let%expect_test "variables" =
  let v = add (var "y" Float) (var "x" Float) in
  eval_float (add (f #1.s) v);
  [%expect {| 3 |}]
;;

let pp tree =
  let ~instructions, ~final_register, ~register_count:_, ~var_mapping:_ =
    Expr_graph.from_tree tree
  in
  printf "result: $%d\n" final_register;
  print_string (Expr_graph.pp_instructions instructions)
;;

let%expect_test "basic conditional" =
  let tree = cond ~condition:(b true) ~then_:(f #99.0s) ~else_:(f #100.0s) in
  pp tree;
  [%expect
    {|
    result: $0
    $1 <- true
    $0 <- cond $1
      then:
        $2 <- 99.
        $0 <- $2
      else:
        $3 <- 100.
        $0 <- $3
    |}];
  eval_float tree;
  [%expect {| 99 |}]
;;

let%expect_test "nested conditional" =
  let tree =
    cond
      ~condition:(b true)
      ~then_:(cond ~condition:(b false) ~then_:(f #1.s) ~else_:(f #42.s))
      ~else_:(f #100.s)
  in
  pp tree;
  [%expect
    {|
    result: $0
    $1 <- true
    $0 <- cond $1
      then:
        $3 <- false
        $2 <- cond $3
          then:
            $4 <- 1.
            $2 <- $4
          else:
            $5 <- 42.
            $2 <- $5
        $0 <- $2
      else:
        $6 <- 100.
        $0 <- $6
    |}];
  eval_float tree;
  [%expect {| 42 |}]
;;
