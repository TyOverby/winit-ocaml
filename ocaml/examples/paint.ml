open Winit_softbuffer

(* State for the painting app *)
type paint_state =
  { mutable canvas_buffer :
      (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t option
  ; mutable canvas_width : int
  ; mutable canvas_height : int
  ; mutable is_drawing : bool
  ; mutable dirty_regions : Winit_softbuffer.damage_rect list
  }

let create_state () =
  { canvas_buffer = None
  ; canvas_width = 0
  ; canvas_height = 0
  ; is_drawing = false
  ; dirty_regions = []
  }
;;

(* Create or recreate the canvas buffer if size changed *)
let ensure_canvas_size state width height =
  if state.canvas_width <> width || state.canvas_height <> height
  then (
    Printf.printf "Creating canvas buffer: %dx%d\n%!" width height;
    let size = width * height in
    let buffer = Bigarray.Array1.create Bigarray.Int32 Bigarray.C_layout size in
    (* Clear to white *)
    let white = 0xFFFFFFFl in
    for i = 0 to size - 1 do
      Bigarray.Array1.unsafe_set buffer i white
    done;
    state.canvas_buffer <- Some buffer;
    state.canvas_width <- width;
    state.canvas_height <- height)
;;

(* Draw a filled circle directly into the canvas buffer and return damage rect *)
let draw_circle_to_canvas state cx cy radius color =
  match state.canvas_buffer with
  | None -> None
  | Some buffer ->
    let width = state.canvas_width in
    let height = state.canvas_height in
    let cx_i = int_of_float cx in
    let cy_i = int_of_float cy in
    let r_i = int_of_float (radius +. 1.0) in
    (* Add 1 for safety margin *)
    let r_squared = radius *. radius in
    (* Calculate bounding box *)
    let min_x = max 0 (cx_i - r_i) in
    let min_y = max 0 (cy_i - r_i) in
    let max_x = min (width - 1) (cx_i + r_i) in
    let max_y = min (height - 1) (cy_i + r_i) in
    (* Draw the circle *)
    for dy = -r_i to r_i do
      for dx = -r_i to r_i do
        let dist_sq = float_of_int ((dx * dx) + (dy * dy)) in
        if dist_sq <= r_squared
        then (
          let x = cx_i + dx in
          let y = cy_i + dy in
          if x >= 0 && x < width && y >= 0 && y < height
          then (
            let index = (y * width) + x in
            Bigarray.Array1.unsafe_set buffer index color))
      done
    done;
    (* Return damage rect if valid *)
    let rect_width = max_x - min_x + 1 in
    let rect_height = max_y - min_y + 1 in
    if rect_width > 0 && rect_height > 0
    then
      Some
        Winit_softbuffer.
          { x = min_x; y = min_y; width = rect_width; height = rect_height }
    else None
;;

(* Blit (copy) the entire canvas buffer to the screen buffer *)
let blit_to_screen canvas_buffer screen_buffer size =
  for i = 0 to size - 1 do
    let pixel = Bigarray.Array1.unsafe_get canvas_buffer i in
    Bigarray.Array1.unsafe_set screen_buffer i pixel
  done
;;

(* Blit only the damaged regions from canvas to screen buffer *)
let blit_damaged_regions canvas_buffer screen_buffer width dirty_regions =
  List.iter
    (fun (rect : Winit_softbuffer.damage_rect) ->
      for y = rect.y to rect.y + rect.height - 1 do
        for x = rect.x to rect.x + rect.width - 1 do
          let index = (y * width) + x in
          let pixel = Bigarray.Array1.unsafe_get canvas_buffer index in
          Bigarray.Array1.unsafe_set screen_buffer index pixel
        done
      done)
    dirty_regions
;;

(* Clear the canvas to white and mark entire canvas as dirty *)
let clear_canvas state =
  match state.canvas_buffer with
  | None -> ()
  | Some buffer ->
    let white = 0xFFFFFFFl in
    let size = state.canvas_width * state.canvas_height in
    for i = 0 to size - 1 do
      Bigarray.Array1.unsafe_set buffer i white
    done;
    (* Mark entire canvas as dirty *)
    state.dirty_regions
    <- [ Winit_softbuffer.
           { x = 0; y = 0; width = state.canvas_width; height = state.canvas_height }
       ];
    Printf.printf "Canvas cleared\n%!"
;;

(* Draw a stroke based on position and pressure, tracking damage *)
let draw_stroke state x y pressure =
  (* Map pressure (0.0-1.0) to radius (2.0-20.0 pixels) *)
  let min_radius = 2.0 in
  let max_radius = 20.0 in
  let radius = min_radius +. (pressure *. (max_radius -. min_radius)) in
  (* Use black color *)
  let color = 0xFF000000l in
  match draw_circle_to_canvas state x y radius color with
  | Some rect -> state.dirty_regions <- rect :: state.dirty_regions
  | None -> ()
;;

let () =
  Printf.printf "=== Simple Painting App (Optimized) ===\n%!";
  Printf.printf "Use your tablet pen to draw!\n%!";
  Printf.printf "- Press pen down to start drawing\n%!";
  Printf.printf "- Pressure controls brush size (2-20 pixels)\n%!";
  Printf.printf "- Press 'C' key to clear canvas\n%!";
  Printf.printf "- Close window to exit\n\n%!";
  let app = create () in
  let state = create_state () in
  let should_exit = ref false in
  while not !should_exit do
    (* Pump events *)
    let events = pump_events app in
    (* Process events *)
    List.iter
      (fun event ->
        match event with
        | CloseRequested -> should_exit := true
        | KeyPressed { key_code = 6; _ } ->
          (* Key code 6 is 'C' - clear canvas *)
          clear_canvas state
        | PointerButtonPressed _ ->
          Printf.printf "Pen down\n%!";
          state.is_drawing <- true
        | PointerButtonReleased _ ->
          Printf.printf "Pen up\n%!";
          state.is_drawing <- false
        | PointerMoved { x; y; source; _ } ->
          (match source with
           | Tablet { pressure; tool_kind; _ } when state.is_drawing ->
             let pressure_val =
               match pressure with
               | Some p -> p
               | None -> 0.0
             in
             Printf.printf
               "Drawing: (%.1f, %.1f) pressure=%.3f tool=%s\n%!"
               x
               y
               pressure_val
               (match tool_kind with
                | Pen -> "Pen"
                | Eraser -> "Eraser"
                | _ -> "Other");
             (* Draw directly to canvas buffer *)
             draw_stroke state x y pressure_val
           | Mouse when state.is_drawing ->
             (* Also support mouse for testing without tablet *)
             draw_stroke state x y 0.5
           | _ -> ())
        | _ -> ())
      events;
    (* Get buffer and draw *)
    let width, height, buffer = get_buffer app in
    (* Ensure canvas is the right size *)
    ensure_canvas_size state width height;
    (* Check buffer age to determine if we need full redraw *)
    let age = get_buffer_age app in
    (* Blit canvas to screen *)
    match state.canvas_buffer, age, state.dirty_regions with
    | Some canvas_buffer, 1, _ :: _ ->
      blit_damaged_regions canvas_buffer buffer width state.dirty_regions;
      present_with_damage app (Array.of_list state.dirty_regions);
      state.dirty_regions <- []
    | _, 1, [] -> ()
    | Some canvas_buffer, _, _ ->
      Printf.printf "blitting everything!%!";
      blit_to_screen canvas_buffer buffer (width * height);
      present app;
      state.dirty_regions <- []
    | _ -> ()
  done;
  Printf.printf "Exiting painting app.\n%!"
;;
