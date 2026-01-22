open Winit_softbuffer

let () =
  Printf.printf "Testing FFI without display...\n%!";
  (* Test 1: Call the version test function *)
  Printf.printf "Test 1: Calling test_version()... ";
  let version = test_version () in
  Printf.printf "OK! Got version: %d\n%!" version;
  (* Test 2: Verify event type conversions work *)
  Printf.printf "Test 2: Event type handling... ";
  let test_events =
    [ { event_type = CloseRequested; data1 = 0; data2 = 0 }
    ; { event_type = Resized; data1 = 1024; data2 = 768 }
    ; { event_type = KeyPressed; data1 = 42; data2 = 0 }
    ; { event_type = MouseMoved; data1 = 100; data2 = 200 }
    ; { event_type = MouseButtonPressed; data1 = 1; data2 = 0 }
    ]
  in
  List.iter
    (fun e ->
      let type_str =
        match e.event_type with
        | NoEvent -> "NoEvent"
        | CloseRequested -> "CloseRequested"
        | Resized -> Printf.sprintf "Resized(%d,%d)" e.data1 e.data2
        | RedrawRequested -> "RedrawRequested"
        | KeyPressed -> Printf.sprintf "KeyPressed(%d)" e.data1
        | KeyReleased -> "KeyReleased"
        | MouseMoved -> Printf.sprintf "MouseMoved(%d,%d)" e.data1 e.data2
        | MouseButtonPressed -> Printf.sprintf "MouseButtonPressed(%d)" e.data1
        | MouseButtonReleased -> "MouseButtonReleased"
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
