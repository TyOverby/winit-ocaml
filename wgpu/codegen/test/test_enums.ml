open! Core

(** Integration tests for enum code generation using inline YAML *)

let%expect_test "enum - texture_format (simple enum with two entries)" =
  let yaml =
    {|
name: texture_format
doc: Texture pixel formats
entries:
  - name: rgba8_unorm
    doc: RGBA 8-bit unsigned normalized
  - name: bgra8_unorm
    doc: BGRA 8-bit unsigned normalized
|}
  in
  let enum = Parse_yml.parse_enum (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_enum_constants enum);
  [%expect
    {|
    === Low-level C ===
    /* Enum: WGPUTextureFormat */
    CAMLprim value caml_wgpu_texture_format_rgba8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Rgba8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_bgra8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Bgra8Unorm));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_enum enum);
  [%expect
    {|
    === Low-level MLI ===
    module Texture_format : sig
      type t =
      | Rgba8_unorm
      | Bgra8_unorm

      val to_int : t -> int
      val of_int : int -> t
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_enum enum);
  [%expect
    {|
    === Low-level ML ===
    module Texture_format = struct
      type t =
      | Rgba8_unorm
      | Bgra8_unorm

    external texture_format_rgba8_unorm : unit -> int = "caml_wgpu_texture_format_rgba8_unorm"
    external texture_format_bgra8_unorm : unit -> int = "caml_wgpu_texture_format_bgra8_unorm"

      let rgba8_unorm_int = texture_format_rgba8_unorm ()
      let bgra8_unorm_int = texture_format_bgra8_unorm ()

      let to_int = function
        | Rgba8_unorm -> rgba8_unorm_int
        | Bgra8_unorm -> bgra8_unorm_int

      let of_int = function
        | x when x = rgba8_unorm_int -> Rgba8_unorm
        | x when x = bgra8_unorm_int -> Bgra8_unorm
        | n -> failwith (Printf.sprintf "Texture_format.of_int: unknown value %d" n)
    end
    |}];
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  [%expect
    {|
    === High-level MLI ===
    module Texture_format : sig
        (** Texture pixel formats *)
    type t =
      | Rgba8_unorm
      | Bgra8_unorm

      val to_int : t -> int
      val of_int : int -> t
    end
    |}];
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_enum enum);
  [%expect
    {|
    === High-level ML ===
    module Texture_format = Wgpu_low.Texture_format
    |}]
;;

let%expect_test "enum - load_op (single entry)" =
  let yaml =
    {|
name: load_op
doc: Load operation
entries:
  - name: clear
    doc: Clear to a value
|}
  in
  let enum = Parse_yml.parse_enum (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_enum_constants enum);
  [%expect
    {|
    === Low-level C ===
    /* Enum: WGPULoadOp */
    CAMLprim value caml_wgpu_load_op_clear(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPULoadOp_Clear));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_enum enum);
  [%expect
    {|
    === Low-level MLI ===
    module Load_op : sig
      type t =
      | Clear

      val to_int : t -> int
      val of_int : int -> t
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_enum enum);
  [%expect
    {|
    === Low-level ML ===
    module Load_op = struct
      type t =
      | Clear

    external load_op_clear : unit -> int = "caml_wgpu_load_op_clear"

      let clear_int = load_op_clear ()

      let to_int = function
        | Clear -> clear_int

      let of_int = function
        | x when x = clear_int -> Clear
        | n -> failwith (Printf.sprintf "Load_op.of_int: unknown value %d" n)
    end
    |}];
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  [%expect
    {|
    === High-level MLI ===
    module Load_op : sig
        (** Load operation *)
    type t =
      | Clear

      val to_int : t -> int
      val of_int : int -> t
    end
    |}];
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_enum enum);
  [%expect {|
    === High-level ML ===
    module Load_op = Wgpu_low.Load_op
    |}]
;;

let%expect_test "enum - texture_dimension (numeric prefix entries)" =
  let yaml =
    {|
name: texture_dimension
doc: Texture dimensions
entries:
  - name: 1d
    doc: One-dimensional
  - name: 2d
    doc: Two-dimensional
  - name: 3d
    doc: Three-dimensional
|}
  in
  let enum = Parse_yml.parse_enum (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_enum_constants enum);
  [%expect
    {|
    === Low-level C ===
    /* Enum: WGPUTextureDimension */
    CAMLprim value caml_wgpu_texture_dimension_1d(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureDimension_1d));
    }

    CAMLprim value caml_wgpu_texture_dimension_2d(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureDimension_2d));
    }

    CAMLprim value caml_wgpu_texture_dimension_3d(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureDimension_3d));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_enum enum);
  [%expect
    {|
    === Low-level MLI ===
    module Texture_dimension : sig
      type t =
      | N1d
      | N2d
      | N3d

      val to_int : t -> int
      val of_int : int -> t
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_enum enum);
  [%expect
    {|
    === Low-level ML ===
    module Texture_dimension = struct
      type t =
      | N1d
      | N2d
      | N3d

    external texture_dimension_1d : unit -> int = "caml_wgpu_texture_dimension_1d"
    external texture_dimension_2d : unit -> int = "caml_wgpu_texture_dimension_2d"
    external texture_dimension_3d : unit -> int = "caml_wgpu_texture_dimension_3d"

      let n1d_int = texture_dimension_1d ()
      let n2d_int = texture_dimension_2d ()
      let n3d_int = texture_dimension_3d ()

      let to_int = function
        | N1d -> n1d_int
        | N2d -> n2d_int
        | N3d -> n3d_int

      let of_int = function
        | x when x = n1d_int -> N1d
        | x when x = n2d_int -> N2d
        | x when x = n3d_int -> N3d
        | n -> failwith (Printf.sprintf "Texture_dimension.of_int: unknown value %d" n)
    end
    |}];
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  [%expect
    {|
    === High-level MLI ===
    module Texture_dimension : sig
        (** Texture dimensions *)
    type t =
      | N1d
      | N2d
      | N3d

      val to_int : t -> int
      val of_int : int -> t
    end
    |}];
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_enum enum);
  [%expect
    {|
    === High-level ML ===
    module Texture_dimension = Wgpu_low.Texture_dimension
    |}]
;;

let%expect_test "enum - high-level MLI with empty doc" =
  let yaml =
    {|
name: texture_format
doc: ""
entries:
  - name: rgba8_unorm
    doc: RGBA 8-bit unsigned normalized
  - name: bgra8_unorm
    doc: BGRA 8-bit unsigned normalized
|}
  in
  let enum = Parse_yml.parse_enum (Yaml.of_string_exn yaml) in
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  [%expect
    {|
    module Texture_format : sig
      type t =
      | Rgba8_unorm
      | Bgra8_unorm

      val to_int : t -> int
      val of_int : int -> t
    end
    |}]
;;

let%expect_test "enum - high-level MLI with TODO doc" =
  let yaml =
    {|
name: texture_format
doc: TODO
entries:
  - name: rgba8_unorm
    doc: RGBA 8-bit unsigned normalized
  - name: bgra8_unorm
    doc: BGRA 8-bit unsigned normalized
|}
  in
  let enum = Parse_yml.parse_enum (Yaml.of_string_exn yaml) in
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  [%expect
    {|
    module Texture_format : sig
      type t =
      | Rgba8_unorm
      | Bgra8_unorm

      val to_int : t -> int
      val of_int : int -> t
    end
    |}]
;;
