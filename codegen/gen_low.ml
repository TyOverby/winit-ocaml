open! Core

(** Generate low-level C stubs and OCaml external bindings *)

(** Convert a snake_case name to PascalCase *)
let to_pascal_case (s : string) : string =
  (* Double underscores become single underscores in C names *)
  let s = String.substr_replace_all s ~pattern:"__" ~with_:"_UNDERSCORE_" in
  let parts = String.split s ~on:'_' in
  let parts =
    List.map parts ~f:(fun p ->
      if String.equal p "UNDERSCORE" then "_" else String.capitalize p)
  in
  String.concat parts
;;

(** Convert a snake_case name to camelCase *)
let to_camel_case (s : string) : string =
  match String.split s ~on:'_' with
  | [] -> ""
  | first :: rest -> first ^ String.concat (List.map rest ~f:String.capitalize)
;;

(** Get the C type name for a WGPU type *)
let c_type_name (name : string) : string = "WGPU" ^ to_pascal_case name

(** Get the C function name for a method *)
let c_method_name (obj_name : string) (method_name : string) : string =
  "wgpu" ^ to_pascal_case obj_name ^ to_pascal_case method_name
;;

(** Get the C function name for a standalone function *)
let c_function_name (name : string) : string = "wgpu" ^ to_pascal_case name

(** Get the OCaml module name for a type *)
let ocaml_module_name (name : string) : string =
  String.capitalize name
  |> String.substr_replace_all ~pattern:"_" ~with_:" "
  |> fun s ->
  String.split s ~on:' ' |> List.map ~f:String.capitalize |> String.concat ~sep:"_"
;;

(** Convert C name conventions (e.g., discrete_GPU -> Discrete_gpu) *)
let normalize_enum_entry_name (name : string) : string =
  (* Handle special cases like GPU, CPU, ID *)
  let s = String.lowercase name in
  let s = String.capitalize s in
  (* OCaml identifiers can't start with a digit, prefix with underscore *)
  if String.length s > 0 && Char.is_digit (String.get s 0) then "N" ^ s else s
;;

(** Generate C code for enum constants *)
let gen_c_enum_constants (enum : Ir.enum) : string =
  let c_name = c_type_name enum.name in
  let entries =
    List.map enum.entries ~f:(fun entry ->
      let c_entry_name = c_type_name enum.name ^ "_" ^ to_pascal_case entry.name in
      sprintf
        "CAMLprim value caml_wgpu_%s_%s(value unit) {\n\
        \  CAMLparam1(unit);\n\
        \  CAMLreturn(Val_int(%s));\n\
         }"
        (String.lowercase enum.name)
        (String.lowercase entry.name)
        c_entry_name)
  in
  sprintf "/* Enum: %s */\n%s\n" c_name (String.concat ~sep:"\n\n" entries)
;;

(** Generate OCaml code for an enum type *)
let gen_ml_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants =
    List.map enum.entries ~f:(fun entry ->
      sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n"
  in
  let to_int_cases =
    List.map enum.entries ~f:(fun entry ->
      sprintf
        "    | %s -> %s_%s ()"
        (normalize_enum_entry_name entry.name)
        (String.lowercase enum.name)
        (String.lowercase entry.name))
    |> String.concat ~sep:"\n"
  in
  let externals =
    List.map enum.entries ~f:(fun entry ->
      sprintf
        "external %s_%s : unit -> int = \"caml_wgpu_%s_%s\""
        (String.lowercase enum.name)
        (String.lowercase entry.name)
        (String.lowercase enum.name)
        (String.lowercase entry.name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    "module %s = struct\n  type t =\n%s\n\n%s\n\n  let to_int = function\n%s\nend\n"
    module_name
    variants
    externals
    to_int_cases
;;

(** Generate MLI for an enum type *)
let gen_mli_enum (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants =
    List.map enum.entries ~f:(fun entry ->
      sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    "module %s : sig\n  type t =\n%s\n\n  val to_int : t -> int\nend\n"
    module_name
    variants
;;

(** Generate C code for bitflag constants *)
let gen_c_bitflag_constants (bitflag : Ir.bitflag) : string =
  let entries =
    List.map bitflag.entries ~f:(fun entry ->
      let c_entry_name = c_type_name bitflag.name ^ "_" ^ to_pascal_case entry.name in
      sprintf
        "CAMLprim value caml_wgpu_%s_%s(value unit) {\n\
        \  CAMLparam1(unit);\n\
        \  CAMLreturn(Val_int(%s));\n\
         }"
        (String.lowercase bitflag.name)
        (String.lowercase entry.name)
        c_entry_name)
  in
  sprintf
    "/* Bitflag: %s */\n%s\n"
    (c_type_name bitflag.name)
    (String.concat ~sep:"\n\n" entries)
;;

(** Generate OCaml code for a bitflag type *)
let gen_ml_bitflag (bitflag : Ir.bitflag) : string =
  let module_name = ocaml_module_name bitflag.name in
  let variants =
    List.map bitflag.entries ~f:(fun entry ->
      sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n"
  in
  let to_int_cases =
    List.map bitflag.entries ~f:(fun entry ->
      sprintf
        "    | %s -> %s_%s ()"
        (normalize_enum_entry_name entry.name)
        (String.lowercase bitflag.name)
        (String.lowercase entry.name))
    |> String.concat ~sep:"\n"
  in
  let externals =
    List.map bitflag.entries ~f:(fun entry ->
      sprintf
        "external %s_%s : unit -> int = \"caml_wgpu_%s_%s\""
        (String.lowercase bitflag.name)
        (String.lowercase entry.name)
        (String.lowercase bitflag.name)
        (String.lowercase entry.name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    "module %s = struct\n\
    \  type t =\n\
     %s\n\n\
     %s\n\n\
    \  let to_int = function\n\
     %s\n\n\
    \  let list_to_int flags =\n\
    \    List.fold_left (fun acc f -> acc lor to_int f) 0 flags\n\
     end\n"
    module_name
    variants
    externals
    to_int_cases
;;

(** Generate MLI for a bitflag type *)
let gen_mli_bitflag (bitflag : Ir.bitflag) : string =
  let module_name = ocaml_module_name bitflag.name in
  let variants =
    List.map bitflag.entries ~f:(fun entry ->
      sprintf "  | %s" (normalize_enum_entry_name entry.name))
    |> String.concat ~sep:"\n"
  in
  sprintf
    "module %s : sig\n\
    \  type t =\n\
     %s\n\n\
    \  val to_int : t -> int\n\
    \  val list_to_int : t list -> int\n\
     end\n"
    module_name
    variants
;;

(** Generate C code for object handle types *)
let gen_c_object_stubs (obj : Ir.object_) : string =
  let c_type = c_type_name obj.name in
  (* Generate release function *)
  let release =
    sprintf
      "CAMLprim value caml_wgpu_%s_release(value handle) {\n\
      \  CAMLparam1(handle);\n\
      \  %s obj = (%s)Nativeint_val(handle);\n\
      \  if (obj != NULL) {\n\
      \    %sRelease(obj);\n\
      \  }\n\
      \  CAMLreturn(Val_unit);\n\
       }"
      (String.lowercase obj.name)
      c_type
      c_type
      (c_function_name obj.name)
  in
  sprintf "/* Object: %s */\n%s\n" c_type release
;;

(** Generate OCaml code for an object type *)
let gen_ml_object (obj : Ir.object_) : string =
  sprintf
    "type %s = nativeint\n\nexternal %s_release : %s -> unit = \"caml_wgpu_%s_release\"\n"
    obj.name
    obj.name
    obj.name
    (String.lowercase obj.name)
;;

(** Generate MLI for an object type *)
let gen_mli_object (obj : Ir.object_) : string =
  let doc = String.strip obj.doc in
  let doc_comment =
    if String.is_empty doc || String.equal doc "TODO"
    then ""
    else sprintf " (** %s *)" doc
  in
  sprintf
    "type %s = nativeint%s\n\nval %s_release : %s -> unit\n"
    obj.name
    doc_comment
    obj.name
    obj.name
;;

(** Generate C stubs for standalone functions *)
let gen_c_function_stubs (func : Ir.function_) : string =
  let c_name = c_function_name func.name in
  match func.name with
  | "create_instance" ->
    sprintf
      "CAMLprim value caml_wgpu_create_instance(value unit) {\n\
      \  CAMLparam1(unit);\n\
      \  WGPUInstanceDescriptor desc = {\n\
      \    .nextInChain = NULL,\n\
      \  };\n\
      \  WGPUInstance instance = wgpuCreateInstance(&desc);\n\
      \  CAMLreturn(caml_copy_nativeint((intnat)instance));\n\
       }"
  | _ -> sprintf "/* TODO: %s */\n" c_name
;;

(** Generate additional helper functions for sync wrappers *)
let gen_c_sync_helpers () : string =
  {|
/* Synchronous adapter request helper */
static void handle_request_adapter_sync(WGPURequestAdapterStatus status,
                                        WGPUAdapter adapter,
                                        WGPUStringView message,
                                        void *userdata1, void *userdata2) {
  (void)status;
  (void)message;
  (void)userdata2;
  *(WGPUAdapter *)userdata1 = adapter;
}

CAMLprim value caml_wgpu_instance_request_adapter_sync(value instance_val) {
  CAMLparam1(instance_val);
  WGPUInstance instance = (WGPUInstance)Nativeint_val(instance_val);
  WGPUAdapter adapter = NULL;

  WGPURequestAdapterCallbackInfo callback_info = {
    .callback = handle_request_adapter_sync,
    .userdata1 = &adapter,
    .userdata2 = NULL,
  };

  wgpuInstanceRequestAdapter(instance, NULL, callback_info);

  CAMLreturn(caml_copy_nativeint((intnat)adapter));
}

/* Synchronous device request helper */
static void handle_request_device_sync(WGPURequestDeviceStatus status,
                                       WGPUDevice device,
                                       WGPUStringView message,
                                       void *userdata1, void *userdata2) {
  (void)status;
  (void)message;
  (void)userdata2;
  *(WGPUDevice *)userdata1 = device;
}

CAMLprim value caml_wgpu_adapter_request_device_sync(value adapter_val) {
  CAMLparam1(adapter_val);
  WGPUAdapter adapter = (WGPUAdapter)Nativeint_val(adapter_val);
  WGPUDevice device = NULL;

  WGPURequestDeviceCallbackInfo callback_info = {
    .callback = handle_request_device_sync,
    .userdata1 = &device,
    .userdata2 = NULL,
  };

  wgpuAdapterRequestDevice(adapter, NULL, callback_info);

  CAMLreturn(caml_copy_nativeint((intnat)device));
}

/* Get device queue */
CAMLprim value caml_wgpu_device_get_queue(value device_val) {
  CAMLparam1(device_val);
  WGPUDevice device = (WGPUDevice)Nativeint_val(device_val);
  WGPUQueue queue = wgpuDeviceGetQueue(device);
  CAMLreturn(caml_copy_nativeint((intnat)queue));
}

/* Get adapter info */
CAMLprim value caml_wgpu_adapter_get_info(value adapter_val) {
  CAMLparam1(adapter_val);
  CAMLlocal1(result);

  WGPUAdapter adapter = (WGPUAdapter)Nativeint_val(adapter_val);
  WGPUAdapterInfo info = {0};
  wgpuAdapterGetInfo(adapter, &info);

  /* Return as a tuple: (vendor, architecture, device, description, backend_type, adapter_type) */
  result = caml_alloc_tuple(6);
  Store_field(result, 0, caml_copy_string(info.vendor.data ? info.vendor.data : ""));
  Store_field(result, 1, caml_copy_string(info.architecture.data ? info.architecture.data : ""));
  Store_field(result, 2, caml_copy_string(info.device.data ? info.device.data : ""));
  Store_field(result, 3, caml_copy_string(info.description.data ? info.description.data : ""));
  Store_field(result, 4, Val_int(info.backendType));
  Store_field(result, 5, Val_int(info.adapterType));

  wgpuAdapterInfoFreeMembers(info);

  CAMLreturn(result);
}
|}
;;

(** Generate all C stubs *)
let gen_c_stubs (api : Ir.api) : string =
  let header =
    {|/* Generated by gen_bindings - low-level C stubs */
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>

#include "webgpu.h"
#include "wgpu.h"

|}
  in
  let enum_stubs =
    List.map api.enums ~f:gen_c_enum_constants |> String.concat ~sep:"\n"
  in
  let bitflag_stubs =
    List.map api.bitflags ~f:gen_c_bitflag_constants |> String.concat ~sep:"\n"
  in
  let object_stubs =
    List.map api.objects ~f:gen_c_object_stubs |> String.concat ~sep:"\n"
  in
  let function_stubs =
    List.map api.functions ~f:gen_c_function_stubs |> String.concat ~sep:"\n"
  in
  let sync_helpers = gen_c_sync_helpers () in
  String.concat [ header; enum_stubs; bitflag_stubs; object_stubs; function_stubs; sync_helpers ]
;;

(** Generate all OCaml bindings *)
let gen_ml (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - low-level OCaml bindings *)\n\n" in
  let enums = List.map api.enums ~f:gen_ml_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_ml_bitflag |> String.concat ~sep:"\n" in
  let objects = List.map api.objects ~f:gen_ml_object |> String.concat ~sep:"\n" in
  let functions =
    {|external create_instance : unit -> instance = "caml_wgpu_create_instance"

external instance_request_adapter_sync : instance -> adapter
  = "caml_wgpu_instance_request_adapter_sync"

external adapter_request_device_sync : adapter -> device
  = "caml_wgpu_adapter_request_device_sync"

external device_get_queue : device -> queue = "caml_wgpu_device_get_queue"

type adapter_info =
  { vendor : string
  ; architecture : string
  ; device : string
  ; description : string
  ; backend_type : int
  ; adapter_type : int
  }

external adapter_get_info_raw :
  adapter -> string * string * string * string * int * int
  = "caml_wgpu_adapter_get_info"

let adapter_get_info adapter =
  let vendor, architecture, device, description, backend_type, adapter_type =
    adapter_get_info_raw adapter
  in
  { vendor; architecture; device; description; backend_type; adapter_type }
|}
  in
  String.concat [ header; enums; bitflags; objects; functions ]
;;

(** Generate all OCaml interface *)
let gen_mli (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - low-level OCaml interface *)\n\n" in
  let enums = List.map api.enums ~f:gen_mli_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_mli_bitflag |> String.concat ~sep:"\n" in
  let objects = List.map api.objects ~f:gen_mli_object |> String.concat ~sep:"\n" in
  let functions =
    {|val create_instance : unit -> instance

val instance_request_adapter_sync : instance -> adapter

val adapter_request_device_sync : adapter -> device

val device_get_queue : device -> queue

type adapter_info =
  { vendor : string
  ; architecture : string
  ; device : string
  ; description : string
  ; backend_type : int
  ; adapter_type : int
  }

val adapter_get_info : adapter -> adapter_info
|}
  in
  String.concat [ header; enums; bitflags; objects; functions ]
;;
