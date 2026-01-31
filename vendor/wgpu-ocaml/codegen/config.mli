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

(** Configuration record that can be threaded through codegen functions. *)
type t

(** Default config for production code generation - respects manual/skipped flags. *)
val default : t

(** Config for testing - generates code for all methods including manual ones. *)
val for_testing : t

(** Config for low-level bindings - only skips methods that are truly problematic at the C
    level. Most "manual" methods in the high-level API still need low-level bindings. *)
val for_low_level : t

(** Check if a method is manually implemented according to the config. Returns [false] if
    [config.ignore_manual_for_generation] is [true]. *)
val is_manual_with_config : t -> object_name:string -> method_name:string -> bool

(** Check if a method is skipped according to the config. Returns [false] if
    [config.ignore_manual_for_generation] is [true]. *)
val is_skipped_with_config : t -> object_name:string -> method_name:string -> bool

(** Check if a method is accounted for (either manual or skipped) according to the config.
    Returns [false] if [config.ignore_manual_for_generation] is [true]. *)
val is_accounted_for_with_config : t -> object_name:string -> method_name:string -> bool
