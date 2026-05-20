open! Core

let%expect_test _ =
  print_endline "hello world";
  [%expect {| hello world |}]
;;
