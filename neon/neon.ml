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

let scene_file = (Sys.get_argv ()).(1)

type compiled_sdf =
  { instructions : (int * Sdf.Expr_graph.instr) list
  ; final_register : int
  ; register_count : int
  ; x_idx : int
  ; y_idx : int
  ; num_vars : int
  }

let compile_sdf_from_source source =
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

let maybe_recompile ~last_mtime ~current_sdf =
  let stats = Core_unix.stat scene_file in
  let mtime = stats.st_mtime in
  if Float.( <> ) mtime last_mtime
  then (
    Printf.printf "File changed, recompiling...\n%!";
    match compile_sdf_from_source (In_channel.read_all scene_file) with
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
      let variables = Sdf.Value.Array.create ~len:num_vars in
      let registers = Sdf.Value.Array.create ~len:register_count in
      Sdf.Value.Array.set_float variables y_idx (Float32_u.of_float (Float.of_int y));
      for x = 0 to width - 1 do
        Sdf.Value.Array.set_float variables x_idx (Float32_u.of_float (Float.of_int x));
        Sdf.Expr_graph_eval.run ~variables ~instructions ~registers;
        let value = Sdf.Value.Array.get registers final_register in
        let dist = Float32_u.to_float (Sdf.Value.to_float value) in
        if Float.(dist <= 0.0)
        then Image_buf.set canvas ~x ~y #0xFF000000l
        else if Float.(dist <= 8.0)
        then Image_buf.set canvas ~x ~y #0xFF5384EDl
        else Image_buf.set canvas ~x ~y #0xFFFFFFFFl
      done))
;;

let () =
  let window =
    Winit.create ~window_level:Always_on_top ~title:"Neon" ~width:200 ~height:200 ()
  in
  let surface = Softbuffer.create (Winit.get_handle window) in
  let state = create_state () in
  let source = In_channel.read_all scene_file in
  let sdf = ref (compile_sdf_from_source source) in
  let last_mtime = ref (Core_unix.stat scene_file).st_mtime in
  let scheduler = Parallel_scheduler.create () in
  let should_exit = ref false in
  while not !should_exit do
    (* Check for file changes *)
    let new_mtime, new_sdf = maybe_recompile ~last_mtime:!last_mtime ~current_sdf:!sdf in
    last_mtime := new_mtime;
    sdf := new_sdf;
    (* Pump events *)
    let events = Winit.pump_events window in
    (* Process events *)
    List.iter events ~f:(fun event ->
      match event with
      | Winit.CloseRequested -> should_exit := true
      | Winit.SurfaceResized { width; height } -> Softbuffer.resize surface ~width ~height
      | Winit.PointerButtonPressed _ ->
        Printf.printf "Pen down\n%!";
        state.is_drawing <- true
      | Winit.PointerButtonReleased _ ->
        Printf.printf "Pen up\n%!";
        state.is_drawing <- false;
        state.last_x <- None;
        state.last_y <- None
      | Winit.PointerMoved { x; y; source = _; _ } ->
        Printf.printf "pointer moved: (%.1f, %.1f)" x y
      | _ -> ());
    (* Get buffer and draw *)
    let screen =
      let width, height, buffer = Softbuffer.get_buffer surface in
      Image_buf.from_external ~width ~height buffer
    in
    (* Ensure canvas is the right size *)
    ensure_canvas_size state screen;
    (* Draw and present *)
    let before = Core.Time_ns.now () in
    draw_shape state !sdf scheduler;
    let after = Core.Time_ns.now () in
    print_s
      [%message "" ~time_to_draw:(Core.Time_ns.abs_diff before after : Time_ns.Span.t)];
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
  done
;;
