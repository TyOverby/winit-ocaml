open! Core

(** Integration tests for struct code generation *)

(* Sample structs for testing *)

let standalone_struct : Ir.struct_ =
  { name = "extent_3d"
  ; doc = "Extent in 3D"
  ; type_ = Standalone
  ; free_members = false
  ; members =
      [ { name = "width"
        ; type_ = Primitive Uint32
        ; optional = false
        ; doc = "Width"
        ; pointer = None
        }
      ; { name = "height"
        ; type_ = Primitive Uint32
        ; optional = false
        ; doc = "Height"
        ; pointer = None
        }
      ; { name = "depth_or_array_layers"
        ; type_ = Primitive Uint32
        ; optional = false
        ; doc = "Depth"
        ; pointer = None
        }
      ]
  }
;;

let base_in_struct : Ir.struct_ =
  { name = "buffer_descriptor"
  ; doc = "Descriptor for creating a buffer"
  ; type_ = Base_in
  ; free_members = false
  ; members =
      [ { name = "label"
        ; type_ = Primitive String
        ; optional = true
        ; doc = "Label"
        ; pointer = None
        }
      ; { name = "size"
        ; type_ = Primitive Uint64
        ; optional = false
        ; doc = "Size in bytes"
        ; pointer = None
        }
      ; { name = "usage"
        ; type_ = Bitflag "buffer_usage"
        ; optional = false
        ; doc = "Usage flags"
        ; pointer = None
        }
      ; { name = "mapped_at_creation"
        ; type_ = Primitive Bool
        ; optional = false
        ; doc = "Map at creation"
        ; pointer = None
        }
      ]
  }
;;

let extension_struct : Ir.struct_ =
  { name = "surface_descriptor_from_xcb_window"
  ; doc = "XCB window surface descriptor"
  ; type_ = Extension_in { extends = [ "surface_descriptor" ] }
  ; free_members = false
  ; members =
      [ { name = "connection"
        ; type_ = Primitive C_void
        ; optional = false
        ; doc = "XCB connection"
        ; pointer = None
        }
      ; { name = "window"
        ; type_ = Primitive Uint32
        ; optional = false
        ; doc = "Window ID"
        ; pointer = None
        }
      ]
  }
;;

let struct_with_array : Ir.struct_ =
  { name = "bind_group_layout_descriptor"
  ; doc = "Descriptor for creating a bind group layout"
  ; type_ = Base_in
  ; free_members = false
  ; members =
      [ { name = "label"
        ; type_ = Primitive String
        ; optional = true
        ; doc = "Label"
        ; pointer = None
        }
      ; { name = "entries"
        ; type_ = Array { elem = Struct "bind_group_layout_entry"; pointer = None }
        ; optional = false
        ; doc = "Entries"
        ; pointer = None
        }
      ]
  }
;;

let struct_with_enum : Ir.struct_ =
  { name = "texture_descriptor"
  ; doc = "Descriptor for creating a texture"
  ; type_ = Base_in
  ; free_members = false
  ; members =
      [ { name = "label"
        ; type_ = Primitive String
        ; optional = true
        ; doc = "Label"
        ; pointer = None
        }
      ; { name = "format"
        ; type_ = Enum "texture_format"
        ; optional = false
        ; doc = "Texture format"
        ; pointer = None
        }
      ; { name = "dimension"
        ; type_ = Enum "texture_dimension"
        ; optional = false
        ; doc = "Texture dimension"
        ; pointer = None
        }
      ]
  }
;;

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

let output_struct : Ir.struct_ =
  { name = "adapter_info"
  ; doc = "Information about an adapter"
  ; type_ = Base_out
  ; free_members = false
  ; members =
      [ { name = "vendor"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "Vendor name"
        ; pointer = None
        }
      ; { name = "architecture"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "Architecture"
        ; pointer = None
        }
      ; { name = "device"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "Device name"
        ; pointer = None
        }
      ; { name = "description"
        ; type_ = Primitive String
        ; optional = false
        ; doc = "Description"
        ; pointer = None
        }
      ]
  }
;;

(* ===== Gen_low struct tests ===== *)

let%expect_test "Gen_low.gen_ml_struct - standalone struct" =
  print_endline (Gen_low.gen_ml_struct standalone_struct);
  [%expect
    {|
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

let%expect_test "Gen_low.gen_mli_struct - standalone struct" =
  print_endline (Gen_low.gen_mli_struct standalone_struct);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.gen_ml_struct - base_in struct with nextInChain" =
  print_endline (Gen_low.gen_ml_struct base_in_struct);
  [%expect
    {|
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

let%expect_test "Gen_low.gen_ml_struct - extension struct" =
  print_endline (Gen_low.gen_ml_struct extension_struct);
  [%expect
    {|
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

let%expect_test "Gen_low.gen_ml_struct - struct with array" =
  print_endline (Gen_low.gen_ml_struct struct_with_array);
  [%expect
    {|
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

let%expect_test "Gen_low.gen_ml_struct - struct with enum" =
  print_endline (Gen_low.gen_ml_struct struct_with_enum);
  [%expect
    {|
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

let%expect_test "Gen_low.gen_ml_struct - struct with object" =
  print_endline (Gen_low.gen_ml_struct struct_with_object);
  [%expect
    {|
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

(* ===== Gen_low C struct stubs tests ===== *)

let%expect_test "Gen_low.gen_c_struct_stubs - standalone struct" =
  print_endline (Gen_low.gen_c_struct_stubs standalone_struct);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.gen_c_struct_stubs - base_in struct with nextInChain" =
  print_endline (Gen_low.gen_c_struct_stubs base_in_struct);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.gen_c_struct_stubs - extension struct" =
  print_endline (Gen_low.gen_c_struct_stubs extension_struct);
  [%expect
    {|
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
    |}]
;;

let%expect_test "Gen_low.gen_c_struct_stubs - struct with array" =
  print_endline (Gen_low.gen_c_struct_stubs struct_with_array);
  [%expect
    {|
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
    |}]
;;
