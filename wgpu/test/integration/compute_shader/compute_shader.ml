open! Core

let num_elements = 64
let data_size = num_elements * 4

let shader_code =
  {|
@group(0) @binding(0) var<storage, read_write> data: array<u32>;

@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) global_id: vec3<u32>) {
    let index = global_id.x;
    if (index < arrayLength(&data)) {
        data[index] = data[index] * 2u;
    }
}
|}
;;

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~size:(Int64.of_int data_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  instance, adapter, device, queue, readback_buffer
;;

let cleanup
  ~instance
  ~adapter
  ~device
  ~queue
  ~readback_buffer
  ~storage_buffer
  ~shader
  ~bind_group_layout
  ~bind_group
  ~pipeline_layout
  ~compute_pipeline
  ~encoder
  ~compute_pass
  ~command_buffer
  =
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Compute_pass_encoder.release compute_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Compute_pipeline.release compute_pipeline;
  Wgpu.Pipeline_layout.release pipeline_layout;
  Wgpu.Bind_group.release bind_group;
  Wgpu.Bind_group_layout.release bind_group_layout;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Buffer.release storage_buffer;
  Wgpu.Shader_module.release shader;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;

let () =
  let instance, adapter, device, queue, readback_buffer = init () in
  let shader = Wgpu.Device.create_shader_module device ~wgsl:shader_code () in
  let storage_buffer =
    Wgpu.Device.create_buffer
      device
      ~size:(Int64.of_int data_size)
      ~usage:
        [ Wgpu.Buffer_usage.Item.Storage
        ; Wgpu.Buffer_usage.Item.Copy_dst
        ; Wgpu.Buffer_usage.Item.Copy_src
        ]
      ~mapped_at_creation:false
      ()
  in
  (* Write initial data [0, 1, 2, ..., 63] to storage buffer *)
  let input_bytes =
    Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout data_size
  in
  for i = 0 to num_elements - 1 do
    let offset = i * 4 in
    Bigarray.Array1.set input_bytes offset (i land 0xFF);
    Bigarray.Array1.set input_bytes (offset + 1) ((i lsr 8) land 0xFF);
    Bigarray.Array1.set input_bytes (offset + 2) ((i lsr 16) land 0xFF);
    Bigarray.Array1.set input_bytes (offset + 3) ((i lsr 24) land 0xFF)
  done;
  Wgpu.Queue.write_buffer queue ~buffer:storage_buffer ~offset:0L ~data:input_bytes;
  let bind_group_layout =
    Wgpu.Device.create_bind_group_layout_for_storage_buffer
      device
      ~label:"compute_bind_group_layout"
      ~binding:0
      ~read_only:false
      ()
  in
  let bind_group =
    Wgpu.Device.create_bind_group
      device
      ~label:"compute_bind_group"
      ~layout:bind_group_layout
      ~entries:
        [ { Wgpu.Bind_group_entry.binding = 0
          ; buffer = Some storage_buffer
          ; offset = 0L
          ; size = Int64.of_int data_size
          ; sampler = None
          ; texture_view = None
          }
        ]
      ()
  in
  let pipeline_layout =
    Wgpu.Device.create_pipeline_layout
      device
      ~label:"compute_pipeline_layout"
      ~bind_group_layouts:[ bind_group_layout ]
      ()
  in
  let compute_pipeline =
    Wgpu.Device.create_compute_pipeline
      device
      ~label:"double_pipeline"
      ~layout:pipeline_layout
      ~compute_module:shader
      ~compute_entry_point:"main"
      ()
  in
  let encoder = Wgpu.Device.create_command_encoder device ~label:"compute_encoder" () in
  let compute_pass =
    Wgpu.Command_encoder.begin_compute_pass_simple encoder ~label:"compute_pass" ()
  in
  Wgpu.Compute_pass_encoder.set_pipeline compute_pass ~pipeline:compute_pipeline;
  Wgpu.set_bind_group compute_pass ~index:0 ~bind_group;
  Wgpu.Compute_pass_encoder.dispatch_workgroups
    compute_pass
    ~workgroupCountX:1
    ~workgroupCountY:1
    ~workgroupCountZ:1;
  Wgpu.Compute_pass_encoder.end_ compute_pass;
  Wgpu.Command_encoder.copy_buffer_to_buffer
    encoder
    ~source:storage_buffer
    ~source_offset:0L
    ~destination:readback_buffer
    ~destination_offset:0L
    ~size:(Int64.of_int data_size);
  let command_buffer = Wgpu.finish encoder ~label:"compute_commands" () in
  let ( (* submit and wait for completion *) ) =
    Wgpu.Queue.submit queue ~commands:[ command_buffer ];
    Wgpu.Device.poll device ~wait:true ()
  in
  let mapped_data =
    Wgpu.map_buffer
      readback_buffer
      ~mode:[ Wgpu.Map_mode.Item.Read ]
      ~offset:0L
      ~size:(Int64.of_int data_size);
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.get_const_mapped_range
      readback_buffer
      ~offset:0L
      ~size:(Int64.of_int data_size)
      ~kind:Bigarray.int8_unsigned
  in
  (* Verify: each value should be doubled *)
  let all_correct = ref true in
  for i = 0 to num_elements - 1 do
    let offset = i * 4 in
    let b0 = Bigarray.Array1.get mapped_data offset in
    let b1 = Bigarray.Array1.get mapped_data (offset + 1) in
    let b2 = Bigarray.Array1.get mapped_data (offset + 2) in
    let b3 = Bigarray.Array1.get mapped_data (offset + 3) in
    let value = b0 lor (b1 lsl 8) lor (b2 lsl 16) lor (b3 lsl 24) in
    let expected = i * 2 in
    if value <> expected
    then (
      print_s
        [%message
          "ERROR" ~index:(i : int) ~value:(value : int) ~expected:(expected : int)];
      all_correct := false)
  done;
  Wgpu.Buffer.unmap readback_buffer;
  cleanup
    ~instance
    ~adapter
    ~device
    ~queue
    ~readback_buffer
    ~storage_buffer
    ~shader
    ~bind_group_layout
    ~bind_group
    ~pipeline_layout
    ~compute_pipeline
    ~encoder
    ~compute_pass
    ~command_buffer;
  if not !all_correct
  then (
    print_endline "FAILURE: Some values incorrect.";
    exit 1)
;;
