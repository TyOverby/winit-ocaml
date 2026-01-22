open Winit_softbuffer

(* A paint stroke is a circle with position, radius, and color *)
type stroke =
  { x : float
  ; y : float
  ; radius : float
  ; color : int32
  }

(* State for the painting app *)
type paint_state =
  { mutable strokes : stroke list
  ; mutable is_drawing : bool
  ; mutable last_x : float
  ; mutable last_y : float
  }

let create_state () =
  { strokes = []; is_drawing = false; last_x = 0.0; last_y = 0.0 }
;;

(* Draw a filled circle (using a simple algorithm) *)
let draw_circle buffer width height cx cy radius color =
  let cx_i = int_of_float cx in
  let cy_i = int_of_float cy in
  let r_i = int_of_float radius in
  let r_squared = radius *. radius in
  for dy = -r_i to r_i do
    for dx = -r_i to r_i do
      let dist_sq = float_of_int (dx * dx + dy * dy) in
      if dist_sq <= r_squared
      then (
        let x = cx_i + dx in
        let y = cy_i + dy in
        if x >= 0 && x < width && y >= 0 && y < height
        then (
          let index = (y * width) + x in
          Bigarray.Array1.set buffer index color))
    done
  done
;;

(* Clear the buffer to white *)
let clear_buffer buffer width height =
  let white = 0xFFFFFFFl in
  for i = 0 to (width * height) - 1 do
    Bigarray.Array1.set buffer i white
  done
;;

(* Draw all strokes *)
let draw_all_strokes buffer width height strokes =
  List.iter
    (fun stroke -> draw_circle buffer width height stroke.x stroke.y stroke.radius stroke.color)
    strokes
;;

(* Add a stroke based on position and pressure *)
let add_stroke state x y pressure =
  (* Map pressure (0.0-1.0) to radius (2.0-20.0 pixels) *)
  let min_radius = 2.0 in
  let max_radius = 20.0 in
  let radius = min_radius +. (pressure *. (max_radius -. min_radius)) in
  (* Use black color *)
  let color = 0xFF000000l in
  let stroke = { x; y; radius; color } in
  state.strokes <- stroke :: state.strokes
;;

let () =
  Printf.printf "=== Simple Painting App ===\n%!";
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
          Printf.printf "Clearing canvas...\n%!";
          state.strokes <- []
        | PointerButtonPressed { x; y; _ } ->
          Printf.printf "Pen down at (%.1f, %.1f)\n%!" x y;
          state.is_drawing <- true;
          state.last_x <- x;
          state.last_y <- y
        | PointerButtonReleased _ ->
          Printf.printf "Pen up\n%!";
          state.is_drawing <- false
        | PointerMoved { x; y; source; _ } ->
          (match source with
           | Tablet { pressure; tool_kind; _ } when state.is_drawing ->
             let pressure_val =
               match pressure with
               | Some p -> p
               | None -> 0.5 (* Default pressure if not available *)
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
             (* Add stroke at current position *)
             add_stroke state x y pressure_val;
             state.last_x <- x;
             state.last_y <- y
           | Mouse when state.is_drawing ->
             (* Also support mouse for testing without tablet *)
             add_stroke state x y 0.5;
             state.last_x <- x;
             state.last_y <- y
           | _ -> ())
        | _ -> ())
      events;
    (* Get buffer and draw *)
    let width, height, buffer = get_buffer app in
    (* Clear to white *)
    clear_buffer buffer width height;
    (* Draw all strokes *)
    draw_all_strokes buffer width height (List.rev state.strokes);
    (* Present *)
    present app;
    (* Limit to ~60 FPS *)
    Unix.sleepf 0.016
  done;
  Printf.printf "Exiting painting app.\n%!"
;;
