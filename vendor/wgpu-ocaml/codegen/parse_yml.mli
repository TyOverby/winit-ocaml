(** YAML parser for the WebGPU API specification.

    This module parses the webgpu.yml file into the intermediate representation defined in
    the {!Ir} module. The YAML file is the authoritative source of the WebGPU API
    specification used for code generation. *)

(** Load and parse a webgpu.yml file.

    [load_file path] reads the YAML file at [path] and converts it to the IR
    representation.

    Raises if the file cannot be read or contains invalid YAML/structure. *)
val load_file : string -> Ir.api

(** {2 Individual Parsers (for testing)} *)

(** Parse an enum from a YAML value. *)
val parse_enum : Yaml.value -> Ir.enum

(** Parse a struct from a YAML value. *)
val parse_struct : Yaml.value -> Ir.struct_

(** Parse an object from a YAML value. *)
val parse_object : Yaml.value -> Ir.object_

(** Parse a method from a YAML value. *)
val parse_method : Yaml.value -> Ir.method_

(** Parse a bitflag from a YAML value. *)
val parse_bitflag : Yaml.value -> Ir.bitflag
