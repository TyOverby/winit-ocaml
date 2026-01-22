(** OCaml bindings for winit and softbuffer *)

type app

type event_type =
  | NoEvent
  | CloseRequested
  | Resized
  | RedrawRequested
  | KeyPressed
  | KeyReleased
  | MouseMoved
  | MouseButtonPressed
  | MouseButtonReleased

let event_type_of_int = function
  | 0 -> NoEvent
  | 1 -> CloseRequested
  | 2 -> Resized
  | 3 -> RedrawRequested
  | 4 -> KeyPressed
  | 5 -> KeyReleased
  | 6 -> MouseMoved
  | 7 -> MouseButtonPressed
  | 8 -> MouseButtonReleased
  | _ -> NoEvent

type event = {
  event_type : event_type;
  data1 : int;
  data2 : int;
}

(* External C stubs *)
external winit_create : unit -> app = "caml_winit_create"
external winit_pump_events_raw : app -> (int * int * int) array = "caml_winit_pump_events"
external get_buffer : app -> (int * int * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t) = "caml_winit_get_buffer"
external present : app -> unit = "caml_winit_present"
external test_version : unit -> int = "caml_winit_test_version"

let create = winit_create

let pump_events app =
  let raw_events = winit_pump_events_raw app in
  Array.to_list (Array.map (fun (et, d1, d2) ->
    { event_type = event_type_of_int et; data1 = d1; data2 = d2 }
  ) raw_events)
