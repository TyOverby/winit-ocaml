(* Auto-generated wgpu-native bindings from webgpu.yml *)
(* Do not edit manually! *)

open Ctypes

(* Library loading *)
let lib =
  let paths =
    [ "libwgpu_native.so"
    ; "libwgpu_native.dylib"
    ; "./vendor/wgpu-native/target/debug/libwgpu_native.so"
    ; "./vendor/wgpu-native/target/release/libwgpu_native.so"
    ]
  in
  let try_load path =
    try Some (Dl.dlopen ~filename:path ~flags:[ Dl.RTLD_NOW ]) with
    | _ -> None
  in
  match List.find_map try_load paths with
  | Some lib -> lib
  | None ->
    failwith
      "Could not find libwgpu_native. Build with: cd vendor/wgpu-native && cargo build"
;;

let foreign name typ = Foreign.foreign ~from:lib name typ

(* String view type *)
module String_view = struct
  type t

  let t : t structure typ = structure "WGPUStringView"
  let data = field t "data" (ptr char)
  let length = field t "length" size_t
  let () = seal t

  let of_string s =
    let len = String.length s in
    let st = make t in
    let buf = CArray.of_string s in
    setf st data (CArray.start buf);
    setf st length (Unsigned.Size_t.of_int len);
    st
  ;;

  let null () =
    let st = make t in
    setf st data (from_voidp char null);
    setf st length Unsigned.Size_t.max_int;
    st
  ;;
end

(* Chained struct for extensions *)
module Chained_struct = struct
  type t

  let t : t structure typ = structure "WGPUChainedStruct"
  let next = field t "next" (ptr void)
  let s_type = field t "sType" uint32_t
  let () = seal t
end

(* === Enums === *)

module AdapterType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let discrete_gpu = Unsigned.UInt32.of_int 0x0001
  let integrated_gpu = Unsigned.UInt32.of_int 0x0002
  let cpu = Unsigned.UInt32.of_int 0x0003
  let unknown = Unsigned.UInt32.of_int 0x0004
end

module AddressMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let clamp_to_edge = Unsigned.UInt32.of_int 0x0001
  let repeat = Unsigned.UInt32.of_int 0x0002
  let mirror_repeat = Unsigned.UInt32.of_int 0x0003
end

module BackendType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let null = Unsigned.UInt32.of_int 0x0001
  let webgpu = Unsigned.UInt32.of_int 0x0002
  let d3d11 = Unsigned.UInt32.of_int 0x0003
  let d3d12 = Unsigned.UInt32.of_int 0x0004
  let metal = Unsigned.UInt32.of_int 0x0005
  let vulkan = Unsigned.UInt32.of_int 0x0006
  let opengl = Unsigned.UInt32.of_int 0x0007
  let opengles = Unsigned.UInt32.of_int 0x0008
end

module BlendFactor = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let zero = Unsigned.UInt32.of_int 0x0001
  let one = Unsigned.UInt32.of_int 0x0002
  let src = Unsigned.UInt32.of_int 0x0003
  let one_minus_src = Unsigned.UInt32.of_int 0x0004
  let src_alpha = Unsigned.UInt32.of_int 0x0005
  let one_minus_src_alpha = Unsigned.UInt32.of_int 0x0006
  let dst = Unsigned.UInt32.of_int 0x0007
  let one_minus_dst = Unsigned.UInt32.of_int 0x0008
  let dst_alpha = Unsigned.UInt32.of_int 0x0009
  let one_minus_dst_alpha = Unsigned.UInt32.of_int 0x000A
  let src_alpha_saturated = Unsigned.UInt32.of_int 0x000B
  let constant = Unsigned.UInt32.of_int 0x000C
  let one_minus_constant = Unsigned.UInt32.of_int 0x000D
  let src1 = Unsigned.UInt32.of_int 0x000E
  let one_minus_src1 = Unsigned.UInt32.of_int 0x000F
  let src1_alpha = Unsigned.UInt32.of_int 0x0010
  let one_minus_src1_alpha = Unsigned.UInt32.of_int 0x0011
end

module BlendOperation = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let add = Unsigned.UInt32.of_int 0x0001
  let subtract = Unsigned.UInt32.of_int 0x0002
  let reverse_subtract = Unsigned.UInt32.of_int 0x0003
  let min = Unsigned.UInt32.of_int 0x0004
  let max = Unsigned.UInt32.of_int 0x0005
end

module BufferBindingType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let binding_not_used = Unsigned.UInt32.of_int 0x0000
  let undefined = Unsigned.UInt32.of_int 0x0001
  let uniform = Unsigned.UInt32.of_int 0x0002
  let storage = Unsigned.UInt32.of_int 0x0003
  let read_only_storage = Unsigned.UInt32.of_int 0x0004
end

module BufferMapState = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let unmapped = Unsigned.UInt32.of_int 0x0001
  let pending = Unsigned.UInt32.of_int 0x0002
  let mapped = Unsigned.UInt32.of_int 0x0003
end

module CallbackMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let wait_any_only = Unsigned.UInt32.of_int 0x0001
  let allow_process_events = Unsigned.UInt32.of_int 0x0002
  let allow_spontaneous = Unsigned.UInt32.of_int 0x0003
end

module CompareFunction = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let never = Unsigned.UInt32.of_int 0x0001
  let less = Unsigned.UInt32.of_int 0x0002
  let equal = Unsigned.UInt32.of_int 0x0003
  let less_equal = Unsigned.UInt32.of_int 0x0004
  let greater = Unsigned.UInt32.of_int 0x0005
  let not_equal = Unsigned.UInt32.of_int 0x0006
  let greater_equal = Unsigned.UInt32.of_int 0x0007
  let always = Unsigned.UInt32.of_int 0x0008
end

module CompilationInfoRequestStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let error = Unsigned.UInt32.of_int 0x0003
  let unknown = Unsigned.UInt32.of_int 0x0004
end

module CompilationMessageType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let error = Unsigned.UInt32.of_int 0x0001
  let warning = Unsigned.UInt32.of_int 0x0002
  let info = Unsigned.UInt32.of_int 0x0003
end

module CompositeAlphaMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let auto = Unsigned.UInt32.of_int 0x0000
  let opaque = Unsigned.UInt32.of_int 0x0001
  let premultiplied = Unsigned.UInt32.of_int 0x0002
  let unpremultiplied = Unsigned.UInt32.of_int 0x0003
  let inherit_ = Unsigned.UInt32.of_int 0x0004
end

module CreatePipelineAsyncStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let validation_error = Unsigned.UInt32.of_int 0x0003
  let internal_error = Unsigned.UInt32.of_int 0x0004
  let unknown = Unsigned.UInt32.of_int 0x0005
end

module CullMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let none = Unsigned.UInt32.of_int 0x0001
  let front = Unsigned.UInt32.of_int 0x0002
  let back = Unsigned.UInt32.of_int 0x0003
end

module DeviceLostReason = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let unknown = Unsigned.UInt32.of_int 0x0001
  let destroyed = Unsigned.UInt32.of_int 0x0002
  let instance_dropped = Unsigned.UInt32.of_int 0x0003
  let failed_creation = Unsigned.UInt32.of_int 0x0004
end

module ErrorFilter = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let validation = Unsigned.UInt32.of_int 0x0001
  let out_of_memory = Unsigned.UInt32.of_int 0x0002
  let internal = Unsigned.UInt32.of_int 0x0003
end

module ErrorType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let no_error = Unsigned.UInt32.of_int 0x0001
  let validation = Unsigned.UInt32.of_int 0x0002
  let out_of_memory = Unsigned.UInt32.of_int 0x0003
  let internal = Unsigned.UInt32.of_int 0x0004
  let unknown = Unsigned.UInt32.of_int 0x0005
end

module FeatureLevel = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let compatibility = Unsigned.UInt32.of_int 0x0001
  let core = Unsigned.UInt32.of_int 0x0002
end

module FeatureName = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let depth_clip_control = Unsigned.UInt32.of_int 0x0001
  let depth32_float_stencil8 = Unsigned.UInt32.of_int 0x0002
  let timestamp_query = Unsigned.UInt32.of_int 0x0003
  let texture_compression_bc = Unsigned.UInt32.of_int 0x0004
  let texture_compression_bc_sliced_3d = Unsigned.UInt32.of_int 0x0005
  let texture_compression_etc2 = Unsigned.UInt32.of_int 0x0006
  let texture_compression_astc = Unsigned.UInt32.of_int 0x0007
  let texture_compression_astc_sliced_3d = Unsigned.UInt32.of_int 0x0008
  let indirect_first_instance = Unsigned.UInt32.of_int 0x0009
  let shader_f16 = Unsigned.UInt32.of_int 0x000A
  let rg11b10_ufloat_renderable = Unsigned.UInt32.of_int 0x000B
  let bgra8_unorm_storage = Unsigned.UInt32.of_int 0x000C
  let float32_filterable = Unsigned.UInt32.of_int 0x000D
  let float32_blendable = Unsigned.UInt32.of_int 0x000E
  let clip_distances = Unsigned.UInt32.of_int 0x000F
  let dual_source_blending = Unsigned.UInt32.of_int 0x0010
end

module FilterMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let nearest = Unsigned.UInt32.of_int 0x0001
  let linear = Unsigned.UInt32.of_int 0x0002
end

module FrontFace = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let ccw = Unsigned.UInt32.of_int 0x0001
  let cw = Unsigned.UInt32.of_int 0x0002
end

module IndexFormat = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let uint16 = Unsigned.UInt32.of_int 0x0001
  let uint32 = Unsigned.UInt32.of_int 0x0002
end

module LoadOp = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let load = Unsigned.UInt32.of_int 0x0001
  let clear = Unsigned.UInt32.of_int 0x0002
end

module MapAsyncStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let error = Unsigned.UInt32.of_int 0x0003
  let aborted = Unsigned.UInt32.of_int 0x0004
  let unknown = Unsigned.UInt32.of_int 0x0005
end

module MipmapFilterMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let nearest = Unsigned.UInt32.of_int 0x0001
  let linear = Unsigned.UInt32.of_int 0x0002
end

module OptionalBool = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let false_ = Unsigned.UInt32.of_int 0x0000
  let true_ = Unsigned.UInt32.of_int 0x0001
  let undefined = Unsigned.UInt32.of_int 0x0002
end

module PopErrorScopeStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let empty_stack = Unsigned.UInt32.of_int 0x0003
end

module PowerPreference = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let low_power = Unsigned.UInt32.of_int 0x0001
  let high_performance = Unsigned.UInt32.of_int 0x0002
end

module PresentMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let fifo = Unsigned.UInt32.of_int 0x0001
  let fifo_relaxed = Unsigned.UInt32.of_int 0x0002
  let immediate = Unsigned.UInt32.of_int 0x0003
  let mailbox = Unsigned.UInt32.of_int 0x0004
end

module PrimitiveTopology = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let point_list = Unsigned.UInt32.of_int 0x0001
  let line_list = Unsigned.UInt32.of_int 0x0002
  let line_strip = Unsigned.UInt32.of_int 0x0003
  let triangle_list = Unsigned.UInt32.of_int 0x0004
  let triangle_strip = Unsigned.UInt32.of_int 0x0005
end

module QueryType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let occlusion = Unsigned.UInt32.of_int 0x0001
  let timestamp = Unsigned.UInt32.of_int 0x0002
end

module QueueWorkDoneStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let error = Unsigned.UInt32.of_int 0x0003
  let unknown = Unsigned.UInt32.of_int 0x0004
end

module RequestAdapterStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let unavailable = Unsigned.UInt32.of_int 0x0003
  let error = Unsigned.UInt32.of_int 0x0004
  let unknown = Unsigned.UInt32.of_int 0x0005
end

module RequestDeviceStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let instance_dropped = Unsigned.UInt32.of_int 0x0002
  let error = Unsigned.UInt32.of_int 0x0003
  let unknown = Unsigned.UInt32.of_int 0x0004
end

module SType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let shader_source_spirv = Unsigned.UInt32.of_int 0x0001
  let shader_source_wgsl = Unsigned.UInt32.of_int 0x0002
  let render_pass_max_draw_count = Unsigned.UInt32.of_int 0x0003
  let surface_source_metal_layer = Unsigned.UInt32.of_int 0x0004
  let surface_source_windows_hwnd = Unsigned.UInt32.of_int 0x0005
  let surface_source_xlib_window = Unsigned.UInt32.of_int 0x0006
  let surface_source_wayland_surface = Unsigned.UInt32.of_int 0x0007
  let surface_source_android_native_window = Unsigned.UInt32.of_int 0x0008
  let surface_source_xcb_window = Unsigned.UInt32.of_int 0x0009
end

module SamplerBindingType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let binding_not_used = Unsigned.UInt32.of_int 0x0000
  let undefined = Unsigned.UInt32.of_int 0x0001
  let filtering = Unsigned.UInt32.of_int 0x0002
  let non_filtering = Unsigned.UInt32.of_int 0x0003
  let comparison = Unsigned.UInt32.of_int 0x0004
end

module Status = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let error = Unsigned.UInt32.of_int 0x0002
end

module StencilOperation = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let keep = Unsigned.UInt32.of_int 0x0001
  let zero = Unsigned.UInt32.of_int 0x0002
  let replace = Unsigned.UInt32.of_int 0x0003
  let invert = Unsigned.UInt32.of_int 0x0004
  let increment_clamp = Unsigned.UInt32.of_int 0x0005
  let decrement_clamp = Unsigned.UInt32.of_int 0x0006
  let increment_wrap = Unsigned.UInt32.of_int 0x0007
  let decrement_wrap = Unsigned.UInt32.of_int 0x0008
end

module StorageTextureAccess = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let binding_not_used = Unsigned.UInt32.of_int 0x0000
  let undefined = Unsigned.UInt32.of_int 0x0001
  let write_only = Unsigned.UInt32.of_int 0x0002
  let read_only = Unsigned.UInt32.of_int 0x0003
  let read_write = Unsigned.UInt32.of_int 0x0004
end

module StoreOp = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let store = Unsigned.UInt32.of_int 0x0001
  let discard = Unsigned.UInt32.of_int 0x0002
end

module SurfaceGetCurrentTextureStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success_optimal = Unsigned.UInt32.of_int 0x0001
  let success_suboptimal = Unsigned.UInt32.of_int 0x0002
  let timeout = Unsigned.UInt32.of_int 0x0003
  let outdated = Unsigned.UInt32.of_int 0x0004
  let lost = Unsigned.UInt32.of_int 0x0005
  let out_of_memory = Unsigned.UInt32.of_int 0x0006
  let device_lost = Unsigned.UInt32.of_int 0x0007
  let error = Unsigned.UInt32.of_int 0x0008
end

module TextureAspect = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let all = Unsigned.UInt32.of_int 0x0001
  let stencil_only = Unsigned.UInt32.of_int 0x0002
  let depth_only = Unsigned.UInt32.of_int 0x0003
end

module TextureDimension = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let _1d = Unsigned.UInt32.of_int 0x0001
  let _2d = Unsigned.UInt32.of_int 0x0002
  let _3d = Unsigned.UInt32.of_int 0x0003
end

module TextureFormat = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let r8_unorm = Unsigned.UInt32.of_int 0x0001
  let r8_snorm = Unsigned.UInt32.of_int 0x0002
  let r8_uint = Unsigned.UInt32.of_int 0x0003
  let r8_sint = Unsigned.UInt32.of_int 0x0004
  let r16_uint = Unsigned.UInt32.of_int 0x0005
  let r16_sint = Unsigned.UInt32.of_int 0x0006
  let r16_float = Unsigned.UInt32.of_int 0x0007
  let rg8_unorm = Unsigned.UInt32.of_int 0x0008
  let rg8_snorm = Unsigned.UInt32.of_int 0x0009
  let rg8_uint = Unsigned.UInt32.of_int 0x000A
  let rg8_sint = Unsigned.UInt32.of_int 0x000B
  let r32_float = Unsigned.UInt32.of_int 0x000C
  let r32_uint = Unsigned.UInt32.of_int 0x000D
  let r32_sint = Unsigned.UInt32.of_int 0x000E
  let rg16_uint = Unsigned.UInt32.of_int 0x000F
  let rg16_sint = Unsigned.UInt32.of_int 0x0010
  let rg16_float = Unsigned.UInt32.of_int 0x0011
  let rgba8_unorm = Unsigned.UInt32.of_int 0x0012
  let rgba8_unorm_srgb = Unsigned.UInt32.of_int 0x0013
  let rgba8_snorm = Unsigned.UInt32.of_int 0x0014
  let rgba8_uint = Unsigned.UInt32.of_int 0x0015
  let rgba8_sint = Unsigned.UInt32.of_int 0x0016
  let bgra8_unorm = Unsigned.UInt32.of_int 0x0017
  let bgra8_unorm_srgb = Unsigned.UInt32.of_int 0x0018
  let rgb10_a2_uint = Unsigned.UInt32.of_int 0x0019
  let rgb10_a2_unorm = Unsigned.UInt32.of_int 0x001A
  let rg11_b10_ufloat = Unsigned.UInt32.of_int 0x001B
  let rgb9_e5_ufloat = Unsigned.UInt32.of_int 0x001C
  let rg32_float = Unsigned.UInt32.of_int 0x001D
  let rg32_uint = Unsigned.UInt32.of_int 0x001E
  let rg32_sint = Unsigned.UInt32.of_int 0x001F
  let rgba16_uint = Unsigned.UInt32.of_int 0x0020
  let rgba16_sint = Unsigned.UInt32.of_int 0x0021
  let rgba16_float = Unsigned.UInt32.of_int 0x0022
  let rgba32_float = Unsigned.UInt32.of_int 0x0023
  let rgba32_uint = Unsigned.UInt32.of_int 0x0024
  let rgba32_sint = Unsigned.UInt32.of_int 0x0025
  let stencil8 = Unsigned.UInt32.of_int 0x0026
  let depth16_unorm = Unsigned.UInt32.of_int 0x0027
  let depth24_plus = Unsigned.UInt32.of_int 0x0028
  let depth24_plus_stencil8 = Unsigned.UInt32.of_int 0x0029
  let depth32_float = Unsigned.UInt32.of_int 0x002A
  let depth32_float_stencil8 = Unsigned.UInt32.of_int 0x002B
  let bc1_rgba_unorm = Unsigned.UInt32.of_int 0x002C
  let bc1_rgba_unorm_srgb = Unsigned.UInt32.of_int 0x002D
  let bc2_rgba_unorm = Unsigned.UInt32.of_int 0x002E
  let bc2_rgba_unorm_srgb = Unsigned.UInt32.of_int 0x002F
  let bc3_rgba_unorm = Unsigned.UInt32.of_int 0x0030
  let bc3_rgba_unorm_srgb = Unsigned.UInt32.of_int 0x0031
  let bc4_r_unorm = Unsigned.UInt32.of_int 0x0032
  let bc4_r_snorm = Unsigned.UInt32.of_int 0x0033
  let bc5_rg_unorm = Unsigned.UInt32.of_int 0x0034
  let bc5_rg_snorm = Unsigned.UInt32.of_int 0x0035
  let bc6h_rgb_ufloat = Unsigned.UInt32.of_int 0x0036
  let bc6h_rgb_float = Unsigned.UInt32.of_int 0x0037
  let bc7_rgba_unorm = Unsigned.UInt32.of_int 0x0038
  let bc7_rgba_unorm_srgb = Unsigned.UInt32.of_int 0x0039
  let etc2_rgb8_unorm = Unsigned.UInt32.of_int 0x003A
  let etc2_rgb8_unorm_srgb = Unsigned.UInt32.of_int 0x003B
  let etc2_rgb8a1_unorm = Unsigned.UInt32.of_int 0x003C
  let etc2_rgb8a1_unorm_srgb = Unsigned.UInt32.of_int 0x003D
  let etc2_rgba8_unorm = Unsigned.UInt32.of_int 0x003E
  let etc2_rgba8_unorm_srgb = Unsigned.UInt32.of_int 0x003F
  let eac_r11_unorm = Unsigned.UInt32.of_int 0x0040
  let eac_r11_snorm = Unsigned.UInt32.of_int 0x0041
  let eac_rg11_unorm = Unsigned.UInt32.of_int 0x0042
  let eac_rg11_snorm = Unsigned.UInt32.of_int 0x0043
  let astc_4x4_unorm = Unsigned.UInt32.of_int 0x0044
  let astc_4x4_unorm_srgb = Unsigned.UInt32.of_int 0x0045
  let astc_5x4_unorm = Unsigned.UInt32.of_int 0x0046
  let astc_5x4_unorm_srgb = Unsigned.UInt32.of_int 0x0047
  let astc_5x5_unorm = Unsigned.UInt32.of_int 0x0048
  let astc_5x5_unorm_srgb = Unsigned.UInt32.of_int 0x0049
  let astc_6x5_unorm = Unsigned.UInt32.of_int 0x004A
  let astc_6x5_unorm_srgb = Unsigned.UInt32.of_int 0x004B
  let astc_6x6_unorm = Unsigned.UInt32.of_int 0x004C
  let astc_6x6_unorm_srgb = Unsigned.UInt32.of_int 0x004D
  let astc_8x5_unorm = Unsigned.UInt32.of_int 0x004E
  let astc_8x5_unorm_srgb = Unsigned.UInt32.of_int 0x004F
  let astc_8x6_unorm = Unsigned.UInt32.of_int 0x0050
  let astc_8x6_unorm_srgb = Unsigned.UInt32.of_int 0x0051
  let astc_8x8_unorm = Unsigned.UInt32.of_int 0x0052
  let astc_8x8_unorm_srgb = Unsigned.UInt32.of_int 0x0053
  let astc_10x5_unorm = Unsigned.UInt32.of_int 0x0054
  let astc_10x5_unorm_srgb = Unsigned.UInt32.of_int 0x0055
  let astc_10x6_unorm = Unsigned.UInt32.of_int 0x0056
  let astc_10x6_unorm_srgb = Unsigned.UInt32.of_int 0x0057
  let astc_10x8_unorm = Unsigned.UInt32.of_int 0x0058
  let astc_10x8_unorm_srgb = Unsigned.UInt32.of_int 0x0059
  let astc_10x10_unorm = Unsigned.UInt32.of_int 0x005A
  let astc_10x10_unorm_srgb = Unsigned.UInt32.of_int 0x005B
  let astc_12x10_unorm = Unsigned.UInt32.of_int 0x005C
  let astc_12x10_unorm_srgb = Unsigned.UInt32.of_int 0x005D
  let astc_12x12_unorm = Unsigned.UInt32.of_int 0x005E
  let astc_12x12_unorm_srgb = Unsigned.UInt32.of_int 0x005F
end

module TextureSampleType = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let binding_not_used = Unsigned.UInt32.of_int 0x0000
  let undefined = Unsigned.UInt32.of_int 0x0001
  let float = Unsigned.UInt32.of_int 0x0002
  let unfilterable_float = Unsigned.UInt32.of_int 0x0003
  let depth = Unsigned.UInt32.of_int 0x0004
  let sint = Unsigned.UInt32.of_int 0x0005
  let uint = Unsigned.UInt32.of_int 0x0006
end

module TextureViewDimension = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let undefined = Unsigned.UInt32.of_int 0x0000
  let _1d = Unsigned.UInt32.of_int 0x0001
  let _2d = Unsigned.UInt32.of_int 0x0002
  let _2d_array = Unsigned.UInt32.of_int 0x0003
  let cube = Unsigned.UInt32.of_int 0x0004
  let cube_array = Unsigned.UInt32.of_int 0x0005
  let _3d = Unsigned.UInt32.of_int 0x0006
end

module VertexFormat = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let uint8 = Unsigned.UInt32.of_int 0x0001
  let uint8x2 = Unsigned.UInt32.of_int 0x0002
  let uint8x4 = Unsigned.UInt32.of_int 0x0003
  let sint8 = Unsigned.UInt32.of_int 0x0004
  let sint8x2 = Unsigned.UInt32.of_int 0x0005
  let sint8x4 = Unsigned.UInt32.of_int 0x0006
  let unorm8 = Unsigned.UInt32.of_int 0x0007
  let unorm8x2 = Unsigned.UInt32.of_int 0x0008
  let unorm8x4 = Unsigned.UInt32.of_int 0x0009
  let snorm8 = Unsigned.UInt32.of_int 0x000A
  let snorm8x2 = Unsigned.UInt32.of_int 0x000B
  let snorm8x4 = Unsigned.UInt32.of_int 0x000C
  let uint16 = Unsigned.UInt32.of_int 0x000D
  let uint16x2 = Unsigned.UInt32.of_int 0x000E
  let uint16x4 = Unsigned.UInt32.of_int 0x000F
  let sint16 = Unsigned.UInt32.of_int 0x0010
  let sint16x2 = Unsigned.UInt32.of_int 0x0011
  let sint16x4 = Unsigned.UInt32.of_int 0x0012
  let unorm16 = Unsigned.UInt32.of_int 0x0013
  let unorm16x2 = Unsigned.UInt32.of_int 0x0014
  let unorm16x4 = Unsigned.UInt32.of_int 0x0015
  let snorm16 = Unsigned.UInt32.of_int 0x0016
  let snorm16x2 = Unsigned.UInt32.of_int 0x0017
  let snorm16x4 = Unsigned.UInt32.of_int 0x0018
  let float16 = Unsigned.UInt32.of_int 0x0019
  let float16x2 = Unsigned.UInt32.of_int 0x001A
  let float16x4 = Unsigned.UInt32.of_int 0x001B
  let float32 = Unsigned.UInt32.of_int 0x001C
  let float32x2 = Unsigned.UInt32.of_int 0x001D
  let float32x3 = Unsigned.UInt32.of_int 0x001E
  let float32x4 = Unsigned.UInt32.of_int 0x001F
  let uint32 = Unsigned.UInt32.of_int 0x0020
  let uint32x2 = Unsigned.UInt32.of_int 0x0021
  let uint32x3 = Unsigned.UInt32.of_int 0x0022
  let uint32x4 = Unsigned.UInt32.of_int 0x0023
  let sint32 = Unsigned.UInt32.of_int 0x0024
  let sint32x2 = Unsigned.UInt32.of_int 0x0025
  let sint32x3 = Unsigned.UInt32.of_int 0x0026
  let sint32x4 = Unsigned.UInt32.of_int 0x0027
  let unorm10__10__10__2 = Unsigned.UInt32.of_int 0x0028
  let unorm8x4_b_g_r_a = Unsigned.UInt32.of_int 0x0029
end

module VertexStepMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let vertex_buffer_not_used = Unsigned.UInt32.of_int 0x0000
  let undefined = Unsigned.UInt32.of_int 0x0001
  let vertex = Unsigned.UInt32.of_int 0x0002
  let instance = Unsigned.UInt32.of_int 0x0003
end

module WaitStatus = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let success = Unsigned.UInt32.of_int 0x0001
  let timed_out = Unsigned.UInt32.of_int 0x0002
  let unsupported_timeout = Unsigned.UInt32.of_int 0x0003
  let unsupported_count = Unsigned.UInt32.of_int 0x0004
  let unsupported_mixed_sources = Unsigned.UInt32.of_int 0x0005
end

module WGSLLanguageFeatureName = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let readonly_and_readwrite_storage_textures = Unsigned.UInt32.of_int 0x0001
  let packed4x8_integer_dot_product = Unsigned.UInt32.of_int 0x0002
  let unrestricted_pointer_parameters = Unsigned.UInt32.of_int 0x0003
  let pointer_composite_access = Unsigned.UInt32.of_int 0x0004
end

(* === Bitflags === *)

module BufferUsage = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let none = Unsigned.UInt32.of_int 0x0000
  let map_read = Unsigned.UInt32.of_int 0x0001
  let map_write = Unsigned.UInt32.of_int 0x0002
  let copy_src = Unsigned.UInt32.of_int 0x0004
  let copy_dst = Unsigned.UInt32.of_int 0x0008
  let index = Unsigned.UInt32.of_int 0x0010
  let vertex = Unsigned.UInt32.of_int 0x0020
  let uniform = Unsigned.UInt32.of_int 0x0040
  let storage = Unsigned.UInt32.of_int 0x0080
  let indirect = Unsigned.UInt32.of_int 0x0100
  let query_resolve = Unsigned.UInt32.of_int 0x0200
  let ( + ) = Unsigned.UInt32.logor
end

module ColorWriteMask = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let none = Unsigned.UInt32.of_int 0x0000
  let red = Unsigned.UInt32.of_int 0x0001
  let green = Unsigned.UInt32.of_int 0x0002
  let blue = Unsigned.UInt32.of_int 0x0004
  let alpha = Unsigned.UInt32.of_int 0x0008
  let all = Unsigned.UInt32.of_int 0x0010
  let ( + ) = Unsigned.UInt32.logor
end

module MapMode = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let none = Unsigned.UInt32.of_int 0x0000
  let read = Unsigned.UInt32.of_int 0x0001
  let write = Unsigned.UInt32.of_int 0x0002
  let ( + ) = Unsigned.UInt32.logor
end

module ShaderStage = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let none = Unsigned.UInt32.of_int 0x0000
  let vertex = Unsigned.UInt32.of_int 0x0001
  let fragment = Unsigned.UInt32.of_int 0x0002
  let compute = Unsigned.UInt32.of_int 0x0004
  let ( + ) = Unsigned.UInt32.logor
end

module TextureUsage = struct
  type t = Unsigned.UInt32.t

  let t = uint32_t
  let none = Unsigned.UInt32.of_int 0x0000
  let copy_src = Unsigned.UInt32.of_int 0x0001
  let copy_dst = Unsigned.UInt32.of_int 0x0002
  let texture_binding = Unsigned.UInt32.of_int 0x0004
  let storage_binding = Unsigned.UInt32.of_int 0x0008
  let render_attachment = Unsigned.UInt32.of_int 0x0010
  let ( + ) = Unsigned.UInt32.logor
end

(* === Object Handles === *)

module Adapter = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module BindGroup = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module BindGroupLayout = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Buffer = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module CommandBuffer = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module CommandEncoder = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module ComputePassEncoder = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module ComputePipeline = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Device = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Instance = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module PipelineLayout = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module QuerySet = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Queue = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module RenderBundle = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module RenderBundleEncoder = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module RenderPassEncoder = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module RenderPipeline = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Sampler = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module ShaderModule = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Surface = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module Texture = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

module TextureView = struct
  type t = unit ptr

  let t : t typ = ptr void
  let t_opt : t option typ = ptr_opt void
end

(* === Callback Info Structs === *)

module BufferMapCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUBufferMapCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module CompilationInfoCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUCompilationInfoCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module CreateComputePipelineAsyncCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUCreateComputePipelineAsyncCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module CreateRenderPipelineAsyncCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUCreateRenderPipelineAsyncCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module DeviceLostCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUDeviceLostCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module PopErrorScopeCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUPopErrorScopeCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module QueueWorkDoneCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUQueueWorkDoneCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module RequestAdapterCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPURequestAdapterCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module RequestDeviceCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPURequestDeviceCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

module UncapturedErrorCallbackInfo = struct
  type t

  let t : t structure typ = structure "WGPUUncapturedErrorCallbackInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let mode = field t "mode" uint32_t
  let callback = field t "callback" (ptr void)
  let userdata1 = field t "userdata1" (ptr void)
  let userdata2 = field t "userdata2" (ptr void)
  let () = seal t
end

(* === Structs === *)

module AdapterInfo = struct
  type t

  let t : t structure typ = structure "WGPUAdapterInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let vendor = field t "vendor" String_view.t
  let architecture = field t "architecture" String_view.t
  let device = field t "device" String_view.t
  let description = field t "description" String_view.t
  let backend_type = field t "backendType" BackendType.t
  let adapter_type = field t "adapterType" AdapterType.t
  let vendor_id = field t "vendorID" uint32_t
  let device_id = field t "deviceID" uint32_t
  let () = seal t
end

module BindGroupDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUBindGroupDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let layout = field t "layout" BindGroupLayout.t
  let entries_count = field t "entriesCount" size_t
  let entries = field t "entries" (ptr (ptr void))
  let () = seal t
end

module BindGroupEntry = struct
  type t

  let t : t structure typ = structure "WGPUBindGroupEntry"
  let next_in_chain = field t "nextInChain" (ptr void)
  let binding = field t "binding" uint32_t
  let buffer = field t "buffer" Buffer.t
  let offset = field t "offset" uint64_t
  let size = field t "size" uint64_t
  let sampler = field t "sampler" Sampler.t
  let texture_view = field t "textureView" TextureView.t
  let () = seal t
end

module BindGroupLayoutDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUBindGroupLayoutDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let entries_count = field t "entriesCount" size_t
  let entries = field t "entries" (ptr (ptr void))
  let () = seal t
end

module BufferBindingLayout = struct
  type t

  let t : t structure typ = structure "WGPUBufferBindingLayout"
  let next_in_chain = field t "nextInChain" (ptr void)
  let type_ = field t "type" BufferBindingType.t
  let has_dynamic_offset = field t "hasDynamicOffset" uint32_t
  let min_binding_size = field t "minBindingSize" uint64_t
  let () = seal t
end

module SamplerBindingLayout = struct
  type t

  let t : t structure typ = structure "WGPUSamplerBindingLayout"
  let next_in_chain = field t "nextInChain" (ptr void)
  let type_ = field t "type" SamplerBindingType.t
  let () = seal t
end

module TextureBindingLayout = struct
  type t

  let t : t structure typ = structure "WGPUTextureBindingLayout"
  let next_in_chain = field t "nextInChain" (ptr void)
  let sample_type = field t "sampleType" TextureSampleType.t
  let view_dimension = field t "viewDimension" TextureViewDimension.t
  let multisampled = field t "multisampled" uint32_t
  let () = seal t
end

module StorageTextureBindingLayout = struct
  type t

  let t : t structure typ = structure "WGPUStorageTextureBindingLayout"
  let next_in_chain = field t "nextInChain" (ptr void)
  let access = field t "access" StorageTextureAccess.t
  let format = field t "format" TextureFormat.t
  let view_dimension = field t "viewDimension" TextureViewDimension.t
  let () = seal t
end

module BindGroupLayoutEntry = struct
  type t

  let t : t structure typ = structure "WGPUBindGroupLayoutEntry"
  let next_in_chain = field t "nextInChain" (ptr void)
  let binding = field t "binding" uint32_t
  let visibility = field t "visibility" ShaderStage.t
  let buffer = field t "buffer" BufferBindingLayout.t
  let sampler = field t "sampler" SamplerBindingLayout.t
  let texture = field t "texture" TextureBindingLayout.t
  let storage_texture = field t "storageTexture" StorageTextureBindingLayout.t
  let () = seal t
end

module BlendComponent = struct
  type t

  let t : t structure typ = structure "WGPUBlendComponent"
  let operation = field t "operation" BlendOperation.t
  let src_factor = field t "srcFactor" BlendFactor.t
  let dst_factor = field t "dstFactor" BlendFactor.t
  let () = seal t
end

module BlendState = struct
  type t

  let t : t structure typ = structure "WGPUBlendState"
  let color = field t "color" BlendComponent.t
  let alpha = field t "alpha" BlendComponent.t
  let () = seal t
end

module BufferDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUBufferDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let usage = field t "usage" BufferUsage.t
  let size = field t "size" uint64_t
  let mapped_at_creation = field t "mappedAtCreation" uint32_t
  let () = seal t
end

module Color = struct
  type t

  let t : t structure typ = structure "WGPUColor"
  let r = field t "r" double
  let g = field t "g" double
  let b = field t "b" double
  let a = field t "a" double
  let () = seal t
end

module ColorTargetState = struct
  type t

  let t : t structure typ = structure "WGPUColorTargetState"
  let next_in_chain = field t "nextInChain" (ptr void)
  let format = field t "format" TextureFormat.t
  let blend = field t "blend" (ptr (ptr void))
  let write_mask = field t "writeMask" ColorWriteMask.t
  let () = seal t
end

module CommandBufferDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUCommandBufferDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let () = seal t
end

module CommandEncoderDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUCommandEncoderDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let () = seal t
end

module CompilationInfo = struct
  type t

  let t : t structure typ = structure "WGPUCompilationInfo"
  let next_in_chain = field t "nextInChain" (ptr void)
  let messages_count = field t "messagesCount" size_t
  let messages = field t "messages" (ptr (ptr void))
  let () = seal t
end

module CompilationMessage = struct
  type t

  let t : t structure typ = structure "WGPUCompilationMessage"
  let next_in_chain = field t "nextInChain" (ptr void)
  let message = field t "message" String_view.t
  let type_ = field t "type" CompilationMessageType.t
  let line_num = field t "lineNum" uint64_t
  let line_pos = field t "linePos" uint64_t
  let offset = field t "offset" uint64_t
  let length = field t "length" uint64_t
  let () = seal t
end

module ComputePassDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUComputePassDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let timestamp_writes = field t "timestampWrites" (ptr (ptr void))
  let () = seal t
end

module ComputePassTimestampWrites = struct
  type t

  let t : t structure typ = structure "WGPUComputePassTimestampWrites"
  let query_set = field t "querySet" QuerySet.t
  let beginning_of_pass_write_index = field t "beginningOfPassWriteIndex" uint32_t
  let end_of_pass_write_index = field t "endOfPassWriteIndex" uint32_t
  let () = seal t
end

module ProgrammableStageDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUProgrammableStageDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let module_ = field t "module" ShaderModule.t
  let entry_point = field t "entryPoint" String_view.t
  let constants_count = field t "constantsCount" size_t
  let constants = field t "constants" (ptr (ptr void))
  let () = seal t
end

module ComputePipelineDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUComputePipelineDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let layout = field t "layout" PipelineLayout.t
  let compute = field t "compute" ProgrammableStageDescriptor.t
  let () = seal t
end

module ConstantEntry = struct
  type t

  let t : t structure typ = structure "WGPUConstantEntry"
  let next_in_chain = field t "nextInChain" (ptr void)
  let key = field t "key" String_view.t
  let value = field t "value" double
  let () = seal t
end

module StencilFaceState = struct
  type t

  let t : t structure typ = structure "WGPUStencilFaceState"
  let compare = field t "compare" CompareFunction.t
  let fail_op = field t "failOp" StencilOperation.t
  let depth_fail_op = field t "depthFailOp" StencilOperation.t
  let pass_op = field t "passOp" StencilOperation.t
  let () = seal t
end

module DepthStencilState = struct
  type t

  let t : t structure typ = structure "WGPUDepthStencilState"
  let next_in_chain = field t "nextInChain" (ptr void)
  let format = field t "format" TextureFormat.t
  let depth_write_enabled = field t "depthWriteEnabled" OptionalBool.t
  let depth_compare = field t "depthCompare" CompareFunction.t
  let stencil_front = field t "stencilFront" StencilFaceState.t
  let stencil_back = field t "stencilBack" StencilFaceState.t
  let stencil_read_mask = field t "stencilReadMask" uint32_t
  let stencil_write_mask = field t "stencilWriteMask" uint32_t
  let depth_bias = field t "depthBias" int32_t
  let depth_bias_slope_scale = field t "depthBiasSlopeScale" float
  let depth_bias_clamp = field t "depthBiasClamp" float
  let () = seal t
end

module QueueDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUQueueDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let () = seal t
end

module DeviceDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUDeviceDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let required_features_count = field t "requiredFeaturesCount" size_t
  let required_features = field t "requiredFeatures" (ptr FeatureName.t)
  let required_limits = field t "requiredLimits" (ptr (ptr void))
  let default_queue = field t "defaultQueue" QueueDescriptor.t
  let device_lost_callback_info = field t "deviceLostCallbackInfo" (ptr void)
  let uncaptured_error_callback_info = field t "uncapturedErrorCallbackInfo" (ptr void)
  let () = seal t
end

module Extent3D = struct
  type t

  let t : t structure typ = structure "WGPUExtent3D"
  let width = field t "width" uint32_t
  let height = field t "height" uint32_t
  let depth_or_array_layers = field t "depthOrArrayLayers" uint32_t
  let () = seal t
end

module FragmentState = struct
  type t

  let t : t structure typ = structure "WGPUFragmentState"
  let next_in_chain = field t "nextInChain" (ptr void)
  let module_ = field t "module" ShaderModule.t
  let entry_point = field t "entryPoint" String_view.t
  let constants_count = field t "constantsCount" size_t
  let constants = field t "constants" (ptr (ptr void))
  let targets_count = field t "targetsCount" size_t
  let targets = field t "targets" (ptr (ptr void))
  let () = seal t
end

module Future = struct
  type t

  let t : t structure typ = structure "WGPUFuture"
  let id = field t "id" uint64_t
  let () = seal t
end

module FutureWaitInfo = struct
  type t

  let t : t structure typ = structure "WGPUFutureWaitInfo"
  let future = field t "future" Future.t
  let completed = field t "completed" uint32_t
  let () = seal t
end

module InstanceCapabilities = struct
  type t

  let t : t structure typ = structure "WGPUInstanceCapabilities"
  let timed_wait_any_enable = field t "timedWaitAnyEnable" uint32_t
  let timed_wait_any_max_count = field t "timedWaitAnyMaxCount" size_t
  let () = seal t
end

module InstanceDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUInstanceDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let features = field t "features" InstanceCapabilities.t
  let () = seal t
end

module Limits = struct
  type t

  let t : t structure typ = structure "WGPULimits"
  let max_texture_dimension_1d = field t "maxTextureDimension1D" uint32_t
  let max_texture_dimension_2d = field t "maxTextureDimension2D" uint32_t
  let max_texture_dimension_3d = field t "maxTextureDimension3D" uint32_t
  let max_texture_array_layers = field t "maxTextureArrayLayers" uint32_t
  let max_bind_groups = field t "maxBindGroups" uint32_t

  let max_bind_groups_plus_vertex_buffers =
    field t "maxBindGroupsPlusVertexBuffers" uint32_t
  ;;

  let max_bindings_per_bind_group = field t "maxBindingsPerBindGroup" uint32_t

  let max_dynamic_uniform_buffers_per_pipeline_layout =
    field t "maxDynamicUniformBuffersPerPipelineLayout" uint32_t
  ;;

  let max_dynamic_storage_buffers_per_pipeline_layout =
    field t "maxDynamicStorageBuffersPerPipelineLayout" uint32_t
  ;;

  let max_sampled_textures_per_shader_stage =
    field t "maxSampledTexturesPerShaderStage" uint32_t
  ;;

  let max_samplers_per_shader_stage = field t "maxSamplersPerShaderStage" uint32_t

  let max_storage_buffers_per_shader_stage =
    field t "maxStorageBuffersPerShaderStage" uint32_t
  ;;

  let max_storage_textures_per_shader_stage =
    field t "maxStorageTexturesPerShaderStage" uint32_t
  ;;

  let max_uniform_buffers_per_shader_stage =
    field t "maxUniformBuffersPerShaderStage" uint32_t
  ;;

  let max_uniform_buffer_binding_size = field t "maxUniformBufferBindingSize" uint64_t
  let max_storage_buffer_binding_size = field t "maxStorageBufferBindingSize" uint64_t

  let min_uniform_buffer_offset_alignment =
    field t "minUniformBufferOffsetAlignment" uint32_t
  ;;

  let min_storage_buffer_offset_alignment =
    field t "minStorageBufferOffsetAlignment" uint32_t
  ;;

  let max_vertex_buffers = field t "maxVertexBuffers" uint32_t
  let max_buffer_size = field t "maxBufferSize" uint64_t
  let max_vertex_attributes = field t "maxVertexAttributes" uint32_t
  let max_vertex_buffer_array_stride = field t "maxVertexBufferArrayStride" uint32_t
  let max_inter_stage_shader_variables = field t "maxInterStageShaderVariables" uint32_t
  let max_color_attachments = field t "maxColorAttachments" uint32_t

  let max_color_attachment_bytes_per_sample =
    field t "maxColorAttachmentBytesPerSample" uint32_t
  ;;

  let max_compute_workgroup_storage_size =
    field t "maxComputeWorkgroupStorageSize" uint32_t
  ;;

  let max_compute_invocations_per_workgroup =
    field t "maxComputeInvocationsPerWorkgroup" uint32_t
  ;;

  let max_compute_workgroup_size_x = field t "maxComputeWorkgroupSizeX" uint32_t
  let max_compute_workgroup_size_y = field t "maxComputeWorkgroupSizeY" uint32_t
  let max_compute_workgroup_size_z = field t "maxComputeWorkgroupSizeZ" uint32_t

  let max_compute_workgroups_per_dimension =
    field t "maxComputeWorkgroupsPerDimension" uint32_t
  ;;

  let () = seal t
end

module MultisampleState = struct
  type t

  let t : t structure typ = structure "WGPUMultisampleState"
  let next_in_chain = field t "nextInChain" (ptr void)
  let count = field t "count" uint32_t
  let mask = field t "mask" uint32_t
  let alpha_to_coverage_enabled = field t "alphaToCoverageEnabled" uint32_t
  let () = seal t
end

module Origin3D = struct
  type t

  let t : t structure typ = structure "WGPUOrigin3D"
  let x = field t "x" uint32_t
  let unknown = field t "unknown" uint32_t
  let z = field t "z" uint32_t
  let () = seal t
end

module PipelineLayoutDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUPipelineLayoutDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let bind_group_layouts_count = field t "bindGroupLayoutsCount" size_t
  let bind_group_layouts = field t "bindGroupLayouts" (ptr BindGroupLayout.t)
  let () = seal t
end

module PrimitiveState = struct
  type t

  let t : t structure typ = structure "WGPUPrimitiveState"
  let next_in_chain = field t "nextInChain" (ptr void)
  let topology = field t "topology" PrimitiveTopology.t
  let strip_index_format = field t "stripIndexFormat" IndexFormat.t
  let front_face = field t "frontFace" FrontFace.t
  let cull_mode = field t "cullMode" CullMode.t
  let unclipped_depth = field t "unclippedDepth" uint32_t
  let () = seal t
end

module QuerySetDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUQuerySetDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let type_ = field t "type" QueryType.t
  let count = field t "count" uint32_t
  let () = seal t
end

module RenderBundleDescriptor = struct
  type t

  let t : t structure typ = structure "WGPURenderBundleDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let () = seal t
end

module RenderBundleEncoderDescriptor = struct
  type t

  let t : t structure typ = structure "WGPURenderBundleEncoderDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let color_formats_count = field t "colorFormatsCount" size_t
  let color_formats = field t "colorFormats" (ptr TextureFormat.t)
  let depth_stencil_format = field t "depthStencilFormat" TextureFormat.t
  let sample_count = field t "sampleCount" uint32_t
  let depth_read_only = field t "depthReadOnly" uint32_t
  let stencil_read_only = field t "stencilReadOnly" uint32_t
  let () = seal t
end

module RenderPassColorAttachment = struct
  type t

  let t : t structure typ = structure "WGPURenderPassColorAttachment"
  let next_in_chain = field t "nextInChain" (ptr void)
  let view = field t "view" TextureView.t
  let depth_slice = field t "depthSlice" uint32_t
  let resolve_target = field t "resolveTarget" TextureView.t
  let load_op = field t "loadOp" LoadOp.t
  let store_op = field t "storeOp" StoreOp.t
  let clear_value = field t "clearValue" Color.t
  let () = seal t
end

module RenderPassDepthStencilAttachment = struct
  type t

  let t : t structure typ = structure "WGPURenderPassDepthStencilAttachment"
  let view = field t "view" TextureView.t
  let depth_load_op = field t "depthLoadOp" LoadOp.t
  let depth_store_op = field t "depthStoreOp" StoreOp.t
  let depth_clear_value = field t "depthClearValue" float
  let depth_read_only = field t "depthReadOnly" uint32_t
  let stencil_load_op = field t "stencilLoadOp" LoadOp.t
  let stencil_store_op = field t "stencilStoreOp" StoreOp.t
  let stencil_clear_value = field t "stencilClearValue" uint32_t
  let stencil_read_only = field t "stencilReadOnly" uint32_t
  let () = seal t
end

module RenderPassDescriptor = struct
  type t

  let t : t structure typ = structure "WGPURenderPassDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let color_attachments_count = field t "colorAttachmentsCount" size_t
  let color_attachments = field t "colorAttachments" (ptr (ptr void))
  let depth_stencil_attachment = field t "depthStencilAttachment" (ptr (ptr void))
  let occlusion_query_set = field t "occlusionQuerySet" QuerySet.t
  let timestamp_writes = field t "timestampWrites" (ptr (ptr void))
  let () = seal t
end

module RenderPassMaxDrawCount = struct
  type t

  let t : t structure typ = structure "WGPURenderPassMaxDrawCount"
  let chain = field t "chain" Chained_struct.t
  let max_draw_count = field t "maxDrawCount" uint64_t
  let () = seal t
end

module RenderPassTimestampWrites = struct
  type t

  let t : t structure typ = structure "WGPURenderPassTimestampWrites"
  let query_set = field t "querySet" QuerySet.t
  let beginning_of_pass_write_index = field t "beginningOfPassWriteIndex" uint32_t
  let end_of_pass_write_index = field t "endOfPassWriteIndex" uint32_t
  let () = seal t
end

module VertexState = struct
  type t

  let t : t structure typ = structure "WGPUVertexState"
  let next_in_chain = field t "nextInChain" (ptr void)
  let module_ = field t "module" ShaderModule.t
  let entry_point = field t "entryPoint" String_view.t
  let constants_count = field t "constantsCount" size_t
  let constants = field t "constants" (ptr (ptr void))
  let buffers_count = field t "buffersCount" size_t
  let buffers = field t "buffers" (ptr (ptr void))
  let () = seal t
end

module RenderPipelineDescriptor = struct
  type t

  let t : t structure typ = structure "WGPURenderPipelineDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let layout = field t "layout" PipelineLayout.t
  let vertex = field t "vertex" VertexState.t
  let primitive = field t "primitive" PrimitiveState.t
  let depth_stencil = field t "depthStencil" (ptr (ptr void))
  let multisample = field t "multisample" MultisampleState.t
  let fragment = field t "fragment" (ptr (ptr void))
  let () = seal t
end

module RequestAdapterOptions = struct
  type t

  let t : t structure typ = structure "WGPURequestAdapterOptions"
  let next_in_chain = field t "nextInChain" (ptr void)
  let feature_level = field t "featureLevel" FeatureLevel.t
  let power_preference = field t "powerPreference" PowerPreference.t
  let force_fallback_adapter = field t "forceFallbackAdapter" uint32_t
  let backend_type = field t "backendType" BackendType.t
  let compatible_surface = field t "compatibleSurface" Surface.t
  let () = seal t
end

module SamplerDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUSamplerDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let address_mode_u = field t "addressModeU" AddressMode.t
  let address_mode_v = field t "addressModeV" AddressMode.t
  let address_mode_w = field t "addressModeW" AddressMode.t
  let mag_filter = field t "magFilter" FilterMode.t
  let min_filter = field t "minFilter" FilterMode.t
  let mipmap_filter = field t "mipmapFilter" MipmapFilterMode.t
  let lod_min_clamp = field t "lodMinClamp" float
  let lod_max_clamp = field t "lodMaxClamp" float
  let compare = field t "compare" CompareFunction.t
  let max_anisotropy = field t "maxAnisotropy" (ptr void) (* unknown: uint16 *)
  let () = seal t
end

module ShaderModuleDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUShaderModuleDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let () = seal t
end

module ShaderSourceSPIRV = struct
  type t

  let t : t structure typ = structure "WGPUShaderSourceSPIRV"
  let chain = field t "chain" Chained_struct.t
  let code_size = field t "codeSize" uint32_t
  let code = field t "code" (ptr uint32_t)
  let () = seal t
end

module ShaderSourceWGSL = struct
  type t

  let t : t structure typ = structure "WGPUShaderSourceWGSL"
  let chain = field t "chain" Chained_struct.t
  let code = field t "code" String_view.t
  let () = seal t
end

module SupportedFeatures = struct
  type t

  let t : t structure typ = structure "WGPUSupportedFeatures"
  let features_count = field t "featuresCount" size_t
  let features = field t "features" (ptr FeatureName.t)
  let () = seal t
end

module SupportedWGSLLanguageFeatures = struct
  type t

  let t : t structure typ = structure "WGPUSupportedWGSLLanguageFeatures"
  let features_count = field t "featuresCount" size_t
  let features = field t "features" (ptr WGSLLanguageFeatureName.t)
  let () = seal t
end

module SurfaceCapabilities = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceCapabilities"
  let next_in_chain = field t "nextInChain" (ptr void)
  let usages = field t "usages" TextureUsage.t
  let formats_count = field t "formatsCount" size_t
  let formats = field t "formats" (ptr TextureFormat.t)
  let present_modes_count = field t "presentModesCount" size_t
  let present_modes = field t "presentModes" (ptr PresentMode.t)
  let alpha_modes_count = field t "alphaModesCount" size_t
  let alpha_modes = field t "alphaModes" (ptr CompositeAlphaMode.t)
  let () = seal t
end

module SurfaceConfiguration = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceConfiguration"
  let next_in_chain = field t "nextInChain" (ptr void)
  let device = field t "device" Device.t
  let format = field t "format" TextureFormat.t
  let usage = field t "usage" TextureUsage.t
  let width = field t "width" uint32_t
  let height = field t "height" uint32_t
  let view_formats_count = field t "viewFormatsCount" size_t
  let view_formats = field t "viewFormats" (ptr TextureFormat.t)
  let alpha_mode = field t "alphaMode" CompositeAlphaMode.t
  let present_mode = field t "presentMode" PresentMode.t
  let () = seal t
end

module SurfaceDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let () = seal t
end

module SurfaceSourceAndroidNativeWindow = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceSourceAndroidNativeWindow"
  let chain = field t "chain" Chained_struct.t
  let window = field t "window" (ptr void)
  let () = seal t
end

module SurfaceSourceMetalLayer = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceSourceMetalLayer"
  let chain = field t "chain" Chained_struct.t
  let layer = field t "layer" (ptr void)
  let () = seal t
end

module SurfaceSourceWaylandSurface = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceSourceWaylandSurface"
  let chain = field t "chain" Chained_struct.t
  let display = field t "display" (ptr void)
  let surface = field t "surface" (ptr void)
  let () = seal t
end

module SurfaceSourceWindowsHWND = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceSourceWindowsHWND"
  let chain = field t "chain" Chained_struct.t
  let hinstance = field t "hinstance" (ptr void)
  let hwnd = field t "hwnd" (ptr void)
  let () = seal t
end

module SurfaceSourceXCBWindow = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceSourceXCBWindow"
  let chain = field t "chain" Chained_struct.t
  let connection = field t "connection" (ptr void)
  let window = field t "window" uint32_t
  let () = seal t
end

module SurfaceSourceXlibWindow = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceSourceXlibWindow"
  let chain = field t "chain" Chained_struct.t
  let display = field t "display" (ptr void)
  let window = field t "window" uint64_t
  let () = seal t
end

module SurfaceTexture = struct
  type t

  let t : t structure typ = structure "WGPUSurfaceTexture"
  let next_in_chain = field t "nextInChain" (ptr void)
  let texture = field t "texture" Texture.t
  let status = field t "status" SurfaceGetCurrentTextureStatus.t
  let () = seal t
end

module TexelCopyBufferLayout = struct
  type t

  let t : t structure typ = structure "WGPUTexelCopyBufferLayout"
  let offset = field t "offset" uint64_t
  let bytes_per_row = field t "bytesPerRow" uint32_t
  let rows_per_image = field t "rowsPerImage" uint32_t
  let () = seal t
end

module TexelCopyBufferInfo = struct
  type t

  let t : t structure typ = structure "WGPUTexelCopyBufferInfo"
  let layout = field t "layout" TexelCopyBufferLayout.t
  let buffer = field t "buffer" Buffer.t
  let () = seal t
end

module TexelCopyTextureInfo = struct
  type t

  let t : t structure typ = structure "WGPUTexelCopyTextureInfo"
  let texture = field t "texture" Texture.t
  let mip_level = field t "mipLevel" uint32_t
  let origin = field t "origin" Origin3D.t
  let aspect = field t "aspect" TextureAspect.t
  let () = seal t
end

module TextureDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUTextureDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let usage = field t "usage" TextureUsage.t
  let dimension = field t "dimension" TextureDimension.t
  let size = field t "size" Extent3D.t
  let format = field t "format" TextureFormat.t
  let mip_level_count = field t "mipLevelCount" uint32_t
  let sample_count = field t "sampleCount" uint32_t
  let view_formats_count = field t "viewFormatsCount" size_t
  let view_formats = field t "viewFormats" (ptr TextureFormat.t)
  let () = seal t
end

module TextureViewDescriptor = struct
  type t

  let t : t structure typ = structure "WGPUTextureViewDescriptor"
  let next_in_chain = field t "nextInChain" (ptr void)
  let label = field t "label" String_view.t
  let format = field t "format" TextureFormat.t
  let dimension = field t "dimension" TextureViewDimension.t
  let base_mip_level = field t "baseMipLevel" uint32_t
  let mip_level_count = field t "mipLevelCount" uint32_t
  let base_array_layer = field t "baseArrayLayer" uint32_t
  let array_layer_count = field t "arrayLayerCount" uint32_t
  let aspect = field t "aspect" TextureAspect.t
  let usage = field t "usage" TextureUsage.t
  let () = seal t
end

module VertexAttribute = struct
  type t

  let t : t structure typ = structure "WGPUVertexAttribute"
  let format = field t "format" VertexFormat.t
  let offset = field t "offset" uint64_t
  let shader_location = field t "shaderLocation" uint32_t
  let () = seal t
end

module VertexBufferLayout = struct
  type t

  let t : t structure typ = structure "WGPUVertexBufferLayout"
  let step_mode = field t "stepMode" VertexStepMode.t
  let array_stride = field t "arrayStride" uint64_t
  let attributes_count = field t "attributesCount" size_t
  let attributes = field t "attributes" (ptr (ptr void))
  let () = seal t
end

(* === Functions === *)

let create_instance =
  foreign "wgpuCreateInstance" (ptr InstanceDescriptor.t @-> returning Instance.t)
;;

let get_instance_capabilities =
  foreign "wgpuGetInstanceCapabilities" (ptr InstanceCapabilities.t @-> returning Status.t)
;;

(* === Object Methods === *)

(* Adapter methods *)
let adapter_get_limits =
  foreign "wgpuAdapterGetLimits" (Adapter.t @-> ptr Limits.t @-> returning Status.t)
;;

let adapter_has_feature =
  foreign "wgpuAdapterHasFeature" (Adapter.t @-> FeatureName.t @-> returning uint32_t)
;;

let adapter_get_features =
  foreign
    "wgpuAdapterGetFeatures"
    (Adapter.t @-> ptr SupportedFeatures.t @-> returning void)
;;

let adapter_get_info =
  foreign "wgpuAdapterGetInfo" (Adapter.t @-> ptr AdapterInfo.t @-> returning Status.t)
;;

let adapter_request_device =
  foreign
    "wgpuAdapterRequestDevice"
    (Adapter.t
     @-> ptr DeviceDescriptor.t
     @-> RequestDeviceCallbackInfo.t
     @-> returning void)
;;

let adapter_release = foreign "wgpuAdapterRelease" (Adapter.t @-> returning void)
let adapter_add_ref = foreign "wgpuAdapterAddRef" (Adapter.t @-> returning void)

(* BindGroup methods *)
let bind_group_set_label =
  foreign "wgpuBindGroupSetLabel" (BindGroup.t @-> String_view.t @-> returning void)
;;

let bind_group_release = foreign "wgpuBindGroupRelease" (BindGroup.t @-> returning void)
let bind_group_add_ref = foreign "wgpuBindGroupAddRef" (BindGroup.t @-> returning void)

(* BindGroupLayout methods *)
let bind_group_layout_set_label =
  foreign
    "wgpuBindGroupLayoutSetLabel"
    (BindGroupLayout.t @-> String_view.t @-> returning void)
;;

let bind_group_layout_release =
  foreign "wgpuBindGroupLayoutRelease" (BindGroupLayout.t @-> returning void)
;;

let bind_group_layout_add_ref =
  foreign "wgpuBindGroupLayoutAddRef" (BindGroupLayout.t @-> returning void)
;;

(* Buffer methods *)
let buffer_map_async =
  foreign
    "wgpuBufferMapAsync"
    (Buffer.t
     @-> MapMode.t
     @-> size_t
     @-> size_t
     @-> BufferMapCallbackInfo.t
     @-> returning void)
;;

let buffer_get_mapped_range =
  foreign
    "wgpuBufferGetMappedRange"
    (Buffer.t @-> size_t @-> size_t @-> returning (ptr void))
;;

let buffer_get_const_mapped_range =
  foreign
    "wgpuBufferGetConstMappedRange"
    (Buffer.t @-> size_t @-> size_t @-> returning (ptr void))
;;

let buffer_set_label =
  foreign "wgpuBufferSetLabel" (Buffer.t @-> String_view.t @-> returning void)
;;

let buffer_get_usage = foreign "wgpuBufferGetUsage" (Buffer.t @-> returning BufferUsage.t)
let buffer_get_size = foreign "wgpuBufferGetSize" (Buffer.t @-> returning uint64_t)

let buffer_get_map_state =
  foreign "wgpuBufferGetMapState" (Buffer.t @-> returning BufferMapState.t)
;;

let buffer_unmap = foreign "wgpuBufferUnmap" (Buffer.t @-> returning void)
let buffer_destroy = foreign "wgpuBufferDestroy" (Buffer.t @-> returning void)
let buffer_release = foreign "wgpuBufferRelease" (Buffer.t @-> returning void)
let buffer_add_ref = foreign "wgpuBufferAddRef" (Buffer.t @-> returning void)

(* CommandBuffer methods *)
let command_buffer_set_label =
  foreign
    "wgpuCommandBufferSetLabel"
    (CommandBuffer.t @-> String_view.t @-> returning void)
;;

let command_buffer_release =
  foreign "wgpuCommandBufferRelease" (CommandBuffer.t @-> returning void)
;;

let command_buffer_add_ref =
  foreign "wgpuCommandBufferAddRef" (CommandBuffer.t @-> returning void)
;;

(* CommandEncoder methods *)
let command_encoder_finish =
  foreign
    "wgpuCommandEncoderFinish"
    (CommandEncoder.t @-> ptr CommandBufferDescriptor.t @-> returning CommandBuffer.t)
;;

let command_encoder_begin_compute_pass =
  foreign
    "wgpuCommandEncoderBeginComputePass"
    (CommandEncoder.t @-> ptr ComputePassDescriptor.t @-> returning ComputePassEncoder.t)
;;

let command_encoder_begin_render_pass =
  foreign
    "wgpuCommandEncoderBeginRenderPass"
    (CommandEncoder.t @-> ptr RenderPassDescriptor.t @-> returning RenderPassEncoder.t)
;;

let command_encoder_copy_buffer_to_buffer =
  foreign
    "wgpuCommandEncoderCopyBufferToBuffer"
    (CommandEncoder.t
     @-> Buffer.t
     @-> uint64_t
     @-> Buffer.t
     @-> uint64_t
     @-> uint64_t
     @-> returning void)
;;

let command_encoder_copy_buffer_to_texture =
  foreign
    "wgpuCommandEncoderCopyBufferToTexture"
    (CommandEncoder.t
     @-> ptr TexelCopyBufferInfo.t
     @-> ptr TexelCopyTextureInfo.t
     @-> ptr Extent3D.t
     @-> returning void)
;;

let command_encoder_copy_texture_to_buffer =
  foreign
    "wgpuCommandEncoderCopyTextureToBuffer"
    (CommandEncoder.t
     @-> ptr TexelCopyTextureInfo.t
     @-> ptr TexelCopyBufferInfo.t
     @-> ptr Extent3D.t
     @-> returning void)
;;

let command_encoder_copy_texture_to_texture =
  foreign
    "wgpuCommandEncoderCopyTextureToTexture"
    (CommandEncoder.t
     @-> ptr TexelCopyTextureInfo.t
     @-> ptr TexelCopyTextureInfo.t
     @-> ptr Extent3D.t
     @-> returning void)
;;

let command_encoder_clear_buffer =
  foreign
    "wgpuCommandEncoderClearBuffer"
    (CommandEncoder.t @-> Buffer.t @-> uint64_t @-> uint64_t @-> returning void)
;;

let command_encoder_insert_debug_marker =
  foreign
    "wgpuCommandEncoderInsertDebugMarker"
    (CommandEncoder.t @-> String_view.t @-> returning void)
;;

let command_encoder_pop_debug_group =
  foreign "wgpuCommandEncoderPopDebugGroup" (CommandEncoder.t @-> returning void)
;;

let command_encoder_push_debug_group =
  foreign
    "wgpuCommandEncoderPushDebugGroup"
    (CommandEncoder.t @-> String_view.t @-> returning void)
;;

let command_encoder_resolve_query_set =
  foreign
    "wgpuCommandEncoderResolveQuerySet"
    (CommandEncoder.t
     @-> QuerySet.t
     @-> uint32_t
     @-> uint32_t
     @-> Buffer.t
     @-> uint64_t
     @-> returning void)
;;

let command_encoder_write_timestamp =
  foreign
    "wgpuCommandEncoderWriteTimestamp"
    (CommandEncoder.t @-> QuerySet.t @-> uint32_t @-> returning void)
;;

let command_encoder_set_label =
  foreign
    "wgpuCommandEncoderSetLabel"
    (CommandEncoder.t @-> String_view.t @-> returning void)
;;

let command_encoder_release =
  foreign "wgpuCommandEncoderRelease" (CommandEncoder.t @-> returning void)
;;

let command_encoder_add_ref =
  foreign "wgpuCommandEncoderAddRef" (CommandEncoder.t @-> returning void)
;;

(* ComputePassEncoder methods *)
let compute_pass_encoder_insert_debug_marker =
  foreign
    "wgpuComputePassEncoderInsertDebugMarker"
    (ComputePassEncoder.t @-> String_view.t @-> returning void)
;;

let compute_pass_encoder_pop_debug_group =
  foreign "wgpuComputePassEncoderPopDebugGroup" (ComputePassEncoder.t @-> returning void)
;;

let compute_pass_encoder_push_debug_group =
  foreign
    "wgpuComputePassEncoderPushDebugGroup"
    (ComputePassEncoder.t @-> String_view.t @-> returning void)
;;

let compute_pass_encoder_set_pipeline =
  foreign
    "wgpuComputePassEncoderSetPipeline"
    (ComputePassEncoder.t @-> ComputePipeline.t @-> returning void)
;;

let compute_pass_encoder_set_bind_group =
  foreign
    "wgpuComputePassEncoderSetBindGroup"
    (ComputePassEncoder.t
     @-> uint32_t
     @-> BindGroup.t
     @-> size_t
     @-> ptr uint32_t
     @-> returning void)
;;

let compute_pass_encoder_dispatch_workgroups =
  foreign
    "wgpuComputePassEncoderDispatchWorkgroups"
    (ComputePassEncoder.t @-> uint32_t @-> uint32_t @-> uint32_t @-> returning void)
;;

let compute_pass_encoder_dispatch_workgroups_indirect =
  foreign
    "wgpuComputePassEncoderDispatchWorkgroupsIndirect"
    (ComputePassEncoder.t @-> Buffer.t @-> uint64_t @-> returning void)
;;

let compute_pass_encoder_end =
  foreign "wgpuComputePassEncoderEnd" (ComputePassEncoder.t @-> returning void)
;;

let compute_pass_encoder_set_label =
  foreign
    "wgpuComputePassEncoderSetLabel"
    (ComputePassEncoder.t @-> String_view.t @-> returning void)
;;

let compute_pass_encoder_release =
  foreign "wgpuComputePassEncoderRelease" (ComputePassEncoder.t @-> returning void)
;;

let compute_pass_encoder_add_ref =
  foreign "wgpuComputePassEncoderAddRef" (ComputePassEncoder.t @-> returning void)
;;

(* ComputePipeline methods *)
let compute_pipeline_get_bind_group_layout =
  foreign
    "wgpuComputePipelineGetBindGroupLayout"
    (ComputePipeline.t @-> uint32_t @-> returning BindGroupLayout.t)
;;

let compute_pipeline_set_label =
  foreign
    "wgpuComputePipelineSetLabel"
    (ComputePipeline.t @-> String_view.t @-> returning void)
;;

let compute_pipeline_release =
  foreign "wgpuComputePipelineRelease" (ComputePipeline.t @-> returning void)
;;

let compute_pipeline_add_ref =
  foreign "wgpuComputePipelineAddRef" (ComputePipeline.t @-> returning void)
;;

(* Device methods *)
let device_create_bind_group =
  foreign
    "wgpuDeviceCreateBindGroup"
    (Device.t @-> ptr BindGroupDescriptor.t @-> returning BindGroup.t)
;;

let device_create_bind_group_layout =
  foreign
    "wgpuDeviceCreateBindGroupLayout"
    (Device.t @-> ptr BindGroupLayoutDescriptor.t @-> returning BindGroupLayout.t)
;;

let device_create_buffer =
  foreign
    "wgpuDeviceCreateBuffer"
    (Device.t @-> ptr BufferDescriptor.t @-> returning Buffer.t)
;;

let device_create_command_encoder =
  foreign
    "wgpuDeviceCreateCommandEncoder"
    (Device.t @-> ptr CommandEncoderDescriptor.t @-> returning CommandEncoder.t)
;;

let device_create_compute_pipeline =
  foreign
    "wgpuDeviceCreateComputePipeline"
    (Device.t @-> ptr ComputePipelineDescriptor.t @-> returning ComputePipeline.t)
;;

let device_create_compute_pipeline_async =
  foreign
    "wgpuDeviceCreateComputePipelineAsync"
    (Device.t
     @-> ptr ComputePipelineDescriptor.t
     @-> CreateComputePipelineAsyncCallbackInfo.t
     @-> returning void)
;;

let device_create_pipeline_layout =
  foreign
    "wgpuDeviceCreatePipelineLayout"
    (Device.t @-> ptr PipelineLayoutDescriptor.t @-> returning PipelineLayout.t)
;;

let device_create_query_set =
  foreign
    "wgpuDeviceCreateQuerySet"
    (Device.t @-> ptr QuerySetDescriptor.t @-> returning QuerySet.t)
;;

let device_create_render_pipeline_async =
  foreign
    "wgpuDeviceCreateRenderPipelineAsync"
    (Device.t
     @-> ptr RenderPipelineDescriptor.t
     @-> CreateRenderPipelineAsyncCallbackInfo.t
     @-> returning void)
;;

let device_create_render_bundle_encoder =
  foreign
    "wgpuDeviceCreateRenderBundleEncoder"
    (Device.t @-> ptr RenderBundleEncoderDescriptor.t @-> returning RenderBundleEncoder.t)
;;

let device_create_render_pipeline =
  foreign
    "wgpuDeviceCreateRenderPipeline"
    (Device.t @-> ptr RenderPipelineDescriptor.t @-> returning RenderPipeline.t)
;;

let device_create_sampler =
  foreign
    "wgpuDeviceCreateSampler"
    (Device.t @-> ptr SamplerDescriptor.t @-> returning Sampler.t)
;;

let device_create_shader_module =
  foreign
    "wgpuDeviceCreateShaderModule"
    (Device.t @-> ptr ShaderModuleDescriptor.t @-> returning ShaderModule.t)
;;

let device_create_texture =
  foreign
    "wgpuDeviceCreateTexture"
    (Device.t @-> ptr TextureDescriptor.t @-> returning Texture.t)
;;

let device_destroy = foreign "wgpuDeviceDestroy" (Device.t @-> returning void)

let device_get_lost_future =
  foreign "wgpuDeviceGetLostFuture" (Device.t @-> returning Future.t)
;;

let device_get_limits =
  foreign "wgpuDeviceGetLimits" (Device.t @-> ptr Limits.t @-> returning Status.t)
;;

let device_has_feature =
  foreign "wgpuDeviceHasFeature" (Device.t @-> FeatureName.t @-> returning uint32_t)
;;

let device_get_features =
  foreign "wgpuDeviceGetFeatures" (Device.t @-> ptr SupportedFeatures.t @-> returning void)
;;

let device_get_adapter_info =
  foreign "wgpuDeviceGetAdapterInfo" (Device.t @-> returning AdapterInfo.t)
;;

let device_get_queue = foreign "wgpuDeviceGetQueue" (Device.t @-> returning Queue.t)

let device_push_error_scope =
  foreign "wgpuDevicePushErrorScope" (Device.t @-> ErrorFilter.t @-> returning void)
;;

let device_pop_error_scope =
  foreign
    "wgpuDevicePopErrorScope"
    (Device.t @-> PopErrorScopeCallbackInfo.t @-> returning void)
;;

let device_set_label =
  foreign "wgpuDeviceSetLabel" (Device.t @-> String_view.t @-> returning void)
;;

let device_release = foreign "wgpuDeviceRelease" (Device.t @-> returning void)
let device_add_ref = foreign "wgpuDeviceAddRef" (Device.t @-> returning void)

(* Instance methods *)
let instance_create_surface =
  foreign
    "wgpuInstanceCreateSurface"
    (Instance.t @-> ptr SurfaceDescriptor.t @-> returning Surface.t)
;;

let instance_get_wgsl_language_features =
  foreign
    "wgpuInstanceGetWGSLLanguageFeatures"
    (Instance.t @-> ptr SupportedWGSLLanguageFeatures.t @-> returning Status.t)
;;

let instance_has_wgsl_language_feature =
  foreign
    "wgpuInstanceHasWGSLLanguageFeature"
    (Instance.t @-> WGSLLanguageFeatureName.t @-> returning uint32_t)
;;

let instance_process_events =
  foreign "wgpuInstanceProcessEvents" (Instance.t @-> returning void)
;;

let instance_request_adapter =
  foreign
    "wgpuInstanceRequestAdapter"
    (Instance.t
     @-> ptr RequestAdapterOptions.t
     @-> RequestAdapterCallbackInfo.t
     @-> returning void)
;;

let instance_wait_any =
  foreign
    "wgpuInstanceWaitAny"
    (Instance.t
     @-> size_t
     @-> ptr FutureWaitInfo.t
     @-> uint64_t
     @-> returning WaitStatus.t)
;;

let instance_release = foreign "wgpuInstanceRelease" (Instance.t @-> returning void)
let instance_add_ref = foreign "wgpuInstanceAddRef" (Instance.t @-> returning void)

(* PipelineLayout methods *)
let pipeline_layout_set_label =
  foreign
    "wgpuPipelineLayoutSetLabel"
    (PipelineLayout.t @-> String_view.t @-> returning void)
;;

let pipeline_layout_release =
  foreign "wgpuPipelineLayoutRelease" (PipelineLayout.t @-> returning void)
;;

let pipeline_layout_add_ref =
  foreign "wgpuPipelineLayoutAddRef" (PipelineLayout.t @-> returning void)
;;

(* QuerySet methods *)
let query_set_set_label =
  foreign "wgpuQuerySetSetLabel" (QuerySet.t @-> String_view.t @-> returning void)
;;

let query_set_get_type =
  foreign "wgpuQuerySetGetType" (QuerySet.t @-> returning QueryType.t)
;;

let query_set_get_count =
  foreign "wgpuQuerySetGetCount" (QuerySet.t @-> returning uint32_t)
;;

let query_set_destroy = foreign "wgpuQuerySetDestroy" (QuerySet.t @-> returning void)
let query_set_release = foreign "wgpuQuerySetRelease" (QuerySet.t @-> returning void)
let query_set_add_ref = foreign "wgpuQuerySetAddRef" (QuerySet.t @-> returning void)

(* Queue methods *)
let queue_submit =
  foreign "wgpuQueueSubmit" (Queue.t @-> size_t @-> ptr CommandBuffer.t @-> returning void)
;;

let queue_on_submitted_work_done =
  foreign
    "wgpuQueueOnSubmittedWorkDone"
    (Queue.t @-> QueueWorkDoneCallbackInfo.t @-> returning void)
;;

let queue_write_buffer =
  foreign
    "wgpuQueueWriteBuffer"
    (Queue.t @-> Buffer.t @-> uint64_t @-> ptr void @-> size_t @-> returning void)
;;

let queue_write_texture =
  foreign
    "wgpuQueueWriteTexture"
    (Queue.t
     @-> ptr TexelCopyTextureInfo.t
     @-> ptr void
     @-> size_t
     @-> ptr TexelCopyBufferLayout.t
     @-> ptr Extent3D.t
     @-> returning void)
;;

let queue_set_label =
  foreign "wgpuQueueSetLabel" (Queue.t @-> String_view.t @-> returning void)
;;

let queue_release = foreign "wgpuQueueRelease" (Queue.t @-> returning void)
let queue_add_ref = foreign "wgpuQueueAddRef" (Queue.t @-> returning void)

(* RenderBundle methods *)
let render_bundle_set_label =
  foreign "wgpuRenderBundleSetLabel" (RenderBundle.t @-> String_view.t @-> returning void)
;;

let render_bundle_release =
  foreign "wgpuRenderBundleRelease" (RenderBundle.t @-> returning void)
;;

let render_bundle_add_ref =
  foreign "wgpuRenderBundleAddRef" (RenderBundle.t @-> returning void)
;;

(* RenderBundleEncoder methods *)
let render_bundle_encoder_set_pipeline =
  foreign
    "wgpuRenderBundleEncoderSetPipeline"
    (RenderBundleEncoder.t @-> RenderPipeline.t @-> returning void)
;;

let render_bundle_encoder_set_bind_group =
  foreign
    "wgpuRenderBundleEncoderSetBindGroup"
    (RenderBundleEncoder.t
     @-> uint32_t
     @-> BindGroup.t
     @-> size_t
     @-> ptr uint32_t
     @-> returning void)
;;

let render_bundle_encoder_draw =
  foreign
    "wgpuRenderBundleEncoderDraw"
    (RenderBundleEncoder.t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> returning void)
;;

let render_bundle_encoder_draw_indexed =
  foreign
    "wgpuRenderBundleEncoderDrawIndexed"
    (RenderBundleEncoder.t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> int32_t
     @-> uint32_t
     @-> returning void)
;;

let render_bundle_encoder_draw_indirect =
  foreign
    "wgpuRenderBundleEncoderDrawIndirect"
    (RenderBundleEncoder.t @-> Buffer.t @-> uint64_t @-> returning void)
;;

let render_bundle_encoder_draw_indexed_indirect =
  foreign
    "wgpuRenderBundleEncoderDrawIndexedIndirect"
    (RenderBundleEncoder.t @-> Buffer.t @-> uint64_t @-> returning void)
;;

let render_bundle_encoder_insert_debug_marker =
  foreign
    "wgpuRenderBundleEncoderInsertDebugMarker"
    (RenderBundleEncoder.t @-> String_view.t @-> returning void)
;;

let render_bundle_encoder_pop_debug_group =
  foreign "wgpuRenderBundleEncoderPopDebugGroup" (RenderBundleEncoder.t @-> returning void)
;;

let render_bundle_encoder_push_debug_group =
  foreign
    "wgpuRenderBundleEncoderPushDebugGroup"
    (RenderBundleEncoder.t @-> String_view.t @-> returning void)
;;

let render_bundle_encoder_set_vertex_buffer =
  foreign
    "wgpuRenderBundleEncoderSetVertexBuffer"
    (RenderBundleEncoder.t
     @-> uint32_t
     @-> Buffer.t
     @-> uint64_t
     @-> uint64_t
     @-> returning void)
;;

let render_bundle_encoder_set_index_buffer =
  foreign
    "wgpuRenderBundleEncoderSetIndexBuffer"
    (RenderBundleEncoder.t
     @-> Buffer.t
     @-> IndexFormat.t
     @-> uint64_t
     @-> uint64_t
     @-> returning void)
;;

let render_bundle_encoder_finish =
  foreign
    "wgpuRenderBundleEncoderFinish"
    (RenderBundleEncoder.t @-> ptr RenderBundleDescriptor.t @-> returning RenderBundle.t)
;;

let render_bundle_encoder_set_label =
  foreign
    "wgpuRenderBundleEncoderSetLabel"
    (RenderBundleEncoder.t @-> String_view.t @-> returning void)
;;

let render_bundle_encoder_release =
  foreign "wgpuRenderBundleEncoderRelease" (RenderBundleEncoder.t @-> returning void)
;;

let render_bundle_encoder_add_ref =
  foreign "wgpuRenderBundleEncoderAddRef" (RenderBundleEncoder.t @-> returning void)
;;

(* RenderPassEncoder methods *)
let render_pass_encoder_set_pipeline =
  foreign
    "wgpuRenderPassEncoderSetPipeline"
    (RenderPassEncoder.t @-> RenderPipeline.t @-> returning void)
;;

let render_pass_encoder_set_bind_group =
  foreign
    "wgpuRenderPassEncoderSetBindGroup"
    (RenderPassEncoder.t
     @-> uint32_t
     @-> BindGroup.t
     @-> size_t
     @-> ptr uint32_t
     @-> returning void)
;;

let render_pass_encoder_draw =
  foreign
    "wgpuRenderPassEncoderDraw"
    (RenderPassEncoder.t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> returning void)
;;

let render_pass_encoder_draw_indexed =
  foreign
    "wgpuRenderPassEncoderDrawIndexed"
    (RenderPassEncoder.t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> int32_t
     @-> uint32_t
     @-> returning void)
;;

let render_pass_encoder_draw_indirect =
  foreign
    "wgpuRenderPassEncoderDrawIndirect"
    (RenderPassEncoder.t @-> Buffer.t @-> uint64_t @-> returning void)
;;

let render_pass_encoder_draw_indexed_indirect =
  foreign
    "wgpuRenderPassEncoderDrawIndexedIndirect"
    (RenderPassEncoder.t @-> Buffer.t @-> uint64_t @-> returning void)
;;

let render_pass_encoder_execute_bundles =
  foreign
    "wgpuRenderPassEncoderExecuteBundles"
    (RenderPassEncoder.t @-> size_t @-> ptr RenderBundle.t @-> returning void)
;;

let render_pass_encoder_insert_debug_marker =
  foreign
    "wgpuRenderPassEncoderInsertDebugMarker"
    (RenderPassEncoder.t @-> String_view.t @-> returning void)
;;

let render_pass_encoder_pop_debug_group =
  foreign "wgpuRenderPassEncoderPopDebugGroup" (RenderPassEncoder.t @-> returning void)
;;

let render_pass_encoder_push_debug_group =
  foreign
    "wgpuRenderPassEncoderPushDebugGroup"
    (RenderPassEncoder.t @-> String_view.t @-> returning void)
;;

let render_pass_encoder_set_stencil_reference =
  foreign
    "wgpuRenderPassEncoderSetStencilReference"
    (RenderPassEncoder.t @-> uint32_t @-> returning void)
;;

let render_pass_encoder_set_blend_constant =
  foreign
    "wgpuRenderPassEncoderSetBlendConstant"
    (RenderPassEncoder.t @-> ptr Color.t @-> returning void)
;;

let render_pass_encoder_set_viewport =
  foreign
    "wgpuRenderPassEncoderSetViewport"
    (RenderPassEncoder.t
     @-> float
     @-> float
     @-> float
     @-> float
     @-> float
     @-> float
     @-> returning void)
;;

let render_pass_encoder_set_scissor_rect =
  foreign
    "wgpuRenderPassEncoderSetScissorRect"
    (RenderPassEncoder.t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> uint32_t
     @-> returning void)
;;

let render_pass_encoder_set_vertex_buffer =
  foreign
    "wgpuRenderPassEncoderSetVertexBuffer"
    (RenderPassEncoder.t
     @-> uint32_t
     @-> Buffer.t
     @-> uint64_t
     @-> uint64_t
     @-> returning void)
;;

let render_pass_encoder_set_index_buffer =
  foreign
    "wgpuRenderPassEncoderSetIndexBuffer"
    (RenderPassEncoder.t
     @-> Buffer.t
     @-> IndexFormat.t
     @-> uint64_t
     @-> uint64_t
     @-> returning void)
;;

let render_pass_encoder_begin_occlusion_query =
  foreign
    "wgpuRenderPassEncoderBeginOcclusionQuery"
    (RenderPassEncoder.t @-> uint32_t @-> returning void)
;;

let render_pass_encoder_end_occlusion_query =
  foreign "wgpuRenderPassEncoderEndOcclusionQuery" (RenderPassEncoder.t @-> returning void)
;;

let render_pass_encoder_end =
  foreign "wgpuRenderPassEncoderEnd" (RenderPassEncoder.t @-> returning void)
;;

let render_pass_encoder_set_label =
  foreign
    "wgpuRenderPassEncoderSetLabel"
    (RenderPassEncoder.t @-> String_view.t @-> returning void)
;;

let render_pass_encoder_release =
  foreign "wgpuRenderPassEncoderRelease" (RenderPassEncoder.t @-> returning void)
;;

let render_pass_encoder_add_ref =
  foreign "wgpuRenderPassEncoderAddRef" (RenderPassEncoder.t @-> returning void)
;;

(* RenderPipeline methods *)
let render_pipeline_get_bind_group_layout =
  foreign
    "wgpuRenderPipelineGetBindGroupLayout"
    (RenderPipeline.t @-> uint32_t @-> returning BindGroupLayout.t)
;;

let render_pipeline_set_label =
  foreign
    "wgpuRenderPipelineSetLabel"
    (RenderPipeline.t @-> String_view.t @-> returning void)
;;

let render_pipeline_release =
  foreign "wgpuRenderPipelineRelease" (RenderPipeline.t @-> returning void)
;;

let render_pipeline_add_ref =
  foreign "wgpuRenderPipelineAddRef" (RenderPipeline.t @-> returning void)
;;

(* Sampler methods *)
let sampler_set_label =
  foreign "wgpuSamplerSetLabel" (Sampler.t @-> String_view.t @-> returning void)
;;

let sampler_release = foreign "wgpuSamplerRelease" (Sampler.t @-> returning void)
let sampler_add_ref = foreign "wgpuSamplerAddRef" (Sampler.t @-> returning void)

(* ShaderModule methods *)
let shader_module_get_compilation_info =
  foreign
    "wgpuShaderModuleGetCompilationInfo"
    (ShaderModule.t @-> CompilationInfoCallbackInfo.t @-> returning void)
;;

let shader_module_set_label =
  foreign "wgpuShaderModuleSetLabel" (ShaderModule.t @-> String_view.t @-> returning void)
;;

let shader_module_release =
  foreign "wgpuShaderModuleRelease" (ShaderModule.t @-> returning void)
;;

let shader_module_add_ref =
  foreign "wgpuShaderModuleAddRef" (ShaderModule.t @-> returning void)
;;

(* Surface methods *)
let surface_configure =
  foreign
    "wgpuSurfaceConfigure"
    (Surface.t @-> ptr SurfaceConfiguration.t @-> returning void)
;;

let surface_get_capabilities =
  foreign
    "wgpuSurfaceGetCapabilities"
    (Surface.t @-> Adapter.t @-> ptr SurfaceCapabilities.t @-> returning Status.t)
;;

let surface_get_current_texture =
  foreign
    "wgpuSurfaceGetCurrentTexture"
    (Surface.t @-> ptr SurfaceTexture.t @-> returning void)
;;

let surface_present = foreign "wgpuSurfacePresent" (Surface.t @-> returning Status.t)
let surface_unconfigure = foreign "wgpuSurfaceUnconfigure" (Surface.t @-> returning void)

let surface_set_label =
  foreign "wgpuSurfaceSetLabel" (Surface.t @-> String_view.t @-> returning void)
;;

let surface_release = foreign "wgpuSurfaceRelease" (Surface.t @-> returning void)
let surface_add_ref = foreign "wgpuSurfaceAddRef" (Surface.t @-> returning void)

(* Texture methods *)
let texture_create_view =
  foreign
    "wgpuTextureCreateView"
    (Texture.t @-> ptr TextureViewDescriptor.t @-> returning TextureView.t)
;;

let texture_set_label =
  foreign "wgpuTextureSetLabel" (Texture.t @-> String_view.t @-> returning void)
;;

let texture_get_width = foreign "wgpuTextureGetWidth" (Texture.t @-> returning uint32_t)
let texture_get_height = foreign "wgpuTextureGetHeight" (Texture.t @-> returning uint32_t)

let texture_get_depth_or_array_layers =
  foreign "wgpuTextureGetDepthOrArrayLayers" (Texture.t @-> returning uint32_t)
;;

let texture_get_mip_level_count =
  foreign "wgpuTextureGetMipLevelCount" (Texture.t @-> returning uint32_t)
;;

let texture_get_sample_count =
  foreign "wgpuTextureGetSampleCount" (Texture.t @-> returning uint32_t)
;;

let texture_get_dimension =
  foreign "wgpuTextureGetDimension" (Texture.t @-> returning TextureDimension.t)
;;

let texture_get_format =
  foreign "wgpuTextureGetFormat" (Texture.t @-> returning TextureFormat.t)
;;

let texture_get_usage =
  foreign "wgpuTextureGetUsage" (Texture.t @-> returning TextureUsage.t)
;;

let texture_destroy = foreign "wgpuTextureDestroy" (Texture.t @-> returning void)
let texture_release = foreign "wgpuTextureRelease" (Texture.t @-> returning void)
let texture_add_ref = foreign "wgpuTextureAddRef" (Texture.t @-> returning void)

(* TextureView methods *)
let texture_view_set_label =
  foreign "wgpuTextureViewSetLabel" (TextureView.t @-> String_view.t @-> returning void)
;;

let texture_view_release =
  foreign "wgpuTextureViewRelease" (TextureView.t @-> returning void)
;;

let texture_view_add_ref =
  foreign "wgpuTextureViewAddRef" (TextureView.t @-> returning void)
;;

(* === Utility Functions === *)

let set_log_callback =
  foreign
    "wgpuSetLogCallback"
    (Foreign.funptr (int @-> String_view.t @-> returning void)
     @-> ptr void
     @-> returning void)
;;

let set_log_level = foreign "wgpuSetLogLevel" (int @-> returning void)

(* === wgpu-native Extensions === *)

let device_poll =
  foreign "wgpuDevicePoll" (Device.t @-> uint32_t @-> ptr void @-> returning uint32_t)
;;
