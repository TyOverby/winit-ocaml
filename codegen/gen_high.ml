open! Core

(** Generate high-level idiomatic OCaml bindings *)

module Method_key = struct
  module T = struct
    type t = string * string [@@deriving sexp, compare]
  end

  include T
  include Comparator.Make (T)
end

(** Methods that are manually implemented in the hand-written sections. These are
    (object_name, method_name) pairs. *)
let manual_implementations =
  Set.of_list
    (module Method_key)
    [ (* Instance methods *)
      "instance", "create_surface"
    ; "instance", "process_events"
    ; "instance", "request_adapter" (* async, we have sync wrapper *)
    ; "instance", "get_WGSL_language_features" (* uses struct output parameter *)
    ; "instance", "wait_any"
      (* uses struct input parameter *)
      (* Adapter methods *)
    ; "adapter", "get_info" (* uses special struct return *)
    ; "adapter", "request_device" (* async, we have sync wrapper *)
    ; "adapter", "get_limits" (* uses struct output parameter *)
    ; "adapter", "get_features"
      (* uses struct output parameter *)
      (* Device methods *)
    ; "device", "create_buffer" (* uses descriptor struct *)
    ; "device", "create_shader_module" (* uses descriptor struct *)
    ; "device", "create_command_encoder" (* uses descriptor struct *)
    ; "device", "create_texture" (* uses descriptor struct *)
    ; "device", "create_sampler" (* uses descriptor struct *)
    ; "device", "create_compute_pipeline" (* uses descriptor struct *)
    ; "device", "create_render_pipeline" (* uses descriptor struct *)
    ; "device", "create_bind_group_layout" (* uses descriptor with arrays *)
    ; "device", "create_bind_group" (* uses descriptor with arrays *)
    ; "device", "create_pipeline_layout" (* uses descriptor with arrays *)
    ; "device", "create_query_set" (* uses descriptor struct *)
    ; "device", "create_render_bundle_encoder" (* uses descriptor struct *)
    ; "device", "pop_error_scope" (* async callback *)
    ; "device", "get_queue" (* hand-written for cleaner return type *)
    ; "device", "get_limits" (* uses struct output parameter *)
    ; "device", "get_features" (* uses struct output parameter *)
    ; "device", "get_lost_future" (* returns Future struct *)
    ; "device", "get_adapter_info"
      (* returns struct *)
      (* Queue methods *)
    ; "queue", "submit" (* uses array argument *)
    ; "queue", "write_buffer" (* uses pointer + size *)
    ; "queue", "write_texture" (* uses structs and pointer *)
    ; "queue", "on_submitted_work_done"
      (* async callback *)
      (* Command encoder methods *)
    ; "command_encoder", "begin_compute_pass" (* uses descriptor struct *)
    ; "command_encoder", "begin_render_pass" (* uses descriptor struct *)
    ; "command_encoder", "finish" (* uses descriptor struct *)
    ; "command_encoder", "copy_buffer_to_buffer" (* implemented separately *)
    ; "command_encoder", "copy_buffer_to_texture" (* uses structs *)
    ; "command_encoder", "copy_texture_to_buffer" (* uses structs *)
    ; "command_encoder", "copy_texture_to_texture" (* uses structs *)
    ; "command_encoder", "clear_buffer" (* simple, could auto-gen but may want manual *)
    ; "command_encoder", "resolve_query_set" (* manual for clarity *)
    ; "command_encoder", "write_timestamp"
      (* manual for clarity *)
      (* Compute pass encoder methods *)
    ; "compute_pass_encoder", "set_bind_group" (* uses array for dynamic offsets *)
    ; "compute_pass_encoder", "push_debug_group" (* simple but keeping manual *)
    ; "compute_pass_encoder", "pop_debug_group" (* simple but keeping manual *)
    ; "compute_pass_encoder", "insert_debug_marker"
      (* simple but keeping manual *)
      (* Render pass encoder methods *)
    ; "render_pass_encoder", "set_bind_group" (* uses array for dynamic offsets *)
    ; "render_pass_encoder", "set_vertex_buffer" (* manual for better API *)
    ; "render_pass_encoder", "set_index_buffer" (* manual for better API *)
    ; "render_pass_encoder", "set_scissor_rect" (* simple, could auto-gen *)
    ; "render_pass_encoder", "set_viewport" (* simple, could auto-gen *)
    ; "render_pass_encoder", "set_blend_constant" (* uses struct *)
    ; "render_pass_encoder", "set_stencil_reference" (* simple *)
    ; "render_pass_encoder", "execute_bundles" (* uses array *)
    ; "render_pass_encoder", "begin_occlusion_query" (* simple *)
    ; "render_pass_encoder", "end_occlusion_query" (* simple *)
    ; "render_pass_encoder", "push_debug_group" (* simple *)
    ; "render_pass_encoder", "pop_debug_group" (* simple *)
    ; "render_pass_encoder", "insert_debug_marker" (* simple *)
    ; "render_pass_encoder", "write_timestamp"
      (* simple *)
      (* Render bundle encoder methods *)
    ; "render_bundle_encoder", "set_bind_group" (* uses array *)
    ; "render_bundle_encoder", "set_vertex_buffer" (* manual *)
    ; "render_bundle_encoder", "set_index_buffer" (* manual *)
    ; "render_bundle_encoder", "finish" (* uses descriptor *)
    ; "render_bundle_encoder", "push_debug_group" (* simple *)
    ; "render_bundle_encoder", "pop_debug_group" (* simple *)
    ; "render_bundle_encoder", "insert_debug_marker"
      (* simple *)
      (* Buffer methods *)
    ; "buffer", "map_async" (* async, we have sync wrapper *)
    ; "buffer", "get_mapped_range" (* returns pointer, we have bigarray wrapper *)
    ; "buffer", "get_const_mapped_range"
      (* returns pointer, we have bigarray wrapper *)
      (* Texture methods *)
    ; "texture", "create_view"
      (* uses descriptor struct *)
      (* Shader module methods *)
    ; "shader_module", "get_compilation_info"
      (* async callback *)
      (* Surface methods - mostly for windowed rendering *)
    ; "surface", "configure" (* uses struct *)
    ; "surface", "get_capabilities" (* uses struct output *)
    ; "surface", "get_current_texture" (* uses struct output *)
    ; "surface", "present" (* simple but for windowed *)
    ; "surface", "unconfigure" (* simple but for windowed *)
    ; "surface", "set_label" (* simple but for windowed *)
    ]
;;

(** Methods that are intentionally not exposed in the high-level API. These are
    (object_name, method_name) pairs with reasons. *)
let intentionally_skipped =
  Set.of_list
    (module Method_key)
    [ (* Internal/advanced methods that typical users don't need *)
      "adapter", "request_adapter_info" (* deprecated, use get_info *)
    ; "device", "create_error_external_texture" (* internal/testing *)
    ; "device", "import_external_texture" (* advanced external interop *)
    ; "device", "create_render_pipeline_async" (* async version, use sync *)
    ; "device", "create_compute_pipeline_async" (* async version, use sync *)
    ; "surface", "get_preferred_format" (* deprecated *)
    ]
;;

(** Check if a method is accounted for (either manual or intentionally skipped) *)
let method_is_accounted_for (obj_name : string) (method_name : string) : bool =
  Set.mem manual_implementations (obj_name, method_name)
  || Set.mem intentionally_skipped (obj_name, method_name)
;;

(** Filter out unhelpful doc strings like "TODO" *)
let useful_doc (doc : string) : string option =
  let doc = String.strip doc in
  if String.is_empty doc
     || String.equal doc "TODO"
     || String.is_prefix doc ~prefix:"TODO\n"
  then None
  else Some doc
;;

(** Get the OCaml module name for a type. Lowercases everything then capitalizes only the
    first letter. e.g., "texture_format" -> "Texture_format", "extent_3D" -> "Extent_3d" *)
let ocaml_module_name (name : string) : string =
  String.lowercase name |> String.capitalize
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
    let args_ok =
      List.for_all method_.args ~f:(fun arg -> is_simple_arg_type arg.type_)
    in
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
    sprintf
      "(match %s with Some x -> x.%s.handle | None -> 0n)"
      arg_name
      (ocaml_module_name name)
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
    sprintf
      "({ %s.handle = %s } : %s.t)"
      (ocaml_module_name name)
      result_expr
      (ocaml_module_name name)
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
     %send\n"
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

(** Order objects so dependencies come first. Objects that don't depend on others come
    first. *)
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
  ; "texture_view" (* Objects that depend on above *)
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

  let submit t ~command_buffers =
    let handles = List.map (fun (cb : Command_buffer.t) -> cb.handle) command_buffers in
    Wgpu_low.queue_submit t.handle (Array.of_list handles)

  let write_buffer t ~buffer ~offset ~data =
    Wgpu_low.queue_write_buffer_bigarray t.handle buffer.Buffer.handle offset data
end

module Device = struct
  type t = { handle : Wgpu_low.device }

  let release t = Wgpu_low.device_release t.handle
  let get_queue t = { Queue.handle = Wgpu_low.device_get_queue t.handle }
  let destroy t = Wgpu_low.device_destroy t.handle
  let has_feature t ~feature = Wgpu_low.device_has_feature t.handle (Feature_name.to_int feature)
  let push_error_scope t ~filter = Wgpu_low.device_push_error_scope t.handle (Error_filter.to_int filter)
  let set_label t ~label = Wgpu_low.device_set_label t.handle label

  let create_buffer t ?(label = "") ~size ~usage ?(mapped_at_creation = false) () =
    let desc = Wgpu_low.Buffer_descriptor.buffer_descriptor_create () in
    Wgpu_low.Buffer_descriptor.buffer_descriptor_set_label desc label;
    Wgpu_low.Buffer_descriptor.buffer_descriptor_set_size desc size;
    Wgpu_low.Buffer_descriptor.buffer_descriptor_set_usage desc (Buffer_usage.list_to_int usage);
    Wgpu_low.Buffer_descriptor.buffer_descriptor_set_mapped_at_creation desc mapped_at_creation;
    let buffer = Wgpu_low.device_create_buffer t.handle desc in
    Wgpu_low.Buffer_descriptor.buffer_descriptor_free desc;
    ({ Buffer.handle = buffer } : Buffer.t)

  let create_shader_module t ?(label = "") ~wgsl () =
    let shader = Wgpu_low.device_create_shader_module_wgsl t.handle label wgsl in
    ({ Shader_module.handle = shader } : Shader_module.t)

  let create_command_encoder t ?(label = "") () =
    let encoder = Wgpu_low.device_create_command_encoder_simple t.handle label in
    ({ Command_encoder.handle = encoder } : Command_encoder.t)

  let create_texture t ?(label = "") ~size ~format ~usage ?(dimension = Texture_dimension.N2d)
      ?(mip_level_count = 1) ?(sample_count = 1) () =
    let desc = Wgpu_low.Texture_descriptor.texture_descriptor_create () in
    Wgpu_low.Texture_descriptor.texture_descriptor_set_label desc label;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_dimension desc (Texture_dimension.to_int dimension);
    let extent = Wgpu_low.Extent_3d.extent_3D_create () in
    let (width, height, depth) = size in
    Wgpu_low.Extent_3d.extent_3D_set_width extent width;
    Wgpu_low.Extent_3d.extent_3D_set_height extent height;
    Wgpu_low.Extent_3d.extent_3D_set_depth_or_array_layers extent depth;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_size desc extent;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_format desc (Texture_format.to_int format);
    Wgpu_low.Texture_descriptor.texture_descriptor_set_usage desc (Texture_usage.list_to_int usage);
    Wgpu_low.Texture_descriptor.texture_descriptor_set_mip_level_count desc mip_level_count;
    Wgpu_low.Texture_descriptor.texture_descriptor_set_sample_count desc sample_count;
    let texture = Wgpu_low.device_create_texture t.handle desc in
    Wgpu_low.Extent_3d.extent_3D_free extent;
    Wgpu_low.Texture_descriptor.texture_descriptor_free desc;
    ({ Texture.handle = texture } : Texture.t)

  let create_sampler t ?(label = "") () =
    ignore (label : string);
    let sampler = Wgpu_low.device_create_sampler t.handle 0n in
    ({ Sampler.handle = sampler } : Sampler.t)

  let create_compute_pipeline t ?(label = "") ~layout ~module_ ~entry_point () =
    let pipeline = Wgpu_low.device_create_compute_pipeline_simple t.handle
      label layout.Pipeline_layout.handle module_.Shader_module.handle entry_point in
    ({ Compute_pipeline.handle = pipeline } : Compute_pipeline.t)

  let create_render_pipeline t ?(label = "") ~shader_module ~vertex_entry_point
      ~fragment_entry_point ~color_format () =
    let pipeline = Wgpu_low.device_create_render_pipeline_simple t.handle
      label shader_module.Shader_module.handle vertex_entry_point
      fragment_entry_point (Texture_format.to_int color_format) in
    ({ Render_pipeline.handle = pipeline } : Render_pipeline.t)

  let create_bind_group_layout_for_storage_buffer t ?(label = "") ~binding ?(read_only = false) () =
    let layout = Wgpu_low.device_create_bind_group_layout_storage t.handle
      label binding read_only in
    ({ Bind_group_layout.handle = layout } : Bind_group_layout.t)

  let create_bind_group t ?(label = "") ~layout ~binding ~buffer ~offset ~size () =
    let bind_group = Wgpu_low.device_create_bind_group_buffer t.handle
      label layout.Bind_group_layout.handle binding buffer.Buffer.handle offset size in
    ({ Bind_group.handle = bind_group } : Bind_group.t)

  let create_pipeline_layout t ?(label = "") ~bind_group_layout () =
    let layout = Wgpu_low.device_create_pipeline_layout_single t.handle
      label bind_group_layout.Bind_group_layout.handle in
    ({ Pipeline_layout.handle = layout } : Pipeline_layout.t)

  let poll t ?(wait = false) () = Wgpu_low.device_poll t.handle wait
end

module Adapter = struct
  type t = { handle : Wgpu_low.adapter }

  let get_info t = Wgpu_low.adapter_get_info t.handle
  let release t = Wgpu_low.adapter_release t.handle
  let request_device t =
    let device = Wgpu_low.adapter_request_device_sync t.handle in
    { Device.handle = device }
  let has_feature t ~feature = Wgpu_low.adapter_has_feature t.handle (Feature_name.to_int feature)
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

(* Convenience functions for methods that take complex descriptors *)

let begin_compute_pass (encoder : Command_encoder.t) ?(label = "") () =
  let pass = Wgpu_low.command_encoder_begin_compute_pass_simple encoder.handle label in
  ({ Compute_pass_encoder.handle = pass } : Compute_pass_encoder.t)

let begin_render_pass (encoder : Command_encoder.t) ?(label = "") ~color_view ~clear_color () =
  let (r, g, b, a) = clear_color in
  let pass = Wgpu_low.command_encoder_begin_render_pass_simple encoder.handle
    label color_view.Texture_view.handle r g b a in
  ({ Render_pass_encoder.handle = pass } : Render_pass_encoder.t)

let finish (encoder : Command_encoder.t) ?(label = "") () =
  let cmd_buffer = Wgpu_low.command_encoder_finish_simple encoder.handle label in
  ({ Command_buffer.handle = cmd_buffer } : Command_buffer.t)

let set_bind_group (pass : Compute_pass_encoder.t) ~index ~bind_group =
  Wgpu_low.compute_pass_encoder_set_bind_group_simple pass.handle index bind_group.Bind_group.handle

let set_bind_group_render (pass : Render_pass_encoder.t) ~index ~bind_group =
  Wgpu_low.render_pass_encoder_set_bind_group pass.handle index bind_group.Bind_group.handle [||]

let copy_texture_to_buffer (encoder : Command_encoder.t) ~texture ~buffer ~size ~bytes_per_row () =
  let (width, height) = size in
  Wgpu_low.command_encoder_copy_texture_to_buffer_simple encoder.handle
    texture.Texture.handle buffer.Buffer.handle width height bytes_per_row

let map_buffer (buffer : Buffer.t) ~mode ~offset ~size =
  ignore (Wgpu_low.buffer_map_sync buffer.handle (Map_mode.list_to_int mode) offset size : int)

let get_mapped_range (buffer : Buffer.t) ~offset ~size =
  Wgpu_low.buffer_get_mapped_range_bigarray buffer.handle offset size

let get_const_mapped_range (buffer : Buffer.t) ~offset ~size =
  Wgpu_low.buffer_get_const_mapped_range_bigarray buffer.handle offset size

let create_texture_view (texture : Texture.t) ?(label = "") () =
  let view = Wgpu_low.texture_create_view_simple texture.handle label in
  ({ Texture_view.handle = view } : Texture_view.t)
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
  val submit : t -> command_buffers:Command_buffer.t list -> unit
  val write_buffer : t -> buffer:Buffer.t -> offset:int64 ->
    data:(int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t -> unit
end

module Device : sig
  type t

  val release : t -> unit
  val get_queue : t -> Queue.t
  val destroy : t -> unit
  val has_feature : t -> feature:Feature_name.t -> bool
  val push_error_scope : t -> filter:Error_filter.t -> unit
  val set_label : t -> label:string -> unit

  (** Create a GPU buffer *)
  val create_buffer : t -> ?label:string -> size:int64 -> usage:Buffer_usage.t list ->
    ?mapped_at_creation:bool -> unit -> Buffer.t

  (** Create a shader module from WGSL source *)
  val create_shader_module : t -> ?label:string -> wgsl:string -> unit -> Shader_module.t

  (** Create a command encoder *)
  val create_command_encoder : t -> ?label:string -> unit -> Command_encoder.t

  (** Create a texture *)
  val create_texture : t -> ?label:string -> size:(int * int * int) ->
    format:Texture_format.t -> usage:Texture_usage.t list ->
    ?dimension:Texture_dimension.t -> ?mip_level_count:int -> ?sample_count:int ->
    unit -> Texture.t

  (** Create a sampler with default settings *)
  val create_sampler : t -> ?label:string -> unit -> Sampler.t

  (** Create a compute pipeline *)
  val create_compute_pipeline : t -> ?label:string -> layout:Pipeline_layout.t ->
    module_:Shader_module.t -> entry_point:string -> unit -> Compute_pipeline.t

  (** Create a render pipeline (uses single shader module for vertex and fragment) *)
  val create_render_pipeline : t -> ?label:string -> shader_module:Shader_module.t ->
    vertex_entry_point:string -> fragment_entry_point:string ->
    color_format:Texture_format.t -> unit -> Render_pipeline.t

  (** Create a bind group layout for a single storage buffer *)
  val create_bind_group_layout_for_storage_buffer : t -> ?label:string -> binding:int ->
    ?read_only:bool -> unit -> Bind_group_layout.t

  (** Create a bind group with a single buffer binding *)
  val create_bind_group : t -> ?label:string -> layout:Bind_group_layout.t ->
    binding:int -> buffer:Buffer.t -> offset:int64 -> size:int64 -> unit -> Bind_group.t

  (** Create a pipeline layout (currently supports single bind group layout) *)
  val create_pipeline_layout : t -> ?label:string -> bind_group_layout:Bind_group_layout.t ->
    unit -> Pipeline_layout.t

  (** Poll the device for completed work *)
  val poll : t -> ?wait:bool -> unit -> unit
end

module Adapter : sig
  type t

  val get_info : t -> Adapter_info.t
  val release : t -> unit
  val request_device : t -> Device.t
  val has_feature : t -> feature:Feature_name.t -> bool
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

(** Begin a compute pass on a command encoder *)
val begin_compute_pass : Command_encoder.t -> ?label:string -> unit -> Compute_pass_encoder.t

(** Begin a render pass on a command encoder with a single color attachment *)
val begin_render_pass : Command_encoder.t -> ?label:string -> color_view:Texture_view.t ->
  clear_color:(float * float * float * float) -> unit -> Render_pass_encoder.t

(** Finish recording commands and get a command buffer *)
val finish : Command_encoder.t -> ?label:string -> unit -> Command_buffer.t

(** Set a bind group on a compute pass encoder *)
val set_bind_group : Compute_pass_encoder.t -> index:int -> bind_group:Bind_group.t -> unit

(** Set a bind group on a render pass encoder *)
val set_bind_group_render : Render_pass_encoder.t -> index:int -> bind_group:Bind_group.t -> unit

(** Copy texture to buffer (for readback) *)
val copy_texture_to_buffer : Command_encoder.t -> texture:Texture.t ->
  buffer:Buffer.t -> size:(int * int) -> bytes_per_row:int -> unit -> unit

(** Map a buffer for CPU access (synchronous) *)
val map_buffer : Buffer.t -> mode:Map_mode.t list -> offset:int64 -> size:int64 -> unit

(** Get mapped buffer data as a bigarray *)
val get_mapped_range : Buffer.t -> offset:int64 -> size:int64 ->
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(** Get const mapped buffer data as a bigarray (for read-only access) *)
val get_const_mapped_range : Buffer.t -> offset:int64 -> size:int64 ->
  (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

(** Create a texture view from a texture *)
val create_texture_view : Texture.t -> ?label:string -> unit -> Texture_view.t
|}
  in
  String.concat [ header; enums; bitflags; objects; adapter_module; instance_module ]
;;

(** Validate that all non-auto-generated methods are accounted for. Returns a list of
    error messages for unaccounted methods. *)
let validate_method_coverage (api : Ir.api) : string list =
  let errors = ref [] in
  List.iter api.objects ~f:(fun obj ->
    List.iter obj.methods ~f:(fun method_ ->
      if not (method_is_high_level method_)
      then
        if (* This method isn't auto-generated, check if it's accounted for *)
           not (method_is_accounted_for obj.name method_.name)
        then (
          let reason =
            if method_is_async method_
            then "async (has callback)"
            else (
              let non_simple_args =
                List.filter method_.args ~f:(fun arg ->
                  not (is_simple_arg_type arg.type_))
                |> List.map ~f:(fun arg ->
                  sprintf
                    "%s: %s"
                    arg.name
                    (match arg.type_ with
                     | Ir.Struct name -> sprintf "Struct(%s)" name
                     | Ir.Callback _ -> "Callback"
                     | Ir.Array _ -> "Array"
                     | Ir.Pointer _ -> "Pointer"
                     | _ -> "other"))
              in
              let non_simple_return =
                match method_.returns with
                | None -> []
                | Some ret ->
                  if is_simple_return_type ret.type_
                  then []
                  else [ sprintf "returns: non-simple" ]
              in
              String.concat ~sep:", " (non_simple_args @ non_simple_return))
          in
          errors
          := sprintf "UNACCOUNTED: %s.%s (%s)" obj.name method_.name reason :: !errors)));
  List.rev !errors
;;

(** Check method coverage and fail if there are unaccounted methods *)
let check_method_coverage (api : Ir.api) : unit =
  let errors = validate_method_coverage api in
  if not (List.is_empty errors)
  then (
    eprintf "\n=== UNACCOUNTED METHODS ===\n";
    eprintf "The following methods are not auto-generated and not listed in\n";
    eprintf "manual_implementations or intentionally_skipped:\n\n";
    List.iter errors ~f:(fun msg -> eprintf "  %s\n" msg);
    eprintf
      "\n\
       Please add these methods to either:\n\
      \  - manual_implementations (if you will implement them)\n\
      \  - intentionally_skipped (if they should not be exposed)\n\n";
    failwith "Unaccounted methods in high-level API")
;;
