open! Core

let () =
  print_endline "\n=== Testing Render Pass (Clear to Color) ===";
  (* Create instance, adapter, device using high-level API *)
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  print_endline "Device and queue obtained.";
  (* Create render target texture *)
  let width = 64 in
  let height = 64 in
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
  print_endline "Render target texture created.";
  (* Create texture view *)
  let texture_view = Wgpu.create_texture_view texture ~label:"render_target_view" () in
  print_endline "Texture view created.";
  (* Create readback buffer - 4 bytes per pixel (RGBA8) *)
  let bytes_per_pixel = 4 in
  (* Align bytes per row to 256 (wgpu requirement) *)
  let bytes_per_row = ((width * bytes_per_pixel) + 255) / 256 * 256 in
  let buffer_size = bytes_per_row * height in
  let readback_buffer =
    Wgpu.Device.create_buffer
      device
      ~label:"readback_buffer"
      ~size:(Int64.of_int buffer_size)
      ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
      ~mapped_at_creation:false
      ()
  in
  print_endline "Readback buffer created.";
  (* Create command encoder *)
  let encoder = Wgpu.Device.create_command_encoder device ~label:"render_encoder" () in
  (* Begin render pass that clears to red (R=1, G=0, B=0, A=1) *)
  (* Use Command_encoder.begin_render_pass directly (module method) *)
  let render_pass =
    Wgpu.Command_encoder.begin_render_pass
      encoder
      ~label:"clear_pass"
      ~color_view:texture_view
      ~clear_color:(1.0, 0.0, 0.0, 1.0)
      ()
  in
  print_endline "Render pass started (clearing to red).";
  (* End render pass immediately (just the clear) *)
  Wgpu.Render_pass_encoder.end_ render_pass;
  print_endline "Render pass ended.";
  (* Copy texture to buffer *)
  Wgpu.copy_texture_to_buffer
    encoder
    ~texture
    ~buffer:readback_buffer
    ~size:(width, height)
    ~bytes_per_row
    ();
  print_endline "Copy texture to buffer command recorded.";
  (* Finish and submit *)
  let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
  Wgpu.Queue.submit queue ~commands:[ command_buffer ];
  print_endline "Commands submitted.";
  (* Poll for completion *)
  Wgpu.Device.poll device ~wait:true ();
  print_endline "Device polled.";
  (* Map readback buffer and verify *)
  Wgpu.map_buffer
    readback_buffer
    ~mode:[ Wgpu.Map_mode.Item.Read ]
    ~offset:0L
    ~size:(Int64.of_int buffer_size);
  Wgpu.Device.poll device ~wait:true ();
  let mapped_data =
    Wgpu.get_const_mapped_range
      readback_buffer
      ~offset:0L
      ~size:(Int64.of_int buffer_size)
  in
  print_endline "Buffer mapped for reading.";
  (* Check first pixel: should be red (255, 0, 0, 255) in RGBA8 *)
  let r = Bigarray.Array1.get mapped_data 0 in
  let g = Bigarray.Array1.get mapped_data 1 in
  let b = Bigarray.Array1.get mapped_data 2 in
  let a = Bigarray.Array1.get mapped_data 3 in
  printf "  First pixel: R=%d G=%d B=%d A=%d\n" r g b a;
  (* Verify all pixels are red *)
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
        then printf "  ERROR at (%d,%d): R=%d G=%d B=%d A=%d\n" x y pr pg pb pa;
        all_correct := false)
    done
  done;
  if !all_correct
  then print_endline "SUCCESS: All pixels correctly cleared to red!"
  else print_endline "FAILURE: Some pixels incorrect.";
  (* Write output to PPM and convert to PNG *)
  let ppm_file = Test_util.output_path "render_clear.ppm" in
  let png_file = Test_util.output_path "render_clear.png" in
  Test_util.write_ppm ~filename:ppm_file ~width ~height ~data:mapped_data ~bytes_per_row;
  printf "  Written to %s\n" ppm_file;
  if Test_util.ppm_to_png ~ppm_file ~png_file
  then (
    printf "  Converted to %s\n" png_file;
    (* Remove the PPM file since we have PNG *)
    Core_unix.unlink ppm_file);
  Wgpu.Buffer.unmap readback_buffer;
  (* Cleanup *)
  Wgpu.Command_buffer.release command_buffer;
  Wgpu.Render_pass_encoder.release render_pass;
  Wgpu.Command_encoder.release encoder;
  Wgpu.Buffer.release readback_buffer;
  Wgpu.Texture_view.release texture_view;
  Wgpu.Texture.release texture;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance;
  print_endline "All resources released."
;;
