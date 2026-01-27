(** High-level code generator for idiomatic OCaml bindings.

    This module generates:
    - OCaml implementation ({!gen_ml}) with type-safe, ergonomic wrappers
    - OCaml interface ({!gen_mli}) with documented type signatures

    The generated code provides a safe, idiomatic OCaml API on top of the low-level
    bindings. Features include:
    - Type-safe enum variants instead of raw integers
    - Handle types wrapped in records with module namespacing
    - Labeled and optional arguments for struct parameters
    - Automatic struct allocation and deallocation
    - Output struct results returned as records *)

(** Output mode for code generation. *)
type output_mode =
  | Implementation (** Generate .ml implementation *)
  | Interface (** Generate .mli interface *)

(** {2 Parameter Collection Types}

    These types are used when collecting parameters from struct definitions to generate
    function signatures with flattened struct fields. *)

(** A parameter collected from a struct for function signature generation. *)
type struct_parameter =
  { param_name : string (** The OCaml parameter name *)
  ; member : Ir.struct_member (** The struct member definition *)
  ; is_optional : bool (** Whether this parameter is optional *)
  ; nested_var : string option
  (** If from a nested struct, the variable name for that struct *)
  }

(** Result of generating struct creation code. *)
type struct_creation_result =
  { created_structs : (string * Ir.struct_) list
  (** (variable_name, struct_definition) pairs for all created structs *)
  ; code_lines : string list (** OCaml code lines that create the structs *)
  }

(** Result of code generation that includes resources to free. *)
type code_with_cleanup =
  { code_lines : string list (** The generated code *)
  ; structs_to_free : (string * Ir.struct_) list
  (** (variable_name, struct_def) pairs for structs needing freeing *)
  }

(** Result of inline struct conversion. *)
type inline_struct_conversion =
  { create_code : string list (** Code to create the C struct *)
  ; set_code : string list (** Code to set all fields on the struct *)
  ; structs_to_free : (string * Ir.struct_) list
  (** (var_name, struct_def) pairs for later freeing *)
  }

(** {2 Main Generation Functions} *)

(** Generate all high-level OCaml code (.ml).

    Returns OCaml source code with:
    - Enum modules re-exporting low-level enums
    - Bitflag modules re-exporting low-level bitflags
    - Object modules with handle types and method implementations
    - Entry struct record type modules
    - Adapter module with Device nested inside
    - Instance module with create function *)
val gen_ml : Ir.api -> string

(** Generate all high-level OCaml interface (.mli).

    Returns OCaml interface code with documented type signatures for all the declarations
    in the implementation. *)
val gen_mli : Ir.api -> string

(** Generate enums module implementation (.ml). *)
val gen_enums_ml : Ir.api -> string

(** Generate enums module interface (.mli). *)
val gen_enums_mli : Ir.api -> string

(** Generate bitsets module implementation (.ml). *)
val gen_bitsets_ml : Ir.api -> string

(** Generate bitsets module interface (.mli). *)
val gen_bitsets_mli : Ir.api -> string

(** {2 Validation} *)

(** Validate that all non-auto-generated methods are accounted for.

    Returns a list of error messages for methods that:
    - Cannot be auto-generated (complex args/returns)
    - Are not listed in Config.method_config as Manual or Skipped *)
val validate_method_coverage : Ir.api -> string list

(** Check method coverage and fail if there are unaccounted methods.

    Calls {!validate_method_coverage} and raises [Failure] with detailed error messages if
    any methods are unaccounted for. *)
val check_method_coverage : Ir.api -> unit

(** {2 Method Classification Predicates}

    These predicates determine how methods should be handled in the high-level API. *)

(** Check if a method can be included in the high-level API with simple args only.

    Returns [true] if the method:
    - Is not async (no callback)
    - Has only directly convertible argument types
    - Has a simple return type (primitive, enum, bitflag, or object) *)
val method_is_high_level_simple : Ir.method_ -> bool

(** Check if a method can be auto-generated for the high-level API.

    Returns [true] if the method:
    - Is not async
    - Has a simple return type
    - Has either: all simple args, auto-generable struct args, or an output struct arg *)
val method_is_high_level : Ir.struct_ list -> Ir.method_ -> bool

(** Check if a struct has only flat members and is an input struct.

    A struct is auto-generable if:
    - It is an input struct (Base_in, Standalone, or Extension_in)
    - All members are flat (primitives, enums, bitflags, objects, or nested flat structs) *)
val is_auto_generable_struct : Ir.struct_ list -> string -> bool

(** {2 Individual Generators}

    These functions generate code for specific API elements. *)

(** Generate enum module (implementation or interface based on mode). *)
val gen_enum : output_mode -> Ir.enum -> string

(** Generate ML implementation for an enum type. *)
val gen_ml_enum : Ir.enum -> string

(** Generate MLI interface for an enum type. *)
val gen_mli_enum : Ir.enum -> string

(** Generate bitflag module (implementation or interface based on mode). *)
val gen_bitflag : output_mode -> Ir.bitflag -> string

(** Generate ML implementation for a bitflag type. *)
val gen_ml_bitflag : Ir.bitflag -> string

(** Generate MLI interface for a bitflag type. *)
val gen_mli_bitflag : Ir.bitflag -> string

(** Generate object module (implementation or interface based on mode). *)
val gen_object : output_mode -> Ir.struct_ list -> Ir.object_ -> string

(** Generate ML implementation for an object type. *)
val gen_ml_object : Ir.struct_ list -> Ir.object_ -> string

(** Generate MLI interface for an object type. *)
val gen_mli_object : Ir.struct_ list -> Ir.object_ -> string

(** Generate a method (implementation or interface based on mode).

    Returns [None] if the method is manually implemented or cannot be auto-generated. *)
val gen_method
  :  output_mode
  -> Ir.struct_ list
  -> Ir.object_
  -> Ir.method_
  -> string option

(** Generate ML implementation for a method. *)
val gen_ml_method : Ir.struct_ list -> Ir.object_ -> Ir.method_ -> string option

(** Generate MLI interface for a method. *)
val gen_mli_method : Ir.struct_ list -> Ir.object_ -> Ir.method_ -> string option

(** {2 Entry Struct Generators}

    Entry structs are structs that appear as elements in array parameters. They are
    represented as OCaml record types in the high-level API. *)

(** Generate a record type module for an entry struct.

    Creates an OCaml module containing a record type [t] with fields corresponding to the
    struct members. Also generates nested modules for any inline structs within the entry
    struct. *)
val gen_array_element_struct_module
  :  output_mode
  -> Ir.struct_ list
  -> Ir.struct_
  -> string

(** Collect all entry structs from the API.

    Returns a list of (entry_struct, nested_structs) pairs for all structs that appear in
    array members of other structs. *)
val collect_array_element_structs : Ir.api -> (Ir.struct_ * Ir.struct_ list) list

(** {2 Special Object Generators}

    Special objects (instance, adapter, device, queue) have some methods that are manually
    implemented. These functions generate only the auto-generated parts. *)

(** Generate auto-generated ML methods for a special object.

    Returns (output_struct_types, methods) as strings, containing only the methods that
    are not manually implemented or skipped. *)
val gen_special_object_auto_methods : Ir.struct_ list -> Ir.object_ -> string * string

(** Generate auto-generated MLI signatures for a special object.

    Returns (output_struct_types, methods) as strings. *)
val gen_special_object_auto_methods_mli : Ir.struct_ list -> Ir.object_ -> string * string

(** {2 Topological Sorting} *)

(** Topologically sort objects so dependencies come first.

    An object A depends on object B if:
    - A method of A returns B
    - A method of A takes B as a parameter
    - A method of A has an output struct with a field of type B

    Uses Kahn's algorithm for topological sorting. *)
val sort_objects : Ir.struct_ list -> Ir.object_ list -> Ir.object_ list

(** {2 Helper Predicates (for testing)}

    These functions are used internally and exposed for unit testing. *)

(** Check if a type is flat (primitive, enum, bitflag, or object - no nested structs). *)
val is_flat_member_type : Ir.type_ref -> bool

(** Check if an argument type can be directly converted (without struct handling). *)
val is_directly_convertible_arg : Ir.type_ref -> bool

(** Check if a method is async (has callback). Re-exported from {!Predicates}. *)
val method_is_async : Ir.method_ -> bool

(** Check if a member type contains a nested struct. Returns struct name if so. *)
val get_inline_struct_name : Ir.type_ref -> string option

(** Check if a member type is an array of structs. Returns struct name if so. *)
val member_is_array_of_structs : Ir.type_ref -> string option

(** Escape OCaml keywords by adding underscore suffix. Re-exported from {!Names}. *)
val escape_keyword : string -> string

(** Filter out unhelpful doc strings. Re-exported from {!Names}. *)
val useful_doc : string -> string option

(** {2 Backward Compatibility Wrappers}

    These functions are kept for backward compatibility with existing code. *)

(** Generate ML implementation for method with output struct argument. *)
val gen_ml_method_with_output_struct
  :  Ir.object_
  -> Ir.method_
  -> Ir.struct_
  -> Ir.arg
  -> string

(** Generate MLI signature for method with output struct argument. *)
val gen_mli_method_with_output_struct : Ir.object_ -> Ir.method_ -> Ir.struct_ -> string
