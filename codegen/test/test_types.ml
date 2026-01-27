open! Core

(** Tests for type mapping functions *)

let%expect_test "c_type_of_type_ref - primitive bool" =
  let type_ref = Ir.Primitive Bool in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| bool |}]
;;

let%expect_test "c_type_of_type_ref - primitive uint32" =
  let type_ref = Ir.Primitive Uint32 in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| uint32_t |}]
;;

let%expect_test "c_type_of_type_ref - primitive int32" =
  let type_ref = Ir.Primitive Int32 in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| int32_t |}]
;;

let%expect_test "c_type_of_type_ref - primitive uint64" =
  let type_ref = Ir.Primitive Uint64 in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| uint64_t |}]
;;

let%expect_test "c_type_of_type_ref - primitive float" =
  let type_ref = Ir.Primitive Float32 in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| float |}]
;;

let%expect_test "c_type_of_type_ref - primitive string" =
  let type_ref = Ir.Primitive String in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| WGPUStringView |}]
;;

let%expect_test "c_type_of_type_ref - primitive c_void" =
  let type_ref = Ir.Primitive C_void in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| void* |}]
;;

let%expect_test "c_type_of_type_ref - enum" =
  let type_ref = Ir.Enum "texture_format" in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| WGPUTextureFormat |}]
;;

let%expect_test "c_type_of_type_ref - bitflag" =
  let type_ref = Ir.Bitflag "texture_usage" in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| WGPUTextureUsage |}]
;;

let%expect_test "c_type_of_type_ref - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| WGPUExtent3d |}]
;;

let%expect_test "c_type_of_type_ref - object" =
  let type_ref = Ir.Object "device" in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| WGPUDevice |}]
;;

let%expect_test "c_type_of_type_ref - array" =
  let type_ref = Ir.Array { elem = Primitive Uint32; pointer = None } in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| uint32_t* |}]
;;

let%expect_test "c_type_of_type_ref - optional primitive" =
  let type_ref = Ir.Optional (Primitive Uint32) in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| uint32_t |}]
;;

let%expect_test "c_type_of_type_ref - pointer to primitive" =
  let type_ref = Ir.Pointer { mutable_ = false; inner = Primitive Uint32 } in
  print_endline (Gen_low.c_type_of_type_ref type_ref);
  [%expect {| uint32_t* |}]
;;

let%expect_test "ml_type_of_type_ref - primitive bool" =
  let type_ref = Ir.Primitive Bool in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| bool |}]
;;

let%expect_test "ml_type_of_type_ref - primitive uint32" =
  let type_ref = Ir.Primitive Uint32 in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| int |}]
;;

let%expect_test "ml_type_of_type_ref - primitive uint64" =
  let type_ref = Ir.Primitive Uint64 in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| int64 |}]
;;

let%expect_test "ml_type_of_type_ref - primitive float" =
  let type_ref = Ir.Primitive Float32 in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| float |}]
;;

let%expect_test "ml_type_of_type_ref - primitive string" =
  let type_ref = Ir.Primitive String in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| string |}]
;;

let%expect_test "ml_type_of_type_ref - enum" =
  let type_ref = Ir.Enum "texture_format" in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| int |}]
;;

let%expect_test "ml_type_of_type_ref - object" =
  let type_ref = Ir.Object "device" in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| device |}]
;;

let%expect_test "ml_type_of_type_ref - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| nativeint |}]
;;

let%expect_test "ml_type_of_type_ref - array of objects" =
  let type_ref = Ir.Array { elem = Object "device"; pointer = None } in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| device array |}]
;;

let%expect_test "ml_type_of_type_ref - array of ints" =
  let type_ref = Ir.Array { elem = Primitive Uint32; pointer = None } in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| int array |}]
;;

let%expect_test "ml_type_of_type_ref - optional primitive" =
  let type_ref = Ir.Optional (Primitive Uint32) in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| int |}]
;;

let%expect_test "ml_type_of_type_ref - pointer" =
  let type_ref = Ir.Pointer { mutable_ = false; inner = Primitive Uint32 } in
  print_endline (Gen_low.ml_type_of_type_ref type_ref);
  [%expect {| nativeint |}]
;;
