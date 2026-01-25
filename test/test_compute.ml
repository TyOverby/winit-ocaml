open Ctypes
open Wgpu

(* WGSL shader that doubles each element in the buffer *)
let shader_source =
  {|
@group(0) @binding(0)
var<storage, read_write> data: array<u32>;

@compute @workgroup_size(1)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    data[global_id.x] = data[global_id.x] * 2u;
}
|}
;;

(* Helper to set up callbacks - uses a reference to store result *)
let request_adapter_sync instance =
  let result = ref None in
  let callback _status adapter _msg _userdata1 _userdata2 =
    if not (is_null adapter) then result := Some adapter
  in
  let cb_info = make RequestAdapterCallbackInfo.t in
  setf cb_info RequestAdapterCallbackInfo.next_in_chain null;
  setf cb_info RequestAdapterCallbackInfo.mode Unsigned.UInt32.zero;
  setf
    cb_info
    RequestAdapterCallbackInfo.callback
    (coerce
       (Foreign.funptr
          (uint32_t
           @-> Adapter.t
           @-> String_view.t
           @-> ptr void
           @-> ptr void
           @-> returning void))
       (ptr void)
       callback);
  setf cb_info RequestAdapterCallbackInfo.userdata1 null;
  setf cb_info RequestAdapterCallbackInfo.userdata2 null;
  instance_request_adapter instance (from_voidp RequestAdapterOptions.t null) cb_info;
  match !result with
  | Some a -> a
  | None -> failwith "Failed to get adapter"
;;

let request_device_sync adapter =
  let result = ref None in
  let callback _status device _msg _userdata1 _userdata2 =
    if not (is_null device) then result := Some device
  in
  let cb_info = make RequestDeviceCallbackInfo.t in
  setf cb_info RequestDeviceCallbackInfo.next_in_chain null;
  setf cb_info RequestDeviceCallbackInfo.mode Unsigned.UInt32.zero;
  setf
    cb_info
    RequestDeviceCallbackInfo.callback
    (coerce
       (Foreign.funptr
          (uint32_t
           @-> Device.t
           @-> String_view.t
           @-> ptr void
           @-> ptr void
           @-> returning void))
       (ptr void)
       callback);
  setf cb_info RequestDeviceCallbackInfo.userdata1 null;
  setf cb_info RequestDeviceCallbackInfo.userdata2 null;
  adapter_request_device adapter (from_voidp DeviceDescriptor.t null) cb_info;
  match !result with
  | Some d -> d
  | None -> failwith "Failed to get device"
;;

let () =
  Printf.printf "Setting up logging...\n%!";
  set_log_level 2;
  (* Warn level *)
  Printf.printf "Creating instance...\n%!";
  let instance = create_instance (from_voidp InstanceDescriptor.t null) in
  if is_null instance then failwith "Failed to create instance";
  Printf.printf "Requesting adapter...\n%!";
  let adapter = request_adapter_sync instance in
  Printf.printf "Requesting device...\n%!";
  let device = request_device_sync adapter in
  Printf.printf "Getting queue...\n%!";
  let queue = device_get_queue device in
  (* Input data: [1, 2, 3, 4] *)
  let numbers = [| 1l; 2l; 3l; 4l |] in
  let numbers_size = Array.length numbers * 4 in
  (* Create shader module *)
  Printf.printf "Creating shader module...\n%!";
  let wgsl_source = make ShaderSourceWGSL.t in
  let chain = getf wgsl_source ShaderSourceWGSL.chain in
  setf chain Chained_struct.next null;
  setf chain Chained_struct.s_type SType.shader_source_wgsl;
  setf wgsl_source ShaderSourceWGSL.code (String_view.of_string shader_source);
  let shader_desc = make ShaderModuleDescriptor.t in
  setf shader_desc ShaderModuleDescriptor.next_in_chain (to_voidp (addr wgsl_source));
  setf shader_desc ShaderModuleDescriptor.label (String_view.of_string "shader");
  let shader_module = device_create_shader_module device (addr shader_desc) in
  if is_null shader_module then failwith "Failed to create shader module";
  (* Create staging buffer *)
  Printf.printf "Creating staging buffer...\n%!";
  let staging_desc = make BufferDescriptor.t in
  setf staging_desc BufferDescriptor.next_in_chain null;
  setf staging_desc BufferDescriptor.label (String_view.of_string "staging_buffer");
  setf staging_desc BufferDescriptor.usage BufferUsage.(map_read + copy_dst);
  setf staging_desc BufferDescriptor.size (Unsigned.UInt64.of_int numbers_size);
  setf staging_desc BufferDescriptor.mapped_at_creation Unsigned.UInt32.zero;
  let staging_buffer = device_create_buffer device (addr staging_desc) in
  (* Create storage buffer *)
  Printf.printf "Creating storage buffer...\n%!";
  let storage_desc = make BufferDescriptor.t in
  setf storage_desc BufferDescriptor.next_in_chain null;
  setf storage_desc BufferDescriptor.label (String_view.of_string "storage_buffer");
  setf storage_desc BufferDescriptor.usage BufferUsage.(storage + copy_dst + copy_src);
  setf storage_desc BufferDescriptor.size (Unsigned.UInt64.of_int numbers_size);
  setf storage_desc BufferDescriptor.mapped_at_creation Unsigned.UInt32.zero;
  let storage_buffer = device_create_buffer device (addr storage_desc) in
  (* Create compute pipeline *)
  Printf.printf "Creating compute pipeline...\n%!";
  let compute_stage = make ProgrammableStageDescriptor.t in
  setf compute_stage ProgrammableStageDescriptor.next_in_chain null;
  setf compute_stage ProgrammableStageDescriptor.module_ shader_module;
  setf
    compute_stage
    ProgrammableStageDescriptor.entry_point
    (String_view.of_string "main");
  setf compute_stage ProgrammableStageDescriptor.constants_count Unsigned.Size_t.zero;
  setf compute_stage ProgrammableStageDescriptor.constants (from_voidp (ptr void) null);
  let pipeline_desc = make ComputePipelineDescriptor.t in
  setf pipeline_desc ComputePipelineDescriptor.next_in_chain null;
  setf
    pipeline_desc
    ComputePipelineDescriptor.label
    (String_view.of_string "compute_pipeline");
  setf pipeline_desc ComputePipelineDescriptor.layout null;
  setf pipeline_desc ComputePipelineDescriptor.compute compute_stage;
  let compute_pipeline = device_create_compute_pipeline device (addr pipeline_desc) in
  (* Get bind group layout *)
  Printf.printf "Getting bind group layout...\n%!";
  let bind_group_layout =
    compute_pipeline_get_bind_group_layout compute_pipeline Unsigned.UInt32.zero
  in
  (* Create bind group *)
  Printf.printf "Creating bind group...\n%!";
  let entry = make BindGroupEntry.t in
  setf entry BindGroupEntry.next_in_chain null;
  setf entry BindGroupEntry.binding Unsigned.UInt32.zero;
  setf entry BindGroupEntry.buffer storage_buffer;
  setf entry BindGroupEntry.offset Unsigned.UInt64.zero;
  setf entry BindGroupEntry.size (Unsigned.UInt64.of_int numbers_size);
  setf entry BindGroupEntry.sampler null;
  setf entry BindGroupEntry.texture_view null;
  let bind_group_desc = make BindGroupDescriptor.t in
  setf bind_group_desc BindGroupDescriptor.next_in_chain null;
  setf bind_group_desc BindGroupDescriptor.label (String_view.of_string "bind_group");
  setf bind_group_desc BindGroupDescriptor.layout bind_group_layout;
  setf bind_group_desc BindGroupDescriptor.entries_count (Unsigned.Size_t.of_int 1);
  setf
    bind_group_desc
    BindGroupDescriptor.entries
    (coerce (ptr BindGroupEntry.t) (ptr (ptr void)) (addr entry));
  let bind_group = device_create_bind_group device (addr bind_group_desc) in
  (* Create command encoder *)
  Printf.printf "Creating command encoder...\n%!";
  let encoder_desc = make CommandEncoderDescriptor.t in
  setf encoder_desc CommandEncoderDescriptor.next_in_chain null;
  setf
    encoder_desc
    CommandEncoderDescriptor.label
    (String_view.of_string "command_encoder");
  let command_encoder = device_create_command_encoder device (addr encoder_desc) in
  (* Begin compute pass *)
  Printf.printf "Beginning compute pass...\n%!";
  let pass_desc = make ComputePassDescriptor.t in
  setf pass_desc ComputePassDescriptor.next_in_chain null;
  setf pass_desc ComputePassDescriptor.label (String_view.of_string "compute_pass");
  setf pass_desc ComputePassDescriptor.timestamp_writes (from_voidp (ptr void) null);
  let compute_pass =
    command_encoder_begin_compute_pass command_encoder (addr pass_desc)
  in
  compute_pass_encoder_set_pipeline compute_pass compute_pipeline;
  compute_pass_encoder_set_bind_group
    compute_pass
    Unsigned.UInt32.zero
    bind_group
    Unsigned.Size_t.zero
    (from_voidp uint32_t null);
  compute_pass_encoder_dispatch_workgroups
    compute_pass
    (Unsigned.UInt32.of_int (Array.length numbers))
    Unsigned.UInt32.one
    Unsigned.UInt32.one;
  compute_pass_encoder_end compute_pass;
  compute_pass_encoder_release compute_pass;
  (* Copy buffer to buffer *)
  Printf.printf "Copying buffer to buffer...\n%!";
  command_encoder_copy_buffer_to_buffer
    command_encoder
    storage_buffer
    Unsigned.UInt64.zero
    staging_buffer
    Unsigned.UInt64.zero
    (Unsigned.UInt64.of_int numbers_size);
  (* Finish command encoder *)
  Printf.printf "Finishing command encoder...\n%!";
  let cmd_buf_desc = make CommandBufferDescriptor.t in
  setf cmd_buf_desc CommandBufferDescriptor.next_in_chain null;
  setf cmd_buf_desc CommandBufferDescriptor.label (String_view.of_string "command_buffer");
  let command_buffer = command_encoder_finish command_encoder (addr cmd_buf_desc) in
  (* Write initial data to storage buffer *)
  Printf.printf "Writing data to storage buffer...\n%!";
  let numbers_arr = CArray.of_list int32_t (Array.to_list numbers) in
  queue_write_buffer
    queue
    storage_buffer
    Unsigned.UInt64.zero
    (to_voidp (CArray.start numbers_arr))
    (Unsigned.Size_t.of_int numbers_size);
  (* Submit command buffer *)
  Printf.printf "Submitting command buffer...\n%!";
  let cmd_bufs = CArray.of_list (ptr void) [ command_buffer ] in
  queue_submit queue (Unsigned.Size_t.of_int 1) (CArray.start cmd_bufs);
  (* Map staging buffer *)
  Printf.printf "Mapping staging buffer...\n%!";
  let map_done = ref false in
  let map_callback _status _msg _userdata1 _userdata2 = map_done := true in
  let map_cb_info = make BufferMapCallbackInfo.t in
  setf map_cb_info BufferMapCallbackInfo.next_in_chain null;
  setf map_cb_info BufferMapCallbackInfo.mode Unsigned.UInt32.zero;
  setf
    map_cb_info
    BufferMapCallbackInfo.callback
    (coerce
       (Foreign.funptr
          (uint32_t @-> String_view.t @-> ptr void @-> ptr void @-> returning void))
       (ptr void)
       map_callback);
  setf map_cb_info BufferMapCallbackInfo.userdata1 null;
  setf map_cb_info BufferMapCallbackInfo.userdata2 null;
  buffer_map_async
    staging_buffer
    MapMode.read
    Unsigned.Size_t.zero
    (Unsigned.Size_t.of_int numbers_size)
    map_cb_info;
  let _ = device_poll device Unsigned.UInt32.one null in
  (* Read results *)
  Printf.printf "Reading results...\n%!";
  let mapped_ptr =
    buffer_get_mapped_range
      staging_buffer
      Unsigned.Size_t.zero
      (Unsigned.Size_t.of_int numbers_size)
  in
  let result_arr = CArray.from_ptr (from_voidp int32_t mapped_ptr) 4 in
  let results = Array.init 4 (fun i -> CArray.get result_arr i) in
  Printf.printf
    "Results: [%ld, %ld, %ld, %ld]\n%!"
    results.(0)
    results.(1)
    results.(2)
    results.(3);
  (* Check expected values *)
  let expected = [| 2l; 4l; 6l; 8l |] in
  let success = results = expected in
  Printf.printf "Test %s!\n%!" (if success then "PASSED" else "FAILED");
  (* Cleanup *)
  Printf.printf "Cleaning up...\n%!";
  buffer_unmap staging_buffer;
  command_buffer_release command_buffer;
  command_encoder_release command_encoder;
  bind_group_release bind_group;
  bind_group_layout_release bind_group_layout;
  compute_pipeline_release compute_pipeline;
  buffer_release storage_buffer;
  buffer_release staging_buffer;
  shader_module_release shader_module;
  queue_release queue;
  device_release device;
  adapter_release adapter;
  instance_release instance;
  Printf.printf "Done!\n%!";
  if not success then exit 1
;;
