(** Centralized type mapping for wgpu code generation.

    This module provides a single source of truth for type mappings between the IR
    representation and various output contexts (C, low-level OCaml, and high-level OCaml).
    It eliminates duplication and ensures consistency across the code generators. *)

(** Output context affects how types are rendered.

    Each context represents a different target for type string generation:
    - [C_code]: C types for FFI stubs (e.g., uint32_t, WGPUDevice)
    - [Ocaml_low_level]: Raw FFI types in OCaml (e.g., int, nativeint)
    - [Ocaml_high_level_arg]: High-level function arguments (e.g., Device.t)
    - [Ocaml_high_level_return]: High-level return values
    - [Ocaml_high_level_member]: High-level struct member types *)
type context =
  | C_code
  | Ocaml_low_level
  | Ocaml_high_level_arg
  | Ocaml_high_level_return
  | Ocaml_high_level_member

(** [ocaml_module_name name] converts a snake_case type name to an OCaml module name by
    lowercasing everything then capitalizing only the first letter.

    Examples:
    - ["texture_format"] -> ["Texture_format"]
    - ["extent_3D"] -> ["Extent_3d"]
    - ["device"] -> ["Device"] *)
val ocaml_module_name : string -> string

(** [c_type_name name] converts a snake_case type name to a WGPU C type name by converting
    to PascalCase and prepending "WGPU".

    Examples:
    - ["texture_format"] -> ["WGPUTextureFormat"]
    - ["device"] -> ["WGPUDevice"]
    - ["extent_3d"] -> ["WGPUExtent3d"] *)
val c_type_name : string -> string

(** [type_string ~context type_ref] returns the string representation of a type in the
    given context.

    The mapping varies by context:
    - Primitives: C uses C types (uint32_t), OCaml uses OCaml types (int)
    - Enums: C uses WGPU types, low-level uses int, high-level uses Module.t
    - Objects: C uses handles, low-level uses raw types, high-level uses Module.t
    - Arrays: Element types are mapped recursively
    - Optionals: High-level wraps with option, others unwrap *)
val type_string : context:context -> Ir.type_ref -> string

(** [convert_arg_to_low ~var_name type_ref] generates OCaml code to convert a high-level
    argument value to its low-level representation.

    [var_name] is the name of the variable holding the high-level value.

    Examples:
    - For enums: generates [Module.to_int var_name]
    - For objects: generates [var_name.Module.handle]
    - For primitives: returns [var_name] unchanged *)
val convert_arg_to_low : var_name:string -> Ir.type_ref -> string

(** [convert_return_to_high ~expr type_ref] generates OCaml code to convert a low-level
    return value to its high-level representation.

    [expr] is the expression producing the low-level value.

    Examples:
    - For enums: generates [Module.of_int (expr)]
    - For objects: generates [{ Module.handle = expr }]
    - For primitives: returns [expr] unchanged *)
val convert_return_to_high : expr:string -> Ir.type_ref -> string

(** [convert_member_to_low ~var_name type_ref] generates OCaml code to convert a
    high-level struct member value to its low-level representation.

    Similar to [convert_arg_to_low] but handles additional cases specific to struct
    members, such as optional enums, bitflag lists, and pointer-to-arrays.

    [var_name] is the name of the variable holding the high-level value. *)
val convert_member_to_low : var_name:string -> Ir.type_ref -> string
