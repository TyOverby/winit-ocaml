open! Core

(** Integration tests for method code generation *)

(* Sample objects and methods for testing *)

let simple_object : Ir.object_ = { name = "buffer"; doc = "A GPU buffer"; methods = [] }

let simple_method_no_args : Ir.method_ =
  { name = "get_size"
  ; doc = "Get the size of the buffer"
  ; args = []
  ; returns = Some { type_ = Primitive Uint64; doc = "Size in bytes" }
  ; callback = None
  }
;;

let simple_method_with_args : Ir.method_ =
  { name = "set_label"
  ; doc = "Set the label"
  ; args =
      [ { name = "label"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "The label"
        ; pointer = None
        }
      ]
  ; returns = None
  ; callback = None
  }
;;

let method_with_enum_arg : Ir.method_ =
  { name = "set_format"
  ; doc = "Set the texture format"
  ; args =
      [ { name = "format"
        ; type_ = Enum "texture_format"
        ; optional = false
        ; doc = "The format"
        ; pointer = None
        }
      ]
  ; returns = None
  ; callback = None
  }
;;

let method_with_object_arg : Ir.method_ =
  { name = "set_bind_group"
  ; doc = "Set a bind group"
  ; args =
      [ { name = "index"
        ; type_ = Primitive Uint32
        ; optional = false
        ; doc = "Bind group index"
        ; pointer = None
        }
      ; { name = "bind_group"
        ; type_ = Object "bind_group"
        ; optional = false
        ; doc = "The bind group"
        ; pointer = None
        }
      ]
  ; returns = None
  ; callback = None
  }
;;

let method_returning_object : Ir.method_ =
  { name = "create_view"
  ; doc = "Create a texture view"
  ; args = []
  ; returns = Some { type_ = Object "texture_view"; doc = "The texture view" }
  ; callback = None
  }
;;

let method_with_array_arg : Ir.method_ =
  { name = "write_buffer"
  ; doc = "Write data to buffer"
  ; args =
      [ { name = "buffer"
        ; type_ = Object "buffer"
        ; optional = false
        ; doc = "The buffer"
        ; pointer = None
        }
      ; { name = "data"
        ; type_ = Array { elem = Primitive Uint32; pointer = None }
        ; optional = false
        ; doc = "The data"
        ; pointer = None
        }
      ]
  ; returns = None
  ; callback = None
  }
;;

let async_method : Ir.method_ =
  { name = "request_adapter"
  ; doc = "Request an adapter"
  ; args = []
  ; returns = None
  ; callback = Some "request_adapter_callback"
  }
;;

let method_with_bitflag_arg : Ir.method_ =
  { name = "create_buffer"
  ; doc = "Create a buffer"
  ; args =
      [ { name = "size"
        ; type_ = Primitive Uint64
        ; optional = false
        ; doc = "Buffer size"
        ; pointer = None
        }
      ; { name = "usage"
        ; type_ = Bitflag "buffer_usage"
        ; optional = false
        ; doc = "Buffer usage flags"
        ; pointer = None
        }
      ]
  ; returns = Some { type_ = Object "buffer"; doc = "The buffer" }
  ; callback = None
  }
;;

let texture_object : Ir.object_ =
  { name = "texture"
  ; doc = "A GPU texture"
  ; methods = [ simple_method_no_args; method_returning_object ]
  }
;;

let queue_object : Ir.object_ =
  { name = "queue"; doc = "A GPU command queue"; methods = [ method_with_array_arg ] }
;;

(* ===== Gen_low method tests ===== *)

let%expect_test "Gen_low.gen_ml_method - no args, returns primitive" =
  print_endline (Gen_low.gen_ml_method simple_object simple_method_no_args);
  [%expect {| external buffer_get_size : buffer -> int64 = "caml_wgpu_buffer_get_size" |}]
;;

let%expect_test "Gen_low.gen_ml_method - with string arg" =
  print_endline (Gen_low.gen_ml_method simple_object simple_method_with_args);
  [%expect
    {| external buffer_set_label : buffer -> string -> unit = "caml_wgpu_buffer_set_label" |}]
;;

let%expect_test "Gen_low.gen_ml_method - with enum arg" =
  print_endline (Gen_low.gen_ml_method simple_object method_with_enum_arg);
  [%expect
    {| external buffer_set_format : buffer -> int -> unit = "caml_wgpu_buffer_set_format" |}]
;;

let%expect_test "Gen_low.gen_ml_method - with object arg" =
  print_endline (Gen_low.gen_ml_method simple_object method_with_object_arg);
  [%expect
    {| external buffer_set_bind_group : buffer -> int -> bind_group -> unit = "caml_wgpu_buffer_set_bind_group" |}]
;;

let%expect_test "Gen_low.gen_ml_method - returns object" =
  print_endline (Gen_low.gen_ml_method simple_object method_returning_object);
  [%expect
    {| external buffer_create_view : buffer -> texture_view = "caml_wgpu_buffer_create_view" |}]
;;

let%expect_test "Gen_low.gen_ml_method - with array arg" =
  print_endline (Gen_low.gen_ml_method queue_object method_with_array_arg);
  [%expect
    {| external queue_write_buffer : queue -> buffer -> int array -> unit = "caml_wgpu_queue_write_buffer" |}]
;;

let%expect_test "Gen_low.gen_ml_method - async method (skipped)" =
  print_endline (Gen_low.gen_ml_method simple_object async_method);
  [%expect {| (* TODO: async method buffer_request_adapter *) |}]
;;

let%expect_test "Gen_low.gen_mli_method - no args, returns primitive" =
  print_endline (Gen_low.gen_mli_method simple_object simple_method_no_args);
  [%expect {| val buffer_get_size : buffer -> int64 |}]
;;

let%expect_test "Gen_low.gen_mli_method - with object arg" =
  print_endline (Gen_low.gen_mli_method simple_object method_with_object_arg);
  [%expect {| val buffer_set_bind_group : buffer -> int -> bind_group -> unit |}]
;;

let%expect_test "Gen_low.gen_mli_method - async method (skipped)" =
  print_endline (Gen_low.gen_mli_method simple_object async_method);
  [%expect {| |}]
;;

(* ===== Gen_low C method stub tests ===== *)

let%expect_test "Gen_low.gen_c_method_stub - no args, returns primitive" =
  print_endline (Gen_low.gen_c_method_stub simple_object simple_method_no_args);
  [%expect
    {|
    CAMLprim value caml_wgpu_buffer_get_size(value self) {
      CAMLparam1(self);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);

      uint64_t result = wgpuBufferGetSize(c_self);
      CAMLreturn(caml_copy_int64(result));
    }
    |}]
;;

let%expect_test "Gen_low.gen_c_method_stub - with string arg" =
  print_endline (Gen_low.gen_c_method_stub simple_object simple_method_with_args);
  [%expect
    {|
    CAMLprim value caml_wgpu_buffer_set_label(value self, value label) {
      CAMLparam2(self, label);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      WGPUStringView c_label = { .data = String_val(label), .length = caml_string_length(label) };
      wgpuBufferSetLabel(c_self, c_label);
      CAMLreturn(Val_unit);
    }
    |}]
;;

let%expect_test "Gen_low.gen_c_method_stub - with enum arg" =
  print_endline (Gen_low.gen_c_method_stub simple_object method_with_enum_arg);
  [%expect
    {|
    CAMLprim value caml_wgpu_buffer_set_format(value self, value format) {
      CAMLparam2(self, format);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      WGPUTextureFormat c_format = Int_val(format);
      wgpuBufferSetFormat(c_self, c_format);
      CAMLreturn(Val_unit);
    }
    |}]
;;

let%expect_test "Gen_low.gen_c_method_stub - with object arg" =
  print_endline (Gen_low.gen_c_method_stub simple_object method_with_object_arg);
  [%expect
    {|
    CAMLprim value caml_wgpu_buffer_set_bind_group(value self, value index, value bind_group) {
      CAMLparam3(self, index, bind_group);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      uint32_t c_index = Int_val(index);
      WGPUBindGroup c_bind_group = (WGPUBindGroup)Nativeint_val(bind_group);
      wgpuBufferSetBindGroup(c_self, c_index, c_bind_group);
      CAMLreturn(Val_unit);
    }
    |}]
;;

let%expect_test "Gen_low.gen_c_method_stub - returns object" =
  print_endline (Gen_low.gen_c_method_stub simple_object method_returning_object);
  [%expect
    {|
    CAMLprim value caml_wgpu_buffer_create_view(value self) {
      CAMLparam1(self);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);

      WGPUTextureView result = wgpuBufferCreateView(c_self);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }
    |}]
;;

let%expect_test "Gen_low.gen_c_method_stub - with array arg" =
  print_endline (Gen_low.gen_c_method_stub queue_object method_with_array_arg);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.gen_c_method_stub - async method (skipped)" =
  print_endline (Gen_low.gen_c_method_stub simple_object async_method);
  [%expect {| /* TODO: async method buffer.request_adapter */ |}]
;;

(* ===== Gen_high method tests ===== *)

(* Note: Gen_high methods require a structs list for auto-generation checks *)
let empty_structs : Ir.struct_ list = []

let%expect_test "Gen_high.gen_ml_method - simple method no args" =
  let result = Gen_high.gen_ml_method empty_structs simple_object simple_method_no_args in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| let get_size t = Wgpu_low.buffer_get_size t.handle |}]
;;

let%expect_test "Gen_high.gen_ml_method - method with string arg" =
  let result =
    Gen_high.gen_ml_method empty_structs simple_object simple_method_with_args
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| let set_label t ~label = Wgpu_low.buffer_set_label t.handle label |}]
;;

let%expect_test "Gen_high.gen_ml_method - method with enum arg" =
  let result = Gen_high.gen_ml_method empty_structs simple_object method_with_enum_arg in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {| let set_format t ~format = Wgpu_low.buffer_set_format t.handle (Texture_format.to_int format) |}]
;;

let%expect_test "Gen_high.gen_ml_method - method with object arg" =
  let result =
    Gen_high.gen_ml_method empty_structs simple_object method_with_object_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {| let set_bind_group t ~index ~bind_group = Wgpu_low.buffer_set_bind_group t.handle index bind_group.Bind_group.handle |}]
;;

let%expect_test "Gen_high.gen_ml_method - method returning object" =
  let result =
    Gen_high.gen_ml_method empty_structs simple_object method_returning_object
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {| let create_view t = ({ Texture_view.handle = Wgpu_low.buffer_create_view t.handle } : Texture_view.t) |}]
;;

let%expect_test "Gen_high.gen_ml_method - method with bitflag arg" =
  let result =
    Gen_high.gen_ml_method empty_structs simple_object method_with_bitflag_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {| let create_buffer t ~size ~usage = ({ Buffer.handle = Wgpu_low.buffer_create_buffer t.handle size (Buffer_usage.list_to_int usage) } : Buffer.t) |}]
;;

let%expect_test "Gen_high.gen_ml_method - async method returns None" =
  let result = Gen_high.gen_ml_method empty_structs simple_object async_method in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| (none) |}]
;;

let%expect_test "Gen_high.gen_mli_method - simple method no args" =
  let result =
    Gen_high.gen_mli_method empty_structs simple_object simple_method_no_args
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| val get_size : t -> int64 |}]
;;

let%expect_test "Gen_high.gen_mli_method - method with string arg" =
  let result =
    Gen_high.gen_mli_method empty_structs simple_object simple_method_with_args
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| val set_label : t -> label:string -> unit |}]
;;

let%expect_test "Gen_high.gen_mli_method - method with enum arg" =
  let result = Gen_high.gen_mli_method empty_structs simple_object method_with_enum_arg in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| val set_format : t -> format:Texture_format.t -> unit |}]
;;

let%expect_test "Gen_high.gen_mli_method - method with object arg" =
  let result =
    Gen_high.gen_mli_method empty_structs simple_object method_with_object_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| val set_bind_group : t -> index:int -> bind_group:Bind_group.t -> unit |}]
;;

let%expect_test "Gen_high.gen_mli_method - method returning object" =
  let result =
    Gen_high.gen_mli_method empty_structs simple_object method_returning_object
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| val create_view : t -> Texture_view.t |}]
;;

let%expect_test "Gen_high.gen_mli_method - method with bitflag arg" =
  let result =
    Gen_high.gen_mli_method empty_structs simple_object method_with_bitflag_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {| val create_buffer : t -> size:int64 -> usage:Buffer_usage.t list -> Buffer.t |}]
;;

let%expect_test "Gen_high.gen_mli_method - async method returns None" =
  let result = Gen_high.gen_mli_method empty_structs simple_object async_method in
  print_endline (Option.value result ~default:"(none)");
  [%expect {| (none) |}]
;;

(* ===== Test methods with struct parameters ===== *)

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

let%expect_test "Gen_high.gen_ml_method - method with struct parameter" =
  let result = Gen_high.gen_ml_method structs_list device_object method_with_struct_arg in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {|
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

let%expect_test "Gen_high.gen_mli_method - method with struct parameter" =
  let result =
    Gen_high.gen_mli_method structs_list device_object method_with_struct_arg
  in
  print_endline (Option.value result ~default:"(none)");
  [%expect
    {|
    val create_buffer : t -> ?label:string -> size:int64 -> usage:Buffer_usage.t list -> unit -> Buffer.t
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

let%expect_test "Gen_high.gen_ml_method_with_output_struct" =
  let result =
    Gen_high.gen_ml_method_with_output_struct
      adapter_object
      method_with_output_struct
      output_struct
      (List.hd_exn method_with_output_struct.args)
  in
  print_endline result;
  [%expect
    {|
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

let%expect_test "Gen_high.gen_mli_method_with_output_struct" =
  let result =
    Gen_high.gen_mli_method_with_output_struct
      adapter_object
      method_with_output_struct
      output_struct
  in
  print_endline result;
  [%expect {|
    val get_info : t -> adapter_info
    |}]
;;
