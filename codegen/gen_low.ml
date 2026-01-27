open! Core

type output_mode =
  | Implementation
  | Interface

let read_template = Names.read_template
let to_pascal_case = Names.to_pascal_case
let to_camel_case = Names.to_camel_case
let c_type_name (name : string) : string = Type_mapping.c_type_name name

let c_method_name (obj_name : string) (method_name : string) : string =
  "wgpu" ^ to_pascal_case obj_name ^ to_pascal_case method_name
;;

let c_function_name (name : string) : string = "wgpu" ^ to_pascal_case name
let ocaml_module_name (name : string) : string = Type_mapping.ocaml_module_name name
let normalize_enum_entry_name = Names.normalize_enum_entry_name
let indent_lines = Names.indent_lines

let c_type_of_type_ref (type_ref : Ir.type_ref) : string =
  Type_mapping.type_string ~context:C_code type_ref
;;

let gen_c_enum_constants (enum : Ir.enum) : string =
  let c_name = c_type_name enum.name in
  let entries =
    List.map enum.entries ~f:(fun entry ->
      let c_entry_name = c_type_name enum.name ^ "_" ^ to_pascal_case entry.name in
      let enum_lower = String.lowercase enum.name in
      let entry_lower = String.lowercase entry.name in
      {%string|CAMLprim value caml_wgpu_%{enum_lower}_%{entry_lower}(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_int(%{c_entry_name}));
}|})
  in
  let entries_str = String.concat ~sep:"\n\n" entries in
  {%string|/* Enum: %{c_name} */
%{entries_str}
|}
;;

let gen_enum (mode : output_mode) (enum : Ir.enum) : string =
  let module_name = ocaml_module_name enum.name in
  let variants =
    List.map enum.entries ~f:(fun entry ->
      let name = normalize_enum_entry_name entry.name in
      {%string|  | %{name}|})
    |> String.concat ~sep:"\n"
  in
  match mode with
  | Interface ->
    {%string|module %{module_name} : sig
  type t =
%{variants}

  val to_int : t -> int
  val of_int : int -> t
end
|}
  | Implementation ->
    (* Helper to make a valid OCaml identifier for cached constant names *)
    let cached_name entry_lower =
      if String.length entry_lower > 0 && Char.is_digit (String.get entry_lower 0)
      then "n" ^ entry_lower ^ "_int"
      else entry_lower ^ "_int"
    in
    let externals =
      List.map enum.entries ~f:(fun entry ->
        let enum_lower = String.lowercase enum.name in
        let entry_lower = String.lowercase entry.name in
        {%string|external %{enum_lower}_%{entry_lower} : unit -> int = "caml_wgpu_%{enum_lower}_%{entry_lower}"|})
      |> String.concat ~sep:"\n"
    in
    let cached_constants =
      List.map enum.entries ~f:(fun entry ->
        let enum_lower = String.lowercase enum.name in
        let entry_lower = String.lowercase entry.name in
        let const_name = cached_name entry_lower in
        {%string|  let %{const_name} = %{enum_lower}_%{entry_lower} ()|})
      |> String.concat ~sep:"\n"
    in
    let to_int_cases =
      List.map enum.entries ~f:(fun entry ->
        let variant_name = normalize_enum_entry_name entry.name in
        let entry_lower = String.lowercase entry.name in
        let const_name = cached_name entry_lower in
        {%string|    | %{variant_name} -> %{const_name}|})
      |> String.concat ~sep:"\n"
    in
    let of_int_cases =
      List.map enum.entries ~f:(fun entry ->
        let variant_name = normalize_enum_entry_name entry.name in
        let entry_lower = String.lowercase entry.name in
        let const_name = cached_name entry_lower in
        {%string|    | x when x = %{const_name} -> %{variant_name}|})
      |> String.concat ~sep:"\n"
    in
    {%string|module %{module_name} = struct
  type t =
%{variants}

%{externals}

%{cached_constants}

  let to_int = function
%{to_int_cases}

  let of_int = function
%{of_int_cases}
    | n -> failwith (Printf.sprintf "%{module_name}.of_int: unknown value %d" n)
end
|}
;;

let gen_ml_enum (enum : Ir.enum) : string = gen_enum Implementation enum
let gen_mli_enum (enum : Ir.enum) : string = gen_enum Interface enum

let gen_c_bitflag_constants (bitflag : Ir.bitflag) : string =
  let entries =
    List.map bitflag.entries ~f:(fun entry ->
      let c_entry_name = c_type_name bitflag.name ^ "_" ^ to_pascal_case entry.name in
      let bitflag_lower = String.lowercase bitflag.name in
      let entry_lower = String.lowercase entry.name in
      {%string|CAMLprim value caml_wgpu_%{bitflag_lower}_%{entry_lower}(value unit) {
  CAMLparam1(unit);
  CAMLreturn(Val_int(%{c_entry_name}));
}|})
  in
  let c_name = c_type_name bitflag.name in
  let entries_str = String.concat ~sep:"\n\n" entries in
  {%string|/* Bitflag: %{c_name} */
%{entries_str}
|}
;;

let gen_bitflag (mode : output_mode) (bitflag : Ir.bitflag) : string =
  let module_name = ocaml_module_name bitflag.name in
  let variants =
    List.map bitflag.entries ~f:(fun entry ->
      let name = normalize_enum_entry_name entry.name in
      {%string|  | %{name}|})
    |> String.concat ~sep:"\n"
  in
  match mode with
  | Interface ->
    {%string|module %{module_name} : sig
  type t =
%{variants}

  val to_int : t -> int
  val list_to_int : t list -> int
end
|}
  | Implementation ->
    (* Helper to make a valid OCaml identifier for cached constant names *)
    let cached_name entry_lower =
      if String.length entry_lower > 0 && Char.is_digit (String.get entry_lower 0)
      then "n" ^ entry_lower ^ "_int"
      else entry_lower ^ "_int"
    in
    let externals =
      List.map bitflag.entries ~f:(fun entry ->
        let bitflag_lower = String.lowercase bitflag.name in
        let entry_lower = String.lowercase entry.name in
        {%string|external %{bitflag_lower}_%{entry_lower} : unit -> int = "caml_wgpu_%{bitflag_lower}_%{entry_lower}"|})
      |> String.concat ~sep:"\n"
    in
    let cached_constants =
      List.map bitflag.entries ~f:(fun entry ->
        let bitflag_lower = String.lowercase bitflag.name in
        let entry_lower = String.lowercase entry.name in
        let const_name = cached_name entry_lower in
        {%string|  let %{const_name} = %{bitflag_lower}_%{entry_lower} ()|})
      |> String.concat ~sep:"\n"
    in
    let to_int_cases =
      List.map bitflag.entries ~f:(fun entry ->
        let variant_name = normalize_enum_entry_name entry.name in
        let entry_lower = String.lowercase entry.name in
        let const_name = cached_name entry_lower in
        {%string|    | %{variant_name} -> %{const_name}|})
      |> String.concat ~sep:"\n"
    in
    {%string|module %{module_name} = struct
  type t =
%{variants}

%{externals}

%{cached_constants}

  let to_int = function
%{to_int_cases}

  let list_to_int flags =
    List.fold_left (fun acc f -> acc lor to_int f) 0 flags
end
|}
;;

let gen_ml_bitflag (bitflag : Ir.bitflag) : string = gen_bitflag Implementation bitflag
let gen_mli_bitflag (bitflag : Ir.bitflag) : string = gen_bitflag Interface bitflag

let gen_c_struct_create_free (struct_ : Ir.struct_) : string =
  let c_name = c_type_name struct_.name in
  let struct_lower = String.lowercase struct_.name in
  {%string|/* Struct: %{c_name} */
CAMLprim value caml_wgpu_%{struct_lower}_create(value unit) {
  CAMLparam1(unit);
  %{c_name} *s = (%{c_name}*)malloc(sizeof(%{c_name}));
  memset(s, 0, sizeof(%{c_name}));
  CAMLreturn(caml_copy_nativeint((intnat)s));
}

CAMLprim value caml_wgpu_%{struct_lower}_free(value handle) {
  CAMLparam1(handle);
  %{c_name} *s = (%{c_name}*)Nativeint_val(handle);
  if (s != NULL) {
    free(s);
  }
  CAMLreturn(Val_unit);
}
|}
;;

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

let gen_c_struct_setter (struct_ : Ir.struct_) (member : Ir.struct_member) : string =
  let c_struct = c_type_name struct_.name in
  let c_field = to_camel_case member.name in
  let struct_lower = String.lowercase struct_.name in
  let member_lower = String.lowercase member.name in
  let func_name = {%string|caml_wgpu_%{struct_lower}_set_%{member_lower}|} in
  let body =
    match member.type_ with
    | Primitive Bool -> {%string|  s->%{c_field} = Bool_val(val);|}
    | Primitive Uint32 -> {%string|  s->%{c_field} = (uint32_t)Int_val(val);|}
    | Primitive Uint64 -> {%string|  s->%{c_field} = (uint64_t)Int64_val(val);|}
    | Primitive Int32 -> {%string|  s->%{c_field} = (int32_t)Int_val(val);|}
    | Primitive Int64 -> {%string|  s->%{c_field} = (int64_t)Int64_val(val);|}
    | Primitive Float32 -> {%string|  s->%{c_field} = (float)Double_val(val);|}
    | Primitive Float64 -> {%string|  s->%{c_field} = Double_val(val);|}
    | Primitive Usize -> {%string|  s->%{c_field} = (size_t)Int64_val(val);|}
    | Primitive (String | Out_string | String_with_default_empty) ->
      {%string|  const char *str = String_val(val);
  s->%{c_field}.data = str;
  s->%{c_field}.length = strlen(str);|}
    | Primitive C_void -> {%string|  s->%{c_field} = (void*)Nativeint_val(val);|}
    | Enum _ -> {%string|  s->%{c_field} = Int_val(val);|}
    | Bitflag _ -> {%string|  s->%{c_field} = Int_val(val);|}
    | Struct _ ->
      let c_type = c_type_of_type_ref member.type_ in
      {%string|  s->%{c_field} = *(%{c_type}*)Nativeint_val(val);|}
    | Object _ ->
      let c_type = c_type_of_type_ref member.type_ in
      {%string|  s->%{c_field} = (%{c_type})Nativeint_val(val);|}
    | Callback _ -> {%string|  (void)s; /* TODO: callback field %{c_field} */|}
    | Array { elem; _ } ->
      let elem_c_type = c_type_of_type_ref elem in
      let count_field = array_count_field_name member.name in
      let copy_code =
        match elem with
        | Object _ ->
          {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = (%{elem_c_type})Nativeint_val(Field(val, i));
  }|}
        | Struct _ ->
          {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = *(%{elem_c_type}*)Nativeint_val(Field(val, i));
  }|}
        | Enum _ | Bitflag _ ->
          {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = Int_val(Field(val, i));
  }|}
        | Primitive Uint32 | Primitive Int32 ->
          {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = Int_val(Field(val, i));
  }|}
        | _ -> {%string|  /* TODO: copy %{elem_c_type} elements */|}
      in
      {%string|  size_t count = Wosize_val(val);
  %{elem_c_type}* arr = (count > 0) ? malloc(count * sizeof(%{elem_c_type})) : NULL;
%{copy_code}
  s->%{count_field} = count;
  s->%{c_field} = arr;|}
    | Optional inner ->
      (match inner with
       | Object _ ->
         let c_type = c_type_of_type_ref inner in
         {%string|  s->%{c_field} = (%{c_type})Nativeint_val(val);|}
       | Struct name ->
         let c_type = c_type_name name in
         {%string|  s->%{c_field} = (%{c_type}*)Nativeint_val(val);|}
       | _ -> {%string|  (void)s; /* TODO: optional field %{c_field} */|})
    | Pointer { inner; _ } ->
      (match inner with
       | Struct name ->
         let c_type = c_type_name name in
         {%string|  s->%{c_field} = (%{c_type}*)Nativeint_val(val);|}
       | Array { elem; _ } ->
         (* Pointer to array - same as array but with pointer indirection *)
         let elem_c_type = c_type_of_type_ref elem in
         let count_field = array_count_field_name member.name in
         let copy_code =
           match elem with
           | Object _ ->
             {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = (%{elem_c_type})Nativeint_val(Field(val, i));
  }|}
           | Struct _ ->
             {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = *(%{elem_c_type}*)Nativeint_val(Field(val, i));
  }|}
           | Enum _ | Bitflag _ ->
             {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = Int_val(Field(val, i));
  }|}
           | Primitive Uint32 | Primitive Int32 ->
             {%string|  for (size_t i = 0; i < count; i++) {
    arr[i] = Int_val(Field(val, i));
  }|}
           | _ -> {%string|  /* TODO: copy %{elem_c_type} elements */|}
         in
         {%string|  size_t count = Wosize_val(val);
  %{elem_c_type}* arr = (count > 0) ? malloc(count * sizeof(%{elem_c_type})) : NULL;
%{copy_code}
  s->%{count_field} = count;
  s->%{c_field} = arr;|}
       | _ -> {%string|  (void)s; /* TODO: pointer field %{c_field} */|})
  in
  {%string|CAMLprim value %{func_name}(value handle, value val) {
  CAMLparam2(handle, val);
  %{c_struct} *s = (%{c_struct}*)Nativeint_val(handle);
%{body}
  CAMLreturn(Val_unit);
}
|}
;;

let gen_c_struct_getter (struct_ : Ir.struct_) (member : Ir.struct_member) : string =
  let c_struct = c_type_name struct_.name in
  let c_field = to_camel_case member.name in
  let struct_lower = String.lowercase struct_.name in
  let member_lower = String.lowercase member.name in
  let func_name = {%string|caml_wgpu_%{struct_lower}_get_%{member_lower}|} in
  let body =
    match member.type_ with
    | Primitive Bool -> {%string|  CAMLreturn(Val_bool(s->%{c_field}));|}
    | Primitive Uint32 -> {%string|  CAMLreturn(Val_int(s->%{c_field}));|}
    | Primitive Uint64 -> {%string|  CAMLreturn(caml_copy_int64(s->%{c_field}));|}
    | Primitive Int32 -> {%string|  CAMLreturn(Val_int(s->%{c_field}));|}
    | Primitive Int64 -> {%string|  CAMLreturn(caml_copy_int64(s->%{c_field}));|}
    | Primitive Float32 ->
      {%string|  CAMLreturn(caml_copy_double((double)s->%{c_field}));|}
    | Primitive Float64 -> {%string|  CAMLreturn(caml_copy_double(s->%{c_field}));|}
    | Primitive Usize -> {%string|  CAMLreturn(caml_copy_int64((int64_t)s->%{c_field}));|}
    | Primitive (String | Out_string | String_with_default_empty) ->
      {%string|  if (s->%{c_field}.data != NULL) {
    CAMLreturn(caml_copy_string(s->%{c_field}.data));
  } else {
    CAMLreturn(caml_copy_string(""));
  }|}
    | Primitive C_void ->
      {%string|  CAMLreturn(caml_copy_nativeint((intnat)s->%{c_field}));|}
    | Enum _ -> {%string|  CAMLreturn(Val_int(s->%{c_field}));|}
    | Bitflag _ -> {%string|  CAMLreturn(Val_int(s->%{c_field}));|}
    | Object _ -> {%string|  CAMLreturn(caml_copy_nativeint((intnat)s->%{c_field}));|}
    | Struct _ | Callback _ | Array _ | Optional _ | Pointer _ ->
      {%string|  (void)s; /* TODO: getter for %{c_field} */
  CAMLreturn(Val_unit);|}
  in
  {%string|CAMLprim value %{func_name}(value handle) {
  CAMLparam1(handle);
  %{c_struct} *s = (%{c_struct}*)Nativeint_val(handle);
%{body}
}
|}
;;

let gen_c_extension_chain_stubs (struct_ : Ir.struct_) : string =
  match struct_.type_ with
  | Ir.Extension_in _ | Ir.Extension_out _ ->
    let c_name = c_type_name struct_.name in
    let lower_name = String.lowercase struct_.name in
    {%string|/* Extension chain functions for %{c_name} */
CAMLprim value caml_wgpu_%{lower_name}_set_chain_stype(value handle, value stype) {
  CAMLparam2(handle, stype);
  %{c_name} *s = (%{c_name}*)Nativeint_val(handle);
  s->chain.sType = Int_val(stype);
  CAMLreturn(Val_unit);
}

CAMLprim value caml_wgpu_%{lower_name}_as_chained(value handle) {
  CAMLparam1(handle);
  %{c_name} *s = (%{c_name}*)Nativeint_val(handle);
  CAMLreturn(caml_copy_nativeint((intnat)&s->chain));
}
|}
  | Ir.Base_in ->
    (* Base input structs use WGPUChainedStruct *)
    let c_name = c_type_name struct_.name in
    let lower_name = String.lowercase struct_.name in
    {%string|/* nextInChain setter for %{c_name} */
CAMLprim value caml_wgpu_%{lower_name}_set_next_in_chain(value handle, value chain) {
  CAMLparam2(handle, chain);
  %{c_name} *s = (%{c_name}*)Nativeint_val(handle);
  s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
  CAMLreturn(Val_unit);
}
|}
  | Ir.Base_out | Ir.Base_in_out ->
    (* Base output structs use WGPUChainedStructOut *)
    let c_name = c_type_name struct_.name in
    let lower_name = String.lowercase struct_.name in
    {%string|/* nextInChain setter for %{c_name} */
CAMLprim value caml_wgpu_%{lower_name}_set_next_in_chain(value handle, value chain) {
  CAMLparam2(handle, chain);
  %{c_name} *s = (%{c_name}*)Nativeint_val(handle);
  s->nextInChain = (WGPUChainedStructOut *)Nativeint_val(chain);
  CAMLreturn(Val_unit);
}
|}
  | Ir.Standalone -> ""
;;

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

let gen_ml_struct (struct_ : Ir.struct_) : string =
  let type_name = struct_.name in
  let module_name = ocaml_module_name struct_.name in
  (* External declarations *)
  let struct_lower = String.lowercase struct_.name in
  let create_ext =
    {%string|external %{type_name}_create : unit -> nativeint = "caml_wgpu_%{struct_lower}_create"|}
  in
  let free_ext =
    {%string|external %{type_name}_free : nativeint -> unit = "caml_wgpu_%{struct_lower}_free"|}
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
      let struct_lower = String.lowercase struct_.name in
      let member_lower = String.lowercase member.name in
      {%string|external %{type_name}_set_%{member.name} : nativeint -> %{ml_type} -> unit = "caml_wgpu_%{struct_lower}_set_%{member_lower}"|})
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
      let struct_lower = String.lowercase struct_.name in
      let member_lower = String.lowercase member.name in
      {%string|external %{type_name}_get_%{member.name} : nativeint -> %{ml_type} = "caml_wgpu_%{struct_lower}_get_%{member_lower}"|})
    |> String.concat ~sep:"\n"
  in
  (* Extension chain functions for extension structs, or nextInChain setter for base structs *)
  let chain_exts =
    match struct_.type_ with
    | Ir.Extension_in _ | Ir.Extension_out _ ->
      let lower_name = String.lowercase struct_.name in
      {%string|

  external %{type_name}_set_chain_stype : nativeint -> int -> unit = "caml_wgpu_%{lower_name}_set_chain_stype"

  external %{type_name}_as_chained : nativeint -> nativeint = "caml_wgpu_%{lower_name}_as_chained"|}
    | Ir.Base_in | Ir.Base_out | Ir.Base_in_out ->
      let lower_name = String.lowercase struct_.name in
      {%string|

  external %{type_name}_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_%{lower_name}_set_next_in_chain"|}
    | Ir.Standalone -> ""
  in
  let setter_exts_indented = indent_lines setter_exts in
  let getter_exts_indented = indent_lines getter_exts in
  {%string|module %{module_name} = struct
  type t = nativeint

  %{create_ext}

  %{free_ext}

%{setter_exts_indented}

%{getter_exts_indented}%{chain_exts}
end
|}
;;

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
      {%string|  val %{type_name}_set_%{member.name} : t -> %{ml_type} -> unit|})
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
      {%string|  val %{type_name}_get_%{member.name} : t -> %{ml_type}|})
    |> String.concat ~sep:"\n"
  in
  (* Extension chain function signatures, or nextInChain setter for base structs *)
  let chain_sigs =
    match struct_.type_ with
    | Ir.Extension_in _ | Ir.Extension_out _ ->
      {%string|
  val %{type_name}_set_chain_stype : t -> int -> unit
  val %{type_name}_as_chained : t -> nativeint|}
    | Ir.Base_in | Ir.Base_out | Ir.Base_in_out ->
      {%string|
  val %{type_name}_set_next_in_chain : t -> nativeint -> unit|}
    | Ir.Standalone -> ""
  in
  {%string|module %{module_name} : sig
  type t = nativeint
  val %{type_name}_create : unit -> t
  val %{type_name}_free : t -> unit
%{setter_sigs}
%{getter_sigs}%{chain_sigs}
end
|}
;;

let method_is_async = Predicates.method_is_async

let method_is_manual (obj_name : string) (method_name : string) : bool =
  match obj_name, method_name with
  | "adapter", "get_info" -> true
  (* device.get_queue is now auto-generated *)
  | _ -> false
;;

let gen_c_array_conversion (arg : Ir.arg) : string =
  match arg.type_ with
  | Array { elem; _ } ->
    let elem_c_type = c_type_of_type_ref elem in
    let count_var = {%string|c_%{arg.name}_count|} in
    let array_var = {%string|c_%{arg.name}|} in
    let copy_code =
      match elem with
      | Object _ ->
        {%string|  for (size_t i = 0; i < %{count_var}; i++) {
    %{array_var}[i] = (%{elem_c_type})Nativeint_val(Field(%{arg.name}, i));
  }|}
      | Struct name ->
        (* For structs, we need to copy the struct contents, not just pointers *)
        let c_type = c_type_name name in
        {%string|  for (size_t i = 0; i < %{count_var}; i++) {
    %{c_type} *src = (%{c_type}*)Nativeint_val(Field(%{arg.name}, i));
    %{array_var}[i] = *src;
  }|}
      | Enum _ | Bitflag _ ->
        {%string|  for (size_t i = 0; i < %{count_var}; i++) {
    %{array_var}[i] = (%{elem_c_type})Int_val(Field(%{arg.name}, i));
  }|}
      | Primitive (Uint32 | Int32) ->
        {%string|  for (size_t i = 0; i < %{count_var}; i++) {
    %{array_var}[i] = (%{elem_c_type})Int_val(Field(%{arg.name}, i));
  }|}
      | Primitive (Uint64 | Int64) ->
        {%string|  for (size_t i = 0; i < %{count_var}; i++) {
    %{array_var}[i] = (%{elem_c_type})Int64_val(Field(%{arg.name}, i));
  }|}
      | _ ->
        {%string|  for (size_t i = 0; i < %{count_var}; i++) {
    %{array_var}[i] = (%{elem_c_type})Nativeint_val(Field(%{arg.name}, i));
  }|}
    in
    {%string|  size_t %{count_var} = Wosize_val(%{arg.name});
  %{elem_c_type}* %{array_var} = (%{count_var} > 0) ? alloca(%{count_var} * sizeof(%{elem_c_type})) : NULL;
%{copy_code}|}
  | _ -> ""
;;

let gen_c_method_stub (obj : Ir.object_) (method_ : Ir.method_) : string =
  (* Skip async methods and manually implemented methods *)
  if method_is_async method_
  then {%string|/* TODO: async method %{obj.name}.%{method_.name} */
|}
  else if method_is_manual obj.name method_.name
  then {%string|/* Manually implemented: %{obj.name}.%{method_.name} */
|}
  else (
    let c_func = c_method_name obj.name method_.name in
    let obj_lower = String.lowercase obj.name in
    let method_lower = String.lowercase method_.name in
    let caml_func = {%string|caml_wgpu_%{obj_lower}_%{method_lower}|} in
    let obj_c_type = c_type_name obj.name in
    (* Build parameter list for CAMLparam *)
    let all_params = "self" :: List.map method_.args ~f:(fun arg -> arg.name) in
    let num_params = List.length all_params in
    let caml_param =
      if num_params <= 5
      then (
        let params_str = String.concat ~sep:", " all_params in
        {%string|CAMLparam%{num_params#Int}(%{params_str})|})
      else (
        (* Need multiple CAMLparam calls *)
        let first5 = List.take all_params 5 in
        let rest = List.drop all_params 5 in
        let first5_str = String.concat ~sep:", " first5 in
        let rest_len = List.length rest in
        let rest_str = String.concat ~sep:", " rest in
        {%string|CAMLparam5(%{first5_str});
  CAMLxparam%{rest_len#Int}(%{rest_str})|})
    in
    (* Build value parameter declarations *)
    let value_params =
      "value self" :: List.map method_.args ~f:(fun arg -> {%string|value %{arg.name}|})
    in
    (* Build argument conversion *)
    let arg_conversions =
      List.map method_.args ~f:(fun arg ->
        let c_type = c_type_of_type_ref arg.type_ in
        match arg.type_ with
        | Primitive Bool -> {%string|  bool c_%{arg.name} = Bool_val(%{arg.name});|}
        | Primitive Uint32 -> {%string|  uint32_t c_%{arg.name} = Int_val(%{arg.name});|}
        | Primitive Uint64 ->
          {%string|  uint64_t c_%{arg.name} = Int64_val(%{arg.name});|}
        | Primitive Int32 -> {%string|  int32_t c_%{arg.name} = Int_val(%{arg.name});|}
        | Primitive Int64 -> {%string|  int64_t c_%{arg.name} = Int64_val(%{arg.name});|}
        | Primitive Float32 -> {%string|  float c_%{arg.name} = Double_val(%{arg.name});|}
        | Primitive Float64 ->
          {%string|  double c_%{arg.name} = Double_val(%{arg.name});|}
        | Primitive Usize -> {%string|  size_t c_%{arg.name} = Int64_val(%{arg.name});|}
        | Primitive (String | Out_string | String_with_default_empty) ->
          {%string|  WGPUStringView c_%{arg.name} = { .data = String_val(%{arg.name}), .length = caml_string_length(%{arg.name}) };|}
        | Primitive C_void ->
          {%string|  void* c_%{arg.name} = (void*)Nativeint_val(%{arg.name});|}
        | Enum _ | Bitflag _ ->
          {%string|  %{c_type} c_%{arg.name} = Int_val(%{arg.name});|}
        | Object _ ->
          {%string|  %{c_type} c_%{arg.name} = (%{c_type})Nativeint_val(%{arg.name});|}
        | Struct _ ->
          (* For struct pointers, we pass the nativeint as a pointer *)
          {%string|  %{c_type}* c_%{arg.name} = (%{c_type}*)Nativeint_val(%{arg.name});|}
        | Pointer { inner = Struct _; _ } ->
          {%string|  %{c_type} c_%{arg.name} = (%{c_type})Nativeint_val(%{arg.name});|}
        | Array _ -> gen_c_array_conversion arg
        | _ -> {%string|  /* TODO: convert %{arg.name} */|})
      |> String.concat ~sep:"\n"
    in
    (* Build C function call arguments - arrays need count + pointer *)
    let c_args =
      "c_self"
      :: List.concat_map method_.args ~f:(fun arg ->
        match arg.type_ with
        | Array _ ->
          (* Array args become count, pointer pair in C API *)
          [ {%string|c_%{arg.name}_count|}; {%string|c_%{arg.name}|} ]
        | _ -> [ {%string|c_%{arg.name}|} ])
    in
    let c_call_args = String.concat ~sep:", " c_args in
    (* Build return handling *)
    let return_code =
      match method_.returns with
      | None -> {%string|  %{c_func}(%{c_call_args});
  CAMLreturn(Val_unit);|}
      | Some ret ->
        let ret_c_type = c_type_of_type_ref ret.type_ in
        (match ret.type_ with
         | Primitive Bool ->
           {%string|  bool result = %{c_func}(%{c_call_args});
  CAMLreturn(Val_bool(result));|}
         | Primitive (Uint32 | Int32) ->
           {%string|  %{ret_c_type} result = %{c_func}(%{c_call_args});
  CAMLreturn(Val_int(result));|}
         | Primitive (Uint64 | Int64 | Usize) ->
           {%string|  %{ret_c_type} result = %{c_func}(%{c_call_args});
  CAMLreturn(caml_copy_int64(result));|}
         | Primitive (Float32 | Float64) ->
           {%string|  %{ret_c_type} result = %{c_func}(%{c_call_args});
  CAMLreturn(caml_copy_double(result));|}
         | Object _ ->
           {%string|  %{ret_c_type} result = %{c_func}(%{c_call_args});
  CAMLreturn(caml_copy_nativeint((intnat)result));|}
         | Enum _ | Bitflag _ ->
           {%string|  %{ret_c_type} result = %{c_func}(%{c_call_args});
  CAMLreturn(Val_int(result));|}
         | _ ->
           {%string|  /* TODO: return type */
  %{c_func}(%{c_call_args});
  CAMLreturn(Val_unit);|})
    in
    (* Handle bytecode calling convention for many args *)
    let bytecode_decl =
      if num_params > 5
      then (
        let argv_args =
          List.mapi all_params ~f:(fun i _ -> {%string|argv[%{i#Int}]|})
          |> String.concat ~sep:", "
        in
        {%string|
CAMLprim value %{caml_func}_bytecode(value *argv, int argn) {
  (void)argn;
  return %{caml_func}(%{argv_args});
}|})
      else ""
    in
    let value_params_str = String.concat ~sep:", " value_params in
    {%string|CAMLprim value %{caml_func}(%{value_params_str}) {
  %{caml_param};
  %{obj_c_type} c_self = (%{obj_c_type})Nativeint_val(self);
%{arg_conversions}
%{return_code}
}%{bytecode_decl}
|})
;;

let gen_c_object_stubs (obj : Ir.object_) : string =
  let c_type = c_type_name obj.name in
  (* Generate release function *)
  let obj_lower = String.lowercase obj.name in
  let c_func_name = c_function_name obj.name in
  let release =
    {%string|CAMLprim value caml_wgpu_%{obj_lower}_release(value handle) {
  CAMLparam1(handle);
  %{c_type} obj = (%{c_type})Nativeint_val(handle);
  if (obj != NULL) {
    %{c_func_name}Release(obj);
  }
  CAMLreturn(Val_unit);
}|}
  in
  (* Generate method stubs *)
  let methods =
    List.map obj.methods ~f:(gen_c_method_stub obj) |> String.concat ~sep:"\n"
  in
  {%string|/* Object: %{c_type} */
%{release}

%{methods}|}
;;

let ml_type_of_type_ref (type_ref : Ir.type_ref) : string =
  Type_mapping.type_string ~context:Ocaml_low_level type_ref
;;

let gen_ml_method (obj : Ir.object_) (method_ : Ir.method_) : string =
  if method_is_async method_
  then {%string|(* TODO: async method %{obj.name}_%{method_.name} *)|}
  else if method_is_manual obj.name method_.name
  then "" (* Already defined manually *)
  else (
    let func_name = {%string|%{obj.name}_%{method_.name}|} in
    let obj_lower = String.lowercase obj.name in
    let method_lower = String.lowercase method_.name in
    let caml_func = {%string|caml_wgpu_%{obj_lower}_%{method_lower}|} in
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
      {%string|external %{func_name} : %{type_sig} = "%{caml_func}_bytecode" "%{caml_func}"|}
    else {%string|external %{func_name} : %{type_sig} = "%{caml_func}"|})
;;

let gen_ml_object_type (obj : Ir.object_) : string =
  {%string|type %{obj.name} = nativeint
|}
;;

let gen_ml_object_methods (obj : Ir.object_) : string =
  let obj_lower = String.lowercase obj.name in
  let release =
    {%string|external %{obj.name}_release : %{obj.name} -> unit = "caml_wgpu_%{obj_lower}_release"
|}
  in
  let methods =
    List.filter_map obj.methods ~f:(fun m ->
      let s = gen_ml_method obj m in
      if String.is_empty s then None else Some s)
    |> String.concat ~sep:"\n"
  in
  release ^ methods
;;

let gen_ml_object (obj : Ir.object_) : string =
  gen_ml_object_type obj ^ "\n" ^ gen_ml_object_methods obj ^ "\n"
;;

let gen_mli_method (obj : Ir.object_) (method_ : Ir.method_) : string =
  if method_is_async method_ || method_is_manual obj.name method_.name
  then ""
  else (
    let func_name = {%string|%{obj.name}_%{method_.name}|} in
    let arg_types =
      obj.name :: List.map method_.args ~f:(fun arg -> ml_type_of_type_ref arg.type_)
    in
    let ret_type =
      match method_.returns with
      | None -> "unit"
      | Some ret -> ml_type_of_type_ref ret.type_
    in
    let type_sig = String.concat ~sep:" -> " arg_types ^ " -> " ^ ret_type in
    {%string|val %{func_name} : %{type_sig}|})
;;

let gen_mli_object_type (obj : Ir.object_) : string =
  {%string|type %{obj.name} = nativeint
|}
;;

let gen_mli_object_methods (obj : Ir.object_) : string =
  let release = {%string|val %{obj.name}_release : %{obj.name} -> unit
|} in
  let methods =
    List.filter_map obj.methods ~f:(fun m ->
      let s = gen_mli_method obj m in
      if String.is_empty s then None else Some s)
    |> String.concat ~sep:"\n"
  in
  if String.is_empty methods then release else release ^ methods ^ "\n"
;;

let gen_mli_object (obj : Ir.object_) : string =
  gen_mli_object_type obj ^ "\n" ^ gen_mli_object_methods obj
;;

let gen_c_function_stubs (func : Ir.function_) : string =
  let c_name = c_function_name func.name in
  match func.name with
  | "create_instance" ->
    {|CAMLprim value caml_wgpu_create_instance(value unit) {
  CAMLparam1(unit);
  WGPUInstanceDescriptor desc = {
    .nextInChain = NULL,
  };
  WGPUInstance instance = wgpuCreateInstance(&desc);
  CAMLreturn(caml_copy_nativeint((intnat)instance));
}|}
  | _ -> {%string|/* TODO: %{c_name} */
|}
;;

let gen_c_sync_helpers () : string = read_template "low/sync_helpers.c"

let gen_c_stubs (api : Ir.api) : string =
  let header = read_template "low/header.c" in
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
  let functions = read_template "low/convenience_functions.ml" in
  String.concat
    [ header; enums; bitflags; structs; object_types; "\n"; object_methods; functions ]
;;

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
  let functions = read_template "low/convenience_functions.mli" in
  String.concat
    [ header; enums; bitflags; structs; object_types; "\n"; object_methods; functions ]
;;
