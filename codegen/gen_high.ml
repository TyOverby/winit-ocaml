open! Core

(** Generate high-level idiomatic OCaml bindings *)

(** Filter out unhelpful doc strings like "TODO" *)
let useful_doc (doc : string) : string option =
  let doc = String.strip doc in
  if String.is_empty doc
     || String.equal doc "TODO"
     || String.is_prefix doc ~prefix:"TODO\n"
  then None
  else Some doc
;;

(** Get the OCaml module name for a type *)
let ocaml_module_name (name : string) : string =
  String.capitalize name
  |> String.substr_replace_all ~pattern:"_" ~with_:" "
  |> fun s ->
  String.split s ~on:' ' |> List.map ~f:String.capitalize |> String.concat ~sep:"_"
;;

(** Convert C name conventions (e.g., discrete_GPU -> Discrete_gpu) *)
let normalize_enum_entry_name (name : string) : string =
  let s = String.lowercase name in
  let s = String.capitalize s in
  (* OCaml identifiers can't start with a digit, prefix with N *)
  if String.length s > 0 && Char.is_digit (String.get s 0) then "N" ^ s else s
;;

(** OCaml reserved words that need escaping *)
let ocaml_keywords =
  [ "and"
  ; "as"
  ; "assert"
  ; "asr"
  ; "begin"
  ; "class"
  ; "constraint"
  ; "do"
  ; "done"
  ; "downto"
  ; "else"
  ; "end"
  ; "exception"
  ; "external"
  ; "false"
  ; "for"
  ; "fun"
  ; "function"
  ; "functor"
  ; "if"
  ; "in"
  ; "include"
  ; "inherit"
  ; "initializer"
  ; "land"
  ; "lazy"
  ; "let"
  ; "lor"
  ; "lsl"
  ; "lsr"
  ; "lxor"
  ; "match"
  ; "method"
  ; "mod"
  ; "module"
  ; "mutable"
  ; "new"
  ; "nonrec"
  ; "object"
  ; "of"
  ; "open"
  ; "or"
  ; "private"
  ; "rec"
  ; "sig"
  ; "struct"
  ; "then"
  ; "to"
  ; "true"
  ; "try"
  ; "type"
  ; "val"
  ; "virtual"
  ; "when"
  ; "while"
  ; "with"
  ]
;;

(** Escape OCaml keywords by adding underscore suffix *)
let escape_keyword (name : string) : string =
  if List.mem ocaml_keywords name ~equal:String.equal then name ^ "_" else name
;;

(** Check if a method uses callbacks (async) *)
let method_is_async (method_ : Ir.method_) : bool = Option.is_some method_.callback

(** Check if an argument type is "simple" (can be easily converted) *)
let rec is_simple_arg_type (type_ref : Ir.type_ref) : bool =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Optional inner -> is_simple_arg_type inner
  | Struct _ -> false (* Structs require descriptor setup *)
  | Callback _ -> false
  | Array _ -> false (* Arrays need special handling *)
  | Pointer _ -> false
;;

(** Check if a return type is "simple" *)
let is_simple_return_type (type_ref : Ir.type_ref) : bool =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Struct _ -> false (* Returning structs is complex *)
  | _ -> false
;;

(** Check if a method can be included in the high-level API *)
let method_is_high_level (method_ : Ir.method_) : bool =
  if method_is_async method_
  then false
  else (
    let args_ok = List.for_all method_.args ~f:(fun arg -> is_simple_arg_type arg.type_) in
    let return_ok =
      match method_.returns with
      | None -> true
      | Some ret -> is_simple_return_type ret.type_
    in
    args_ok && return_ok)
;;

(** Get high-level OCaml type for a type_ref (for arguments) *)
let rec high_level_arg_type (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive Bool -> "bool"
  | Primitive (Uint32 | Int32) -> "int"
  | Primitive (Uint64 | Int64 | Usize) -> "int64"
  | Primitive (Float32 | Float64) -> "float"
  | Primitive (String | Out_string | String_with_default_empty) -> "string"
  | Primitive C_void -> "nativeint"
  | Enum name -> ocaml_module_name name ^ ".t"
  | Bitflag name -> ocaml_module_name name ^ ".t list"
  | Object name -> ocaml_module_name name ^ ".t"
  | Optional inner -> high_level_arg_type inner ^ " option"
  | Struct _ -> "nativeint" (* fallback *)
  | Callback _ -> "nativeint"
  | Array _ -> "nativeint array"
  | Pointer _ -> "nativeint"
;;

(** Get high-level OCaml type for return values *)
let high_level_return_type (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive Bool -> "bool"
  | Primitive (Uint32 | Int32) -> "int"
  | Primitive (Uint64 | Int64 | Usize) -> "int64"
  | Primitive (Float32 | Float64) -> "float"
  | Primitive (String | Out_string | String_with_default_empty) -> "string"
  | Primitive C_void -> "nativeint"
  | Enum _ -> "int" (* TODO: add of_int to enums *)
  | Bitflag _ -> "int" (* bitflags return raw int, no of_int yet *)
  | Object name -> ocaml_module_name name ^ ".t"
  | _ -> "nativeint"
;;

(** Generate code to convert a high-level argument to low-level *)
let arg_to_low_level (arg_name : string) (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive _ -> arg_name
  | Enum name -> sprintf "(%s.to_int %s)" (ocaml_module_name name) arg_name
  | Bitflag name -> sprintf "(%s.list_to_int %s)" (ocaml_module_name name) arg_name
  | Object name -> sprintf "%s.%s.handle" arg_name (ocaml_module_name name)
  | Optional (Object name) ->
    sprintf "(match %s with Some x -> x.%s.handle | None -> 0n)" arg_name (ocaml_module_name name)
  | Optional _ -> arg_name (* shouldn't happen for simple types *)
  | _ -> arg_name
;;

(** Generate code to convert a low-level return value to high-level *)
let return_to_high_level (result_expr : string) (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive _ -> result_expr
  | Enum _ -> result_expr (* enums return as ints for now *)
  | Bitflag _ -> result_expr (* bitflags return as ints for now *)
  | Object name ->
    sprintf "({ %s.handle = %s } : %s.t)" (ocaml_module_name name) result_expr (ocaml_module_name name)
  | _ -> result_expr
;;

(** Generate ML implementation for a method *)
let gen_ml_method (obj : Ir.object_) (method_ : Ir.method_) : string option =
  if not (method_is_high_level method_)
  then None
  else (
    let method_name = escape_keyword method_.name in
    let low_level_func = sprintf "Wgpu_low.%s_%s" obj.name method_.name in
    (* Build argument list *)
    let args =
      List.map method_.args ~f:(fun arg ->
        let converted = arg_to_low_level arg.name arg.type_ in
        arg.name, converted)
    in
    let arg_names = List.map args ~f:fst in
    let arg_conversions = List.map args ~f:snd in
    (* Build function signature *)
    let param_list =
      if List.is_empty arg_names
      then "t"
      else "t " ^ String.concat ~sep:" " (List.map arg_names ~f:(sprintf "~%s"))
    in
    (* Build call *)
    let call_args = "t.handle" :: arg_conversions in
    let call = sprintf "%s %s" low_level_func (String.concat ~sep:" " call_args) in
    (* Build return *)
    let body =
      match method_.returns with
      | None -> call
      | Some ret -> return_to_high_level call ret.type_
    in
    Some (sprintf "  let %s %s = %s\n" method_name param_list body))
;;

(** Generate MLI signature for a method *)
let gen_mli_method (_obj : Ir.object_) (method_ : Ir.method_) : string option =
  if not (method_is_high_level method_)
  then None
  else (
    let method_name = escape_keyword method_.name in
    (* Build argument types *)
    let arg_types =
      List.map method_.args ~f:(fun arg ->
        sprintf "%s:%s" arg.name (high_level_arg_type arg.type_))
    in
    let return_type =
      match method_.returns with
      | None -> "unit"
      | Some ret -> high_level_return_type ret.type_
    in
    let type_sig =
      if List.is_empty arg_types
      then sprintf "t -> %s" return_type
      else sprintf "t -> %s -> %s" (String.concat ~sep:" -> " arg_types) return_type
    in
    Some (sprintf "  val %s : %s\n" method_name type_sig))
;;

(** Generate high-level OCaml code for an enum type (re-exports low-level) *)
let gen_ml_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  sprintf "module %s = Wgpu_low.%s\n" module_name module_name
;;

(** Generate MLI for an enum type *)
let gen_mli_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let doc_comment =
    match useful_doc enum.doc with
    | None -> ""
    | Some doc -> sprintf "  (** %s *)\n" doc
  in
  let variants =
    List.map enum.entries ~f:(fun entry ->
      sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    "module %s : sig\n%s  type t =\n%s\n\n  val to_int : t -> int\nend\n"
    module_name
    doc_comment
    variants
;;

(** Generate high-level OCaml code for a bitflag type *)
let gen_ml_bitflag (bitflag : Ir.bitflag) : string =
  let module_name = ocaml_module_name bitflag.name in
  sprintf "module %s = Wgpu_low.%s\n" module_name module_name
;;

(** Generate MLI for a bitflag type *)
let gen_mli_bitflag (bitflag : Ir.bitflag) : string =
  let module_name = ocaml_module_name bitflag.name in
  let doc_comment =
    match useful_doc bitflag.doc with
    | None -> ""
    | Some doc -> sprintf "  (** %s *)\n" doc
  in
  let variants =
    List.map bitflag.entries ~f:(fun entry ->
      sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    "module %s : sig\n\
     %s  type t =\n\
     %s\n\n\
    \  val to_int : t -> int\n\
    \  val list_to_int : t list -> int\n\
     end\n"
    module_name
    doc_comment
    variants
;;

(** Generate high-level OCaml code for an object type with methods *)
let gen_ml_object (obj : Ir.object_) : string =
  let module_name = ocaml_module_name obj.name in
  let methods =
    List.filter_map obj.methods ~f:(gen_ml_method obj) |> String.concat ~sep:""
  in
  sprintf
    "module %s = struct\n\
    \  type t = { handle : Wgpu_low.%s }\n\n\
    \  let release t = Wgpu_low.%s_release t.handle\n\
     %s\
     end\n"
    module_name
    obj.name
    obj.name
    methods
;;

(** Generate MLI for an object type with methods *)
let gen_mli_object (obj : Ir.object_) : string =
  let module_name = ocaml_module_name obj.name in
  let doc_comment =
    match useful_doc obj.doc with
    | None -> ""
    | Some doc -> sprintf "  (** %s *)\n\n" doc
  in
  let methods =
    List.filter_map obj.methods ~f:(gen_mli_method obj) |> String.concat ~sep:""
  in
  sprintf
    "module %s : sig\n%s  type t\n\n  val release : t -> unit\n%send\n"
    module_name
    doc_comment
    methods
;;

(** Order objects so dependencies come first. Objects that don't depend on others come first. *)
let object_order =
  [ (* Leaf objects - no dependencies on other objects in methods *)
    "bind_group"
  ; "bind_group_layout"
  ; "buffer"
  ; "command_buffer"
  ; "compute_pipeline"
  ; "pipeline_layout"
  ; "query_set"
  ; "render_bundle"
  ; "render_pipeline"
  ; "sampler"
  ; "shader_module"
  ; "surface"
  ; "texture"
  ; "texture_view"
    (* Objects that depend on above *)
  ; "command_encoder"
  ; "compute_pass_encoder"
  ; "render_bundle_encoder"
  ; "render_pass_encoder"
  ]
;;

let sort_objects (objects : Ir.object_ list) : Ir.object_ list =
  let order_map =
    List.mapi object_order ~f:(fun i name -> name, i) |> Map.of_alist_exn (module String)
  in
  List.sort objects ~compare:(fun a b ->
    let a_order = Map.find order_map a.name |> Option.value ~default:999 in
    let b_order = Map.find order_map b.name |> Option.value ~default:999 in
    Int.compare a_order b_order)
;;

(** Generate all high-level OCaml code *)
let gen_ml (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - high-level OCaml bindings *)\n\n" in
  let enums = List.map api.enums ~f:gen_ml_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_ml_bitflag |> String.concat ~sep:"\n" in
  (* Filter out objects we handle specially *)
  let special_objects = [ "instance"; "adapter"; "device"; "queue" ] in
  let objects =
    List.filter api.objects ~f:(fun obj ->
      not (List.mem special_objects obj.name ~equal:String.equal))
    |> sort_objects
    |> List.map ~f:gen_ml_object
    |> String.concat ~sep:"\n"
  in
  (* Adapter module *)
  let adapter_module =
    {|module Adapter_info = struct
  type t = Wgpu_low.adapter_info =
    { vendor : string
    ; architecture : string
    ; device : string
    ; description : string
    ; backend_type : int
    ; adapter_type : int
    }
end

module Queue = struct
  type t = { handle : Wgpu_low.queue }

  let release t = Wgpu_low.queue_release t.handle
  let set_label t ~label = Wgpu_low.queue_set_label t.handle label
end

module Device = struct
  type t = { handle : Wgpu_low.device }

  let release t = Wgpu_low.device_release t.handle
  let get_queue t = { Queue.handle = Wgpu_low.device_get_queue t.handle }
  let destroy t = Wgpu_low.device_destroy t.handle
  let has_feature t ~feature = Wgpu_low.device_has_feature t.handle (Feature_Name.to_int feature)
  let push_error_scope t ~filter = Wgpu_low.device_push_error_scope t.handle (Error_Filter.to_int filter)
  let set_label t ~label = Wgpu_low.device_set_label t.handle label
end

module Adapter = struct
  type t = { handle : Wgpu_low.adapter }

  let get_info t = Wgpu_low.adapter_get_info t.handle
  let release t = Wgpu_low.adapter_release t.handle
  let request_device t =
    let device = Wgpu_low.adapter_request_device_sync t.handle in
    { Device.handle = device }
  let has_feature t ~feature = Wgpu_low.adapter_has_feature t.handle (Feature_Name.to_int feature)
end
|}
  in
  (* Instance module with create function - special handling *)
  let instance_module =
    {|module Instance = struct
  type t = { handle : Wgpu_low.instance }

  let create () = { handle = Wgpu_low.create_instance () }
  let release t = Wgpu_low.instance_release t.handle

  let request_adapter t =
    let adapter = Wgpu_low.instance_request_adapter_sync t.handle in
    { Adapter.handle = adapter }
end
|}
  in
  String.concat [ header; enums; bitflags; objects; adapter_module; instance_module ]
;;

(** Generate all high-level OCaml interface *)
let gen_mli (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - high-level OCaml interface *)\n\n" in
  let enums = List.map api.enums ~f:gen_mli_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_mli_bitflag |> String.concat ~sep:"\n" in
  (* Filter out objects we handle specially *)
  let special_objects = [ "instance"; "adapter"; "device"; "queue" ] in
  let objects =
    List.filter api.objects ~f:(fun obj ->
      not (List.mem special_objects obj.name ~equal:String.equal))
    |> sort_objects
    |> List.map ~f:gen_mli_object
    |> String.concat ~sep:"\n"
  in
  (* Adapter module *)
  let adapter_module =
    {|module Adapter_info : sig
  type t =
    { vendor : string
    ; architecture : string
    ; device : string
    ; description : string
    ; backend_type : int
    ; adapter_type : int
    }
end

module Queue : sig
  type t

  val release : t -> unit
  val set_label : t -> label:string -> unit
end

module Device : sig
  type t

  val release : t -> unit
  val get_queue : t -> Queue.t
  val destroy : t -> unit
  val has_feature : t -> feature:Feature_Name.t -> bool
  val push_error_scope : t -> filter:Error_Filter.t -> unit
  val set_label : t -> label:string -> unit
end

module Adapter : sig
  type t

  val get_info : t -> Adapter_info.t
  val release : t -> unit
  val request_device : t -> Device.t
  val has_feature : t -> feature:Feature_Name.t -> bool
end
|}
  in
  (* Instance module interface - special handling *)
  let instance_module =
    {|module Instance : sig
  type t

  val create : unit -> t
  val release : t -> unit
  val request_adapter : t -> Adapter.t
end
|}
  in
  String.concat [ header; enums; bitflags; objects; adapter_module; instance_module ]
;;
