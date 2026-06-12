open! Core

(** Export a {!Phase_trace.Captured.t} to a Perfetto-compatible trace file.

    Writes Fuchsia Trace Format ([.fxt]) via Jane Street's [tracing] library
    ([Tracing_zero.Writer], the allocation-free synchronous writer — no async). Open the
    result at {:https://ui.perfetto.dev}.

    Layout: the capture becomes one Perfetto process (named after [Captured.name]); lane 0
    is the main-thread track. Forked lanes are packed onto synthetic threads — lanes that
    do not overlap in time share a track — so a 1000-row parallel loop renders as roughly
    one track per domain rather than 1000. Span args are emitted as Perfetto args on each
    slice.

    This lives in its own library so the core [phase_trace] recorder does not depend on
    [tracing] (and its async/cohttp closure). *)

val write_file : Phase_trace.Captured.t -> filename:string -> unit
