open! Core

let width = 64
let height = 64
let bytes_per_pixel = 4

(* Align bytes per row to 256 (wgpu requirement) *)
let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256
let buffer_size = bytes_per_row * height

let init () =
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  let texture =
    Wgpu.Device.create_texture
      device
      ~label:"render_target"
      ~size_width:width
      ~size_height:height
      ~size_depth_or_array_layers:1
      ~format:Wgpu.Texture_format.Rgba8_unorm
      ~dimension:N2d
      ~mip_level_count:1
      ~sample_count:1
      ~usage:
        [ Wgpu.Texture_usage.Item.Render_attachment; Wgpu.Texture_usage.Item.Copy_src ]
      ()
  in
  let texture_view = Wgpu.create_texture_view texture ~label:"render_target_view" () in
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  instance, adapter, device, queue, texture, texture_view, readback_buffer
;;

let cleanup
  ~instance
  ~adapter
  ~device
  ~queue
  ~texture
  ~texture_view
  ~readback_buffer
  ~command_buffer
  ~render_pass
  ~encoder
  =
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;

let () =
  let instance, adapter, device, queue, texture, texture_view, readback_buffer =
    init ()
  in
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  (* Begin render pass that clears to red (R=1, G=0, B=0, A=1) *)
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"clear_pass"
      ~color_view:texture_view
      ~clear_color:(1.0, 0.0, 0.0, 1.0)
      ()
  in
  Wgpu.Render_pass_encoder.end_ render_pass;
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture
    ~buffer:readback_buffer
    ~size:(width, height)
    ~bytes_per_row
    ();
  let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
  Wgpu.Queue.submit queue ~commands:[ command_buffer ];
  Wgpu.Device.poll device ~wait:true ();
  (* Map readback buffer and verify *)
  let mapped_data =
    Wgpu.map_buffer
      readback_buffer
      ~mode:[ Wgpu.Map_mode.Item.Read ]
      ~offset:0L
      ~size:(Int64.of_int buffer_size);
    Wgpu.Device.poll device ~wait:true ();
    Wgpu.get_const_mapped_range
      readback_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
  in
  (* Verify all pixels are red (255, 0, 0, 255) *)
  let all_correct = ref true in
  for y = 0 to height - 1 do
    for x = 0 to width - 1 do
      let offset = (y * bytes_per_row) + (x * bytes_per_pixel) in
      let pr = Bigarray.Array1.get mapped_data offset in
      let pg = Bigarray.Array1.get mapped_data (offset + 1) in
      let pb = Bigarray.Array1.get mapped_data (offset + 2) in
      let pa = Bigarray.Array1.get mapped_data (offset + 3) in
      if pr <> 255 || pg <> 0 || pb <> 0 || pa <> 255
      then (
        if !all_correct
        then
          print_s
            [%message
              "ERROR: unexpected pixel"
                (x : int)
                (y : int)
                (pr : int)
                (pg : int)
                (pb : int)
                (pa : int)];
        all_correct := false)
    done
  done;
  let ( (* Write output to PNG *) ) =
    let ppm_file = Test_util.output_path "render_clear.ppm" in
    let png_file = Test_util.output_path "render_clear.png" in
    Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
    Test_util.ppm_to_png ~ppm_file ~png_file;
    ()
  in
  Wgpu.Buffer.unmap readback_buffer;
  cleanup
    ~instance
    ~adapter
    ~device
    ~queue
    ~texture
    ~texture_view
    ~readback_buffer
    ~command_buffer
    ~render_pass
    ~encoder;
  if not !all_correct
  then (
    print_endline "FAILURE: Some pixels incorrect.";
    exit 1)
;;
