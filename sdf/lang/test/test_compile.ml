open! Core
open Sdf

let compile s =
  match Neo.compile s with
  | Ok tree -> print_s [%sexp (tree : Expr_tree.t)]
  | Error e -> print_s [%sexp (e : Error.t)]
;;

let%expect_test "float literal" =
  compile {| export 42; |};
  [%expect {| ((loc <string>:1:8) (kind (Float_literal 42)) (type_ Float)) |}]
;;

let%expect_test "boolean literal" =
  compile {| export true; |};
  [%expect {| ((loc <string>:1:8) (kind (Bool_literal true)) (type_ Bool)) |}]
;;

let%expect_test "arithmetic" =
  compile {| export 1 + 2; |};
  [%expect
    {|
    ((loc <string>:1:8)
     (kind
      (Add ((loc <string>:1:8) (kind (Float_literal 1)) (type_ Float))
       ((loc <string>:1:12) (kind (Float_literal 2)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "let binding" =
  compile {| let x = 1 + 2; export x + 3; |};
  [%expect
    {|
    ((loc <string>:1:23)
     (kind
      (Add
       ((loc <string>:1:9)
        (kind
         (Add ((loc <string>:1:9) (kind (Float_literal 1)) (type_ Float))
          ((loc <string>:1:13) (kind (Float_literal 2)) (type_ Float))))
        (type_ Float))
       ((loc <string>:1:27) (kind (Float_literal 3)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "var binding" =
  compile {| let x : float = var("x"); export x + 1; |};
  [%expect
    {|
    ((loc <string>:1:34)
     (kind
      (Add ((loc <string>:1:17) (kind (Var x Float)) (type_ Float))
       ((loc <string>:1:38) (kind (Float_literal 1)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "simple function" =
  compile {|
    fn add(a, b) { a + b }
    export add(1, 2);
  |};
  [%expect
    {|
    ((loc <string>:2:19)
     (kind
      (Add ((loc <string>:3:15) (kind (Float_literal 1)) (type_ Float))
       ((loc <string>:3:18) (kind (Float_literal 2)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "simple function via let binding" =
  compile {|
    let add = fn(a, b) { a + b };
    export add(1, 2);
  |};
  [%expect
    {|
    ((loc <string>:2:25)
     (kind
      (Add ((loc <string>:3:15) (kind (Float_literal 1)) (type_ Float))
       ((loc <string>:3:18) (kind (Float_literal 2)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "function returning function" =
  compile
    {|
    fn make_adder(n) {
      fn(x) { x + n }
    }
    let add5 = make_adder(5);
    export add5(10);
  |};
  [%expect
    {|
    ((loc <string>:3:14)
     (kind
      (Add ((loc <string>:6:16) (kind (Float_literal 10)) (type_ Float))
       ((loc <string>:5:26) (kind (Float_literal 5)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "if with static condition" =
  compile {| export if true { 1 } else { 2 }; |};
  [%expect {| ((loc <string>:1:18) (kind (Float_literal 1)) (type_ Float)) |}]
;;

let%expect_test "if with runtime condition" =
  compile
    {|
    let x : float = var("x");
    export if x < 10 { x + 1 } else { x - 1 };
  |};
  [%expect
    {|
    ((loc <string>:3:14)
     (kind
      (Cond
       (condition
        ((loc <string>:3:14)
         (kind
          (Lt ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
           ((loc <string>:3:18) (kind (Float_literal 10)) (type_ Float))))
         (type_ Bool)))
       (then_
        ((loc <string>:3:23)
         (kind
          (Add ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
           ((loc <string>:3:27) (kind (Float_literal 1)) (type_ Float))))
         (type_ Float)))
       (else_
        ((loc <string>:3:38)
         (kind
          (Sub ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
           ((loc <string>:3:42) (kind (Float_literal 1)) (type_ Float))))
         (type_ Float)))))
     (type_ Float))
    |}]
;;

let%expect_test "builtin sqrt" =
  compile {| export sqrt(9); |};
  [%expect
    {|
    ((loc <string>:1:8)
     (kind (Sqrt ((loc <string>:1:13) (kind (Float_literal 9)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "method call UFCS" =
  compile {|
    fn double(x) { x + x }
    export 5.double();
  |};
  [%expect
    {|
    ((loc <string>:2:19)
     (kind
      (Add ((loc <string>:3:11) (kind (Float_literal 5)) (type_ Float))
       ((loc <string>:3:11) (kind (Float_literal 5)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "method call UFCS (let binding)" =
  compile {|
    let double = fn(x) { x + x };
    export 5.double();
  |};
  [%expect
    {|
    ((loc <string>:2:25)
     (kind
      (Add ((loc <string>:3:11) (kind (Float_literal 5)) (type_ Float))
       ((loc <string>:3:11) (kind (Float_literal 5)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "partial application" =
  compile
    {|
    fn add(a, b) { a + b }
    let add5 = add(_, 5);
    export add5(10);
  |};
  [%expect
    {|
    ((loc <string>:2:19)
     (kind
      (Add ((loc <string>:4:16) (kind (Float_literal 10)) (type_ Float))
       ((loc <string>:3:22) (kind (Float_literal 5)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "unary negation" =
  compile {| export -42; |};
  [%expect
    {|
    ((loc <string>:1:8)
     (kind (Neg ((loc <string>:1:9) (kind (Float_literal 42)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "multi-placeholder partial application" =
  compile
    {|
    fn f(a, b, c) { a + b + c }
    let g = f(_, 10, _);
    export g(1, 2);
  |};
  [%expect
    {|
    ((loc <string>:2:20)
     (kind
      (Add
       ((loc <string>:2:20)
        (kind
         (Add ((loc <string>:4:13) (kind (Float_literal 1)) (type_ Float))
          ((loc <string>:3:17) (kind (Float_literal 10)) (type_ Float))))
        (type_ Float))
       ((loc <string>:4:16) (kind (Float_literal 2)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "dynamic if with closures (lifted)" =
  compile
    {|
    let x : float = var("x");
    let cond : bool = var("cond");
    let f = if cond { fn(a) { a + 1 } } else { fn(a) { a - 1 } };
    export f(x);
  |};
  [%expect
    {|
    ((loc <string>:3:22)
     (kind
      (Cond (condition ((loc <string>:3:22) (kind (Var cond Bool)) (type_ Bool)))
       (then_
        ((loc <string>:4:30)
         (kind
          (Add ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
           ((loc <string>:4:34) (kind (Float_literal 1)) (type_ Float))))
         (type_ Float)))
       (else_
        ((loc <string>:4:55)
         (kind
          (Sub ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
           ((loc <string>:4:59) (kind (Float_literal 1)) (type_ Float))))
         (type_ Float)))))
     (type_ Float))
    |}]
;;

let%expect_test "variable shadowing" =
  compile {|
    let x = 1;
    let x = x + 2;
    export x;
  |};
  [%expect
    {|
    ((loc <string>:3:12)
     (kind
      (Add ((loc <string>:2:12) (kind (Float_literal 1)) (type_ Float))
       ((loc <string>:3:16) (kind (Float_literal 2)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "nested function calls" =
  compile {|
    fn f(x) { x + 1 }
    fn g(x) { x * 2 }
    export g(f(3));
  |};
  [%expect
    {|
    ((loc <string>:3:14)
     (kind
      (Mul
       ((loc <string>:2:14)
        (kind
         (Add ((loc <string>:4:15) (kind (Float_literal 3)) (type_ Float))
          ((loc <string>:2:18) (kind (Float_literal 1)) (type_ Float))))
        (type_ Float))
       ((loc <string>:3:18) (kind (Float_literal 2)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "all builtins" =
  compile
    {|
    let x : float = var("x");
    let y : float = var("y");
    let a = abs(x);
    let b = neg(y);
    let c = sign(x);
    let d = sin(x);
    let e = cos(y);
    let f = round(x);
    let g = min(x, y);
    let h = max(x, y);
    export a + b + c + d + e + f + g + h;
  |};
  [%expect
    {|
    ((loc <string>:12:11)
     (kind
      (Add
       ((loc <string>:12:11)
        (kind
         (Add
          ((loc <string>:12:11)
           (kind
            (Add
             ((loc <string>:12:11)
              (kind
               (Add
                ((loc <string>:12:11)
                 (kind
                  (Add
                   ((loc <string>:12:11)
                    (kind
                     (Add
                      ((loc <string>:12:11)
                       (kind
                        (Add
                         ((loc <string>:4:12)
                          (kind
                           (Abs
                            ((loc <string>:2:20) (kind (Var x Float))
                             (type_ Float))))
                          (type_ Float))
                         ((loc <string>:5:12)
                          (kind
                           (Neg
                            ((loc <string>:3:20) (kind (Var y Float))
                             (type_ Float))))
                          (type_ Float))))
                       (type_ Float))
                      ((loc <string>:6:12)
                       (kind
                        (Sign
                         ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))))
                       (type_ Float))))
                    (type_ Float))
                   ((loc <string>:7:12)
                    (kind
                     (Sin
                      ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))))
                    (type_ Float))))
                 (type_ Float))
                ((loc <string>:8:12)
                 (kind
                  (Cos ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))))
                 (type_ Float))))
              (type_ Float))
             ((loc <string>:9:12)
              (kind
               (Round ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))))
              (type_ Float))))
           (type_ Float))
          ((loc <string>:10:12)
           (kind
            (Min ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
             ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))))
           (type_ Float))))
        (type_ Float))
       ((loc <string>:11:12)
        (kind
         (Max ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
          ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))))
        (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "xor builtin" =
  compile
    {|
    let a : bool = var("a");
    let b : bool = var("b");
    export if xor(a, b) { 1 } else { 0 };
  |};
  [%expect
    {|
    ((loc <string>:4:14)
     (kind
      (Cond
       (condition
        ((loc <string>:4:14)
         (kind
          (Xor ((loc <string>:2:19) (kind (Var a Bool)) (type_ Bool))
           ((loc <string>:3:19) (kind (Var b Bool)) (type_ Bool))))
         (type_ Bool)))
       (then_ ((loc <string>:4:26) (kind (Float_literal 1)) (type_ Float)))
       (else_ ((loc <string>:4:37) (kind (Float_literal 0)) (type_ Float)))))
     (type_ Float))
    |}]
;;

let%expect_test "builtin shadowing" =
  compile {|
    fn sqrt(x) { x * x }
    export sqrt(3);
  |};
  [%expect
    {|
    ((loc <string>:2:17)
     (kind
      (Mul ((loc <string>:3:16) (kind (Float_literal 3)) (type_ Float))
       ((loc <string>:3:16) (kind (Float_literal 3)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "example.neo circle shape" =
  compile
    {|
    let x : float = var("x");
    let y : float = var("y");

    fn circle(cx, cy, r) {
      fn(x, y) {
        let dx = cx - x;
        let dy = cy - y;
        sqrt(dx * dx + dy * dy) - r
      }
    }

    let my_shape = circle(100, 100, 30);
    export my_shape(x, y);
  |};
  [%expect
    {|
    ((loc <string>:9:8)
     (kind
      (Sub
       ((loc <string>:9:8)
        (kind
         (Sqrt
          ((loc <string>:9:13)
           (kind
            (Add
             ((loc <string>:9:13)
              (kind
               (Mul
                ((loc <string>:7:17)
                 (kind
                  (Sub
                   ((loc <string>:13:26) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))))
                 (type_ Float))
                ((loc <string>:7:17)
                 (kind
                  (Sub
                   ((loc <string>:13:26) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))))
                 (type_ Float))))
              (type_ Float))
             ((loc <string>:9:23)
              (kind
               (Mul
                ((loc <string>:8:17)
                 (kind
                  (Sub
                   ((loc <string>:13:31) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))))
                 (type_ Float))
                ((loc <string>:8:17)
                 (kind
                  (Sub
                   ((loc <string>:13:31) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))))
                 (type_ Float))))
              (type_ Float))))
           (type_ Float))))
        (type_ Float))
       ((loc <string>:13:36) (kind (Float_literal 30)) (type_ Float))))
     (type_ Float))
    |}]
;;

let%expect_test "example.neo with modulate" =
  compile
    {|
    let x : float = var("x");
    let y : float = var("y");

    fn circle(cx, cy, r) {
      fn(x, y) {
        let dx = cx - x;
        let dy = cy - y;
        sqrt(dx * dx + dy * dy) - r
      }
    }

    fn modulate(f, freq, amp) {
      fn(x, y) {
        let x = x + sin(y / freq) * amp;
        let y = y + cos(x / freq) * amp;
        f(x, y)
      }
    }

    let modulate_high = true;
    let my_modulate =
      if modulate_high {
        modulate(_, 20, 20)
      } else {
        modulate(_, 10, 10)
      };

    let my_shape = circle(100, 100, 30).my_modulate();
    export my_shape(x, y);
  |};
  [%expect
    {|
    ((loc <string>:9:8)
     (kind
      (Sub
       ((loc <string>:9:8)
        (kind
         (Sqrt
          ((loc <string>:9:13)
           (kind
            (Add
             ((loc <string>:9:13)
              (kind
               (Mul
                ((loc <string>:7:17)
                 (kind
                  (Sub
                   ((loc <string>:29:26) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:15:16)
                    (kind
                     (Add
                      ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
                      ((loc <string>:15:20)
                       (kind
                        (Mul
                         ((loc <string>:15:20)
                          (kind
                           (Sin
                            ((loc <string>:15:24)
                             (kind
                              (Div
                               ((loc <string>:3:20) (kind (Var y Float))
                                (type_ Float))
                               ((loc <string>:24:20) (kind (Float_literal 20))
                                (type_ Float))))
                             (type_ Float))))
                          (type_ Float))
                         ((loc <string>:24:24) (kind (Float_literal 20))
                          (type_ Float))))
                       (type_ Float))))
                    (type_ Float))))
                 (type_ Float))
                ((loc <string>:7:17)
                 (kind
                  (Sub
                   ((loc <string>:29:26) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:15:16)
                    (kind
                     (Add
                      ((loc <string>:2:20) (kind (Var x Float)) (type_ Float))
                      ((loc <string>:15:20)
                       (kind
                        (Mul
                         ((loc <string>:15:20)
                          (kind
                           (Sin
                            ((loc <string>:15:24)
                             (kind
                              (Div
                               ((loc <string>:3:20) (kind (Var y Float))
                                (type_ Float))
                               ((loc <string>:24:20) (kind (Float_literal 20))
                                (type_ Float))))
                             (type_ Float))))
                          (type_ Float))
                         ((loc <string>:24:24) (kind (Float_literal 20))
                          (type_ Float))))
                       (type_ Float))))
                    (type_ Float))))
                 (type_ Float))))
              (type_ Float))
             ((loc <string>:9:23)
              (kind
               (Mul
                ((loc <string>:8:17)
                 (kind
                  (Sub
                   ((loc <string>:29:31) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:16:16)
                    (kind
                     (Add
                      ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))
                      ((loc <string>:16:20)
                       (kind
                        (Mul
                         ((loc <string>:16:20)
                          (kind
                           (Cos
                            ((loc <string>:16:24)
                             (kind
                              (Div
                               ((loc <string>:15:16)
                                (kind
                                 (Add
                                  ((loc <string>:2:20) (kind (Var x Float))
                                   (type_ Float))
                                  ((loc <string>:15:20)
                                   (kind
                                    (Mul
                                     ((loc <string>:15:20)
                                      (kind
                                       (Sin
                                        ((loc <string>:15:24)
                                         (kind
                                          (Div
                                           ((loc <string>:3:20)
                                            (kind (Var y Float)) (type_ Float))
                                           ((loc <string>:24:20)
                                            (kind (Float_literal 20))
                                            (type_ Float))))
                                         (type_ Float))))
                                      (type_ Float))
                                     ((loc <string>:24:24)
                                      (kind (Float_literal 20)) (type_ Float))))
                                   (type_ Float))))
                                (type_ Float))
                               ((loc <string>:24:20) (kind (Float_literal 20))
                                (type_ Float))))
                             (type_ Float))))
                          (type_ Float))
                         ((loc <string>:24:24) (kind (Float_literal 20))
                          (type_ Float))))
                       (type_ Float))))
                    (type_ Float))))
                 (type_ Float))
                ((loc <string>:8:17)
                 (kind
                  (Sub
                   ((loc <string>:29:31) (kind (Float_literal 100))
                    (type_ Float))
                   ((loc <string>:16:16)
                    (kind
                     (Add
                      ((loc <string>:3:20) (kind (Var y Float)) (type_ Float))
                      ((loc <string>:16:20)
                       (kind
                        (Mul
                         ((loc <string>:16:20)
                          (kind
                           (Cos
                            ((loc <string>:16:24)
                             (kind
                              (Div
                               ((loc <string>:15:16)
                                (kind
                                 (Add
                                  ((loc <string>:2:20) (kind (Var x Float))
                                   (type_ Float))
                                  ((loc <string>:15:20)
                                   (kind
                                    (Mul
                                     ((loc <string>:15:20)
                                      (kind
                                       (Sin
                                        ((loc <string>:15:24)
                                         (kind
                                          (Div
                                           ((loc <string>:3:20)
                                            (kind (Var y Float)) (type_ Float))
                                           ((loc <string>:24:20)
                                            (kind (Float_literal 20))
                                            (type_ Float))))
                                         (type_ Float))))
                                      (type_ Float))
                                     ((loc <string>:24:24)
                                      (kind (Float_literal 20)) (type_ Float))))
                                   (type_ Float))))
                                (type_ Float))
                               ((loc <string>:24:20) (kind (Float_literal 20))
                                (type_ Float))))
                             (type_ Float))))
                          (type_ Float))
                         ((loc <string>:24:24) (kind (Float_literal 20))
                          (type_ Float))))
                       (type_ Float))))
                    (type_ Float))))
                 (type_ Float))))
              (type_ Float))))
           (type_ Float))))
        (type_ Float))
       ((loc <string>:29:36) (kind (Float_literal 30)) (type_ Float))))
     (type_ Float))
    |}]
;;
