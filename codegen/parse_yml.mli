(** YAML parser for the WebGPU API specification.

    This module parses the webgpu.yml file into the intermediate representation defined in
    the {!Ir} module. The YAML file is the authoritative source of the WebGPU API
    specification used for code generation. *)

(** Load and parse a webgpu.yml file.

    [load_file path] reads the YAML file at [path] and converts it to the IR
    representation.

    Raises if the file cannot be read or contains invalid YAML/structure. *)
val load_file : string -> Ir.api
