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

let oracle_registry : unit -> (string * (module Sdf.Oracle.S) portable) list =
  fun () ->
  [ "passthrough", { portable = (module Sdf_passthrough_oracle) }
  ; "resample", { portable = (module Sdf_resample_oracle) }
  ]
;;

let read_source ~scene_file ~last_mtime ~current_source =
  let stats = Core_unix.stat scene_file in
  let mtime = stats.st_mtime in
  if Float.( <> ) mtime last_mtime
  then mtime, In_channel.read_all scene_file
  else mtime, current_source
;;

let color_grayscale (dist : float) : Int32_u.t =
  if Float.(dist <= 0.0)
  then #0xFF000000l
  else if Float.(dist <= 1.0)
  then (
    let component = dist *. 255.0 |> Float.to_int |> Int32_u.of_int_trunc in
    Int32_u.(
      component lor shift_left component 8 lor shift_left component 16 lor #0xFF000000l))
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

let draw_shape' (state : state) runner ~filename ~source ~show_timings =
  let width = Image_buf.width state.canvas in
  let height = Image_buf.height state.canvas in
  let canvas = state.canvas in
  let region =
    { Sdf.Sample_region.start_x = #0.0s
    ; end_x = Float32_u.of_float (Float.of_int width)
    ; samples_x = width
    ; start_y = #0.0s
    ; end_y = Float32_u.of_float (Float.of_int height)
    ; samples_y = height
    }
  in
  Sdf_runner.run runner ~region ~filename source ~f:(fun par result get ->
    let color_pixel =
      match state.render_mode with
      | Grayscale -> color_grayscale
      | Rings -> color_rings
    in
    let before = Core.Time_ns.now () in
    Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
      for x = 0 to width - 1 do
        let dist =
          Float32_u.to_float (Sdf.Value.to_float (get (Obj.magic Obj.magic result) ~x ~y))
        in
        Image_buf.set canvas ~x ~y (color_pixel dist)
      done);
    let after = Core.Time_ns.now () in
    if show_timings
    then
      print_s
        [%message "" ~copy_pixels:(Core.Time_ns.abs_diff before after : Time_ns.Span.t)])
;;

(* The available evaluation backends, each a [(module Batch_backend_intf.S_parallel)],
   selected by the [-backend] flag. *)
let backends : (string * (module Sdf.Executor.S) portable) list =
  [ "batch", { portable = (module Sdf.Expr_graph_batch_eval) }
  ; "graph", { portable = (module Sdf.Expr_graph_eval) }
  ; "tree", { portable = (module Sdf.Expr_tree_eval) }
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
       let runner = Sdf_runner.create backend.portable in
       List.iter (oracle_registry ()) ~f:(fun (name, { portable = oracle }) ->
         Sdf_runner.add_oracle runner ~name oracle);
       let last_mtime = ref (Core_unix.stat scene_file).st_mtime in
       let last_source = ref (In_channel.read_all scene_file) in
       let should_exit = ref false in
       let switch_backend label =
         match List.Assoc.find backends label ~equal:String.equal with
         | None -> ()
         | Some { portable = backend } ->
           Printf.printf "Switching to %s backend\n%!" label;
           Sdf_runner.set_executor runner backend
       in
       while not !should_exit do
         let () =
           let mtime, source =
             read_source ~scene_file ~last_mtime:!last_mtime ~current_source:!last_source
           in
           last_mtime := mtime;
           last_source := source;
           ()
         in
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
         let before = Core.Time_ns.now () in
         draw_shape' state runner ~filename:scene_file ~source:!last_source ~show_timings;
         let after = Core.Time_ns.now () in
         if show_timings
         then
           print_s
             [%message
               "" ~time_to_draw:(Core.Time_ns.abs_diff before after : Time_ns.Span.t)];
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
