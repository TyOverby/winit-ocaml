open! Core

(** Regression tests using the real webgpu.yml file.

    These tests load the actual WebGPU API specification and generate code for specific
    items, capturing the output as expect test snapshots. This helps detect regressions
    when codegen changes affect real API types. *)

(** Find the webgpu.yml file relative to the test directory. Tests can run from various
    directories depending on the build system. *)
let find_yml_path () : string =
  let candidates =
    [ "webgpu.yml"
    ; "vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ]
  in
  match List.find candidates ~f:Stdlib.Sys.file_exists with
  | Some path -> path
  | None -> failwith "Could not find webgpu.yml"
;;

let webgpu_yml_path = find_yml_path ()

(** Lazily loaded API from the real webgpu.yml *)
let api = lazy (Parse_yml.load_file webgpu_yml_path)

(** {2 Lookup Functions} *)

let lookup_enum name =
  let api = Lazy.force api in
  match List.find api.enums ~f:(fun e -> String.equal e.name name) with
  | Some e -> e
  | None -> failwithf "Enum not found: %s" name ()
;;

let lookup_bitflag name =
  let api = Lazy.force api in
  match List.find api.bitflags ~f:(fun b -> String.equal b.name name) with
  | Some b -> b
  | None -> failwithf "Bitflag not found: %s" name ()
;;

let lookup_struct name =
  let api = Lazy.force api in
  match List.find api.structs ~f:(fun s -> String.equal s.name name) with
  | Some s -> s
  | None -> failwithf "Struct not found: %s" name ()
;;

let lookup_object name =
  let api = Lazy.force api in
  match List.find api.objects ~f:(fun o -> String.equal o.name name) with
  | Some o -> o
  | None -> failwithf "Object not found: %s" name ()
;;

let lookup_method obj method_name =
  match List.find obj.Ir.methods ~f:(fun m -> String.equal m.name method_name) with
  | Some m -> m
  | None -> failwithf "Method not found: %s.%s" obj.name method_name ()
;;

let all_structs () = (Lazy.force api).structs

(** {2 Print Helpers} *)

let print_enum_outputs enum =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_enum_constants enum);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_enum enum);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_enum enum);
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_enum enum)
;;

let print_bitflag_outputs bitflag =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_bitflag_constants bitflag);
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_bitflag bitflag);
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_bitflag bitflag)
;;

let print_struct_outputs struct_ =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_)
;;

let print_method_outputs obj method_ =
  let structs = all_structs () in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method structs obj method_
     |> Option.value ~default:"(none)");
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method structs obj method_
     |> Option.value ~default:"(none)")
;;

(** {2 Manual Method Regression Tests}

    Tests for all methods marked as Manual in config.ml. These tests document what the
    codegen would produce for manually-implemented methods, helping us understand when
    codegen improvements might make manual implementation unnecessary. *)

(* Instance methods *)

let%expect_test "manual: instance.release" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "release" in
  print_method_outputs obj method_;
  [%expect.unreachable]
[@@expect.uncaught_exn
  {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)
  (Failure "Method not found: instance.release")
  Raised at Stdlib.failwith in file "stdlib.ml" (inlined), line 39, characters 17-33
  Called from Base__Printf.failwithf.(fun) in file "src/printf.ml", line 7, characters 24-34
  Called from Codegen_test__Test_regression.(fun) in file "codegen/test/test_regression.ml", line 130, characters 16-43
  Called from Ppx_expect_runtime__Test_block.Configured.dump_backtrace in file "runtime/test_block.ml", line 359, characters 10-25
  |}]
;;

let%expect_test "manual: instance.create_surface" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "create_surface" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_instance_create_surface(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUInstance c_self = (WGPUInstance)Nativeint_val(self);
      WGPUSurfaceDescriptor* c_descriptor = (WGPUSurfaceDescriptor*)Nativeint_val(descriptor);
      WGPUSurface result = wgpuInstanceCreateSurface(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val instance_create_surface : instance -> nativeint -> surface
    === Low-level ML ===
    external instance_create_surface : instance -> nativeint -> surface = "caml_wgpu_instance_create_surface"
    === High-level MLI ===
      val create_surface : t -> ?label:string -> unit -> Surface.t

    === High-level ML ===
      let create_surface t ?(label = "") () =
        let desc_descriptor = Wgpu_low.Surface_descriptor.surface_descriptor_create () in
        Wgpu_low.Surface_descriptor.surface_descriptor_set_label desc_descriptor label;
        let result = Wgpu_low.instance_create_surface t.handle desc_descriptor in
        Wgpu_low.Surface_descriptor.surface_descriptor_free desc_descriptor;
        ({ Surface.handle = result } : Surface.t)
    |}]
;;

let%expect_test "manual: instance.process_events" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "process_events" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_instance_process_events(value self) {
      CAMLparam1(self);
      WGPUInstance c_self = (WGPUInstance)Nativeint_val(self);

      wgpuInstanceProcessEvents(c_self);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val instance_process_events : instance -> unit
    === Low-level ML ===
    external instance_process_events : instance -> unit = "caml_wgpu_instance_process_events"
    === High-level MLI ===
      val process_events : t -> unit

    === High-level ML ===
      let process_events t = Wgpu_low.instance_process_events t.handle
    |}]
;;

let%expect_test "manual: instance.request_adapter" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "request_adapter" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method instance.request_adapter */

    === Low-level MLI ===

    === Low-level ML ===
    (* TODO: async method instance_request_adapter *)
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: instance.get_WGSL_language_features" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "get_WGSL_language_features" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_instance_get_wgsl_language_features(value self, value features) {
      CAMLparam2(self, features);
      WGPUInstance c_self = (WGPUInstance)Nativeint_val(self);
      WGPUSupportedWGSLLanguageFeatures* c_features = (WGPUSupportedWGSLLanguageFeatures*)Nativeint_val(features);
      WGPUStatus result = wgpuInstanceGetWGSLLanguageFeatures(c_self, c_features);
      CAMLreturn(Val_int(result));
    }

    === Low-level MLI ===
    val instance_get_WGSL_language_features : instance -> nativeint -> int
    === Low-level ML ===
    external instance_get_WGSL_language_features : instance -> nativeint -> int = "caml_wgpu_instance_get_wgsl_language_features"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: instance.wait_any" =
  let obj = lookup_object "instance" in
  let method_ = lookup_method obj "wait_any" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_instance_wait_any(value self, value future_count, value futures, value timeout_NS) {
      CAMLparam4(self, future_count, futures, timeout_NS);
      WGPUInstance c_self = (WGPUInstance)Nativeint_val(self);
      size_t c_future_count = Int64_val(future_count);
      WGPUFutureWaitInfo* c_futures = (WGPUFutureWaitInfo*)Nativeint_val(futures);
      uint64_t c_timeout_NS = Int64_val(timeout_NS);
      WGPUWaitStatus result = wgpuInstanceWaitAny(c_self, c_future_count, c_futures, c_timeout_NS);
      CAMLreturn(Val_int(result));
    }

    === Low-level MLI ===
    val instance_wait_any : instance -> int64 -> nativeint -> int64 -> int
    === Low-level ML ===
    external instance_wait_any : instance -> int64 -> nativeint -> int64 -> int = "caml_wgpu_instance_wait_any"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

(* Adapter methods *)

let%expect_test "manual: adapter.release" =
  let obj = lookup_object "adapter" in
  let method_ = lookup_method obj "release" in
  print_method_outputs obj method_;
  [%expect.unreachable]
[@@expect.uncaught_exn {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)
  (Failure "Method not found: adapter.release")
  Raised at Stdlib.failwith in file "stdlib.ml" (inlined), line 39, characters 17-33
  Called from Base__Printf.failwithf.(fun) in file "src/printf.ml", line 7, characters 24-34
  Called from Codegen_test__Test_regression.(fun) in file "codegen/test/test_regression.ml", line 283, characters 16-43
  Called from Ppx_expect_runtime__Test_block.Configured.dump_backtrace in file "runtime/test_block.ml", line 359, characters 10-25
  |}]
;;

let%expect_test "manual: adapter.has_feature" =
  let obj = lookup_object "adapter" in
  let method_ = lookup_method obj "has_feature" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_adapter_has_feature(value self, value feature) {
      CAMLparam2(self, feature);
      WGPUAdapter c_self = (WGPUAdapter)Nativeint_val(self);
      WGPUFeatureName c_feature = Int_val(feature);
      bool result = wgpuAdapterHasFeature(c_self, c_feature);
      CAMLreturn(Val_bool(result));
    }

    === Low-level MLI ===
    val adapter_has_feature : adapter -> int -> bool
    === Low-level ML ===
    external adapter_has_feature : adapter -> int -> bool = "caml_wgpu_adapter_has_feature"
    === High-level MLI ===
      val has_feature : t -> feature:Feature_name.t -> bool

    === High-level ML ===
      let has_feature t ~feature = Wgpu_low.adapter_has_feature t.handle (Feature_name.to_int feature)
    |}]
;;

let%expect_test "manual: adapter.get_info" =
  let obj = lookup_object "adapter" in
  let method_ = lookup_method obj "get_info" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_adapter_get_info(value self, value info) {
      CAMLparam2(self, info);
      WGPUAdapter c_self = (WGPUAdapter)Nativeint_val(self);
      WGPUAdapterInfo* c_info = (WGPUAdapterInfo*)Nativeint_val(info);
      WGPUStatus result = wgpuAdapterGetInfo(c_self, c_info);
      CAMLreturn(Val_int(result));
    }

    === Low-level MLI ===
    val adapter_get_info : adapter -> nativeint -> int
    === Low-level ML ===
    external adapter_get_info : adapter -> nativeint -> int = "caml_wgpu_adapter_get_info"
    === High-level MLI ===
      val get_info : t -> adapter_info

    === High-level ML ===
      let get_info t =
        let output = Wgpu_low.Adapter_info.adapter_info_create () in
        let _status = Wgpu_low.adapter_get_info t.handle output in
        let vendor = (Wgpu_low.Adapter_info.adapter_info_get_vendor output) in
        let architecture = (Wgpu_low.Adapter_info.adapter_info_get_architecture output) in
        let device = (Wgpu_low.Adapter_info.adapter_info_get_device output) in
        let description = (Wgpu_low.Adapter_info.adapter_info_get_description output) in
        let backend_type = (Backend_type.of_int (Wgpu_low.Adapter_info.adapter_info_get_backend_type output)) in
        let adapter_type = (Adapter_type.of_int (Wgpu_low.Adapter_info.adapter_info_get_adapter_type output)) in
        let vendor_ID = (Wgpu_low.Adapter_info.adapter_info_get_vendor_ID output) in
        let device_ID = (Wgpu_low.Adapter_info.adapter_info_get_device_ID output) in
        let result = { vendor; architecture; device; description; backend_type; adapter_type; vendor_ID; device_ID } in
        Wgpu_low.Adapter_info.adapter_info_free output;
        result
    |}]
;;

let%expect_test "manual: adapter.request_device" =
  let obj = lookup_object "adapter" in
  let method_ = lookup_method obj "request_device" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method adapter.request_device */

    === Low-level MLI ===

    === Low-level ML ===
    (* TODO: async method adapter_request_device *)
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: adapter.get_features" =
  let obj = lookup_object "adapter" in
  let method_ = lookup_method obj "get_features" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_adapter_get_features(value self, value features) {
      CAMLparam2(self, features);
      WGPUAdapter c_self = (WGPUAdapter)Nativeint_val(self);
      WGPUSupportedFeatures* c_features = (WGPUSupportedFeatures*)Nativeint_val(features);
      wgpuAdapterGetFeatures(c_self, c_features);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val adapter_get_features : adapter -> nativeint -> unit
    === Low-level ML ===
    external adapter_get_features : adapter -> nativeint -> unit = "caml_wgpu_adapter_get_features"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

(* Device methods *)

let%expect_test "manual: device.release" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "release" in
  print_method_outputs obj method_;
  [%expect.unreachable]
[@@expect.uncaught_exn {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)
  (Failure "Method not found: device.release")
  Raised at Stdlib.failwith in file "stdlib.ml" (inlined), line 39, characters 17-33
  Called from Base__Printf.failwithf.(fun) in file "src/printf.ml", line 7, characters 24-34
  Called from Codegen_test__Test_regression.(fun) in file "codegen/test/test_regression.ml", line 415, characters 16-43
  Called from Ppx_expect_runtime__Test_block.Configured.dump_backtrace in file "runtime/test_block.ml", line 359, characters 10-25
  |}]
;;

let%expect_test "manual: device.poll" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "poll" in
  print_method_outputs obj method_;
  [%expect.unreachable]
[@@expect.uncaught_exn {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)
  (Failure "Method not found: device.poll")
  Raised at Stdlib.failwith in file "stdlib.ml" (inlined), line 39, characters 17-33
  Called from Base__Printf.failwithf.(fun) in file "src/printf.ml", line 7, characters 24-34
  Called from Codegen_test__Test_regression.(fun) in file "codegen/test/test_regression.ml", line 432, characters 16-40
  Called from Ppx_expect_runtime__Test_block.Configured.dump_backtrace in file "runtime/test_block.ml", line 359, characters 10-25
  |}]
;;

let%expect_test "manual: device.get_features" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "get_features" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_get_features(value self, value features) {
      CAMLparam2(self, features);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUSupportedFeatures* c_features = (WGPUSupportedFeatures*)Nativeint_val(features);
      wgpuDeviceGetFeatures(c_self, c_features);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val device_get_features : device -> nativeint -> unit
    === Low-level ML ===
    external device_get_features : device -> nativeint -> unit = "caml_wgpu_device_get_features"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: device.create_shader_module" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_shader_module" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_shader_module(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUShaderModuleDescriptor* c_descriptor = (WGPUShaderModuleDescriptor*)Nativeint_val(descriptor);
      WGPUShaderModule result = wgpuDeviceCreateShaderModule(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_shader_module : device -> nativeint -> shader_module
    === Low-level ML ===
    external device_create_shader_module : device -> nativeint -> shader_module = "caml_wgpu_device_create_shader_module"
    === High-level MLI ===
      val create_shader_module : t -> ?label:string -> unit -> Shader_module.t

    === High-level ML ===
      let create_shader_module t ?(label = "") () =
        let desc_descriptor = Wgpu_low.Shader_module_descriptor.shader_module_descriptor_create () in
        Wgpu_low.Shader_module_descriptor.shader_module_descriptor_set_label desc_descriptor label;
        let result = Wgpu_low.device_create_shader_module t.handle desc_descriptor in
        Wgpu_low.Shader_module_descriptor.shader_module_descriptor_free desc_descriptor;
        ({ Shader_module.handle = result } : Shader_module.t)
    |}]
;;

let%expect_test "manual: device.create_texture" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_texture" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_texture(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUTextureDescriptor* c_descriptor = (WGPUTextureDescriptor*)Nativeint_val(descriptor);
      WGPUTexture result = wgpuDeviceCreateTexture(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_texture : device -> nativeint -> texture
    === Low-level ML ===
    external device_create_texture : device -> nativeint -> texture = "caml_wgpu_device_create_texture"
    === High-level MLI ===
      val create_texture : t -> ?label:string -> usage:Texture_usage.Item.t list -> dimension:Texture_dimension.t -> size_width:int -> size_height:int -> size_depth_or_array_layers:int -> format:Texture_format.t -> mip_level_count:int -> sample_count:int -> ?view_formats:Texture_format.t list -> unit -> Texture.t

    === High-level ML ===
      let create_texture t ?(label = "") ~usage ~dimension ~size_width ~size_height ~size_depth_or_array_layers ~format ~mip_level_count ~sample_count ?(view_formats = []) () =
        let size_nested = Wgpu_low.Extent_3d.extent_3D_create () in
        let desc_descriptor = Wgpu_low.Texture_descriptor.texture_descriptor_create () in
        Wgpu_low.Texture_descriptor.texture_descriptor_set_label desc_descriptor label;
        Wgpu_low.Texture_descriptor.texture_descriptor_set_usage desc_descriptor (Texture_usage.list_to_int usage);
        Wgpu_low.Texture_descriptor.texture_descriptor_set_dimension desc_descriptor (Texture_dimension.to_int dimension);
        Wgpu_low.Extent_3d.extent_3D_set_width size_nested size_width;
        Wgpu_low.Extent_3d.extent_3D_set_height size_nested size_height;
        Wgpu_low.Extent_3d.extent_3D_set_depth_or_array_layers size_nested size_depth_or_array_layers;
        Wgpu_low.Texture_descriptor.texture_descriptor_set_size desc_descriptor size_nested;
        Wgpu_low.Texture_descriptor.texture_descriptor_set_format desc_descriptor (Texture_format.to_int format);
        Wgpu_low.Texture_descriptor.texture_descriptor_set_mip_level_count desc_descriptor mip_level_count;
        Wgpu_low.Texture_descriptor.texture_descriptor_set_sample_count desc_descriptor sample_count;
        Wgpu_low.Texture_descriptor.texture_descriptor_set_view_formats desc_descriptor (Array.of_list (List.map Texture_format.to_int view_formats));
        let result = Wgpu_low.device_create_texture t.handle desc_descriptor in
        Wgpu_low.Extent_3d.extent_3D_free size_nested;
        Wgpu_low.Texture_descriptor.texture_descriptor_free desc_descriptor;
        ({ Texture.handle = result } : Texture.t)
    |}]
;;

let%expect_test "manual: device.create_compute_pipeline" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_compute_pipeline" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_compute_pipeline(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPUComputePipelineDescriptor* c_descriptor = (WGPUComputePipelineDescriptor*)Nativeint_val(descriptor);
      WGPUComputePipeline result = wgpuDeviceCreateComputePipeline(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_compute_pipeline : device -> nativeint -> compute_pipeline
    === Low-level ML ===
    external device_create_compute_pipeline : device -> nativeint -> compute_pipeline = "caml_wgpu_device_create_compute_pipeline"
    === High-level MLI ===
      val create_compute_pipeline : t -> ?label:string -> ?layout:Pipeline_layout.t -> compute_module:Shader_module.t -> compute_entry_point:string -> ?compute_constants:Constant_entry.t list -> unit -> Compute_pipeline.t

    === High-level ML ===
      let create_compute_pipeline t ?(label = "") ?(layout = "") ~compute_module ~compute_entry_point ?(compute_constants = []) () =
        let compute_nested = Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_create () in
        let desc_descriptor = Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_create () in
        Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_label desc_descriptor label;
        Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_layout desc_descriptor layout.Pipeline_layout.handle;
        Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_module compute_nested compute_module.Shader_module.handle;
        Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_entry_point compute_nested compute_entry_point;
        let compute_constants_structs = List.map (fun (entry : Constant_entry.t) ->
            let e = Wgpu_low.Constant_entry.constant_entry_create () in
            Wgpu_low.Constant_entry.constant_entry_set_key e entry.key;
            Wgpu_low.Constant_entry.constant_entry_set_value e entry.value;
            e) compute_constants in
        let compute_constants_array = Array.of_list compute_constants_structs in
        Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_set_constants compute_nested compute_constants_array;
        Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_set_compute desc_descriptor compute_nested;
        let result = Wgpu_low.device_create_compute_pipeline t.handle desc_descriptor in
        List.iter (fun e -> Wgpu_low.Constant_entry.constant_entry_free e) compute_constants_structs;
        Wgpu_low.Programmable_stage_descriptor.programmable_stage_descriptor_free compute_nested;
        Wgpu_low.Compute_pipeline_descriptor.compute_pipeline_descriptor_free desc_descriptor;
        ({ Compute_pipeline.handle = result } : Compute_pipeline.t)
    |}]
;;

let%expect_test "manual: device.create_render_pipeline" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_render_pipeline" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_create_render_pipeline(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);
      WGPURenderPipelineDescriptor* c_descriptor = (WGPURenderPipelineDescriptor*)Nativeint_val(descriptor);
      WGPURenderPipeline result = wgpuDeviceCreateRenderPipeline(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_create_render_pipeline : device -> nativeint -> render_pipeline
    === Low-level ML ===
    external device_create_render_pipeline : device -> nativeint -> render_pipeline = "caml_wgpu_device_create_render_pipeline"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: device.create_bind_group_layout_for_storage_buffer" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "create_bind_group_layout_for_storage_buffer" in
  print_method_outputs obj method_;
  [%expect.unreachable]
[@@expect.uncaught_exn {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)
  (Failure
    "Method not found: device.create_bind_group_layout_for_storage_buffer")
  Raised at Stdlib.failwith in file "stdlib.ml" (inlined), line 39, characters 17-33
  Called from Base__Printf.failwithf.(fun) in file "src/printf.ml", line 7, characters 24-34
  Called from Codegen_test__Test_regression.(fun) in file "codegen/test/test_regression.ml", line 623, characters 16-79
  Called from Ppx_expect_runtime__Test_block.Configured.dump_backtrace in file "runtime/test_block.ml", line 359, characters 10-25
  |}]
;;

let%expect_test "manual: device.pop_error_scope" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "pop_error_scope" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method device.pop_error_scope */

    === Low-level MLI ===

    === Low-level ML ===
    (* TODO: async method device_pop_error_scope *)
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: device.get_queue" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "get_queue" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_get_queue(value self) {
      CAMLparam1(self);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);

      WGPUQueue result = wgpuDeviceGetQueue(c_self);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val device_get_queue : device -> queue
    === Low-level ML ===
    external device_get_queue : device -> queue = "caml_wgpu_device_get_queue"
    === High-level MLI ===
      val get_queue : t -> Queue.t

    === High-level ML ===
      let get_queue t = ({ Queue.handle = Wgpu_low.device_get_queue t.handle } : Queue.t)
    |}]
;;

let%expect_test "manual: device.get_lost_future" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "get_lost_future" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_get_lost_future(value self) {
      CAMLparam1(self);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);

      /* TODO: return type */
      wgpuDeviceGetLostFuture(c_self);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val device_get_lost_future : device -> nativeint
    === Low-level ML ===
    external device_get_lost_future : device -> nativeint = "caml_wgpu_device_get_lost_future"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: device.get_adapter_info" =
  let obj = lookup_object "device" in
  let method_ = lookup_method obj "get_adapter_info" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_device_get_adapter_info(value self) {
      CAMLparam1(self);
      WGPUDevice c_self = (WGPUDevice)Nativeint_val(self);

      /* TODO: return type */
      wgpuDeviceGetAdapterInfo(c_self);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val device_get_adapter_info : device -> nativeint
    === Low-level ML ===
    external device_get_adapter_info : device -> nativeint = "caml_wgpu_device_get_adapter_info"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

(* Queue methods *)

let%expect_test "manual: queue.release" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "release" in
  print_method_outputs obj method_;
  [%expect.unreachable]
[@@expect.uncaught_exn {|
  (* CR expect_test_collector: This test expectation appears to contain a backtrace.
     This is strongly discouraged as backtraces are fragile.
     Please change this test to not include a backtrace. *)
  (Failure "Method not found: queue.release")
  Raised at Stdlib.failwith in file "stdlib.ml" (inlined), line 39, characters 17-33
  Called from Base__Printf.failwithf.(fun) in file "src/printf.ml", line 7, characters 24-34
  Called from Codegen_test__Test_regression.(fun) in file "codegen/test/test_regression.ml", line 744, characters 16-43
  Called from Ppx_expect_runtime__Test_block.Configured.dump_backtrace in file "runtime/test_block.ml", line 359, characters 10-25
  |}]
;;

let%expect_test "manual: queue.set_label" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "set_label" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_queue_set_label(value self, value label) {
      CAMLparam2(self, label);
      WGPUQueue c_self = (WGPUQueue)Nativeint_val(self);
      WGPUStringView c_label = { .data = String_val(label), .length = caml_string_length(label) };
      wgpuQueueSetLabel(c_self, c_label);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val queue_set_label : queue -> string -> unit
    === Low-level ML ===
    external queue_set_label : queue -> string -> unit = "caml_wgpu_queue_set_label"
    === High-level MLI ===
      val set_label : t -> label:string -> unit

    === High-level ML ===
      let set_label t ~label = Wgpu_low.queue_set_label t.handle label
    |}]
;;

let%expect_test "manual: queue.submit" =
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
      val submit : t -> commands:Command_buffer.t list -> unit

    === High-level ML ===
      let submit t ~commands = Wgpu_low.queue_submit t.handle (Array.of_list (List.map (fun x -> x.Command_buffer.handle) commands))
    |}]
;;

let%expect_test "manual: queue.write_buffer" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "write_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_queue_write_buffer(value self, value buffer, value buffer_offset, value data, value size) {
      CAMLparam5(self, buffer, buffer_offset, data, size);
      WGPUQueue c_self = (WGPUQueue)Nativeint_val(self);
      WGPUBuffer c_buffer = (WGPUBuffer)Nativeint_val(buffer);
      uint64_t c_buffer_offset = Int64_val(buffer_offset);
      void* c_data = (void*)Nativeint_val(data);
      size_t c_size = Int64_val(size);
      wgpuQueueWriteBuffer(c_self, c_buffer, c_buffer_offset, c_data, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val queue_write_buffer : queue -> buffer -> int64 -> nativeint -> int64 -> unit
    === Low-level ML ===
    external queue_write_buffer : queue -> buffer -> int64 -> nativeint -> int64 -> unit = "caml_wgpu_queue_write_buffer"
    === High-level MLI ===
      val write_buffer : t -> buffer:Buffer.t -> buffer_offset:int64 -> data:nativeint -> size:int64 -> unit

    === High-level ML ===
      let write_buffer t ~buffer ~buffer_offset ~data ~size = Wgpu_low.queue_write_buffer t.handle buffer.Buffer.handle buffer_offset data size
    |}]
;;

let%expect_test "manual: queue.write_texture" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "write_texture" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_queue_write_texture(value self, value destination, value data, value data_size, value data_layout, value write_size) {
      CAMLparam5(self, destination, data, data_size, data_layout);
      CAMLxparam1(write_size);
      WGPUQueue c_self = (WGPUQueue)Nativeint_val(self);
      WGPUTexelCopyTextureInfo* c_destination = (WGPUTexelCopyTextureInfo*)Nativeint_val(destination);
      void* c_data = (void*)Nativeint_val(data);
      size_t c_data_size = Int64_val(data_size);
      WGPUTexelCopyBufferLayout* c_data_layout = (WGPUTexelCopyBufferLayout*)Nativeint_val(data_layout);
      WGPUExtent3D* c_write_size = (WGPUExtent3D*)Nativeint_val(write_size);
      wgpuQueueWriteTexture(c_self, c_destination, c_data, c_data_size, c_data_layout, c_write_size);
      CAMLreturn(Val_unit);
    }
    CAMLprim value caml_wgpu_queue_write_texture_bytecode(value *argv, int argn) {
      (void)argn;
      return caml_wgpu_queue_write_texture(argv[0], argv[1], argv[2], argv[3], argv[4], argv[5]);
    }

    === Low-level MLI ===
    val queue_write_texture : queue -> nativeint -> nativeint -> int64 -> nativeint -> nativeint -> unit
    === Low-level ML ===
    external queue_write_texture : queue -> nativeint -> nativeint -> int64 -> nativeint -> nativeint -> unit = "caml_wgpu_queue_write_texture_bytecode" "caml_wgpu_queue_write_texture"
    === High-level MLI ===
      val write_texture : t -> destination_texture:Texture.t -> destination_mip_level:int -> destination_origin_x:int -> destination_origin_y:int -> destination_origin_z:int -> destination_aspect:Texture_aspect.t -> data_layout_offset:int64 -> data_layout_bytes_per_row:int -> data_layout_rows_per_image:int -> write_size_width:int -> write_size_height:int -> write_size_depth_or_array_layers:int -> data:nativeint -> data_size:int64 -> unit -> unit

    === High-level ML ===
      let write_texture t ~destination_texture ~destination_mip_level ~destination_origin_x ~destination_origin_y ~destination_origin_z ~destination_aspect ~data_layout_offset ~data_layout_bytes_per_row ~data_layout_rows_per_image ~write_size_width ~write_size_height ~write_size_depth_or_array_layers ~data ~data_size () =
        let destination_origin_nested = Wgpu_low.Origin_3d.origin_3D_create () in
        let desc_destination = Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_create () in
        let desc_data_layout = Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_create () in
        let desc_write_size = Wgpu_low.Extent_3d.extent_3D_create () in
        Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_texture desc_destination destination_texture.Texture.handle;
        Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_mip_level desc_destination destination_mip_level;
        Wgpu_low.Origin_3d.origin_3D_set_x destination_origin_nested destination_origin_x;
        Wgpu_low.Origin_3d.origin_3D_set_y destination_origin_nested destination_origin_y;
        Wgpu_low.Origin_3d.origin_3D_set_z destination_origin_nested destination_origin_z;
        Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_origin desc_destination destination_origin_nested;
        Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_set_aspect desc_destination (Texture_aspect.to_int destination_aspect);
        Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_set_offset desc_data_layout data_layout_offset;
        Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_set_bytes_per_row desc_data_layout data_layout_bytes_per_row;
        Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_set_rows_per_image desc_data_layout data_layout_rows_per_image;
        Wgpu_low.Extent_3d.extent_3D_set_width desc_write_size write_size_width;
        Wgpu_low.Extent_3d.extent_3D_set_height desc_write_size write_size_height;
        Wgpu_low.Extent_3d.extent_3D_set_depth_or_array_layers desc_write_size write_size_depth_or_array_layers;
        Wgpu_low.queue_write_texture t.handle desc_destination data data_size desc_data_layout desc_write_size;
        Wgpu_low.Extent_3d.extent_3D_free desc_write_size;
        Wgpu_low.Texel_copy_buffer_layout.texel_copy_buffer_layout_free desc_data_layout;
        Wgpu_low.Origin_3d.origin_3D_free destination_origin_nested;
        Wgpu_low.Texel_copy_texture_info.texel_copy_texture_info_free desc_destination;
        ()
    |}]
;;

let%expect_test "manual: queue.on_submitted_work_done" =
  let obj = lookup_object "queue" in
  let method_ = lookup_method obj "on_submitted_work_done" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method queue.on_submitted_work_done */

    === Low-level MLI ===

    === Low-level ML ===
    (* TODO: async method queue_on_submitted_work_done *)
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

(* Command encoder methods *)

let%expect_test "manual: command_encoder.begin_compute_pass" =
  let obj = lookup_object "command_encoder" in
  let method_ = lookup_method obj "begin_compute_pass" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_command_encoder_begin_compute_pass(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUCommandEncoder c_self = (WGPUCommandEncoder)Nativeint_val(self);
      WGPUComputePassDescriptor* c_descriptor = (WGPUComputePassDescriptor*)Nativeint_val(descriptor);
      WGPUComputePassEncoder result = wgpuCommandEncoderBeginComputePass(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val command_encoder_begin_compute_pass : command_encoder -> nativeint -> compute_pass_encoder
    === Low-level ML ===
    external command_encoder_begin_compute_pass : command_encoder -> nativeint -> compute_pass_encoder = "caml_wgpu_command_encoder_begin_compute_pass"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: command_encoder.begin_render_pass" =
  let obj = lookup_object "command_encoder" in
  let method_ = lookup_method obj "begin_render_pass" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_command_encoder_begin_render_pass(value self, value descriptor) {
      CAMLparam2(self, descriptor);
      WGPUCommandEncoder c_self = (WGPUCommandEncoder)Nativeint_val(self);
      WGPURenderPassDescriptor* c_descriptor = (WGPURenderPassDescriptor*)Nativeint_val(descriptor);
      WGPURenderPassEncoder result = wgpuCommandEncoderBeginRenderPass(c_self, c_descriptor);
      CAMLreturn(caml_copy_nativeint((intnat)result));
    }

    === Low-level MLI ===
    val command_encoder_begin_render_pass : command_encoder -> nativeint -> render_pass_encoder
    === Low-level ML ===
    external command_encoder_begin_render_pass : command_encoder -> nativeint -> render_pass_encoder = "caml_wgpu_command_encoder_begin_render_pass"
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

(* Render pass encoder methods *)

let%expect_test "manual: render_pass_encoder.set_vertex_buffer" =
  let obj = lookup_object "render_pass_encoder" in
  let method_ = lookup_method obj "set_vertex_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_render_pass_encoder_set_vertex_buffer(value self, value slot, value buffer, value offset, value size) {
      CAMLparam5(self, slot, buffer, offset, size);
      WGPURenderPassEncoder c_self = (WGPURenderPassEncoder)Nativeint_val(self);
      uint32_t c_slot = Int_val(slot);
      WGPUBuffer c_buffer = (WGPUBuffer)Nativeint_val(buffer);
      uint64_t c_offset = Int64_val(offset);
      uint64_t c_size = Int64_val(size);
      wgpuRenderPassEncoderSetVertexBuffer(c_self, c_slot, c_buffer, c_offset, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val render_pass_encoder_set_vertex_buffer : render_pass_encoder -> int -> buffer -> int64 -> int64 -> unit
    === Low-level ML ===
    external render_pass_encoder_set_vertex_buffer : render_pass_encoder -> int -> buffer -> int64 -> int64 -> unit = "caml_wgpu_render_pass_encoder_set_vertex_buffer"
    === High-level MLI ===
      val set_vertex_buffer : t -> slot:int -> buffer:Buffer.t -> offset:int64 -> size:int64 -> unit

    === High-level ML ===
      let set_vertex_buffer t ~slot ~buffer ~offset ~size = Wgpu_low.render_pass_encoder_set_vertex_buffer t.handle slot buffer.Buffer.handle offset size
    |}]
;;

let%expect_test "manual: render_pass_encoder.set_index_buffer" =
  let obj = lookup_object "render_pass_encoder" in
  let method_ = lookup_method obj "set_index_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_render_pass_encoder_set_index_buffer(value self, value buffer, value format, value offset, value size) {
      CAMLparam5(self, buffer, format, offset, size);
      WGPURenderPassEncoder c_self = (WGPURenderPassEncoder)Nativeint_val(self);
      WGPUBuffer c_buffer = (WGPUBuffer)Nativeint_val(buffer);
      WGPUIndexFormat c_format = Int_val(format);
      uint64_t c_offset = Int64_val(offset);
      uint64_t c_size = Int64_val(size);
      wgpuRenderPassEncoderSetIndexBuffer(c_self, c_buffer, c_format, c_offset, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val render_pass_encoder_set_index_buffer : render_pass_encoder -> buffer -> int -> int64 -> int64 -> unit
    === Low-level ML ===
    external render_pass_encoder_set_index_buffer : render_pass_encoder -> buffer -> int -> int64 -> int64 -> unit = "caml_wgpu_render_pass_encoder_set_index_buffer"
    === High-level MLI ===
      val set_index_buffer : t -> buffer:Buffer.t -> format:Index_format.t -> offset:int64 -> size:int64 -> unit

    === High-level ML ===
      let set_index_buffer t ~buffer ~format ~offset ~size = Wgpu_low.render_pass_encoder_set_index_buffer t.handle buffer.Buffer.handle (Index_format.to_int format) offset size
    |}]
;;

(* Render bundle encoder methods *)

let%expect_test "manual: render_bundle_encoder.set_vertex_buffer" =
  let obj = lookup_object "render_bundle_encoder" in
  let method_ = lookup_method obj "set_vertex_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_render_bundle_encoder_set_vertex_buffer(value self, value slot, value buffer, value offset, value size) {
      CAMLparam5(self, slot, buffer, offset, size);
      WGPURenderBundleEncoder c_self = (WGPURenderBundleEncoder)Nativeint_val(self);
      uint32_t c_slot = Int_val(slot);
      WGPUBuffer c_buffer = (WGPUBuffer)Nativeint_val(buffer);
      uint64_t c_offset = Int64_val(offset);
      uint64_t c_size = Int64_val(size);
      wgpuRenderBundleEncoderSetVertexBuffer(c_self, c_slot, c_buffer, c_offset, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val render_bundle_encoder_set_vertex_buffer : render_bundle_encoder -> int -> buffer -> int64 -> int64 -> unit
    === Low-level ML ===
    external render_bundle_encoder_set_vertex_buffer : render_bundle_encoder -> int -> buffer -> int64 -> int64 -> unit = "caml_wgpu_render_bundle_encoder_set_vertex_buffer"
    === High-level MLI ===
      val set_vertex_buffer : t -> slot:int -> buffer:Buffer.t -> offset:int64 -> size:int64 -> unit

    === High-level ML ===
      let set_vertex_buffer t ~slot ~buffer ~offset ~size = Wgpu_low.render_bundle_encoder_set_vertex_buffer t.handle slot buffer.Buffer.handle offset size
    |}]
;;

let%expect_test "manual: render_bundle_encoder.set_index_buffer" =
  let obj = lookup_object "render_bundle_encoder" in
  let method_ = lookup_method obj "set_index_buffer" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_render_bundle_encoder_set_index_buffer(value self, value buffer, value format, value offset, value size) {
      CAMLparam5(self, buffer, format, offset, size);
      WGPURenderBundleEncoder c_self = (WGPURenderBundleEncoder)Nativeint_val(self);
      WGPUBuffer c_buffer = (WGPUBuffer)Nativeint_val(buffer);
      WGPUIndexFormat c_format = Int_val(format);
      uint64_t c_offset = Int64_val(offset);
      uint64_t c_size = Int64_val(size);
      wgpuRenderBundleEncoderSetIndexBuffer(c_self, c_buffer, c_format, c_offset, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val render_bundle_encoder_set_index_buffer : render_bundle_encoder -> buffer -> int -> int64 -> int64 -> unit
    === Low-level ML ===
    external render_bundle_encoder_set_index_buffer : render_bundle_encoder -> buffer -> int -> int64 -> int64 -> unit = "caml_wgpu_render_bundle_encoder_set_index_buffer"
    === High-level MLI ===
      val set_index_buffer : t -> buffer:Buffer.t -> format:Index_format.t -> offset:int64 -> size:int64 -> unit

    === High-level ML ===
      let set_index_buffer t ~buffer ~format ~offset ~size = Wgpu_low.render_bundle_encoder_set_index_buffer t.handle buffer.Buffer.handle (Index_format.to_int format) offset size
    |}]
;;

(* Buffer methods *)

let%expect_test "manual: buffer.map_async" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "map_async" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method buffer.map_async */

    === Low-level MLI ===

    === Low-level ML ===
    (* TODO: async method buffer_map_async *)
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

let%expect_test "manual: buffer.get_mapped_range" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "get_mapped_range" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_get_mapped_range(value self, value offset, value size) {
      CAMLparam3(self, offset, size);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      size_t c_offset = Int64_val(offset);
      size_t c_size = Int64_val(size);
      /* TODO: return type */
      wgpuBufferGetMappedRange(c_self, c_offset, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val buffer_get_mapped_range : buffer -> int64 -> int64 -> nativeint
    === Low-level ML ===
    external buffer_get_mapped_range : buffer -> int64 -> int64 -> nativeint = "caml_wgpu_buffer_get_mapped_range"
    === High-level MLI ===
      val get_mapped_range : t -> offset:int64 -> size:int64 -> nativeint

    === High-level ML ===
      let get_mapped_range t ~offset ~size = Wgpu_low.buffer_get_mapped_range t.handle offset size
    |}]
;;

let%expect_test "manual: buffer.get_const_mapped_range" =
  let obj = lookup_object "buffer" in
  let method_ = lookup_method obj "get_const_mapped_range" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_buffer_get_const_mapped_range(value self, value offset, value size) {
      CAMLparam3(self, offset, size);
      WGPUBuffer c_self = (WGPUBuffer)Nativeint_val(self);
      size_t c_offset = Int64_val(offset);
      size_t c_size = Int64_val(size);
      /* TODO: return type */
      wgpuBufferGetConstMappedRange(c_self, c_offset, c_size);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val buffer_get_const_mapped_range : buffer -> int64 -> int64 -> nativeint
    === Low-level ML ===
    external buffer_get_const_mapped_range : buffer -> int64 -> int64 -> nativeint = "caml_wgpu_buffer_get_const_mapped_range"
    === High-level MLI ===
      val get_const_mapped_range : t -> offset:int64 -> size:int64 -> nativeint

    === High-level ML ===
      let get_const_mapped_range t ~offset ~size = Wgpu_low.buffer_get_const_mapped_range t.handle offset size
    |}]
;;

(* Shader module methods *)

let%expect_test "manual: shader_module.get_compilation_info" =
  let obj = lookup_object "shader_module" in
  let method_ = lookup_method obj "get_compilation_info" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    /* TODO: async method shader_module.get_compilation_info */

    === Low-level MLI ===

    === Low-level ML ===
    (* TODO: async method shader_module_get_compilation_info *)
    === High-level MLI ===
    (none)
    === High-level ML ===
    (none)
    |}]
;;

(* Surface methods *)

let%expect_test "manual: surface.configure" =
  let obj = lookup_object "surface" in
  let method_ = lookup_method obj "configure" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_surface_configure(value self, value config) {
      CAMLparam2(self, config);
      WGPUSurface c_self = (WGPUSurface)Nativeint_val(self);
      WGPUSurfaceConfiguration* c_config = (WGPUSurfaceConfiguration*)Nativeint_val(config);
      wgpuSurfaceConfigure(c_self, c_config);
      CAMLreturn(Val_unit);
    }

    === Low-level MLI ===
    val surface_configure : surface -> nativeint -> unit
    === Low-level ML ===
    external surface_configure : surface -> nativeint -> unit = "caml_wgpu_surface_configure"
    === High-level MLI ===
      val configure : t -> device:Device.t -> format:Texture_format.t -> usage:Texture_usage.Item.t list -> width:int -> height:int -> ?view_formats:Texture_format.t list -> alpha_mode:Composite_alpha_mode.t -> present_mode:Present_mode.t -> unit -> unit

    === High-level ML ===
      let configure t ~device ~format ~usage ~width ~height ?(view_formats = []) ~alpha_mode ~present_mode () =
        let desc_config = Wgpu_low.Surface_configuration.surface_configuration_create () in
        Wgpu_low.Surface_configuration.surface_configuration_set_device desc_config device.Device.handle;
        Wgpu_low.Surface_configuration.surface_configuration_set_format desc_config (Texture_format.to_int format);
        Wgpu_low.Surface_configuration.surface_configuration_set_usage desc_config (Texture_usage.list_to_int usage);
        Wgpu_low.Surface_configuration.surface_configuration_set_width desc_config width;
        Wgpu_low.Surface_configuration.surface_configuration_set_height desc_config height;
        Wgpu_low.Surface_configuration.surface_configuration_set_view_formats desc_config (Array.of_list (List.map Texture_format.to_int view_formats));
        Wgpu_low.Surface_configuration.surface_configuration_set_alpha_mode desc_config (Composite_alpha_mode.to_int alpha_mode);
        Wgpu_low.Surface_configuration.surface_configuration_set_present_mode desc_config (Present_mode.to_int present_mode);
        Wgpu_low.surface_configure t.handle desc_config;
        Wgpu_low.Surface_configuration.surface_configuration_free desc_config;
        ()
    |}]
;;

let%expect_test "manual: surface.get_capabilities" =
  let obj = lookup_object "surface" in
  let method_ = lookup_method obj "get_capabilities" in
  print_method_outputs obj method_;
  [%expect
    {|
    === Low-level C ===
    CAMLprim value caml_wgpu_surface_get_capabilities(value self, value adapter, value capabilities) {
      CAMLparam3(self, adapter, capabilities);
      WGPUSurface c_self = (WGPUSurface)Nativeint_val(self);
      WGPUAdapter c_adapter = (WGPUAdapter)Nativeint_val(adapter);
      WGPUSurfaceCapabilities* c_capabilities = (WGPUSurfaceCapabilities*)Nativeint_val(capabilities);
      WGPUStatus result = wgpuSurfaceGetCapabilities(c_self, c_adapter, c_capabilities);
      CAMLreturn(Val_int(result));
    }

    === Low-level MLI ===
    val surface_get_capabilities : surface -> adapter -> nativeint -> int
    === Low-level ML ===
    external surface_get_capabilities : surface -> adapter -> nativeint -> int = "caml_wgpu_surface_get_capabilities"
    === High-level MLI ===
      val get_capabilities : t -> adapter:Adapter.t -> surface_capabilities

    === High-level ML ===
      let get_capabilities t ~adapter =
        let output = Wgpu_low.Surface_capabilities.surface_capabilities_create () in
        let _status = Wgpu_low.surface_get_capabilities t.handle adapter.Adapter.handle output in
        let usages = (Wgpu_low.Surface_capabilities.surface_capabilities_get_usages output) in
        let formats = (Wgpu_low.Surface_capabilities.surface_capabilities_get_formats output) in
        let present_modes = (Wgpu_low.Surface_capabilities.surface_capabilities_get_present_modes output) in
        let alpha_modes = (Wgpu_low.Surface_capabilities.surface_capabilities_get_alpha_modes output) in
        let result = { usages; formats; present_modes; alpha_modes } in
        Wgpu_low.Surface_capabilities.surface_capabilities_free output;
        result
    |}]
;;
