open! Core

(** Centralized type mapping for code generation *)

(** Output context affects how types are rendered *)
type context =
  | C_code (** C types for FFI *)
  | Ocaml_low_level (** Low-level OCaml bindings - raw FFI types *)
  | Ocaml_high_level_arg (** High-level function arguments *)
  | Ocaml_high_level_return (** High-level return values *)
  | Ocaml_high_level_member (** High-level struct members *)

(** Get the OCaml module name for a type. Lowercases everything then capitalizes only the
    first letter. e.g., "texture_format" -> "Texture_format", "extent_3D" -> "Extent_3d" *)
let ocaml_module_name (name : string) : string =
  String.lowercase name |> String.capitalize
;;

(** Get the C type name for a WGPU type (e.g., "texture_format" -> "WGPUTextureFormat") *)
let c_type_name (name : string) : string =
  (* Convert snake_case to PascalCase *)
  let pascal =
    String.split name ~on:'_' |> List.map ~f:String.capitalize |> String.concat ~sep:""
  in
  "WGPU" ^ pascal
;;

(** Get the string representation of a type in a given context *)
let rec type_string ~context (type_ref : Ir.type_ref) : string =
  match context, type_ref with
  (* Primitives - Bool *)
  | C_code, Primitive Bool -> "bool"
  | _, Primitive Bool -> "bool"
  (* Primitives - Integers *)
  | C_code, Primitive Uint32 -> "uint32_t"
  | C_code, Primitive Uint64 -> "uint64_t"
  | C_code, Primitive Int32 -> "int32_t"
  | C_code, Primitive Int64 -> "int64_t"
  | C_code, Primitive Usize -> "size_t"
  | _, Primitive (Uint32 | Int32) -> "int"
  | _, Primitive (Uint64 | Int64 | Usize) -> "int64"
  (* Primitives - Floats *)
  | C_code, Primitive Float32 -> "float"
  | C_code, Primitive Float64 -> "double"
  | _, Primitive (Float32 | Float64) -> "float"
  (* Primitives - Strings *)
  | C_code, Primitive (String | Out_string | String_with_default_empty) ->
    "WGPUStringView"
  | _, Primitive (String | Out_string | String_with_default_empty) -> "string"
  (* Primitives - Void pointer *)
  | C_code, Primitive C_void -> "void*"
  | _, Primitive C_void -> "nativeint"
  (* Enums: low-level uses int, high-level uses module type *)
  | C_code, Enum name -> c_type_name name
  | Ocaml_low_level, Enum _ -> "int"
  | _, Enum name -> ocaml_module_name name ^ ".t"
  (* Bitflags: returns need special handling *)
  | C_code, Bitflag name -> c_type_name name
  | Ocaml_low_level, Bitflag _ -> "int"
  | Ocaml_high_level_return, Bitflag _ -> "int" (* Could be combination *)
  | (Ocaml_high_level_arg | Ocaml_high_level_member), Bitflag name ->
    ocaml_module_name name ^ ".t list"
  (* Objects: low-level uses raw type, high-level uses module type *)
  | C_code, Object name -> c_type_name name
  | Ocaml_low_level, Object name -> name (* type alias to nativeint *)
  | _, Object name -> ocaml_module_name name ^ ".t"
  (* Structs *)
  | C_code, Struct name -> c_type_name name
  | (Ocaml_low_level | Ocaml_high_level_arg | Ocaml_high_level_return), Struct _ ->
    "nativeint"
  | Ocaml_high_level_member, Struct name -> ocaml_module_name name ^ ".t"
  (* Callbacks *)
  | C_code, Callback name -> c_type_name name
  | _, Callback _ -> "nativeint"
  (* Arrays - need context-specific handling *)
  | C_code, Array { elem; _ } -> type_string ~context:C_code elem ^ "*"
  | Ocaml_low_level, Array { elem; _ } ->
    (* Arrays of objects become object arrays, others become nativeint or specific arrays *)
    (match elem with
     | Object name -> name ^ " array"
     | Enum _ | Bitflag _ -> "int array"
     | Primitive (Uint32 | Int32) -> "int array"
     | _ -> "nativeint array")
  | (Ocaml_high_level_arg | Ocaml_high_level_return), Array { elem; _ } ->
    type_string ~context elem ^ " list"
  | Ocaml_high_level_member, Array { elem = Object name; _ } ->
    ocaml_module_name name ^ ".t list"
  | Ocaml_high_level_member, Array { elem = Struct name; _ } ->
    ocaml_module_name name ^ ".t list"
  | Ocaml_high_level_member, Array { elem = Enum name; _ } ->
    ocaml_module_name name ^ ".t list"
  | Ocaml_high_level_member, Array { elem = Bitflag name; _ } ->
    ocaml_module_name name ^ ".t list list"
  | Ocaml_high_level_member, Array { elem; _ } -> type_string ~context elem ^ " list"
  (* Optional - wrap inner type *)
  | C_code, Optional inner -> type_string ~context:C_code inner
  | Ocaml_low_level, Optional inner -> type_string ~context:Ocaml_low_level inner
  | (Ocaml_high_level_arg | Ocaml_high_level_return), Optional inner ->
    type_string ~context inner ^ " option"
  | Ocaml_high_level_member, Optional (Enum name) -> ocaml_module_name name ^ ".t option"
  | Ocaml_high_level_member, Optional (Object name) ->
    ocaml_module_name name ^ ".t option"
  | Ocaml_high_level_member, Optional inner ->
    type_string ~context:Ocaml_high_level_arg inner ^ " option"
  (* Pointers *)
  | C_code, Pointer { inner; _ } -> type_string ~context:C_code inner ^ "*"
  | Ocaml_low_level, Pointer _ -> "nativeint"
  | (Ocaml_high_level_arg | Ocaml_high_level_return), Pointer _ -> "nativeint"
  | Ocaml_high_level_member, Pointer { inner = Array { elem = Struct name; _ }; _ } ->
    (* Array of structs passed by pointer *)
    ocaml_module_name name ^ ".t list"
  | Ocaml_high_level_member, Pointer { inner = Array { elem; _ }; _ } ->
    (* Other array types passed by pointer *)
    type_string ~context:Ocaml_high_level_member (Array { elem; pointer = None })
  | Ocaml_high_level_member, Pointer _ -> "nativeint"
;;
