(** Name transformation utilities for code generation.

    This module provides functions for converting between different naming conventions
    used in the WebGPU API (snake_case) and OCaml/C code (PascalCase, camelCase). It also
    handles OCaml keyword escaping and other name-related utilities. *)

(** Convert snake_case to PascalCase, preserving double underscores as single underscores
    in the output.

    Double underscores in C names have special meaning, so they are preserved.

    Examples:
    - ["texture_format"] -> ["TextureFormat"]
    - ["some__name"] -> ["Some_Name"] (double underscore preserved)
    - ["1d"] -> ["1d"] (numeric prefix unchanged) *)
val to_pascal_case : string -> string

(** Convert snake_case to camelCase.

    The first word remains lowercase, subsequent words are capitalized.

    Examples:
    - ["bind_group_layout"] -> ["bindGroupLayout"]
    - ["entry_count"] -> ["entryCount"]
    - ["x"] -> ["x"] *)
val to_camel_case : string -> string

(** Normalize an enum entry name for use as an OCaml variant.

    Converts to lowercase then capitalizes the first letter. Prefixes numeric names with
    "N" since OCaml identifiers cannot start with digits.

    Examples:
    - ["discrete_GPU"] -> ["Discrete_gpu"]
    - ["1d"] -> ["N1d"]
    - ["RGBA8_UNORM"] -> ["Rgba8_unorm"] *)
val normalize_enum_entry_name : string -> string

(** List of OCaml reserved keywords that need escaping. *)
val ocaml_keywords : string list

(** Escape OCaml keywords by adding an underscore suffix.

    If the name is a reserved keyword, appends an underscore. Otherwise returns the name
    unchanged.

    Examples:
    - ["type"] -> ["type_"]
    - ["module"] -> ["module_"]
    - ["foo"] -> ["foo"] *)
val escape_keyword : string -> string

(** Indent all lines of a string by one level (2 spaces).

    Useful for generating properly indented code. *)
val indent_lines : string -> string

(** Read a template file from the codegen/templates directory.

    [read_template path] reads the file at [../codegen/templates/path] relative to the
    current working directory.

    Raises if the file does not exist. *)
val read_template : string -> string

(** Filter out unhelpful documentation strings.

    Returns [None] if the doc string is empty, equals "TODO", or starts with "TODO\n".
    Otherwise returns [Some doc] with whitespace stripped. *)
val useful_doc : string -> string option
