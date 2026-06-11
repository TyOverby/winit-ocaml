open! Core

module type Prepared_oracle = sig @@ portable
  type t : value mod contended portable

  module type S = sig
    type t : value mod contended portable

    val sample : t -> x:float32# -> y:float32# -> float32#

    (** Conservative range version of [sample]: must return an interval containing
        [sample t ~x ~y] for every (x, y) in the box [x] × [y]. *)
    val sample_range : t -> x:Interval.t -> y:Interval.t -> Interval.t
  end

  val wrap
    : ('a : value mod contended portable).
    (module S with type t = 'a) @ portable -> 'a -> t

  val sample : t -> x:float32# -> y:float32# -> float32# @@ portable
  val sample_range : t -> x:Interval.t -> y:Interval.t -> Interval.t @@ portable
end
