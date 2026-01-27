open! Core

(** Generate low-level C stubs and OCaml external bindings *)

(** Read a template file from the templates directory *)
let read_template (path : string) : string =
  let template_path = "../codegen/templates/" ^ path in
  In_channel.read_all template_path
;;

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

(** Get the OCaml module name for a type. Lowercases everything then capitalizes only the
    first letter. e.g., "texture_format" -> "Texture_format", "extent_3D" -> "Extent_3d" *)
let ocaml_module_name (name : string) : string =
  String.lowercase name |> String.capitalize
;;

(** Convert C name conventions (e.g., discrete_GPU -> Discrete_gpu) *)
let normalize_enum_entry_name (name : string) : string =
  (* Handle special cases like GPU, CPU, ID *)
  let s = String.lowercase name in
  let s = String.capitalize s in
  (* OCaml identifiers can't start with a digit, prefix with underscore *)
  if String.length s > 0 && Char.is_digit (String.get s 0) then "N" ^ s else s
;;

(** Helper to indent lines *)
let indent_lines s =
  String.split_lines s |> List.map ~f:(fun line -> "  " ^ line) |> String.concat ~sep:"\n"
;;

(** Map IR type to C type string *)
let rec c_type_of_type_ref (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive Bool -> "bool"
  | Primitive Uint32 -> "uint32_t"
  | Primitive Uint64 -> "uint64_t"
  | Primitive Int32 -> "int32_t"
  | Primitive Int64 -> "int64_t"
  | Primitive Float32 -> "float"
  | Primitive Float64 -> "double"
  | Primitive Usize -> "size_t"
  | Primitive String -> "WGPUStringView"
  | Primitive Out_string -> "WGPUStringView"
  | Primitive String_with_default_empty -> "WGPUStringView"
  | Primitive C_void -> "void*"
  | Enum name -> c_type_name name
  | Bitflag name -> c_type_name name
  | Struct name -> c_type_name name
  | Object name -> c_type_name name
  | Callback name -> c_type_name name
  | Array { elem; _ } -> c_type_of_type_ref elem ^ "*"
  | Optional inner -> c_type_of_type_ref inner
  | Pointer { inner; _ } -> c_type_of_type_ref inner ^ "*"
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
  let of_int_cases =
    List.map enum.entries ~f:(fun entry ->
      sprintf
        "    | x when x = %s_%s () -> %s"
        (String.lowercase enum.name)
        (String.lowercase entry.name)
        (normalize_enum_entry_name entry.name))
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
    "module %s = struct\n\
    \  type t =\n\
     %s\n\n\
     %s\n\n\
    \  let to_int = function\n\
     %s\n\n\
    \  let of_int = function\n\
     %s\n\
    \    | n -> failwith (Printf.sprintf \"%s.of_int: unknown value %%d\" n)\n\
     end\n"
    module_name
    variants
    externals
    to_int_cases
    of_int_cases
    module_name
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
    "module %s : sig\n\
    \  type t =\n\
     %s\n\n\
    \  val to_int : t -> int\n\
    \  val of_int : int -> t\n\
     end\n"
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

(** Generate C struct allocation/deallocation functions *)
let gen_c_struct_create_free (struct_ : Ir.struct_) : string =
  let c_name = c_type_name struct_.name in
  sprintf
    {|/* Struct: %s */
CAMLprim value caml_wgpu_%s_create(value unit) {
  CAMLparam1(unit);
  %s *s = (%s*)malloc(sizeof(%s));
  memset(s, 0, sizeof(%s));
  CAMLreturn(caml_copy_nativeint((intnat)s));
}

CAMLprim value caml_wgpu_%s_free(value handle) {
  CAMLparam1(handle);
  %s *s = (%s*)Nativeint_val(handle);
  if (s != NULL) {
    free(s);
  }
  CAMLreturn(Val_unit);
}
|}
    c_name
    (String.lowercase struct_.name)
    c_name
    c_name
    c_name
    c_name
    (String.lowercase struct_.name)
    c_name
    c_name
;;

(** Compute the count field name for an array field. e.g., "entries" -> "entryCount",
    "bind_group_layouts" -> "bindGroupLayoutCount" *)
let array_count_field_name (array_field : string) : string =
  let camel = to_camel_case array_field in
  (* Remove trailing 's' to get singular, then add 'Count' *)
  let singular =
    if String.is_suffix camel ~suffix:"ies"
    then String.chop_suffix_exn camel ~suffix:"ies" ^ "y"
    else if String.is_suffix camel ~suffix:"s"
    then String.chop_suffix_exn camel ~suffix:"s"
    else camel
  in
  singular ^ "Count"
;;

(** Generate C setter for a struct member *)
let gen_c_struct_setter (struct_ : Ir.struct_) (member : Ir.struct_member) : string =
  let c_struct = c_type_name struct_.name in
  let c_field = to_camel_case member.name in
  let func_name =
    sprintf
      "caml_wgpu_%s_set_%s"
      (String.lowercase struct_.name)
      (String.lowercase member.name)
  in
  let body =
    match member.type_ with
    | Primitive Bool -> sprintf "  s->%s = Bool_val(val);" c_field
    | Primitive Uint32 -> sprintf "  s->%s = (uint32_t)Int_val(val);" c_field
    | Primitive Uint64 -> sprintf "  s->%s = (uint64_t)Int64_val(val);" c_field
    | Primitive Int32 -> sprintf "  s->%s = (int32_t)Int_val(val);" c_field
    | Primitive Int64 -> sprintf "  s->%s = (int64_t)Int64_val(val);" c_field
    | Primitive Float32 -> sprintf "  s->%s = (float)Double_val(val);" c_field
    | Primitive Float64 -> sprintf "  s->%s = Double_val(val);" c_field
    | Primitive Usize -> sprintf "  s->%s = (size_t)Int64_val(val);" c_field
    | Primitive (String | Out_string | String_with_default_empty) ->
      sprintf
        "  const char *str = String_val(val);\n\
        \  s->%s.data = str;\n\
        \  s->%s.length = strlen(str);"
        c_field
        c_field
    | Primitive C_void -> sprintf "  s->%s = (void*)Nativeint_val(val);" c_field
    | Enum _ -> sprintf "  s->%s = Int_val(val);" c_field
    | Bitflag _ -> sprintf "  s->%s = Int_val(val);" c_field
    | Struct _ ->
      sprintf
        "  s->%s = *(%s*)Nativeint_val(val);"
        c_field
        (c_type_of_type_ref member.type_)
    | Object _ ->
      sprintf
        "  s->%s = (%s)Nativeint_val(val);"
        c_field
        (c_type_of_type_ref member.type_)
    | Callback _ -> sprintf "  (void)s; /* TODO: callback field %s */" c_field
    | Array { elem; _ } ->
      let elem_c_type = c_type_of_type_ref elem in
      let count_field = array_count_field_name member.name in
      let copy_code =
        match elem with
        | Object _ ->
          sprintf
            "  for (size_t i = 0; i < count; i++) {\n\
            \    arr[i] = (%s)Nativeint_val(Field(val, i));\n\
            \  }"
            elem_c_type
        | Struct _ ->
          sprintf
            "  for (size_t i = 0; i < count; i++) {\n\
            \    arr[i] = *(%s*)Nativeint_val(Field(val, i));\n\
            \  }"
            elem_c_type
        | Enum _ | Bitflag _ ->
          "  for (size_t i = 0; i < count; i++) {\n\
          \    arr[i] = Int_val(Field(val, i));\n\
          \  }"
        | Primitive Uint32 | Primitive Int32 ->
          "  for (size_t i = 0; i < count; i++) {\n\
          \    arr[i] = Int_val(Field(val, i));\n\
          \  }"
        | _ -> sprintf "  /* TODO: copy %s elements */" elem_c_type
      in
      sprintf
        "  size_t count = Wosize_val(val);\n\
        \  %s* arr = (count > 0) ? malloc(count * sizeof(%s)) : NULL;\n\
         %s\n\
        \  s->%s = count;\n\
        \  s->%s = arr;"
        elem_c_type
        elem_c_type
        copy_code
        count_field
        c_field
    | Optional inner ->
      (match inner with
       | Object _ ->
         sprintf "  s->%s = (%s)Nativeint_val(val);" c_field (c_type_of_type_ref inner)
       | Struct name ->
         sprintf "  s->%s = (%s*)Nativeint_val(val);" c_field (c_type_name name)
       | _ -> sprintf "  (void)s; /* TODO: optional field %s */" c_field)
    | Pointer { inner; _ } ->
      (match inner with
       | Struct name ->
         sprintf "  s->%s = (%s*)Nativeint_val(val);" c_field (c_type_name name)
       | Array { elem; _ } ->
         (* Pointer to array - same as array but with pointer indirection *)
         let elem_c_type = c_type_of_type_ref elem in
         let count_field = array_count_field_name member.name in
         let copy_code =
           match elem with
           | Object _ ->
             sprintf
               "  for (size_t i = 0; i < count; i++) {\n\
               \    arr[i] = (%s)Nativeint_val(Field(val, i));\n\
               \  }"
               elem_c_type
           | Struct _ ->
             sprintf
               "  for (size_t i = 0; i < count; i++) {\n\
               \    arr[i] = *(%s*)Nativeint_val(Field(val, i));\n\
               \  }"
               elem_c_type
           | Enum _ | Bitflag _ ->
             "  for (size_t i = 0; i < count; i++) {\n\
             \    arr[i] = Int_val(Field(val, i));\n\
             \  }"
           | Primitive Uint32 | Primitive Int32 ->
             "  for (size_t i = 0; i < count; i++) {\n\
             \    arr[i] = Int_val(Field(val, i));\n\
             \  }"
           | _ -> sprintf "  /* TODO: copy %s elements */" elem_c_type
         in
         sprintf
           "  size_t count = Wosize_val(val);\n\
           \  %s* arr = (count > 0) ? malloc(count * sizeof(%s)) : NULL;\n\
            %s\n\
           \  s->%s = count;\n\
           \  s->%s = arr;"
           elem_c_type
           elem_c_type
           copy_code
           count_field
           c_field
       | _ -> sprintf "  (void)s; /* TODO: pointer field %s */" c_field)
  in
  sprintf
    {|CAMLprim value %s(value handle, value val) {
  CAMLparam2(handle, val);
  %s *s = (%s*)Nativeint_val(handle);
%s
  CAMLreturn(Val_unit);
}
|}
    func_name
    c_struct
    c_struct
    body
;;

(** Generate C getter for a struct member *)
let gen_c_struct_getter (struct_ : Ir.struct_) (member : Ir.struct_member) : string =
  let c_struct = c_type_name struct_.name in
  let c_field = to_camel_case member.name in
  let func_name =
    sprintf
      "caml_wgpu_%s_get_%s"
      (String.lowercase struct_.name)
      (String.lowercase member.name)
  in
  let body =
    match member.type_ with
    | Primitive Bool -> sprintf "  CAMLreturn(Val_bool(s->%s));" c_field
    | Primitive Uint32 -> sprintf "  CAMLreturn(Val_int(s->%s));" c_field
    | Primitive Uint64 -> sprintf "  CAMLreturn(caml_copy_int64(s->%s));" c_field
    | Primitive Int32 -> sprintf "  CAMLreturn(Val_int(s->%s));" c_field
    | Primitive Int64 -> sprintf "  CAMLreturn(caml_copy_int64(s->%s));" c_field
    | Primitive Float32 ->
      sprintf "  CAMLreturn(caml_copy_double((double)s->%s));" c_field
    | Primitive Float64 -> sprintf "  CAMLreturn(caml_copy_double(s->%s));" c_field
    | Primitive Usize -> sprintf "  CAMLreturn(caml_copy_int64((int64_t)s->%s));" c_field
    | Primitive (String | Out_string | String_with_default_empty) ->
      sprintf
        "  if (s->%s.data != NULL) {\n\
        \    CAMLreturn(caml_copy_string(s->%s.data));\n\
        \  } else {\n\
        \    CAMLreturn(caml_copy_string(\"\"));\n\
        \  }"
        c_field
        c_field
    | Primitive C_void ->
      sprintf "  CAMLreturn(caml_copy_nativeint((intnat)s->%s));" c_field
    | Enum _ -> sprintf "  CAMLreturn(Val_int(s->%s));" c_field
    | Bitflag _ -> sprintf "  CAMLreturn(Val_int(s->%s));" c_field
    | Object _ -> sprintf "  CAMLreturn(caml_copy_nativeint((intnat)s->%s));" c_field
    | Struct _ | Callback _ | Array _ | Optional _ | Pointer _ ->
      sprintf "  (void)s; /* TODO: getter for %s */\n  CAMLreturn(Val_unit);" c_field
  in
  sprintf
    {|CAMLprim value %s(value handle) {
  CAMLparam1(handle);
  %s *s = (%s*)Nativeint_val(handle);
%s
}
|}
    func_name
    c_struct
    c_struct
    body
;;

(** Generate C code for extension struct chain header functions *)
let gen_c_extension_chain_stubs (struct_ : Ir.struct_) : string =
  match struct_.type_ with
  | Ir.Extension_in _ | Ir.Extension_out _ ->
    let c_name = c_type_name struct_.name in
    let lower_name = String.lowercase struct_.name in
    sprintf
      {|/* Extension chain functions for %s */
CAMLprim value caml_wgpu_%s_set_chain_stype(value handle, value stype) {
  CAMLparam2(handle, stype);
  %s *s = (%s*)Nativeint_val(handle);
  s->chain.sType = Int_val(stype);
  CAMLreturn(Val_unit);
}

CAMLprim value caml_wgpu_%s_as_chained(value handle) {
  CAMLparam1(handle);
  %s *s = (%s*)Nativeint_val(handle);
  CAMLreturn(caml_copy_nativeint((intnat)&s->chain));
}
|}
      c_name
      lower_name
      c_name
      c_name
      lower_name
      c_name
      c_name
  | Ir.Base_in ->
    (* Base input structs use WGPUChainedStruct *)
    let c_name = c_type_name struct_.name in
    let lower_name = String.lowercase struct_.name in
    sprintf
      {|/* nextInChain setter for %s */
CAMLprim value caml_wgpu_%s_set_next_in_chain(value handle, value chain) {
  CAMLparam2(handle, chain);
  %s *s = (%s*)Nativeint_val(handle);
  s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
  CAMLreturn(Val_unit);
}
|}
      c_name
      lower_name
      c_name
      c_name
  | Ir.Base_out | Ir.Base_in_out ->
    (* Base output structs use WGPUChainedStructOut *)
    let c_name = c_type_name struct_.name in
    let lower_name = String.lowercase struct_.name in
    sprintf
      {|/* nextInChain setter for %s */
CAMLprim value caml_wgpu_%s_set_next_in_chain(value handle, value chain) {
  CAMLparam2(handle, chain);
  %s *s = (%s*)Nativeint_val(handle);
  s->nextInChain = (WGPUChainedStructOut *)Nativeint_val(chain);
  CAMLreturn(Val_unit);
}
|}
      c_name
      lower_name
      c_name
      c_name
  | Ir.Standalone -> ""
;;

(** Generate all C code for a struct *)
let gen_c_struct_stubs (struct_ : Ir.struct_) : string =
  let create_free = gen_c_struct_create_free struct_ in
  let setters =
    List.map struct_.members ~f:(gen_c_struct_setter struct_) |> String.concat ~sep:"\n"
  in
  let getters =
    List.map struct_.members ~f:(gen_c_struct_getter struct_) |> String.concat ~sep:"\n"
  in
  let chain_stubs = gen_c_extension_chain_stubs struct_ in
  String.concat ~sep:"\n" [ create_free; setters; getters; chain_stubs ]
;;

(** Generate OCaml external for struct operations *)
let gen_ml_struct (struct_ : Ir.struct_) : string =
  let type_name = struct_.name in
  let module_name = ocaml_module_name struct_.name in
  (* External declarations *)
  let create_ext =
    sprintf
      "external %s_create : unit -> nativeint = \"caml_wgpu_%s_create\""
      type_name
      (String.lowercase struct_.name)
  in
  let free_ext =
    sprintf
      "external %s_free : nativeint -> unit = \"caml_wgpu_%s_free\""
      type_name
      (String.lowercase struct_.name)
  in
  let setter_exts =
    List.map struct_.members ~f:(fun member ->
      let ml_type =
        match member.type_ with
        | Primitive Bool -> "bool"
        | Primitive (Uint32 | Int32) -> "int"
        | Primitive (Uint64 | Int64 | Usize) -> "int64"
        | Primitive (Float32 | Float64) -> "float"
        | Primitive (String | Out_string | String_with_default_empty) -> "string"
        | Primitive C_void -> "nativeint"
        | Enum _ | Bitflag _ -> "int"
        | Array { elem; _ } ->
          (match elem with
           | Enum _ | Bitflag _ -> "int array"
           | Primitive (Uint32 | Int32) -> "int array"
           | _ -> "nativeint array")
        | Pointer { inner = Array { elem; _ }; _ } ->
          (match elem with
           | Enum _ | Bitflag _ -> "int array"
           | Primitive (Uint32 | Int32) -> "int array"
           | _ -> "nativeint array")
        | Object _ | Struct _ | Callback _ | Optional _ | Pointer _ -> "nativeint"
      in
      sprintf
        "external %s_set_%s : nativeint -> %s -> unit = \"caml_wgpu_%s_set_%s\""
        type_name
        member.name
        ml_type
        (String.lowercase struct_.name)
        (String.lowercase member.name))
    |> String.concat ~sep:"\n"
  in
  let getter_exts =
    List.map struct_.members ~f:(fun member ->
      let ml_type =
        match member.type_ with
        | Primitive Bool -> "bool"
        | Primitive (Uint32 | Int32) -> "int"
        | Primitive (Uint64 | Int64 | Usize) -> "int64"
        | Primitive (Float32 | Float64) -> "float"
        | Primitive (String | Out_string | String_with_default_empty) -> "string"
        | Primitive C_void -> "nativeint"
        | Enum _ | Bitflag _ -> "int"
        | Object _ | Struct _ | Callback _ | Array _ | Optional _ | Pointer _ ->
          "nativeint"
      in
      sprintf
        "external %s_get_%s : nativeint -> %s = \"caml_wgpu_%s_get_%s\""
        type_name
        member.name
        ml_type
        (String.lowercase struct_.name)
        (String.lowercase member.name))
    |> String.concat ~sep:"\n"
  in
  (* Extension chain functions for extension structs, or nextInChain setter for base structs *)
  let chain_exts =
    match struct_.type_ with
    | Ir.Extension_in _ | Ir.Extension_out _ ->
      let lower_name = String.lowercase struct_.name in
      sprintf
        "\n\n\
        \  external %s_set_chain_stype : nativeint -> int -> unit = \
         \"caml_wgpu_%s_set_chain_stype\"\n\n\
        \  external %s_as_chained : nativeint -> nativeint = \"caml_wgpu_%s_as_chained\""
        type_name
        lower_name
        type_name
        lower_name
    | Ir.Base_in | Ir.Base_out | Ir.Base_in_out ->
      let lower_name = String.lowercase struct_.name in
      sprintf
        "\n\n\
        \  external %s_set_next_in_chain : nativeint -> nativeint -> unit = \
         \"caml_wgpu_%s_set_next_in_chain\""
        type_name
        lower_name
    | Ir.Standalone -> ""
  in
  sprintf
    "module %s = struct\n  type t = nativeint\n\n  %s\n\n  %s\n\n%s\n\n%s%s\nend\n"
    module_name
    create_ext
    free_ext
    (indent_lines setter_exts)
    (indent_lines getter_exts)
    chain_exts
;;

(** Generate MLI for struct *)
let gen_mli_struct (struct_ : Ir.struct_) : string =
  let module_name = ocaml_module_name struct_.name in
  let type_name = struct_.name in
  (* Signature for setters *)
  let setter_sigs =
    List.map struct_.members ~f:(fun member ->
      let ml_type =
        match member.type_ with
        | Primitive Bool -> "bool"
        | Primitive (Uint32 | Int32) -> "int"
        | Primitive (Uint64 | Int64 | Usize) -> "int64"
        | Primitive (Float32 | Float64) -> "float"
        | Primitive (String | Out_string | String_with_default_empty) -> "string"
        | Primitive C_void -> "nativeint"
        | Enum _ | Bitflag _ -> "int"
        | Array { elem; _ } ->
          (match elem with
           | Enum _ | Bitflag _ -> "int array"
           | Primitive (Uint32 | Int32) -> "int array"
           | _ -> "nativeint array")
        | Pointer { inner = Array { elem; _ }; _ } ->
          (match elem with
           | Enum _ | Bitflag _ -> "int array"
           | Primitive (Uint32 | Int32) -> "int array"
           | _ -> "nativeint array")
        | Object _ | Struct _ | Callback _ | Optional _ | Pointer _ -> "nativeint"
      in
      sprintf "  val %s_set_%s : t -> %s -> unit" type_name member.name ml_type)
    |> String.concat ~sep:"\n"
  in
  let getter_sigs =
    List.map struct_.members ~f:(fun member ->
      let ml_type =
        match member.type_ with
        | Primitive Bool -> "bool"
        | Primitive (Uint32 | Int32) -> "int"
        | Primitive (Uint64 | Int64 | Usize) -> "int64"
        | Primitive (Float32 | Float64) -> "float"
        | Primitive (String | Out_string | String_with_default_empty) -> "string"
        | Primitive C_void -> "nativeint"
        | Enum _ | Bitflag _ -> "int"
        | Object _ | Struct _ | Callback _ | Array _ | Optional _ | Pointer _ ->
          "nativeint"
      in
      sprintf "  val %s_get_%s : t -> %s" type_name member.name ml_type)
    |> String.concat ~sep:"\n"
  in
  (* Extension chain function signatures, or nextInChain setter for base structs *)
  let chain_sigs =
    match struct_.type_ with
    | Ir.Extension_in _ | Ir.Extension_out _ ->
      sprintf
        "\n\
        \  val %s_set_chain_stype : t -> int -> unit\n\
        \  val %s_as_chained : t -> nativeint"
        type_name
        type_name
    | Ir.Base_in | Ir.Base_out | Ir.Base_in_out ->
      sprintf "\n  val %s_set_next_in_chain : t -> nativeint -> unit" type_name
    | Ir.Standalone -> ""
  in
  sprintf
    "module %s : sig\n\
    \  type t = nativeint\n\
    \  val %s_create : unit -> t\n\
    \  val %s_free : t -> unit\n\
     %s\n\
     %s%s\n\
     end\n"
    module_name
    type_name
    type_name
    setter_sigs
    getter_sigs
    chain_sigs
;;

(** Check if a method uses callbacks (async) *)
let method_is_async (method_ : Ir.method_) : bool = Option.is_some method_.callback

(** Check if method is manually implemented in sync helpers *)
let method_is_manual (obj_name : string) (method_name : string) : bool =
  match obj_name, method_name with
  | "adapter", "get_info" -> true
  (* device.get_queue is now auto-generated *)
  | _ -> false
;;

(** Get the element type of an array type_ref *)
let array_elem_c_type (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Array { elem; _ } -> c_type_of_type_ref elem
  | _ -> "void*"
;;

(** Generate C code for array argument conversion *)
let gen_c_array_conversion (arg : Ir.arg) : string =
  match arg.type_ with
  | Array { elem; _ } ->
    let elem_c_type = c_type_of_type_ref elem in
    let count_var = sprintf "c_%s_count" arg.name in
    let array_var = sprintf "c_%s" arg.name in
    let copy_code =
      match elem with
      | Object _ ->
        sprintf
          "  for (size_t i = 0; i < %s; i++) {\n\
          \    %s[i] = (%s)Nativeint_val(Field(%s, i));\n\
          \  }"
          count_var
          array_var
          elem_c_type
          arg.name
      | Struct name ->
        (* For structs, we need to copy the struct contents, not just pointers *)
        sprintf
          "  for (size_t i = 0; i < %s; i++) {\n\
          \    %s *src = (%s*)Nativeint_val(Field(%s, i));\n\
          \    %s[i] = *src;\n\
          \  }"
          count_var
          (c_type_name name)
          (c_type_name name)
          arg.name
          array_var
      | Enum _ | Bitflag _ ->
        sprintf
          "  for (size_t i = 0; i < %s; i++) {\n\
          \    %s[i] = (%s)Int_val(Field(%s, i));\n\
          \  }"
          count_var
          array_var
          elem_c_type
          arg.name
      | Primitive (Uint32 | Int32) ->
        sprintf
          "  for (size_t i = 0; i < %s; i++) {\n\
          \    %s[i] = (%s)Int_val(Field(%s, i));\n\
          \  }"
          count_var
          array_var
          elem_c_type
          arg.name
      | Primitive (Uint64 | Int64) ->
        sprintf
          "  for (size_t i = 0; i < %s; i++) {\n\
          \    %s[i] = (%s)Int64_val(Field(%s, i));\n\
          \  }"
          count_var
          array_var
          elem_c_type
          arg.name
      | _ ->
        sprintf
          "  for (size_t i = 0; i < %s; i++) {\n\
          \    %s[i] = (%s)Nativeint_val(Field(%s, i));\n\
          \  }"
          count_var
          array_var
          elem_c_type
          arg.name
    in
    sprintf
      "  size_t %s = Wosize_val(%s);\n\
      \  %s* %s = (%s > 0) ? alloca(%s * sizeof(%s)) : NULL;\n\
       %s"
      count_var
      arg.name
      elem_c_type
      array_var
      count_var
      count_var
      elem_c_type
      copy_code
  | _ -> ""
;;

(** Generate C stub for a single method *)
let gen_c_method_stub (obj : Ir.object_) (method_ : Ir.method_) : string =
  (* Skip async methods and manually implemented methods *)
  if method_is_async method_
  then sprintf "/* TODO: async method %s.%s */\n" obj.name method_.name
  else if method_is_manual obj.name method_.name
  then sprintf "/* Manually implemented: %s.%s */\n" obj.name method_.name
  else (
    let c_func = c_method_name obj.name method_.name in
    let caml_func =
      sprintf
        "caml_wgpu_%s_%s"
        (String.lowercase obj.name)
        (String.lowercase method_.name)
    in
    let obj_c_type = c_type_name obj.name in
    (* Build parameter list for CAMLparam *)
    let all_params = "self" :: List.map method_.args ~f:(fun arg -> arg.name) in
    let num_params = List.length all_params in
    let caml_param =
      if num_params <= 5
      then sprintf "CAMLparam%d(%s)" num_params (String.concat ~sep:", " all_params)
      else (
        (* Need multiple CAMLparam calls *)
        let first5 = List.take all_params 5 in
        let rest = List.drop all_params 5 in
        sprintf
          "CAMLparam5(%s);\n  CAMLxparam%d(%s)"
          (String.concat ~sep:", " first5)
          (List.length rest)
          (String.concat ~sep:", " rest))
    in
    (* Build value parameter declarations *)
    let value_params =
      "value self" :: List.map method_.args ~f:(fun arg -> sprintf "value %s" arg.name)
    in
    (* Build argument conversion *)
    let arg_conversions =
      List.map method_.args ~f:(fun arg ->
        let c_type = c_type_of_type_ref arg.type_ in
        match arg.type_ with
        | Primitive Bool -> sprintf "  bool c_%s = Bool_val(%s);" arg.name arg.name
        | Primitive Uint32 -> sprintf "  uint32_t c_%s = Int_val(%s);" arg.name arg.name
        | Primitive Uint64 -> sprintf "  uint64_t c_%s = Int64_val(%s);" arg.name arg.name
        | Primitive Int32 -> sprintf "  int32_t c_%s = Int_val(%s);" arg.name arg.name
        | Primitive Int64 -> sprintf "  int64_t c_%s = Int64_val(%s);" arg.name arg.name
        | Primitive Float32 -> sprintf "  float c_%s = Double_val(%s);" arg.name arg.name
        | Primitive Float64 -> sprintf "  double c_%s = Double_val(%s);" arg.name arg.name
        | Primitive Usize -> sprintf "  size_t c_%s = Int64_val(%s);" arg.name arg.name
        | Primitive (String | Out_string | String_with_default_empty) ->
          sprintf
            "  WGPUStringView c_%s = { .data = String_val(%s), .length = \
             caml_string_length(%s) };"
            arg.name
            arg.name
            arg.name
        | Primitive C_void ->
          sprintf "  void* c_%s = (void*)Nativeint_val(%s);" arg.name arg.name
        | Enum _ | Bitflag _ ->
          sprintf "  %s c_%s = Int_val(%s);" c_type arg.name arg.name
        | Object _ ->
          sprintf "  %s c_%s = (%s)Nativeint_val(%s);" c_type arg.name c_type arg.name
        | Struct _ ->
          (* For struct pointers, we pass the nativeint as a pointer *)
          sprintf "  %s* c_%s = (%s*)Nativeint_val(%s);" c_type arg.name c_type arg.name
        | Pointer { inner = Struct _; _ } ->
          sprintf "  %s c_%s = (%s)Nativeint_val(%s);" c_type arg.name c_type arg.name
        | Array _ -> gen_c_array_conversion arg
        | _ -> sprintf "  /* TODO: convert %s */" arg.name)
      |> String.concat ~sep:"\n"
    in
    (* Build C function call arguments - arrays need count + pointer *)
    let c_args =
      "c_self"
      :: List.concat_map method_.args ~f:(fun arg ->
        match arg.type_ with
        | Array _ ->
          (* Array args become count, pointer pair in C API *)
          [ sprintf "c_%s_count" arg.name; sprintf "c_%s" arg.name ]
        | _ -> [ sprintf "c_%s" arg.name ])
    in
    let c_call_args = String.concat ~sep:", " c_args in
    (* Build return handling *)
    let return_code =
      match method_.returns with
      | None -> sprintf "  %s(%s);\n  CAMLreturn(Val_unit);" c_func c_call_args
      | Some ret ->
        let ret_c_type = c_type_of_type_ref ret.type_ in
        (match ret.type_ with
         | Primitive Bool ->
           sprintf
             "  bool result = %s(%s);\n  CAMLreturn(Val_bool(result));"
             c_func
             c_call_args
         | Primitive (Uint32 | Int32) ->
           sprintf
             "  %s result = %s(%s);\n  CAMLreturn(Val_int(result));"
             ret_c_type
             c_func
             c_call_args
         | Primitive (Uint64 | Int64 | Usize) ->
           sprintf
             "  %s result = %s(%s);\n  CAMLreturn(caml_copy_int64(result));"
             ret_c_type
             c_func
             c_call_args
         | Primitive (Float32 | Float64) ->
           sprintf
             "  %s result = %s(%s);\n  CAMLreturn(caml_copy_double(result));"
             ret_c_type
             c_func
             c_call_args
         | Object _ ->
           sprintf
             "  %s result = %s(%s);\n  CAMLreturn(caml_copy_nativeint((intnat)result));"
             ret_c_type
             c_func
             c_call_args
         | Enum _ | Bitflag _ ->
           sprintf
             "  %s result = %s(%s);\n  CAMLreturn(Val_int(result));"
             ret_c_type
             c_func
             c_call_args
         | _ ->
           sprintf
             "  /* TODO: return type */\n  %s(%s);\n  CAMLreturn(Val_unit);"
             c_func
             c_call_args)
    in
    (* Handle bytecode calling convention for many args *)
    let bytecode_decl =
      if num_params > 5
      then
        sprintf
          "\n\
           CAMLprim value %s_bytecode(value *argv, int argn) {\n\
          \  (void)argn;\n\
          \  return %s(%s);\n\
           }"
          caml_func
          caml_func
          (String.concat
             ~sep:", "
             (List.mapi all_params ~f:(fun i _ -> sprintf "argv[%d]" i)))
      else ""
    in
    sprintf
      {|CAMLprim value %s(%s) {
  %s;
  %s c_self = (%s)Nativeint_val(self);
%s
%s
}%s
|}
      caml_func
      (String.concat ~sep:", " value_params)
      caml_param
      obj_c_type
      obj_c_type
      arg_conversions
      return_code
      bytecode_decl)
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
  (* Generate method stubs *)
  let methods =
    List.map obj.methods ~f:(gen_c_method_stub obj) |> String.concat ~sep:"\n"
  in
  sprintf "/* Object: %s */\n%s\n\n%s" c_type release methods
;;

(** Get OCaml type string for a type_ref *)
let rec ml_type_of_type_ref (type_ref : Ir.type_ref) : string =
  match type_ref with
  | Primitive Bool -> "bool"
  | Primitive (Uint32 | Int32) -> "int"
  | Primitive (Uint64 | Int64 | Usize) -> "int64"
  | Primitive (Float32 | Float64) -> "float"
  | Primitive (String | Out_string | String_with_default_empty) -> "string"
  | Primitive C_void -> "nativeint"
  | Enum _ | Bitflag _ -> "int"
  | Object name -> name
  | Struct _ -> "nativeint"
  | Callback _ -> "nativeint"
  | Array { elem; _ } ->
    (* Arrays of objects become object arrays, others become nativeint arrays *)
    (match elem with
     | Object name -> name ^ " array"
     | Enum _ | Bitflag _ -> "int array"
     | Primitive (Uint32 | Int32) -> "int array"
     | _ -> "nativeint array")
  | Optional inner -> ml_type_of_type_ref inner
  | Pointer _ -> "nativeint"
;;

(** Generate OCaml external declaration for a method *)
let gen_ml_method (obj : Ir.object_) (method_ : Ir.method_) : string =
  if method_is_async method_
  then sprintf "(* TODO: async method %s_%s *)" obj.name method_.name
  else if method_is_manual obj.name method_.name
  then "" (* Already defined manually *)
  else (
    let func_name = sprintf "%s_%s" obj.name method_.name in
    let caml_func =
      sprintf
        "caml_wgpu_%s_%s"
        (String.lowercase obj.name)
        (String.lowercase method_.name)
    in
    let arg_types =
      obj.name :: List.map method_.args ~f:(fun arg -> ml_type_of_type_ref arg.type_)
    in
    let ret_type =
      match method_.returns with
      | None -> "unit"
      | Some ret -> ml_type_of_type_ref ret.type_
    in
    let num_args = List.length arg_types in
    let type_sig = String.concat ~sep:" -> " arg_types ^ " -> " ^ ret_type in
    if num_args > 5
    then
      sprintf
        "external %s : %s = \"%s_bytecode\" \"%s\""
        func_name
        type_sig
        caml_func
        caml_func
    else sprintf "external %s : %s = \"%s\"" func_name type_sig caml_func)
;;

(** Generate OCaml type declaration for an object *)
let gen_ml_object_type (obj : Ir.object_) : string =
  sprintf "type %s = nativeint\n" obj.name
;;

(** Generate OCaml method declarations for an object *)
let gen_ml_object_methods (obj : Ir.object_) : string =
  let release =
    sprintf
      "external %s_release : %s -> unit = \"caml_wgpu_%s_release\"\n"
      obj.name
      obj.name
      (String.lowercase obj.name)
  in
  let methods =
    List.filter_map obj.methods ~f:(fun m ->
      let s = gen_ml_method obj m in
      if String.is_empty s then None else Some s)
    |> String.concat ~sep:"\n"
  in
  release ^ methods
;;

(** Generate OCaml code for an object type *)
let gen_ml_object (obj : Ir.object_) : string =
  gen_ml_object_type obj ^ "\n" ^ gen_ml_object_methods obj ^ "\n"
;;

(** Generate MLI declaration for a method *)
let gen_mli_method (obj : Ir.object_) (method_ : Ir.method_) : string =
  if method_is_async method_ || method_is_manual obj.name method_.name
  then ""
  else (
    let func_name = sprintf "%s_%s" obj.name method_.name in
    let arg_types =
      obj.name :: List.map method_.args ~f:(fun arg -> ml_type_of_type_ref arg.type_)
    in
    let ret_type =
      match method_.returns with
      | None -> "unit"
      | Some ret -> ml_type_of_type_ref ret.type_
    in
    let type_sig = String.concat ~sep:" -> " arg_types ^ " -> " ^ ret_type in
    sprintf "val %s : %s" func_name type_sig)
;;

(** Generate MLI type declaration only for an object *)
let gen_mli_object_type (obj : Ir.object_) : string =
  sprintf "type %s = nativeint\n" obj.name
;;

(** Generate MLI method declarations for an object *)
let gen_mli_object_methods (obj : Ir.object_) : string =
  let release = sprintf "val %s_release : %s -> unit\n" obj.name obj.name in
  let methods =
    List.filter_map obj.methods ~f:(fun m ->
      let s = gen_mli_method obj m in
      if String.is_empty s then None else Some s)
    |> String.concat ~sep:"\n"
  in
  if String.is_empty methods then release else release ^ methods ^ "\n"
;;

(** Generate MLI for an object type - deprecated, use gen_mli_object_type +
    gen_mli_object_methods *)
let gen_mli_object (obj : Ir.object_) : string =
  gen_mli_object_type obj ^ "\n" ^ gen_mli_object_methods obj
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
let gen_c_sync_helpers () : string = read_template "low/sync_helpers.c"

(** Generate all C stubs *)
let gen_c_stubs (api : Ir.api) : string =
  let header =
    {|/* Generated by gen_bindings - low-level C stubs */
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/custom.h>
#include <caml/fail.h>
#include <caml/bigarray.h>
#include <string.h>
#include <stdlib.h>

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
  let struct_stubs =
    List.map api.structs ~f:gen_c_struct_stubs |> String.concat ~sep:"\n"
  in
  let object_stubs =
    List.map api.objects ~f:gen_c_object_stubs |> String.concat ~sep:"\n"
  in
  let function_stubs =
    List.map api.functions ~f:gen_c_function_stubs |> String.concat ~sep:"\n"
  in
  let sync_helpers = gen_c_sync_helpers () in
  String.concat
    [ header
    ; enum_stubs
    ; bitflag_stubs
    ; struct_stubs
    ; object_stubs
    ; function_stubs
    ; sync_helpers
    ]
;;

(** Generate all OCaml bindings *)
let gen_ml (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - low-level OCaml bindings *)\n\n" in
  let enums = List.map api.enums ~f:gen_ml_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_ml_bitflag |> String.concat ~sep:"\n" in
  let structs = List.map api.structs ~f:gen_ml_struct |> String.concat ~sep:"\n" in
  (* Generate all object types first, then all methods to handle forward references *)
  let object_types =
    List.map api.objects ~f:gen_ml_object_type |> String.concat ~sep:""
  in
  let object_methods =
    List.map api.objects ~f:gen_ml_object_methods |> String.concat ~sep:"\n"
  in
  let functions =
    {|external create_instance : unit -> instance = "caml_wgpu_create_instance"

external instance_request_adapter_sync : instance -> int -> int -> adapter
  = "caml_wgpu_instance_request_adapter_sync"

external adapter_request_device_sync : adapter -> device
  = "caml_wgpu_adapter_request_device_sync"

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

external queue_submit_single : queue -> command_buffer -> unit
  = "caml_wgpu_queue_submit_single"

external device_poll : device -> bool -> unit
  = "caml_wgpu_device_poll"

external buffer_map_sync : buffer -> int -> int64 -> int64 -> int
  = "caml_wgpu_buffer_map_sync"

external buffer_get_mapped_range_bigarray :
  buffer -> int64 -> int64 -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
  = "caml_wgpu_buffer_get_mapped_range_bigarray"

external buffer_get_const_mapped_range_bigarray :
  buffer -> int64 -> int64 -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
  = "caml_wgpu_buffer_get_const_mapped_range_bigarray"

external queue_write_buffer_bigarray :
  queue -> buffer -> int64 -> (_, _, Bigarray.c_layout) Bigarray.Array1.t -> unit
  = "caml_wgpu_queue_write_buffer_bigarray"

external device_create_bind_group_layout_storage :
  device -> string -> int -> bool -> bind_group_layout
  = "caml_wgpu_device_create_bind_group_layout_storage"

external device_create_bind_group_buffer :
  device -> string -> bind_group_layout -> int -> buffer -> int64 -> int64 -> bind_group
  = "caml_wgpu_device_create_bind_group_buffer_bytecode" "caml_wgpu_device_create_bind_group_buffer"

external device_create_texture_2d :
  device -> string -> int -> int -> int -> int -> texture
  = "caml_wgpu_device_create_texture_2d_bytecode" "caml_wgpu_device_create_texture_2d"

external texture_create_view_configurable :
  texture -> string -> int -> int -> int -> int -> int -> int -> int -> texture_view
  = "caml_wgpu_texture_create_view_configurable_bytecode" "caml_wgpu_texture_create_view_configurable"

external command_encoder_begin_render_pass_configurable :
  command_encoder -> string -> texture_view -> int -> int -> float -> float -> float -> float -> render_pass_encoder
  = "caml_wgpu_command_encoder_begin_render_pass_configurable_bytecode" "caml_wgpu_command_encoder_begin_render_pass_configurable"

external device_create_render_pipeline_full :
  device -> string -> shader_module -> string -> string -> int -> int -> int -> int ->
  bool -> int -> int -> int -> int -> int -> int -> int -> render_pipeline
  = "caml_wgpu_device_create_render_pipeline_full_bytecode" "caml_wgpu_device_create_render_pipeline_full"
|}
  in
  String.concat
    [ header; enums; bitflags; structs; object_types; "\n"; object_methods; functions ]
;;

(** Generate all OCaml interface *)
let gen_mli (api : Ir.api) : string =
  let header = "(* Generated by gen_bindings - low-level OCaml interface *)\n\n" in
  let enums = List.map api.enums ~f:gen_mli_enum |> String.concat ~sep:"\n" in
  let bitflags = List.map api.bitflags ~f:gen_mli_bitflag |> String.concat ~sep:"\n" in
  let structs = List.map api.structs ~f:gen_mli_struct |> String.concat ~sep:"\n" in
  (* Generate all object types first, then all methods to handle forward references *)
  let object_types =
    List.map api.objects ~f:gen_mli_object_type |> String.concat ~sep:""
  in
  let object_methods =
    List.map api.objects ~f:gen_mli_object_methods |> String.concat ~sep:"\n"
  in
  let functions =
    {|val create_instance : unit -> instance

val instance_request_adapter_sync : instance -> int -> int -> adapter

val adapter_request_device_sync : adapter -> device

type adapter_info =
  { vendor : string
  ; architecture : string
  ; device : string
  ; description : string
  ; backend_type : int
  ; adapter_type : int
  }

val adapter_get_info : adapter -> adapter_info

val queue_submit_single : queue -> command_buffer -> unit

val device_poll : device -> bool -> unit

val buffer_map_sync : buffer -> int -> int64 -> int64 -> int

val buffer_get_mapped_range_bigarray :
  buffer -> int64 -> int64 -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

val buffer_get_const_mapped_range_bigarray :
  buffer -> int64 -> int64 -> (int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t

val queue_write_buffer_bigarray :
  queue -> buffer -> int64 -> (_, _, Bigarray.c_layout) Bigarray.Array1.t -> unit

val device_create_bind_group_layout_storage :
  device -> string -> int -> bool -> bind_group_layout

val device_create_bind_group_buffer :
  device -> string -> bind_group_layout -> int -> buffer -> int64 -> int64 -> bind_group

val device_create_texture_2d :
  device -> string -> int -> int -> int -> int -> texture

val texture_create_view_configurable :
  texture -> string -> int -> int -> int -> int -> int -> int -> int -> texture_view

val command_encoder_begin_render_pass_configurable :
  command_encoder -> string -> texture_view -> int -> int -> float -> float -> float -> float -> render_pass_encoder

val device_create_render_pipeline_full :
  device -> string -> shader_module -> string -> string -> int -> int -> int -> int ->
  bool -> int -> int -> int -> int -> int -> int -> int -> render_pipeline
|}
  in
  String.concat
    [ header; enums; bitflags; structs; object_types; "\n"; object_methods; functions ]
;;
