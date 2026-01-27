open! Core

(** Regression tests using the real webgpu.yml file.

    These tests load the actual WebGPU API specification and generate code for specific
    items, capturing the output as expect test snapshots. This helps detect regressions
    when codegen changes affect real API types. *)

(** Find the webgpu.yml file relative to the test directory. Tests can run from various
    directories depending on the build system. *)
let find_yml_path () : string =
  let candidates =
    [ "webgpu.yml"
    ; "vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ]
  in
  match List.find candidates ~f:Stdlib.Sys.file_exists with
  | Some path -> path
  | None -> failwith "Could not find webgpu.yml"
;;

let webgpu_yml_path = find_yml_path ()

(** Lazily loaded API from the real webgpu.yml *)
let api = lazy (Parse_yml.load_file webgpu_yml_path)

(** {2 Lookup Functions} *)

let lookup_enum name =
  let api = Lazy.force api in
  match List.find api.enums ~f:(fun e -> String.equal e.name name) with
  | Some e -> e
  | None -> failwithf "Enum not found: %s" name ()
;;

let lookup_bitflag name =
  let api = Lazy.force api in
  match List.find api.bitflags ~f:(fun b -> String.equal b.name name) with
  | Some b -> b
  | None -> failwithf "Bitflag not found: %s" name ()
;;

let lookup_struct name =
  let api = Lazy.force api in
  match List.find api.structs ~f:(fun s -> String.equal s.name name) with
  | Some s -> s
  | None -> failwithf "Struct not found: %s" name ()
;;

let lookup_object name =
  let api = Lazy.force api in
  match List.find api.objects ~f:(fun o -> String.equal o.name name) with
  | Some o -> o
  | None -> failwithf "Object not found: %s" name ()
;;

let lookup_method obj method_name =
  match List.find obj.Ir.methods ~f:(fun m -> String.equal m.name method_name) with
  | Some m -> m
  | None -> failwithf "Method not found: %s.%s" obj.name method_name ()
;;

let all_structs () = (Lazy.force api).structs

(** {2 Print Helpers} *)

let print_enum_outputs enum =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_enum_constants enum);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_enum enum);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_enum enum);
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_enum enum)
;;

let print_bitflag_outputs bitflag =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_bitflag_constants bitflag);
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_bitflag bitflag);
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_bitflag bitflag)
;;

let print_struct_outputs struct_ =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_)
;;

let print_method_outputs obj method_ =
  let structs = all_structs () in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method structs obj method_
     |> Option.value ~default:"(none)");
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method structs obj method_
     |> Option.value ~default:"(none)")
;;

(** {2 Enum Tests} *)

let%expect_test "enum - texture_format (real API enum with many entries)" =
  let enum = lookup_enum "texture_format" in
  print_enum_outputs enum;
  [%expect
    {|
    === Low-level C ===
    /* Enum: WGPUTextureFormat */
    CAMLprim value caml_wgpu_texture_format_undefined(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Undefined));
    }

    CAMLprim value caml_wgpu_texture_format_r8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_r8_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R8Snorm));
    }

    CAMLprim value caml_wgpu_texture_format_r8_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R8Uint));
    }

    CAMLprim value caml_wgpu_texture_format_r8_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R8Sint));
    }

    CAMLprim value caml_wgpu_texture_format_r16_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R16Uint));
    }

    CAMLprim value caml_wgpu_texture_format_r16_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R16Sint));
    }

    CAMLprim value caml_wgpu_texture_format_r16_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R16Float));
    }

    CAMLprim value caml_wgpu_texture_format_rg8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_rg8_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG8Snorm));
    }

    CAMLprim value caml_wgpu_texture_format_rg8_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG8Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rg8_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG8Sint));
    }

    CAMLprim value caml_wgpu_texture_format_r32_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R32Float));
    }

    CAMLprim value caml_wgpu_texture_format_r32_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R32Uint));
    }

    CAMLprim value caml_wgpu_texture_format_r32_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_R32Sint));
    }

    CAMLprim value caml_wgpu_texture_format_rg16_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG16Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rg16_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG16Sint));
    }

    CAMLprim value caml_wgpu_texture_format_rg16_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG16Float));
    }

    CAMLprim value caml_wgpu_texture_format_rgba8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_rgba8_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA8UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_rgba8_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA8Snorm));
    }

    CAMLprim value caml_wgpu_texture_format_rgba8_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA8Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rgba8_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA8Sint));
    }

    CAMLprim value caml_wgpu_texture_format_bgra8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BGRA8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_bgra8_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BGRA8UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_rgb10_a2_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGB10A2Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rgb10_a2_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGB10A2Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_rg11_b10_ufloat(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG11B10Ufloat));
    }

    CAMLprim value caml_wgpu_texture_format_rgb9_e5_ufloat(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGB9E5Ufloat));
    }

    CAMLprim value caml_wgpu_texture_format_rg32_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG32Float));
    }

    CAMLprim value caml_wgpu_texture_format_rg32_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG32Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rg32_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RG32Sint));
    }

    CAMLprim value caml_wgpu_texture_format_rgba16_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA16Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rgba16_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA16Sint));
    }

    CAMLprim value caml_wgpu_texture_format_rgba16_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA16Float));
    }

    CAMLprim value caml_wgpu_texture_format_rgba32_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA32Float));
    }

    CAMLprim value caml_wgpu_texture_format_rgba32_uint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA32Uint));
    }

    CAMLprim value caml_wgpu_texture_format_rgba32_sint(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_RGBA32Sint));
    }

    CAMLprim value caml_wgpu_texture_format_stencil8(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Stencil8));
    }

    CAMLprim value caml_wgpu_texture_format_depth16_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Depth16Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_depth24_plus(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Depth24Plus));
    }

    CAMLprim value caml_wgpu_texture_format_depth24_plus_stencil8(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Depth24PlusStencil8));
    }

    CAMLprim value caml_wgpu_texture_format_depth32_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Depth32Float));
    }

    CAMLprim value caml_wgpu_texture_format_depth32_float_stencil8(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Depth32FloatStencil8));
    }

    CAMLprim value caml_wgpu_texture_format_bc1_rgba_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC1RGBAUnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc1_rgba_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC1RGBAUnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_bc2_rgba_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC2RGBAUnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc2_rgba_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC2RGBAUnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_bc3_rgba_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC3RGBAUnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc3_rgba_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC3RGBAUnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_bc4_r_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC4RUnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc4_r_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC4RSnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc5_rg_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC5RGUnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc5_rg_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC5RGSnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc6h_rgb_ufloat(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC6HRGBUfloat));
    }

    CAMLprim value caml_wgpu_texture_format_bc6h_rgb_float(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC6HRGBFloat));
    }

    CAMLprim value caml_wgpu_texture_format_bc7_rgba_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC7RGBAUnorm));
    }

    CAMLprim value caml_wgpu_texture_format_bc7_rgba_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_BC7RGBAUnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_etc2_rgb8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ETC2RGB8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_etc2_rgb8_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ETC2RGB8UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_etc2_rgb8a1_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ETC2RGB8A1Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_etc2_rgb8a1_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ETC2RGB8A1UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_etc2_rgba8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ETC2RGBA8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_etc2_rgba8_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ETC2RGBA8UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_eac_r11_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_EACR11Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_eac_r11_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_EACR11Snorm));
    }

    CAMLprim value caml_wgpu_texture_format_eac_rg11_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_EACRG11Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_eac_rg11_snorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_EACRG11Snorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_4x4_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC4x4Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_4x4_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC4x4UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_5x4_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC5x4Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_5x4_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC5x4UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_5x5_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC5x5Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_5x5_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC5x5UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_6x5_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC6x5Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_6x5_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC6x5UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_6x6_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC6x6Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_6x6_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC6x6UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_8x5_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC8x5Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_8x5_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC8x5UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_8x6_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC8x6Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_8x6_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC8x6UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_8x8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC8x8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_8x8_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC8x8UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x5_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x5Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x5_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x5UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x6_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x6Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x6_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x6UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x8_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x8UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x10_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x10Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_10x10_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC10x10UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_12x10_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC12x10Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_12x10_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC12x10UnormSrgb));
    }

    CAMLprim value caml_wgpu_texture_format_astc_12x12_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC12x12Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_astc_12x12_unorm_srgb(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_ASTC12x12UnormSrgb));
    }

    === Low-level MLI ===
    module Texture_format : sig
      type t =
      | Undefined
      | R8_unorm
      | R8_snorm
      | R8_uint
      | R8_sint
      | R16_uint
      | R16_sint
      | R16_float
      | Rg8_unorm
      | Rg8_snorm
      | Rg8_uint
      | Rg8_sint
      | R32_float
      | R32_uint
      | R32_sint
      | Rg16_uint
      | Rg16_sint
      | Rg16_float
      | Rgba8_unorm
      | Rgba8_unorm_srgb
      | Rgba8_snorm
      | Rgba8_uint
      | Rgba8_sint
      | Bgra8_unorm
      | Bgra8_unorm_srgb
      | Rgb10_a2_uint
      | Rgb10_a2_unorm
      | Rg11_b10_ufloat
      | Rgb9_e5_ufloat
      | Rg32_float
      | Rg32_uint
      | Rg32_sint
      | Rgba16_uint
      | Rgba16_sint
      | Rgba16_float
      | Rgba32_float
      | Rgba32_uint
      | Rgba32_sint
      | Stencil8
      | Depth16_unorm
      | Depth24_plus
      | Depth24_plus_stencil8
      | Depth32_float
      | Depth32_float_stencil8
      | Bc1_rgba_unorm
      | Bc1_rgba_unorm_srgb
      | Bc2_rgba_unorm
      | Bc2_rgba_unorm_srgb
      | Bc3_rgba_unorm
      | Bc3_rgba_unorm_srgb
      | Bc4_r_unorm
      | Bc4_r_snorm
      | Bc5_rg_unorm
      | Bc5_rg_snorm
      | Bc6h_rgb_ufloat
      | Bc6h_rgb_float
      | Bc7_rgba_unorm
      | Bc7_rgba_unorm_srgb
      | Etc2_rgb8_unorm
      | Etc2_rgb8_unorm_srgb
      | Etc2_rgb8a1_unorm
      | Etc2_rgb8a1_unorm_srgb
      | Etc2_rgba8_unorm
      | Etc2_rgba8_unorm_srgb
      | Eac_r11_unorm
      | Eac_r11_snorm
      | Eac_rg11_unorm
      | Eac_rg11_snorm
      | Astc_4x4_unorm
      | Astc_4x4_unorm_srgb
      | Astc_5x4_unorm
      | Astc_5x4_unorm_srgb
      | Astc_5x5_unorm
      | Astc_5x5_unorm_srgb
      | Astc_6x5_unorm
      | Astc_6x5_unorm_srgb
      | Astc_6x6_unorm
      | Astc_6x6_unorm_srgb
      | Astc_8x5_unorm
      | Astc_8x5_unorm_srgb
      | Astc_8x6_unorm
      | Astc_8x6_unorm_srgb
      | Astc_8x8_unorm
      | Astc_8x8_unorm_srgb
      | Astc_10x5_unorm
      | Astc_10x5_unorm_srgb
      | Astc_10x6_unorm
      | Astc_10x6_unorm_srgb
      | Astc_10x8_unorm
      | Astc_10x8_unorm_srgb
      | Astc_10x10_unorm
      | Astc_10x10_unorm_srgb
      | Astc_12x10_unorm
      | Astc_12x10_unorm_srgb
      | Astc_12x12_unorm
      | Astc_12x12_unorm_srgb

      val to_int : t -> int
      val of_int : int -> t
    end

    === Low-level ML ===
    module Texture_format = struct
      type t =
      | Undefined
      | R8_unorm
      | R8_snorm
      | R8_uint
      | R8_sint
      | R16_uint
      | R16_sint
      | R16_float
      | Rg8_unorm
      | Rg8_snorm
      | Rg8_uint
      | Rg8_sint
      | R32_float
      | R32_uint
      | R32_sint
      | Rg16_uint
      | Rg16_sint
      | Rg16_float
      | Rgba8_unorm
      | Rgba8_unorm_srgb
      | Rgba8_snorm
      | Rgba8_uint
      | Rgba8_sint
      | Bgra8_unorm
      | Bgra8_unorm_srgb
      | Rgb10_a2_uint
      | Rgb10_a2_unorm
      | Rg11_b10_ufloat
      | Rgb9_e5_ufloat
      | Rg32_float
      | Rg32_uint
      | Rg32_sint
      | Rgba16_uint
      | Rgba16_sint
      | Rgba16_float
      | Rgba32_float
      | Rgba32_uint
      | Rgba32_sint
      | Stencil8
      | Depth16_unorm
      | Depth24_plus
      | Depth24_plus_stencil8
      | Depth32_float
      | Depth32_float_stencil8
      | Bc1_rgba_unorm
      | Bc1_rgba_unorm_srgb
      | Bc2_rgba_unorm
      | Bc2_rgba_unorm_srgb
      | Bc3_rgba_unorm
      | Bc3_rgba_unorm_srgb
      | Bc4_r_unorm
      | Bc4_r_snorm
      | Bc5_rg_unorm
      | Bc5_rg_snorm
      | Bc6h_rgb_ufloat
      | Bc6h_rgb_float
      | Bc7_rgba_unorm
      | Bc7_rgba_unorm_srgb
      | Etc2_rgb8_unorm
      | Etc2_rgb8_unorm_srgb
      | Etc2_rgb8a1_unorm
      | Etc2_rgb8a1_unorm_srgb
      | Etc2_rgba8_unorm
      | Etc2_rgba8_unorm_srgb
      | Eac_r11_unorm
      | Eac_r11_snorm
      | Eac_rg11_unorm
      | Eac_rg11_snorm
      | Astc_4x4_unorm
      | Astc_4x4_unorm_srgb
      | Astc_5x4_unorm
      | Astc_5x4_unorm_srgb
      | Astc_5x5_unorm
      | Astc_5x5_unorm_srgb
      | Astc_6x5_unorm
      | Astc_6x5_unorm_srgb
      | Astc_6x6_unorm
      | Astc_6x6_unorm_srgb
      | Astc_8x5_unorm
      | Astc_8x5_unorm_srgb
      | Astc_8x6_unorm
      | Astc_8x6_unorm_srgb
      | Astc_8x8_unorm
      | Astc_8x8_unorm_srgb
      | Astc_10x5_unorm
      | Astc_10x5_unorm_srgb
      | Astc_10x6_unorm
      | Astc_10x6_unorm_srgb
      | Astc_10x8_unorm
      | Astc_10x8_unorm_srgb
      | Astc_10x10_unorm
      | Astc_10x10_unorm_srgb
      | Astc_12x10_unorm
      | Astc_12x10_unorm_srgb
      | Astc_12x12_unorm
      | Astc_12x12_unorm_srgb

    external texture_format_undefined : unit -> int = "caml_wgpu_texture_format_undefined"
    external texture_format_r8_unorm : unit -> int = "caml_wgpu_texture_format_r8_unorm"
    external texture_format_r8_snorm : unit -> int = "caml_wgpu_texture_format_r8_snorm"
    external texture_format_r8_uint : unit -> int = "caml_wgpu_texture_format_r8_uint"
    external texture_format_r8_sint : unit -> int = "caml_wgpu_texture_format_r8_sint"
    external texture_format_r16_uint : unit -> int = "caml_wgpu_texture_format_r16_uint"
    external texture_format_r16_sint : unit -> int = "caml_wgpu_texture_format_r16_sint"
    external texture_format_r16_float : unit -> int = "caml_wgpu_texture_format_r16_float"
    external texture_format_rg8_unorm : unit -> int = "caml_wgpu_texture_format_rg8_unorm"
    external texture_format_rg8_snorm : unit -> int = "caml_wgpu_texture_format_rg8_snorm"
    external texture_format_rg8_uint : unit -> int = "caml_wgpu_texture_format_rg8_uint"
    external texture_format_rg8_sint : unit -> int = "caml_wgpu_texture_format_rg8_sint"
    external texture_format_r32_float : unit -> int = "caml_wgpu_texture_format_r32_float"
    external texture_format_r32_uint : unit -> int = "caml_wgpu_texture_format_r32_uint"
    external texture_format_r32_sint : unit -> int = "caml_wgpu_texture_format_r32_sint"
    external texture_format_rg16_uint : unit -> int = "caml_wgpu_texture_format_rg16_uint"
    external texture_format_rg16_sint : unit -> int = "caml_wgpu_texture_format_rg16_sint"
    external texture_format_rg16_float : unit -> int = "caml_wgpu_texture_format_rg16_float"
    external texture_format_rgba8_unorm : unit -> int = "caml_wgpu_texture_format_rgba8_unorm"
    external texture_format_rgba8_unorm_srgb : unit -> int = "caml_wgpu_texture_format_rgba8_unorm_srgb"
    external texture_format_rgba8_snorm : unit -> int = "caml_wgpu_texture_format_rgba8_snorm"
    external texture_format_rgba8_uint : unit -> int = "caml_wgpu_texture_format_rgba8_uint"
    external texture_format_rgba8_sint : unit -> int = "caml_wgpu_texture_format_rgba8_sint"
    external texture_format_bgra8_unorm : unit -> int = "caml_wgpu_texture_format_bgra8_unorm"
    external texture_format_bgra8_unorm_srgb : unit -> int = "caml_wgpu_texture_format_bgra8_unorm_srgb"
    external texture_format_rgb10_a2_uint : unit -> int = "caml_wgpu_texture_format_rgb10_a2_uint"
    external texture_format_rgb10_a2_unorm : unit -> int = "caml_wgpu_texture_format_rgb10_a2_unorm"
    external texture_format_rg11_b10_ufloat : unit -> int = "caml_wgpu_texture_format_rg11_b10_ufloat"
    external texture_format_rgb9_e5_ufloat : unit -> int = "caml_wgpu_texture_format_rgb9_e5_ufloat"
    external texture_format_rg32_float : unit -> int = "caml_wgpu_texture_format_rg32_float"
    external texture_format_rg32_uint : unit -> int = "caml_wgpu_texture_format_rg32_uint"
    external texture_format_rg32_sint : unit -> int = "caml_wgpu_texture_format_rg32_sint"
    external texture_format_rgba16_uint : unit -> int = "caml_wgpu_texture_format_rgba16_uint"
    external texture_format_rgba16_sint : unit -> int = "caml_wgpu_texture_format_rgba16_sint"
    external texture_format_rgba16_float : unit -> int = "caml_wgpu_texture_format_rgba16_float"
    external texture_format_rgba32_float : unit -> int = "caml_wgpu_texture_format_rgba32_float"
    external texture_format_rgba32_uint : unit -> int = "caml_wgpu_texture_format_rgba32_uint"
    external texture_format_rgba32_sint : unit -> int = "caml_wgpu_texture_format_rgba32_sint"
    external texture_format_stencil8 : unit -> int = "caml_wgpu_texture_format_stencil8"
    external texture_format_depth16_unorm : unit -> int = "caml_wgpu_texture_format_depth16_unorm"
    external texture_format_depth24_plus : unit -> int = "caml_wgpu_texture_format_depth24_plus"
    external texture_format_depth24_plus_stencil8 : unit -> int = "caml_wgpu_texture_format_depth24_plus_stencil8"
    external texture_format_depth32_float : unit -> int = "caml_wgpu_texture_format_depth32_float"
    external texture_format_depth32_float_stencil8 : unit -> int = "caml_wgpu_texture_format_depth32_float_stencil8"
    external texture_format_bc1_rgba_unorm : unit -> int = "caml_wgpu_texture_format_bc1_rgba_unorm"
    external texture_format_bc1_rgba_unorm_srgb : unit -> int = "caml_wgpu_texture_format_bc1_rgba_unorm_srgb"
    external texture_format_bc2_rgba_unorm : unit -> int = "caml_wgpu_texture_format_bc2_rgba_unorm"
    external texture_format_bc2_rgba_unorm_srgb : unit -> int = "caml_wgpu_texture_format_bc2_rgba_unorm_srgb"
    external texture_format_bc3_rgba_unorm : unit -> int = "caml_wgpu_texture_format_bc3_rgba_unorm"
    external texture_format_bc3_rgba_unorm_srgb : unit -> int = "caml_wgpu_texture_format_bc3_rgba_unorm_srgb"
    external texture_format_bc4_r_unorm : unit -> int = "caml_wgpu_texture_format_bc4_r_unorm"
    external texture_format_bc4_r_snorm : unit -> int = "caml_wgpu_texture_format_bc4_r_snorm"
    external texture_format_bc5_rg_unorm : unit -> int = "caml_wgpu_texture_format_bc5_rg_unorm"
    external texture_format_bc5_rg_snorm : unit -> int = "caml_wgpu_texture_format_bc5_rg_snorm"
    external texture_format_bc6h_rgb_ufloat : unit -> int = "caml_wgpu_texture_format_bc6h_rgb_ufloat"
    external texture_format_bc6h_rgb_float : unit -> int = "caml_wgpu_texture_format_bc6h_rgb_float"
    external texture_format_bc7_rgba_unorm : unit -> int = "caml_wgpu_texture_format_bc7_rgba_unorm"
    external texture_format_bc7_rgba_unorm_srgb : unit -> int = "caml_wgpu_texture_format_bc7_rgba_unorm_srgb"
    external texture_format_etc2_rgb8_unorm : unit -> int = "caml_wgpu_texture_format_etc2_rgb8_unorm"
    external texture_format_etc2_rgb8_unorm_srgb : unit -> int = "caml_wgpu_texture_format_etc2_rgb8_unorm_srgb"
    external texture_format_etc2_rgb8a1_unorm : unit -> int = "caml_wgpu_texture_format_etc2_rgb8a1_unorm"
    external texture_format_etc2_rgb8a1_unorm_srgb : unit -> int = "caml_wgpu_texture_format_etc2_rgb8a1_unorm_srgb"
    external texture_format_etc2_rgba8_unorm : unit -> int = "caml_wgpu_texture_format_etc2_rgba8_unorm"
    external texture_format_etc2_rgba8_unorm_srgb : unit -> int = "caml_wgpu_texture_format_etc2_rgba8_unorm_srgb"
    external texture_format_eac_r11_unorm : unit -> int = "caml_wgpu_texture_format_eac_r11_unorm"
    external texture_format_eac_r11_snorm : unit -> int = "caml_wgpu_texture_format_eac_r11_snorm"
    external texture_format_eac_rg11_unorm : unit -> int = "caml_wgpu_texture_format_eac_rg11_unorm"
    external texture_format_eac_rg11_snorm : unit -> int = "caml_wgpu_texture_format_eac_rg11_snorm"
    external texture_format_astc_4x4_unorm : unit -> int = "caml_wgpu_texture_format_astc_4x4_unorm"
    external texture_format_astc_4x4_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_4x4_unorm_srgb"
    external texture_format_astc_5x4_unorm : unit -> int = "caml_wgpu_texture_format_astc_5x4_unorm"
    external texture_format_astc_5x4_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_5x4_unorm_srgb"
    external texture_format_astc_5x5_unorm : unit -> int = "caml_wgpu_texture_format_astc_5x5_unorm"
    external texture_format_astc_5x5_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_5x5_unorm_srgb"
    external texture_format_astc_6x5_unorm : unit -> int = "caml_wgpu_texture_format_astc_6x5_unorm"
    external texture_format_astc_6x5_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_6x5_unorm_srgb"
    external texture_format_astc_6x6_unorm : unit -> int = "caml_wgpu_texture_format_astc_6x6_unorm"
    external texture_format_astc_6x6_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_6x6_unorm_srgb"
    external texture_format_astc_8x5_unorm : unit -> int = "caml_wgpu_texture_format_astc_8x5_unorm"
    external texture_format_astc_8x5_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_8x5_unorm_srgb"
    external texture_format_astc_8x6_unorm : unit -> int = "caml_wgpu_texture_format_astc_8x6_unorm"
    external texture_format_astc_8x6_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_8x6_unorm_srgb"
    external texture_format_astc_8x8_unorm : unit -> int = "caml_wgpu_texture_format_astc_8x8_unorm"
    external texture_format_astc_8x8_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_8x8_unorm_srgb"
    external texture_format_astc_10x5_unorm : unit -> int = "caml_wgpu_texture_format_astc_10x5_unorm"
    external texture_format_astc_10x5_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_10x5_unorm_srgb"
    external texture_format_astc_10x6_unorm : unit -> int = "caml_wgpu_texture_format_astc_10x6_unorm"
    external texture_format_astc_10x6_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_10x6_unorm_srgb"
    external texture_format_astc_10x8_unorm : unit -> int = "caml_wgpu_texture_format_astc_10x8_unorm"
    external texture_format_astc_10x8_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_10x8_unorm_srgb"
    external texture_format_astc_10x10_unorm : unit -> int = "caml_wgpu_texture_format_astc_10x10_unorm"
    external texture_format_astc_10x10_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_10x10_unorm_srgb"
    external texture_format_astc_12x10_unorm : unit -> int = "caml_wgpu_texture_format_astc_12x10_unorm"
    external texture_format_astc_12x10_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_12x10_unorm_srgb"
    external texture_format_astc_12x12_unorm : unit -> int = "caml_wgpu_texture_format_astc_12x12_unorm"
    external texture_format_astc_12x12_unorm_srgb : unit -> int = "caml_wgpu_texture_format_astc_12x12_unorm_srgb"

      let undefined_int = texture_format_undefined ()
      let r8_unorm_int = texture_format_r8_unorm ()
      let r8_snorm_int = texture_format_r8_snorm ()
      let r8_uint_int = texture_format_r8_uint ()
      let r8_sint_int = texture_format_r8_sint ()
      let r16_uint_int = texture_format_r16_uint ()
      let r16_sint_int = texture_format_r16_sint ()
      let r16_float_int = texture_format_r16_float ()
      let rg8_unorm_int = texture_format_rg8_unorm ()
      let rg8_snorm_int = texture_format_rg8_snorm ()
      let rg8_uint_int = texture_format_rg8_uint ()
      let rg8_sint_int = texture_format_rg8_sint ()
      let r32_float_int = texture_format_r32_float ()
      let r32_uint_int = texture_format_r32_uint ()
      let r32_sint_int = texture_format_r32_sint ()
      let rg16_uint_int = texture_format_rg16_uint ()
      let rg16_sint_int = texture_format_rg16_sint ()
      let rg16_float_int = texture_format_rg16_float ()
      let rgba8_unorm_int = texture_format_rgba8_unorm ()
      let rgba8_unorm_srgb_int = texture_format_rgba8_unorm_srgb ()
      let rgba8_snorm_int = texture_format_rgba8_snorm ()
      let rgba8_uint_int = texture_format_rgba8_uint ()
      let rgba8_sint_int = texture_format_rgba8_sint ()
      let bgra8_unorm_int = texture_format_bgra8_unorm ()
      let bgra8_unorm_srgb_int = texture_format_bgra8_unorm_srgb ()
      let rgb10_a2_uint_int = texture_format_rgb10_a2_uint ()
      let rgb10_a2_unorm_int = texture_format_rgb10_a2_unorm ()
      let rg11_b10_ufloat_int = texture_format_rg11_b10_ufloat ()
      let rgb9_e5_ufloat_int = texture_format_rgb9_e5_ufloat ()
      let rg32_float_int = texture_format_rg32_float ()
      let rg32_uint_int = texture_format_rg32_uint ()
      let rg32_sint_int = texture_format_rg32_sint ()
      let rgba16_uint_int = texture_format_rgba16_uint ()
      let rgba16_sint_int = texture_format_rgba16_sint ()
      let rgba16_float_int = texture_format_rgba16_float ()
      let rgba32_float_int = texture_format_rgba32_float ()
      let rgba32_uint_int = texture_format_rgba32_uint ()
      let rgba32_sint_int = texture_format_rgba32_sint ()
      let stencil8_int = texture_format_stencil8 ()
      let depth16_unorm_int = texture_format_depth16_unorm ()
      let depth24_plus_int = texture_format_depth24_plus ()
      let depth24_plus_stencil8_int = texture_format_depth24_plus_stencil8 ()
      let depth32_float_int = texture_format_depth32_float ()
      let depth32_float_stencil8_int = texture_format_depth32_float_stencil8 ()
      let bc1_rgba_unorm_int = texture_format_bc1_rgba_unorm ()
      let bc1_rgba_unorm_srgb_int = texture_format_bc1_rgba_unorm_srgb ()
      let bc2_rgba_unorm_int = texture_format_bc2_rgba_unorm ()
      let bc2_rgba_unorm_srgb_int = texture_format_bc2_rgba_unorm_srgb ()
      let bc3_rgba_unorm_int = texture_format_bc3_rgba_unorm ()
      let bc3_rgba_unorm_srgb_int = texture_format_bc3_rgba_unorm_srgb ()
      let bc4_r_unorm_int = texture_format_bc4_r_unorm ()
      let bc4_r_snorm_int = texture_format_bc4_r_snorm ()
      let bc5_rg_unorm_int = texture_format_bc5_rg_unorm ()
      let bc5_rg_snorm_int = texture_format_bc5_rg_snorm ()
      let bc6h_rgb_ufloat_int = texture_format_bc6h_rgb_ufloat ()
      let bc6h_rgb_float_int = texture_format_bc6h_rgb_float ()
      let bc7_rgba_unorm_int = texture_format_bc7_rgba_unorm ()
      let bc7_rgba_unorm_srgb_int = texture_format_bc7_rgba_unorm_srgb ()
      let etc2_rgb8_unorm_int = texture_format_etc2_rgb8_unorm ()
      let etc2_rgb8_unorm_srgb_int = texture_format_etc2_rgb8_unorm_srgb ()
      let etc2_rgb8a1_unorm_int = texture_format_etc2_rgb8a1_unorm ()
      let etc2_rgb8a1_unorm_srgb_int = texture_format_etc2_rgb8a1_unorm_srgb ()
      let etc2_rgba8_unorm_int = texture_format_etc2_rgba8_unorm ()
      let etc2_rgba8_unorm_srgb_int = texture_format_etc2_rgba8_unorm_srgb ()
      let eac_r11_unorm_int = texture_format_eac_r11_unorm ()
      let eac_r11_snorm_int = texture_format_eac_r11_snorm ()
      let eac_rg11_unorm_int = texture_format_eac_rg11_unorm ()
      let eac_rg11_snorm_int = texture_format_eac_rg11_snorm ()
      let astc_4x4_unorm_int = texture_format_astc_4x4_unorm ()
      let astc_4x4_unorm_srgb_int = texture_format_astc_4x4_unorm_srgb ()
      let astc_5x4_unorm_int = texture_format_astc_5x4_unorm ()
      let astc_5x4_unorm_srgb_int = texture_format_astc_5x4_unorm_srgb ()
      let astc_5x5_unorm_int = texture_format_astc_5x5_unorm ()
      let astc_5x5_unorm_srgb_int = texture_format_astc_5x5_unorm_srgb ()
      let astc_6x5_unorm_int = texture_format_astc_6x5_unorm ()
      let astc_6x5_unorm_srgb_int = texture_format_astc_6x5_unorm_srgb ()
      let astc_6x6_unorm_int = texture_format_astc_6x6_unorm ()
      let astc_6x6_unorm_srgb_int = texture_format_astc_6x6_unorm_srgb ()
      let astc_8x5_unorm_int = texture_format_astc_8x5_unorm ()
      let astc_8x5_unorm_srgb_int = texture_format_astc_8x5_unorm_srgb ()
      let astc_8x6_unorm_int = texture_format_astc_8x6_unorm ()
      let astc_8x6_unorm_srgb_int = texture_format_astc_8x6_unorm_srgb ()
      let astc_8x8_unorm_int = texture_format_astc_8x8_unorm ()
      let astc_8x8_unorm_srgb_int = texture_format_astc_8x8_unorm_srgb ()
      let astc_10x5_unorm_int = texture_format_astc_10x5_unorm ()
      let astc_10x5_unorm_srgb_int = texture_format_astc_10x5_unorm_srgb ()
      let astc_10x6_unorm_int = texture_format_astc_10x6_unorm ()
      let astc_10x6_unorm_srgb_int = texture_format_astc_10x6_unorm_srgb ()
      let astc_10x8_unorm_int = texture_format_astc_10x8_unorm ()
      let astc_10x8_unorm_srgb_int = texture_format_astc_10x8_unorm_srgb ()
      let astc_10x10_unorm_int = texture_format_astc_10x10_unorm ()
      let astc_10x10_unorm_srgb_int = texture_format_astc_10x10_unorm_srgb ()
      let astc_12x10_unorm_int = texture_format_astc_12x10_unorm ()
      let astc_12x10_unorm_srgb_int = texture_format_astc_12x10_unorm_srgb ()
      let astc_12x12_unorm_int = texture_format_astc_12x12_unorm ()
      let astc_12x12_unorm_srgb_int = texture_format_astc_12x12_unorm_srgb ()

      let to_int = function
        | Undefined -> undefined_int
        | R8_unorm -> r8_unorm_int
        | R8_snorm -> r8_snorm_int
        | R8_uint -> r8_uint_int
        | R8_sint -> r8_sint_int
        | R16_uint -> r16_uint_int
        | R16_sint -> r16_sint_int
        | R16_float -> r16_float_int
        | Rg8_unorm -> rg8_unorm_int
        | Rg8_snorm -> rg8_snorm_int
        | Rg8_uint -> rg8_uint_int
        | Rg8_sint -> rg8_sint_int
        | R32_float -> r32_float_int
        | R32_uint -> r32_uint_int
        | R32_sint -> r32_sint_int
        | Rg16_uint -> rg16_uint_int
        | Rg16_sint -> rg16_sint_int
        | Rg16_float -> rg16_float_int
        | Rgba8_unorm -> rgba8_unorm_int
        | Rgba8_unorm_srgb -> rgba8_unorm_srgb_int
        | Rgba8_snorm -> rgba8_snorm_int
        | Rgba8_uint -> rgba8_uint_int
        | Rgba8_sint -> rgba8_sint_int
        | Bgra8_unorm -> bgra8_unorm_int
        | Bgra8_unorm_srgb -> bgra8_unorm_srgb_int
        | Rgb10_a2_uint -> rgb10_a2_uint_int
        | Rgb10_a2_unorm -> rgb10_a2_unorm_int
        | Rg11_b10_ufloat -> rg11_b10_ufloat_int
        | Rgb9_e5_ufloat -> rgb9_e5_ufloat_int
        | Rg32_float -> rg32_float_int
        | Rg32_uint -> rg32_uint_int
        | Rg32_sint -> rg32_sint_int
        | Rgba16_uint -> rgba16_uint_int
        | Rgba16_sint -> rgba16_sint_int
        | Rgba16_float -> rgba16_float_int
        | Rgba32_float -> rgba32_float_int
        | Rgba32_uint -> rgba32_uint_int
        | Rgba32_sint -> rgba32_sint_int
        | Stencil8 -> stencil8_int
        | Depth16_unorm -> depth16_unorm_int
        | Depth24_plus -> depth24_plus_int
        | Depth24_plus_stencil8 -> depth24_plus_stencil8_int
        | Depth32_float -> depth32_float_int
        | Depth32_float_stencil8 -> depth32_float_stencil8_int
        | Bc1_rgba_unorm -> bc1_rgba_unorm_int
        | Bc1_rgba_unorm_srgb -> bc1_rgba_unorm_srgb_int
        | Bc2_rgba_unorm -> bc2_rgba_unorm_int
        | Bc2_rgba_unorm_srgb -> bc2_rgba_unorm_srgb_int
        | Bc3_rgba_unorm -> bc3_rgba_unorm_int
        | Bc3_rgba_unorm_srgb -> bc3_rgba_unorm_srgb_int
        | Bc4_r_unorm -> bc4_r_unorm_int
        | Bc4_r_snorm -> bc4_r_snorm_int
        | Bc5_rg_unorm -> bc5_rg_unorm_int
        | Bc5_rg_snorm -> bc5_rg_snorm_int
        | Bc6h_rgb_ufloat -> bc6h_rgb_ufloat_int
        | Bc6h_rgb_float -> bc6h_rgb_float_int
        | Bc7_rgba_unorm -> bc7_rgba_unorm_int
        | Bc7_rgba_unorm_srgb -> bc7_rgba_unorm_srgb_int
        | Etc2_rgb8_unorm -> etc2_rgb8_unorm_int
        | Etc2_rgb8_unorm_srgb -> etc2_rgb8_unorm_srgb_int
        | Etc2_rgb8a1_unorm -> etc2_rgb8a1_unorm_int
        | Etc2_rgb8a1_unorm_srgb -> etc2_rgb8a1_unorm_srgb_int
        | Etc2_rgba8_unorm -> etc2_rgba8_unorm_int
        | Etc2_rgba8_unorm_srgb -> etc2_rgba8_unorm_srgb_int
        | Eac_r11_unorm -> eac_r11_unorm_int
        | Eac_r11_snorm -> eac_r11_snorm_int
        | Eac_rg11_unorm -> eac_rg11_unorm_int
        | Eac_rg11_snorm -> eac_rg11_snorm_int
        | Astc_4x4_unorm -> astc_4x4_unorm_int
        | Astc_4x4_unorm_srgb -> astc_4x4_unorm_srgb_int
        | Astc_5x4_unorm -> astc_5x4_unorm_int
        | Astc_5x4_unorm_srgb -> astc_5x4_unorm_srgb_int
        | Astc_5x5_unorm -> astc_5x5_unorm_int
        | Astc_5x5_unorm_srgb -> astc_5x5_unorm_srgb_int
        | Astc_6x5_unorm -> astc_6x5_unorm_int
        | Astc_6x5_unorm_srgb -> astc_6x5_unorm_srgb_int
        | Astc_6x6_unorm -> astc_6x6_unorm_int
        | Astc_6x6_unorm_srgb -> astc_6x6_unorm_srgb_int
        | Astc_8x5_unorm -> astc_8x5_unorm_int
        | Astc_8x5_unorm_srgb -> astc_8x5_unorm_srgb_int
        | Astc_8x6_unorm -> astc_8x6_unorm_int
        | Astc_8x6_unorm_srgb -> astc_8x6_unorm_srgb_int
        | Astc_8x8_unorm -> astc_8x8_unorm_int
        | Astc_8x8_unorm_srgb -> astc_8x8_unorm_srgb_int
        | Astc_10x5_unorm -> astc_10x5_unorm_int
        | Astc_10x5_unorm_srgb -> astc_10x5_unorm_srgb_int
        | Astc_10x6_unorm -> astc_10x6_unorm_int
        | Astc_10x6_unorm_srgb -> astc_10x6_unorm_srgb_int
        | Astc_10x8_unorm -> astc_10x8_unorm_int
        | Astc_10x8_unorm_srgb -> astc_10x8_unorm_srgb_int
        | Astc_10x10_unorm -> astc_10x10_unorm_int
        | Astc_10x10_unorm_srgb -> astc_10x10_unorm_srgb_int
        | Astc_12x10_unorm -> astc_12x10_unorm_int
        | Astc_12x10_unorm_srgb -> astc_12x10_unorm_srgb_int
        | Astc_12x12_unorm -> astc_12x12_unorm_int
        | Astc_12x12_unorm_srgb -> astc_12x12_unorm_srgb_int

      let of_int = function
        | x when x = undefined_int -> Undefined
        | x when x = r8_unorm_int -> R8_unorm
        | x when x = r8_snorm_int -> R8_snorm
        | x when x = r8_uint_int -> R8_uint
        | x when x = r8_sint_int -> R8_sint
        | x when x = r16_uint_int -> R16_uint
        | x when x = r16_sint_int -> R16_sint
        | x when x = r16_float_int -> R16_float
        | x when x = rg8_unorm_int -> Rg8_unorm
        | x when x = rg8_snorm_int -> Rg8_snorm
        | x when x = rg8_uint_int -> Rg8_uint
        | x when x = rg8_sint_int -> Rg8_sint
        | x when x = r32_float_int -> R32_float
        | x when x = r32_uint_int -> R32_uint
        | x when x = r32_sint_int -> R32_sint
        | x when x = rg16_uint_int -> Rg16_uint
        | x when x = rg16_sint_int -> Rg16_sint
        | x when x = rg16_float_int -> Rg16_float
        | x when x = rgba8_unorm_int -> Rgba8_unorm
        | x when x = rgba8_unorm_srgb_int -> Rgba8_unorm_srgb
        | x when x = rgba8_snorm_int -> Rgba8_snorm
        | x when x = rgba8_uint_int -> Rgba8_uint
        | x when x = rgba8_sint_int -> Rgba8_sint
        | x when x = bgra8_unorm_int -> Bgra8_unorm
        | x when x = bgra8_unorm_srgb_int -> Bgra8_unorm_srgb
        | x when x = rgb10_a2_uint_int -> Rgb10_a2_uint
        | x when x = rgb10_a2_unorm_int -> Rgb10_a2_unorm
        | x when x = rg11_b10_ufloat_int -> Rg11_b10_ufloat
        | x when x = rgb9_e5_ufloat_int -> Rgb9_e5_ufloat
        | x when x = rg32_float_int -> Rg32_float
        | x when x = rg32_uint_int -> Rg32_uint
        | x when x = rg32_sint_int -> Rg32_sint
        | x when x = rgba16_uint_int -> Rgba16_uint
        | x when x = rgba16_sint_int -> Rgba16_sint
        | x when x = rgba16_float_int -> Rgba16_float
        | x when x = rgba32_float_int -> Rgba32_float
        | x when x = rgba32_uint_int -> Rgba32_uint
        | x when x = rgba32_sint_int -> Rgba32_sint
        | x when x = stencil8_int -> Stencil8
        | x when x = depth16_unorm_int -> Depth16_unorm
        | x when x = depth24_plus_int -> Depth24_plus
        | x when x = depth24_plus_stencil8_int -> Depth24_plus_stencil8
        | x when x = depth32_float_int -> Depth32_float
        | x when x = depth32_float_stencil8_int -> Depth32_float_stencil8
        | x when x = bc1_rgba_unorm_int -> Bc1_rgba_unorm
        | x when x = bc1_rgba_unorm_srgb_int -> Bc1_rgba_unorm_srgb
        | x when x = bc2_rgba_unorm_int -> Bc2_rgba_unorm
        | x when x = bc2_rgba_unorm_srgb_int -> Bc2_rgba_unorm_srgb
        | x when x = bc3_rgba_unorm_int -> Bc3_rgba_unorm
        | x when x = bc3_rgba_unorm_srgb_int -> Bc3_rgba_unorm_srgb
        | x when x = bc4_r_unorm_int -> Bc4_r_unorm
        | x when x = bc4_r_snorm_int -> Bc4_r_snorm
        | x when x = bc5_rg_unorm_int -> Bc5_rg_unorm
        | x when x = bc5_rg_snorm_int -> Bc5_rg_snorm
        | x when x = bc6h_rgb_ufloat_int -> Bc6h_rgb_ufloat
        | x when x = bc6h_rgb_float_int -> Bc6h_rgb_float
        | x when x = bc7_rgba_unorm_int -> Bc7_rgba_unorm
        | x when x = bc7_rgba_unorm_srgb_int -> Bc7_rgba_unorm_srgb
        | x when x = etc2_rgb8_unorm_int -> Etc2_rgb8_unorm
        | x when x = etc2_rgb8_unorm_srgb_int -> Etc2_rgb8_unorm_srgb
        | x when x = etc2_rgb8a1_unorm_int -> Etc2_rgb8a1_unorm
        | x when x = etc2_rgb8a1_unorm_srgb_int -> Etc2_rgb8a1_unorm_srgb
        | x when x = etc2_rgba8_unorm_int -> Etc2_rgba8_unorm
        | x when x = etc2_rgba8_unorm_srgb_int -> Etc2_rgba8_unorm_srgb
        | x when x = eac_r11_unorm_int -> Eac_r11_unorm
        | x when x = eac_r11_snorm_int -> Eac_r11_snorm
        | x when x = eac_rg11_unorm_int -> Eac_rg11_unorm
        | x when x = eac_rg11_snorm_int -> Eac_rg11_snorm
        | x when x = astc_4x4_unorm_int -> Astc_4x4_unorm
        | x when x = astc_4x4_unorm_srgb_int -> Astc_4x4_unorm_srgb
        | x when x = astc_5x4_unorm_int -> Astc_5x4_unorm
        | x when x = astc_5x4_unorm_srgb_int -> Astc_5x4_unorm_srgb
        | x when x = astc_5x5_unorm_int -> Astc_5x5_unorm
        | x when x = astc_5x5_unorm_srgb_int -> Astc_5x5_unorm_srgb
        | x when x = astc_6x5_unorm_int -> Astc_6x5_unorm
        | x when x = astc_6x5_unorm_srgb_int -> Astc_6x5_unorm_srgb
        | x when x = astc_6x6_unorm_int -> Astc_6x6_unorm
        | x when x = astc_6x6_unorm_srgb_int -> Astc_6x6_unorm_srgb
        | x when x = astc_8x5_unorm_int -> Astc_8x5_unorm
        | x when x = astc_8x5_unorm_srgb_int -> Astc_8x5_unorm_srgb
        | x when x = astc_8x6_unorm_int -> Astc_8x6_unorm
        | x when x = astc_8x6_unorm_srgb_int -> Astc_8x6_unorm_srgb
        | x when x = astc_8x8_unorm_int -> Astc_8x8_unorm
        | x when x = astc_8x8_unorm_srgb_int -> Astc_8x8_unorm_srgb
        | x when x = astc_10x5_unorm_int -> Astc_10x5_unorm
        | x when x = astc_10x5_unorm_srgb_int -> Astc_10x5_unorm_srgb
        | x when x = astc_10x6_unorm_int -> Astc_10x6_unorm
        | x when x = astc_10x6_unorm_srgb_int -> Astc_10x6_unorm_srgb
        | x when x = astc_10x8_unorm_int -> Astc_10x8_unorm
        | x when x = astc_10x8_unorm_srgb_int -> Astc_10x8_unorm_srgb
        | x when x = astc_10x10_unorm_int -> Astc_10x10_unorm
        | x when x = astc_10x10_unorm_srgb_int -> Astc_10x10_unorm_srgb
        | x when x = astc_12x10_unorm_int -> Astc_12x10_unorm
        | x when x = astc_12x10_unorm_srgb_int -> Astc_12x10_unorm_srgb
        | x when x = astc_12x12_unorm_int -> Astc_12x12_unorm
        | x when x = astc_12x12_unorm_srgb_int -> Astc_12x12_unorm_srgb
        | n -> failwith (Printf.sprintf "Texture_format.of_int: unknown value %d" n)
    end

    === High-level MLI ===
    module Texture_format : sig
      type t =
      | Undefined
      | R8_unorm
      | R8_snorm
      | R8_uint
      | R8_sint
      | R16_uint
      | R16_sint
      | R16_float
      | Rg8_unorm
      | Rg8_snorm
      | Rg8_uint
      | Rg8_sint
      | R32_float
      | R32_uint
      | R32_sint
      | Rg16_uint
      | Rg16_sint
      | Rg16_float
      | Rgba8_unorm
      | Rgba8_unorm_srgb
      | Rgba8_snorm
      | Rgba8_uint
      | Rgba8_sint
      | Bgra8_unorm
      | Bgra8_unorm_srgb
      | Rgb10_a2_uint
      | Rgb10_a2_unorm
      | Rg11_b10_ufloat
      | Rgb9_e5_ufloat
      | Rg32_float
      | Rg32_uint
      | Rg32_sint
      | Rgba16_uint
      | Rgba16_sint
      | Rgba16_float
      | Rgba32_float
      | Rgba32_uint
      | Rgba32_sint
      | Stencil8
      | Depth16_unorm
      | Depth24_plus
      | Depth24_plus_stencil8
      | Depth32_float
      | Depth32_float_stencil8
      | Bc1_rgba_unorm
      | Bc1_rgba_unorm_srgb
      | Bc2_rgba_unorm
      | Bc2_rgba_unorm_srgb
      | Bc3_rgba_unorm
      | Bc3_rgba_unorm_srgb
      | Bc4_r_unorm
      | Bc4_r_snorm
      | Bc5_rg_unorm
      | Bc5_rg_snorm
      | Bc6h_rgb_ufloat
      | Bc6h_rgb_float
      | Bc7_rgba_unorm
      | Bc7_rgba_unorm_srgb
      | Etc2_rgb8_unorm
      | Etc2_rgb8_unorm_srgb
      | Etc2_rgb8a1_unorm
      | Etc2_rgb8a1_unorm_srgb
      | Etc2_rgba8_unorm
      | Etc2_rgba8_unorm_srgb
      | Eac_r11_unorm
      | Eac_r11_snorm
      | Eac_rg11_unorm
      | Eac_rg11_snorm
      | Astc_4x4_unorm
      | Astc_4x4_unorm_srgb
      | Astc_5x4_unorm
      | Astc_5x4_unorm_srgb
      | Astc_5x5_unorm
      | Astc_5x5_unorm_srgb
      | Astc_6x5_unorm
      | Astc_6x5_unorm_srgb
      | Astc_6x6_unorm
      | Astc_6x6_unorm_srgb
      | Astc_8x5_unorm
      | Astc_8x5_unorm_srgb
      | Astc_8x6_unorm
      | Astc_8x6_unorm_srgb
      | Astc_8x8_unorm
      | Astc_8x8_unorm_srgb
      | Astc_10x5_unorm
      | Astc_10x5_unorm_srgb
      | Astc_10x6_unorm
      | Astc_10x6_unorm_srgb
      | Astc_10x8_unorm
      | Astc_10x8_unorm_srgb
      | Astc_10x10_unorm
      | Astc_10x10_unorm_srgb
      | Astc_12x10_unorm
      | Astc_12x10_unorm_srgb
      | Astc_12x12_unorm
      | Astc_12x12_unorm_srgb

      val to_int : t -> int
      val of_int : int -> t
    end

    === High-level ML ===
    module Texture_format = Wgpu_low.Texture_format
    |}]
;;

(** {2 Bitflag Tests} *)

let%expect_test "bitflag - buffer_usage (real API bitflag)" =
  let bitflag = lookup_bitflag "buffer_usage" in
  print_bitflag_outputs bitflag;
  [%expect
    {|
    === Low-level C ===
    /* Bitflag: WGPUBufferUsage */
    CAMLprim value caml_wgpu_buffer_usage_none(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_None));
    }

    CAMLprim value caml_wgpu_buffer_usage_map_read(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_MapRead));
    }

    CAMLprim value caml_wgpu_buffer_usage_map_write(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_MapWrite));
    }

    CAMLprim value caml_wgpu_buffer_usage_copy_src(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_CopySrc));
    }

    CAMLprim value caml_wgpu_buffer_usage_copy_dst(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_CopyDst));
    }

    CAMLprim value caml_wgpu_buffer_usage_index(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Index));
    }

    CAMLprim value caml_wgpu_buffer_usage_vertex(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Vertex));
    }

    CAMLprim value caml_wgpu_buffer_usage_uniform(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Uniform));
    }

    CAMLprim value caml_wgpu_buffer_usage_storage(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Storage));
    }

    CAMLprim value caml_wgpu_buffer_usage_indirect(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Indirect));
    }

    CAMLprim value caml_wgpu_buffer_usage_query_resolve(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_QueryResolve));
    }

    === High-level MLI ===
    module Buffer_usage : sig
      type t =
      | None
      | Map_read
      | Map_write
      | Copy_src
      | Copy_dst
      | Index
      | Vertex
      | Uniform
      | Storage
      | Indirect
      | Query_resolve

      val to_int : t -> int
      val list_to_int : t list -> int
    end

    === High-level ML ===
    module Buffer_usage = Wgpu_low.Buffer_usage
    |}]
;;

(** {2 Struct Tests} *)

let%expect_test "struct - buffer_descriptor (base_in struct with chained types)" =
  let struct_ = lookup_struct "buffer_descriptor" in
  print_struct_outputs struct_;
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUBufferDescriptor */
    CAMLprim value caml_wgpu_buffer_descriptor_create(value unit) {
      CAMLparam1(unit);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)malloc(sizeof(WGPUBufferDescriptor));
      memset(s, 0, sizeof(WGPUBufferDescriptor));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_free(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      const char *str = String_val(val);
      s->label.data = str;
      s->label.length = strlen(str);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_usage(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->usage = Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_size(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->size = (uint64_t)Int64_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_mapped_at_creation(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->mappedAtCreation = Bool_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_label(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      if (s->label.data != NULL) {
        CAMLreturn(caml_copy_string(s->label.data));
      } else {
        CAMLreturn(caml_copy_string(""));
      }
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_usage(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->usage));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_size(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(caml_copy_int64(s->size));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_mapped_at_creation(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_bool(s->mappedAtCreation));
    }

    /* nextInChain setter for WGPUBufferDescriptor */
    CAMLprim value caml_wgpu_buffer_descriptor_set_next_in_chain(value handle, value chain) {
      CAMLparam2(handle, chain);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    module Buffer_descriptor : sig
      type t = nativeint
      val buffer_descriptor_create : unit -> t
      val buffer_descriptor_free : t -> unit
      val buffer_descriptor_set_label : t -> string -> unit
      val buffer_descriptor_set_usage : t -> int -> unit
      val buffer_descriptor_set_size : t -> int64 -> unit
      val buffer_descriptor_set_mapped_at_creation : t -> bool -> unit
      val buffer_descriptor_get_label : t -> string
      val buffer_descriptor_get_usage : t -> int
      val buffer_descriptor_get_size : t -> int64
      val buffer_descriptor_get_mapped_at_creation : t -> bool
      val buffer_descriptor_set_next_in_chain : t -> nativeint -> unit
    end

    === Low-level ML ===
    module Buffer_descriptor = struct
      type t = nativeint

      external buffer_descriptor_create : unit -> nativeint = "caml_wgpu_buffer_descriptor_create"

      external buffer_descriptor_free : nativeint -> unit = "caml_wgpu_buffer_descriptor_free"

      external buffer_descriptor_set_label : nativeint -> string -> unit = "caml_wgpu_buffer_descriptor_set_label"
      external buffer_descriptor_set_usage : nativeint -> int -> unit = "caml_wgpu_buffer_descriptor_set_usage"
      external buffer_descriptor_set_size : nativeint -> int64 -> unit = "caml_wgpu_buffer_descriptor_set_size"
      external buffer_descriptor_set_mapped_at_creation : nativeint -> bool -> unit = "caml_wgpu_buffer_descriptor_set_mapped_at_creation"

      external buffer_descriptor_get_label : nativeint -> string = "caml_wgpu_buffer_descriptor_get_label"
      external buffer_descriptor_get_usage : nativeint -> int = "caml_wgpu_buffer_descriptor_get_usage"
      external buffer_descriptor_get_size : nativeint -> int64 = "caml_wgpu_buffer_descriptor_get_size"
      external buffer_descriptor_get_mapped_at_creation : nativeint -> bool = "caml_wgpu_buffer_descriptor_get_mapped_at_creation"

      external buffer_descriptor_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_buffer_descriptor_set_next_in_chain"
    end
    |}]
;;

let%expect_test "struct - bind_group_layout_descriptor (struct with array)" =
  let struct_ = lookup_struct "bind_group_layout_descriptor" in
  print_struct_outputs struct_;
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUBindGroupLayoutDescriptor */
    CAMLprim value caml_wgpu_bind_group_layout_descriptor_create(value unit) {
      CAMLparam1(unit);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)malloc(sizeof(WGPUBindGroupLayoutDescriptor));
      memset(s, 0, sizeof(WGPUBindGroupLayoutDescriptor));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_free(value handle) {
      CAMLparam1(handle);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      const char *str = String_val(val);
      s->label.data = str;
      s->label.length = strlen(str);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_entries(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      size_t count = Wosize_val(val);
      WGPUBindGroupLayoutEntry* arr = (count > 0) ? malloc(count * sizeof(WGPUBindGroupLayoutEntry)) : NULL;
      for (size_t i = 0; i < count; i++) {
        arr[i] = *(WGPUBindGroupLayoutEntry*)Nativeint_val(Field(val, i));
      }
      s->entryCount = count;
      s->entries = arr;
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_get_label(value handle) {
      CAMLparam1(handle);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      if (s->label.data != NULL) {
        CAMLreturn(caml_copy_string(s->label.data));
      } else {
        CAMLreturn(caml_copy_string(""));
      }
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_get_entries(value handle) {
      CAMLparam1(handle);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      (void)s; /* TODO: getter for entries */
      CAMLreturn(Val_unit);
    }

    /* nextInChain setter for WGPUBindGroupLayoutDescriptor */
    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_next_in_chain(value handle, value chain) {
      CAMLparam2(handle, chain);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    module Bind_group_layout_descriptor : sig
      type t = nativeint
      val bind_group_layout_descriptor_create : unit -> t
      val bind_group_layout_descriptor_free : t -> unit
      val bind_group_layout_descriptor_set_label : t -> string -> unit
      val bind_group_layout_descriptor_set_entries : t -> nativeint array -> unit
      val bind_group_layout_descriptor_get_label : t -> string
      val bind_group_layout_descriptor_get_entries : t -> nativeint
      val bind_group_layout_descriptor_set_next_in_chain : t -> nativeint -> unit
    end

    === Low-level ML ===
    module Bind_group_layout_descriptor = struct
      type t = nativeint

      external bind_group_layout_descriptor_create : unit -> nativeint = "caml_wgpu_bind_group_layout_descriptor_create"

      external bind_group_layout_descriptor_free : nativeint -> unit = "caml_wgpu_bind_group_layout_descriptor_free"

      external bind_group_layout_descriptor_set_label : nativeint -> string -> unit = "caml_wgpu_bind_group_layout_descriptor_set_label"
      external bind_group_layout_descriptor_set_entries : nativeint -> nativeint array -> unit = "caml_wgpu_bind_group_layout_descriptor_set_entries"

      external bind_group_layout_descriptor_get_label : nativeint -> string = "caml_wgpu_bind_group_layout_descriptor_get_label"
      external bind_group_layout_descriptor_get_entries : nativeint -> nativeint = "caml_wgpu_bind_group_layout_descriptor_get_entries"

      external bind_group_layout_descriptor_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_bind_group_layout_descriptor_set_next_in_chain"
    end
    |}]
;;

let%expect_test "struct - extent_3D (standalone struct)" =
  let struct_ = lookup_struct "extent_3D" in
  print_struct_outputs struct_;
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUExtent3D */
    CAMLprim value caml_wgpu_extent_3d_create(value unit) {
      CAMLparam1(unit);
      WGPUExtent3D *s = (WGPUExtent3D*)malloc(sizeof(WGPUExtent3D));
      memset(s, 0, sizeof(WGPUExtent3D));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_extent_3d_free(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_width(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      s->width = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_height(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      s->height = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_depth_or_array_layers(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      s->depthOrArrayLayers = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_get_width(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->width));
    }

    CAMLprim value caml_wgpu_extent_3d_get_height(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->height));
    }

    CAMLprim value caml_wgpu_extent_3d_get_depth_or_array_layers(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->depthOrArrayLayers));
    }


    === Low-level MLI ===
    module Extent_3d : sig
      type t = nativeint
      val extent_3D_create : unit -> t
      val extent_3D_free : t -> unit
      val extent_3D_set_width : t -> int -> unit
      val extent_3D_set_height : t -> int -> unit
      val extent_3D_set_depth_or_array_layers : t -> int -> unit
      val extent_3D_get_width : t -> int
      val extent_3D_get_height : t -> int
      val extent_3D_get_depth_or_array_layers : t -> int
    end

    === Low-level ML ===
    module Extent_3d = struct
      type t = nativeint

      external extent_3D_create : unit -> nativeint = "caml_wgpu_extent_3d_create"

      external extent_3D_free : nativeint -> unit = "caml_wgpu_extent_3d_free"

      external extent_3D_set_width : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_width"
      external extent_3D_set_height : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_height"
      external extent_3D_set_depth_or_array_layers : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_depth_or_array_layers"

      external extent_3D_get_width : nativeint -> int = "caml_wgpu_extent_3d_get_width"
      external extent_3D_get_height : nativeint -> int = "caml_wgpu_extent_3d_get_height"
      external extent_3D_get_depth_or_array_layers : nativeint -> int = "caml_wgpu_extent_3d_get_depth_or_array_layers"
    end
    |}]
;;

(** {2 Method Tests} *)

let%expect_test "method - buffer.get_size (simple method, no args, returns primitive)" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "get_size" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_get_size(value self) {
      CAMLparam1(self);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);

      uint64_t result = wgpuBufferGetSize(c_self);
      CAMLreturn(caml_copy_int64(result));
    }

    === Low-level MLI ===
    val buffer_get_size : buffer -> int64
    === Low-level ML ===
    external buffer_get_size : buffer -> int64 = "caml_wgpu_buffer_get_size"
    === High-level MLI ===
      val get_size : t -> int64

    === High-level ML ===
      let get_size t = Wgpu_low.buffer_get_size t.handle
    |}]
;;

let%expect_test "method - buffer.set_label (method with string arg)" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "set_label" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_set_label(value self, value label) {
      CAMLparam2(self, label);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      WGPUStringView c_label = { .data = String_val(label), .length = caml_string_length(label) };
      wgpuBufferSetLabel(c_self, c_label);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val buffer_set_label : buffer -> string -> unit
    === Low-level ML ===
    external buffer_set_label : buffer -> string -> unit = "caml_wgpu_buffer_set_label"
    === High-level MLI ===
      val set_label : t -> label:string -> unit

    === High-level ML ===
      let set_label t ~label = Wgpu_low.buffer_set_label t.handle label
    |}]
;;

let%expect_test "method - device.create_buffer (method with struct descriptor arg)" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_buffer(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUBufferDescriptor* c_descriptor = (WGPUBufferDescriptor*)Nativeint_val(descriptor);
      WGPUBuffer result = wgpuDeviceCreateBuffer(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_buffer : device -> nativeint -> buffer
    === Low-level ML ===
    external device_create_buffer : device -> nativeint -> buffer = "caml_wgpu_device_create_buffer"
    === High-level MLI ===
      val create_buffer : t -> ?label:string -> usage:Buffer_usage.Item.t list -> size:int64 -> mapped_at_creation:bool -> unit -> Buffer.t

    === High-level ML ===
      let create_buffer t ?(label = "") ~usage ~size ~mapped_at_creation () =
        let desc_descriptor = Wgpu_low.Buffer_descriptor.buffer_descriptor_create () in
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_label desc_descriptor label;
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_usage desc_descriptor (Buffer_usage.list_to_int usage);
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_size desc_descriptor size;
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_mapped_at_creation desc_descriptor mapped_at_creation;
        let result = Wgpu_low.device_create_buffer t.handle desc_descriptor in
        Wgpu_low.Buffer_descriptor.buffer_descriptor_free desc_descriptor;
        ({ Buffer.handle = result } : Buffer.t)
    |}]
;;

let%expect_test "method - device.create_bind_group_layout (method with complex struct \
                 arg)"
  =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_bind_group_layout" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_bind_group_layout(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUBindGroupLayoutDescriptor* c_descriptor = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(descriptor);
      WGPUBindGroupLayout result = wgpuDeviceCreateBindGroupLayout(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_bind_group_layout : device -> nativeint -> bind_group_layout
    === Low-level ML ===
    external device_create_bind_group_layout : device -> nativeint -> bind_group_layout = "caml_wgpu_device_create_bind_group_layout"
    === High-level MLI ===
      val create_bind_group_layout : t -> ?label:string -> ?entries:Bind_group_layout_entry.t list -> unit -> Bind_group_layout.t

    === High-level ML ===
      let create_bind_group_layout t ?(label = "") ?(entries = []) () =
        let desc_descriptor = Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_create () in
        Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_set_label desc_descriptor label;
        let entries_structs = List.map (fun (entry : Bind_group_layout_entry.t) ->
            let e = Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_create () in
            Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_binding e entry.binding;
            Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_visibility e (Shader_stage.list_to_int entry.visibility);
            (match entry.buffer with
             | Some buffer_rec ->
               let nested_buffer = Wgpu_low.Buffer_binding_layout.buffer_binding_layout_create () in
               Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_type nested_buffer (Buffer_binding_type.to_int buffer_rec.type_);
               Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_has_dynamic_offset nested_buffer buffer_rec.has_dynamic_offset;
               Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_min_binding_size nested_buffer buffer_rec.min_binding_size;
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_buffer e nested_buffer
             | None -> ());
            (match entry.sampler with
             | Some sampler_rec ->
               let nested_sampler = Wgpu_low.Sampler_binding_layout.sampler_binding_layout_create () in
               Wgpu_low.Sampler_binding_layout.sampler_binding_layout_set_type nested_sampler (Sampler_binding_type.to_int sampler_rec.type_);
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_sampler e nested_sampler
             | None -> ());
            (match entry.texture with
             | Some texture_rec ->
               let nested_texture = Wgpu_low.Texture_binding_layout.texture_binding_layout_create () in
               Wgpu_low.Texture_binding_layout.texture_binding_layout_set_sample_type nested_texture (Texture_sample_type.to_int texture_rec.sample_type);
               Wgpu_low.Texture_binding_layout.texture_binding_layout_set_view_dimension nested_texture (Texture_view_dimension.to_int texture_rec.view_dimension);
               Wgpu_low.Texture_binding_layout.texture_binding_layout_set_multisampled nested_texture texture_rec.multisampled;
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_texture e nested_texture
             | None -> ());
            (match entry.storage_texture with
             | Some storage_texture_rec ->
               let nested_storage_texture = Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_create () in
               Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_set_access nested_storage_texture (Storage_texture_access.to_int storage_texture_rec.access);
               Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_set_format nested_storage_texture (Texture_format.to_int storage_texture_rec.format);
               Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_set_view_dimension nested_storage_texture (Texture_view_dimension.to_int storage_texture_rec.view_dimension);
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_storage_texture e nested_storage_texture
             | None -> ());
            e) entries in
        let entries_array = Array.of_list entries_structs in
        Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_set_entries desc_descriptor entries_array;
        let result = Wgpu_low.device_create_bind_group_layout t.handle desc_descriptor in
        List.iter (fun e -> Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_free e) entries_structs;
        Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_free desc_descriptor;
        ({ Bind_group_layout.handle = result } : Bind_group_layout.t)
    |}]
;;

let%expect_test "method - queue.submit (method with array arg)" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "submit" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_queue_submit(value self, value commands) {
      CAMLparam2(self, commands);
      WGPUQueue c_self = (WGPUQueue)Nativeint_val(self);
      size_t c_commands_count = Wosize_val(commands);
      WGPUCommandBuffer* c_commands = (c_commands_count > 0) ? alloca(c_commands_count * sizeof(WGPUCommandBuffer)) : NULL;
      for (size_t i = 0; i < c_commands_count; i++) {
        c_commands[i] = (WGPUCommandBuffer)Nativeint_val(Field(commands, i));
      }
      wgpuQueueSubmit(c_self, c_commands_count, c_commands);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val queue_submit : queue -> command_buffer array -> unit
    === Low-level ML ===
    external queue_submit : queue -> command_buffer array -> unit = "caml_wgpu_queue_submit"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;
