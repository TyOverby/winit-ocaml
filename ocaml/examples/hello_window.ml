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
    (* Process events *)
    List.iter
      (fun event ->
        match event with
        | CloseRequested ->
          Printf.printf "Frame %d: Close requested\n%!" !frame;
          should_exit := true
        | SurfaceResized { width; height } ->
          Printf.printf "Frame %d: Resized to %dx%d\n%!" !frame width height
        | KeyPressed { key_code; location; repeat } ->
          Printf.printf
            "Frame %d: Key %d pressed (location=%s, repeat=%b)\n%!"
            !frame
            key_code
            (match location with
             | Standard -> "standard"
             | Left -> "left"
             | Right -> "right"
             | Numpad -> "numpad")
            repeat
        | PointerButtonPressed { button; x; y; primary = _ } ->
          Printf.printf
            "Frame %d: Mouse button %d pressed at (%.1f, %.1f)\n%!"
            !frame
            button
            x
            y
        | ModifiersChanged { shift; control; alt; super = _ } ->
          Printf.printf
            "Frame %d: Modifiers changed (shift=%s, ctrl=%s, alt=%s)\n%!"
            !frame
            (match shift with
             | Unknown -> "unknown"
             | LeftPressed -> "left"
             | RightPressed -> "right"
             | BothPressed -> "both")
            (match control with
             | Unknown -> "unknown"
             | LeftPressed -> "left"
             | RightPressed -> "right"
             | BothPressed -> "both")
            (match alt with
             | Unknown -> "unknown"
             | LeftPressed -> "left"
             | RightPressed -> "right"
             | BothPressed -> "both")
        | _ -> ())
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
