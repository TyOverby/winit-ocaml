(* WebGPU Fundamentals: Compute Shaders - Builtins

   This test demonstrates the compute shader builtin values:
   - workgroup_id: The ID of the workgroup (same for all threads in a workgroup)
   - local_invocation_id: The thread ID within the workgroup
   - global_invocation_id: A unique ID for each thread across all workgroups
   - local_invocation_index: Linearized version of local_invocation_id
   - num_workgroups: The dispatch count passed to dispatchWorkgroups

   We dispatch 4x3x2 workgroups, each with 2x3x4 threads, for a total of 24 workgroups *
   24 threads/workgroup = 576 threads.

   Each thread writes its workgroup_id, local_invocation_id, and global_invocation_id to
   storage buffers, which we then read back and print.
*)

open! Core

(* Workgroup dimensions *)
let workgroup_size_x = 2
let workgroup_size_y = 3
let workgroup_size_z = 4
let num_threads_per_workgroup = workgroup_size_x * workgroup_size_y * workgroup_size_z

(* Dispatch dimensions *)
let dispatch_count_x = 4
let dispatch_count_y = 3
let dispatch_count_z = 2
let num_workgroups = dispatch_count_x * dispatch_count_y * dispatch_count_z
let num_results = num_workgroups * num_threads_per_workgroup

(* vec3u is padded to 16 bytes (4 u32s) *)
let vec3_size_bytes = 4 * 4
let buffer_size = num_results * vec3_size_bytes

let shader_code =
  sprintf
    {|
// NOTE!: vec3u is padded to 4 bytes (actually 16 bytes per vec3u in arrays)
@group(0) @binding(0) var<storage, read_write> workgroupResult: array<vec3u>;
@group(0) @binding(1) var<storage, read_write> localResult: array<vec3u>;
@group(0) @binding(2) var<storage, read_write> globalResult: array<vec3u>;

@compute @workgroup_size(%d, %d, %d) fn computeSomething(
    @builtin(workgroup_id) workgroup_id : vec3<u32>,
    @builtin(local_invocation_id) local_invocation_id : vec3<u32>,
    @builtin(global_invocation_id) global_invocation_id : vec3<u32>,
    @builtin(local_invocation_index) local_invocation_index: u32,
    @builtin(num_workgroups) num_workgroups: vec3<u32>
) {
  // workgroup_index is similar to local_invocation_index except for
  // workgroups, not threads inside a workgroup.
  // It is not a builtin so we compute it ourselves.

  let workgroup_index =
     workgroup_id.x +
     workgroup_id.y * num_workgroups.x +
     workgroup_id.z * num_workgroups.x * num_workgroups.y;

  // global_invocation_index is like local_invocation_index
  // except linear across all invocations across all dispatched
  // workgroups. It is not a builtin so we compute it ourselves.

  let global_invocation_index =
     workgroup_index * %du +
     local_invocation_index;

  // now we can write each of these builtins to our buffers.
  workgroupResult[global_invocation_index] = workgroup_id;
  localResult[global_invocation_index] = local_invocation_id;
  globalResult[global_invocation_index] = global_invocation_id;
}
|}
    workgroup_size_x
    workgroup_size_y
    workgroup_size_z
    num_threads_per_workgroup
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  instance, adapter, device, queue
;;

(* Read a vec3u from a mapped buffer at the given result index *)
let read_vec3u ~data ~index =
  (* Each vec3u takes 16 bytes (4 u32s, with padding) *)
  let byte_offset = index * vec3_size_bytes in
  let read_u32 off =
    let b0 = Bigarray.Array1.get data (byte_offset + off) in
    let b1 = Bigarray.Array1.get data (byte_offset + off + 1) in
    let b2 = Bigarray.Array1.get data (byte_offset + off + 2) in
    let b3 = Bigarray.Array1.get data (byte_offset + off + 3) in
    b0 lor (b1 lsl 8) lor (b2 lsl 16) lor (b3 lsl 24)
  in
  let x = read_u32 0 in
  let y = read_u32 4 in
  let z = read_u32 8 in
  x, y, z
;;

let () =
  let instance, adapter, device, queue = init () in
  let shader = Wgpu.Device.create_shader_module device ~wgsl:shader_code () in
  (* Create bind group layout with three read-write storage buffer bindings *)
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout
      device
      ~label:"compute_builtins_bind_group_layout"
      ~entries:
        [ Wgpu.Bind_group_layout_entry.create
            ~binding:0
            ~visibility:[ Wgpu.Shader_stage.Item.Compute ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Storage
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:1
            ~visibility:[ Wgpu.Shader_stage.Item.Compute ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Storage
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ; Wgpu.Bind_group_layout_entry.create
            ~binding:2
            ~visibility:[ Wgpu.Shader_stage.Item.Compute ]
            ~buffer:
              (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
                 ~type_:Wgpu.Buffer_binding_type.Storage
                 ~has_dynamic_offset:false
                 ~min_binding_size:0L
                 ())
            ()
        ]
      ()
  in
  (* Create pipeline layout *)
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"compute_builtins_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  (* Create compute pipeline *)
  let compute_pipeline =
    Wgpu.Device.create_compute_pipeline
      device
      ~label:"compute_builtins_pipeline"
      ~layout:pipeline_layout
      ~compute_module:shader
      ~compute_entry_point:"computeSomething"
      ()
  in
  (* Create storage buffers *)
  let workgroup_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"workgroup_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_src ]
      ~mapped_at_creation:false
      ()
  in
  let local_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"local_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_src ]
      ~mapped_at_creation:false
      ()
  in
  let global_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"global_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_src ]
      ~mapped_at_creation:false
      ()
  in
  (* Create readback buffers *)
  let workgroup_read_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"workgroup_read_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let local_read_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"local_read_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  let global_read_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"global_read_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Create bind group *)
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"compute_builtins_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ Wgpu.Bind_group_entry.create
            ~binding:0
            ~buffer:workgroup_buffer
            ~offset:0L
            ~size:(Int64.of_int buffer_size)
            ()
        ; Wgpu.Bind_group_entry.create
            ~binding:1
            ~buffer:local_buffer
            ~offset:0L
            ~size:(Int64.of_int buffer_size)
            ()
        ; Wgpu.Bind_group_entry.create
            ~binding:2
            ~buffer:global_buffer
            ~offset:0L
            ~size:(Int64.of_int buffer_size)
            ()
        ]
      ()
  in
  (* Encode and run compute pass *)
  let encoder =
    Wgpu.Device.create_command_encoder device ~label:"compute_builtins_encoder" ()
  in
  let compute_pass =
    Wgpu.Command_encoder.begin_compute_pass encoder ~label:"compute_builtins_pass" ()
  in
  Wgpu.Compute_pass_encoder.set_pipeline compute_pass ~pipeline:compute_pipeline;
  Wgpu.set_bind_group compute_pass ~index:0 ~bind_group;
  Wgpu.Compute_pass_encoder.dispatch_workgroups
    compute_pass
    ~workgroupCountX:dispatch_count_x
    ~workgroupCountY:dispatch_count_y
    ~workgroupCountZ:dispatch_count_z;
  Wgpu.Compute_pass_encoder.end_ compute_pass;
  (* Copy storage buffers to readback buffers *)
  Wgpu.Command_encoder.copy_buffer_to_buffer
    encoder
    ~source:workgroup_buffer
    ~source_offset:0L
    ~destination:workgroup_read_buffer
    ~destination_offset:0L
    ~size:(Int64.of_int buffer_size);
  Wgpu.Command_encoder.copy_buffer_to_buffer
    encoder
    ~source:local_buffer
    ~source_offset:0L
    ~destination:local_read_buffer
    ~destination_offset:0L
    ~size:(Int64.of_int buffer_size);
  Wgpu.Command_encoder.copy_buffer_to_buffer
    encoder
    ~source:global_buffer
    ~source_offset:0L
    ~destination:global_read_buffer
    ~destination_offset:0L
    ~size:(Int64.of_int buffer_size);
  let command_buffer = Wgpu.finish encoder ~label:"compute_builtins_commands" () in
  let ( (* Submit and wait *) ) =
    Wgpu.Queue.submit queue ~commands:[ command_buffer ];
    Wgpu.Device.poll device ~wait:true ()
  in
  (* Map and read back results *)
  let workgroup_data =
    Wgpu.map_buffer
      workgroup_read_buffer
      ~mode:[ Wgpu.Map_mode.Item.Read ]
      ~offset:0L
      ~size:(Int64.of_int buffer_size);
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.get_const_mapped_range
      workgroup_read_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
      ~kind:Bigarray.int8_unsigned
  in
  let local_data =
    Wgpu.map_buffer
      local_read_buffer
      ~mode:[ Wgpu.Map_mode.Item.Read ]
      ~offset:0L
      ~size:(Int64.of_int buffer_size);
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.get_const_mapped_range
      local_read_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
      ~kind:Bigarray.int8_unsigned
  in
  let global_data =
    Wgpu.map_buffer
      global_read_buffer
      ~mode:[ Wgpu.Map_mode.Item.Read ]
      ~offset:0L
      ~size:(Int64.of_int buffer_size);
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.get_const_mapped_range
      global_read_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
      ~kind:Bigarray.int8_unsigned
  in
  (* Verify all results - only print on errors *)
  let all_correct = ref true in
  let error_count = ref 0 in
  for i = 0 to num_results - 1 do
    let workgroup = read_vec3u ~data:workgroup_data ~index:i in
    let local = read_vec3u ~data:local_data ~index:i in
    let global = read_vec3u ~data:global_data ~index:i in
    let wg_x, wg_y, wg_z = workgroup in
    let local_x, local_y, local_z = local in
    let global_x, global_y, global_z = global in
    (* Verify global = workgroup * workgroup_size + local *)
    let expected_global_x = (wg_x * workgroup_size_x) + local_x in
    let expected_global_y = (wg_y * workgroup_size_y) + local_y in
    let expected_global_z = (wg_z * workgroup_size_z) + local_z in
    if global_x <> expected_global_x
       || global_y <> expected_global_y
       || global_z <> expected_global_z
    then (
      (* Only print first few errors to avoid spam *)
      if !error_count < 5
      then
        print_s
          [%message
            "ERROR: global_invocation_id mismatch"
              ~index:(i : int)
              (workgroup : int * int * int)
              (local : int * int * int)
              (global : int * int * int)
              ~expected:
                ((expected_global_x, expected_global_y, expected_global_z)
                 : int * int * int)];
      incr error_count;
      all_correct := false)
  done;
  (* Cleanup *)
  Wgpu.Buffer.unmap workgroup_read_buffer;
  Wgpu.Buffer.unmap local_read_buffer;
  Wgpu.Buffer.unmap global_read_buffer;
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Compute_pass_encoder.release compute_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Buffer.release global_read_buffer;
  Wgpu.Buffer.release local_read_buffer;
  Wgpu.Buffer.release workgroup_read_buffer;
  Wgpu.Buffer.release global_buffer;
  Wgpu.Buffer.release local_buffer;
  Wgpu.Buffer.release workgroup_buffer;
  Wgpu.Compute_pipeline.release compute_pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  if not !all_correct
  then (
    print_endline "FAILURE: Some global_invocation_id values were incorrect.";
    exit 1)
;;
