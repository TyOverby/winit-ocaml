open! Core
module Atomic = Basement.Portable_atomic

module Arg = struct
  type t =
    | Int of int
    | Float of float
    | String of string
    | Bool of bool
  [@@deriving sexp_of]
end

(* Raw events recorded into a lane's private buffer. Timestamps are nanoseconds since the
   trace's start. *)
module Event = struct
  type t =
    | Begin of
        { name : string
        ; args : (string * Arg.t) list
        ; ts : int
        }
    | End of { ts : int }
end

(* A completed lane, as joined into the shared sink. Immutable, so it crosses contention
   and portability and can be pushed through an atomic. *)
module Lane = struct
  type t =
    { id : int
    ; parent_lane : int (* -1 for the root lane *)
    ; parent_begin : int (* event index in the parent lane; -1 = lane root *)
    ; wrap_name : string option
    ; start_ts : int
    ; end_ts : int
    ; events : Event.t list (* in recording order *)
    }
end

(* Shared, domain-crossing state of a live trace. The only mutable pieces are atomics;
   joined lanes are CAS-pushed onto [lanes]. *)
module Sink = struct
  type t =
    { name : string option
    ; start_ns : int (* epoch ns at [create], the zero point for all [ts] *)
    ; started_at : Time_ns.Alternate_sexp.t
    ; live : bool Atomic.t
    ; next_lane : int Atomic.t
    ; lanes : Lane.t list Atomic.t
    }
end

type t =
  { sink : Sink.t option (* [None] for [null] writers *)
  ; lane_id : int
  ; is_root : bool
  ; mutable events_rev : Event.t list
  ; mutable n_events : int
  ; mutable open_stack : int list (* indices of currently-open [Begin]s *)
  }

let[@inline] now (sink : Sink.t) =
  Int63.to_int_exn (Time_now.nanoseconds_since_unix_epoch ()) - sink.start_ns
;;

let null_writer ~is_root =
  { sink = None; lane_id = -1; is_root; events_rev = []; n_events = 0; open_stack = [] }
;;

let null () = null_writer ~is_root:true

let create ?name () =
  let start_ns = Int63.to_int_exn (Time_now.nanoseconds_since_unix_epoch ()) in
  let sink =
    { Sink.name
    ; start_ns
    ; started_at = Time_ns.of_int63_ns_since_epoch (Int63.of_int start_ns)
    ; live = Atomic.make true
    ; next_lane = Atomic.make 1
    ; lanes = Atomic.make []
    }
  in
  { sink = Some sink
  ; lane_id = 0
  ; is_root = true
  ; events_rev = []
  ; n_events = 0
  ; open_stack = []
  }
;;

let is_recording t =
  match t.sink with
  | None -> false
  | Some sink -> Atomic.get sink.live
;;

let span ?(args = []) t name ~f =
  match t.sink with
  | None -> f ()
  | Some sink ->
    if not (Atomic.get sink.live)
    then f ()
    else (
      let idx = t.n_events in
      t.events_rev <- Begin { name; args; ts = now sink } :: t.events_rev;
      t.n_events <- idx + 1;
      t.open_stack <- idx :: t.open_stack;
      let close () =
        t.events_rev <- End { ts = now sink } :: t.events_rev;
        t.n_events <- t.n_events + 1;
        match t.open_stack with
        | [] -> ()
        | _ :: rest -> t.open_stack <- rest
      in
      match f () with
      | x ->
        close ();
        x
      | exception exn ->
        close ();
        raise exn)
;;

module Fork = struct
  type t =
    | Inert
    | Live of
        { sink : Sink.t
        ; lane : int
        ; begin_idx : int (* -1 = the forking lane's root *)
        }
end

let fork t : Fork.t =
  match t.sink with
  | None -> Inert
  | Some sink ->
    if not (Atomic.get sink.live)
    then Inert
    else (
      let begin_idx =
        match t.open_stack with
        | [] -> -1
        | idx :: _ -> idx
      in
      Live { sink; lane = t.lane_id; begin_idx })
;;

let with_fork ?name (fk : Fork.t) ~f =
  match fk with
  | Inert -> f (null_writer ~is_root:false)
  | Live { sink; lane = parent_lane; begin_idx = parent_begin } ->
    if not (Atomic.get sink.live)
    then f (null_writer ~is_root:false)
    else (
      let id = Atomic.fetch_and_add sink.next_lane 1 in
      let start_ts = now sink in
      let w =
        { sink = Some sink
        ; lane_id = id
        ; is_root = false
        ; events_rev = []
        ; n_events = 0
        ; open_stack = []
        }
      in
      let join () =
        let lane =
          { Lane.id
          ; parent_lane
          ; parent_begin
          ; wrap_name = name
          ; start_ts
          ; end_ts = now sink
          ; events = List.rev w.events_rev
          }
        in
        let rec push () =
          let cur = Atomic.get sink.lanes in
          if not (Atomic.compare_and_set sink.lanes cur (lane :: cur)) then push ()
        in
        push ()
      in
      match f w with
      | x ->
        join ();
        x
      | exception exn ->
        join ();
        raise exn)
;;

module Captured = struct
  module Span = struct
    type t =
      { name : string
      ; args : (string * Arg.t) list
      ; start : Time_ns.Span.t
      ; duration : Time_ns.Span.t
      ; lane : int
      ; children : t list
      }
    [@@deriving sexp_of]
  end

  type t =
    { name : string option
    ; started_at : Time_ns.Alternate_sexp.t
    ; duration : Time_ns.Span.t
    ; roots : Span.t list
    }
  [@@deriving sexp_of]
end

(* Pure post-processing: turn the bag of joined lanes back into one span forest. Each lane
   replays into a tree; lanes then attach beneath the span their fork captured (or beneath
   their parent lane's wrap/attachment point when the fork was captured outside any span). *)
module Assemble = struct
  module Node = struct
    type t =
      { name : string
      ; args : (string * Arg.t) list
      ; start : int
      ; mutable dur : int
      ; lane : int
      ; mutable children_rev : t list
      }
  end

  let parse_lane (lane : Lane.t) ~node_of_begin =
    let roots_rev : Node.t list ref = ref [] in
    let stack : Node.t list ref = ref [] in
    let idx = ref 0 in
    List.iter lane.events ~f:(fun ev ->
      (match ev with
       | Event.Begin { name; args; ts } ->
         (* Until its [End] arrives, a span conservatively extends to the end of its lane. *)
         let node =
           { Node.name
           ; args
           ; start = ts
           ; dur = lane.end_ts - ts
           ; lane = lane.id
           ; children_rev = []
           }
         in
         Hashtbl.set node_of_begin ~key:(lane.id, !idx) ~data:node;
         (match !stack with
          | parent :: _ -> parent.Node.children_rev <- node :: parent.children_rev
          | [] -> roots_rev := node :: !roots_rev);
         stack := node :: !stack
       | End { ts } ->
         (match !stack with
          | top :: rest ->
            top.Node.dur <- ts - top.start;
            stack := rest
          | [] -> ()));
      incr idx);
    List.rev !roots_rev
  ;;

  let rec freeze (n : Node.t) : Captured.Span.t =
    let children =
      List.rev_map n.children_rev ~f:freeze
      |> List.sort ~compare:(fun (a : Captured.Span.t) b ->
        Time_ns.Span.compare a.start b.start)
    in
    { name = n.name
    ; args = n.args
    ; start = Time_ns.Span.of_int_ns n.start
    ; duration = Time_ns.Span.of_int_ns (max n.dur 0)
    ; lane = n.lane
    ; children
    }
  ;;

  let captured ~name ~started_at ~end_ts (lanes : Lane.t list) : Captured.t =
    let node_of_begin = Hashtbl.Poly.create () in
    let lane_by_id = Hashtbl.create (module Int) in
    let lane_roots = Hashtbl.create (module Int) in
    let wrap_node = Hashtbl.create (module Int) in
    List.iter lanes ~f:(fun l -> Hashtbl.set lane_by_id ~key:l.Lane.id ~data:l);
    List.iter lanes ~f:(fun l ->
      Hashtbl.set lane_roots ~key:l.Lane.id ~data:(parse_lane l ~node_of_begin));
    List.iter lanes ~f:(fun l ->
      match l.wrap_name with
      | None -> ()
      | Some wrap ->
        let node =
          { Node.name = wrap
          ; args = []
          ; start = l.start_ts
          ; dur = l.end_ts - l.start_ts
          ; lane = l.id
          ; children_rev = List.rev (Hashtbl.find_exn lane_roots l.id)
          }
        in
        Hashtbl.set wrap_node ~key:l.id ~data:node);
    let trace_roots_rev : Node.t list ref = ref [] in
    (* Where do a lane's root-level spans land? Normally on the span its fork captured; a
       fork captured outside any span chases up through the parent lane. [depth] guards
       against cycles from corrupt input. *)
    let rec attach_target (l : Lane.t) ~depth =
      if depth > 10_000 || l.parent_lane < 0
      then `Roots
      else if l.parent_begin >= 0
      then (
        match Hashtbl.find node_of_begin (l.parent_lane, l.parent_begin) with
        | Some n -> `Node n
        | None -> `Roots)
      else (
        match Hashtbl.find wrap_node l.parent_lane with
        | Some n -> `Node n
        | None ->
          (match Hashtbl.find lane_by_id l.parent_lane with
           | None -> `Roots
           | Some parent -> attach_target parent ~depth:(depth + 1)))
    in
    List.iter lanes ~f:(fun l ->
      let exported =
        match Hashtbl.find wrap_node l.id with
        | Some w -> [ w ]
        | None -> Hashtbl.find_exn lane_roots l.id
      in
      let target = if l.id = 0 then `Roots else attach_target l ~depth:0 in
      List.iter exported ~f:(fun n ->
        match target with
        | `Roots -> trace_roots_rev := n :: !trace_roots_rev
        | `Node p -> p.Node.children_rev <- n :: p.Node.children_rev));
    let roots =
      List.rev_map !trace_roots_rev ~f:freeze
      |> List.sort ~compare:(fun (a : Captured.Span.t) b ->
        Time_ns.Span.compare a.start b.start)
    in
    { Captured.name; started_at; duration = Time_ns.Span.of_int_ns end_ts; roots }
  ;;
end

let empty_captured =
  { Captured.name = None
  ; started_at = Time_ns.epoch
  ; duration = Time_ns.Span.zero
  ; roots = []
  }
;;

let finish t =
  match t.sink with
  | None -> empty_captured
  | Some sink ->
    if not t.is_root
    then failwith "Phase_trace.finish: called on a writer that did not come from [create]";
    if not (Atomic.exchange sink.live false)
    then failwith "Phase_trace.finish: trace already finished";
    let end_ts = now sink in
    let lane0 =
      { Lane.id = 0
      ; parent_lane = -1
      ; parent_begin = -1
      ; wrap_name = None
      ; start_ts = 0
      ; end_ts
      ; events = List.rev t.events_rev
      }
    in
    let lanes = lane0 :: Atomic.exchange sink.lanes [] in
    Assemble.captured ~name:sink.name ~started_at:sink.started_at ~end_ts lanes
;;

module Summary = struct
  type t =
    { name : string
    ; count : int
    ; total : Time_ns.Span.t
    ; self : Time_ns.Span.t
    ; max : Time_ns.Span.t
    ; children : t list
    }
  [@@deriving sexp_of]

  let rec summarize (spans : Captured.Span.t list) : t list =
    let groups = Hashtbl.create (module String) in
    let order_rev = ref [] in
    List.iter spans ~f:(fun s ->
      match Hashtbl.find groups s.name with
      | Some rest -> Hashtbl.set groups ~key:s.name ~data:(s :: rest)
      | None ->
        order_rev := s.name :: !order_rev;
        Hashtbl.set groups ~key:s.name ~data:[ s ]);
    List.rev_map !order_rev ~f:(fun name ->
      let instances = List.rev (Hashtbl.find_exn groups name) in
      let count = List.length instances in
      let total =
        List.fold instances ~init:Time_ns.Span.zero ~f:(fun acc s ->
          Time_ns.Span.( + ) acc s.duration)
      in
      let max =
        List.fold instances ~init:Time_ns.Span.zero ~f:(fun acc s ->
          Time_ns.Span.max acc s.duration)
      in
      let children = summarize (List.concat_map instances ~f:(fun s -> s.children)) in
      let child_total =
        List.fold children ~init:Time_ns.Span.zero ~f:(fun acc c ->
          Time_ns.Span.( + ) acc c.total)
      in
      let self =
        Time_ns.Span.max Time_ns.Span.zero (Time_ns.Span.( - ) total child_total)
      in
      { name; count; total; self; max; children })
  ;;

  let of_captured (captured : Captured.t) = summarize captured.roots

  let to_string_hum ?max_depth ts =
    let buf = Buffer.create 256 in
    let span_str s = Time_ns.Span.to_string_hum ~decimals:2 s in
    let rec go depth ~parent_total ts =
      let truncated =
        match max_depth with
        | Some d -> depth >= d
        | None -> false
      in
      if not truncated
      then
        List.sort ts ~compare:(fun a b -> Time_ns.Span.compare b.total a.total)
        |> List.iter ~f:(fun t ->
          let pct =
            match parent_total with
            | Some p when Time_ns.Span.( > ) p Time_ns.Span.zero ->
              sprintf
                " (%.0f%%)"
                (100. *. (Time_ns.Span.to_ns t.total /. Time_ns.Span.to_ns p))
            | _ -> ""
          in
          Buffer.add_string
            buf
            (sprintf
               "%s%s: count=%d total=%s self=%s max=%s%s\n"
               (String.make (depth * 2) ' ')
               t.name
               t.count
               (span_str t.total)
               (span_str t.self)
               (span_str t.max)
               pct);
          go (depth + 1) ~parent_total:(Some t.total) t.children)
    in
    go 0 ~parent_total:None ts;
    Buffer.contents buf
  ;;
end
