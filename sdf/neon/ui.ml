open! Core

type render_mode =
  | Grayscale
  | Rings
[@@deriving sexp_of]

type state =
  { mutable canvas : (Image_buf.t[@sexp.opaque])
  ; mutable is_drawing : bool
  ; mutable dirty_regions : (Softbuffer.damage_rect list[@sexp.opaque])
  ; mutable last_x : float option
  ; mutable last_y : float option
  ; mutable render_mode : render_mode
  }
[@@warning "-69"] [@@deriving sexp_of]

let create_state () =
  { canvas = Image_buf.create ~width:0 ~height:0 #0l
  ; is_drawing = false
  ; dirty_regions = []
  ; last_x = None
  ; last_y = None
  ; render_mode = Grayscale
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

(* A compiled scene, ready to render. The chosen backend is packed together with its
   prepared program so that [draw_shape] can recover the backend's full module (including
   its [Variable_idx], [Batch], and [Result] types) when it unpacks the value. *)
type compiled_sdf =
  | Compiled :
      (module Sdf.Executor.S_parallel with type Prepared.t = 'p) * 'p
      -> compiled_sdf

let compile_sdf_from_source (module B : Sdf.Executor.S_parallel) ~scene_file source =
  let tree = Neo.compile ~filename:scene_file source |> Or_error.ok_exn in
  Compiled ((module B), B.Prepared.of_tree tree)
;;

let maybe_recompile backend ~scene_file ~last_mtime ~current_sdf =
  let stats = Core_unix.stat scene_file in
  let mtime = stats.st_mtime in
  if Float.( <> ) mtime last_mtime
  then (
    Printf.printf "File changed, recompiling...\n%!";
    match
      compile_sdf_from_source backend ~scene_file (In_channel.read_all scene_file)
    with
    | sdf ->
      Printf.printf "Recompiled successfully.\n%!";
      mtime, sdf
    | exception exn ->
      Printf.printf "Compilation error: %s\n%!" (Exn.to_string exn);
      mtime, current_sdf)
  else mtime, current_sdf
;;

let color_grayscale (dist : float) : Int32_u.t =
  if Float.(dist <= 0.0)
  then #0xFF000000l
  else if Float.(dist <= 1.0)
  then (
    let component = dist *. 255.0 |> Float.to_int |> Int32_u.of_int_trunc in
    Int32_u.(
      component
      lor shift_left component 8
      lor shift_left component 16
      lor #0xFF000000l))
  else #0xFFFFFFFFl
;;

let color_rings (dist : float) : Int32_u.t =
  let abs_d = Float.abs dist in
  (* Base colors: orange outside, blue inside *)
  let base_r, base_g, base_b =
    if Float.(dist > 0.0) then 0.9, 0.6, 0.3 else 0.4, 0.7, 0.85
  in
  (* Exponential darkening near the surface *)
  let fade = 1.0 -. Float.exp (-0.1 *. abs_d) in
  (* Concentric rings every 10 pixels *)
  let ring = 0.8 +. (0.2 *. Float.cos (Float.pi *. 2.0 *. dist /. 10.0)) in
  (* Combine base color with fade and rings *)
  let r = base_r *. fade *. ring in
  let g = base_g *. fade *. ring in
  let b = base_b *. fade *. ring in
  (* White contour at the zero-crossing (smoothstep over 1.5 pixels) *)
  let t = Float.min 1.0 (abs_d /. 1.5) in
  let edge = 1.0 -. (t *. t *. (3.0 -. (2.0 *. t))) in
  let r = r +. ((1.0 -. r) *. edge) in
  let g = g +. ((1.0 -. g) *. edge) in
  let b = b +. ((1.0 -. b) *. edge) in
  (* Pack to ARGB *)
  let ri = Float.to_int (r *. 255.0) |> Int.max 0 |> Int.min 255 in
  let gi = Float.to_int (g *. 255.0) |> Int.max 0 |> Int.min 255 in
  let bi = Float.to_int (b *. 255.0) |> Int.max 0 |> Int.min 255 in
  Int32_u.(
    of_int_trunc bi
    lor shift_left (of_int_trunc gi) 8
    lor shift_left (of_int_trunc ri) 16
    lor #0xFF000000l)
;;

let draw_shape (state : state) (Compiled ((module B), prepared)) scheduler =
  let width = Image_buf.width state.canvas in
  let height = Image_buf.height state.canvas in
  let canvas = state.canvas in
  (* Evaluate the whole grid in one shot. [x] and [y] are the pixel coordinates, expressed
     as affine functions of [(x, y)] so the backend never materialises per-pixel
     coordinate buffers; the backend owns the parallel fan-out internally. *)
  (* Colour the canvas from the host-resident result grid, in parallel over rows. *)
  Parallel_scheduler.parallel scheduler ~f:(fun par ->
    let batch = B.Batch.create prepared ~width ~height in
    Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
      B.Batch.set_affine batch ~var ~base:0.0 ~dx:1.0 ~dy:0.0);
    Option.iter (B.Prepared.lookup_variable prepared "y") ~f:(fun var ->
      B.Batch.set_affine batch ~var ~base:0.0 ~dx:0.0 ~dy:1.0);
    let result = B.Batch.run batch ~par ~oracles:Sdf.Oracle.Key.Map.empty in
    let color_pixel =
      match state.render_mode with
      | Grayscale -> color_grayscale
      | Rings -> color_rings
    in
    Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
      for x = 0 to width - 1 do
        let dist = Float32_u.to_float (Sdf.Value.to_float (B.Result.get result ~x ~y)) in
        Image_buf.set canvas ~x ~y (color_pixel dist)
      done))
;;

(* The available evaluation backends, each a [(module Batch_backend_intf.S_parallel)],
   selected by the [-backend] flag. *)
let backends : (string * (module Sdf.Executor.S_parallel)) list =
  [ "batch", (module Sdf.Expr_graph_batch_eval.Parallel)
  ; "graph", (module Sdf.Expr_graph_eval.Parallel)
  ; "tree", (module Sdf.Expr_tree_eval.Parallel)
  ]
;;

let backend_arg = Command.Arg_type.of_alist_exn backends

(* Physical key codes (the [keyboard_types.Code] enum discriminants reported by winit) for
   the keys that hot-swap the backend at runtime: b, g, t, and u on a US layout. *)
let backend_for_key_code key_code =
  match key_code with
  | 20 (* KeyB *) -> Some "batch"
  | 25 (* KeyG *) -> Some "graph"
  | 38 (* KeyT *) -> Some "tree"
  | 39 (* KeyU *) -> Some "gpu"
  | _ -> None
;;

let command =
  Command.basic
    ~summary:"Neon SDF renderer UI"
    (let%map_open.Command scene_file = anon ("SCENE_FILE" %: string)
     and show_timings =
       flag "-timings" no_arg ~doc:" Print timing information for each frame"
     and backend =
       flag
         "-backend"
         (optional_with_default
            (List.Assoc.find_exn backends "batch" ~equal:String.equal)
            backend_arg)
         ~doc:"BACKEND Evaluation backend: batch (default), graph, tree, or gpu"
     in
     fun () ->
       let window =
         Winit.create ~window_level:Always_on_top ~title:"Neon" ~width:400 ~height:400 ()
       in
       let surface = Softbuffer.create (Winit.get_handle window) in
       let state = create_state () in
       let source = In_channel.read_all scene_file in
       (* The active backend can be hot-swapped at runtime via the b/g/t keys. Switching
          re-derives the prepared program (which is backend-specific) from the current
          scene source. *)
       let current_backend = ref backend in
       let sdf = ref (compile_sdf_from_source !current_backend ~scene_file source) in
       let last_mtime = ref (Core_unix.stat scene_file).st_mtime in
       let scheduler = Parallel_scheduler.create () in
       let should_exit = ref false in
       let switch_backend label =
         match List.Assoc.find backends label ~equal:String.equal with
         | None -> ()
         | Some backend ->
           Printf.printf "Switching to %s backend\n%!" label;
           current_backend := backend;
           sdf
           := compile_sdf_from_source backend ~scene_file (In_channel.read_all scene_file)
       in
       while not !should_exit do
         (* Check for file changes *)
         let new_mtime, new_sdf =
           maybe_recompile
             !current_backend
             ~scene_file
             ~last_mtime:!last_mtime
             ~current_sdf:!sdf
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
           | Winit.KeyPressed { key_code; repeat = false; _ } ->
             Option.iter (backend_for_key_code key_code) ~f:switch_backend;
             if key_code = 40 (* KeyV *)
             then (
               state.render_mode
               <- (match state.render_mode with
                   | Grayscale -> Rings
                   | Rings -> Grayscale);
               Printf.printf
                 "Render mode: %s\n%!"
                 (match state.render_mode with
                  | Grayscale -> "grayscale"
                  | Rings -> "rings"))
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
