open! Core

(** Tests for helper functions *)

let%expect_test "is_flat_member_type - primitive" =
  let type_ref = Ir.Primitive Uint32 in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - enum" =
  let type_ref = Ir.Enum "texture_format" in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - bitflag" =
  let type_ref = Ir.Bitflag "texture_usage" in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - object" =
  let type_ref = Ir.Object "device" in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "is_flat_member_type - callback" =
  let type_ref = Ir.Callback "some_callback" in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "is_flat_member_type - optional primitive" =
  let type_ref = Ir.Optional (Primitive Uint32) in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - optional struct" =
  let type_ref = Ir.Optional (Struct "extent_3d") in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "is_flat_member_type - array of primitives" =
  let type_ref = Ir.Array { elem = Primitive Uint32; pointer = None } in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - array of structs" =
  let type_ref = Ir.Array { elem = Struct "extent_3d"; pointer = None } in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "is_flat_member_type - pointer to array of primitives" =
  let type_ref =
    Ir.Pointer
      { mutable_ = false; inner = Array { elem = Primitive Uint32; pointer = None } }
  in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_flat_member_type - pointer" =
  let type_ref = Ir.Pointer { mutable_ = false; inner = Primitive Uint32 } in
  print_s [%sexp (Gen_high.For_testing.is_flat_member_type type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "is_directly_convertible_arg - primitive" =
  let type_ref = Ir.Primitive Uint32 in
  print_s [%sexp (Gen_high.For_testing.is_directly_convertible_arg type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_directly_convertible_arg - enum" =
  let type_ref = Ir.Enum "texture_format" in
  print_s [%sexp (Gen_high.For_testing.is_directly_convertible_arg type_ref : bool)];
  [%expect {| true |}]
;;

let%expect_test "is_directly_convertible_arg - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_s [%sexp (Gen_high.For_testing.is_directly_convertible_arg type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "is_directly_convertible_arg - callback" =
  let type_ref = Ir.Callback "some_callback" in
  print_s [%sexp (Gen_high.For_testing.is_directly_convertible_arg type_ref : bool)];
  [%expect {| false |}]
;;

let%expect_test "method_is_async - no callback" =
  let method_ : Ir.method_ =
    { name = "get_limits"; doc = ""; args = []; returns = None; callback = None }
  in
  print_s [%sexp (Gen_high.For_testing.method_is_async method_ : bool)];
  [%expect {| false |}]
;;

let%expect_test "method_is_async - with callback" =
  let method_ : Ir.method_ =
    { name = "request_adapter"
    ; doc = ""
    ; args = []
    ; returns = None
    ; callback = Some "request_adapter_callback"
    }
  in
  print_s [%sexp (Gen_high.For_testing.method_is_async method_ : bool)];
  [%expect {| true |}]
;;

let%expect_test "get_inline_struct_name - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_s [%sexp (Gen_high.For_testing.get_inline_struct_name type_ref : string option)];
  [%expect {| (extent_3d) |}]
;;

let%expect_test "get_inline_struct_name - not a struct" =
  let type_ref = Ir.Primitive Uint32 in
  print_s [%sexp (Gen_high.For_testing.get_inline_struct_name type_ref : string option)];
  [%expect {| () |}]
;;

let%expect_test "member_is_array_of_structs - array of structs" =
  let type_ref = Ir.Array { elem = Struct "extent_3d"; pointer = None } in
  print_s
    [%sexp (Gen_high.For_testing.member_is_array_of_structs type_ref : string option)];
  [%expect {| (extent_3d) |}]
;;

let%expect_test "member_is_array_of_structs - pointer to array of structs" =
  let type_ref =
    Ir.Pointer
      { mutable_ = false; inner = Array { elem = Struct "extent_3d"; pointer = None } }
  in
  print_s
    [%sexp (Gen_high.For_testing.member_is_array_of_structs type_ref : string option)];
  [%expect {| (extent_3d) |}]
;;

let%expect_test "member_is_array_of_structs - array of primitives" =
  let type_ref = Ir.Array { elem = Primitive Uint32; pointer = None } in
  print_s
    [%sexp (Gen_high.For_testing.member_is_array_of_structs type_ref : string option)];
  [%expect {| () |}]
;;

let%expect_test "member_is_array_of_structs - not an array" =
  let type_ref = Ir.Struct "extent_3d" in
  print_s
    [%sexp (Gen_high.For_testing.member_is_array_of_structs type_ref : string option)];
  [%expect {| () |}]
;;

let%expect_test "useful_doc - valid doc" =
  print_s [%sexp (Gen_high.For_testing.useful_doc "This is a valid doc" : string option)];
  [%expect {| ("This is a valid doc") |}]
;;

let%expect_test "useful_doc - empty doc" =
  print_s [%sexp (Gen_high.For_testing.useful_doc "" : string option)];
  [%expect {| () |}]
;;

let%expect_test "useful_doc - just TODO" =
  print_s [%sexp (Gen_high.For_testing.useful_doc "TODO" : string option)];
  [%expect {| () |}]
;;

let%expect_test "useful_doc - TODO with newline" =
  print_s [%sexp (Gen_high.For_testing.useful_doc "TODO\nSomething else" : string option)];
  [%expect {| () |}]
;;

let%expect_test "useful_doc - whitespace only" =
  print_s [%sexp (Gen_high.For_testing.useful_doc "   \n  " : string option)];
  [%expect {| () |}]
;;
