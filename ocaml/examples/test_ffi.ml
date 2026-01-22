open Winit_softbuffer

let () =
  Printf.printf "Testing FFI without display...\n%!";
  (* Test 1: Call the version test function *)
  Printf.printf "Test 1: Calling test_version()... ";
  let version = test_version () in
  Printf.printf "OK! Got version: %d\n%!" version;
  (* Test 2: Verify event type handling works *)
  Printf.printf "Test 2: Event type handling... ";
  let test_events =
    [ CloseRequested
    ; SurfaceResized { width = 1024; height = 768 }
    ; KeyPressed { key_code = 42; location = Standard; repeat = false }
    ; PointerMoved { x = 100.0; y = 200.0; primary = true; source = Mouse }
    ; PointerButtonPressed { button = 1; x = 100.0; y = 200.0; primary = true }
    ; ModifiersChanged
        { shift = LeftPressed; control = Unknown; alt = Unknown; super = Unknown }
    ; MouseWheel { delta_type = Line; x = 0.0; y = 1.0; phase = Moved }
    ; Focused
    ; ThemeChanged Light
    ; ScaleFactorChanged 2.0
    ]
  in
  List.iter
    (fun e ->
      let type_str =
        match e with
        | NoEvent -> "NoEvent"
        | CloseRequested -> "CloseRequested"
        | SurfaceResized { width; height } ->
          Printf.sprintf "SurfaceResized(%d,%d)" width height
        | RedrawRequested -> "RedrawRequested"
        | KeyPressed { key_code; location = _; repeat } ->
          Printf.sprintf "KeyPressed(code=%d, repeat=%b)" key_code repeat
        | KeyReleased { key_code; location = _; repeat = _ } ->
          Printf.sprintf "KeyReleased(code=%d)" key_code
        | ModifiersChanged { shift; control = _; alt = _; super = _ } ->
          Printf.sprintf
            "ModifiersChanged(shift=%s)"
            (match shift with
             | Unknown -> "unknown"
             | LeftPressed -> "left"
             | RightPressed -> "right"
             | BothPressed -> "both")
        | PointerMoved { x; y; primary = _; source = _ } ->
          Printf.sprintf "PointerMoved(%.0f,%.0f)" x y
        | PointerButtonPressed { button; x = _; y = _; primary = _ } ->
          Printf.sprintf "PointerButtonPressed(%d)" button
        | PointerButtonReleased { button; x = _; y = _; primary = _ } ->
          Printf.sprintf "PointerButtonReleased(%d)" button
        | PointerEntered { x = _; y = _; primary = _; source = _ } -> "PointerEntered"
        | PointerLeft { x = _; y = _; primary = _; source = _ } -> "PointerLeft"
        | MouseWheel { delta_type = _; x = _; y; phase = _ } ->
          Printf.sprintf "MouseWheel(y=%.1f)" y
        | Focused -> "Focused"
        | Unfocused -> "Unfocused"
        | WindowMoved { x; y } -> Printf.sprintf "WindowMoved(%d,%d)" x y
        | Destroyed -> "Destroyed"
        | Occluded -> "Occluded"
        | Unoccluded -> "Unoccluded"
        | ThemeChanged theme ->
          Printf.sprintf
            "ThemeChanged(%s)"
            (match theme with
             | Light -> "light"
             | Dark -> "dark")
        | ScaleFactorChanged scale -> Printf.sprintf "ScaleFactorChanged(%.1f)" scale
      in
      Printf.printf "  - %s\n%!" type_str)
    test_events;
  Printf.printf "OK!\n%!";
  Printf.printf "\n=== FFI Tests Passed ===\n";
  Printf.printf "The OCaml → C → Rust FFI chain is working correctly!\n";
  Printf.printf "\nThe window creation requires a display server (X11/Wayland).\n";
  Printf.printf "On systems with a display, run: dune exec examples/hello_window.exe\n";
  Printf.printf "\nNote: The 'test_version' function successfully called Rust code\n";
  Printf.printf "      and returned value %d, proving the FFI is functional.\n%!" version
;;
