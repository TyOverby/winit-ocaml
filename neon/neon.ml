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

(* Blit (copy) the entire canvas buffer to the screen buffer *)

let draw_shape (state : state) =
  for x = 0 to 100 do
    for y = 0 to 100 do
      if x % 2 = 0 && y % 2 = 0 then Image_buf.set state.canvas ~x ~y #0xFF000000l
    done
  done;
  let _ = state in
  ()
;;

let () =
  let window = Winit.create () in
  let surface = Softbuffer.create (Winit.get_handle window) in
  let state = create_state () in
  let should_exit = ref false in
  while not !should_exit do
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
    (* Blit canvas to screen *)
    Printf.printf "blitting everything!\n%!";
    draw_shape state;
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
  done;
  Printf.printf "Exiting painting app.\n%!"
;;
