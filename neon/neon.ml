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
  let open Sdf.Expr_tree.Direct in
  let x = var "x" Float in
  let y = var "y" Float in
  let x = add x (mul (sin (div y (float_literal #5.0s))) (float_literal #5.0s)) in
  let y = add y (mul (cos (div x (float_literal #5.0s))) (float_literal #5.0s)) in
  let cx_lit = float_literal cx in
  let cy_lit = float_literal cy in
  let r_lit = float_literal r in
  let dx = sub x cx_lit in
  let dy = sub y cy_lit in
  let dx2 = mul dx dx in
  let dy2 = mul dy dy in
  let sum = add dx2 dy2 in
  let dist = sqrt sum in
  sub dist r_lit
;;

(* Smooth union: min(a, b) - h*h*0.25/k where h = max(k - abs(a-b), 0) and k = k_in * 4 *)
let smooth_union ~k a b =
  let open Sdf.Expr_tree.Direct in
  let four = float_literal #4.0s in
  let k_scaled = mul k four in
  let a_minus_b = sub a b in
  let abs_diff = abs a_minus_b in
  let k_minus_abs = sub k_scaled abs_diff in
  let zero = float_literal #0.0s in
  let h = max k_minus_abs zero in
  let h_sq = mul h h in
  let quarter = float_literal #0.25s in
  let h_sq_quarter = mul h_sq quarter in
  let correction = div h_sq_quarter k_scaled in
  let min_ab = min a b in
  sub min_ab correction
;;

let build_sdf () =
  let open Sdf.Expr_tree.Direct in
  let k = float_literal #10.0s in
  let c1 = build_circle_sdf ~cx:#150.0s ~cy:#150.0s ~r:#80.0s in
  let c2 = build_circle_sdf ~cx:#250.0s ~cy:#200.0s ~r:#80.0s in
  smooth_union ~k c1 c2
;;

type compiled_sdf =
  { instructions : (int * Sdf.Expr_graph.instr) list
  ; final_register : int
  ; register_count : int
  ; x_idx : int
  ; y_idx : int
  ; num_vars : int
  }

let compile_sdf () =
  let tree = build_sdf () in
  let ~instructions, ~final_register, ~register_count, ~var_mapping =
    Sdf.Expr_graph.from_tree tree
  in
  let x_idx = Hashtbl.find_exn var_mapping "x" in
  let y_idx = Hashtbl.find_exn var_mapping "y" in
  let num_vars = Hashtbl.length var_mapping in
  { instructions; final_register; register_count; x_idx; y_idx; num_vars }
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
    Parallel.for_ par ~start:0 ~stop:width ~f:(fun _par x ->
      let variables = Sdf.Value.Array.create ~len:num_vars in
      let registers = Sdf.Value.Array.create ~len:register_count in
      Sdf.Value.Array.set_float variables x_idx (Float32_u.of_float (Float.of_int x));
      for y = 0 to height - 1 do
        Sdf.Value.Array.set_float variables y_idx (Float32_u.of_float (Float.of_int y));
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
  let window = Winit.create () in
  let surface = Softbuffer.create (Winit.get_handle window) in
  let state = create_state () in
  let sdf = compile_sdf () in
  let scheduler = Parallel_scheduler.create () in
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
    draw_shape state sdf scheduler;
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
