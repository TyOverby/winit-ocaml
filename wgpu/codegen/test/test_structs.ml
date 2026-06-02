open! Core

(** Integration tests for struct code generation using inline YAML *)

let%expect_test "struct - extent_3d (standalone struct)" =
  let yaml =
    {|
name: extent_3d
doc: Extent in 3D
type: standalone
members:
  - name: width
    type: uint32
    doc: Width
  - name: height
    type: uint32
    doc: Height
  - name: depth_or_array_layers
    type: uint32
    doc: Depth
|}
  in
  let struct_ = Parse_yml.parse_struct (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUExtent3d */
    CAMLprim value caml_wgpu_extent_3d_create(value unit) {
      CAMLparam1(unit);
      WGPUExtent3d *s = (WGPUExtent3d*)malloc(sizeof(WGPUExtent3d));
      memset(s, 0, sizeof(WGPUExtent3d));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_extent_3d_free(value handle) {
      CAMLparam1(handle);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_width(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      s->width = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_height(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      s->height = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_set_depth_or_array_layers(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      s->depthOrArrayLayers = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_extent_3d_get_width(value handle) {
      CAMLparam1(handle);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->width));
    }

    CAMLprim value caml_wgpu_extent_3d_get_height(value handle) {
      CAMLparam1(handle);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->height));
    }

    CAMLprim value caml_wgpu_extent_3d_get_depth_or_array_layers(value handle) {
      CAMLparam1(handle);
      WGPUExtent3d *s = (WGPUExtent3d*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->depthOrArrayLayers));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  [%expect
    {|
    === Low-level MLI ===
    module Extent_3d : sig
      type t = nativeint
      val extent_3d_create : unit -> t
      val extent_3d_free : t -> unit
      val extent_3d_set_width : t -> int -> unit
      val extent_3d_set_height : t -> int -> unit
      val extent_3d_set_depth_or_array_layers : t -> int -> unit
      val extent_3d_get_width : t -> int
      val extent_3d_get_height : t -> int
      val extent_3d_get_depth_or_array_layers : t -> int
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_);
  [%expect
    {|
    === Low-level ML ===
    module Extent_3d = struct
      type t = nativeint

      external extent_3d_create : unit -> nativeint = "caml_wgpu_extent_3d_create"

      external extent_3d_free : nativeint -> unit = "caml_wgpu_extent_3d_free"

      external extent_3d_set_width : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_width"
      external extent_3d_set_height : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_height"
      external extent_3d_set_depth_or_array_layers : nativeint -> int -> unit = "caml_wgpu_extent_3d_set_depth_or_array_layers"

      external extent_3d_get_width : nativeint -> int = "caml_wgpu_extent_3d_get_width"
      external extent_3d_get_height : nativeint -> int = "caml_wgpu_extent_3d_get_height"
      external extent_3d_get_depth_or_array_layers : nativeint -> int = "caml_wgpu_extent_3d_get_depth_or_array_layers"
    end
    |}]
;;

let%expect_test "struct - buffer_descriptor (base_in struct with nextInChain)" =
  let yaml =
    {|
name: buffer_descriptor
doc: Descriptor for creating a buffer
type: base_in
members:
  - name: label
    type: string
    optional: true
    doc: Label
  - name: size
    type: uint64
    doc: Size in bytes
  - name: usage
    type: bitflag.buffer_usage
    doc: Usage flags
  - name: mapped_at_creation
    type: bool
    doc: Map at creation
|}
  in
  let struct_ = Parse_yml.parse_struct (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
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
        if (s->label.data != NULL) {
          free((void *)s->label.data);
        }
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      size_t len = caml_string_length(val);
      char *copy = malloc(len + 1);
      memcpy(copy, String_val(val), len);
      copy[len] = '\0';
      if (s->label.data != NULL) {
        free((void *)s->label.data);
      }
      s->label.data = copy;
      s->label.length = len;
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_size(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->size = (uint64_t)Int64_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_buffer_descriptor_set_usage(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      s->usage = Int_val(val);
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

    CAMLprim value caml_wgpu_buffer_descriptor_get_size(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(caml_copy_int64(s->size));
    }

    CAMLprim value caml_wgpu_buffer_descriptor_get_usage(value handle) {
      CAMLparam1(handle);
      WGPUBufferDescriptor *s = (WGPUBufferDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->usage));
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
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  [%expect
    {|
    === Low-level MLI ===
    module Buffer_descriptor : sig
      type t = nativeint
      val buffer_descriptor_create : unit -> t
      val buffer_descriptor_free : t -> unit
      val buffer_descriptor_set_label : t -> string -> unit
      val buffer_descriptor_set_size : t -> int64 -> unit
      val buffer_descriptor_set_usage : t -> int -> unit
      val buffer_descriptor_set_mapped_at_creation : t -> bool -> unit
      val buffer_descriptor_get_label : t -> string
      val buffer_descriptor_get_size : t -> int64
      val buffer_descriptor_get_usage : t -> int
      val buffer_descriptor_get_mapped_at_creation : t -> bool
      val buffer_descriptor_set_next_in_chain : t -> nativeint -> unit
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_);
  [%expect
    {|
    === Low-level ML ===
    module Buffer_descriptor = struct
      type t = nativeint

      external buffer_descriptor_create : unit -> nativeint = "caml_wgpu_buffer_descriptor_create"

      external buffer_descriptor_free : nativeint -> unit = "caml_wgpu_buffer_descriptor_free"

      external buffer_descriptor_set_label : nativeint -> string -> unit = "caml_wgpu_buffer_descriptor_set_label"
      external buffer_descriptor_set_size : nativeint -> int64 -> unit = "caml_wgpu_buffer_descriptor_set_size"
      external buffer_descriptor_set_usage : nativeint -> int -> unit = "caml_wgpu_buffer_descriptor_set_usage"
      external buffer_descriptor_set_mapped_at_creation : nativeint -> bool -> unit = "caml_wgpu_buffer_descriptor_set_mapped_at_creation"

      external buffer_descriptor_get_label : nativeint -> string = "caml_wgpu_buffer_descriptor_get_label"
      external buffer_descriptor_get_size : nativeint -> int64 = "caml_wgpu_buffer_descriptor_get_size"
      external buffer_descriptor_get_usage : nativeint -> int = "caml_wgpu_buffer_descriptor_get_usage"
      external buffer_descriptor_get_mapped_at_creation : nativeint -> bool = "caml_wgpu_buffer_descriptor_get_mapped_at_creation"

      external buffer_descriptor_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_buffer_descriptor_set_next_in_chain"
    end
    |}]
;;

let%expect_test "struct - surface_descriptor_from_xcb_window (extension_in struct)" =
  let yaml =
    {|
name: surface_descriptor_from_xcb_window
doc: XCB window surface descriptor
type: extension_in
extends:
  - surface_descriptor
members:
  - name: connection
    type: c_void
    doc: XCB connection
  - name: window
    type: uint32
    doc: Window ID
|}
  in
  let struct_ = Parse_yml.parse_struct (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUSurfaceDescriptorFromXcbWindow */
    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_create(value unit) {
      CAMLparam1(unit);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)malloc(sizeof(WGPUSurfaceDescriptorFromXcbWindow));
      memset(s, 0, sizeof(WGPUSurfaceDescriptorFromXcbWindow));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_free(value handle) {
      CAMLparam1(handle);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_set_connection(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      s->connection = (void*)Nativeint_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_set_window(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      s->window = (uint32_t)Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_get_connection(value handle) {
      CAMLparam1(handle);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      CAMLreturn(caml_copy_nativeint((intnat)s->connection));
    }

    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_get_window(value handle) {
      CAMLparam1(handle);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->window));
    }

    /* Extension chain functions for WGPUSurfaceDescriptorFromXcbWindow */
    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_set_chain_stype(value handle, value stype) {
      CAMLparam2(handle, stype);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      s->chain.sType = Int_val(stype);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_surface_descriptor_from_xcb_window_as_chained(value handle) {
      CAMLparam1(handle);
      WGPUSurfaceDescriptorFromXcbWindow *s = (WGPUSurfaceDescriptorFromXcbWindow*)Nativeint_val(handle);
      CAMLreturn(caml_copy_nativeint((intnat)&s->chain));
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  [%expect
    {|
    === Low-level MLI ===
    module Surface_descriptor_from_xcb_window : sig
      type t = nativeint
      val surface_descriptor_from_xcb_window_create : unit -> t
      val surface_descriptor_from_xcb_window_free : t -> unit
      val surface_descriptor_from_xcb_window_set_connection : t -> nativeint -> unit
      val surface_descriptor_from_xcb_window_set_window : t -> int -> unit
      val surface_descriptor_from_xcb_window_get_connection : t -> nativeint
      val surface_descriptor_from_xcb_window_get_window : t -> int
      val surface_descriptor_from_xcb_window_set_chain_stype : t -> int -> unit
      val surface_descriptor_from_xcb_window_as_chained : t -> nativeint
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_);
  [%expect
    {|
    === Low-level ML ===
    module Surface_descriptor_from_xcb_window = struct
      type t = nativeint

      external surface_descriptor_from_xcb_window_create : unit -> nativeint = "caml_wgpu_surface_descriptor_from_xcb_window_create"

      external surface_descriptor_from_xcb_window_free : nativeint -> unit = "caml_wgpu_surface_descriptor_from_xcb_window_free"

      external surface_descriptor_from_xcb_window_set_connection : nativeint -> nativeint -> unit = "caml_wgpu_surface_descriptor_from_xcb_window_set_connection"
      external surface_descriptor_from_xcb_window_set_window : nativeint -> int -> unit = "caml_wgpu_surface_descriptor_from_xcb_window_set_window"

      external surface_descriptor_from_xcb_window_get_connection : nativeint -> nativeint = "caml_wgpu_surface_descriptor_from_xcb_window_get_connection"
      external surface_descriptor_from_xcb_window_get_window : nativeint -> int = "caml_wgpu_surface_descriptor_from_xcb_window_get_window"

      external surface_descriptor_from_xcb_window_set_chain_stype : nativeint -> int -> unit = "caml_wgpu_surface_descriptor_from_xcb_window_set_chain_stype"

      external surface_descriptor_from_xcb_window_as_chained : nativeint -> nativeint = "caml_wgpu_surface_descriptor_from_xcb_window_as_chained"
    end
    |}]
;;

let%expect_test "struct - bind_group_layout_descriptor (struct with array)" =
  let yaml =
    {|
name: bind_group_layout_descriptor
doc: Descriptor for creating a bind group layout
type: base_in
members:
  - name: label
    type: string
    optional: true
    doc: Label
  - name: entries
    type: array<struct.bind_group_layout_entry>
    doc: Entries
|}
  in
  let struct_ = Parse_yml.parse_struct (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
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
        if (s->label.data != NULL) {
          free((void *)s->label.data);
        }
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_bind_group_layout_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUBindGroupLayoutDescriptor *s = (WGPUBindGroupLayoutDescriptor*)Nativeint_val(handle);
      size_t len = caml_string_length(val);
      char *copy = malloc(len + 1);
      memcpy(copy, String_val(val), len);
      copy[len] = '\0';
      if (s->label.data != NULL) {
        free((void *)s->label.data);
      }
      s->label.data = copy;
      s->label.length = len;
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
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  [%expect
    {|
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
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_);
  [%expect
    {|
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

let%expect_test "struct - texture_descriptor (struct with enum)" =
  let yaml =
    {|
name: texture_descriptor
doc: Descriptor for creating a texture
type: base_in
members:
  - name: label
    type: string
    optional: true
    doc: Label
  - name: format
    type: enum.texture_format
    doc: Texture format
  - name: dimension
    type: enum.texture_dimension
    doc: Texture dimension
|}
  in
  let struct_ = Parse_yml.parse_struct (Yaml.of_string_exn yaml) in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPUTextureDescriptor */
    CAMLprim value caml_wgpu_texture_descriptor_create(value unit) {
      CAMLparam1(unit);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)malloc(sizeof(WGPUTextureDescriptor));
      memset(s, 0, sizeof(WGPUTextureDescriptor));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_texture_descriptor_free(value handle) {
      CAMLparam1(handle);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      if (s != NULL) {
        if (s->label.data != NULL) {
          free((void *)s->label.data);
        }
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_texture_descriptor_set_label(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      size_t len = caml_string_length(val);
      char *copy = malloc(len + 1);
      memcpy(copy, String_val(val), len);
      copy[len] = '\0';
      if (s->label.data != NULL) {
        free((void *)s->label.data);
      }
      s->label.data = copy;
      s->label.length = len;
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_texture_descriptor_set_format(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      s->format = Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_texture_descriptor_set_dimension(value handle, value val) {
      CAMLparam2(handle, val);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      s->dimension = Int_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_texture_descriptor_get_label(value handle) {
      CAMLparam1(handle);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      if (s->label.data != NULL) {
        CAMLreturn(caml_copy_string(s->label.data));
      } else {
        CAMLreturn(caml_copy_string(""));
      }
    }

    CAMLprim value caml_wgpu_texture_descriptor_get_format(value handle) {
      CAMLparam1(handle);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->format));
    }

    CAMLprim value caml_wgpu_texture_descriptor_get_dimension(value handle) {
      CAMLparam1(handle);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      CAMLreturn(Val_int(s->dimension));
    }

    /* nextInChain setter for WGPUTextureDescriptor */
    CAMLprim value caml_wgpu_texture_descriptor_set_next_in_chain(value handle, value chain) {
      CAMLparam2(handle, chain);
      WGPUTextureDescriptor *s = (WGPUTextureDescriptor*)Nativeint_val(handle);
      s->nextInChain = (WGPUChainedStruct const *)Nativeint_val(chain);
      CAMLreturn(Val_unit);
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  [%expect
    {|
    === Low-level MLI ===
    module Texture_descriptor : sig
      type t = nativeint
      val texture_descriptor_create : unit -> t
      val texture_descriptor_free : t -> unit
      val texture_descriptor_set_label : t -> string -> unit
      val texture_descriptor_set_format : t -> int -> unit
      val texture_descriptor_set_dimension : t -> int -> unit
      val texture_descriptor_get_label : t -> string
      val texture_descriptor_get_format : t -> int
      val texture_descriptor_get_dimension : t -> int
      val texture_descriptor_set_next_in_chain : t -> nativeint -> unit
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_);
  [%expect
    {|
    === Low-level ML ===
    module Texture_descriptor = struct
      type t = nativeint

      external texture_descriptor_create : unit -> nativeint = "caml_wgpu_texture_descriptor_create"

      external texture_descriptor_free : nativeint -> unit = "caml_wgpu_texture_descriptor_free"

      external texture_descriptor_set_label : nativeint -> string -> unit = "caml_wgpu_texture_descriptor_set_label"
      external texture_descriptor_set_format : nativeint -> int -> unit = "caml_wgpu_texture_descriptor_set_format"
      external texture_descriptor_set_dimension : nativeint -> int -> unit = "caml_wgpu_texture_descriptor_set_dimension"

      external texture_descriptor_get_label : nativeint -> string = "caml_wgpu_texture_descriptor_get_label"
      external texture_descriptor_get_format : nativeint -> int = "caml_wgpu_texture_descriptor_get_format"
      external texture_descriptor_get_dimension : nativeint -> int = "caml_wgpu_texture_descriptor_get_dimension"

      external texture_descriptor_set_next_in_chain : nativeint -> nativeint -> unit = "caml_wgpu_texture_descriptor_set_next_in_chain"
    end
    |}]
;;

(* Note: struct_with_object and output_struct tests use IR.Optional type which doesn't
   parse directly from standard YAML. We keep these as direct IR for now since they test
   edge cases in the IR that may not have a standard YAML representation. *)

let struct_with_object : Ir.struct_ =
  { name = "render_pass_color_attachment"
  ; doc = "Color attachment for render pass"
  ; type_ = Standalone
  ; free_members = false
  ; members =
      [ { name = "view"
        ; type_ = Object "texture_view"
        ; optional = false
        ; doc = "Texture view"
        ; pointer = None
        }
      ; { name = "resolve_target"
        ; type_ = Optional (Object "texture_view")
        ; optional = true
        ; doc = "Resolve target"
        ; pointer = None
        }
      ]
  }
;;

let%expect_test "struct - render_pass_color_attachment (struct with object and optional)" =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_with_object);
  [%expect
    {|
    === Low-level C ===
    /* Struct: WGPURenderPassColorAttachment */
    CAMLprim value caml_wgpu_render_pass_color_attachment_create(value unit) {
      CAMLparam1(unit);
      WGPURenderPassColorAttachment *s = (WGPURenderPassColorAttachment*)malloc(sizeof(WGPURenderPassColorAttachment));
      memset(s, 0, sizeof(WGPURenderPassColorAttachment));
      CAMLreturn(caml_copy_nativeint((intnat)s));
    }

    CAMLprim value caml_wgpu_render_pass_color_attachment_free(value handle) {
      CAMLparam1(handle);
      WGPURenderPassColorAttachment *s = (WGPURenderPassColorAttachment*)Nativeint_val(handle);
      if (s != NULL) {
        free(s);
      }
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_render_pass_color_attachment_set_view(value handle, value val) {
      CAMLparam2(handle, val);
      WGPURenderPassColorAttachment *s = (WGPURenderPassColorAttachment*)Nativeint_val(handle);
      s->view = (WGPUTextureView)Nativeint_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_render_pass_color_attachment_set_resolve_target(value handle, value val) {
      CAMLparam2(handle, val);
      WGPURenderPassColorAttachment *s = (WGPURenderPassColorAttachment*)Nativeint_val(handle);
      s->resolveTarget = (WGPUTextureView)Nativeint_val(val);
      CAMLreturn(Val_unit);
    }

    CAMLprim value caml_wgpu_render_pass_color_attachment_get_view(value handle) {
      CAMLparam1(handle);
      WGPURenderPassColorAttachment *s = (WGPURenderPassColorAttachment*)Nativeint_val(handle);
      CAMLreturn(caml_copy_nativeint((intnat)s->view));
    }

    CAMLprim value caml_wgpu_render_pass_color_attachment_get_resolve_target(value handle) {
      CAMLparam1(handle);
      WGPURenderPassColorAttachment *s = (WGPURenderPassColorAttachment*)Nativeint_val(handle);
      (void)s; /* TODO: getter for resolveTarget */
      CAMLreturn(Val_unit);
    }
    |}];
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_with_object);
  [%expect
    {|
    === Low-level MLI ===
    module Render_pass_color_attachment : sig
      type t = nativeint
      val render_pass_color_attachment_create : unit -> t
      val render_pass_color_attachment_free : t -> unit
      val render_pass_color_attachment_set_view : t -> nativeint -> unit
      val render_pass_color_attachment_set_resolve_target : t -> nativeint -> unit
      val render_pass_color_attachment_get_view : t -> nativeint
      val render_pass_color_attachment_get_resolve_target : t -> nativeint
    end
    |}];
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_with_object);
  [%expect
    {|
    === Low-level ML ===
    module Render_pass_color_attachment = struct
      type t = nativeint

      external render_pass_color_attachment_create : unit -> nativeint = "caml_wgpu_render_pass_color_attachment_create"

      external render_pass_color_attachment_free : nativeint -> unit = "caml_wgpu_render_pass_color_attachment_free"

      external render_pass_color_attachment_set_view : nativeint -> nativeint -> unit = "caml_wgpu_render_pass_color_attachment_set_view"
      external render_pass_color_attachment_set_resolve_target : nativeint -> nativeint -> unit = "caml_wgpu_render_pass_color_attachment_set_resolve_target"

      external render_pass_color_attachment_get_view : nativeint -> nativeint = "caml_wgpu_render_pass_color_attachment_get_view"
      external render_pass_color_attachment_get_resolve_target : nativeint -> nativeint = "caml_wgpu_render_pass_color_attachment_get_resolve_target"
    end
    |}]
;;
