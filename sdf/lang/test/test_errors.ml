open! Core

let compile_error s =
  match Neo.compile s with
  | Ok _tree -> print_endline "OK (no error)"
  | Error e -> print_s [%sexp (e : Error.t)]
;;

let parse_error s =
  match Neo.parse s with
  | Ok _program -> print_endline "OK (no error)"
  | Error e -> print_s [%sexp (e : Error.t)]
;;

(* === Lexer errors === *)

let%expect_test "lexer: unexpected character" =
  parse_error {| export @; |};
  [%expect {| ("unexpected character: @" (loc <string>:1:9)) |}]
;;

let%expect_test "lexer: unterminated string" =
  parse_error {| export "hello |};
  [%expect {| ("unterminated string literal" (loc <string>:1:15)) |}]
;;

let%expect_test "lexer: invalid escape in string" =
  parse_error "export \"hello\\qworld\";";
  [%expect {| ("invalid escape in string" (loc <string>:1:14)) |}]
;;

(* === Parser errors === *)

let%expect_test "parser: missing semicolon" =
  parse_error {| export 42 |};
  [%expect {| ("syntax error" (loc <string>:1:11)) |}]
;;

let%expect_test "parser: missing export" =
  parse_error {| 42; |};
  [%expect {| ("syntax error" (loc <string>:1:3)) |}]
;;

let%expect_test "parser: missing else" =
  parse_error {| export if true { 1 }; |};
  [%expect {| ("syntax error" (loc <string>:1:22)) |}]
;;

let%expect_test "parser: missing closing brace" =
  parse_error {| export if true { 1 else { 2 }; |};
  [%expect {| ("syntax error" (loc <string>:1:24)) |}]
;;

(* === Compile errors === *)

let%expect_test "compile: unbound variable" =
  compile_error {| export foo; |};
  [%expect {| ("unbound variable 'foo'" (loc <string>:1:8)) |}]
;;

let%expect_test "compile: unbound function" =
  compile_error {| export foo(1); |};
  [%expect {| ("unbound function 'foo'" (loc <string>:1:8)) |}]
;;

let%expect_test "compile: placeholder outside call" =
  compile_error {| export _; |};
  [%expect {| ("placeholder _ outside of function call arguments" (loc <string>:1:8)) |}]
;;

let%expect_test "compile: wrong arg count (user fn)" =
  compile_error {|
    fn add(a, b) { a + b }
    export add(1, 2, 3);
  |};
  [%expect {| ("wrong number of arguments: expected 2 but got 3" (loc <string>:3:11)) |}]
;;

let%expect_test "compile: wrong arg count (builtin)" =
  compile_error {| export sqrt(1, 2); |};
  [%expect
    {|
    ("wrong number of arguments to 'sqrt': expected 1 but got 2"
     (loc <string>:1:8))
    |}]
;;

let%expect_test "compile: string as expression" =
  compile_error {| export "hello"; |};
  [%expect {| ("cannot use string 'hello' as an expression" (loc <string>:1:14)) |}]
;;

let%expect_test "compile: function as expression" =
  compile_error {|
    fn f(x) { x }
    export f;
  |};
  [%expect
    {|
    ("cannot use function as a value; did you forget to call it?"
     (loc <string>:3:11))
    |}]
;;

let%expect_test "compile: calling non-function" =
  compile_error {|
    let x = 42;
    export x(1);
  |};
  [%expect {| ("cannot call a non-function value" (loc <string>:3:11)) |}]
;;

let%expect_test "compile: var() wrong arg type" =
  compile_error {| export var(42); |};
  [%expect {| ("var() expects a string argument" (loc <string>:1:8)) |}]
;;

let%expect_test "compile: var() wrong arg count" =
  compile_error {| export var("a", "b"); |};
  [%expect {| ("var() expects exactly 1 argument but got 2" (loc <string>:1:8)) |}]
;;

(* === Type errors === *)

let%expect_test "type error: float op on bool (rhs)" =
  compile_error {|
    let a : bool = var("a");
    export 1 + a;
  |};
  [%expect
    {|
    ("type error in addition: right-hand side is bool, expected float"
     (loc <string>:2:19))
    |}]
;;

let%expect_test "type error: float op on bool (lhs)" =
  compile_error {|
    let a : bool = var("a");
    export a + 1;
  |};
  [%expect
    {|
    ("type error in addition: left-hand side is bool, expected float"
     (loc <string>:2:19))
    |}]
;;

let%expect_test "type error: float op on both bools" =
  compile_error
    {|
    let a : bool = var("a");
    let b : bool = var("b");
    export a + b;
  |};
  [%expect
    {|
    ("type error in addition: both arguments are bool, expected float"
     (lhs_loc <string>:2:19) (rhs_loc <string>:3:19))
    |}]
;;

let%expect_test "type error: bool op on float (rhs)" =
  compile_error {|
    let a : bool = var("a");
    export a && 1;
  |};
  [%expect
    {|
    ("type error in and: right-hand side is float, expected bool"
     (loc <string>:3:16))
    |}]
;;

let%expect_test "type error: bool op on float (lhs)" =
  compile_error {|
    let a : bool = var("a");
    export 1 && a;
  |};
  [%expect
    {|
    ("type error in and: left-hand side is float, expected bool"
     (loc <string>:3:11))
    |}]
;;

let%expect_test "type error: bool op on both floats" =
  compile_error
    {|
    let x : float = var("x");
    let y : float = var("y");
    export x && y;
  |};
  [%expect
    {|
    ("type error in and: both arguments are float, expected bool"
     (lhs_loc <string>:2:20) (rhs_loc <string>:3:20))
    |}]
;;

let%expect_test "type error: unary float op on bool" =
  compile_error {|
    let a : bool = var("a");
    export sqrt(a);
  |};
  [%expect
    {|
    ("type error: 'sqrt' expects a float argument but got bool"
     (loc <string>:2:19))
    |}]
;;

let%expect_test "type error: if-condition is float" =
  compile_error {|
    let x : float = var("x");
    export if x { 1 } else { 2 };
  |};
  [%expect {| ("type error: if-condition is float, expected bool" (loc <string>:2:20)) |}]
;;

let%expect_test "type error: if-arms disagree" =
  compile_error {|
    let a : bool = var("a");
    export if a { 1 } else { true };
  |};
  [%expect
    {|
    ("type error: if-arms disagree; then-branch is float but else-branch is bool"
     (then_loc <string>:3:18) (else_loc <string>:3:29))
    |}]
;;

(* === format_error tests === *)

let format_error_test source =
  match Neo.compile ~filename:"test.neo" source with
  | Ok _ -> print_endline "OK (no error)"
  | Error e -> print_endline (Neo.format_error ~source e)
;;

let%expect_test "format_error: unbound variable" =
  format_error_test "export foo;";
  [%expect
    {|
    error: unbound variable 'foo'
     --> test.neo:1:7
      |
    1 | export foo;
      |        ^
    |}]
;;

let%expect_test "format_error: type error" =
  format_error_test "let a : bool = var(\"a\");\nexport 1 + a;";
  [%expect
    {|
    error: type error in addition: right-hand side is bool, expected float
     --> test.neo:1:15
      |
    1 | let a : bool = var("a");
      |                ^
    |}]
;;
