(* Code generator for wgpu-native OCaml bindings
   Reads webgpu.yml and generates ctypes bindings *)

open Printf

(* Helper to convert snake_case to PascalCase *)
let pascal_case s =
  let parts = String.split_on_char '_' s in
  let capitalize_first s =
    if String.length s = 0
    then s
    else String.uppercase_ascii (String.sub s 0 1) ^ String.sub s 1 (String.length s - 1)
  in
  String.concat "" (List.map capitalize_first parts)
;;

(* Helper to convert to snake_case (OCaml convention) *)
let snake_case s = String.lowercase_ascii s

(* Reserved OCaml keywords that need escaping *)
let is_keyword = function
  | "type"
  | "module"
  | "end"
  | "in"
  | "let"
  | "and"
  | "or"
  | "not"
  | "if"
  | "then"
  | "else"
  | "match"
  | "with"
  | "function"
  | "fun"
  | "true"
  | "false"
  | "mod"
  | "land"
  | "lor"
  | "lxor"
  | "lsl"
  | "lsr"
  | "asr"
  | "val"
  | "method"
  | "object"
  | "class"
  | "inherit"
  | "open"
  | "include"
  | "sig"
  | "struct"
  | "begin"
  | "exception"
  | "try"
  | "raise"
  | "assert"
  | "lazy"
  | "while"
  | "for"
  | "do"
  | "done"
  | "to"
  | "downto"
  | "mutable"
  | "rec"
  | "as"
  | "of"
  | "constraint"
  | "private"
  | "virtual"
  | "new"
  | "external" -> true
  | _ -> false
;;

let escape_keyword s =
  if is_keyword s
  then s ^ "_"
  else if String.length s > 0 && s.[0] >= '0' && s.[0] <= '9'
  then "_" ^ s (* Prefix with underscore if starts with digit *)
  else s
;;

let yaml_to_string_opt = function
  | `String s -> Some s
  | _ -> None
;;

let yaml_to_int = function
  | `Float f -> int_of_float f
  | `String s ->
    (try
       if String.length s > 2 && String.sub s 0 2 = "0x"
       then int_of_string s
       else int_of_string s
     with
     | _ -> 0)
  | _ -> 0
;;

let yaml_to_bool = function
  | `Bool b -> b
  | _ -> false
;;

let yaml_get key = function
  | `O fields -> List.assoc_opt key fields
  | _ -> None
;;

let yaml_get_list key = function
  | `O fields ->
    (match List.assoc_opt key fields with
     | Some (`A lst) -> lst
     | _ -> [])
  | _ -> []
;;

let yaml_get_string key obj = Option.bind (yaml_get key obj) yaml_to_string_opt

let yaml_get_bool key obj =
  Option.map yaml_to_bool (yaml_get key obj) |> Option.value ~default:false
;;

(* Parse type string from YAML to determine ctypes type
   use_void_for_structs: if true, use (ptr void) for struct references to avoid ordering issues *)
let rec parse_type_string ?(use_void_for_structs = false) s =
  (* Handle common types *)
  match s with
  | "bool" -> "uint32_t" (* WGPUBool is uint32_t *)
  | "uint32" -> "uint32_t"
  | "uint64" -> "uint64_t"
  | "int32" -> "int32_t"
  | "int64" -> "int64_t"
  | "usize" -> "size_t"
  | "float32" -> "float"
  | "float64" -> "double"
  | "c_void" -> "void"
  | "string_with_default_empty" -> "String_view.t"
  | "out_string" -> "String_view.t"
  | "nullable_string" -> "String_view.t"
  | _ when String.length s > 5 && String.sub s 0 5 = "enum." ->
    let name = String.sub s 5 (String.length s - 5) in
    sprintf "%s.t" (pascal_case name)
  | _ when String.length s > 8 && String.sub s 0 8 = "bitflag." ->
    let name = String.sub s 8 (String.length s - 8) in
    sprintf "%s.t" (pascal_case name)
  | _ when String.length s > 7 && String.sub s 0 7 = "struct." ->
    if use_void_for_structs
    then "(ptr void)"
    else (
      let name = String.sub s 7 (String.length s - 7) in
      sprintf "%s.t" (pascal_case name))
  | _ when String.length s > 7 && String.sub s 0 7 = "object." ->
    let name = String.sub s 7 (String.length s - 7) in
    sprintf "%s.t" (pascal_case name)
  | _ when String.length s > 9 && String.sub s 0 9 = "callback." ->
    "(ptr void)" (* callbacks are function pointers *)
  | _ when String.length s > 6 && String.sub s 0 6 = "array<" ->
    let inner = String.sub s 6 (String.length s - 7) in
    sprintf "(ptr %s)" (parse_type_string ~use_void_for_structs inner)
  | _ -> sprintf "(ptr void) (* unknown: %s *)" s
;;

(* Check if a type string represents an object handle (already a pointer type) *)
let is_object_type type_str =
  String.length type_str > 7 && String.sub type_str 0 7 = "object."
;;

(* Get the ctypes type for a member, considering pointer/optional flags
   For struct fields, we always use void* for other struct references to avoid forward declaration issues *)
let member_ctypes_type member =
  let type_str = yaml_get_string "type" member |> Option.value ~default:"c_void" in
  let is_pointer =
    match yaml_get_string "pointer" member with
    | Some "immutable" | Some "mutable" -> true
    | _ -> false
  in
  let is_optional = yaml_get_bool "optional" member in
  (* Object handles are already pointers, so don't add another ptr level for optional *)
  let is_obj = is_object_type type_str in
  (* For struct pointers, use void* to avoid forward declaration issues.
     For embedded structs (no pointer), use the actual type - topo sort ensures availability. *)
  let is_struct = String.length type_str > 7 && String.sub type_str 0 7 = "struct." in
  let use_void_for_structs = is_pointer || is_optional in
  let base_type =
    parse_type_string ~use_void_for_structs:(use_void_for_structs && is_struct) type_str
  in
  if is_pointer || (is_optional && not is_obj)
  then sprintf "(ptr %s)" base_type
  else base_type
;;

(* Generate enum module *)
let gen_enum oc (enum : Yaml.value) =
  let name = yaml_get_string "name" enum |> Option.value ~default:"unknown" in
  let entries = yaml_get_list "entries" enum in
  let module_name = pascal_case name in
  fprintf oc "module %s = struct\n" module_name;
  fprintf oc "  type t = Unsigned.UInt32.t\n";
  fprintf oc "  let t = uint32_t\n\n";
  let idx = ref 0 in
  List.iter
    (fun entry ->
      match entry with
      | `Null -> incr idx
      | `O _ ->
        let entry_name =
          yaml_get_string "name" entry |> Option.value ~default:"unknown"
        in
        let ocaml_name = escape_keyword (snake_case entry_name) in
        let value =
          match yaml_get "value" entry with
          | Some v -> yaml_to_int v
          | None ->
            let v = !idx in
            incr idx;
            v
        in
        fprintf oc "  let %s = Unsigned.UInt32.of_int 0x%04X\n" ocaml_name value
      | _ -> ())
    entries;
  fprintf oc "end\n\n"
;;

(* Generate bitflag module *)
let gen_bitflag oc (bitflag : Yaml.value) =
  let name = yaml_get_string "name" bitflag |> Option.value ~default:"unknown" in
  let entries = yaml_get_list "entries" bitflag in
  let module_name = pascal_case name in
  fprintf oc "module %s = struct\n" module_name;
  fprintf oc "  type t = Unsigned.UInt32.t\n";
  fprintf oc "  let t = uint32_t\n\n";
  let bit = ref 0 in
  List.iter
    (fun entry ->
      match entry with
      | `O _ ->
        let entry_name =
          yaml_get_string "name" entry |> Option.value ~default:"unknown"
        in
        let ocaml_name = escape_keyword (snake_case entry_name) in
        let value =
          if ocaml_name = "none"
          then 0
          else (
            let v = 1 lsl !bit in
            incr bit;
            v)
        in
        fprintf oc "  let %s = Unsigned.UInt32.of_int 0x%04X\n" ocaml_name value
      | _ -> ())
    entries;
  fprintf oc "\n  let ( + ) = Unsigned.UInt32.logor\n";
  fprintf oc "end\n\n"
;;

(* Generate object handle module *)
let gen_object_handle oc (obj : Yaml.value) =
  let name = yaml_get_string "name" obj |> Option.value ~default:"unknown" in
  let module_name = pascal_case name in
  fprintf oc "module %s = struct\n" module_name;
  fprintf oc "  type t = unit ptr\n";
  fprintf oc "  let t : t typ = ptr void\n";
  fprintf oc "  let t_opt : t option typ = ptr_opt void\n";
  fprintf oc "end\n\n"
;;

(* Helper to convert snake_case to camelCase for C field names *)
let to_camel_case member_name =
  let parts = String.split_on_char '_' member_name in
  match parts with
  | [] -> member_name
  | first :: rest ->
    first
    ^ String.concat
        ""
        (List.map
           (fun s ->
             if String.length s > 0
             then
               String.uppercase_ascii (String.sub s 0 1)
               ^ String.sub s 1 (String.length s - 1)
             else s)
           rest)
;;

(* Extract struct name from type string if it's a struct type *)
let extract_struct_dep type_str =
  if String.length type_str > 7 && String.sub type_str 0 7 = "struct."
  then Some (String.sub type_str 7 (String.length type_str - 7))
  else if String.length type_str > 6 && String.sub type_str 0 6 = "array<"
  then (
    let inner = String.sub type_str 6 (String.length type_str - 7) in
    if String.length inner > 7 && String.sub inner 0 7 = "struct."
    then Some (String.sub inner 7 (String.length inner - 7))
    else None)
  else None
;;

(* Check if a member is an embedded struct (not a pointer) *)
let is_embedded_struct member =
  let type_str = yaml_get_string "type" member |> Option.value ~default:"" in
  let is_struct = String.length type_str > 7 && String.sub type_str 0 7 = "struct." in
  let is_pointer =
    match yaml_get_string "pointer" member with
    | Some "immutable" | Some "mutable" -> true
    | _ -> false
  in
  is_struct && not is_pointer
;;

(* Get list of embedded struct dependencies for a struct *)
let get_struct_deps st =
  let members = yaml_get_list "members" st in
  List.filter_map
    (fun member ->
      match member with
      | `O _ when is_embedded_struct member ->
        let type_str = yaml_get_string "type" member |> Option.value ~default:"" in
        extract_struct_dep type_str
      | _ -> None)
    members
;;

(* Topological sort of structs based on embedded struct dependencies *)
let topo_sort_structs structs =
  (* Build a map from struct name to struct YAML *)
  let struct_map =
    List.fold_left
      (fun acc st ->
        let name = yaml_get_string "name" st |> Option.value ~default:"unknown" in
        (name, st) :: acc)
      []
      structs
  in
  (* Track visited and sorted *)
  let visited = Hashtbl.create 64 in
  let sorted = ref [] in
  let rec visit name =
    if Hashtbl.mem visited name
    then ()
    else (
      Hashtbl.add visited name true;
      match List.assoc_opt name struct_map with
      | Some st ->
        let deps = get_struct_deps st in
        List.iter visit deps;
        sorted := st :: !sorted
      | None -> ())
  in
  List.iter
    (fun st ->
      let name = yaml_get_string "name" st |> Option.value ~default:"unknown" in
      visit name)
    structs;
  List.rev !sorted
;;

(* Generate struct with fields *)
let gen_struct oc (st : Yaml.value) =
  let name = yaml_get_string "name" st |> Option.value ~default:"unknown" in
  let members = yaml_get_list "members" st in
  let module_name = pascal_case name in
  let struct_type = yaml_get_string "type" st |> Option.value ~default:"standalone" in
  fprintf oc "module %s = struct\n" module_name;
  fprintf oc "  type t\n\n";
  fprintf oc "  let t : t structure typ = structure \"WGPU%s\"\n" (pascal_case name);
  (* For base_in/base_out structs, add nextInChain field *)
  if struct_type = "base_in" || struct_type = "base_out"
  then fprintf oc "  let next_in_chain = field t \"nextInChain\" (ptr void)\n";
  (* For extension_in/extension_out structs, add chain field (embedded Chained_struct) *)
  if struct_type = "extension_in" || struct_type = "extension_out"
  then fprintf oc "  let chain = field t \"chain\" Chained_struct.t\n";
  (* Generate fields for members *)
  List.iter
    (fun member ->
      match member with
      | `O _ ->
        let member_name =
          yaml_get_string "name" member |> Option.value ~default:"unknown"
        in
        let type_str = yaml_get_string "type" member |> Option.value ~default:"c_void" in
        let ocaml_field_name = escape_keyword (snake_case member_name) in
        let c_field_name = to_camel_case member_name in
        (* Check if this is an array type - if so, emit count field first *)
        if String.length type_str > 6 && String.sub type_str 0 6 = "array<"
        then (
          (* Emit count field *)
          let count_ocaml_name = ocaml_field_name ^ "_count" in
          let count_c_name = c_field_name ^ "Count" in
          fprintf oc "  let %s = field t \"%s\" size_t\n" count_ocaml_name count_c_name;
          (* Emit pointer field *)
          let inner = String.sub type_str 6 (String.length type_str - 7) in
          let ptr_type =
            sprintf "(ptr %s)" (parse_type_string ~use_void_for_structs:true inner)
          in
          fprintf
            oc
            "  let %s = field t \"%s\" %s\n"
            ocaml_field_name
            c_field_name
            ptr_type)
        else (
          let ctypes_type = member_ctypes_type member in
          fprintf
            oc
            "  let %s = field t \"%s\" %s\n"
            ocaml_field_name
            c_field_name
            ctypes_type)
      | _ -> ())
    members;
  fprintf oc "  let () = seal t\n";
  fprintf oc "end\n\n"
;;

(* Generate callback info struct *)
let gen_callback_info oc (cb : Yaml.value) =
  let name = yaml_get_string "name" cb |> Option.value ~default:"unknown" in
  let module_name = pascal_case name ^ "CallbackInfo" in
  fprintf oc "module %s = struct\n" module_name;
  fprintf oc "  type t\n";
  fprintf
    oc
    "  let t : t structure typ = structure \"WGPU%sCallbackInfo\"\n"
    (pascal_case name);
  fprintf oc "  let next_in_chain = field t \"nextInChain\" (ptr void)\n";
  fprintf oc "  let mode = field t \"mode\" uint32_t\n";
  fprintf oc "  let callback = field t \"callback\" (ptr void)\n";
  fprintf oc "  let userdata1 = field t \"userdata1\" (ptr void)\n";
  fprintf oc "  let userdata2 = field t \"userdata2\" (ptr void)\n";
  fprintf oc "  let () = seal t\n";
  fprintf oc "end\n\n"
;;

(* Generate function binding *)
let gen_function oc obj_name (meth : Yaml.value) =
  let meth_name = yaml_get_string "name" meth |> Option.value ~default:"unknown" in
  let args = yaml_get_list "args" meth in
  let returns = yaml_get "returns" meth in
  let has_callback = Option.is_some (yaml_get_string "callback" meth) in
  (* Build function name *)
  let c_func_name =
    if obj_name = ""
    then sprintf "wgpu%s" (pascal_case meth_name)
    else sprintf "wgpu%s%s" (pascal_case obj_name) (pascal_case meth_name)
  in
  let ocaml_func_name =
    if obj_name = ""
    then snake_case meth_name
    else sprintf "%s_%s" (snake_case obj_name) (snake_case meth_name)
  in
  (* Build argument types *)
  let arg_types = Buffer.create 64 in
  (* First arg is the object itself (if method) *)
  if obj_name <> ""
  then Buffer.add_string arg_types (sprintf "%s.t @-> " (pascal_case obj_name));
  (* Add regular arguments *)
  List.iter
    (fun arg ->
      match arg with
      | `O _ ->
        let arg_type = yaml_get_string "type" arg |> Option.value ~default:"c_void" in
        let is_pointer =
          match yaml_get_string "pointer" arg with
          | Some "immutable" -> true
          | Some "mutable" -> true
          | _ -> false
        in
        let is_optional = yaml_get_bool "optional" arg in
        (* Check if this is an array type - if so, emit count then pointer *)
        if String.length arg_type > 6 && String.sub arg_type 0 6 = "array<"
        then (
          (* Emit count arg (size_t) *)
          Buffer.add_string arg_types "size_t @-> ";
          (* Emit pointer arg *)
          let inner = String.sub arg_type 6 (String.length arg_type - 7) in
          Buffer.add_string arg_types (sprintf "(ptr %s) @-> " (parse_type_string inner)))
        else (
          (* Object handles are already pointers, so don't add another ptr level for optional *)
          let is_obj = is_object_type arg_type in
          let ctypes =
            if is_pointer || (is_optional && not is_obj)
            then sprintf "(ptr %s)" (parse_type_string arg_type)
            else parse_type_string arg_type
          in
          Buffer.add_string arg_types (sprintf "%s @-> " ctypes))
      | _ -> ())
    args;
  (* Add callback info if present *)
  if has_callback
  then (
    let cb_name = yaml_get_string "callback" meth |> Option.value ~default:"unknown" in
    let cb_name = String.sub cb_name 9 (String.length cb_name - 9) in
    (* Remove "callback." prefix *)
    Buffer.add_string arg_types (sprintf "%sCallbackInfo.t @-> " (pascal_case cb_name)));
  (* Return type *)
  let return_type =
    match returns with
    | Some ret ->
      let ret_type = yaml_get_string "type" ret |> Option.value ~default:"c_void" in
      let is_pointer =
        match yaml_get_string "pointer" ret with
        | Some "immutable" | Some "mutable" -> true
        | _ -> false
      in
      let base = parse_type_string ret_type in
      if is_pointer then sprintf "(ptr %s)" base else base
    | None -> "void"
  in
  fprintf
    oc
    "let %s =\n  foreign \"%s\"\n    (%sreturning %s)\n;;\n\n"
    (escape_keyword ocaml_func_name)
    c_func_name
    (Buffer.contents arg_types)
    return_type
;;

(* Main generation *)
let generate_bindings yaml_path output_path =
  let ic = open_in yaml_path in
  let content = really_input_string ic (in_channel_length ic) in
  close_in ic;
  let yaml =
    match Yaml.of_string content with
    | Ok y -> y
    | Error (`Msg e) -> failwith (sprintf "YAML parse error: %s" e)
  in
  let oc = open_out output_path in
  (* Header *)
  fprintf oc "(* Auto-generated wgpu-native bindings from webgpu.yml *)\n";
  fprintf oc "(* Do not edit manually! *)\n\n";
  fprintf oc "open Ctypes\n\n";
  (* Library loading *)
  fprintf oc "(* Library loading *)\n";
  fprintf oc "let lib =\n";
  fprintf oc "  let paths =\n";
  fprintf oc "    [ \"libwgpu_native.so\"\n";
  fprintf oc "    ; \"libwgpu_native.dylib\"\n";
  fprintf oc "    ; \"./vendor/wgpu-native/target/debug/libwgpu_native.so\"\n";
  fprintf oc "    ; \"./vendor/wgpu-native/target/release/libwgpu_native.so\"\n";
  fprintf oc "    ]\n";
  fprintf oc "  in\n";
  fprintf oc "  let try_load path =\n";
  fprintf oc "    try Some (Dl.dlopen ~filename:path ~flags:[ Dl.RTLD_NOW ]) with\n";
  fprintf oc "    | _ -> None\n";
  fprintf oc "  in\n";
  fprintf oc "  match List.find_map try_load paths with\n";
  fprintf oc "  | Some lib -> lib\n";
  fprintf oc "  | None ->\n";
  fprintf oc "    failwith\n";
  fprintf
    oc
    "      \"Could not find libwgpu_native. Build with: cd vendor/wgpu-native && cargo \\\n";
  fprintf oc "       build\"\n";
  fprintf oc ";;\n\n";
  fprintf oc "let foreign name typ = Foreign.foreign ~from:lib name typ\n\n";
  (* String view *)
  fprintf oc "(* String view type *)\n";
  fprintf oc "module String_view = struct\n";
  fprintf oc "  type t\n\n";
  fprintf oc "  let t : t structure typ = structure \"WGPUStringView\"\n";
  fprintf oc "  let data = field t \"data\" (ptr char)\n";
  fprintf oc "  let length = field t \"length\" size_t\n";
  fprintf oc "  let () = seal t\n\n";
  fprintf oc "  let of_string s =\n";
  fprintf oc "    let len = String.length s in\n";
  fprintf oc "    let st = make t in\n";
  fprintf oc "    let buf = CArray.of_string s in\n";
  fprintf oc "    setf st data (CArray.start buf);\n";
  fprintf oc "    setf st length (Unsigned.Size_t.of_int len);\n";
  fprintf oc "    st\n";
  fprintf oc "  ;;\n\n";
  fprintf oc "  let null () =\n";
  fprintf oc "    let st = make t in\n";
  fprintf oc "    setf st data (from_voidp char null);\n";
  fprintf oc "    setf st length Unsigned.Size_t.max_int;\n";
  fprintf oc "    st\n";
  fprintf oc "  ;;\n";
  fprintf oc "end\n\n";
  (* Chained struct *)
  fprintf oc "(* Chained struct for extensions *)\n";
  fprintf oc "module Chained_struct = struct\n";
  fprintf oc "  type t\n\n";
  fprintf oc "  let t : t structure typ = structure \"WGPUChainedStruct\"\n";
  fprintf oc "  let next = field t \"next\" (ptr void)\n";
  fprintf oc "  let s_type = field t \"sType\" uint32_t\n";
  fprintf oc "  let () = seal t\n";
  fprintf oc "end\n\n";
  (* Generate enums *)
  fprintf oc "(* === Enums === *)\n\n";
  List.iter (gen_enum oc) (yaml_get_list "enums" yaml);
  (* Generate bitflags *)
  fprintf oc "(* === Bitflags === *)\n\n";
  List.iter (gen_bitflag oc) (yaml_get_list "bitflags" yaml);
  (* Generate object handles *)
  fprintf oc "(* === Object Handles === *)\n\n";
  List.iter (gen_object_handle oc) (yaml_get_list "objects" yaml);
  (* Generate callback info structs *)
  fprintf oc "(* === Callback Info Structs === *)\n\n";
  List.iter (gen_callback_info oc) (yaml_get_list "callbacks" yaml);
  (* Generate structs with fields *)
  fprintf oc "(* === Structs === *)\n\n";
  let sorted_structs = topo_sort_structs (yaml_get_list "structs" yaml) in
  List.iter (gen_struct oc) sorted_structs;
  (* Generate standalone functions *)
  fprintf oc "(* === Functions === *)\n\n";
  List.iter (gen_function oc "") (yaml_get_list "functions" yaml);
  (* Generate object methods *)
  fprintf oc "(* === Object Methods === *)\n\n";
  List.iter
    (fun obj ->
      let obj_name = yaml_get_string "name" obj |> Option.value ~default:"unknown" in
      let methods = yaml_get_list "methods" obj in
      if List.length methods > 0
      then (
        fprintf oc "(* %s methods *)\n" (pascal_case obj_name);
        List.iter (gen_function oc obj_name) methods;
        (* Add release and addref *)
        fprintf
          oc
          "let %s_release =\n\
          \  foreign \"wgpu%sRelease\"\n\
          \    (%s.t @-> returning void)\n\
           ;;\n\n"
          (snake_case obj_name)
          (pascal_case obj_name)
          (pascal_case obj_name);
        fprintf
          oc
          "let %s_add_ref =\n\
          \  foreign \"wgpu%sAddRef\"\n\
          \    (%s.t @-> returning void)\n\
           ;;\n\n"
          (snake_case obj_name)
          (pascal_case obj_name)
          (pascal_case obj_name)))
    (yaml_get_list "objects" yaml);
  (* Add some utility functions *)
  fprintf oc "(* === Utility Functions === *)\n\n";
  fprintf oc "let set_log_callback =\n";
  fprintf oc "  foreign \"wgpuSetLogCallback\"\n";
  fprintf
    oc
    "    (Foreign.funptr (int @-> String_view.t @-> returning void) @-> ptr void @-> \
     returning void)\n";
  fprintf oc ";;\n\n";
  fprintf
    oc
    "let set_log_level = foreign \"wgpuSetLogLevel\" (int @-> returning void)\n\n";
  (* wgpu-native specific extensions *)
  fprintf oc "(* === wgpu-native Extensions === *)\n\n";
  fprintf oc "let device_poll =\n";
  fprintf oc "  foreign \"wgpuDevicePoll\"\n";
  fprintf oc "    (Device.t @-> uint32_t @-> ptr void @-> returning uint32_t)\n";
  fprintf oc ";;\n";
  close_out oc;
  printf "Generated %s\n" output_path
;;

let () =
  let yaml_path = Sys.argv.(1) in
  let output_path = Sys.argv.(2) in
  generate_bindings yaml_path output_path
;;
