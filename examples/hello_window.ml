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
    List.iter (fun event ->
      match event.event_type with
      | CloseRequested ->
          Printf.printf "Frame %d: Close requested\n%!" !frame;
          should_exit := true
      | Resized ->
          Printf.printf "Frame %d: Resized to %dx%d\n%!" !frame event.data1 event.data2
      | KeyPressed ->
          Printf.printf "Frame %d: Key pressed\n%!" !frame
      | MouseButtonPressed ->
          Printf.printf "Frame %d: Mouse button %d pressed\n%!" !frame event.data1
      | _ -> ()
    ) events;

    (* Get buffer and draw *)
    let (width, height, buffer) = get_buffer app in

    (* Draw a gradient that changes with frame number *)
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let index = y * width + x in
        let red = Int32.of_int ((x + !frame) mod 256) in
        let green = Int32.of_int ((y + !frame / 2) mod 256) in
        let blue = Int32.of_int (!frame mod 256) in
        let color = Int32.logor (Int32.logor blue (Int32.shift_left green 8)) (Int32.shift_left red 16) in
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
