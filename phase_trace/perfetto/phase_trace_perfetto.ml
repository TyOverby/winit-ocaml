open! Core
module Trace = Tracing.Trace

let tracing_arg ((name, arg) : string * Phase_trace.Arg.t) : Trace.Arg.t =
  ( name
  , match arg with
    | Int i -> Int i
    | Float f -> Float f
    | String s -> String s
    | Bool b -> Interned (Bool.to_string b) )
;;

(* Each recorded lane gets packed onto a synthetic "thread" track: lane 0 is the main
   thread, and other lanes greedily share a track with any lane whose spans they don't
   overlap in time. A 1000-row parallel loop thus renders as roughly one track per domain. *)
module Packing = struct
  type interval =
    { lane : int
    ; start : Time_ns.Span.t
    ; stop : Time_ns.Span.t
    }

  let lane_intervals (roots : Phase_trace.Captured.Span.t list) =
    let bounds = Hashtbl.create (module Int) in
    let rec visit (s : Phase_trace.Captured.Span.t) =
      let stop = Time_ns.Span.( + ) s.start s.duration in
      Hashtbl.update bounds s.lane ~f:(function
        | None -> s.start, stop
        | Some (lo, hi) -> Time_ns.Span.min lo s.start, Time_ns.Span.max hi stop);
      List.iter s.children ~f:visit
    in
    List.iter roots ~f:visit;
    Hashtbl.to_alist bounds
    |> List.map ~f:(fun (lane, (start, stop)) -> { lane; start; stop })
    |> List.sort ~compare:(fun a b ->
      match Time_ns.Span.compare a.start b.start with
      | 0 -> Int.compare a.lane b.lane
      | c -> c)
  ;;

  (* Greedy interval partitioning; returns lane -> track index. Track 0 is reserved for
     lane 0. *)
  let assign (roots : Phase_trace.Captured.Span.t list) =
    let track_of_lane = Hashtbl.create (module Int) in
    Hashtbl.set track_of_lane ~key:0 ~data:0;
    let track_busy_until = ref [] in
    (* (track index, last stop) in track order *)
    List.iter (lane_intervals roots) ~f:(fun { lane; start; stop } ->
      if lane <> 0
      then (
        let rec place tracks =
          match tracks with
          | [] ->
            let idx = 1 + List.length !track_busy_until in
            Hashtbl.set track_of_lane ~key:lane ~data:idx;
            !track_busy_until @ [ idx, stop ]
          | (idx, busy_until) :: rest when Time_ns.Span.( <= ) busy_until start ->
            Hashtbl.set track_of_lane ~key:lane ~data:idx;
            (idx, stop) :: rest
          | head :: rest -> head :: place rest
        in
        track_busy_until := place !track_busy_until));
    track_of_lane
  ;;
end

let write_file (captured : Phase_trace.Captured.t) ~filename =
  let writer = Tracing_destinations_unix.file_writer ~filename () in
  let t = Trace.Expert.create ~base_time:(Some captured.started_at) writer in
  let pid =
    Trace.allocate_pid t ~name:(Option.value captured.name ~default:"phase_trace")
  in
  let track_of_lane = Packing.assign captured.roots in
  let thread_of_track = Hashtbl.create (module Int) in
  let thread_for_lane lane =
    let track = Hashtbl.find track_of_lane lane |> Option.value ~default:0 in
    Hashtbl.find_or_add thread_of_track track ~default:(fun () ->
      let name = if track = 0 then "main" else sprintf "track-%d" track in
      Trace.allocate_thread t ~pid ~name)
  in
  let rec write_span (s : Phase_trace.Captured.Span.t) =
    Trace.write_duration_complete
      t
      ~args:(List.map s.args ~f:tracing_arg)
      ~thread:(thread_for_lane s.lane)
      ~category:"phase"
      ~name:s.name
      ~time:s.start
      ~time_end:(Time_ns.Span.( + ) s.start s.duration);
    List.iter s.children ~f:write_span
  in
  List.iter captured.roots ~f:write_span;
  Trace.close t
;;
