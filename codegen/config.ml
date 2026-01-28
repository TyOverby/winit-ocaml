open! Core

module Method_key = struct
  module T = struct
    type t = string * string [@@deriving sexp, compare, equal]
  end

  include T
  include Comparator.Make (T)
end

type method_handling =
  | Manual of { reason : string } (** Method is implemented by hand in template code *)
  | Skipped of { reason : string } (** Method is intentionally not exposed *)
  | Auto (** Method is auto-generated *)
[@@deriving sexp_of]

let method_config : (Method_key.t * method_handling) list =
  [ (* Instance methods - some manually implemented in instance_module *)
    ( ("instance", "release")
    , Manual { reason = "Custom release logic with instance cleanup" } )
  ; ("instance", "create_surface"), Manual { reason = "Complex struct handling" }
  ; ("instance", "process_events"), Manual { reason = "Special event processing logic" }
  ; ( ("instance", "request_adapter")
    , Manual { reason = "Async method, we provide sync wrapper" } )
  ; ( ("instance", "get_WGSL_language_features")
    , Manual { reason = "Uses struct output parameter" } )
  ; ("instance", "wait_any"), Manual { reason = "Uses struct input parameter" }
    (* Adapter methods - some manually implemented in adapter_module_suffix *)
  ; ("adapter", "release"), Manual { reason = "Custom release logic" }
  ; ("adapter", "has_feature"), Manual { reason = "Custom feature checking logic" }
  ; ( ("adapter", "get_info")
    , Manual { reason = "Uses special struct return, manually implemented" } )
  ; ( ("adapter", "request_device")
    , Manual { reason = "Async method, we provide sync wrapper" } )
  ; ("adapter", "get_features"), Manual { reason = "Output struct with array member" }
    (* Device methods - manually implemented in adapter_module_prefix *)
  ; ("device", "release"), Manual { reason = "Custom release logic" }
  ; ("device", "poll"), Manual { reason = "Custom polling logic" }
  ; ("device", "get_features"), Manual { reason = "Output struct with array member" }
  ; ("device", "create_shader_module"), Manual { reason = "Uses chained WGSL struct" }
  ; ("device", "create_texture"), Manual { reason = "Uses nested extent_3D struct" }
  ; ( ("device", "create_compute_pipeline")
    , Manual { reason = "Uses nested programmable_stage" } )
  ; ("device", "create_render_pipeline"), Manual { reason = "Deeply nested descriptors" }
  ; ( ("device", "create_bind_group_layout_for_storage_buffer")
    , Manual { reason = "Convenience helper method" } )
  ; ("device", "pop_error_scope"), Manual { reason = "Async callback" }
  ; ("device", "get_queue"), Manual { reason = "Hand-written for cleaner return type" }
  ; ("device", "get_lost_future"), Manual { reason = "Returns Future struct" }
  ; ("device", "get_adapter_info"), Manual { reason = "Returns struct" }
    (* Queue methods - some manually implemented in adapter_module_prefix *)
  ; ("queue", "release"), Manual { reason = "Custom release logic" }
  ; ("queue", "set_label"), Manual { reason = "Custom label handling" }
  ; ("queue", "submit"), Manual { reason = "Uses array argument" }
  ; ("queue", "write_buffer"), Manual { reason = "Uses pointer + size" }
  ; ("queue", "write_texture"), Manual { reason = "Uses structs and pointer" }
  ; ("queue", "on_submitted_work_done"), Manual { reason = "Async callback" }
    (* Command encoder methods - keep only complex ones *)
  ; ( ("command_encoder", "begin_compute_pass")
    , Manual { reason = "Uses descriptor struct with arrays" } )
  ; ( ("command_encoder", "begin_render_pass")
    , Manual { reason = "Uses descriptor struct with arrays" } )
    (* Render pass encoder methods - keep only complex ones *)
  ; ( ("render_pass_encoder", "set_vertex_buffer")
    , Manual { reason = "Manual for better API" } )
  ; ( ("render_pass_encoder", "set_index_buffer")
    , Manual { reason = "Manual for better API" } )
    (* Render bundle encoder methods - keep only complex ones *)
  ; ( ("render_bundle_encoder", "set_vertex_buffer")
    , Manual { reason = "Manual for better API" } )
  ; ( ("render_bundle_encoder", "set_index_buffer")
    , Manual { reason = "Manual for better API" } )
    (* Buffer methods *)
  ; ("buffer", "map_async"), Manual { reason = "Async method, we provide sync wrapper" }
  ; ( ("buffer", "get_mapped_range")
    , Manual { reason = "Returns pointer, we have bigarray wrapper" } )
  ; ( ("buffer", "get_const_mapped_range")
    , Manual { reason = "Returns pointer, we have bigarray wrapper" } )
    (* Shader module methods *)
  ; ("shader_module", "get_compilation_info"), Manual { reason = "Async callback" }
    (* Surface methods - mostly for windowed rendering *)
  ; ("surface", "configure"), Manual { reason = "Uses struct" }
  ; ("surface", "get_capabilities"), Manual { reason = "Uses struct output with arrays" }
    (* Intentionally skipped methods *)
  ; ( ("adapter", "request_adapter_info")
    , Skipped { reason = "Deprecated, use get_info instead" } )
  ; ("device", "create_error_external_texture"), Skipped { reason = "Internal/testing" }
  ; ( ("device", "import_external_texture")
    , Skipped { reason = "Advanced external interop" } )
  ; ( ("device", "create_render_pipeline_async")
    , Skipped { reason = "Async version, use sync" } )
  ; ( ("device", "create_compute_pipeline_async")
    , Skipped { reason = "Async version, use sync" } )
  ; ("surface", "get_preferred_format"), Skipped { reason = "Deprecated" }
  ]
;;

let manual_implementations =
  List.filter_map method_config ~f:(fun (key, handling) ->
    match handling with
    | Manual _ -> Some key
    | _ -> None)
  |> Set.of_list (module Method_key)
;;

let intentionally_skipped =
  List.filter_map method_config ~f:(fun (key, handling) ->
    match handling with
    | Skipped _ -> Some key
    | _ -> None)
  |> Set.of_list (module Method_key)
;;

let get_handling ~(object_name : string) ~(method_name : string) : method_handling =
  match
    List.Assoc.find method_config ~equal:[%equal: Method_key.t] (object_name, method_name)
  with
  | Some handling -> handling
  | None -> Auto
;;

let manual_methods : Method_key.t list =
  List.filter_map method_config ~f:(fun (key, handling) ->
    match handling with
    | Manual _ -> Some key
    | _ -> None)
;;

let skipped_methods : Method_key.t list =
  List.filter_map method_config ~f:(fun (key, handling) ->
    match handling with
    | Skipped _ -> Some key
    | _ -> None)
;;

let is_accounted_for ~(object_name : string) ~(method_name : string) : bool =
  match get_handling ~object_name ~method_name with
  | Auto -> false
  | Manual _ | Skipped _ -> true
;;

let is_manual ~(object_name : string) ~(method_name : string) : bool =
  Set.mem manual_implementations (object_name, method_name)
;;

let is_skipped ~(object_name : string) ~(method_name : string) : bool =
  Set.mem intentionally_skipped (object_name, method_name)
;;

let validate_config (api : Ir.api) : unit =
  let all_methods =
    List.concat_map api.objects ~f:(fun obj ->
      List.map obj.methods ~f:(fun m -> obj.name, m.name))
    |> Set.of_list (module Method_key)
  in
  List.iter method_config ~f:(fun ((obj, meth), _handling) ->
    if not (Set.mem all_methods (obj, meth))
    then eprintf "Warning: Configured method %s.%s does not exist in API\n%!" obj meth)
;;

(** Configuration record that can be threaded through codegen functions. *)
type t =
  { method_config : (Method_key.t * method_handling) list
  ; ignore_manual_for_generation : bool
  (** When [true], all methods are generated regardless of manual/skipped status. This is
      useful for testing to see what code would be generated. *)
  }

(** Default config for production code generation - respects manual/skipped flags. *)
let default : t = { method_config; ignore_manual_for_generation = false }

(** Config for testing - generates code for all methods including manual ones. *)
let for_testing : t = { method_config; ignore_manual_for_generation = true }

(** Config for low-level bindings - only skips methods that are truly problematic at the C
    level. Most "manual" methods in the high-level API still need low-level bindings. *)
let for_low_level : t =
  { method_config =
      [ (* Only adapter.get_info is manually implemented at the low level *)
        ( ("adapter", "get_info")
        , Manual { reason = "Uses special struct return, manually implemented" } )
      ]
  ; ignore_manual_for_generation = false
  }
;;

(** Get manual implementations set from a config. *)
let manual_implementations_of (config : t)
  : (string * string, Method_key.comparator_witness) Set.t
  =
  List.filter_map config.method_config ~f:(fun (key, handling) ->
    match handling with
    | Manual _ -> Some key
    | _ -> None)
  |> Set.of_list (module Method_key)
;;

(** Get intentionally skipped methods set from a config. *)
let intentionally_skipped_of (config : t)
  : (string * string, Method_key.comparator_witness) Set.t
  =
  List.filter_map config.method_config ~f:(fun (key, handling) ->
    match handling with
    | Skipped _ -> Some key
    | _ -> None)
  |> Set.of_list (module Method_key)
;;

(** Check if a method is manually implemented according to the config. Returns [false] if
    [config.ignore_manual_for_generation] is [true]. *)
let is_manual_with_config (config : t) ~(object_name : string) ~(method_name : string)
  : bool
  =
  if config.ignore_manual_for_generation
  then false
  else Set.mem (manual_implementations_of config) (object_name, method_name)
;;

(** Check if a method is skipped according to the config. Returns [false] if
    [config.ignore_manual_for_generation] is [true]. *)
let is_skipped_with_config (config : t) ~(object_name : string) ~(method_name : string)
  : bool
  =
  if config.ignore_manual_for_generation
  then false
  else Set.mem (intentionally_skipped_of config) (object_name, method_name)
;;

(** Check if a method is accounted for (either manual or skipped) according to the config.
    Returns [false] if [config.ignore_manual_for_generation] is [true]. *)
let is_accounted_for_with_config
  (config : t)
  ~(object_name : string)
  ~(method_name : string)
  : bool
  =
  if config.ignore_manual_for_generation
  then false
  else is_accounted_for ~object_name ~method_name
;;
