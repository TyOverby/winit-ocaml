open! Core

(** Tests for name transformation functions *)

let%expect_test "to_pascal_case - basic snake_case" =
  print_endline (Gen_low.to_pascal_case "texture_format");
  [%expect {| TextureFormat |}]
;;

let%expect_test "to_pascal_case - with numbers" =
  print_endline (Gen_low.to_pascal_case "extent_3d");
  [%expect {| Extent3d |}]
;;

let%expect_test "to_pascal_case - already uppercase" =
  print_endline (Gen_low.to_pascal_case "GPU");
  [%expect {| GPU |}]
;;

let%expect_test "to_pascal_case - double underscore" =
  print_endline (Gen_low.to_pascal_case "texture__view");
  [%expect {| Texture_View |}]
;;

let%expect_test "to_pascal_case - single word" =
  print_endline (Gen_low.to_pascal_case "texture");
  [%expect {| Texture |}]
;;

let%expect_test "to_camel_case - basic snake_case" =
  print_endline (Gen_low.to_camel_case "texture_format");
  [%expect {| textureFormat |}]
;;

let%expect_test "to_camel_case - with numbers" =
  print_endline (Gen_low.to_camel_case "extent_3d");
  [%expect {| extent3d |}]
;;

let%expect_test "to_camel_case - single word" =
  print_endline (Gen_low.to_camel_case "texture");
  [%expect {| texture |}]
;;

let%expect_test "to_camel_case - empty parts" =
  print_endline (Gen_low.to_camel_case "");
  [%expect {| |}]
;;

let%expect_test "c_type_name" =
  print_endline (Gen_low.c_type_name "texture_format");
  [%expect {| WGPUTextureFormat |}]
;;

let%expect_test "c_type_name - with numbers" =
  print_endline (Gen_low.c_type_name "extent_3d");
  [%expect {| WGPUExtent3d |}]
;;

let%expect_test "c_function_name" =
  print_endline (Gen_low.c_function_name "create_instance");
  [%expect {| wgpuCreateInstance |}]
;;

let%expect_test "ocaml_module_name - basic" =
  print_endline (Gen_low.ocaml_module_name "texture_format");
  [%expect {| Texture_format |}]
;;

let%expect_test "ocaml_module_name - with uppercase" =
  print_endline (Gen_low.ocaml_module_name "extent_3D");
  [%expect {| Extent_3d |}]
;;

let%expect_test "ocaml_module_name - all caps" =
  print_endline (Gen_low.ocaml_module_name "GPU");
  [%expect {| Gpu |}]
;;

let%expect_test "normalize_enum_entry_name - basic" =
  print_endline (Gen_low.normalize_enum_entry_name "discrete_gpu");
  [%expect {| Discrete_gpu |}]
;;

let%expect_test "normalize_enum_entry_name - all caps" =
  print_endline (Gen_low.normalize_enum_entry_name "GPU");
  [%expect {| Gpu |}]
;;

let%expect_test "normalize_enum_entry_name - starts with digit" =
  print_endline (Gen_low.normalize_enum_entry_name "2d");
  [%expect {| N2d |}]
;;

let%expect_test "normalize_enum_entry_name - single word" =
  print_endline (Gen_low.normalize_enum_entry_name "undefined");
  [%expect {| Undefined |}]
;;

let%expect_test "escape_keyword - OCaml reserved word" =
  print_endline (Gen_high.escape_keyword "method");
  [%expect {| method_ |}]
;;

let%expect_test "escape_keyword - not a keyword" =
  print_endline (Gen_high.escape_keyword "my_function");
  [%expect {| my_function |}]
;;

let%expect_test "escape_keyword - another keyword" =
  print_endline (Gen_high.escape_keyword "type");
  [%expect {| type_ |}]
;;
