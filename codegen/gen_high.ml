open! Core

(** Generate high-level idiomatic OCaml bindings *)

(** Output mode for code generation *)
type output_mode =
  | Implementation (** Generate .ml implementation *)
  | Interface (** Generate .mli interface *)

(** Record types for code generation results *)

(** A parameter collected from a struct for function signature generation *)
type struct_parameter = {
  param_name : string;
  (** The OCaml parameter name *)
  member : Ir.struct_member;
  (** The struct member definition *)
  is_optional : bool;
  (** Whether this parameter is optional *)
  nested_var : string option;
  (** If this comes from a nested struct, the variable name for that nested struct *)
}

(** Result of generating struct creation code *)
type struct_creation_result = {
  created_structs : (string * Ir.struct_) list;
  (** List of (variable_name, struct_definition) pairs for all created structs *)
  code_lines : string list;
  (** OCaml code lines that create the structs *)
}

(** Result of code generation that includes resources to free *)
type code_with_cleanup = {
  code_lines : string list;
  (** The generated code *)
  structs_to_free : (string * Ir.struct_) list;
  (** List of (variable_name, struct_def) pairs for structs that need freeing *)
}

(** Result of inline struct conversion *)
type inline_struct_conversion = {
  create_code : string list;
  (** Code to create the C struct *)
  set_code : string list;
  (** Code to set all fields on the struct *)
  structs_to_free : (string * Ir.struct_) list;
  (** List of (var_name, struct_def) pairs for later freeing *)
}

(** Read a template file from the templates directory *)
let read_template (path : string) : string =
  let template_path = "../codegen/templates/" ^ path in
  In_channel.read_all template_path
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
let ocaml_module_name (name : string) : string = Type_mapping.ocaml_module_name name

(** Convert C name conventions (e.g., discrete_GPU -> Discrete_gpu) *)
let normalize_enum_entry_name (name : string) : string = Names.normalize_enum_entry_name name

(** Escape OCaml keywords by adding underscore suffix *)
let escape_keyword (name : string) : string = Names.escape_keyword name

(** Check if a method uses callbacks (async) *)
let method_is_async (method_ : Ir.method_) : bool = Option.is_some method_.callback

(** Check if a type is flat (primitive, enum, bitflag, or object) - no nested structs *)
let rec is_flat_member_type (type_ref : Ir.type_ref) : bool =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Optional inner -> is_flat_member_type inner
  | Struct _ -> false
  | Callback _ -> false
  | Array { elem; _ } -> is_flat_member_type elem (* Arrays of flat types are OK *)
  | Pointer { inner = Array { elem; _ }; _ } ->
    (* Pointer to array is just an array passed by reference *)
    is_flat_member_type elem
  | Pointer _ -> false
;;

(** Check if a type is flat, allowing nested structs that are themselves flat. Uses
    visited set to prevent infinite recursion. *)
let rec is_flat_member_type_with_nested
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
  | Optional inner -> is_flat_member_type_with_nested structs visited inner
  | Struct name ->
    (* Check if the nested struct is simple (and not already being visited) *)
    if Set.mem visited name
    then false (* Circular reference *)
    else is_auto_generable_struct_aux structs (Set.add visited name) name
  | Callback _ -> false
  | Array { elem; _ } -> is_flat_member_type_with_nested structs visited elem
  | Pointer { inner = Array { elem; _ }; _ } ->
    (* Pointer to array is just an array passed by reference *)
    is_flat_member_type_with_nested structs visited elem
  | Pointer _ -> false

(** Auxiliary function to check if a struct is auto-generable, with visited tracking *)
and is_auto_generable_struct_aux
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
      is_flat_member_type_with_nested structs visited member.type_)
;;

(** Check if a struct has only flat members (allowing nested flat structs) and is an
    input struct, making it auto-generable *)
let is_auto_generable_struct (structs : Ir.struct_ list) (struct_name : string) : bool =
  is_auto_generable_struct_aux structs (Set.empty (module String)) struct_name
;;

(** Check if a member type contains a nested struct *)
let get_inline_struct_name (type_ref : Ir.type_ref) : string option =
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
let get_array_element_structs (structs : Ir.struct_ list) (struct_ : Ir.struct_)
  : Ir.struct_ list
  =
  List.filter_map struct_.members ~f:(fun member ->
    match member_is_array_of_structs member.type_ with
    | Some name -> List.find structs ~f:(fun s -> String.equal s.name name)
    | None -> None)
;;

(** Collect all nested struct members from a struct, recursively. Returns a list of (path,
    struct_def) pairs where path is the variable name path. *)
let rec collect_inline_structs_recursive
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  : (string * Ir.struct_) list
  =
  List.concat_map struct_.members ~f:(fun member ->
    match get_inline_struct_name member.type_ with
    | Some nested_name ->
      (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
       | None -> []
       | Some inline_struct ->
         let nested_var = prefix ^ "_" ^ member.name ^ "_nested" in
         (* Add this inline struct and any inline structs within it *)
         (nested_var, inline_struct)
         :: collect_inline_structs_recursive structs nested_var inline_struct)
    | None -> [])
;;

(** Check if an argument type can be directly converted (without struct handling) *)
let rec is_directly_convertible_arg (type_ref : Ir.type_ref) : bool =
  match type_ref with
  | Primitive _ -> true
  | Enum _ -> true
  | Bitflag _ -> true
  | Object _ -> true
  | Optional inner -> is_directly_convertible_arg inner
  | Struct _ -> false (* Structs handled separately *)
  | Callback _ -> false
  | Array { elem; _ } -> is_directly_convertible_arg elem (* Arrays of directly convertible types are OK *)
  | Pointer _ -> false
;;

(** Get all auto-generable struct parameters from a method (input structs only) *)
let get_auto_generable_struct_params (structs : Ir.struct_ list) (method_ : Ir.method_)
  : (Ir.arg * Ir.struct_) list
  =
  List.filter_map method_.args ~f:(fun arg ->
    match arg.type_, arg.pointer with
    | Struct name, (Some `Immutable | None) ->
      if is_auto_generable_struct structs name
      then
        List.find structs ~f:(fun s -> String.equal s.name name)
        |> Option.map ~f:(fun s -> arg, s)
      else None
    | _ -> None)
;;

(** Check if a method has at least one struct parameter and all structs are auto-generable
    input structs *)
let method_has_auto_generable_struct_params (structs : Ir.struct_ list) (method_ : Ir.method_)
  : bool
  =
  let struct_parameters =
    List.filter method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> true
      | _ -> false)
  in
  if List.is_empty struct_parameters
  then false
  else
    List.for_all struct_parameters ~f:(fun arg ->
      match arg.type_, arg.pointer with
      | Struct name, (Some `Immutable | None) -> is_auto_generable_struct structs name
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
    && List.for_all struct_.members ~f:(fun member -> is_flat_member_type member.type_)
;;

(** Check if a method has exactly one output struct argument (mutable pointer to struct) *)
let method_has_output_struct_arg (structs : Ir.struct_ list) (method_ : Ir.method_)
  : (Ir.arg * Ir.struct_) option
  =
  let output_struct_parameters =
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
  match output_struct_parameters with
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
      List.for_all method_.args ~f:(fun arg -> is_directly_convertible_arg arg.type_)
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
        List.for_all method_.args ~f:(fun arg -> is_directly_convertible_arg arg.type_)
      in
      if all_simple
      then true
      else (
        (* Check if all struct parameters are auto-generable input structs, with other parameters also directly convertible *)
        let non_struct_parameters_are_directly_convertible =
          List.for_all method_.args ~f:(fun arg ->
            match arg.type_ with
            | Struct _ -> true (* will check separately *)
            | _ -> is_directly_convertible_arg arg.type_)
        in
        if non_struct_parameters_are_directly_convertible && method_has_auto_generable_struct_params structs method_
        then true
        else (
          (* Check if there's an output struct arg *)
          match method_has_output_struct_arg structs method_ with
          | Some _ -> non_struct_parameters_are_directly_convertible
          | None -> false))))
;;

(** Get high-level OCaml type for a type_ref (for arguments) *)
let high_level_arg_type (type_ref : Ir.type_ref) : string =
  Type_mapping.type_string ~context:Ocaml_high_level_arg type_ref
;;

(** Get high-level OCaml type for return values *)
let high_level_return_type (type_ref : Ir.type_ref) : string =
  Type_mapping.type_string ~context:Ocaml_high_level_return type_ref
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
  : struct_parameter list
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
      [ { param_name; member; is_optional; nested_var } ]
    | None ->
      (* Check for direct nested struct *)
      (match get_inline_struct_name member.type_ with
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
         [ { param_name; member; is_optional; nested_var } ]))
;;

(** Generate code to create a struct and all its nested structs *)
let rec generate_struct_creates
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  (var_name : string)
  : struct_creation_result
  =
  let struct_module = ocaml_module_name struct_.name in
  let create_line =
    sprintf "let %s = Wgpu_low.%s.%s_create () in" var_name struct_module struct_.name
  in
  (* Collect nested struct creates *)
  let nested_results =
    List.filter_map struct_.members ~f:(fun member ->
      match get_inline_struct_name member.type_ with
      | Some nested_name ->
        (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
         | None -> None
         | Some nested_struct ->
           let nested_var = prefix ^ member.name ^ "_nested" in
           let nested_prefix = prefix ^ member.name ^ "_" in
           Some (generate_struct_creates structs nested_prefix nested_struct nested_var))
      | None -> None)
  in
  let all_created_structs, all_code_lines =
    List.fold
      nested_results
      ~init:([], [])
      ~f:(fun (vars, creates) result ->
        vars @ result.created_structs, creates @ result.code_lines)
  in
  { created_structs = (var_name, struct_) :: all_created_structs
  ; code_lines = all_code_lines @ [ create_line ]
  }
;;

(** Generate code to convert a nested struct record field to a C struct *)
let gen_inline_struct_conversion
  (_structs : Ir.struct_ list)
  (entry_var : string)
  (field_name : string)
  (inline_struct : Ir.struct_)
  (parent_var : string)
  : inline_struct_conversion
  =
  let nested_module = ocaml_module_name inline_struct.name in
  let nested_var = parent_var ^ "_" ^ field_name in
  (* Create the nested struct *)
  let create_code =
    [ sprintf
        "let %s = Wgpu_low.%s.%s_create () in"
        nested_var
        nested_module
        inline_struct.name
    ]
  in
  (* Set fields from the record *)
  let set_code =
    List.filter_map inline_struct.members ~f:(fun member ->
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
             inline_struct.name
             member.name
             nested_var
             converted)))
  in
  { create_code; set_code; structs_to_free = [ nested_var, inline_struct ] }
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

(** Generate code to convert a list of entry struct records to C structs *)
let generate_array_of_structs_conversion
  (structs : Ir.struct_ list)
  (param_name : string)
  (array_element_struct : Ir.struct_)
  (parent_var : string)
  (parent_struct : Ir.struct_)
  (member_name : string)
  : code_with_cleanup
  =
  let array_element_module = ocaml_module_name array_element_struct.name in
  let parent_module = ocaml_module_name parent_struct.name in
  let entries_var = param_name ^ "_structs" in
  let array_var = param_name ^ "_array" in
  (* Generate code to convert each entry record to a C struct *)
  let loop_code =
    [ sprintf "let %s = List.map (fun (entry : %s.t) ->" entries_var array_element_module
    ]
    @ [ sprintf
          "    let e = Wgpu_low.%s.%s_create () in"
          array_element_module
          array_element_struct.name
      ]
    @ List.concat_map array_element_struct.members ~f:(fun member ->
      if String.equal member.name "nextInChain"
      then []
      else (
        match get_inline_struct_name member.type_ with
        | Some nested_name ->
          (* Nested struct - wrap in Option.iter *)
          (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
           | None -> []
           | Some inline_struct ->
             let nested_module = ocaml_module_name inline_struct.name in
             let nested_var = "nested_" ^ member.name in
             [ sprintf "    (match entry.%s with" (escape_keyword member.name)
             ; sprintf "     | Some %s_rec ->" member.name
             ; sprintf
                 "       let %s = Wgpu_low.%s.%s_create () in"
                 nested_var
                 nested_module
                 inline_struct.name
             ]
             @ List.filter_map inline_struct.members ~f:(fun nm ->
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
                      inline_struct.name
                      nm.name
                      nested_var
                      converted)))
             @ [ sprintf
                   "       Wgpu_low.%s.%s_set_%s e %s"
                   array_element_module
                   array_element_struct.name
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
              array_element_module
              array_element_struct.name
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
  { code_lines = loop_code; structs_to_free = [ entries_var, array_element_struct ] }
;;

(** Generate code to set fields on a struct, including assigning nested structs. prefix is
    the parameter prefix for this struct. *)
let rec generate_struct_sets
  (structs : Ir.struct_ list)
  (prefix : string)
  (struct_ : Ir.struct_)
  (var_name : string)
  : code_with_cleanup
  =
  let struct_module = ocaml_module_name struct_.name in
  let results =
    List.map struct_.members ~f:(fun member ->
      (* First check for array-of-structs *)
      match member_is_array_of_structs member.type_ with
      | Some entry_name ->
        (match List.find structs ~f:(fun s -> String.equal s.name entry_name) with
         | Some array_element_struct ->
           let param_name = escape_keyword (prefix ^ member.name) in
           generate_array_of_structs_conversion
             structs
             param_name
             array_element_struct
             var_name
             struct_
             member.name
         | None -> { code_lines = []; structs_to_free = [] })
      | None ->
        (* Check for direct nested struct *)
        (match get_inline_struct_name member.type_ with
         | Some nested_name ->
           (* First, recursively set fields on the nested struct *)
           (match List.find structs ~f:(fun s -> String.equal s.name nested_name) with
            | None -> { code_lines = []; structs_to_free = [] }
            | Some nested_struct ->
              let nested_var = prefix ^ member.name ^ "_nested" in
              let nested_prefix = prefix ^ member.name ^ "_" in
              let nested_result =
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
              { code_lines = nested_result.code_lines @ [ set_nested ]
              ; structs_to_free = nested_result.structs_to_free
              })
         | None ->
           (* Regular member - set the value *)
           let param_name = escape_keyword (prefix ^ member.name) in
           let converted = member_to_low_level param_name member.type_ in
           { code_lines =
               [ sprintf
                   "Wgpu_low.%s.%s_set_%s %s %s;"
                   struct_module
                   struct_.name
                   member.name
                   var_name
                   converted
               ]
           ; structs_to_free = []
           }))
  in
  let code = List.concat_map results ~f:(fun r -> r.code_lines) in
  let vars = List.concat_map results ~f:(fun r -> r.structs_to_free) in
  { code_lines = code; structs_to_free = vars }
;;

(** Generate ML implementation for a method with one or more struct parameters *)
let gen_ml_method_with_structs
  (structs : Ir.struct_ list)
  (obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_parameters : (Ir.arg * Ir.struct_) list)
  : string
  =
  let method_name = escape_keyword method_.name in
  let use_prefix = List.length struct_parameters > 1 in
  (* Get non-struct parameters *)
  let non_struct_parameters =
    List.filter method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> false
      | _ -> true)
  in
  (* Build parameter list from all struct members + non-struct parameters (including nested) *)
  let struct_params =
    List.concat_map struct_parameters ~f:(fun (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      collect_struct_params structs base_prefix struct_ None)
  in
  let non_struct_params =
    List.map non_struct_parameters ~f:(fun arg -> escape_keyword arg.name, arg, arg.optional)
  in
  (* Build function signature *)
  let param_strs =
    List.filter_map struct_params ~f:(fun p ->
      if p.is_optional
      then Some (sprintf "?(%s = %s)" p.param_name (default_value_for_type p.member.type_))
      else Some (sprintf "~%s" p.param_name))
    @ List.filter_map non_struct_params ~f:(fun (name, _arg, is_opt) ->
      if is_opt then Some (sprintf "?%s" name) else Some (sprintf "~%s" name))
  in
  let param_list = "t " ^ String.concat ~sep:" " param_strs ^ " ()" in
  (* Generate struct creation for each struct parameter (including nested structs) *)
  let all_struct_vars, create_structs_lists =
    List.fold struct_parameters ~init:([], []) ~f:(fun (vars, creates) (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      let desc_var = "desc_" ^ arg.name in
      let result = generate_struct_creates structs base_prefix struct_ desc_var in
      vars @ result.created_structs, creates @ result.code_lines)
  in
  let create_structs = create_structs_lists in
  (* Generate field setting for each struct (including nested structs) *)
  let set_fields, array_element_struct_lists =
    List.fold struct_parameters ~init:([], []) ~f:(fun (fields, entry_lists) (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      let desc_var = "desc_" ^ arg.name in
      let result = generate_struct_sets structs base_prefix struct_ desc_var in
      fields @ result.code_lines, entry_lists @ result.structs_to_free)
  in
  (* Build the call arguments, mapping each struct parameter to its desc variable *)
  let struct_parameter_names =
    List.map struct_parameters ~f:(fun (arg, _) -> arg.name) |> Set.of_list (module String)
  in
  let call_args =
    List.map method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ when Set.mem struct_parameter_names arg.name -> "desc_" ^ arg.name
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
    List.concat_map array_element_struct_lists ~f:(fun (list_var, array_element_struct) ->
      let array_element_module = ocaml_module_name array_element_struct.name in
      [ sprintf
          "List.iter (fun e -> Wgpu_low.%s.%s_free e) %s;"
          array_element_module
          array_element_struct.name
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
  (* Get non-struct parameters that are not the output struct *)
  let non_struct_parameters =
    List.filter method_.args ~f:(fun a ->
      not
        (match a.type_ with
         | Struct _ -> true
         | _ -> false))
  in
  (* Build parameter list *)
  let param_list =
    if List.is_empty non_struct_parameters
    then "t"
    else
      "t "
      ^ String.concat
          ~sep:" "
          (List.map non_struct_parameters ~f:(fun a -> sprintf "~%s" (escape_keyword a.name)))
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
      let struct_parameters = get_auto_generable_struct_params structs method_ in
      (match struct_parameters with
       | _ :: _ ->
         (* One or more auto-generable struct parameters *)
         Some (gen_ml_method_with_structs structs obj method_ struct_parameters)
       | [] ->
         (* Original simple method generation - no struct parameters *)
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
let high_level_member_type (member : Ir.struct_member) : string =
  Type_mapping.type_string ~context:Ocaml_high_level_member member.type_

(** Get high-level OCaml type for a type_ref (for struct members) *)
let high_level_member_type_of_type (type_ref : Ir.type_ref) : string =
  Type_mapping.type_string ~context:Ocaml_high_level_member type_ref
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
let rec array_element_struct_member_type
  (_structs : Ir.struct_ list)
  (member : Ir.struct_member)
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
and gen_array_element_struct_module (structs : Ir.struct_ list) (struct_ : Ir.struct_)
  : string
  =
  let module_name = ocaml_module_name struct_.name in
  (* First, generate modules for any nested structs *)
  let nested_modules =
    List.filter_map struct_.members ~f:(fun member ->
      match get_inline_struct_name member.type_ with
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
        let field_type = array_element_struct_member_type structs member in
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
let gen_array_element_struct_module_mli (structs : Ir.struct_ list) (struct_ : Ir.struct_)
  : string
  =
  let module_name = ocaml_module_name struct_.name in
  (* First, generate module signatures for any nested structs *)
  let nested_modules =
    List.filter_map struct_.members ~f:(fun member ->
      match get_inline_struct_name member.type_ with
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
        let field_type = array_element_struct_member_type structs member in
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

(** Generate MLI signature for a method with one or more struct parameters *)
let gen_mli_method_with_structs
  (structs : Ir.struct_ list)
  (_obj : Ir.object_)
  (method_ : Ir.method_)
  (struct_parameters : (Ir.arg * Ir.struct_) list)
  : string
  =
  let method_name = escape_keyword method_.name in
  let use_prefix = List.length struct_parameters > 1 in
  (* Get non-struct parameters *)
  let non_struct_parameters =
    List.filter method_.args ~f:(fun arg ->
      match arg.type_ with
      | Struct _ -> false
      | _ -> true)
  in
  (* Build parameter types from all struct members + non-struct parameters (including nested) *)
  let struct_param_types =
    List.concat_map struct_parameters ~f:(fun (arg, struct_) ->
      let base_prefix = if use_prefix then arg.name ^ "_" else "" in
      let params = collect_struct_params structs base_prefix struct_ None in
      List.map params ~f:(fun p ->
        let type_str = high_level_member_type p.member in
        if p.is_optional
        then sprintf "?%s:%s" p.param_name type_str
        else sprintf "%s:%s" p.param_name type_str))
  in
  let non_struct_param_types =
    List.map non_struct_parameters ~f:(fun arg ->
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
  let all_params = struct_param_types @ non_struct_param_types in
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
  (* Get non-struct parameters that are not the output struct *)
  let non_struct_parameters =
    List.filter method_.args ~f:(fun a ->
      not
        (match a.type_ with
         | Struct _ -> true
         | _ -> false))
  in
  let non_struct_param_types =
    List.map non_struct_parameters ~f:(fun arg ->
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
    if List.is_empty non_struct_param_types
    then sprintf "t -> %s" return_type
    else sprintf "t -> %s -> %s" (String.concat ~sep:" -> " non_struct_param_types) return_type
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
      (* Check if this method has auto-generable struct parameters *)
      let struct_parameters = get_auto_generable_struct_params structs method_ in
      (match struct_parameters with
       | _ :: _ ->
         (* One or more auto-generable struct parameters *)
         Some (gen_mli_method_with_structs structs obj method_ struct_parameters)
       | [] ->
         (* Original simple method generation - no struct parameters *)
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
(** Generate enum module - unified implementation and interface *)
let gen_enum (mode : output_mode) (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  match mode with
  | Implementation -> sprintf "module %s = Wgpu_low.%s\n" module_name module_name
  | Interface ->
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

(** Generate ML implementation for an enum type *)
let gen_ml_enum (enum : Ir.enum) : string = gen_enum Implementation enum

(** Generate MLI interface for an enum type *)
let gen_mli_enum (enum : Ir.enum) : string = gen_enum Interface enum

(** Generate bitflag module - unified implementation and interface *)
let gen_bitflag (mode : output_mode) (bitflag : Ir.bitflag) : string =
  let module_name = ocaml_module_name bitflag.name in
  match mode with
  | Implementation -> sprintf "module %s = Wgpu_low.%s\n" module_name module_name
  | Interface ->
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

(** Generate ML implementation for a bitflag type *)
let gen_ml_bitflag (bitflag : Ir.bitflag) : string = gen_bitflag Implementation bitflag

(** Generate MLI interface for a bitflag type *)
let gen_mli_bitflag (bitflag : Ir.bitflag) : string = gen_bitflag Interface bitflag

(** Generate high-level OCaml code for an object type with methods *)
(** Generate object module - unified implementation and interface *)
let gen_object (mode : output_mode) (structs : Ir.struct_ list) (obj : Ir.object_) : string
  =
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
  match mode with
  | Implementation ->
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
  | Interface ->
    let doc_comment =
      match useful_doc obj.doc with
      | None -> ""
      | Some doc -> sprintf "  (** %s *)\n\n" doc
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

(** Generate ML implementation for an object type *)
let gen_ml_object (structs : Ir.struct_ list) (obj : Ir.object_) : string =
  gen_object Implementation structs obj
;;

(** Generate MLI interface for an object type *)
let gen_mli_object (structs : Ir.struct_ list) (obj : Ir.object_) : string =
  gen_object Interface structs obj
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
    Returns a deduplicated list of (array_element_struct, nested_structs) pairs. *)
let collect_array_element_structs (api : Ir.api) : (Ir.struct_ * Ir.struct_ list) list =
  let array_element_struct_names =
    List.concat_map api.structs ~f:(fun struct_ ->
      List.filter_map struct_.members ~f:(fun member ->
        member_is_array_of_structs member.type_))
    |> List.dedup_and_sort ~compare:String.compare
  in
  List.filter_map array_element_struct_names ~f:(fun name ->
    match List.find api.structs ~f:(fun s -> String.equal s.name name) with
    | Some array_element_struct ->
      (* Find nested structs within this array element struct *)
      let nested =
        List.filter_map array_element_struct.members ~f:(fun member ->
          match get_inline_struct_name member.type_ with
          | Some nested_name ->
            List.find api.structs ~f:(fun s -> String.equal s.name nested_name)
          | None -> None)
      in
      Some (array_element_struct, nested)
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
  let array_element_struct_modules =
    collect_array_element_structs api
    |> List.map ~f:(fun (array_element_struct, _nested) ->
      gen_array_element_struct_module api.structs array_element_struct)
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
  let adapter_module_prefix = read_template "high/adapter_module_prefix.ml" in
  let adapter_module_suffix = read_template "high/adapter_module_suffix.ml" in
  let adapter_module =
    adapter_module_prefix
    ^ device_output_types
    ^ "\n"
    ^ device_auto_methods
    ^ adapter_module_suffix
  in
  (* Instance module with create function - special handling *)
  let instance_module = read_template "high/instance_module.ml" in
  String.concat
    [ header
    ; enums
    ; bitflags
    ; objects
    ; array_element_struct_modules
    ; adapter_module
    ; instance_module
    ]
;;

(** Generate all high-level OCaml interface *)
let gen_mli (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - high-level OCaml interface *)\n\n" in
  let enums = List.map api.enums ~f:gen_mli_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_mli_bitflag |> String.concat ~sep:"\n" in
  (* Generate array element struct module signatures (for array-of-struct parameters) *)
  let array_element_struct_modules =
    collect_array_element_structs api
    |> List.map ~f:(fun (array_element_struct, _nested) ->
      gen_array_element_struct_module_mli api.structs array_element_struct)
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
  let adapter_module_prefix = read_template "high/adapter_module_prefix.mli" in
  let adapter_module_suffix = read_template "high/adapter_module_suffix.mli" in
  let adapter_module =
    adapter_module_prefix
    ^ device_output_types_mli
    ^ "\n"
    ^ device_auto_methods_mli
    ^ adapter_module_suffix
  in
  (* Instance module interface - special handling *)
  let instance_module = read_template "high/instance_module.mli" in
  String.concat
    [ header
    ; enums
    ; bitflags
    ; objects
    ; array_element_struct_modules
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
                    not (is_auto_generable_struct api.structs name)
                  | _ -> not (is_directly_convertible_arg arg.type_))
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
