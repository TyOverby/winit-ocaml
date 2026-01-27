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

(** Check if a type is simple (primitive, enum, bitflag, or object) - no nested structs *)
let rec is_simple_member_type (type_ref : Ir.type_ref) : bool =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Optional inner -> is_simple_member_type inner
  | Struct _ -> false
  | Callback _ -> false
  | Array { elem; _ } -> is_simple_member_type elem (* Arrays of simple types are OK *)
  | Pointer { inner = Array { elem; _ }; _ } ->
    (* Pointer to array is just an array passed by reference *)
    is_simple_member_type elem
  | Pointer _ -> false
;;

(** Check if a type is simple, allowing nested structs that are themselves simple. Uses
    visited set to prevent infinite recursion. *)
let rec is_simple_member_type_with_nested
  (structs : Ir.struct_ list)
  (visited : Set.M(String).t)
  (type_ref : Ir.type_ref)
  : bool
  =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Optional inner -> is_simple_member_type_with_nested structs visited inner
  | Struct name ->
    (* Check if the nested struct is simple (and not already being visited) *)
    if Set.mem visited name
    then false (* Circular reference *)
    else is_simple_struct_aux structs (Set.add visited name) name
  | Callback _ -> false
  | Array { elem; _ } -> is_simple_member_type_with_nested structs visited elem
  | Pointer { inner = Array { elem; _ }; _ } ->
    (* Pointer to array is just an array passed by reference *)
    is_simple_member_type_with_nested structs visited elem
  | Pointer _ -> false

(** Auxiliary function to check if a struct is simple, with visited tracking *)
and is_simple_struct_aux
  (structs : Ir.struct_ list)
  (visited : Set.M(String).t)
  (struct_name : string)
  : bool
  =
  match List.find structs ~f:(fun s -> String.equal s.name struct_name) with
  | None -> false
  | Some struct_ ->
    (* Only input structs can be auto-generated - not output structs *)
    let is_input_struct =
      match struct_.type_ with
      | Base_in | Standalone | Extension_in _ -> true
      | Base_out | Base_in_out | Extension_out _ -> false
    in
    is_input_struct
    && List.for_all struct_.members ~f:(fun member ->
      is_simple_member_type_with_nested structs visited member.type_)
;;

(** Check if a struct has only simple members (allowing nested simple structs) and is an
    input struct *)
let is_simple_struct (structs : Ir.struct_ list) (struct_name : string) : bool =
  is_simple_struct_aux structs (Set.empty (module String)) struct_name
;;

(** Check if a member type contains a nested struct *)
let member_is_nested_struct (type_ref : Ir.type_ref) : string option =
  match type_ref with
  | Struct name -> Some name
  | _ -> None
;;

(** Check if a member type is an array of structs. Returns the struct name if so. *)
let member_is_array_of_structs (type_ref : Ir.type_ref) : string option =
  match type_ref with
  | Array { elem = Struct name; _ } -> Some name
  | Pointer { inner = Array { elem = Struct name; _ }; _ } -> Some name
  | _ -> None
;;

(** Get all entry structs that appear in arrays within a struct *)
let get_array_entry_structs (structs : Ir.struct_ list) (struct_ : Ir.struct_)
  : Ir.struct_ list
  =
  List.filter_map struct_.members ~f:(fun member ->
    match member_is_array_of_structs member.type_ with
    | Some name -> List.find structs ~f:(fun s -> String.equal s.name name)
    | None -> None)
;;

(** Collect all nested struct members from a struct, recursively. Returns a list of (path,
    struct_def) pairs where path is the variable name path. *)
let rec collect_nested_structs
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  : (string * Ir.struct_) list
  =
  List.concat_map struct_.members ~f:(fun member ->
    match member_is_nested_struct member.type_ with
    | Some nested_name ->
      (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
       | None -> []
       | Some nested_struct ->
         let nested_var = prefix ^ "_" ^ member.name ^ "_nested" in
         (* Add this nested struct and any nested structs within it *)
         (nested_var, nested_struct)
         :: collect_nested_structs structs nested_var nested_struct)
    | None -> [])
;;

(** Check if an argument type is "simple" (can be easily converted) *)
let rec is_simple_arg_type (type_ref : Ir.type_ref) : bool =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Optional inner -> is_simple_arg_type inner
  | Struct _ -> false (* Structs handled separately *)
  | Callback _ -> false
  | Array { elem; _ } -> is_simple_arg_type elem (* Arrays of simple types are OK *)
  | Pointer _ -> false
;;

(** Get all simple struct arguments from a method (input structs only) *)
let get_simple_struct_args (structs : Ir.struct_ list) (method_ : Ir.method_)
  : (Ir.arg * Ir.struct_) list
  =
  List.filter_map method_.args ~f:(fun arg ->
    match arg.type_, arg.pointer with
    | Struct name, (Some `Immutable | None) ->
      if is_simple_struct structs name
      then
        List.find structs ~f:(fun s -> String.equal s.name name)
        |> Option.map ~f:(fun s -> arg, s)
      else None
    | _ -> None)
;;

(** Check if a method has at least one struct argument and all structs are simple input
    structs *)
let method_has_simple_struct_args (structs : Ir.struct_ list) (method_ : Ir.method_)
  : bool
  =
  let struct_args =
    List.filter method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> true
      | _ -> false)
  in
  if List.is_empty struct_args
  then false
  else
    List.for_all struct_args ~f:(fun arg ->
      match arg.type_, arg.pointer with
      | Struct name, (Some `Immutable | None) -> is_simple_struct structs name
      | Struct _, Some `Mutable -> false (* output struct, handled separately *)
      | _ -> false)
;;

(** Check if a struct can be used for output (has only simple readable members) *)
let is_simple_output_struct (structs : Ir.struct_ list) (struct_name : string) : bool =
  match List.find structs ~f:(fun s -> String.equal s.name struct_name) with
  | None -> false
  | Some struct_ ->
    (* Output structs must be base_out or base_in_out *)
    let is_output_struct =
      match struct_.type_ with
      | Base_out | Base_in_out | Extension_out _ -> true
      | Base_in | Standalone | Extension_in _ -> false
    in
    is_output_struct
    && List.for_all struct_.members ~f:(fun member -> is_simple_member_type member.type_)
;;

(** Check if a method has exactly one output struct argument (mutable pointer to struct) *)
let method_has_output_struct_arg (structs : Ir.struct_ list) (method_ : Ir.method_)
  : (Ir.arg * Ir.struct_) option
  =
  let output_struct_args =
    List.filter_map method_.args ~f:(fun arg ->
      match arg.type_, arg.pointer with
      | Struct name, Some `Mutable ->
        if is_simple_output_struct structs name
        then
          List.find structs ~f:(fun s -> String.equal s.name name)
          |> Option.map ~f:(fun s -> arg, s)
        else None
      | _ -> None)
  in
  match output_struct_args with
  | [ pair ] -> Some pair
  | _ -> None
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

(** Check if a method can be included in the high-level API (simple args only) *)
let method_is_high_level_simple (method_ : Ir.method_) : bool =
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

(** Check if a method can be auto-generated (either simple args, simple struct arg, or
    output struct) *)
let method_is_high_level (structs : Ir.struct_ list) (method_ : Ir.method_) : bool =
  if method_is_async method_
  then false
  else (
    let return_ok =
      match method_.returns with
      | None -> true
      | Some ret -> is_simple_return_type ret.type_
    in
    if not return_ok
    then false
    else (
      (* Check if all args are simple *)
      let all_simple =
        List.for_all method_.args ~f:(fun arg -> is_simple_arg_type arg.type_)
      in
      if all_simple
      then true
      else (
        (* Check if all struct args are simple input structs, with other args also simple *)
        let non_struct_args_simple =
          List.for_all method_.args ~f:(fun arg ->
            match arg.type_ with
            | Struct _ -> true (* will check separately *)
            | _ -> is_simple_arg_type arg.type_)
        in
        if non_struct_args_simple && method_has_simple_struct_args structs method_
        then true
        else (
          (* Check if there's an output struct arg *)
          match method_has_output_struct_arg structs method_ with
          | Some _ -> non_struct_args_simple
          | None -> false))))
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
  | Array { elem; _ } -> high_level_arg_type elem ^ " list"
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
  | Enum name -> ocaml_module_name name ^ ".t"
  | Bitflag _ -> "int" (* bitflags return raw int - could be combination of flags *)
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
  | Array { elem = Object name; _ } ->
    (* Convert list of objects to array of handles *)
    sprintf
      "(Array.of_list (List.map (fun x -> x.%s.handle) %s))"
      (ocaml_module_name name)
      arg_name
  | Array { elem = Primitive _; _ } ->
    (* Convert list of primitives to array *)
    sprintf "(Array.of_list %s)" arg_name
  | Array { elem = Enum name; _ } ->
    (* Convert list of enums to array of ints *)
    sprintf "(Array.of_list (List.map %s.to_int %s))" (ocaml_module_name name) arg_name
  | _ -> arg_name
;;

(** Generate code to convert a low-level return value to high-level *)
let return_to_high_level (result_expr : string) (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive _ -> result_expr
  | Enum name -> sprintf "(%s.of_int (%s))" (ocaml_module_name name) result_expr
  | Bitflag _ -> result_expr (* bitflags return as ints - could be combination of flags *)
  | Object name ->
    sprintf
      "({ %s.handle = %s } : %s.t)"
      (ocaml_module_name name)
      result_expr
      (ocaml_module_name name)
  | _ -> result_expr
;;

(** Generate code to convert a struct member value to low-level *)
let member_to_low_level (member_name : string) (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive _ -> member_name
  | Enum name -> sprintf "(%s.to_int %s)" (ocaml_module_name name) member_name
  | Bitflag name -> sprintf "(%s.list_to_int %s)" (ocaml_module_name name) member_name
  | Object name -> sprintf "%s.%s.handle" member_name (ocaml_module_name name)
  | Optional (Enum name) ->
    sprintf
      "(match %s with Some x -> %s.to_int x | None -> 0)"
      member_name
      (ocaml_module_name name)
  | Optional (Object name) ->
    sprintf
      "(match %s with Some x -> x.%s.handle | None -> 0n)"
      member_name
      (ocaml_module_name name)
  | Optional _ -> member_name
  | Array { elem = Object name; _ } ->
    (* Convert list of objects to array of handles *)
    sprintf
      "(Array.of_list (List.map (fun x -> x.%s.handle) %s))"
      (ocaml_module_name name)
      member_name
  | Array { elem = Primitive _; _ } ->
    (* Convert list of primitives to array *)
    sprintf "(Array.of_list %s)" member_name
  | Array { elem = Enum name; _ } ->
    (* Convert list of enums to array of ints *)
    sprintf "(Array.of_list (List.map %s.to_int %s))" (ocaml_module_name name) member_name
  | Array { elem = Bitflag name; _ } ->
    (* Convert list of bitflag lists to array of ints *)
    sprintf
      "(Array.of_list (List.map %s.list_to_int %s))"
      (ocaml_module_name name)
      member_name
  | Pointer { inner = Array { elem = Object name; _ }; _ } ->
    (* Pointer to array of objects - same as array of objects *)
    sprintf
      "(Array.of_list (List.map (fun x -> x.%s.handle) %s))"
      (ocaml_module_name name)
      member_name
  | Pointer { inner = Array { elem = Primitive _; _ }; _ } ->
    (* Pointer to array of primitives *)
    sprintf "(Array.of_list %s)" member_name
  | Pointer { inner = Array { elem = Enum name; _ }; _ } ->
    (* Pointer to array of enums *)
    sprintf "(Array.of_list (List.map %s.to_int %s))" (ocaml_module_name name) member_name
  | _ -> member_name
;;

(** Get default value for a type (used for optional struct members) *)
let default_value_for_type (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive String_with_default_empty -> {|""|}
  | Primitive Bool -> "false"
  | Primitive (Uint32 | Int32) -> "0"
  | Primitive (Uint64 | Int64 | Usize) -> "0L"
  | Primitive (Float32 | Float64) -> "0.0"
  | Optional _ -> "None"
  | Array _ -> "[]"
  | Pointer { inner = Array _; _ } -> "[]"
  | _ -> {|""|}
;;

(** Recursively collect all parameters from a struct, including nested structs. Returns
    (param_name, member, is_optional, nested_var_name option) list. nested_var_name is
    Some if this parameter belongs to a nested struct.

    For array-of-struct members, we don't recurse - the parameter is a list of records. *)
let rec collect_struct_params
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  (nested_var : string option)
  : (string * Ir.struct_member * bool * string option) list
  =
  List.concat_map struct_.members ~f:(fun member ->
    (* First check if this is an array-of-structs - these are NOT flattened *)
    match member_is_array_of_structs member.type_ with
    | Some _ ->
      (* Array of structs - parameter is a list of records, don't recurse *)
      let param_name = escape_keyword (prefix ^ member.name) in
      let is_optional =
        member.optional
        ||
        match member.type_ with
        | Array _ | Pointer { inner = Array _; _ } -> true
        | _ -> false
      in
      [ param_name, member, is_optional, nested_var ]
    | None ->
      (* Check for direct nested struct *)
      (match member_is_nested_struct member.type_ with
       | Some nested_name ->
         (* This member is a nested struct - collect its parameters *)
         (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
          | None -> []
          | Some nested_struct ->
            let nested_prefix = prefix ^ member.name ^ "_" in
            let nested_var_name = prefix ^ member.name ^ "_nested" in
            collect_struct_params
              structs
              nested_prefix
              nested_struct
              (Some nested_var_name))
       | None ->
         (* Regular member - create parameter *)
         let param_name = escape_keyword (prefix ^ member.name) in
         let is_optional =
           member.optional
           ||
           match member.type_ with
           | Primitive String_with_default_empty -> true
           | Optional _ -> true
           | Array _ -> true
           | Pointer { inner = Array _; _ } -> true
           | _ -> false
         in
         [ param_name, member, is_optional, nested_var ]))
;;

(** Generate code to create a struct and all its nested structs. Returns list of
    (var_name, struct_) pairs for all created structs (including nested). *)
let rec generate_struct_creates
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  (var_name : string)
  : (string * Ir.struct_) list * string list
  =
  let struct_module = ocaml_module_name struct_.name in
  let create_line =
    sprintf "let %s = Wgpu_low.%s.%s_create () in" var_name struct_module struct_.name
  in
  (* Collect nested struct creates *)
  let nested_results =
    List.filter_map struct_.members ~f:(fun member ->
      match member_is_nested_struct member.type_ with
      | Some nested_name ->
        (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
         | None -> None
         | Some nested_struct ->
           let nested_var = prefix ^ member.name ^ "_nested" in
           let nested_prefix = prefix ^ member.name ^ "_" in
           Some (generate_struct_creates structs nested_prefix nested_struct nested_var))
      | None -> None)
  in
  let nested_vars, nested_creates =
    List.fold nested_results ~init:([], []) ~f:(fun (vars, creates) (v, c) ->
      vars @ v, creates @ c)
  in
  (var_name, struct_) :: nested_vars, nested_creates @ [ create_line ]
;;

(** Generate code to convert a nested struct record field to a C struct. Returns
    (create_code, set_code, free_vars) where:
    - create_code creates the C struct
    - set_code sets all fields on the struct
    - free_vars is a list of (var_name, struct_name) pairs for later freeing *)
let gen_nested_struct_conversion
  (_structs : Ir.struct_ list)
  (entry_var : string)
  (field_name : string)
  (nested_struct : Ir.struct_)
  (parent_var : string)
  : string list * string list * (string * Ir.struct_) list
  =
  let nested_module = ocaml_module_name nested_struct.name in
  let nested_var = parent_var ^ "_" ^ field_name in
  (* Create the nested struct *)
  let create_code =
    [ sprintf
        "let %s = Wgpu_low.%s.%s_create () in"
        nested_var
        nested_module
        nested_struct.name
    ]
  in
  (* Set fields from the record *)
  let set_code =
    List.filter_map nested_struct.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else (
        let member_field = escape_keyword member.name in
        let value_expr = sprintf "%s.%s.%s" entry_var field_name member_field in
        let converted = member_to_low_level value_expr member.type_ in
        Some
          (sprintf
             "Wgpu_low.%s.%s_set_%s %s %s;"
             nested_module
             nested_struct.name
             member.name
             nested_var
             converted)))
  in
  create_code, set_code, [ nested_var, nested_struct ]
;;

(** Convert an entry struct member value to low-level, handling the optional flag *)
let entry_member_to_low_level (field_access : string) (member : Ir.struct_member) : string
  =
  match member.type_, member.optional with
  | Object name, true ->
    (* Optional object - wrap in match *)
    sprintf
      "(match %s with Some x -> x.%s.handle | None -> 0n)"
      field_access
      (ocaml_module_name name)
  | _ -> member_to_low_level field_access member.type_
;;

(** Generate code to convert a list of entry struct records to C structs. Returns
    (code_lines, vars_to_free) where vars_to_free is a list of (var_name, struct) pairs
    that need to be freed. *)
let generate_array_of_structs_conversion
  (structs : Ir.struct_ list)
  (param_name : string)
  (entry_struct : Ir.struct_)
  (parent_var : string)
  (parent_struct : Ir.struct_)
  (member_name : string)
  : string list * (string * Ir.struct_) list
  =
  let entry_module = ocaml_module_name entry_struct.name in
  let parent_module = ocaml_module_name parent_struct.name in
  let entries_var = param_name ^ "_structs" in
  let array_var = param_name ^ "_array" in
  (* Generate code to convert each entry record to a C struct *)
  let loop_code =
    [ sprintf "let %s = List.map (fun (entry : %s.t) ->" entries_var entry_module ]
    @ [ sprintf "    let e = Wgpu_low.%s.%s_create () in" entry_module entry_struct.name ]
    @ List.concat_map entry_struct.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then []
      else (
        match member_is_nested_struct member.type_ with
        | Some nested_name ->
          (* Nested struct - wrap in Option.iter *)
          (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
           | None -> []
           | Some nested_struct ->
             let nested_module = ocaml_module_name nested_struct.name in
             let nested_var = "nested_" ^ member.name in
             [ sprintf "    (match entry.%s with" (escape_keyword member.name)
             ; sprintf "     | Some %s_rec ->" member.name
             ; sprintf
                 "       let %s = Wgpu_low.%s.%s_create () in"
                 nested_var
                 nested_module
                 nested_struct.name
             ]
             @ List.filter_map nested_struct.members ~f:(fun nm ->
               if String.equal nm.name "nextInChain"
               then None
               else (
                 let field_access =
                   sprintf "%s_rec.%s" member.name (escape_keyword nm.name)
                 in
                 let converted = member_to_low_level field_access nm.type_ in
                 Some
                   (sprintf
                      "       Wgpu_low.%s.%s_set_%s %s %s;"
                      nested_module
                      nested_struct.name
                      nm.name
                      nested_var
                      converted)))
             @ [ sprintf
                   "       Wgpu_low.%s.%s_set_%s e %s"
                   entry_module
                   entry_struct.name
                   member.name
                   nested_var
               ; "     | None -> ());"
               ])
        | None ->
          (* Regular member - use entry_member_to_low_level for proper optional handling *)
          let field_access = sprintf "entry.%s" (escape_keyword member.name) in
          let converted = entry_member_to_low_level field_access member in
          [ sprintf
              "    Wgpu_low.%s.%s_set_%s e %s;"
              entry_module
              entry_struct.name
              member.name
              converted
          ]))
    @ [ "    e) " ^ param_name ^ " in" ]
    @ [ sprintf "let %s = Array.of_list %s in" array_var entries_var ]
    @ [ sprintf
          "Wgpu_low.%s.%s_set_%s %s %s;"
          parent_module
          parent_struct.name
          member_name
          parent_var
          array_var
      ]
  in
  (* The entry structs will need to be freed later *)
  loop_code, [ entries_var, entry_struct ]
;;

(** Generate code to set fields on a struct, including assigning nested structs. prefix is
    the parameter prefix for this struct. Returns (set_code, vars_to_free). *)
let rec generate_struct_sets
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  (var_name : string)
  : string list * (string * Ir.struct_) list
  =
  let struct_module = ocaml_module_name struct_.name in
  let results =
    List.map struct_.members ~f:(fun member ->
      (* First check for array-of-structs *)
      match member_is_array_of_structs member.type_ with
      | Some entry_name ->
        (match List.find structs ~f:(fun s -> String.equal s.name entry_name) with
         | Some entry_struct ->
           let param_name = escape_keyword (prefix ^ member.name) in
           generate_array_of_structs_conversion
             structs
             param_name
             entry_struct
             var_name
             struct_
             member.name
         | None -> [], [])
      | None ->
        (* Check for direct nested struct *)
        (match member_is_nested_struct member.type_ with
         | Some nested_name ->
           (* First, recursively set fields on the nested struct *)
           (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
            | None -> [], []
            | Some nested_struct ->
              let nested_var = prefix ^ member.name ^ "_nested" in
              let nested_prefix = prefix ^ member.name ^ "_" in
              let nested_sets, nested_vars =
                generate_struct_sets structs nested_prefix nested_struct nested_var
              in
              (* Then, set the nested struct on the parent *)
              let set_nested =
                sprintf
                  "Wgpu_low.%s.%s_set_%s %s %s;"
                  struct_module
                  struct_.name
                  member.name
                  var_name
                  nested_var
              in
              nested_sets @ [ set_nested ], nested_vars)
         | None ->
           (* Regular member - set the value *)
           let param_name = escape_keyword (prefix ^ member.name) in
           let converted = member_to_low_level param_name member.type_ in
           ( [ sprintf
                 "Wgpu_low.%s.%s_set_%s %s %s;"
                 struct_module
                 struct_.name
                 member.name
                 var_name
                 converted
             ]
           , [] )))
  in
  let code = List.concat_map results ~f:fst in
  let vars = List.concat_map results ~f:snd in
  code, vars
;;

(** Generate ML implementation for a method with one or more struct arguments *)
let gen_ml_method_with_structs
  (structs : Ir.struct_ list)
  (obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_args : (Ir.arg * Ir.struct_) list)
  : string
  =
  let method_name = escape_keyword method_.name in
  let use_prefix = List.length struct_args > 1 in
  (* Get non-struct args *)
  let other_args =
    List.filter method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> false
      | _ -> true)
  in
  (* Build parameter list from all struct members + other args (including nested) *)
  let struct_params =
    List.concat_map struct_args ~f:(fun (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      collect_struct_params structs base_prefix struct_ None)
  in
  let other_params =
    List.map other_args ~f:(fun arg -> escape_keyword arg.name, arg, arg.optional)
  in
  (* Build function signature *)
  let param_strs =
    List.filter_map struct_params ~f:(fun (name, member, is_opt, _) ->
      if is_opt
      then Some (sprintf "?(%s = %s)" name (default_value_for_type member.type_))
      else Some (sprintf "~%s" name))
    @ List.filter_map other_params ~f:(fun (name, _arg, is_opt) ->
      if is_opt then Some (sprintf "?%s" name) else Some (sprintf "~%s" name))
  in
  let param_list = "t " ^ String.concat ~sep:" " param_strs ^ " ()" in
  (* Generate struct creation for each struct arg (including nested structs) *)
  let all_struct_vars, create_structs_lists =
    List.fold struct_args ~init:([], []) ~f:(fun (vars, creates) (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      let desc_var = "desc_" ^ arg.name in
      let new_vars, new_creates =
        generate_struct_creates structs base_prefix struct_ desc_var
      in
      vars @ new_vars, creates @ new_creates)
  in
  let create_structs = create_structs_lists in
  (* Generate field setting for each struct (including nested structs) *)
  let set_fields, entry_struct_lists =
    List.fold struct_args ~init:([], []) ~f:(fun (fields, entry_lists) (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      let desc_var = "desc_" ^ arg.name in
      let field_code, entry_vars =
        generate_struct_sets structs base_prefix struct_ desc_var
      in
      fields @ field_code, entry_lists @ entry_vars)
  in
  (* Build the call args, mapping each struct arg to its desc variable *)
  let struct_arg_names =
    List.map struct_args ~f:(fun (arg, _) -> arg.name) |> Set.of_list (module String)
  in
  let call_args =
    List.map method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ when Set.mem struct_arg_names arg.name -> "desc_" ^ arg.name
      | _ -> arg_to_low_level (escape_keyword arg.name) arg.type_)
  in
  let call =
    sprintf
      "Wgpu_low.%s_%s t.handle %s"
      obj.name
      method_.name
      (String.concat ~sep:" " call_args)
  in
  (* Generate code to free entry struct lists *)
  let free_entry_lists =
    List.concat_map entry_struct_lists ~f:(fun (list_var, entry_struct) ->
      let entry_module = ocaml_module_name entry_struct.name in
      [ sprintf
          "List.iter (fun e -> Wgpu_low.%s.%s_free e) %s;"
          entry_module
          entry_struct.name
          list_var
      ])
  in
  (* Generate struct freeing (reverse order: parent structs first, then nested) *)
  let free_structs =
    List.map (List.rev all_struct_vars) ~f:(fun (var_name, struct_) ->
      let struct_module = ocaml_module_name struct_.name in
      sprintf "Wgpu_low.%s.%s_free %s;" struct_module struct_.name var_name)
  in
  (* Generate result handling *)
  let all_frees = free_entry_lists @ free_structs in
  let result_and_free =
    match method_.returns with
    | None -> String.concat ~sep:"\n    " ([ call ^ ";" ] @ all_frees @ [ "()" ])
    | Some ret ->
      let free_lines = String.concat ~sep:"\n    " all_frees in
      sprintf
        "let result = %s in\n    %s\n    %s"
        call
        free_lines
        (return_to_high_level "result" ret.type_)
  in
  (* Put it all together *)
  let body_lines = create_structs @ set_fields @ [ result_and_free ] in
  let body = String.concat ~sep:"\n    " body_lines in
  sprintf "  let %s %s =\n    %s\n" method_name param_list body
;;

(** Generate ML implementation for a method with output struct argument *)
let gen_ml_method_with_output_struct
  (obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_ : Ir.struct_)
  (_arg : Ir.arg)
  : string
  =
  let method_name = escape_keyword method_.name in
  let struct_module = ocaml_module_name struct_.name in
  let struct_var = "output" in
  (* Get other args that are not the output struct *)
  let other_args =
    List.filter method_.args ~f:(fun a ->
      not
        (match a.type_ with
         | Struct _ -> true
         | _ -> false))
  in
  (* Build parameter list *)
  let param_list =
    if List.is_empty other_args
    then "t"
    else
      "t "
      ^ String.concat
          ~sep:" "
          (List.map other_args ~f:(fun a -> sprintf "~%s" (escape_keyword a.name)))
  in
  (* Create the output struct *)
  let create_struct =
    sprintf "let %s = Wgpu_low.%s.%s_create () in" struct_var struct_module struct_.name
  in
  (* Build call args *)
  let call_args =
    List.map method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> struct_var
      | _ -> arg_to_low_level (escape_keyword arg.name) arg.type_)
  in
  let call =
    sprintf
      "let _status = Wgpu_low.%s_%s t.handle %s in"
      obj.name
      method_.name
      (String.concat ~sep:" " call_args)
  in
  (* Read fields from the struct *)
  let read_fields =
    List.filter_map struct_.members ~f:(fun member ->
      (* Skip nextInChain *)
      if String.equal member.name "nextInChain"
      then None
      else (
        let field_name = escape_keyword member.name in
        let getter_name =
          sprintf "Wgpu_low.%s.%s_get_%s" struct_module struct_.name member.name
        in
        let value_expr =
          match member.type_ with
          | Enum name ->
            sprintf "(%s.of_int (%s %s))" (ocaml_module_name name) getter_name struct_var
          | Object name ->
            sprintf
              "({ %s.handle = %s %s } : %s.t)"
              (ocaml_module_name name)
              getter_name
              struct_var
              (ocaml_module_name name)
          | _ -> sprintf "(%s %s)" getter_name struct_var
        in
        Some (sprintf "let %s = %s in" field_name value_expr)))
  in
  (* Build the record *)
  let record_fields =
    List.filter_map struct_.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else Some (sprintf "%s" (escape_keyword member.name)))
  in
  let build_record =
    sprintf "let result = { %s } in" (String.concat ~sep:"; " record_fields)
  in
  (* Free the struct *)
  let free_struct =
    sprintf "Wgpu_low.%s.%s_free %s;" struct_module struct_.name struct_var
  in
  (* Return result *)
  let return_result = "result" in
  (* Combine all lines *)
  let body_lines =
    [ create_struct; call ] @ read_fields @ [ build_record; free_struct; return_result ]
  in
  let body = String.concat ~sep:"\n    " body_lines in
  sprintf "  let %s %s =\n    %s\n" method_name param_list body
;;

(** Generate ML implementation for a method *)
let gen_ml_method (structs : Ir.struct_ list) (obj : Ir.object_) (method_ : Ir.method_)
  : string option
  =
  (* Skip methods that are manually implemented *)
  if Config.is_manual ~object_name:obj.name ~method_name:method_.name
  then None
  else if not (method_is_high_level structs method_)
  then None
  else (
    (* First check for output struct arg *)
    match method_has_output_struct_arg structs method_ with
    | Some (arg, struct_) ->
      Some (gen_ml_method_with_output_struct obj method_ struct_ arg)
    | None ->
      (* Check if this method has simple struct arguments *)
      let struct_args = get_simple_struct_args structs method_ in
      (match struct_args with
       | _ :: _ ->
         (* One or more simple struct args *)
         Some (gen_ml_method_with_structs structs obj method_ struct_args)
       | [] ->
         (* Original simple method generation - no struct args *)
         let method_name = escape_keyword method_.name in
         let low_level_func = sprintf "Wgpu_low.%s_%s" obj.name method_.name in
         let args =
           List.map method_.args ~f:(fun arg ->
             let converted = arg_to_low_level arg.name arg.type_ in
             arg.name, converted)
         in
         let arg_names = List.map args ~f:fst in
         let arg_conversions = List.map args ~f:snd in
         let param_list =
           if List.is_empty arg_names
           then "t"
           else "t " ^ String.concat ~sep:" " (List.map arg_names ~f:(sprintf "~%s"))
         in
         let call_args = "t.handle" :: arg_conversions in
         let call = sprintf "%s %s" low_level_func (String.concat ~sep:" " call_args) in
         let body =
           match method_.returns with
           | None -> call
           | Some ret -> return_to_high_level call ret.type_
         in
         Some (sprintf "  let %s %s = %s\n" method_name param_list body)))
;;

(** Get high-level OCaml type for a struct member *)
let rec high_level_member_type (member : Ir.struct_member) : string =
  high_level_member_type_of_type member.type_

(** Get high-level OCaml type for a type_ref (for struct members) *)
and high_level_member_type_of_type (type_ref : Ir.type_ref) : string =
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
  | Optional (Enum name) -> ocaml_module_name name ^ ".t option"
  | Optional (Object name) -> ocaml_module_name name ^ ".t option"
  | Optional inner -> high_level_arg_type inner ^ " option"
  | Array { elem = Object name; _ } -> ocaml_module_name name ^ ".t list"
  | Array { elem = Struct name; _ } -> ocaml_module_name name ^ ".t list"
  | Array { elem = Enum name; _ } -> ocaml_module_name name ^ ".t list"
  | Array { elem = Bitflag name; _ } -> ocaml_module_name name ^ ".t list list"
  | Array { elem = Primitive Bool; _ } -> "bool list"
  | Array { elem = Primitive (Uint32 | Int32); _ } -> "int list"
  | Array { elem = Primitive (Uint64 | Int64 | Usize); _ } -> "int64 list"
  | Array { elem = Primitive (Float32 | Float64); _ } -> "float list"
  | Array { elem = Primitive (String | Out_string | String_with_default_empty); _ } ->
    "string list"
  | Pointer { inner = Array { elem = Struct name; _ }; _ } ->
    (* Array of structs passed by pointer *)
    ocaml_module_name name ^ ".t list"
  | Pointer { inner = Array { elem; _ }; _ } ->
    (* Other array types passed by pointer *)
    high_level_member_type_of_type (Array { elem; pointer = None })
  | Struct name -> ocaml_module_name name ^ ".t"
  | _ -> "nativeint"
;;

(** Generate record type definition for an output struct *)
let gen_output_struct_record_type (struct_ : Ir.struct_) : string =
  let type_name = String.lowercase struct_.name in
  let fields =
    List.filter_map struct_.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else (
        let field_name = escape_keyword member.name in
        let field_type = high_level_member_type member in
        Some (sprintf "  %s : %s" field_name field_type)))
  in
  sprintf "type %s = {\n%s\n}\n" type_name (String.concat ~sep:";\n" fields)
;;

(** Get high-level type for an entry struct member, including handling nested structs as
    records and respecting the optional flag *)
let rec entry_struct_member_type (_structs : Ir.struct_ list) (member : Ir.struct_member)
  : string
  =
  match member.type_ with
  | Struct nested_name ->
    (* Nested struct becomes an optional record type *)
    let nested_module = ocaml_module_name nested_name in
    sprintf "%s.t option" nested_module
  | Object name when member.optional ->
    (* Optional object becomes an option type *)
    sprintf "%s.t option" (ocaml_module_name name)
  | _ -> high_level_member_type member

(** Generate a record type module for an entry struct (a struct that appears in arrays).
    Also generates record types for any nested structs. *)
and gen_entry_struct_module (structs : Ir.struct_ list) (struct_ : Ir.struct_) : string =
  let module_name = ocaml_module_name struct_.name in
  (* First, generate modules for any nested structs *)
  let nested_modules =
    List.filter_map struct_.members ~f:(fun member ->
      match member_is_nested_struct member.type_ with
      | Some nested_name ->
        List.find structs ~f:(fun s -> String.equal s.name nested_name)
        |> Option.map ~f:(gen_nested_struct_module structs)
      | None -> None)
    |> List.dedup_and_sort ~compare:String.compare
    |> String.concat ~sep:"\n"
  in
  (* Generate the record type for this struct *)
  let fields =
    List.filter_map struct_.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else (
        let field_name = escape_keyword member.name in
        let field_type = entry_struct_member_type structs member in
        Some (sprintf "      %s : %s" field_name field_type)))
  in
  let record_type =
    sprintf "    type t = {\n%s\n    }" (String.concat ~sep:";\n" fields)
  in
  sprintf
    "  module %s = struct\n%s%s\n  end\n"
    module_name
    (if String.is_empty nested_modules then "" else nested_modules ^ "\n")
    record_type

(** Generate a simple record module for a nested struct (struct that is a member of an
    entry struct) *)
and gen_nested_struct_module (_structs : Ir.struct_ list) (struct_ : Ir.struct_) : string =
  let module_name = ocaml_module_name struct_.name in
  let fields =
    List.filter_map struct_.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else (
        let field_name = escape_keyword member.name in
        let field_type = high_level_member_type member in
        Some (sprintf "        %s : %s" field_name field_type)))
  in
  sprintf
    "    module %s = struct\n      type t = {\n%s\n      }\n    end\n"
    module_name
    (String.concat ~sep:";\n" fields)
;;

(** Check if a struct contains array-of-struct members *)
let struct_has_array_of_structs (struct_ : Ir.struct_) : bool =
  List.exists struct_.members ~f:(fun member ->
    Option.is_some (member_is_array_of_structs member.type_))
;;

(** Generate MLI for a nested struct module *)
let gen_nested_struct_module_mli (_structs : Ir.struct_ list) (struct_ : Ir.struct_)
  : string
  =
  let module_name = ocaml_module_name struct_.name in
  let fields =
    List.filter_map struct_.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else (
        let field_name = escape_keyword member.name in
        let field_type = high_level_member_type member in
        Some (sprintf "        %s : %s" field_name field_type)))
  in
  sprintf
    "    module %s : sig\n      type t = {\n%s\n      }\n    end\n"
    module_name
    (String.concat ~sep:";\n" fields)
;;

(** Generate MLI for an entry struct module *)
let gen_entry_struct_module_mli (structs : Ir.struct_ list) (struct_ : Ir.struct_)
  : string
  =
  let module_name = ocaml_module_name struct_.name in
  (* First, generate module signatures for any nested structs *)
  let nested_modules =
    List.filter_map struct_.members ~f:(fun member ->
      match member_is_nested_struct member.type_ with
      | Some nested_name ->
        List.find structs ~f:(fun s -> String.equal s.name nested_name)
        |> Option.map ~f:(gen_nested_struct_module_mli structs)
      | None -> None)
    |> List.dedup_and_sort ~compare:String.compare
    |> String.concat ~sep:"\n"
  in
  (* Generate the record type for this struct *)
  let fields =
    List.filter_map struct_.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then None
      else (
        let field_name = escape_keyword member.name in
        let field_type = entry_struct_member_type structs member in
        Some (sprintf "      %s : %s" field_name field_type)))
  in
  let record_type =
    sprintf "    type t = {\n%s\n    }" (String.concat ~sep:";\n" fields)
  in
  sprintf
    "  module %s : sig\n%s%s\n  end\n"
    module_name
    (if String.is_empty nested_modules then "" else nested_modules ^ "\n")
    record_type
;;

(** Generate MLI signature for a method with one or more struct arguments *)
let gen_mli_method_with_structs
  (structs : Ir.struct_ list)
  (_obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_args : (Ir.arg * Ir.struct_) list)
  : string
  =
  let method_name = escape_keyword method_.name in
  let use_prefix = List.length struct_args > 1 in
  (* Get non-struct args *)
  let other_args =
    List.filter method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> false
      | _ -> true)
  in
  (* Build parameter types from all struct members + other args (including nested) *)
  let struct_param_types =
    List.concat_map struct_args ~f:(fun (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      let params = collect_struct_params structs base_prefix struct_ None in
      List.map params ~f:(fun (param_name, member, is_optional, _) ->
        let type_str = high_level_member_type member in
        if is_optional
        then sprintf "?%s:%s" param_name type_str
        else sprintf "%s:%s" param_name type_str))
  in
  let other_param_types =
    List.map other_args ~f:(fun arg ->
      let param_name = escape_keyword arg.name in
      let type_str = high_level_arg_type arg.type_ in
      if arg.optional
      then sprintf "?%s:%s" param_name type_str
      else sprintf "%s:%s" param_name type_str)
  in
  let return_type =
    match method_.returns with
    | None -> "unit"
    | Some ret -> high_level_return_type ret.type_
  in
  let all_params = struct_param_types @ other_param_types in
  let type_sig =
    sprintf "t -> %s -> unit -> %s" (String.concat ~sep:" -> " all_params) return_type
  in
  sprintf "  val %s : %s\n" method_name type_sig
;;

(** Generate MLI signature for a method with output struct argument *)
let gen_mli_method_with_output_struct
  (_obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_ : Ir.struct_)
  : string
  =
  let method_name = escape_keyword method_.name in
  (* Get other args that are not the output struct *)
  let other_args =
    List.filter method_.args ~f:(fun a ->
      not
        (match a.type_ with
         | Struct _ -> true
         | _ -> false))
  in
  let other_param_types =
    List.map other_args ~f:(fun arg ->
      let param_name = escape_keyword arg.name in
      let type_str = high_level_arg_type arg.type_ in
      if arg.optional
      then sprintf "?%s:%s" param_name type_str
      else sprintf "%s:%s" param_name type_str)
  in
  (* Build record type name from struct name *)
  let record_type_name = String.lowercase struct_.name in
  let return_type = record_type_name in
  let type_sig =
    if List.is_empty other_param_types
    then sprintf "t -> %s" return_type
    else sprintf "t -> %s -> %s" (String.concat ~sep:" -> " other_param_types) return_type
  in
  sprintf "  val %s : %s\n" method_name type_sig
;;

(** Generate MLI signature for a method *)
let gen_mli_method (structs : Ir.struct_ list) (obj : Ir.object_) (method_ : Ir.method_)
  : string option
  =
  (* Skip methods that are manually implemented *)
  if Config.is_manual ~object_name:obj.name ~method_name:method_.name
  then None
  else if not (method_is_high_level structs method_)
  then None
  else (
    (* First check for output struct arg *)
    match method_has_output_struct_arg structs method_ with
    | Some (_arg, struct_) -> Some (gen_mli_method_with_output_struct obj method_ struct_)
    | None ->
      (* Check if this method has simple struct arguments *)
      let struct_args = get_simple_struct_args structs method_ in
      (match struct_args with
       | _ :: _ ->
         (* One or more simple struct args *)
         Some (gen_mli_method_with_structs structs obj method_ struct_args)
       | [] ->
         (* Original simple method generation - no struct args *)
         let method_name = escape_keyword method_.name in
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
         Some (sprintf "  val %s : %s\n" method_name type_sig)))
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
    "module %s : sig\n\
     %s  type t =\n\
     %s\n\n\
    \  val to_int : t -> int\n\
    \  val of_int : int -> t\n\
     end\n"
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
let gen_ml_object (structs : Ir.struct_ list) (obj : Ir.object_) : string =
  let module_name = ocaml_module_name obj.name in
  (* Collect output struct types used by this object's methods *)
  let output_struct_types =
    List.filter_map obj.methods ~f:(fun method_ ->
      match method_has_output_struct_arg structs method_ with
      | Some (_arg, struct_) -> Some (gen_output_struct_record_type struct_)
      | None -> None)
    |> List.dedup_and_sort ~compare:String.compare
    |> String.concat ~sep:"\n"
  in
  let methods =
    List.filter_map obj.methods ~f:(gen_ml_method structs obj) |> String.concat ~sep:""
  in
  sprintf
    "module %s = struct\n\
    \  type t = { handle : Wgpu_low.%s }\n\n\
     %s  let release t = Wgpu_low.%s_release t.handle\n\
     %send\n"
    module_name
    obj.name
    (if String.is_empty output_struct_types then "" else "  " ^ output_struct_types ^ "\n")
    obj.name
    methods
;;

(** Generate MLI for an object type with methods *)
let gen_mli_object (structs : Ir.struct_ list) (obj : Ir.object_) : string =
  let module_name = ocaml_module_name obj.name in
  let doc_comment =
    match useful_doc obj.doc with
    | None -> ""
    | Some doc -> sprintf "  (** %s *)\n\n" doc
  in
  (* Collect output struct types used by this object's methods *)
  let output_struct_types =
    List.filter_map obj.methods ~f:(fun method_ ->
      match method_has_output_struct_arg structs method_ with
      | Some (_arg, struct_) -> Some (gen_output_struct_record_type struct_)
      | None -> None)
    |> List.dedup_and_sort ~compare:String.compare
    |> String.concat ~sep:"\n"
  in
  let methods =
    List.filter_map obj.methods ~f:(gen_mli_method structs obj) |> String.concat ~sep:""
  in
  sprintf
    "module %s : sig\n%s  type t\n\n%s  val release : t -> unit\n%send\n"
    module_name
    doc_comment
    (if String.is_empty output_struct_types then "" else "  " ^ output_struct_types ^ "\n")
    methods
;;

(** Extract object dependencies from a type_ref. Returns object names that must be defined
    before this type can be used. *)
let rec extract_object_deps (type_ref : Ir.type_ref) : string list =
  match type_ref with
  | Object name -> [ name ]
  | Optional inner -> extract_object_deps inner
  | Array { elem; _ } -> extract_object_deps elem
  | Pointer { inner; _ } -> extract_object_deps inner
  | Primitive _ | Enum _ | Bitflag _ | Struct _ | Callback _ -> []
;;

(** Get all object dependencies for a single object. An object A depends on object B if:
    1. A method of A returns B (e.g., Texture.create_view returns Texture_view)
    2. A method of A takes B as a parameter (e.g., Compute_pass_encoder.set_pipeline takes
       Compute_pipeline)
    3. A method of A has an output struct with a field of type B *)
let get_object_dependencies (structs : Ir.struct_ list) (obj : Ir.object_)
  : Set.M(String).t
  =
  let deps = ref (Set.empty (module String)) in
  List.iter obj.methods ~f:(fun method_ ->
    (* Check return type *)
    (match method_.returns with
     | Some ret ->
       List.iter (extract_object_deps ret.type_) ~f:(fun dep ->
         if not (String.equal dep obj.name) then deps := Set.add !deps dep)
     | None -> ());
    (* Check argument types *)
    List.iter method_.args ~f:(fun arg ->
      (* Direct object arguments *)
      List.iter (extract_object_deps arg.type_) ~f:(fun dep ->
        if not (String.equal dep obj.name) then deps := Set.add !deps dep);
      (* Output struct args - check their fields *)
      match arg.type_, arg.pointer with
      | Struct name, Some `Mutable ->
        (match List.find structs ~f:(fun s -> String.equal s.name name) with
         | Some struct_ ->
           List.iter struct_.members ~f:(fun member ->
             List.iter (extract_object_deps member.type_) ~f:(fun dep ->
               if not (String.equal dep obj.name) then deps := Set.add !deps dep))
         | None -> ())
      | _ -> ()));
  !deps
;;

(** Topologically sort objects so dependencies come first. Uses Kahn's algorithm. *)
let sort_objects (structs : Ir.struct_ list) (objects : Ir.object_ list) : Ir.object_ list
  =
  (* Build dependency map: object name -> set of objects it depends on *)
  let dep_map =
    List.map objects ~f:(fun obj -> obj.name, get_object_dependencies structs obj)
    |> Map.of_alist_exn (module String)
  in
  (* Build reverse dependency map: object name -> set of objects that depend on it *)
  let rdep_map =
    let init =
      List.map objects ~f:(fun obj -> obj.name, Set.empty (module String))
      |> Map.of_alist_exn (module String)
    in
    Map.fold dep_map ~init ~f:(fun ~key:obj ~data:deps acc ->
      Set.fold deps ~init:acc ~f:(fun acc dep ->
        Map.update acc dep ~f:(function
          | None -> Set.singleton (module String) obj
          | Some s -> Set.add s obj)))
  in
  (* Kahn's algorithm for topological sort *)
  let in_degree =
    Map.map dep_map ~f:(fun deps ->
      (* Only count deps that are in our object list *)
      Set.count deps ~f:(fun d -> Map.mem dep_map d))
  in
  let queue =
    Map.filter in_degree ~f:(fun degree -> degree = 0) |> Map.keys |> Queue.of_list
  in
  let in_degree = ref in_degree in
  let result = ref [] in
  while not (Queue.is_empty queue) do
    let obj_name = Queue.dequeue_exn queue in
    result := obj_name :: !result;
    (* Decrease in-degree of dependents *)
    let dependents =
      Map.find rdep_map obj_name |> Option.value ~default:(Set.empty (module String))
    in
    Set.iter dependents ~f:(fun dependent ->
      in_degree
      := Map.update !in_degree dependent ~f:(function
           | None -> 0
           | Some d -> d - 1);
      if Map.find_exn !in_degree dependent = 0 then Queue.enqueue queue dependent)
  done;
  (* Return objects in sorted order *)
  let order_map =
    List.rev !result
    |> List.mapi ~f:(fun i name -> name, i)
    |> Map.of_alist_exn (module String)
  in
  List.sort objects ~compare:(fun a b ->
    let a_order = Map.find order_map a.name |> Option.value ~default:999 in
    let b_order = Map.find order_map b.name |> Option.value ~default:999 in
    Int.compare a_order b_order)
;;

(** Collect all entry structs (structs that appear in arrays within other structs).
    Returns a deduplicated list of (entry_struct, nested_structs) pairs. *)
let collect_entry_structs (api : Ir.api) : (Ir.struct_ * Ir.struct_ list) list =
  let entry_struct_names =
    List.concat_map api.structs ~f:(fun struct_ ->
      List.filter_map struct_.members ~f:(fun member ->
        member_is_array_of_structs member.type_))
    |> List.dedup_and_sort ~compare:String.compare
  in
  List.filter_map entry_struct_names ~f:(fun name ->
    match List.find api.structs ~f:(fun s -> String.equal s.name name) with
    | Some entry_struct ->
      (* Find nested structs within this entry struct *)
      let nested =
        List.filter_map entry_struct.members ~f:(fun member ->
          match member_is_nested_struct member.type_ with
          | Some nested_name ->
            List.find api.structs ~f:(fun s -> String.equal s.name nested_name)
          | None -> None)
      in
      Some (entry_struct, nested)
    | None -> None)
;;

(** Generate auto-generated ML methods for a special object (one that is partially
    hand-written). Returns (output_struct_types, methods) as strings. *)
let gen_special_object_auto_methods (structs : Ir.struct_ list) (obj : Ir.object_)
  : string * string
  =
  let methods_to_generate =
    List.filter obj.methods ~f:(fun method_ ->
      (not (Config.is_manual ~object_name:obj.name ~method_name:method_.name))
      && not (Config.is_skipped ~object_name:obj.name ~method_name:method_.name))
  in
  (* Collect output struct types from methods that will be auto-generated *)
  let output_struct_types =
    List.filter_map methods_to_generate ~f:(fun method_ ->
      match method_has_output_struct_arg structs method_ with
      | Some (_arg, struct_) -> Some (gen_output_struct_record_type struct_)
      | None -> None)
    |> List.dedup_and_sort ~compare:String.compare
    |> String.concat ~sep:"\n"
  in
  let methods =
    List.filter_map methods_to_generate ~f:(fun method_ ->
      gen_ml_method structs obj method_)
    |> String.concat ~sep:""
  in
  output_struct_types, methods
;;

(** Generate auto-generated MLI signatures for a special object. Returns
    (output_struct_types, methods). *)
let gen_special_object_auto_methods_mli (structs : Ir.struct_ list) (obj : Ir.object_)
  : string * string
  =
  let methods_to_generate =
    List.filter obj.methods ~f:(fun method_ ->
      (not (Config.is_manual ~object_name:obj.name ~method_name:method_.name))
      && not (Config.is_skipped ~object_name:obj.name ~method_name:method_.name))
  in
  (* Collect output struct types from methods that will be auto-generated *)
  let output_struct_types =
    List.filter_map methods_to_generate ~f:(fun method_ ->
      match method_has_output_struct_arg structs method_ with
      | Some (_arg, struct_) -> Some (gen_output_struct_record_type struct_)
      | None -> None)
    |> List.dedup_and_sort ~compare:String.compare
    |> String.concat ~sep:"\n"
  in
  let methods =
    List.filter_map methods_to_generate ~f:(fun method_ ->
      gen_mli_method structs obj method_)
    |> String.concat ~sep:""
  in
  output_struct_types, methods
;;

(** Generate all high-level OCaml code *)
let gen_ml (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - high-level OCaml bindings *)\n\n" in
  let enums = List.map api.enums ~f:gen_ml_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_ml_bitflag |> String.concat ~sep:"\n" in
  (* Generate entry struct modules (for array-of-struct parameters) *)
  let entry_struct_modules =
    collect_entry_structs api
    |> List.map ~f:(fun (entry_struct, _nested) ->
      gen_entry_struct_module api.structs entry_struct)
    |> String.concat ~sep:"\n"
  in
  (* Filter out objects we handle specially *)
  let special_objects = [ "instance"; "adapter"; "device"; "queue" ] in
  let regular_objects =
    List.filter api.objects ~f:(fun obj ->
      not (List.mem special_objects obj.name ~equal:String.equal))
  in
  let objects =
    regular_objects
    |> sort_objects api.structs
    |> List.map ~f:(gen_ml_object api.structs)
    |> String.concat ~sep:"\n"
  in
  (* Generate auto-generated methods for Device *)
  let device_output_types, device_auto_methods =
    match List.find api.objects ~f:(fun obj -> String.equal obj.name "device") with
    | Some device_obj -> gen_special_object_auto_methods api.structs device_obj
    | None -> "", ""
  in
  (* Adapter module *)
  let adapter_module_prefix =
    {|module Adapter_info = struct
  type t =
    { vendor : string
    ; architecture : string
    ; device : string
    ; description : string
    ; backend_type : Backend_type.t
    ; adapter_type : Adapter_type.t
    }

  let of_low (info : Wgpu_low.adapter_info) : t =
    { vendor = info.vendor
    ; architecture = info.architecture
    ; device = info.device
    ; description = info.description
    ; backend_type = Backend_type.of_int info.backend_type
    ; adapter_type = Adapter_type.of_int info.adapter_type
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

  let create_shader_module t ?(label = "") ~wgsl () =
    (* Create the WGSL source extension struct *)
    let wgsl_source = Wgpu_low.Shader_source_wgsl.shader_source_WGSL_create () in
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_set_code wgsl_source wgsl;
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_set_chain_stype wgsl_source (S_type.to_int S_type.Shader_source_wgsl);
    (* Create the shader module descriptor and chain the extension *)
    let desc = Wgpu_low.Shader_module_descriptor.shader_module_descriptor_create () in
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_label desc label;
    let chained = Wgpu_low.Shader_source_wgsl.shader_source_WGSL_as_chained wgsl_source in
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_next_in_chain desc chained;
    (* Create the shader module *)
    let shader = Wgpu_low.device_create_shader_module t.handle desc in
    (* Free the descriptor structs *)
    Wgpu_low.Shader_module_descriptor.shader_module_descriptor_free desc;
    Wgpu_low.Shader_source_wgsl.shader_source_WGSL_free wgsl_source;
    ({ Shader_module.handle = shader } : Shader_module.t)

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

  let create_compute_pipeline t ?(label = "") ~layout ~module_ ~entry_point () =
    let stage_desc = Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_create () in
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_module stage_desc module_.Shader_module.handle;
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_entry_point stage_desc entry_point;
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_constants stage_desc [||];
    let desc = Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_create () in
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_label desc label;
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_layout desc layout.Pipeline_layout.handle;
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_compute desc stage_desc;
    let pipeline = Wgpu_low.device_create_compute_pipeline t.handle desc in
    Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_free stage_desc;
    Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_free desc;
    ({ Compute_pipeline.handle = pipeline } : Compute_pipeline.t)

  let create_render_pipeline t ?(label = "") ~shader_module ~vertex_entry_point
      ~fragment_entry_point ~color_format
      ?(topology = Primitive_topology.Triangle_list)
      ?(front_face = Front_face.Ccw)
      ?(cull_mode = Cull_mode.None)
      ?(blend : (Blend_factor.t * Blend_factor.t * Blend_operation.t *
                 Blend_factor.t * Blend_factor.t * Blend_operation.t) option)
      ?(write_mask = [ Color_write_mask.All ])
      () =
    let blend_enabled, color_src, color_dst, color_op, alpha_src, alpha_dst, alpha_op =
      match blend with
      | None -> false, Blend_factor.One, Blend_factor.Zero, Blend_operation.Add,
                       Blend_factor.One, Blend_factor.Zero, Blend_operation.Add
      | Some (cs, cd, co, as_, ad, ao) -> true, cs, cd, co, as_, ad, ao
    in
    let pipeline = Wgpu_low.device_create_render_pipeline_full t.handle
      label shader_module.Shader_module.handle vertex_entry_point
      fragment_entry_point (Texture_format.to_int color_format)
      (Primitive_topology.to_int topology)
      (Front_face.to_int front_face)
      (Cull_mode.to_int cull_mode)
      blend_enabled
      (Blend_factor.to_int color_src) (Blend_factor.to_int color_dst)
      (Blend_operation.to_int color_op)
      (Blend_factor.to_int alpha_src) (Blend_factor.to_int alpha_dst)
      (Blend_operation.to_int alpha_op)
      (Color_write_mask.list_to_int write_mask) in
    ({ Render_pipeline.handle = pipeline } : Render_pipeline.t)

  let create_bind_group_layout_for_storage_buffer t ?(label = "") ~binding ?(read_only = false) () =
    let layout = Wgpu_low.device_create_bind_group_layout_storage t.handle
      label binding read_only in
    ({ Bind_group_layout.handle = layout } : Bind_group_layout.t)

  (* AUTO-GENERATED DEVICE METHODS INJECTED HERE *)
|}
  in
  let adapter_module_suffix =
    {|
  let poll t ?(wait = false) () = Wgpu_low.device_poll t.handle wait
end

module Adapter = struct
  type t = { handle : Wgpu_low.adapter }

  let get_info t = Adapter_info.of_low (Wgpu_low.adapter_get_info t.handle)
  let release t = Wgpu_low.adapter_release t.handle
  let request_device t =
    let device = Wgpu_low.adapter_request_device_sync t.handle in
    { Device.handle = device }
  let has_feature t ~feature = Wgpu_low.adapter_has_feature t.handle (Feature_name.to_int feature)
end
|}
  in
  let adapter_module =
    adapter_module_prefix
    ^ device_output_types
    ^ "\n"
    ^ device_auto_methods
    ^ adapter_module_suffix
  in
  (* Instance module with create function - special handling *)
  let instance_module =
    {|module Instance = struct
  type t = { handle : Wgpu_low.instance }

  let create () = { handle = Wgpu_low.create_instance () }
  let release t = Wgpu_low.instance_release t.handle

  let request_adapter t
      ?(power_preference = Power_preference.Undefined)
      ?(backend_type = Backend_type.Undefined)
      () =
    let adapter = Wgpu_low.instance_request_adapter_sync t.handle
      (Power_preference.to_int power_preference)
      (Backend_type.to_int backend_type) in
    { Adapter.handle = adapter }
end

(* Convenience functions for methods that take complex descriptors *)

let begin_compute_pass (encoder : Command_encoder.t) ?(label = "") () =
  let desc = Wgpu_low.Compute_pass_descriptor.compute_pass_descriptor_create () in
  Wgpu_low.Compute_pass_descriptor.compute_pass_descriptor_set_label desc label;
  let pass = Wgpu_low.command_encoder_begin_compute_pass encoder.handle desc in
  Wgpu_low.Compute_pass_descriptor.compute_pass_descriptor_free desc;
  ({ Compute_pass_encoder.handle = pass } : Compute_pass_encoder.t)

let begin_render_pass (encoder : Command_encoder.t) ?(label = "") ~color_view
    ?(load_op = Load_op.Clear) ?(store_op = Store_op.Store)
    ~clear_color () =
  let (r, g, b, a) = clear_color in
  let pass = Wgpu_low.command_encoder_begin_render_pass_configurable encoder.handle
    label color_view.Texture_view.handle
    (Load_op.to_int load_op) (Store_op.to_int store_op)
    r g b a in
  ({ Render_pass_encoder.handle = pass } : Render_pass_encoder.t)

let finish (encoder : Command_encoder.t) ?(label = "") () =
  Command_encoder.finish encoder ~label ()

let set_bind_group (pass : Compute_pass_encoder.t) ~index ~bind_group =
  Compute_pass_encoder.set_bind_group pass ~group_index:index ~group:bind_group ~dynamic_offsets:[]

let set_bind_group_render (pass : Render_pass_encoder.t) ~index ~bind_group =
  Render_pass_encoder.set_bind_group pass ~group_index:index ~group:bind_group ~dynamic_offsets:[]

let copy_texture_to_buffer (encoder : Command_encoder.t) ~texture ~buffer ~size ~bytes_per_row () =
  let (width, height) = size in
  Command_encoder.copy_texture_to_buffer encoder
    ~source_texture:texture
    ~source_mip_level:0
    ~source_origin_x:0
    ~source_origin_y:0
    ~source_origin_z:0
    ~source_aspect:Texture_aspect.All
    ~destination_layout_offset:0L
    ~destination_layout_bytes_per_row:bytes_per_row
    ~destination_layout_rows_per_image:height
    ~destination_buffer:buffer
    ~copy_size_width:width
    ~copy_size_height:height
    ~copy_size_depth_or_array_layers:1
    ()

let map_buffer (buffer : Buffer.t) ~mode ~offset ~size =
  ignore (Wgpu_low.buffer_map_sync buffer.handle (Map_mode.list_to_int mode) offset size : int)

let get_mapped_range (buffer : Buffer.t) ~offset ~size =
  Wgpu_low.buffer_get_mapped_range_bigarray buffer.handle offset size

let get_const_mapped_range (buffer : Buffer.t) ~offset ~size =
  Wgpu_low.buffer_get_const_mapped_range_bigarray buffer.handle offset size

let create_texture_view (texture : Texture.t) ?(label = "")
    ?(format = Texture_format.Undefined)
    ?(dimension = Texture_view_dimension.Undefined)
    ?(aspect = Texture_aspect.All)
    ?(base_mip_level = 0)
    ?(mip_level_count = 0xFFFFFFFF) (* WGPU_MIP_LEVEL_COUNT_UNDEFINED *)
    ?(base_array_layer = 0)
    ?(array_layer_count = 0xFFFFFFFF) (* WGPU_ARRAY_LAYER_COUNT_UNDEFINED *)
    () =
  let view = Wgpu_low.texture_create_view_configurable texture.handle label
    (Texture_format.to_int format)
    (Texture_view_dimension.to_int dimension)
    (Texture_aspect.to_int aspect)
    base_mip_level mip_level_count
    base_array_layer array_layer_count in
  ({ Texture_view.handle = view } : Texture_view.t)
|}
  in
  String.concat
    [ header
    ; enums
    ; bitflags
    ; objects
    ; entry_struct_modules
    ; adapter_module
    ; instance_module
    ]
;;

(** Generate all high-level OCaml interface *)
let gen_mli (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - high-level OCaml interface *)\n\n" in
  let enums = List.map api.enums ~f:gen_mli_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_mli_bitflag |> String.concat ~sep:"\n" in
  (* Generate entry struct module signatures (for array-of-struct parameters) *)
  let entry_struct_modules =
    collect_entry_structs api
    |> List.map ~f:(fun (entry_struct, _nested) ->
      gen_entry_struct_module_mli api.structs entry_struct)
    |> String.concat ~sep:"\n"
  in
  (* Generate auto-generated method signatures for Device *)
  let device_output_types_mli, device_auto_methods_mli =
    match List.find api.objects ~f:(fun obj -> String.equal obj.name "device") with
    | Some device_obj -> gen_special_object_auto_methods_mli api.structs device_obj
    | None -> "", ""
  in
  (* Filter out objects we handle specially *)
  let special_objects = [ "instance"; "adapter"; "device"; "queue" ] in
  let regular_objects =
    List.filter api.objects ~f:(fun obj ->
      not (List.mem special_objects obj.name ~equal:String.equal))
  in
  let objects =
    regular_objects
    |> sort_objects api.structs
    |> List.map ~f:(gen_mli_object api.structs)
    |> String.concat ~sep:"\n"
  in
  (* Adapter module *)
  let adapter_module_prefix =
    {|module Adapter_info : sig
  type t =
    { vendor : string
    ; architecture : string
    ; device : string
    ; description : string
    ; backend_type : Backend_type.t
    ; adapter_type : Adapter_type.t
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

  (** Create a shader module from WGSL source *)
  val create_shader_module : t -> ?label:string -> wgsl:string -> unit -> Shader_module.t

  (** Create a texture *)
  val create_texture : t -> ?label:string -> size:(int * int * int) ->
    format:Texture_format.t -> usage:Texture_usage.t list ->
    ?dimension:Texture_dimension.t -> ?mip_level_count:int -> ?sample_count:int ->
    unit -> Texture.t

  (** Create a compute pipeline *)
  val create_compute_pipeline : t -> ?label:string -> layout:Pipeline_layout.t ->
    module_:Shader_module.t -> entry_point:string -> unit -> Compute_pipeline.t

  (** Create a render pipeline (uses single shader module for vertex and fragment).
      The [blend] parameter is a tuple of (color_src, color_dst, color_op, alpha_src, alpha_dst, alpha_op). *)
  val create_render_pipeline : t -> ?label:string -> shader_module:Shader_module.t ->
    vertex_entry_point:string -> fragment_entry_point:string ->
    color_format:Texture_format.t ->
    ?topology:Primitive_topology.t -> ?front_face:Front_face.t ->
    ?cull_mode:Cull_mode.t ->
    ?blend:(Blend_factor.t * Blend_factor.t * Blend_operation.t *
            Blend_factor.t * Blend_factor.t * Blend_operation.t) ->
    ?write_mask:Color_write_mask.t list ->
    unit -> Render_pipeline.t

  (** Create a bind group layout for a single storage buffer *)
  val create_bind_group_layout_for_storage_buffer : t -> ?label:string -> binding:int ->
    ?read_only:bool -> unit -> Bind_group_layout.t

  (* AUTO-GENERATED DEVICE METHOD SIGNATURES INJECTED HERE *)
|}
  in
  let adapter_module_suffix =
    {|
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
  let adapter_module =
    adapter_module_prefix
    ^ device_output_types_mli
    ^ "\n"
    ^ device_auto_methods_mli
    ^ adapter_module_suffix
  in
  (* Instance module interface - special handling *)
  let instance_module =
    {|module Instance : sig
  type t

  val create : unit -> t
  val release : t -> unit
  val request_adapter : t -> ?power_preference:Power_preference.t ->
    ?backend_type:Backend_type.t -> unit -> Adapter.t
end

(** Begin a compute pass on a command encoder *)
val begin_compute_pass : Command_encoder.t -> ?label:string -> unit -> Compute_pass_encoder.t

(** Begin a render pass on a command encoder with a single color attachment *)
val begin_render_pass : Command_encoder.t -> ?label:string -> color_view:Texture_view.t ->
  ?load_op:Load_op.t -> ?store_op:Store_op.t ->
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
val create_texture_view : Texture.t -> ?label:string ->
  ?format:Texture_format.t -> ?dimension:Texture_view_dimension.t ->
  ?aspect:Texture_aspect.t -> ?base_mip_level:int -> ?mip_level_count:int ->
  ?base_array_layer:int -> ?array_layer_count:int -> unit -> Texture_view.t
|}
  in
  String.concat
    [ header
    ; enums
    ; bitflags
    ; objects
    ; entry_struct_modules
    ; adapter_module
    ; instance_module
    ]
;;

(** Validate that all non-auto-generated methods are accounted for. Returns a list of
    error messages for unaccounted methods. *)
let validate_method_coverage (api : Ir.api) : string list =
  let errors = ref [] in
  List.iter api.objects ~f:(fun obj ->
    List.iter obj.methods ~f:(fun method_ ->
      if not (method_is_high_level api.structs method_)
      then
        if (* This method isn't auto-generated, check if it's accounted for *)
           not (Config.is_accounted_for ~object_name:obj.name ~method_name:method_.name)
        then (
          let reason =
            if method_is_async method_
            then "async (has callback)"
            else (
              let non_simple_args =
                List.filter method_.args ~f:(fun arg ->
                  match arg.type_ with
                  | Struct name ->
                    (* Check if struct is simple *)
                    not (is_simple_struct api.structs name)
                  | _ -> not (is_simple_arg_type arg.type_))
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
    eprintf "Config.method_config:\n\n";
    List.iter errors ~f:(fun msg -> eprintf "  %s\n" msg);
    eprintf
      "\n\
       Please add these methods to Config.method_config in codegen/config.ml as either:\n\
      \  - Manual { reason = \"...\" } (if you will implement them manually)\n\
      \  - Skipped { reason = \"...\" } (if they should not be exposed)\n\n";
    failwith "Unaccounted methods in high-level API")
;;
