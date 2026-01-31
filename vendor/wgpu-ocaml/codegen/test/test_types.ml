open! Core

(** Tests for type mapping functions *)

let%expect_test "c_type_of_type_ref - primitive bool" =
  let type_ref = Ir.Primitive Bool in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| bool |}]
;;

let%expect_test "c_type_of_type_ref - primitive uint32" =
  let type_ref = Ir.Primitive Uint32 in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| uint32_t |}]
;;

let%expect_test "c_type_of_type_ref - primitive int32" =
  let type_ref = Ir.Primitive Int32 in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| int32_t |}]
;;

let%expect_test "c_type_of_type_ref - primitive uint64" =
  let type_ref = Ir.Primitive Uint64 in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| uint64_t |}]
;;

let%expect_test "c_type_of_type_ref - primitive float" =
  let type_ref = Ir.Primitive Float32 in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| float |}]
;;

let%expect_test "c_type_of_type_ref - primitive string" =
  let type_ref = Ir.Primitive String in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| WGPUStringView |}]
;;

let%expect_test "c_type_of_type_ref - primitive c_void" =
  let type_ref = Ir.Primitive C_void in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| void* |}]
;;

let%expect_test "c_type_of_type_ref - enum" =
  let type_ref = Ir.Enum "texture_format" in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| WGPUTextureFormat |}]
;;

let%expect_test "c_type_of_type_ref - bitflag" =
  let type_ref = Ir.Bitflag "texture_usage" in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| WGPUTextureUsage |}]
;;

let%expect_test "c_type_of_type_ref - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| WGPUExtent3d |}]
;;

let%expect_test "c_type_of_type_ref - object" =
  let type_ref = Ir.Object "device" in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| WGPUDevice |}]
;;

let%expect_test "c_type_of_type_ref - array" =
  let type_ref = Ir.Array { elem = Primitive Uint32; pointer = None } in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| uint32_t* |}]
;;

let%expect_test "c_type_of_type_ref - optional primitive" =
  let type_ref = Ir.Optional (Primitive Uint32) in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| uint32_t |}]
;;

let%expect_test "c_type_of_type_ref - pointer to primitive" =
  let type_ref = Ir.Pointer { mutable_ = false; inner = Primitive Uint32 } in
  print_endline (Gen_low.For_testing.c_type_of_type_ref type_ref);
  [%expect {| uint32_t* |}]
;;

let%expect_test "ml_type_of_type_ref - primitive bool" =
  let type_ref = Ir.Primitive Bool in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| bool |}]
;;

let%expect_test "ml_type_of_type_ref - primitive uint32" =
  let type_ref = Ir.Primitive Uint32 in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| int |}]
;;

let%expect_test "ml_type_of_type_ref - primitive uint64" =
  let type_ref = Ir.Primitive Uint64 in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| int64 |}]
;;

let%expect_test "ml_type_of_type_ref - primitive float" =
  let type_ref = Ir.Primitive Float32 in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| float |}]
;;

let%expect_test "ml_type_of_type_ref - primitive string" =
  let type_ref = Ir.Primitive String in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| string |}]
;;

let%expect_test "ml_type_of_type_ref - enum" =
  let type_ref = Ir.Enum "texture_format" in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| int |}]
;;

let%expect_test "ml_type_of_type_ref - object" =
  let type_ref = Ir.Object "device" in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| device |}]
;;

let%expect_test "ml_type_of_type_ref - struct" =
  let type_ref = Ir.Struct "extent_3d" in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| nativeint |}]
;;

let%expect_test "ml_type_of_type_ref - array of objects" =
  let type_ref = Ir.Array { elem = Object "device"; pointer = None } in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| device array |}]
;;

let%expect_test "ml_type_of_type_ref - array of ints" =
  let type_ref = Ir.Array { elem = Primitive Uint32; pointer = None } in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| int array |}]
;;

let%expect_test "ml_type_of_type_ref - optional primitive" =
  let type_ref = Ir.Optional (Primitive Uint32) in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| int |}]
;;

let%expect_test "ml_type_of_type_ref - pointer" =
  let type_ref = Ir.Pointer { mutable_ = false; inner = Primitive Uint32 } in
  print_endline (Gen_low.For_testing.ml_type_of_type_ref type_ref);
  [%expect {| nativeint |}]
;;

(* ===== Direct Type_mapping tests ===== *)

let%expect_test "Type_mapping.type_string - C_code context" =
  let test type_ref = print_endline (Type_mapping.type_string ~context:C_code type_ref) in
  test (Ir.Primitive Bool);
  test (Ir.Primitive Uint32);
  test (Ir.Primitive String);
  test (Ir.Enum "texture_format");
  test (Ir.Object "device");
  [%expect
    {|
    bool
    uint32_t
    WGPUStringView
    WGPUTextureFormat
    WGPUDevice
    |}]
;;

let%expect_test "Type_mapping.type_string - Ocaml_low_level context" =
  let test type_ref =
    print_endline (Type_mapping.type_string ~context:Ocaml_low_level type_ref)
  in
  test (Ir.Primitive Bool);
  test (Ir.Primitive Uint32);
  test (Ir.Primitive String);
  test (Ir.Enum "texture_format");
  test (Ir.Object "device");
  test (Ir.Bitflag "texture_usage");
  [%expect {|
    bool
    int
    string
    int
    device
    int
    |}]
;;

let%expect_test "Type_mapping.type_string - Ocaml_high_level_arg context" =
  let test type_ref =
    print_endline (Type_mapping.type_string ~context:Ocaml_high_level_arg type_ref)
  in
  test (Ir.Primitive Bool);
  test (Ir.Primitive Uint32);
  test (Ir.Enum "texture_format");
  test (Ir.Object "device");
  test (Ir.Bitflag "texture_usage");
  test (Ir.Optional (Ir.Object "device"));
  [%expect
    {|
    bool
    int
    Texture_format.t
    Device.t
    Texture_usage.Item.t list
    Device.t option
    |}]
;;

let%expect_test "Type_mapping.type_string - Ocaml_high_level_return context" =
  let test type_ref =
    print_endline (Type_mapping.type_string ~context:Ocaml_high_level_return type_ref)
  in
  test (Ir.Primitive Bool);
  test (Ir.Enum "texture_format");
  test (Ir.Object "device");
  test (Ir.Bitflag "texture_usage");
  (* Returns int, not list, since could be combination *)
  [%expect {|
    bool
    Texture_format.t
    Device.t
    int
    |}]
;;

let%expect_test "Type_mapping.type_string - Ocaml_high_level_member context" =
  let test type_ref =
    print_endline (Type_mapping.type_string ~context:Ocaml_high_level_member type_ref)
  in
  test (Ir.Struct "extent_3d");
  test (Ir.Array { elem = Ir.Object "device"; pointer = None });
  test (Ir.Optional (Ir.Enum "texture_format"));
  [%expect {|
    Extent_3d.t
    Device.t list
    Texture_format.t option
    |}]
;;

let%expect_test "Type_mapping.ocaml_module_name" =
  print_endline (Type_mapping.ocaml_module_name "texture_format");
  print_endline (Type_mapping.ocaml_module_name "extent_3D");
  print_endline (Type_mapping.ocaml_module_name "device");
  [%expect {|
    Texture_format
    Extent_3d
    Device
    |}]
;;

let%expect_test "Type_mapping.c_type_name" =
  print_endline (Type_mapping.c_type_name "texture_format");
  print_endline (Type_mapping.c_type_name "extent_3d");
  print_endline (Type_mapping.c_type_name "device");
  [%expect {|
    WGPUTextureFormat
    WGPUExtent3d
    WGPUDevice
    |}]
;;

(* ===== Conversion function tests ===== *)

let%expect_test "Type_mapping.convert_arg_to_low - primitives" =
  print_endline (Type_mapping.convert_arg_to_low ~var_name:"x" (Ir.Primitive Bool));
  print_endline (Type_mapping.convert_arg_to_low ~var_name:"x" (Ir.Primitive Uint32));
  [%expect {|
    x
    x
    |}]
;;

let%expect_test "Type_mapping.convert_arg_to_low - enum" =
  print_endline
    (Type_mapping.convert_arg_to_low ~var_name:"fmt" (Ir.Enum "texture_format"));
  [%expect {| (Texture_format.to_int fmt) |}]
;;

let%expect_test "Type_mapping.convert_arg_to_low - object" =
  print_endline (Type_mapping.convert_arg_to_low ~var_name:"dev" (Ir.Object "device"));
  [%expect {| dev.Device.handle |}]
;;

let%expect_test "Type_mapping.convert_arg_to_low - bitflag" =
  print_endline
    (Type_mapping.convert_arg_to_low ~var_name:"usage" (Ir.Bitflag "texture_usage"));
  [%expect {| (Texture_usage.list_to_int usage) |}]
;;

let%expect_test "Type_mapping.convert_arg_to_low - optional object" =
  print_endline
    (Type_mapping.convert_arg_to_low ~var_name:"dev" (Ir.Optional (Ir.Object "device")));
  [%expect {| (match dev with Some x -> x.Device.handle | None -> 0n) |}]
;;

let%expect_test "Type_mapping.convert_arg_to_low - array of objects" =
  print_endline
    (Type_mapping.convert_arg_to_low
       ~var_name:"devices"
       (Ir.Array { elem = Ir.Object "device"; pointer = None }));
  [%expect {| (Array.of_list (List.map (fun x -> x.Device.handle) devices)) |}]
;;

let%expect_test "Type_mapping.convert_return_to_high - primitives" =
  print_endline (Type_mapping.convert_return_to_high ~expr:"result" (Ir.Primitive Bool));
  print_endline (Type_mapping.convert_return_to_high ~expr:"result" (Ir.Primitive Uint32));
  [%expect {|
    result
    result
    |}]
;;

let%expect_test "Type_mapping.convert_return_to_high - enum" =
  print_endline
    (Type_mapping.convert_return_to_high ~expr:"result" (Ir.Enum "texture_format"));
  [%expect {| (Texture_format.of_int (result)) |}]
;;

let%expect_test "Type_mapping.convert_return_to_high - object" =
  print_endline (Type_mapping.convert_return_to_high ~expr:"result" (Ir.Object "device"));
  [%expect {| ({ Device.handle = result } : Device.t) |}]
;;

let%expect_test "Type_mapping.convert_return_to_high - bitflag" =
  print_endline
    (Type_mapping.convert_return_to_high ~expr:"result" (Ir.Bitflag "texture_usage"));
  [%expect {| result |}]
;;

let%expect_test "Type_mapping.convert_member_to_low - primitives" =
  print_endline (Type_mapping.convert_member_to_low ~var_name:"x" (Ir.Primitive Bool));
  print_endline (Type_mapping.convert_member_to_low ~var_name:"x" (Ir.Primitive Uint32));
  [%expect {|
    x
    x
    |}]
;;

let%expect_test "Type_mapping.convert_member_to_low - enum" =
  print_endline
    (Type_mapping.convert_member_to_low ~var_name:"fmt" (Ir.Enum "texture_format"));
  [%expect {| (Texture_format.to_int fmt) |}]
;;

let%expect_test "Type_mapping.convert_member_to_low - optional enum" =
  print_endline
    (Type_mapping.convert_member_to_low
       ~var_name:"fmt"
       (Ir.Optional (Ir.Enum "texture_format")));
  [%expect {| (match fmt with Some x -> Texture_format.to_int x | None -> 0) |}]
;;

let%expect_test "Type_mapping.convert_member_to_low - array of bitflags" =
  print_endline
    (Type_mapping.convert_member_to_low
       ~var_name:"usages"
       (Ir.Array { elem = Ir.Bitflag "texture_usage"; pointer = None }));
  [%expect {| (Array.of_list (List.map Texture_usage.list_to_int usages)) |}]
;;
