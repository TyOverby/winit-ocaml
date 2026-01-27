open! Core
open Test_regression

(* This module is just for testing that the regression test infrastructure works.
   Don't add any real regression tests to this file! *)

(** {2 Enum Tests} *)

let%expect_test "enum - texture_format (real API enum with many entries)" =
  let enum = lookup_enum "adapter_type" in
  print_enum_outputs enum;
  [%expect
    {|
    === Low-level C ===
    /* Enum: WGPUAdapterType */
    CAMLprim value caml_wgpu_adapter_type_discrete_gpu(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUAdapterType_DiscreteGPU));
    }

    CAMLprim value caml_wgpu_adapter_type_integrated_gpu(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUAdapterType_IntegratedGPU));
    }

    CAMLprim value caml_wgpu_adapter_type_cpu(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUAdapterType_CPU));
    }

    CAMLprim value caml_wgpu_adapter_type_unknown(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUAdapterType_Unknown));
    }

    === Low-level MLI ===
    module Adapter_type : sig
      type t =
      | Discrete_gpu
      | Integrated_gpu
      | Cpu
      | Unknown

      val to_int : t -> int
      val of_int : int -> t
    end

    === Low-level ML ===
    module Adapter_type = struct
      type t =
      | Discrete_gpu
      | Integrated_gpu
      | Cpu
      | Unknown

    external adapter_type_discrete_gpu : unit -> int = "caml_wgpu_adapter_type_discrete_gpu"
    external adapter_type_integrated_gpu : unit -> int = "caml_wgpu_adapter_type_integrated_gpu"
    external adapter_type_cpu : unit -> int = "caml_wgpu_adapter_type_cpu"
    external adapter_type_unknown : unit -> int = "caml_wgpu_adapter_type_unknown"

      let discrete_gpu_int = adapter_type_discrete_gpu ()
      let integrated_gpu_int = adapter_type_integrated_gpu ()
      let cpu_int = adapter_type_cpu ()
      let unknown_int = adapter_type_unknown ()

      let to_int = function
        | Discrete_gpu -> discrete_gpu_int
        | Integrated_gpu -> integrated_gpu_int
        | Cpu -> cpu_int
        | Unknown -> unknown_int

      let of_int = function
        | x when x = discrete_gpu_int -> Discrete_gpu
        | x when x = integrated_gpu_int -> Integrated_gpu
        | x when x = cpu_int -> Cpu
        | x when x = unknown_int -> Unknown
        | n -> failwith (Printf.sprintf "Adapter_type.of_int: unknown value %d" n)
    end

    === High-level MLI ===
    module Adapter_type : sig
      type t =
      | Discrete_gpu
      | Integrated_gpu
      | Cpu
      | Unknown

      val to_int : t -> int
      val of_int : int -> t
    end

    === High-level ML ===
    module Adapter_type = Wgpu_low.Adapter_type
    |}]
;;

(** {2 Bitflag Tests} *)

let%expect_test "bitflag - buffer_usage (real API bitflag)" =
  let bitflag = lookup_bitflag "buffer_usage" in
  print_bitflag_outputs bitflag;
  [%expect
    {|
    === Low-level C ===
    /* Bitflag: WGPUBufferUsage */
    CAMLprim value caml_wgpu_buffer_usage_none(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_None));
    }

    CAMLprim value caml_wgpu_buffer_usage_map_read(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_MapRead));
    }

    CAMLprim value caml_wgpu_buffer_usage_map_write(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_MapWrite));
    }

    CAMLprim value caml_wgpu_buffer_usage_copy_src(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_CopySrc));
    }

    CAMLprim value caml_wgpu_buffer_usage_copy_dst(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_CopyDst));
    }

    CAMLprim value caml_wgpu_buffer_usage_index(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Index));
    }

    CAMLprim value caml_wgpu_buffer_usage_vertex(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Vertex));
    }

    CAMLprim value caml_wgpu_buffer_usage_uniform(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Uniform));
    }

    CAMLprim value caml_wgpu_buffer_usage_storage(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Storage));
    }

    CAMLprim value caml_wgpu_buffer_usage_indirect(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_Indirect));
    }

    CAMLprim value caml_wgpu_buffer_usage_query_resolve(value unit) {
      CAMLparam1(unit);
      CAMLreturn(Val_int(WGPUBufferUsage_QueryResolve));
    }

    === High-level MLI ===
    module Buffer_usage : sig
      type t =
      | None
      | Map_read
      | Map_write
      | Copy_src
      | Copy_dst
      | Index
      | Vertex
      | Uniform
      | Storage
      | Indirect
      | Query_resolve

      val to_int : t -> int
      val list_to_int : t list -> int
    end

    === High-level ML ===
    module Buffer_usage = Wgpu_low.Buffer_usage
    |}]
;;

(** {2 Struct Tests} *)

let%expect_test "struct - buffer_descriptor (base_in struct with chained types)" =
  let struct_ = lookup_struct "buffer_descriptor" in
  print_struct_outputs struct_;
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUBufferDescriptor */
    CAMLprim value caml_wgpu_buffer_descriptor_create(value unit) {
      CAMLparam1(unit);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)malloc(sizeof(WGPUBufferDescriptor));
      memset(s, 0, sizeof(WGPUBufferDescriptor));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_free(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      const char *str = String_val(val);
      s->label.data = str;
      s->label.length = strlen(str);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_usage(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->usage = Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_size(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->size = (uint64_t)Int64_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_mapped_at_creation(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->mappedAtCreation = Bool_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_label(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      if (s->label.data != NULL) {
        CAMLreturn(caml_copy_string(s->label.data));
      } else {
        CAMLreturn(caml_copy_string(""));
      }
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_usage(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->usage));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_size(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(caml_copy_int64(s->size));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_mapped_at_creation(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_bool(s->mappedAtCreation));
    }

    /* nextInChain setter for WGPUBufferDescriptor */
    CAMLprim value caml_wgpu_buffer_descriptor_set_next_in_chain(value handle, value chain) {
      CAMLparam2(handle, chain);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    module Buffer_descriptor : sig
      type t = nativeint
      val buffer_descriptor_create : unit -> t
      val buffer_descriptor_free : t -> unit
      val buffer_descriptor_set_label : t -> string -> unit
      val buffer_descriptor_set_usage : t -> int -> unit
      val buffer_descriptor_set_size : t -> int64 -> unit
      val buffer_descriptor_set_mapped_at_creation : t -> bool -> unit
      val buffer_descriptor_get_label : t -> string
      val buffer_descriptor_get_usage : t -> int
      val buffer_descriptor_get_size : t -> int64
      val buffer_descriptor_get_mapped_at_creation : t -> bool
      val buffer_descriptor_set_next_in_chain : t -> nativeint -> unit
    end

    === Low-level ML ===
    module Buffer_descriptor = struct
      type t = nativeint

      external buffer_descriptor_create : unit -> nativeint = "caml_wgpu_buffer_descriptor_create"

      external buffer_descriptor_free : nativeint -> unit = "caml_wgpu_buffer_descriptor_free"

      external buffer_descriptor_set_label : nativeint -> string -> unit = "caml_wgpu_buffer_descriptor_set_label"
      external buffer_descriptor_set_usage : nativeint -> int -> unit = "caml_wgpu_buffer_descriptor_set_usage"
      external buffer_descriptor_set_size : nativeint -> int64 -> unit = "caml_wgpu_buffer_descriptor_set_size"
      external buffer_descriptor_set_mapped_at_creation : nativeint -> bool -> unit = "caml_wgpu_buffer_descriptor_set_mapped_at_creation"

      external buffer_descriptor_get_label : nativeint -> string = "caml_wgpu_buffer_descriptor_get_label"
      external buffer_descriptor_get_usage : nativeint -> int = "caml_wgpu_buffer_descriptor_get_usage"
      external buffer_descriptor_get_size : nativeint -> int64 = "caml_wgpu_buffer_descriptor_get_size"
      external buffer_descriptor_get_mapped_at_creation : nativeint -> bool = "caml_wgpu_buffer_descriptor_get_mapped_at_creation"

      external buffer_descriptor_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_buffer_descriptor_set_next_in_chain"
    end
    |}]
;;

let%expect_test "struct - bind_group_layout_descriptor (struct with array)" =
  let struct_ = lookup_struct "bind_group_layout_descriptor" in
  print_struct_outputs struct_;
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUBindGroupLayoutDescriptor */
    CAMLprim value caml_wgpu_bind_group_layout_descriptor_create(value unit) {
      CAMLparam1(unit);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)malloc(sizeof(WGPUBindGroupLayoutDescriptor));
      memset(s, 0, sizeof(WGPUBindGroupLayoutDescriptor));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_free(value handle) {
      CAMLparam1(handle);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      const char *str = String_val(val);
      s->label.data = str;
      s->label.length = strlen(str);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_entries(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      size_t count = Wosize_val(val);
      WGPUBindGroupLayoutEntry* arr = (count > 0) ? malloc(count * sizeof(WGPUBindGroupLayoutEntry)) : NULL;
      for (size_t i = 0; i < count; i++) {
        arr[i] = *(WGPUBindGroupLayoutEntry*)Nativeint_val(Field(val, i));
      }
      s->entryCount = count;
      s->entries = arr;
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_get_label(value handle) {
      CAMLparam1(handle);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      if (s->label.data != NULL) {
        CAMLreturn(caml_copy_string(s->label.data));
      } else {
        CAMLreturn(caml_copy_string(""));
      }
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_get_entries(value handle) {
      CAMLparam1(handle);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      (void)s; /* TODO: getter for entries */
      CAMLreturn(Val_unit);
    }

    /* nextInChain setter for WGPUBindGroupLayoutDescriptor */
    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_next_in_chain(value handle, value chain) {
      CAMLparam2(handle, chain);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    module Bind_group_layout_descriptor : sig
      type t = nativeint
      val bind_group_layout_descriptor_create : unit -> t
      val bind_group_layout_descriptor_free : t -> unit
      val bind_group_layout_descriptor_set_label : t -> string -> unit
      val bind_group_layout_descriptor_set_entries : t -> nativeint array -> unit
      val bind_group_layout_descriptor_get_label : t -> string
      val bind_group_layout_descriptor_get_entries : t -> nativeint
      val bind_group_layout_descriptor_set_next_in_chain : t -> nativeint -> unit
    end

    === Low-level ML ===
    module Bind_group_layout_descriptor = struct
      type t = nativeint

      external bind_group_layout_descriptor_create : unit -> nativeint = "caml_wgpu_bind_group_layout_descriptor_create"

      external bind_group_layout_descriptor_free : nativeint -> unit = "caml_wgpu_bind_group_layout_descriptor_free"

      external bind_group_layout_descriptor_set_label : nativeint -> string -> unit = "caml_wgpu_bind_group_layout_descriptor_set_label"
      external bind_group_layout_descriptor_set_entries : nativeint -> nativeint array -> unit = "caml_wgpu_bind_group_layout_descriptor_set_entries"

      external bind_group_layout_descriptor_get_label : nativeint -> string = "caml_wgpu_bind_group_layout_descriptor_get_label"
      external bind_group_layout_descriptor_get_entries : nativeint -> nativeint = "caml_wgpu_bind_group_layout_descriptor_get_entries"

      external bind_group_layout_descriptor_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_bind_group_layout_descriptor_set_next_in_chain"
    end
    |}]
;;

let%expect_test "struct - extent_3D (standalone struct)" =
  let struct_ = lookup_struct "extent_3D" in
  print_struct_outputs struct_;
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUExtent3D */
    CAMLprim value caml_wgpu_extent_3d_create(value unit) {
      CAMLparam1(unit);
      WGPUExtent3D *s = (WGPUExtent3D*)malloc(sizeof(WGPUExtent3D));
      memset(s, 0, sizeof(WGPUExtent3D));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_extent_3d_free(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_width(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      s->width = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_height(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      s->height = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_depth_or_array_layers(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      s->depthOrArrayLayers = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_get_width(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->width));
    }

    CAMLprim value caml_wgpu_extent_3d_get_height(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->height));
    }

    CAMLprim value caml_wgpu_extent_3d_get_depth_or_array_layers(value handle) {
      CAMLparam1(handle);
      WGPUExtent3D *s = (WGPUExtent3D*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->depthOrArrayLayers));
    }


    === Low-level MLI ===
    module Extent_3d : sig
      type t = nativeint
      val extent_3D_create : unit -> t
      val extent_3D_free : t -> unit
      val extent_3D_set_width : t -> int -> unit
      val extent_3D_set_height : t -> int -> unit
      val extent_3D_set_depth_or_array_layers : t -> int -> unit
      val extent_3D_get_width : t -> int
      val extent_3D_get_height : t -> int
      val extent_3D_get_depth_or_array_layers : t -> int
    end

    === Low-level ML ===
    module Extent_3d = struct
      type t = nativeint

      external extent_3D_create : unit -> nativeint = "caml_wgpu_extent_3d_create"

      external extent_3D_free : nativeint -> unit = "caml_wgpu_extent_3d_free"

      external extent_3D_set_width : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_width"
      external extent_3D_set_height : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_height"
      external extent_3D_set_depth_or_array_layers : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_depth_or_array_layers"

      external extent_3D_get_width : nativeint -> int = "caml_wgpu_extent_3d_get_width"
      external extent_3D_get_height : nativeint -> int = "caml_wgpu_extent_3d_get_height"
      external extent_3D_get_depth_or_array_layers : nativeint -> int = "caml_wgpu_extent_3d_get_depth_or_array_layers"
    end
    |}]
;;

(** {2 Method Tests} *)

let%expect_test "method - buffer.get_size (simple method, no args, returns primitive)" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "get_size" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_get_size(value self) {
      CAMLparam1(self);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);

      uint64_t result = wgpuBufferGetSize(c_self);
      CAMLreturn(caml_copy_int64(result));
    }

    === Low-level MLI ===
    val buffer_get_size : buffer -> int64
    === Low-level ML ===
    external buffer_get_size : buffer -> int64 = "caml_wgpu_buffer_get_size"
    === High-level MLI ===
      val get_size : t -> int64

    === High-level ML ===
      let get_size t = Wgpu_low.buffer_get_size t.handle
    |}]
;;

let%expect_test "method - buffer.set_label (method with string arg)" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "set_label" in
  print_method_outputs obj method_;
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

    === Low-level MLI ===
    val buffer_set_label : buffer -> string -> unit
    === Low-level ML ===
    external buffer_set_label : buffer -> string -> unit = "caml_wgpu_buffer_set_label"
    === High-level MLI ===
      val set_label : t -> label:string -> unit

    === High-level ML ===
      let set_label t ~label = Wgpu_low.buffer_set_label t.handle label
    |}]
;;

let%expect_test "method - device.create_buffer (method with struct descriptor arg)" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_buffer(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUBufferDescriptor* c_descriptor = (WGPUBufferDescriptor*)Nativeint_val(descriptor);
      WGPUBuffer result = wgpuDeviceCreateBuffer(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_buffer : device -> nativeint -> buffer
    === Low-level ML ===
    external device_create_buffer : device -> nativeint -> buffer = "caml_wgpu_device_create_buffer"
    === High-level MLI ===
      val create_buffer : t -> ?label:string -> usage:Buffer_usage.Item.t list -> size:int64 -> mapped_at_creation:bool -> unit -> Buffer.t

    === High-level ML ===
      let create_buffer t ?(label = "") ~usage ~size ~mapped_at_creation () =
        let desc_descriptor = Wgpu_low.Buffer_descriptor.buffer_descriptor_create () in
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_label desc_descriptor label;
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_usage desc_descriptor (Buffer_usage.list_to_int usage);
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_size desc_descriptor size;
        Wgpu_low.Buffer_descriptor.buffer_descriptor_set_mapped_at_creation desc_descriptor mapped_at_creation;
        let result = Wgpu_low.device_create_buffer t.handle desc_descriptor in
        Wgpu_low.Buffer_descriptor.buffer_descriptor_free desc_descriptor;
        ({ Buffer.handle = result } : Buffer.t)
    |}]
;;

let%expect_test "method - device.create_bind_group_layout (method with complex struct \
                 arg)"
  =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_bind_group_layout" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_bind_group_layout(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUBindGroupLayoutDescriptor* c_descriptor = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(descriptor);
      WGPUBindGroupLayout result = wgpuDeviceCreateBindGroupLayout(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_bind_group_layout : device -> nativeint -> bind_group_layout
    === Low-level ML ===
    external device_create_bind_group_layout : device -> nativeint -> bind_group_layout = "caml_wgpu_device_create_bind_group_layout"
    === High-level MLI ===
      val create_bind_group_layout : t -> ?label:string -> ?entries:Bind_group_layout_entry.t list -> unit -> Bind_group_layout.t

    === High-level ML ===
      let create_bind_group_layout t ?(label = "") ?(entries = []) () =
        let desc_descriptor = Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_create () in
        Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_set_label desc_descriptor label;
        let entries_structs = List.map (fun (entry : Bind_group_layout_entry.t) ->
            let e = Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_create () in
            Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_binding e entry.binding;
            Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_visibility e (Shader_stage.list_to_int entry.visibility);
            (match entry.buffer with
             | Some buffer_rec ->
               let nested_buffer = Wgpu_low.Buffer_binding_layout.buffer_binding_layout_create () in
               Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_type nested_buffer (Buffer_binding_type.to_int buffer_rec.type_);
               Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_has_dynamic_offset nested_buffer buffer_rec.has_dynamic_offset;
               Wgpu_low.Buffer_binding_layout.buffer_binding_layout_set_min_binding_size nested_buffer buffer_rec.min_binding_size;
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_buffer e nested_buffer
             | None -> ());
            (match entry.sampler with
             | Some sampler_rec ->
               let nested_sampler = Wgpu_low.Sampler_binding_layout.sampler_binding_layout_create () in
               Wgpu_low.Sampler_binding_layout.sampler_binding_layout_set_type nested_sampler (Sampler_binding_type.to_int sampler_rec.type_);
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_sampler e nested_sampler
             | None -> ());
            (match entry.texture with
             | Some texture_rec ->
               let nested_texture = Wgpu_low.Texture_binding_layout.texture_binding_layout_create () in
               Wgpu_low.Texture_binding_layout.texture_binding_layout_set_sample_type nested_texture (Texture_sample_type.to_int texture_rec.sample_type);
               Wgpu_low.Texture_binding_layout.texture_binding_layout_set_view_dimension nested_texture (Texture_view_dimension.to_int texture_rec.view_dimension);
               Wgpu_low.Texture_binding_layout.texture_binding_layout_set_multisampled nested_texture texture_rec.multisampled;
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_texture e nested_texture
             | None -> ());
            (match entry.storage_texture with
             | Some storage_texture_rec ->
               let nested_storage_texture = Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_create () in
               Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_set_access nested_storage_texture (Storage_texture_access.to_int storage_texture_rec.access);
               Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_set_format nested_storage_texture (Texture_format.to_int storage_texture_rec.format);
               Wgpu_low.Storage_texture_binding_layout.storage_texture_binding_layout_set_view_dimension nested_storage_texture (Texture_view_dimension.to_int storage_texture_rec.view_dimension);
               Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_set_storage_texture e nested_storage_texture
             | None -> ());
            e) entries in
        let entries_array = Array.of_list entries_structs in
        Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_set_entries desc_descriptor entries_array;
        let result = Wgpu_low.device_create_bind_group_layout t.handle desc_descriptor in
        List.iter (fun e -> Wgpu_low.Bind_group_layout_entry.bind_group_layout_entry_free e) entries_structs;
        Wgpu_low.Bind_group_layout_descriptor.bind_group_layout_descriptor_free desc_descriptor;
        ({ Bind_group_layout.handle = result } : Bind_group_layout.t)
    |}]
;;

let%expect_test "method - queue.submit (method with array arg)" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "submit" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_queue_submit(value self, value commands) {
      CAMLparam2(self, commands);
      WGPUQueue c_self = (WGPUQueue)Nativeint_val(self);
      size_t c_commands_count = Wosize_val(commands);
      WGPUCommandBuffer* c_commands = (c_commands_count > 0) ? alloca(c_commands_count * sizeof(WGPUCommandBuffer)) : NULL;
      for (size_t i = 0; i < c_commands_count; i++) {
        c_commands[i] = (WGPUCommandBuffer)Nativeint_val(Field(commands, i));
      }
      wgpuQueueSubmit(c_self, c_commands_count, c_commands);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val queue_submit : queue -> command_buffer array -> unit
    === Low-level ML ===
    external queue_submit : queue -> command_buffer array -> unit = "caml_wgpu_queue_submit"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;
