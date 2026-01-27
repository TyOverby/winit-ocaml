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

(** {2 Functions Exposed for Testing}

    These functions are implementation details exposed only for unit testing. *)
module For_testing : sig
  (** Output mode for code generation. *)
  type output_mode =
    | Implementation (** Generate .ml implementation *)
    | Interface (** Generate .mli interface *)

  (** Generate ML implementation for an enum type. *)
  val gen_ml_enum : Ir.enum -> string

  (** Generate MLI interface for an enum type. *)
  val gen_mli_enum : Ir.enum -> string

  (** Generate ML implementation for a bitflag type. *)
  val gen_ml_bitflag : Ir.bitflag -> string

  (** Generate MLI interface for a bitflag type. *)
  val gen_mli_bitflag : Ir.bitflag -> string

  (** Generate ML implementation for a method.

      Returns [None] if the method is manually implemented or cannot be auto-generated. *)
  val gen_ml_method : Ir.struct_ list -> Ir.object_ -> Ir.method_ -> string option

  (** Generate MLI interface for a method.

      Returns [None] if the method is manually implemented or cannot be auto-generated. *)
  val gen_mli_method : Ir.struct_ list -> Ir.object_ -> Ir.method_ -> string option

  (** Generate ML implementation for method with output struct argument. *)
  val gen_ml_method_with_output_struct
    :  Ir.object_
    -> Ir.method_
    -> Ir.struct_
    -> Ir.arg
    -> string

  (** Generate MLI signature for method with output struct argument. *)
  val gen_mli_method_with_output_struct : Ir.object_ -> Ir.method_ -> Ir.struct_ -> string

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
end
