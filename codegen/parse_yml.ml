open! Core

(** Parse webgpu.yml into the IR *)

let get_string_exn (yaml : Yaml.value) key =
  match yaml with
  | `O assoc ->
    (match List.Assoc.find assoc key ~equal:String.equal with
     | Some (`String s) -> s
     | Some _ -> failwithf "expected string for key %s" key ()
     | None -> failwithf "missing key %s" key ())
  | _ -> failwith "expected object"
;;

let get_string_opt (yaml : Yaml.value) key =
  match yaml with
  | `O assoc ->
    (match List.Assoc.find assoc key ~equal:String.equal with
     | Some (`String s) -> Some s
     | Some `Null -> None
     | Some (`Bool b) ->
       (* YAML parses y/n/yes/no/on/off/true/false as bools.
          For names, y and n are common single-letter field names (coordinates).
          Map back to single letters when appropriate. *)
       Some (if b then "y" else "n")
     | Some (`Float f) -> Some (Float.to_string f)
     | Some _ -> None
     | None -> None)
  | _ -> None
;;

let get_string_or_default (yaml : Yaml.value) key ~default =
  Option.value (get_string_opt yaml key) ~default
;;

let get_bool_opt (yaml : Yaml.value) key =
  match yaml with
  | `O assoc ->
    (match List.Assoc.find assoc key ~equal:String.equal with
     | Some (`Bool b) -> Some b
     | Some _ -> failwithf "expected bool for key %s" key ()
     | None -> None)
  | _ -> None
;;

let get_list_exn (yaml : Yaml.value) key =
  match yaml with
  | `O assoc ->
    (match List.Assoc.find assoc key ~equal:String.equal with
     | Some (`A list) -> list
     | Some _ -> failwithf "expected list for key %s" key ()
     | None -> [])
  | _ -> failwith "expected object"
;;

let get_obj_opt (yaml : Yaml.value) key =
  match yaml with
  | `O assoc -> List.Assoc.find assoc key ~equal:String.equal
  | _ -> None
;;

(** Parse a type reference string like "uint32", "enum.backend_type", "array<struct.foo>" *)
let rec parse_type_ref (s : string) : Ir.type_ref =
  match s with
  | "bool" -> Primitive Bool
  | "uint32" -> Primitive Uint32
  | "uint64" -> Primitive Uint64
  | "int32" -> Primitive Int32
  | "int64" -> Primitive Int64
  | "float32" -> Primitive Float32
  | "float64" -> Primitive Float64
  | "usize" -> Primitive Usize
  | "uint16" -> Primitive Uint32 (* Treat uint16 as uint32 for simplicity *)
  | "string" -> Primitive String
  | "out_string" -> Primitive Out_string
  | "string_with_default_empty" -> Primitive String_with_default_empty
  | "nullable_string" -> Primitive String (* nullable string is still a string *)
  | "c_void" | "void" -> Primitive C_void
  | s when String.is_prefix s ~prefix:"enum." ->
    Enum (String.chop_prefix_exn s ~prefix:"enum.")
  | s when String.is_prefix s ~prefix:"bitflag." ->
    Bitflag (String.chop_prefix_exn s ~prefix:"bitflag.")
  | s when String.is_prefix s ~prefix:"struct." ->
    Struct (String.chop_prefix_exn s ~prefix:"struct.")
  | s when String.is_prefix s ~prefix:"object." ->
    Object (String.chop_prefix_exn s ~prefix:"object.")
  | s when String.is_prefix s ~prefix:"callback." ->
    Callback (String.chop_prefix_exn s ~prefix:"callback.")
  | s when String.is_prefix s ~prefix:"array<" && String.is_suffix s ~suffix:">" ->
    let inner = String.chop_prefix_exn s ~prefix:"array<" in
    let inner = String.chop_suffix_exn inner ~suffix:">" in
    Array { elem = parse_type_ref inner; pointer = None }
  | s ->
    eprintf "Warning: unknown type '%s', treating as c_void\n" s;
    Primitive C_void
;;

let parse_pointer_opt (yaml : Yaml.value) : [ `Mutable | `Immutable ] option =
  match get_string_opt yaml "pointer" with
  | Some "mutable" -> Some `Mutable
  | Some "immutable" -> Some `Immutable
  | Some s -> failwithf "unknown pointer type: %s" s ()
  | None -> None
;;

let parse_constant (yaml : Yaml.value) : Ir.constant =
  { name = get_string_exn yaml "name"
  ; value = get_string_exn yaml "value"
  ; doc = get_string_or_default yaml "doc" ~default:""
  }
;;

let parse_enum_entry (yaml : Yaml.value) : Ir.enum_entry option =
  match yaml with
  | `Null -> None
  | `O _ ->
    Some
      { name = get_string_or_default yaml "name" ~default:"undefined"
      ; doc = get_string_or_default yaml "doc" ~default:""
      ; value = None
      }
  | _ -> failwith "expected object or null for enum entry"
;;

let parse_enum (yaml : Yaml.value) : Ir.enum =
  let entries = get_list_exn yaml "entries" in
  let entries = List.filter_map entries ~f:parse_enum_entry in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; entries
  }
;;

let parse_bitflag (yaml : Yaml.value) : Ir.bitflag =
  let entries = get_list_exn yaml "entries" in
  let entries = List.filter_map entries ~f:parse_enum_entry in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; entries
  }
;;

let parse_struct_member (yaml : Yaml.value) : Ir.struct_member =
  let name = get_string_or_default yaml "name" ~default:"unnamed" in
  let type_str = get_string_or_default yaml "type" ~default:"c_void" in
  let type_ = parse_type_ref type_str in
  let type_ =
    match parse_pointer_opt yaml with
    | Some `Mutable -> Ir.Pointer { mutable_ = true; inner = type_ }
    | Some `Immutable -> Ir.Pointer { mutable_ = false; inner = type_ }
    | None -> type_
  in
  { name
  ; type_
  ; optional = Option.value (get_bool_opt yaml "optional") ~default:false
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; pointer = parse_pointer_opt yaml
  }
;;

let parse_struct_type (yaml : Yaml.value) : Ir.struct_type =
  match get_string_opt yaml "type" with
  | Some "base_in" -> Base_in
  | Some "base_out" -> Base_out
  | Some "base_in_out" | Some "base_in_or_out" -> Base_in_out
  | Some "extension_in" -> Base_in (* Extension structs are also input *)
  | Some "extension_out" -> Base_out
  | Some "extension_in_out" -> Base_in_out
  | Some "standalone" | None -> Standalone
  | Some s ->
    eprintf "Warning: unknown struct type '%s', treating as standalone\n" s;
    Standalone
;;

let parse_struct (yaml : Yaml.value) : Ir.struct_ =
  let members = get_list_exn yaml "members" in
  let members = List.map members ~f:parse_struct_member in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; type_ = parse_struct_type yaml
  ; free_members = Option.value (get_bool_opt yaml "free_members") ~default:false
  ; members
  }
;;

let parse_arg (yaml : Yaml.value) : Ir.arg =
  let name =
    match get_string_opt yaml "name" with
    | Some n -> n
    | None ->
      eprintf "Warning: arg missing name in: %s\n" (Yaml.to_string_exn yaml);
      "unnamed"
  in
  let type_str =
    match get_string_opt yaml "type" with
    | Some t -> t
    | None ->
      eprintf "Warning: arg missing type in: %s\n" (Yaml.to_string_exn yaml);
      "c_void"
  in
  let type_ = parse_type_ref type_str in
  { name
  ; type_
  ; optional = Option.value (get_bool_opt yaml "optional") ~default:false
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; pointer = parse_pointer_opt yaml
  }
;;

let parse_return_type (yaml : Yaml.value) : Ir.return_type =
  { type_ = parse_type_ref (get_string_exn yaml "type")
  ; doc = get_string_or_default yaml "doc" ~default:""
  }
;;

let parse_callback (yaml : Yaml.value) : Ir.callback =
  let args =
    match get_obj_opt yaml "args" with
    | Some (`A args) -> List.map args ~f:parse_arg
    | _ -> []
  in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; args
  ; style = get_string_or_default yaml "style" ~default:""
  }
;;

let parse_function (yaml : Yaml.value) : Ir.function_ =
  let args =
    match get_obj_opt yaml "args" with
    | Some (`A args) -> List.map args ~f:parse_arg
    | _ -> []
  in
  let returns = get_obj_opt yaml "returns" |> Option.map ~f:parse_return_type in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; args
  ; returns
  }
;;

let parse_method (yaml : Yaml.value) : Ir.method_ =
  let args =
    match get_obj_opt yaml "args" with
    | Some (`A args) -> List.map args ~f:parse_arg
    | _ -> []
  in
  let returns = get_obj_opt yaml "returns" |> Option.map ~f:parse_return_type in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; args
  ; returns
  ; callback = get_string_opt yaml "callback"
  }
;;

let parse_object (yaml : Yaml.value) : Ir.object_ =
  let methods =
    match get_obj_opt yaml "methods" with
    | Some (`A methods) -> List.map methods ~f:parse_method
    | _ -> []
  in
  { name = get_string_exn yaml "name"
  ; doc = get_string_or_default yaml "doc" ~default:""
  ; methods
  }
;;

let parse_api (yaml : Yaml.value) : Ir.api =
  { constants = get_list_exn yaml "constants" |> List.map ~f:parse_constant
  ; enums = get_list_exn yaml "enums" |> List.map ~f:parse_enum
  ; bitflags = get_list_exn yaml "bitflags" |> List.map ~f:parse_bitflag
  ; structs = get_list_exn yaml "structs" |> List.map ~f:parse_struct
  ; callbacks = get_list_exn yaml "callbacks" |> List.map ~f:parse_callback
  ; functions = get_list_exn yaml "functions" |> List.map ~f:parse_function
  ; objects = get_list_exn yaml "objects" |> List.map ~f:parse_object
  }
;;

let load_file (path : string) : Ir.api =
  let yaml = In_channel.read_all path |> Yaml.of_string_exn in
  parse_api yaml
;;
