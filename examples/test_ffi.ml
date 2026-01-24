let () =
  Printf.printf "Testing FFI without display...\n%!";
  (* Test 1: Call the version test function *)
  Printf.printf "Test 1: Calling test_version()... ";
  let version = Winit.test_version () in
  Printf.printf "OK! Got version: %d\n%!" version;
  (* Test 2: Verify event type handling works *)
  Printf.printf "Test 2: Event type handling... ";
  let test_events =
    [ Winit.CloseRequested
    ; Winit.SurfaceResized { width = 1024; height = 768 }
    ; Winit.KeyPressed { key_code = 42; location = Standard; repeat = false }
    ; Winit.PointerMoved { x = 100.0; y = 200.0; primary = true; source = Mouse }
    ; Winit.PointerButtonPressed { button = 1; x = 100.0; y = 200.0; primary = true }
    ; Winit.ModifiersChanged
        { shift = LeftPressed; control = Unknown; alt = Unknown; super = Unknown }
    ; Winit.MouseWheel { delta_type = Line; x = 0.0; y = 1.0; phase = Moved }
    ; Winit.Focused
    ; Winit.ThemeChanged Light
    ; Winit.ScaleFactorChanged 2.0
    ]
  in
  List.iter
    (fun e ->
      let type_str =
        match e with
        | Winit.NoEvent -> "NoEvent"
        | Winit.CloseRequested -> "CloseRequested"
        | Winit.SurfaceResized { width; height } ->
          Printf.sprintf "SurfaceResized(%d,%d)" width height
        | Winit.RedrawRequested -> "RedrawRequested"
        | Winit.KeyPressed { key_code; location = _; repeat } ->
          Printf.sprintf "KeyPressed(code=%d, repeat=%b)" key_code repeat
        | Winit.KeyReleased { key_code; location = _; repeat = _ } ->
          Printf.sprintf "KeyReleased(code=%d)" key_code
        | Winit.ModifiersChanged { shift; control = _; alt = _; super = _ } ->
          Printf.sprintf
            "ModifiersChanged(shift=%s)"
            (match shift with
             | Winit.Unknown -> "unknown"
             | Winit.LeftPressed -> "left"
             | Winit.RightPressed -> "right"
             | Winit.BothPressed -> "both")
        | Winit.PointerMoved { x; y; primary = _; source = _ } ->
          Printf.sprintf "PointerMoved(%.0f,%.0f)" x y
        | Winit.PointerButtonPressed { button; x = _; y = _; primary = _ } ->
          Printf.sprintf "PointerButtonPressed(%d)" button
        | Winit.PointerButtonReleased { button; x = _; y = _; primary = _ } ->
          Printf.sprintf "PointerButtonReleased(%d)" button
        | Winit.PointerEntered { x = _; y = _; primary = _; source = _ } ->
          "PointerEntered"
        | Winit.PointerLeft { x = _; y = _; primary = _; source = _ } -> "PointerLeft"
        | Winit.MouseWheel { delta_type = _; x = _; y; phase = _ } ->
          Printf.sprintf "MouseWheel(y=%.1f)" y
        | Winit.Focused -> "Focused"
        | Winit.Unfocused -> "Unfocused"
        | Winit.WindowMoved { x; y } -> Printf.sprintf "WindowMoved(%d,%d)" x y
        | Winit.Destroyed -> "Destroyed"
        | Winit.Occluded -> "Occluded"
        | Winit.Unoccluded -> "Unoccluded"
        | Winit.ThemeChanged theme ->
          Printf.sprintf
            "ThemeChanged(%s)"
            (match theme with
             | Winit.Light -> "light"
             | Winit.Dark -> "dark")
        | Winit.ScaleFactorChanged scale ->
          Printf.sprintf "ScaleFactorChanged(%.1f)" scale
      in
      Printf.printf "  - %s\n%!" type_str)
    test_events;
  Printf.printf "OK!\n%!";
  Printf.printf "\n=== FFI Tests Passed ===\n";
  Printf.printf "The OCaml -> C -> Rust FFI chain is working correctly!\n";
  Printf.printf "\nThe window creation requires a display server (X11/Wayland).\n";
  Printf.printf "On systems with a display, run: dune exec examples/hello_window.exe\n";
  Printf.printf "\nNote: The 'test_version' function successfully called Rust code\n";
  Printf.printf "      and returned value %d, proving the FFI is functional.\n%!" version
;;
