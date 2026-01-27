open! Core

(** Integration tests for enum code generation *)

(* Sample enums for testing *)
let simple_enum : Ir.enum =
  { name = "texture_format"
  ; doc = "Texture pixel formats"
  ; entries =
      [ { name = "rgba8_unorm"; doc = "RGBA 8-bit unsigned normalized"; value = None }
      ; { name = "bgra8_unorm"; doc = "BGRA 8-bit unsigned normalized"; value = None }
      ]
  }
;;

let single_entry_enum : Ir.enum =
  { name = "load_op"
  ; doc = "Load operation"
  ; entries = [ { name = "clear"; doc = "Clear to a value"; value = None } ]
  }
;;

let enum_with_explicit_values : Ir.enum =
  { name = "power_preference"
  ; doc = "Power preference for adapter selection"
  ; entries =
      [ { name = "undefined"; doc = "No preference"; value = Some 0 }
      ; { name = "low_power"; doc = "Prefer low power"; value = Some 1 }
      ; { name = "high_performance"; doc = "Prefer high performance"; value = Some 2 }
      ]
  }
;;

let enum_with_numeric_prefix : Ir.enum =
  { name = "texture_dimension"
  ; doc = "Texture dimensions"
  ; entries =
      [ { name = "1d"; doc = "One-dimensional"; value = None }
      ; { name = "2d"; doc = "Two-dimensional"; value = None }
      ; { name = "3d"; doc = "Three-dimensional"; value = None }
      ]
  }
;;

(* ===== Gen_low enum tests ===== *)

let%expect_test "Gen_low.For_testing.gen_ml_enum - simple enum" =
  print_endline (Gen_low.For_testing.gen_ml_enum simple_enum);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.For_testing.gen_mli_enum - simple enum" =
  print_endline (Gen_low.For_testing.gen_mli_enum simple_enum);
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

let%expect_test "Gen_low.For_testing.gen_c_enum_constants - simple enum" =
  print_endline (Gen_low.For_testing.gen_c_enum_constants simple_enum);
  [%expect
    {|
    /* Enum: WGPUTextureFormat */
    CAMLprim value caml_wgpu_texture_format_rgba8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Rgba8Unorm));
    }

    CAMLprim value caml_wgpu_texture_format_bgra8_unorm(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUTextureFormat_Bgra8Unorm));
    }
    |}]
;;

let%expect_test "Gen_low.For_testing.gen_ml_enum - single entry" =
  print_endline (Gen_low.For_testing.gen_ml_enum single_entry_enum);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.For_testing.gen_ml_enum - numeric prefix entries" =
  print_endline (Gen_low.For_testing.gen_ml_enum enum_with_numeric_prefix);
  [%expect
    {|
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
    |}]
;;

(* ===== Gen_high enum tests ===== *)

let%expect_test "Gen_high.For_testing.gen_ml_enum - simple enum" =
  print_endline (Gen_high.For_testing.gen_ml_enum simple_enum);
  [%expect {| module Texture_format = Wgpu_low.Texture_format |}]
;;

let%expect_test "Gen_high.For_testing.gen_mli_enum - simple enum" =
  print_endline (Gen_high.For_testing.gen_mli_enum simple_enum);
  [%expect
    {|
    module Texture_format : sig
        (** Texture pixel formats *)
    type t =
      | Rgba8_unorm
      | Bgra8_unorm

      val to_int : t -> int
      val of_int : int -> t
    end
    |}]
;;

let%expect_test "Gen_high.For_testing.gen_mli_enum - enum with empty doc" =
  let enum_no_doc = { simple_enum with doc = "" } in
  print_endline (Gen_high.For_testing.gen_mli_enum enum_no_doc);
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

let%expect_test "Gen_high.For_testing.gen_mli_enum - enum with TODO doc" =
  let enum_todo_doc = { simple_enum with doc = "TODO" } in
  print_endline (Gen_high.For_testing.gen_mli_enum enum_todo_doc);
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

let%expect_test "Gen_high.For_testing.gen_mli_enum - enum with numeric prefix entries" =
  print_endline (Gen_high.For_testing.gen_mli_enum enum_with_numeric_prefix);
  [%expect
    {|
    module Texture_dimension : sig
        (** Texture dimensions *)
    type t =
      | N1d
      | N2d
      | N3d

      val to_int : t -> int
      val of_int : int -> t
    end
    |}]
;;
