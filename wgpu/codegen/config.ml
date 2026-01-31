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
  [ ("instance", "create_surface"), Manual { reason = "Complex struct handling" }
  ; ( ("instance", "get_WGSL_language_features")
    , Manual { reason = "Uses struct output parameter" } )
  ; ("instance", "wait_any"), Manual { reason = "Uses struct input parameter" }
  ; ( ("adapter", "get_info")
    , Manual { reason = "Uses special struct return, manually implemented" } )
  ; ("adapter", "get_features"), Manual { reason = "Output struct with array member" }
  ; ("device", "get_features"), Manual { reason = "Output struct with array member" }
  ; ("device", "create_shader_module"), Manual { reason = "Uses chained WGSL struct" }
  ; ("device", "create_render_pipeline"), Manual { reason = "Deeply nested descriptors" }
  ; ("device", "get_adapter_info"), Manual { reason = "Returns struct" }
  ; ("queue", "write_buffer"), Manual { reason = "Uses pointer + size" }
  ; ( ("queue", "write_texture")
    , Manual { reason = "Uses pointer + size, bigarray wrapper" } )
  ; ( ("command_encoder", "begin_compute_pass")
    , Manual { reason = "Uses descriptor struct with arrays" } )
  ; ( ("command_encoder", "begin_render_pass")
    , Manual { reason = "Uses descriptor struct with arrays" } )
  ; ( ("surface", "get_current_texture")
    , Manual { reason = "Manually implemented with custom surface_texture type" } )
  ; ( ("surface", "get_capabilities")
    , Skipped { reason = "Low-level array getters not yet implemented" } )
    (* Intentionally skipped methods, usually for async reasons *)
  ; ("shader_module", "get_compilation_info"), Manual { reason = "Async callback" }
  ; ("buffer", "map_async"), Manual { reason = "Async method, we provide sync wrapper" }
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
  ; ("device", "pop_error_scope"), Manual { reason = "Async callback" }
  ; ("device", "get_lost_future"), Manual { reason = "Returns Future struct" }
  ; ("device", "poll"), Manual { reason = "Custom polling logic" }
  ; ( ("adapter", "request_device")
    , Manual { reason = "Async method, we provide sync wrapper" } )
  ; ( ("instance", "request_adapter")
    , Manual { reason = "Async method, we provide sync wrapper" } )
  ; ("queue", "on_submitted_work_done"), Manual { reason = "Async callback" }
  ]
;;

(** Configuration record that can be threaded through codegen functions. *)
type t = { method_config : (Method_key.t * method_handling) list }

(** Default config for production code generation - respects manual/skipped flags. *)
let default : t = { method_config }

(** Config for testing - generates code for all methods including manual ones. *)
let for_testing : t = { method_config = [] }

(** Config for low-level bindings - only skips methods that are truly problematic at the C
    level. Most "manual" methods in the high-level API still need low-level bindings. *)
let for_low_level : t =
  { method_config =
      [ (* Only adapter.get_info is manually implemented at the low level *)
        ( ("adapter", "get_info")
        , Manual { reason = "Uses special struct return, manually implemented" } )
      ]
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
  Set.mem (manual_implementations_of config) (object_name, method_name)
;;

(** Check if a method is skipped according to the config. Returns [false] if
    [config.ignore_manual_for_generation] is [true]. *)
let is_skipped_with_config (config : t) ~(object_name : string) ~(method_name : string)
  : bool
  =
  Set.mem (intentionally_skipped_of config) (object_name, method_name)
;;

(** Check if a method is accounted for (either manual or skipped) according to the config.
    Returns [false] if [config.ignore_manual_for_generation] is [true]. *)
let is_accounted_for_with_config
  (config : t)
  ~(object_name : string)
  ~(method_name : string)
  : bool
  =
  is_skipped_with_config config ~object_name ~method_name
  || is_manual_with_config config ~object_name ~method_name
;;
