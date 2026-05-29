open! Core

(* This test demonstrates that bigarray functions work with different element types, not
   just int8_unsigned. We write float32 data to a GPU buffer and read it back, verifying
   the data round-trips correctly. *)

let num_floats = 16
let data_size = num_floats * 4 (* float32 is 4 bytes *)

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  instance, adapter, device, queue
;;

let cleanup ~instance ~adapter ~device ~queue ~gpu_buffer ~readback_buffer =
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Buffer.release gpu_buffer;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;

let () =
  let instance, adapter, device, queue = init () in
  (* Create GPU buffer that can receive writes and be copied from *)
  let gpu_buffer =
    Wgpu.Device.create_buffer
      device
      ~size:(Int64.of_int data_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Copy_src; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Create readback buffer for mapping *)
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~size:(Int64.of_int data_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  (* Create float32 input data: [1.5, 2.5, 3.5, ...] *)
  let input_data = Bigarray.Array1.create Bigarray.float32 Bigarray.c_layout num_floats in
  for i = 0 to num_floats - 1 do
    Bigarray.Array1.set input_data i (Float.of_int i +. 0.5)
  done;
  (* Write float32 data directly to GPU buffer - this demonstrates Queue.write_buffer
     accepting float32 bigarray *)
  Wgpu.Queue.write_buffer queue ~buffer:gpu_buffer ~offset:0L ~data:input_data;
  (* Copy from GPU buffer to readback buffer *)
  let encoder = Wgpu.Device.create_command_encoder device () in
  Wgpu.Command_encoder.copy_buffer_to_buffer
    encoder
    ~source:gpu_buffer
    ~source_offset:0L
    ~destination:readback_buffer
    ~destination_offset:0L
    ~size:(Int64.of_int data_size);
  let command_buffer = Wgpu.Command_encoder.finish encoder () in
  Wgpu.Queue.submit queue ~commands:[ command_buffer ];
  Wgpu.Device.poll device ~wait:true ();
  (* Map and read back as float32 - this demonstrates get_const_mapped_range with
     kind:Bigarray.float32 *)
  let output_data =
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
      ~kind:Bigarray.float32
  in
  (* Verify: each value should match the input *)
  let all_correct = ref true in
  for i = 0 to num_floats - 1 do
    let input_val = Bigarray.Array1.get input_data i in
    let output_val = Bigarray.Array1.get output_data i in
    if Float.( <> ) input_val output_val
    then (
      print_s
        [%message
          "ERROR" ~index:(i : int) ~input:(input_val : float) ~output:(output_val : float)];
      all_correct := false)
  done;
  Wgpu.Buffer.unmap readback_buffer;
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Command_encoder.release encoder;
  cleanup ~instance ~adapter ~device ~queue ~gpu_buffer ~readback_buffer;
  if not !all_correct
  then (
    print_endline "FAILURE: Float32 data round-trip failed.";
    exit 1)
;;
