(** Hello Triangle example using wgpu for GPU-accelerated rendering to a winit window *)

let shader_code =
  {|
struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    @location(0) color: vec3<f32>,
}

@vertex
fn vs_main(@builtin(vertex_index) in_vertex_index: u32) -> VertexOutput {
    // Classic triangle vertices - centered, pointing up
    var positions = array<vec2<f32>, 3>(
        vec2<f32>(0.0, 0.5),    // Top vertex
        vec2<f32>(-0.5, -0.5),  // Bottom-left vertex
        vec2<f32>(0.5, -0.5),   // Bottom-right vertex
    );

    // RGB colors for each vertex
    var colors = array<vec3<f32>, 3>(
        vec3<f32>(1.0, 0.0, 0.0),  // Red at top
        vec3<f32>(0.0, 1.0, 0.0),  // Green at bottom-left
        vec3<f32>(0.0, 0.0, 1.0),  // Blue at bottom-right
    );

    var output: VertexOutput;
    output.position = vec4<f32>(positions[in_vertex_index], 0.0, 1.0);
    output.color = colors[in_vertex_index];
    return output;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.color, 1.0);
}
|}
;;

let () =
  (* Create window *)
  let window = Winit.create () in
  (* Initialize wgpu *)
  let instance = Wgpu.Instance.create () in
  let adapter = Wgpu.Instance.request_adapter instance () in
  let device = Wgpu.Adapter.request_device adapter in
  let queue = Wgpu.Device.get_queue device in
  (* Create surface from window *)
  let surface = Winit_wgpu.create_surface ~instance ~window in
  (* Create shader module *)
  let shader =
    Wgpu.Device.create_shader_module device ~label:"triangle_shader" ~wgsl:shader_code ()
  in
  (* Get initial surface size in physical pixels (not logical) *)
  let initial_width, initial_height = Winit.surface_size window in
  let width = ref initial_width in
  let height = ref initial_height in
  (* Configure surface *)
  let configure_surface () =
    Wgpu.Surface.configure
      surface
      ~device
      ~format:Wgpu.Texture_format.Bgra8_unorm
      ~usage:[ Wgpu.Texture_usage.Item.Render_attachment ]
      ~width:!width
      ~height:!height
      ~alpha_mode:Wgpu.Composite_alpha_mode.Auto
      ~present_mode:Wgpu.Present_mode.Fifo
      ()
  in
  configure_surface ();
  (* Create render pipeline *)
  let pipeline =
    Wgpu.Device.create_render_pipeline
      device
      ~label:"triangle_pipeline"
      ~shader_module:shader
      ~vertex_entry_point:"vs_main"
      ~fragment_entry_point:"fs_main"
      ~color_format:Wgpu.Texture_format.Bgra8_unorm
      ()
  in
  (* Main loop *)
  let running = ref true in
  while !running do
    (* Handle events *)
    List.iter
      (fun event ->
        match event with
        | Winit.CloseRequested -> running := false
        | Winit.SurfaceResized { width = w; height = h } ->
          width := w;
          height := h;
          if w > 0 && h > 0 then configure_surface ()
        | _ -> ())
      (Winit.pump_events window);
    (* Skip rendering if window is minimized *)
    if !width > 0 && !height > 0
    then (
      (* Get current surface texture *)
      let surface_texture = Wgpu.Surface.get_current_texture surface in
      let texture_view =
        Wgpu.create_texture_view surface_texture.texture ~label:"surface_view" ()
      in
      (* Create command encoder *)
      let encoder =
        Wgpu.Device.create_command_encoder device ~label:"render_encoder" ()
      in
      (* Begin render pass *)
      let render_pass =
        Wgpu.begin_render_pass
          encoder
          ~label:"triangle_pass"
          ~color_view:texture_view
          ~clear_color:(0.1, 0.2, 0.3, 1.0)
          ()
      in
      (* Draw triangle *)
      Wgpu.Render_pass_encoder.set_pipeline render_pass ~pipeline;
      Wgpu.Render_pass_encoder.draw
        render_pass
        ~vertex_count:3
        ~instance_count:1
        ~first_vertex:0
        ~first_instance:0;
      Wgpu.Render_pass_encoder.end_ render_pass;
      (* Submit commands *)
      let command_buffer = Wgpu.finish encoder ~label:"render_commands" () in
      Wgpu.Queue.submit queue ~commands:[ command_buffer ];
      (* Present *)
      let _status = Wgpu.Surface.present surface in
      (* Cleanup frame resources *)
      Wgpu.Command_buffer.release command_buffer;
      Wgpu.Render_pass_encoder.release render_pass;
      Wgpu.Command_encoder.release encoder;
      Wgpu.Texture_view.release texture_view;
      Wgpu.Texture.release surface_texture.texture);
    (* Small delay to avoid busy-waiting *)
    Unix.sleepf 0.016
  done;
  (* Cleanup *)
  Wgpu.Render_pipeline.release pipeline;
  Wgpu.Shader_module.release shader;
  Wgpu.Surface.release surface;
  Wgpu.Queue.release queue;
  Wgpu.Device.release device;
  Wgpu.Adapter.release adapter;
  Wgpu.Instance.release instance
;;
