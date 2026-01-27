(** Low-level code generator for C stubs and OCaml external bindings.

    This module generates:
    - C stubs ({!gen_c_stubs}) that implement the FFI layer between OCaml and wgpu-native
    - OCaml external declarations ({!gen_ml}) that bind to the C stubs
    - OCaml interface ({!gen_mli}) that declares the external bindings

    The generated code provides direct access to the WebGPU C API with minimal
    abstraction. Types are represented as raw values (nativeint for handles, int for
    enums) and require manual memory management. *)

(** Output mode for code generation. *)
type output_mode =
  | Implementation (** Generate .ml implementation *)
  | Interface (** Generate .mli interface *)

(** Generate all C stubs for the WebGPU API.

    Returns C source code that includes:
    - Enum constant accessors
    - Bitflag constant accessors
    - Struct allocation, field setters/getters, and deallocation
    - Object method wrappers
    - Standalone function wrappers
    - Synchronous helper functions *)
val gen_c_stubs : Ir.api -> string

(** Generate all OCaml external bindings (.ml).

    Returns OCaml source code with:
    - Enum modules with to_int/of_int converters
    - Bitflag modules with to_int/list_to_int converters
    - Struct modules with create/free and field accessors
    - Object type aliases and method externals
    - Convenience functions from templates *)
val gen_ml : Ir.api -> string

(** Generate all OCaml interface declarations (.mli).

    Returns OCaml interface code with type signatures for all the declarations in the
    implementation. *)
val gen_mli : Ir.api -> string

(** {2 Individual Generators}

    These functions generate code for specific API elements. They are used internally and
    can be useful for testing. *)

(** Generate C code for enum constant accessors. *)
val gen_c_enum_constants : Ir.enum -> string

(** Generate C code for bitflag constant accessors. *)
val gen_c_bitflag_constants : Ir.bitflag -> string

(** Generate C code for a struct (allocation, setters, getters, deallocation). *)
val gen_c_struct_stubs : Ir.struct_ -> string

(** Generate C code for an object (release function and method stubs). *)
val gen_c_object_stubs : Ir.object_ -> string

(** Generate C code for a standalone function. *)
val gen_c_function_stubs : Ir.function_ -> string

(** Generate OCaml enum module implementation. *)
val gen_ml_enum : Ir.enum -> string

(** Generate OCaml enum module interface. *)
val gen_mli_enum : Ir.enum -> string

(** Generate OCaml bitflag module implementation. *)
val gen_ml_bitflag : Ir.bitflag -> string

(** Generate OCaml bitflag module interface. *)
val gen_mli_bitflag : Ir.bitflag -> string

(** Generate OCaml struct module implementation. *)
val gen_ml_struct : Ir.struct_ -> string

(** Generate OCaml struct module interface. *)
val gen_mli_struct : Ir.struct_ -> string

(** Generate OCaml object type and methods implementation. *)
val gen_ml_object : Ir.object_ -> string

(** Generate OCaml object type and methods interface. *)
val gen_mli_object : Ir.object_ -> string

(** {2 Method Generation}

    Functions for generating method code. *)

(** Generate OCaml external declaration for a method. *)
val gen_ml_method : Ir.object_ -> Ir.method_ -> string

(** Generate MLI declaration for a method. *)
val gen_mli_method : Ir.object_ -> Ir.method_ -> string

(** Generate C stub for a single method. *)
val gen_c_method_stub : Ir.object_ -> Ir.method_ -> string

(** {2 Type Mapping Utilities}

    Functions for converting type references to string representations. *)

(** Map IR type to C type string. *)
val c_type_of_type_ref : Ir.type_ref -> string

(** Get OCaml type string for a type_ref (low-level). *)
val ml_type_of_type_ref : Ir.type_ref -> string

(** {2 Naming Utilities}

    These functions are re-exported from {!Names} and {!Type_mapping} for convenience. *)

(** Get the C type name for a WGPU type (e.g., "texture_format" -> "WGPUTextureFormat"). *)
val c_type_name : string -> string

(** Get the C function name for a method (e.g., "device", "create_buffer" ->
    "wgpuDeviceCreateBuffer"). *)
val c_method_name : string -> string -> string

(** Get the C function name for a standalone function (e.g., "create_instance" ->
    "wgpuCreateInstance"). *)
val c_function_name : string -> string

(** Get the OCaml module name for a type (e.g., "texture_format" -> "Texture_format"). *)
val ocaml_module_name : string -> string

(** Convert snake_case to PascalCase. *)
val to_pascal_case : string -> string

(** Convert snake_case to camelCase. *)
val to_camel_case : string -> string

(** Normalize enum entry name for OCaml variant. *)
val normalize_enum_entry_name : string -> string
