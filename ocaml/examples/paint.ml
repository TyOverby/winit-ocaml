open Winit_softbuffer

(* State for the painting app *)
type paint_state =
  { mutable canvas_buffer :
      (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t option
  ; mutable canvas_width : int
  ; mutable canvas_height : int
  ; mutable is_drawing : bool
  ; mutable dirty_regions : Winit_softbuffer.damage_rect list
  ; mutable last_x : float option
  ; mutable last_y : float option
  ; mutable last_radius : float option
  }

let create_state () =
  { canvas_buffer = None
  ; canvas_width = 0
  ; canvas_height = 0
  ; is_drawing = false
  ; dirty_regions = []
  ; last_x = None
  ; last_y = None
  ; last_radius = None
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

(* Helper: Check if a point is inside a quadrilateral using cross products *)
let point_in_quad px py (x0, y0) (x1, y1) (x2, y2) (x3, y3) =
  (* Check if point is on the same side of each edge *)
  let cross (ax, ay) (bx, by) (cx, cy) =
    ((bx -. ax) *. (cy -. ay)) -. ((by -. ay) *. (cx -. ax))
  in
  let s0 = cross (x0, y0) (x1, y1) (px, py) in
  let s1 = cross (x1, y1) (x2, y2) (px, py) in
  let s2 = cross (x2, y2) (x3, y3) (px, py) in
  let s3 = cross (x3, y3) (x0, y0) (px, py) in
  (s0 >= 0.0 && s1 >= 0.0 && s2 >= 0.0 && s3 >= 0.0)
  || (s0 <= 0.0 && s1 <= 0.0 && s2 <= 0.0 && s3 <= 0.0)
;;

(* Draw a filled quadrilateral connecting two circles *)
let draw_quad_to_canvas state x0 y0 r0 x1 y1 r1 color =
  match state.canvas_buffer with
  | None -> None
  | Some buffer ->
    let width = state.canvas_width in
    let height = state.canvas_height in
    (* Calculate direction vector and perpendicular *)
    let dx = x1 -. x0 in
    let dy = y1 -. y0 in
    let dist = sqrt ((dx *. dx) +. (dy *. dy)) in
    if dist < 0.01
    then None (* Too close, skip *)
    else (
      (* Perpendicular vector (normalized) *)
      let px = -.dy /. dist in
      let py = dx /. dist in
      (* Four corners of the quadrilateral *)
      let corner0 = x0 +. (px *. r0), y0 +. (py *. r0) in
      let corner1 = x0 -. (px *. r0), y0 -. (py *. r0) in
      let corner2 = x1 -. (px *. r1), y1 -. (py *. r1) in
      let corner3 = x1 +. (px *. r1), y1 +. (py *. r1) in
      (* Calculate bounding box (union of both circles) *)
      let min_x = max 0 (int_of_float (min x0 x1 -. max r0 r1 -. 1.0)) in
      let min_y = max 0 (int_of_float (min y0 y1 -. max r0 r1 -. 1.0)) in
      let max_x = min (width - 1) (int_of_float (max x0 x1 +. max r0 r1 +. 1.0)) in
      let max_y = min (height - 1) (int_of_float (max y0 y1 +. max r0 r1 +. 1.0)) in
      (* Fill the quadrilateral *)
      for y = min_y to max_y do
        for x = min_x to max_x do
          let fx = float_of_int x in
          let fy = float_of_int y in
          if point_in_quad fx fy corner0 corner1 corner2 corner3
          then (
            let index = (y * width) + x in
            Bigarray.Array1.unsafe_set buffer index color)
        done
      done;
      (* Return damage rect *)
      let rect_width = max_x - min_x + 1 in
      let rect_height = max_y - min_y + 1 in
      if rect_width > 0 && rect_height > 0
      then
        Some
          Winit_softbuffer.
            { x = min_x; y = min_y; width = rect_width; height = rect_height }
      else None)
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
let blit_to_screen canvas_buffer screen_buffer =
  (* Bigarray.Array1.blit uses memcpy internally - much faster than element-by-element *)
  if Bigarray.Array1.dim canvas_buffer = Bigarray.Array1.dim screen_buffer
  then Bigarray.Array1.blit canvas_buffer screen_buffer
  else
    (* Fallback to manual copy if sizes don't match (shouldn't happen) *)
    let size = min (Bigarray.Array1.dim canvas_buffer) (Bigarray.Array1.dim screen_buffer) in
    for i = 0 to size - 1 do
      let pixel = Bigarray.Array1.unsafe_get canvas_buffer i in
      Bigarray.Array1.unsafe_set screen_buffer i pixel
    done
;;

(* Blit only the damaged regions from canvas to screen buffer *)
let blit_damaged_regions canvas_buffer screen_buffer width dirty_regions =
  List.iter
    (fun (rect : Winit_softbuffer.damage_rect) ->
      (* Copy row by row using Bigarray.blit for each row *)
      for y = rect.y to rect.y + rect.height - 1 do
        let row_start = (y * width) + rect.x in
        let src_row = Bigarray.Array1.sub canvas_buffer row_start rect.width in
        let dst_row = Bigarray.Array1.sub screen_buffer row_start rect.width in
        Bigarray.Array1.blit src_row dst_row
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
  (* Check if this is a continuation of a stroke *)
  match state.last_x, state.last_y, state.last_radius with
  | Some last_x, Some last_y, Some last_radius ->
    (* Draw connecting quadrilateral *)
    (match draw_quad_to_canvas state last_x last_y last_radius x y radius color with
     | Some rect -> state.dirty_regions <- rect :: state.dirty_regions
     | None -> ());
    (* Draw circle at current position *)
    (match draw_circle_to_canvas state x y radius color with
     | Some rect -> state.dirty_regions <- rect :: state.dirty_regions
     | None -> ());
    (* Update last position *)
    state.last_x <- Some x;
    state.last_y <- Some y;
    state.last_radius <- Some radius
  | _ ->
    (* First stroke - just draw circle *)
    (match draw_circle_to_canvas state x y radius color with
     | Some rect -> state.dirty_regions <- rect :: state.dirty_regions
     | None -> ());
    (* Save position for next stroke *)
    state.last_x <- Some x;
    state.last_y <- Some y;
    state.last_radius <- Some radius
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
          state.is_drawing <- false;
          (* Reset stroke state so next stroke starts fresh *)
          state.last_x <- None;
          state.last_y <- None;
          state.last_radius <- None
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
    Printf.printf "age:%d\n%!" age;
    match state.canvas_buffer, age, state.dirty_regions with
    | Some canvas_buffer, 1, _ :: _ ->
      blit_damaged_regions canvas_buffer buffer width state.dirty_regions;
      present_with_damage app (Array.of_list state.dirty_regions);
      state.dirty_regions <- []
    | _, 1, [] -> ()
    | Some canvas_buffer, _, _ ->
      Printf.printf "blitting everything!\n%!";
      blit_to_screen canvas_buffer buffer;
      present app;
      state.dirty_regions <- []
    | _ -> ()
  done;
  Printf.printf "Exiting painting app.\n%!"
;;
