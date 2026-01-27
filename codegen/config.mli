(** Configuration for method handling in the high-level bindings generator.

    This module defines which methods in the WebGPU API need special handling and tracks
    whether each method is auto-generated, manually implemented, or intentionally skipped.
    This provides a single source of truth for method coverage and helps ensure no methods
    are accidentally omitted. *)

(** Method key: (object_name, method_name) pair for identifying methods. *)
module Method_key : sig
  type t = string * string [@@deriving sexp, compare, equal]

  include Core.Comparator.S with type t := t
end

(** Method handling categories.

    Each method in the API falls into one of these categories:
    - [Manual]: Implemented by hand in template code
    - [Skipped]: Intentionally not exposed in the high-level API
    - [Auto]: Auto-generated from the API specification *)
type method_handling =
  | Manual of { reason : string } (** Method is implemented by hand in template code *)
  | Skipped of { reason : string } (** Method is intentionally not exposed *)
  | Auto (** Method is auto-generated *)
[@@deriving sexp_of]

(** Get the handling configuration for a specific method.

    Returns [Auto] if the method is not explicitly configured. *)
val get_handling : object_name:string -> method_name:string -> method_handling

(** List of all manually implemented methods as (object_name, method_name) pairs. *)
val manual_methods : Method_key.t list

(** List of all intentionally skipped methods as (object_name, method_name) pairs. *)
val skipped_methods : Method_key.t list

(** Check if a method is accounted for in the configuration.

    Returns [true] if the method is either manually implemented or skipped. Returns
    [false] if the method should be auto-generated. *)
val is_accounted_for : object_name:string -> method_name:string -> bool

(** Check if a method is manually implemented. *)
val is_manual : object_name:string -> method_name:string -> bool

(** Check if a method is intentionally skipped. *)
val is_skipped : object_name:string -> method_name:string -> bool

(** Validate that all configured methods exist in the API.

    Prints warnings for any methods in the configuration that do not exist in the provided
    API specification. Call this during code generation to catch stale configuration
    entries. *)
val validate_config : Ir.api -> unit
