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
  [%expect {| ("expected ';' after export expression" (loc <string>:1:11)) |}]
;;

let%expect_test "parser: missing export" =
  parse_error {| 42; |};
  [%expect
    {|
    ("expected 'export' statement or top-level declaration (let, fn)"
     (loc <string>:1:1))
    |}]
;;

let%expect_test "parser: if with 'then' keyword (OCaml-style)" =
  parse_error {| export if true then { 1 } else { 2 }; |};
  [%expect {|
    ("expected '{' after 'if' condition (Neo uses 'if cond { ... } else { ... }', not 'if cond then ...')"
     (loc <string>:1:16))
    |}]
;;

let%expect_test "parser: if missing opening brace" =
  parse_error {| export if true 1 else { 2 }; |};
  [%expect {|
    ("expected '{' after 'if' condition (Neo uses 'if cond { ... } else { ... }', not 'if cond then ...')"
     (loc <string>:1:16))
    |}]
;;

let%expect_test "parser: else missing opening brace" =
  parse_error {| export if true { 1 } else 2; |};
  [%expect {|
    ("expected '{' after 'else' (Neo requires braces: 'if cond { ... } else { ... }')"
     (loc <string>:1:27))
    |}]
;;

let%expect_test "parser: missing else" =
  parse_error {| export if true { 1 }; |};
  [%expect {| ("expected 'else' branch after 'if' body" (loc <string>:1:21)) |}]
;;

let%expect_test "parser: missing closing brace" =
  parse_error {| export if true { 1 else { 2 }; |};
  [%expect {| ("expected '}' to close block" (loc <string>:1:20)) |}]
;;

let%expect_test "parser: let with no identifier" =
  parse_error {| let = 1; export 0; |};
  [%expect {| ("expected identifier after 'let'" (loc <string>:1:5)) |}]
;;

let%expect_test "parser: let with no '='" =
  parse_error {| let x 1; export 0; |};
  [%expect
    {| ("expected '=' or ':' after identifier in let binding" (loc <string>:1:7)) |}]
;;

let%expect_test "parser: let with no expression after '='" =
  parse_error {| let x = ; export 0; |};
  [%expect {| ("expected expression after '='" (loc <string>:1:9)) |}]
;;

let%expect_test "parser: let binding missing semicolon" =
  parse_error {| let x = 1 export 0; |};
  [%expect {| ("expected ';' after let binding" (loc <string>:1:11)) |}]
;;

let%expect_test "parser: let with type annotation missing '='" =
  parse_error {| let x : float 1; export 0; |};
  [%expect {| ("expected '=' after type annotation" (loc <string>:1:15)) |}]
;;

let%expect_test "parser: let with bad type annotation" =
  parse_error {| let x : foo = 1; export 0; |};
  [%expect {| ("expected type ('float' or 'bool') after ':'" (loc <string>:1:9)) |}]
;;

let%expect_test "parser: binary operator missing rhs" =
  parse_error {| export 1 + ; |};
  [%expect {| ("expected expression after operator" (loc <string>:1:12)) |}]
;;

let%expect_test "parser: comparison operator missing rhs" =
  parse_error {| export 1 < ; |};
  [%expect {| ("expected expression after operator" (loc <string>:1:12)) |}]
;;

let%expect_test "parser: logical operator missing rhs" =
  parse_error {| export true && ; |};
  [%expect {| ("expected expression after operator" (loc <string>:1:16)) |}]
;;

let%expect_test "parser: dot without method name" =
  parse_error {| export 1.(); |};
  [%expect {| ("expected method name after '.'" (loc <string>:1:10)) |}]
;;

let%expect_test "parser: method name without '('" =
  parse_error {| export 1.foo; |};
  [%expect {| ("expected '(' after method name" (loc <string>:1:13)) |}]
;;

let%expect_test "parser: fn missing '(' after name" =
  parse_error {| fn foo { 1 } export 0; |};
  [%expect {| ("expected '(' after function name" (loc <string>:1:8)) |}]
;;

let%expect_test "parser: fn missing '{' after ')'" =
  parse_error {| export fn() 1; |};
  [%expect {| ("expected '{' to open function body" (loc <string>:1:13)) |}]
;;

let%expect_test "parser: empty input" =
  parse_error {||};
  [%expect
    {|
    ("expected 'export' statement or top-level declaration (let, fn)"
     (loc <string>:1:0))
    |}]
;;

let%expect_test "parser: export with no expression" =
  parse_error {| export ; |};
  [%expect {| ("expected expression after 'export'" (loc <string>:1:8)) |}]
;;

let%expect_test "parser: extra content after export" =
  parse_error {| export 1; let x = 2; |};
  [%expect
    {|
    ("unexpected content after 'export ...;' (expected end of file)"
     (loc <string>:1:11))
    |}]
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
