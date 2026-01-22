open Winit_softbuffer

let () =
  Printf.printf "Creating window...\n%!";
  let app = create () in
  Printf.printf "Window created! Version: %d\n%!" (test_version ());
  Printf.printf "Running for 180 frames (~3 seconds)...\n%!";
  let frame = ref 0 in
  let should_exit = ref false in
  while !frame < 180 && not !should_exit do
    (* Pump events *)
    let events = pump_events app in
    (* Process events - EXHAUSTIVE printing for testing *)
    List.iter
      (fun event ->
        match event with
        | CloseRequested ->
          Printf.printf "Frame %d: CloseRequested\n%!" !frame;
          should_exit := true
        | SurfaceResized { width; height } ->
          Printf.printf
            "Frame %d: SurfaceResized { width=%d; height=%d }\n%!"
            !frame
            width
            height
        | RedrawRequested -> () (* Printf.printf "Frame %d: RedrawRequested\n%!" !frame *)
        | KeyPressed { key_code; location; repeat } ->
          Printf.printf
            "Frame %d: KeyPressed { key_code=%d; location=%s; repeat=%b }\n%!"
            !frame
            key_code
            (match location with
             | Standard -> "Standard"
             | Left -> "Left"
             | Right -> "Right"
             | Numpad -> "Numpad")
            repeat
        | KeyReleased { key_code; location; repeat } ->
          Printf.printf
            "Frame %d: KeyReleased { key_code=%d; location=%s; repeat=%b }\n%!"
            !frame
            key_code
            (match location with
             | Standard -> "Standard"
             | Left -> "Left"
             | Right -> "Right"
             | Numpad -> "Numpad")
            repeat
        | ModifiersChanged { shift; control; alt; super } ->
          Printf.printf
            "Frame %d: ModifiersChanged { shift=%s; control=%s; alt=%s; super=%s }\n%!"
            !frame
            (match shift with
             | Unknown -> "Unknown"
             | LeftPressed -> "LeftPressed"
             | RightPressed -> "RightPressed"
             | BothPressed -> "BothPressed")
            (match control with
             | Unknown -> "Unknown"
             | LeftPressed -> "LeftPressed"
             | RightPressed -> "RightPressed"
             | BothPressed -> "BothPressed")
            (match alt with
             | Unknown -> "Unknown"
             | LeftPressed -> "LeftPressed"
             | RightPressed -> "RightPressed"
             | BothPressed -> "BothPressed")
            (match super with
             | Unknown -> "Unknown"
             | LeftPressed -> "LeftPressed"
             | RightPressed -> "RightPressed"
             | BothPressed -> "BothPressed")
        | PointerMoved { x; y; primary; source } ->
          (match source with
           | Mouse ->
             Printf.printf
               "Frame %d: PointerMoved { x=%.2f; y=%.2f; primary=%b; source=Mouse }\n%!"
               !frame
               x
               y
               primary
           | Touch ->
             Printf.printf
               "Frame %d: PointerMoved { x=%.2f; y=%.2f; primary=%b; source=Touch }\n%!"
               !frame
               x
               y
               primary
           | Tablet { pressure; tilt_x; tilt_y; tool_kind } ->
             Printf.printf
               "Frame %d: PointerMoved { x=%.2f; y=%.2f; primary=%b; source=Tablet { \
                tool=%s; pressure=%s; tilt_x=%s; tilt_y=%s } }\n\
                %!"
               !frame
               x
               y
               primary
               (match tool_kind with
                | Pen -> "Pen"
                | Eraser -> "Eraser"
                | Brush -> "Brush"
                | Pencil -> "Pencil"
                | Airbrush -> "Airbrush"
                | Finger -> "Finger"
                | TabletMouse -> "TabletMouse"
                | Lens -> "Lens")
               (match pressure with
                | Some p -> Printf.sprintf "%.3f" p
                | None -> "None")
               (match tilt_x with
                | Some t -> Printf.sprintf "%d°" t
                | None -> "None")
               (match tilt_y with
                | Some t -> Printf.sprintf "%d°" t
                | None -> "None")
           | Unknown ->
             Printf.printf
               "Frame %d: PointerMoved { x=%.2f; y=%.2f; primary=%b; source=Unknown }\n%!"
               !frame
               x
               y
               primary)
        | PointerEntered { x; y; primary; source } ->
          (match source with
           | Tablet { tool_kind; _ } ->
             Printf.printf
               "Frame %d: PointerEntered { x=%.2f; y=%.2f; primary=%b; source=Tablet(%s) }\n\
                %!"
               !frame
               x
               y
               primary
               (match tool_kind with
                | Pen -> "Pen"
                | Eraser -> "Eraser"
                | _ -> "Other")
           | _ ->
             Printf.printf
               "Frame %d: PointerEntered { x=%.2f; y=%.2f; primary=%b; source=%s }\n%!"
               !frame
               x
               y
               primary
               (match source with
                | Mouse -> "Mouse"
                | Touch -> "Touch"
                | Unknown -> "Unknown"
                | _ -> "Other"))
        | PointerLeft { x; y; primary; source } ->
          (match source with
           | Tablet { tool_kind; _ } ->
             Printf.printf
               "Frame %d: PointerLeft { x=%.2f; y=%.2f; primary=%b; source=Tablet(%s) }\n\
                %!"
               !frame
               x
               y
               primary
               (match tool_kind with
                | Pen -> "Pen"
                | Eraser -> "Eraser"
                | _ -> "Other")
           | _ ->
             Printf.printf
               "Frame %d: PointerLeft { x=%.2f; y=%.2f; primary=%b; source=%s }\n%!"
               !frame
               x
               y
               primary
               (match source with
                | Mouse -> "Mouse"
                | Touch -> "Touch"
                | Unknown -> "Unknown"
                | _ -> "Other"))
        | PointerButtonPressed { button; x; y; primary } ->
          Printf.printf
            "Frame %d: PointerButtonPressed { button=%d; x=%.2f; y=%.2f; primary=%b }\n%!"
            !frame
            button
            x
            y
            primary
        | PointerButtonReleased { button; x; y; primary } ->
          Printf.printf
            "Frame %d: PointerButtonReleased { button=%d; x=%.2f; y=%.2f; primary=%b }\n\
             %!"
            !frame
            button
            x
            y
            primary
        | MouseWheel { delta_type; x; y; phase } ->
          Printf.printf
            "Frame %d: MouseWheel { delta_type=%s; x=%.2f; y=%.2f; phase=%s }\n%!"
            !frame
            (match delta_type with
             | Line -> "Line"
             | Pixel -> "Pixel")
            x
            y
            (match phase with
             | Started -> "Started"
             | Moved -> "Moved"
             | Ended -> "Ended"
             | Cancelled -> "Cancelled")
        | Focused -> Printf.printf "Frame %d: Focused\n%!" !frame
        | Unfocused -> Printf.printf "Frame %d: Unfocused\n%!" !frame
        | WindowMoved { x; y } ->
          Printf.printf "Frame %d: WindowMoved { x=%d; y=%d }\n%!" !frame x y
        | Destroyed -> Printf.printf "Frame %d: Destroyed\n%!" !frame
        | Occluded -> Printf.printf "Frame %d: Occluded\n%!" !frame
        | Unoccluded -> Printf.printf "Frame %d: Unoccluded\n%!" !frame
        | ThemeChanged theme ->
          Printf.printf
            "Frame %d: ThemeChanged %s\n%!"
            !frame
            (match theme with
             | Light -> "Light"
             | Dark -> "Dark")
        | ScaleFactorChanged scale ->
          Printf.printf "Frame %d: ScaleFactorChanged %.2f\n%!" !frame scale
        | NoEvent -> ())
      events;
    (* Get buffer and draw *)
    let width, height, buffer = get_buffer app in
    (* Draw a gradient that changes with frame number *)
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let index = (y * width) + x in
        let red = Int32.of_int ((x + !frame) mod 256) in
        let green = Int32.of_int ((y + (!frame / 2)) mod 256) in
        let blue = Int32.of_int (!frame mod 256) in
        let color =
          Int32.logor
            (Int32.logor blue (Int32.shift_left green 8))
            (Int32.shift_left red 16)
        in
        Bigarray.Array1.set buffer index color
      done
    done;
    (* Present *)
    present app;
    (* Limit to ~60 FPS *)
    Unix.sleepf 0.016;
    incr frame
  done;
  Printf.printf "Drew %d frames. Exiting.\n%!" !frame
;;
