@@ portable

open! Core

(** Broad-strokes hierarchical tracing for the sdf pipeline.

    [Phase_trace] records a tree of named, wall-clock-timed spans ("phases"), with
    explicit support for the [Parallel] fork/join style the executors use. It is meant for
    coarse instrumentation — pipeline passes, oracle preparation, tile scheduling, per-row
    batch evaluation — not per-pixel events: recording a span costs one clock read and an
    unsynchronized buffer push on the owning thread.

    {2 Model}

    A {!t} is a {e writer}: a handle owned by exactly one thread, holding a private event
    buffer. Nesting {!span} calls on a writer is what records dependencies ("this
    batch-eval ran inside this resample-oracle preparation").

    To cross into parallel code, {!fork} captures the writer's current position as a
    {!Fork.t}, which {e is} safe to share across domains (its kind crosses portability and
    contention). Each {!with_fork} invocation opens a fresh writer — a {e lane} — whose
    spans attach beneath the captured position. Tasks write to their own lanes with no
    synchronization, and each lane synchronizes exactly once (a lock-free atomic push onto
    the trace's shared sink) when it is joined at the end of [with_fork]. The mode system
    enforces the discipline: [t] cannot be captured by a [Parallel] task closure, [Fork.t]
    can.

    {!finish} assembles everything into a {!Captured.t} tree. That tree can be collapsed
    into a {!Summary} — siblings merged by name, so a parallel loop's thousand row-lanes
    report as one line with [count = 1000] — or exported to Perfetto via
    [Phase_trace_perfetto] (separate library), which preserves the full lane-level detail.

    {2 Example}

    {[
      let trace = Phase_trace.create ~name:"render" () in
      Phase_trace.span trace "prepare-oracles" ~f:(fun () -> ...);
      let fk = Phase_trace.fork trace in
      Parallel.for_ par ~start:0 ~stop:height ~f:(fun _par y ->
        Phase_trace.with_fork fk ~name:"row" ~f:(fun trace ->
          Phase_trace.span trace "batch-eval" ~f:(fun () -> ...)));
      let captured = Phase_trace.finish trace in
      print_endline
        (Phase_trace.Summary.to_string_hum
           (Phase_trace.Summary.of_captured captured))
    ]} *)

module Arg : sig
  (** Auxiliary data attached to a span — region dimensions, instruction counts, oracle
      names. Carried through to Perfetto's argument pane; ignored by summaries. *)
  type t =
    | Int of int
    | Float of float
    | String of string
    | Bool of bool
  [@@deriving sexp_of]
end

(** A trace writer. Owned by the thread that created it; recording on it is unsynchronized
    and not thread-safe, which the mode system enforces — [t] does not mode-cross
    portability or contention, so a [Parallel] task closure cannot capture one. To record
    from parallel tasks, see {!fork} / {!with_fork}. *)
type t

(** [create ()] starts a live trace and returns its root writer. [name] labels the trace
    in summaries and as the Perfetto process name. *)
val create : ?name:string -> unit -> t

(** A writer that records nothing, for tracing-disabled configurations. All operations on
    it (and on forks of it) are cheap no-ops; {!finish} returns an empty capture.
    Instrumented code never needs to know whether its writer is live. *)
val null : unit -> t

(** [false] on {!null} writers and after {!finish}. Use to skip computing expensive [args]
    when nobody is listening. *)
val is_recording : t -> bool

(** [span t name ~f] runs [f] and records a span covering its execution, nested inside the
    span currently open on [t] (if any). If [f] raises, the span is closed at the raise
    point and the exception is re-raised.

    [f] is taken at [local once] (it is called exactly once and never escapes), so the
    body may close over local values — notably a [Parallel.t @ local] — and once values. *)
val span : ?args:(string * Arg.t) list -> t -> string -> f:(unit -> 'a) @ local once -> 'a

(** [add_args t args] appends [args] to the span currently open on [t] — for data only
    known once the phase has started or finished its work, e.g. how many tiles a
    scheduling pass culled. No-op when no span is open or [t] is not recording. *)
val add_args : t -> (string * Arg.t) list -> unit

module Fork : sig
  (** A capture of a writer's current position that can cross into parallel tasks: the
      kind annotation lets a [Parallel.for_] closure capture it, where the writer itself
      cannot be. A single [Fork.t] may be used by any number of tasks concurrently. *)
  type t : value mod contended portable
end

(** [fork t] captures [t]'s currently-open span as the attachment point for lanes
    subsequently opened with {!with_fork}. The fork of a {!null} writer is inert. *)
val fork : t -> Fork.t

(** [with_fork fk ~f] opens a fresh lane writer, runs [f] with it, then joins the lane
    back into the trace (the only synchronized step: one lock-free atomic push). Spans
    recorded on the lane attach beneath the span captured by {!fork}; when [name] is given
    they are additionally wrapped in a span of that name, timed over the whole [with_fork]
    call.

    Safe to call concurrently from many tasks sharing one [Fork.t]. The lane writer must
    not escape [f]. If [f] raises, the lane is still joined and the exception re-raised.

    As with {!span}, [f] is taken at [local once] so that, inside a [Parallel.for_] task,
    the lane body can close over the task's [Parallel.t @ local] (e.g. to fork further
    work) and over once values. *)
val with_fork : ?name:string -> Fork.t -> f:(t -> 'a) @ local once -> 'a

module Captured : sig
  (** The result of a completed trace: the full span forest, rich enough for Perfetto
      export. Records are exposed (and sexp-constructible) so tooling and tests can build
      or inspect captures directly. *)

  module Span : sig
    type t =
      { name : string
      ; args : (string * Arg.t) list
      ; start : Time_ns.Span.t (** offset from the start of the trace *)
      ; duration : Time_ns.Span.t
      ; lane : int
      (** which writer recorded this span: [0] is the root writer, and each {!with_fork}
          invocation gets a fresh positive id. A span's children may live on other lanes
          (their lanes were forked beneath it). *)
      ; children : t list (** ordered by [start] *)
      }
    [@@deriving sexp_of]
  end

  type t =
    { name : string option
    ; started_at : Time_ns.t (** wall-clock start, for Perfetto's clock domain *)
    ; duration : Time_ns.Span.t
    ; roots : Span.t list
    }
  [@@deriving sexp_of]
end

(** [finish t] stops the trace and returns everything recorded. Call it on the writer that
    {!create} returned, after instrumented work is done: lanes from any [with_fork] call
    still in flight are absent from the result. Subsequent recording on [t] (or its forks)
    is a no-op, and a second [finish] raises. *)
val finish : t -> Captured.t

module Summary : sig
  (** A collapsed view of a capture for at-a-glance profiling: sibling spans with the same
      name are merged into one node, recursively — so the per-row lanes of a parallel loop
      become a single child with [count] = number of rows. *)

  type t =
    { name : string
    ; count : int
    ; total : Time_ns.Span.t
    (** summed across merged spans and lanes; under parallelism this is CPU-time-like and
        can exceed the parent's wall-clock [total] *)
    ; self : Time_ns.Span.t (** [total] minus the [total] of children *)
    ; max : Time_ns.Span.t (** longest single merged instance *)
    ; children : t list (** ordered by first appearance in the capture *)
    }
  [@@deriving sexp_of]

  val of_captured : Captured.t -> t list

  (** Box-drawing tree, one line per node with total / self / percent-of-parent (plus
      count and max when a node merges several spans). Nodes are rendered in the order
      given — {!of_captured}'s first-appearance order, i.e. the order the phases first
      executed. [max_depth] truncates the tree. *)
  val to_string_hum : ?max_depth:int -> t list -> string
end
