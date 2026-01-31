open! Core

(** Integration tests for method code generation using inline YAML *)

(* Helper to extract first method from parsed object *)
let first_method obj =
  match obj.Ir.methods with
  | m :: _ -> m
  | [] -> failwith "Object has no methods"
;;

let%expect_test "method - get_size (no args, returns primitive)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: get_size
    doc: Get the size of the buffer
    returns:
      type: uint64
      doc: Size in bytes
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_get_size(value self) {
      CAMLparam1(self);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);

      uint64_t result = wgpuBufferGetSize(c_self);
      CAMLreturn(caml_copy_int64(result));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect {|
    === Low-level MLI ===
    val buffer_get_size : buffer -> int64
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    external buffer_get_size : buffer -> int64 = "caml_wgpu_buffer_get_size"
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect {|
    === High-level MLI ===
      val get_size : t -> int64
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let get_size t = Wgpu_low.buffer_get_size t.handle
    |}]
;;

let%expect_test "method - set_label (with string arg)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: set_label
    doc: Set the label
    args:
      - name: label
        type: string
        doc: The label
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_set_label(value self, value label) {
      CAMLparam2(self, label);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      WGPUStringView c_label = { .data = String_val(label), .length = caml_string_length(label) };
      wgpuBufferSetLabel(c_self, c_label);
      CAMLreturn(Val_unit);
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect
    {|
    === Low-level MLI ===
    val buffer_set_label : buffer -> string -> unit
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    external buffer_set_label : buffer -> string -> unit = "caml_wgpu_buffer_set_label"
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level MLI ===
      val set_label : t -> label:string -> unit
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let set_label t ~label = Wgpu_low.buffer_set_label t.handle label
    |}]
;;

let%expect_test "method - set_format (with enum arg)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: set_format
    doc: Set the texture format
    args:
      - name: format
        type: enum.texture_format
        doc: The format
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_set_format(value self, value format) {
      CAMLparam2(self, format);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      WGPUTextureFormat c_format = Int_val(format);
      wgpuBufferSetFormat(c_self, c_format);
      CAMLreturn(Val_unit);
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect
    {|
    === Low-level MLI ===
    val buffer_set_format : buffer -> int -> unit
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    external buffer_set_format : buffer -> int -> unit = "caml_wgpu_buffer_set_format"
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level MLI ===
      val set_format : t -> format:Texture_format.t -> unit
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let set_format t ~format = Wgpu_low.buffer_set_format t.handle (Texture_format.to_int format)
    |}]
;;

let%expect_test "method - set_bind_group (with object arg)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: set_bind_group
    doc: Set a bind group
    args:
      - name: index
        type: uint32
        doc: Bind group index
      - name: bind_group
        type: object.bind_group
        doc: The bind group
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_set_bind_group(value self, value index, value bind_group) {
      CAMLparam3(self, index, bind_group);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      uint32_t c_index = Int_val(index);
      WGPUBindGroup c_bind_group = (WGPUBindGroup)Nativeint_val(bind_group);
      wgpuBufferSetBindGroup(c_self, c_index, c_bind_group);
      CAMLreturn(Val_unit);
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect
    {|
    === Low-level MLI ===
    val buffer_set_bind_group : buffer -> int -> bind_group -> unit
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    external buffer_set_bind_group : buffer -> int -> bind_group -> unit = "caml_wgpu_buffer_set_bind_group"
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level MLI ===
      val set_bind_group : t -> index:int -> bind_group:Bind_group.t -> unit
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let set_bind_group t ~index ~bind_group = Wgpu_low.buffer_set_bind_group t.handle index bind_group.Bind_group.handle
    |}]
;;

let%expect_test "method - create_view (returns object)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: create_view
    doc: Create a texture view
    returns:
      type: object.texture_view
      doc: The texture view
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_create_view(value self) {
      CAMLparam1(self);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);

      WGPUTextureView result = wgpuBufferCreateView(c_self);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect
    {|
    === Low-level MLI ===
    val buffer_create_view : buffer -> texture_view
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    external buffer_create_view : buffer -> texture_view = "caml_wgpu_buffer_create_view"
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level MLI ===
      val create_view : t -> Texture_view.t
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let create_view t = ({ Texture_view.handle = Wgpu_low.buffer_create_view t.handle } : Texture_view.t)
    |}]
;;

let%expect_test "method - write_buffer (with array arg)" =
  let yaml =
    {|
name: queue
doc: A GPU command queue
methods:
  - name: write_buffer
    doc: Write data to buffer
    args:
      - name: buffer
        type: object.buffer
        doc: The buffer
      - name: data
        type: array<uint32>
        doc: The data
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_queue_write_buffer(value self, value buffer, value data) {
      CAMLparam3(self, buffer, data);
      WGPUQueue c_self = (WGPUQueue)Nativeint_val(self);
      WGPUBuffer c_buffer = (WGPUBuffer)Nativeint_val(buffer);
      size_t c_data_count = Wosize_val(data);
      uint32_t* c_data = (c_data_count > 0) ? alloca(c_data_count * sizeof(uint32_t)) : NULL;
      for (size_t i = 0; i < c_data_count; i++) {
        c_data[i] = (uint32_t)Int_val(Field(data, i));
      }
      wgpuQueueWriteBuffer(c_self, c_buffer, c_data_count, c_data);
      CAMLreturn(Val_unit);
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect
    {|
    === Low-level MLI ===
    val queue_write_buffer : queue -> buffer -> int array -> unit
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    external queue_write_buffer : queue -> buffer -> int array -> unit = "caml_wgpu_queue_write_buffer"
    |}]
;;

let%expect_test "method - request_adapter (async method is skipped)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: request_adapter
    doc: Request an adapter
    callback: request_adapter_callback
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method buffer.request_adapter */
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  [%expect {|
    === Low-level MLI ===
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  [%expect
    {|
    === Low-level ML ===
    (* TODO: async method buffer_request_adapter *)
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect {|
    === High-level MLI ===
    (none)
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect {|
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "method - create_buffer (with bitflag arg)" =
  let yaml =
    {|
name: buffer
doc: A GPU buffer
methods:
  - name: create_buffer
    doc: Create a buffer
    args:
      - name: size
        type: uint64
        doc: Buffer size
      - name: usage
        type: bitflag.buffer_usage
        doc: Buffer usage flags
    returns:
      type: object.buffer
      doc: The buffer
|}
  in
  let obj = Parse_yml.parse_object (Yaml.of_string_exn yaml) in
  let method_ = first_method obj in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_create_buffer(value self, value size, value usage) {
      CAMLparam3(self, size, usage);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      uint64_t c_size = Int64_val(size);
      WGPUBufferUsage c_usage = Int_val(usage);
      WGPUBuffer result = wgpuBufferCreateBuffer(c_self, c_size, c_usage);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }
    |}];
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level MLI ===
      val create_buffer : t -> size:int64 -> usage:Buffer_usage.Item.t list -> Buffer.t
    |}];
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method [] obj method_ |> Option.value ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let create_buffer t ~size ~usage = ({ Buffer.handle = Wgpu_low.buffer_create_buffer t.handle size (Buffer_usage.list_to_int usage) } : Buffer.t)
    |}]
;;

(* ===== Test methods with struct parameters ===== *)
(* These tests require struct context which is harder to express in simple YAML,
   so we keep them as direct IR for now *)

let simple_descriptor_struct : Ir.struct_ =
  { name = "buffer_descriptor"
  ; doc = "Buffer descriptor"
  ; type_ = Base_in
  ; free_members = false
  ; members =
      [ { name = "label"
        ; type_ = Primitive String_with_default_empty
        ; optional = true
        ; doc = "Label"
        ; pointer = None
        }
      ; { name = "size"
        ; type_ = Primitive Uint64
        ; optional = false
        ; doc = "Size"
        ; pointer = None
        }
      ; { name = "usage"
        ; type_ = Bitflag "buffer_usage"
        ; optional = false
        ; doc = "Usage"
        ; pointer = None
        }
      ]
  }
;;

let structs_list = [ simple_descriptor_struct ]
let device_object : Ir.object_ = { name = "device"; doc = "A GPU device"; methods = [] }

let method_with_struct_arg : Ir.method_ =
  { name = "create_buffer"
  ; doc = "Create a buffer"
  ; args =
      [ { name = "descriptor"
        ; type_ = Struct "buffer_descriptor"
        ; optional = false
        ; doc = "Buffer descriptor"
        ; pointer = Some `Immutable
        }
      ]
  ; returns = Some { type_ = Object "buffer"; doc = "The buffer" }
  ; callback = None
  }
;;

let%expect_test "method - create_buffer (with struct parameter expands to args)" =
  print_endline "=== High-level MLI ===";
  let result =
    Gen_high.For_testing.gen_mli_method structs_list device_object method_with_struct_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {|
    === High-level MLI ===
      val create_buffer : t -> ?label:string -> size:int64 -> usage:Buffer_usage.Item.t list -> unit -> Buffer.t
    |}];
  print_endline "=== High-level ML ===";
  let result =
    Gen_high.For_testing.gen_ml_method structs_list device_object method_with_struct_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {|
    === High-level ML ===
      let create_buffer t ?(label = "") ~size ~usage () =
        let desc_descriptor = Wgpu_low.Buffer_descriptor.buffer_descriptor_create () in
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_label desc_descriptor label;
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_size desc_descriptor size;
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_usage desc_descriptor (Buffer_usage.list_to_int usage);
        let result = Wgpu_low.device_create_buffer t.handle desc_descriptor in
        Wgpu_low.Buffer_descriptor.buffer_descriptor_free desc_descriptor;
        ({ Buffer.handle = result } : Buffer.t)
    |}]
;;

(* ===== Test output struct methods ===== *)

let output_struct : Ir.struct_ =
  { name = "adapter_info"
  ; doc = "Adapter information"
  ; type_ = Base_out
  ; free_members = false
  ; members =
      [ { name = "vendor"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "Vendor name"
        ; pointer = None
        }
      ; { name = "device"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "Device name"
        ; pointer = None
        }
      ]
  }
;;

let structs_with_output = [ output_struct ]

let adapter_object : Ir.object_ =
  { name = "adapter"; doc = "A GPU adapter"; methods = [] }
;;

let method_with_output_struct : Ir.method_ =
  { name = "get_info"
  ; doc = "Get adapter information"
  ; args =
      [ { name = "info"
        ; type_ = Struct "adapter_info"
        ; optional = false
        ; doc = "Output info struct"
        ; pointer = Some `Mutable
        }
      ]
  ; returns = Some { type_ = Primitive Uint32; doc = "Status" }
  ; callback = None
  }
;;

let%expect_test "method - get_info (with output struct returns record)" =
  print_endline "=== High-level MLI ===";
  let result =
    Gen_high.For_testing.gen_mli_method_with_output_struct
      adapter_object
      method_with_output_struct
      output_struct
  in
  print_endline result;
  [%expect {|
    === High-level MLI ===
      val get_info : t -> adapter_info
    |}];
  print_endline "=== High-level ML ===";
  let result =
    Gen_high.For_testing.gen_ml_method_with_output_struct
      adapter_object
      method_with_output_struct
      output_struct
      (List.hd_exn method_with_output_struct.args)
  in
  print_endline result;
  [%expect
    {|
    === High-level ML ===
      let get_info t =
        let output = Wgpu_low.Adapter_info.adapter_info_create () in
        let _status = Wgpu_low.adapter_get_info t.handle output in
        let vendor = (Wgpu_low.Adapter_info.adapter_info_get_vendor output) in
        let device = (Wgpu_low.Adapter_info.adapter_info_get_device output) in
        let result = { vendor; device } in
        Wgpu_low.Adapter_info.adapter_info_free output;
        result
    |}]
;;
