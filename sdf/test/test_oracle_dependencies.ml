open! Core
open Sdf

let here = Stdlib.Lexing.dummy_pos
let ok = Or_error.ok_exn
let f x = ok (Expr_tree.float_literal ~loc:here x)
let var name type_ = ok (Expr_tree.var ~loc:here name type_)
let add a b = ok (Expr_tree.add ~loc:here a b)
let sub a b = ok (Expr_tree.sub ~loc:here a b)
let mul a b = ok (Expr_tree.mul ~loc:here a b)
let lt a b = ok (Expr_tree.lt ~loc:here a b)
let oracle name args = ok (Expr_tree.oracle ~loc:here name args)
let cond ~condition ~then_ ~else_ = ok (Expr_tree.cond ~loc:here ~condition ~then_ ~else_)

let print_deps tree =
  let { Oracle_dependencies.toposorted } = Oracle_dependencies.extract_deps tree in
  List.iteri toposorted ~f:(fun i level ->
    printf "level %d:\n" i;
    List.iter level ~f:(fun (name, args) ->
      printf
        "  %s(%s)\n"
        name
        (String.concat
           ~sep:", "
           (List.map args ~f:(fun a -> Sexp.to_string_hum (Expr_tree.sexp_of_t a))))))
;;

let%expect_test "no oracles" =
  let tree = add (f #1.s) (f #2.s) in
  print_deps tree;
  [%expect {||}]
;;

let%expect_test "single oracle with no dependencies" =
  let x = var "x" Float in
  let tree = oracle "blur" [ x ] in
  print_deps tree;
  [%expect {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;

let%expect_test "two independent oracles" =
  let x = var "x" Float in
  let y = var "y" Float in
  let a = oracle "blur" [ x ] in
  let b = oracle "sharpen" [ y ] in
  let tree = add a b in
  print_deps tree;
  [%expect {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
      sharpen(((loc :0:-1) (kind (Var y Float)) (type_ Float)))
    |}]
;;

let%expect_test "oracle depending on another oracle" =
  let x = var "x" Float in
  let blur_x = oracle "blur" [ x ] in
  let tree = oracle "sharpen" [ blur_x ] in
  print_deps tree;
  [%expect {|
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
  let a = oracle "a" [ x ] in
  let b = oracle "b" [ a ] in
  let tree = oracle "c" [ b ] in
  print_deps tree;
  [%expect {|
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
  let base = oracle "base" [ x ] in
  let left = oracle "left" [ base ] in
  let right = oracle "right" [ base ] in
  let tree = oracle "top" [ left; right ] in
  print_deps tree;
  [%expect {|
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
  let blur_x = oracle "blur" [ x ] in
  (* Same oracle used in two places *)
  let tree = add blur_x blur_x in
  print_deps tree;
  [%expect {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;

let%expect_test "same name different args are different oracles" =
  let x = var "x" Float in
  let y = var "y" Float in
  let blur_x = oracle "blur" [ x ] in
  let blur_y = oracle "blur" [ y ] in
  let tree = add blur_x blur_y in
  print_deps tree;
  [%expect {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
      blur(((loc :0:-1) (kind (Var y Float)) (type_ Float)))
    |}]
;;

let%expect_test "oracle nested inside arithmetic" =
  let x = var "x" Float in
  let o = oracle "blur" [ x ] in
  let tree = mul (add o (f #1.s)) (sub o (f #2.s)) in
  print_deps tree;
  [%expect {|
    level 0:
      blur(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;

let%expect_test "oracle inside cond branches" =
  let x = var "x" Float in
  let o1 = oracle "a" [ x ] in
  let o2 = oracle "b" [ x ] in
  let tree = cond ~condition:(lt o1 (f #0.s)) ~then_:o1 ~else_:o2 in
  print_deps tree;
  [%expect {|
    level 0:
      a(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
      b(((loc :0:-1) (kind (Var x Float)) (type_ Float)))
    |}]
;;
