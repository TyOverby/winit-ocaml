open! Core

let parse s =
  match Neo.parse s with
  | Ok program -> print_s [%sexp (program : Neo.Ast.program)]
  | Error e -> print_s [%sexp (e : Error.t)]
;;

let%expect_test "float literal" =
  parse {| export 42; |};
  [%expect {| ((stmts ()) (export ((loc <string>:1:8) (kind (Float_lit 42))))) |}]
;;

let%expect_test "arithmetic" =
  parse {| export 1 + 2 * 3; |};
  [%expect
    {|
    ((stmts ())
     (export
      ((loc <string>:1:8)
       (kind
        (Binop Add ((loc <string>:1:8) (kind (Float_lit 1)))
         ((loc <string>:1:12)
          (kind
           (Binop Mul ((loc <string>:1:12) (kind (Float_lit 2)))
            ((loc <string>:1:16) (kind (Float_lit 3)))))))))))
    |}]
;;

let%expect_test "let binding" =
  parse {| let x = 1 + 2; export x; |};
  [%expect
    {|
    ((stmts
      ((Let (loc <string>:1:1) (name x) (type_annot ())
        (value
         ((loc <string>:1:9)
          (kind
           (Binop Add ((loc <string>:1:9) (kind (Float_lit 1)))
            ((loc <string>:1:13) (kind (Float_lit 2))))))))))
     (export ((loc <string>:1:23) (kind (Ident x)))))
    |}]
;;

let%expect_test "let with type annotation" =
  parse {| let x : float = var("x"); export x; |};
  [%expect
    {|
    ((stmts
      ((Let (loc <string>:1:1) (name x) (type_annot (Float_type))
        (value
         ((loc <string>:1:17)
          (kind
           (Call ((loc <string>:1:17) (kind (Ident var)))
            (((loc <string>:1:23) (kind (String_lit x)))))))))))
     (export ((loc <string>:1:34) (kind (Ident x)))))
    |}]
;;

let%expect_test "fn declaration" =
  parse {| fn add(a, b) { a + b } export add(1, 2); |};
  [%expect
    {|
    ((stmts
      ((Fn_decl (loc <string>:1:1) (name add)
        (params (((name a) (type_annot ())) ((name b) (type_annot ()))))
        (body
         ((stmts ())
          (expr
           ((loc <string>:1:16)
            (kind
             (Binop Add ((loc <string>:1:16) (kind (Ident a)))
              ((loc <string>:1:20) (kind (Ident b))))))))))))
     (export
      ((loc <string>:1:31)
       (kind
        (Call ((loc <string>:1:31) (kind (Ident add)))
         (((loc <string>:1:35) (kind (Float_lit 1)))
          ((loc <string>:1:38) (kind (Float_lit 2)))))))))
    |}]
;;

let%expect_test "anonymous fn in block" =
  parse {| fn make() { fn(x) { x + 1 } } export make(); |};
  [%expect
    {|
    ((stmts
      ((Fn_decl (loc <string>:1:1) (name make) (params ())
        (body
         ((stmts ())
          (expr
           ((loc <string>:1:13)
            (kind
             (Fn (((name x) (type_annot ())))
              ((stmts ())
               (expr
                ((loc <string>:1:21)
                 (kind
                  (Binop Add ((loc <string>:1:21) (kind (Ident x)))
                   ((loc <string>:1:25) (kind (Float_lit 1)))))))))))))))))
     (export
      ((loc <string>:1:38)
       (kind (Call ((loc <string>:1:38) (kind (Ident make))) ())))))
    |}]
;;

let%expect_test "if expression" =
  parse {| export if true { 1 } else { 2 }; |};
  [%expect
    {|
    ((stmts ())
     (export
      ((loc <string>:1:8)
       (kind
        (If ((loc <string>:1:11) (kind (Bool_lit true)))
         ((stmts ()) (expr ((loc <string>:1:18) (kind (Float_lit 1)))))
         ((stmts ()) (expr ((loc <string>:1:29) (kind (Float_lit 2))))))))))
    |}]
;;

let%expect_test "method call" =
  parse {| export x.foo(1, 2); |};
  [%expect
    {|
    ((stmts ())
     (export
      ((loc <string>:1:8)
       (kind
        (Method_call ((loc <string>:1:8) (kind (Ident x))) foo
         (((loc <string>:1:14) (kind (Float_lit 1)))
          ((loc <string>:1:17) (kind (Float_lit 2)))))))))
    |}]
;;

let%expect_test "placeholder" =
  parse {| export f(_, 1); |};
  [%expect
    {|
    ((stmts ())
     (export
      ((loc <string>:1:8)
       (kind
        (Call ((loc <string>:1:8) (kind (Ident f)))
         (((loc <string>:1:10) (kind Placeholder))
          ((loc <string>:1:13) (kind (Float_lit 1)))))))))
    |}]
;;

let%expect_test "unary neg" =
  parse {| export -x; |};
  [%expect
    {|
    ((stmts ())
     (export
      ((loc <string>:1:8)
       (kind (Unary_neg ((loc <string>:1:9) (kind (Ident x))))))))
    |}]
;;

let%expect_test "block with let stmts" =
  parse {|
    fn f(x) {
      let y = x + 1;
      y * 2
    }
    export f(10);
  |};
  [%expect
    {|
    ((stmts
      ((Fn_decl (loc <string>:2:4) (name f) (params (((name x) (type_annot ()))))
        (body
         ((stmts
           ((Let (loc <string>:3:6) (name y) (type_annot ())
             (value
              ((loc <string>:3:14)
               (kind
                (Binop Add ((loc <string>:3:14) (kind (Ident x)))
                 ((loc <string>:3:18) (kind (Float_lit 1))))))))))
          (expr
           ((loc <string>:4:6)
            (kind
             (Binop Mul ((loc <string>:4:6) (kind (Ident y)))
              ((loc <string>:4:10) (kind (Float_lit 2))))))))))))
     (export
      ((loc <string>:6:11)
       (kind
        (Call ((loc <string>:6:11) (kind (Ident f)))
         (((loc <string>:6:13) (kind (Float_lit 10)))))))))
    |}]
;;
