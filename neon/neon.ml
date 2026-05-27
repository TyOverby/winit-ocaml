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

(* Build a circle SDF: sqrt((x - cx)^2 + (y - cy)^2) - r *)
let build_circle_sdf ~cx ~cy ~r =
  let open Or_error.Let_syntax in
  let loc = [%here] in
  let%bind x = Sdf.Expr_tree.var ~loc "x" Float in
  let%bind y = Sdf.Expr_tree.var ~loc "y" Float in
  let%bind cx_lit = Sdf.Expr_tree.float_literal ~loc cx in
  let%bind cy_lit = Sdf.Expr_tree.float_literal ~loc cy in
  let%bind r_lit = Sdf.Expr_tree.float_literal ~loc r in
  let%bind dx = Sdf.Expr_tree.sub ~loc x cx_lit in
  let%bind dy = Sdf.Expr_tree.sub ~loc y cy_lit in
  let%bind dx2 = Sdf.Expr_tree.mul ~loc dx dx in
  let%bind dy2 = Sdf.Expr_tree.mul ~loc dy dy in
  let%bind sum = Sdf.Expr_tree.add ~loc dx2 dy2 in
  let%bind dist = Sdf.Expr_tree.sqrt ~loc sum in
  Sdf.Expr_tree.sub ~loc dist r_lit
;;

(* Smooth union: min(a, b) - h*h*0.25/k where h = max(k - abs(a-b), 0) and k = k_in * 4 *)
let smooth_union ~k a b =
  let open Or_error.Let_syntax in
  let loc = [%here] in
  let%bind four = Sdf.Expr_tree.float_literal ~loc #4.0s in
  let%bind k_scaled = Sdf.Expr_tree.mul ~loc k four in
  let%bind a_minus_b = Sdf.Expr_tree.sub ~loc a b in
  let%bind abs_diff = Sdf.Expr_tree.abs ~loc a_minus_b in
  let%bind k_minus_abs = Sdf.Expr_tree.sub ~loc k_scaled abs_diff in
  let%bind zero = Sdf.Expr_tree.float_literal ~loc #0.0s in
  let%bind h = Sdf.Expr_tree.max ~loc k_minus_abs zero in
  let%bind h_sq = Sdf.Expr_tree.mul ~loc h h in
  let%bind quarter = Sdf.Expr_tree.float_literal ~loc #0.25s in
  let%bind h_sq_quarter = Sdf.Expr_tree.mul ~loc h_sq quarter in
  let%bind correction = Sdf.Expr_tree.div ~loc h_sq_quarter k_scaled in
  let%bind min_ab = Sdf.Expr_tree.min ~loc a b in
  Sdf.Expr_tree.sub ~loc min_ab correction
;;

let build_sdf () =
  Or_error.ok_exn
    (let open Or_error.Let_syntax in
     let%bind k = Sdf.Expr_tree.float_literal ~loc:[%here] #10.0s in
     let%bind c1 = build_circle_sdf ~cx:#150.0s ~cy:#150.0s ~r:#80.0s in
     let%bind c2 = build_circle_sdf ~cx:#250.0s ~cy:#200.0s ~r:#80.0s in
     smooth_union ~k c1 c2)
;;

type compiled_sdf =
  { run : variables:Sdf.Value.Array.t -> Sdf.Value.t
  ; variables : Sdf.Value.Array.t
  ; x_idx : int
  ; y_idx : int
  }

let compile_sdf () =
  let tree = build_sdf () in
  let ~instructions, ~final_register, ~register_count, ~var_mapping =
    Sdf.Expr_graph.from_tree tree
  in
  let registers = Sdf.Value.Array.create ~len:register_count in
  let run ~variables =
    Sdf.Expr_graph_eval.run ~instructions ~registers ~variables;
    Sdf.Value.Array.get registers final_register
  in
  let x_idx = Hashtbl.find_exn var_mapping "x" in
  let y_idx = Hashtbl.find_exn var_mapping "y" in
  let num_vars = Hashtbl.length var_mapping in
  let variables = Sdf.Value.Array.create ~len:num_vars in
  { run; variables; x_idx; y_idx }
;;

let draw_shape (state : state) (sdf : compiled_sdf) =
  let width = Image_buf.width state.canvas in
  let height = Image_buf.height state.canvas in
  for x = 0 to width - 1 do
    for y = 0 to height - 1 do
      Sdf.Value.Array.set_float
        sdf.variables
        sdf.x_idx
        (Float32_u.of_float (Float.of_int x));
      Sdf.Value.Array.set_float
        sdf.variables
        sdf.y_idx
        (Float32_u.of_float (Float.of_int y));
      let value = sdf.run ~variables:sdf.variables in
      let dist = Float32_u.to_float (Sdf.Value.to_float value) in
      if Float.(dist <= 0.0)
      then Image_buf.set state.canvas ~x ~y #0xFF000000l
      else if Float.(dist <= 8.0)
      then Image_buf.set state.canvas ~x ~y #0xFF5384EDl
      else Image_buf.set state.canvas ~x ~y #0xFFFFFFFFl
    done
  done
;;

let () =
  let window = Winit.create () in
  let surface = Softbuffer.create (Winit.get_handle window) in
  let state = create_state () in
  let sdf = compile_sdf () in
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
    let before = Core.Time_ns.now () in
    draw_shape state sdf;
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
