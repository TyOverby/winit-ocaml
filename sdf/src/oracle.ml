open! Core
module Key = Oracle_key
module Prepared = Prepared_oracle

module type S = sig @@ portable
  type t : value mod contended portable [@@deriving equal, compare, sexp_of]

  include Comparator.S [@mode portable] with type t := t

  val create : Expr_tree.t list -> t

  (** [trace] is the writer of the thread calling [prepare]; implementations record their
      internal phases beneath the span currently open on it. Pass [Phase_trace.null ()]
      when not tracing. *)
  val prepare
    :  t
    -> par:Parallel.t @ local
    -> trace:Phase_trace.t
    -> exec:(module Executor.S) @ shareable
    -> oracles:Prepared.t Map.M(Oracle_key).t
    -> sample_region:Sample_region.t
    -> Prepared.t
end
