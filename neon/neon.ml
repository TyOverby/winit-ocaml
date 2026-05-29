open! Core

type state =
  { mutable canvas : (Image_buf.t[@sexp.opaque])
  ; mutable is_drawing : bool
  ; mutable dirty_regions : (Softbuffer.damage_rect list[@sexp.opaque])
  ; mutable last_x : float option
  ; mutable last_y : float option
  }
[@@warning "-69"] [@@deriving sexp_of]

let create_state () =
  { canvas = Image_buf.create ~width:0 ~height:0 #0l
  ; is_drawing = false
  ; dirty_regions = []
  ; last_x = None
  ; last_y = None
  }
;;

(* Create or recreate the canvas buffer if size changed *)
let ensure_canvas_size state screen =
  let width = Image_buf.width screen
  and height = Image_buf.height screen in
  if Image_buf.width state.canvas <> width || Image_buf.height state.canvas <> height
  then (
    Printf.printf "Creating canvas buffer: %dx%d\n%!" width height;
    state.canvas <- Image_buf.create ~width ~height #0xFFFFFFFl)
;;

type compiled_sdf =
  { instructions : (int * Sdf.Expr_graph.instr) iarray
  ; final_register : int
  ; register_count : int
  ; x_idx : int
  ; y_idx : int
  ; num_vars : int
  }

let compile_sdf_from_source ~scene_file source =
  let tree = Neo.compile ~filename:scene_file source |> Or_error.ok_exn in
  let ~instructions, ~final_register, ~register_count, ~var_mapping =
    Sdf.Expr_graph.from_tree tree
  in
  Printf.printf "registers before minimization: %d\n%!" register_count;
  let ~instructions, ~final_register, ~register_count =
    Sdf.Expr_graph_register_minimizer.minimize
      ~instructions
      ~final_register
      ~register_count
  in
  Printf.printf "registers after minimization:  %d\n%!" register_count;
  let x_idx = Hashtbl.find_exn var_mapping "x" in
  let y_idx = Hashtbl.find_exn var_mapping "y" in
  let num_vars = Hashtbl.length var_mapping in
  { instructions; final_register; register_count; x_idx; y_idx; num_vars }
;;

let maybe_recompile ~scene_file ~last_mtime ~current_sdf =
  let stats = Core_unix.stat scene_file in
  let mtime = stats.st_mtime in
  if Float.( <> ) mtime last_mtime
  then (
    Printf.printf "File changed, recompiling...\n%!";
    match compile_sdf_from_source ~scene_file (In_channel.read_all scene_file) with
    | sdf ->
      Printf.printf "Recompiled successfully.\n%!";
      mtime, sdf
    | exception exn ->
      Printf.printf "Compilation error: %s\n%!" (Exn.to_string exn);
      mtime, current_sdf)
  else mtime, current_sdf
;;

let draw_shape (state : state) (sdf : compiled_sdf) (scheduler : Parallel_scheduler.t) =
  let width = Image_buf.width state.canvas in
  let height = Image_buf.height state.canvas in
  let canvas = state.canvas in
  let instructions = sdf.instructions in
  let final_register = sdf.final_register in
  let register_count = sdf.register_count in
  let x_idx = sdf.x_idx in
  let y_idx = sdf.y_idx in
  let num_vars = sdf.num_vars in
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
      let register_bank =
        Sdf.Expr_graph_batch_eval.Register_bank.create ~register_count ~width
      in
      let variable_bank =
        Sdf.Expr_graph_batch_eval.Variable_bank.create ~num_vars ~width
      in
      let y_val = Sdf.Value.of_float (Float32_u.of_float (Float.of_int y)) in
      for x = 0 to width - 1 do
        Sdf.Expr_graph_batch_eval.Variable_bank.set_variable
          variable_bank
          ~var:y_idx
          ~px:x
          y_val;
        Sdf.Expr_graph_batch_eval.Variable_bank.set_variable
          variable_bank
          ~var:x_idx
          ~px:x
          (Sdf.Value.of_float (Float32_u.of_float (Float.of_int x)))
      done;
      Sdf.Expr_graph_batch_eval.run ~variable_bank ~instructions ~register_bank ~width;
      for x = 0 to width - 1 do
        let value =
          Sdf.Expr_graph_batch_eval.Register_bank.get_result
            register_bank
            ~reg:final_register
            ~px:x
        in
        let dist = Float32_u.to_float (Sdf.Value.to_float value) in
        if Float.(dist <= 0.0)
        then Image_buf.set canvas ~x ~y #0xFF000000l
        else if Float.(dist <= 1.0)
        then (
          let component = dist *. 255.0 |> Float.to_int |> Int32_u.of_int_trunc in
          let color =
            Int32_u.(
              component
              lor shift_left component 8
              lor shift_left component 16
              lor #0xFF000000l)
          in
          Image_buf.set canvas ~x ~y color)
        else Image_buf.set canvas ~x ~y #0xFFFFFFFFl
      done))
;;

let command =
  Command.basic
    ~summary:"Neon SDF renderer"
    (let%map_open.Command scene_file = anon ("SCENE_FILE" %: string)
     and show_timings =
       flag "-timings" no_arg ~doc:" Print timing information for each frame"
     in
     fun () ->
       let window =
         Winit.create ~window_level:Always_on_top ~title:"Neon" ~width:400 ~height:400 ()
       in
       let surface = Softbuffer.create (Winit.get_handle window) in
       let state = create_state () in
       let source = In_channel.read_all scene_file in
       let sdf = ref (compile_sdf_from_source ~scene_file source) in
       let last_mtime = ref (Core_unix.stat scene_file).st_mtime in
       let scheduler = Parallel_scheduler.create () in
       let should_exit = ref false in
       while not !should_exit do
         (* Check for file changes *)
         let new_mtime, new_sdf =
           maybe_recompile ~scene_file ~last_mtime:!last_mtime ~current_sdf:!sdf
         in
         last_mtime := new_mtime;
         sdf := new_sdf;
         (* Pump events *)
         let events = Winit.pump_events window in
         (* Process events *)
         List.iter events ~f:(fun event ->
           match event with
           | Winit.CloseRequested -> should_exit := true
           | Winit.SurfaceResized { width; height } ->
             Softbuffer.resize surface ~width ~height
           | Winit.PointerButtonPressed _ -> state.is_drawing <- true
           | Winit.PointerButtonReleased _ ->
             state.is_drawing <- false;
             state.last_x <- None;
             state.last_y <- None
           | Winit.PointerMoved { x = _; y = _; source = _; _ } -> ()
           | _ -> ());
         (* Get buffer and draw *)
         let screen =
           let width, height, buffer = Softbuffer.get_buffer surface in
           Image_buf.from_external ~width ~height buffer
         in
         (* Ensure canvas is the right size *)
         ensure_canvas_size state screen;
         (* Draw and present *)
         if show_timings
         then (
           let before = Core.Time_ns.now () in
           draw_shape state !sdf scheduler;
           let after = Core.Time_ns.now () in
           print_s
             [%message
               "" ~time_to_draw:(Core.Time_ns.abs_diff before after : Time_ns.Span.t)])
         else draw_shape state !sdf scheduler;
         Image_buf.blit
           ~from:state.canvas
           ~to_:screen
           ~x:0
           ~y:0
           ~region:
             #{ Image_buf.Rect.x = 0
              ; y = 0
              ; w = Image_buf.width state.canvas
              ; h = Image_buf.height state.canvas
              };
         Softbuffer.present surface
       done)
;;

let () = Command_unix.run command
