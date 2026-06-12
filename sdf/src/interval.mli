@@ portable

open! Core

(** Inclusive intervals of [float32#] values, plus a three-valued boolean, used by the
    interval evaluator ({!Expr_graph_range_eval}) to bound the value of an expression over
    a whole region instead of at a single point.

    Every operation here mirrors a scalar primitive of the expression language and is
    {e conservative}: if the scalar operation applied to any values drawn from the input
    intervals can produce [v], then [v] is contained in the output interval.

    NaN is handled through a distinguished "top" interval: an interval with a NaN endpoint
    means "any float value, possibly NaN". Operations that could produce NaN for some
    inputs in range return {!top}. Because the language's division and square root are
    total ([x / 0 = 0] and [sqrt x = 0] for [x < 0]), NaN can only arise from arithmetic
    on infinities ([inf - inf], [0 * inf], [inf / inf]) or trig of an infinity, so [top]
    is rare in practice. *)
type t =
  #{ lo : Float32_u.t
   ; hi : Float32_u.t
   }

(** The interval of all values, including NaN. Both endpoints are NaN. *)
val top : t

val is_top : t -> bool

(** [of_point v] is the single-point interval [[v, v]] ([top] if [v] is NaN). *)
val of_point : Float32_u.t -> t

(** [create ~lo ~hi] builds the interval [[lo, hi]]. Endpoints are swapped if given out of
    order; a NaN endpoint yields [top]. *)
val create : lo:Float32_u.t -> hi:Float32_u.t -> t

(** [contains t v] is true iff a scalar evaluation that produced [v] is consistent with
    the interval [t]. NaN is only contained in [top]. *)
val contains : t -> Float32_u.t -> bool

(** Smallest interval containing both arguments. *)
val hull : t -> t -> t

val sexp_of_t : t -> Sexp.t
val to_string : t -> string

(** A three-valued boolean: the set of booleans a boolean subexpression can take over the
    region. At least one of the two fields is always true. *)
module Bool : sig
  type t =
    #{ can_be_false : bool
     ; can_be_true : bool
     }

  val of_point : bool -> t
  val maybe : t
  val definitely_true : t -> bool
  val definitely_false : t -> bool
  val contains : t -> bool -> bool
  val hull : t -> t -> t
  val and_ : t -> t -> t
  val or_ : t -> t -> t
  val xor : t -> t -> t
  val sexp_of_t : t -> Sexp.t
  val to_string : t -> string
end

(** Interval versions of the float-valued primitives. Semantics match the scalar evaluator
    exactly, e.g. [div] and [sqrt] are total ([x / 0 = 0], [sqrt x = 0] for [x < 0]),
    [sign] maps NaN to 0, [min]/[max] propagate NaN from either argument, and [round]
    rounds half-integers to even (the hardware rounding of the SIMD backend). *)

val add : t -> t -> t
val sub : t -> t -> t
val mul : t -> t -> t
val div : t -> t -> t
val sqrt : t -> t
val abs : t -> t
val neg : t -> t
val sign : t -> t
val sin : t -> t
val cos : t -> t
val round : t -> t
val min : t -> t -> t
val max : t -> t -> t

(** Interval comparisons: definite only when the operand intervals don't overlap the other
    side. Comparisons against [top] are always {!Bool.maybe}. *)

val lt : t -> t -> Bool.t
val gt : t -> t -> Bool.t
val lte : t -> t -> Bool.t
val gte : t -> t -> Bool.t
