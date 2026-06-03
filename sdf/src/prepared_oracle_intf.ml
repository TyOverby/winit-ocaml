open! Core

module type S = sig
  type t : value mod contended portable

  val sample : t -> x:float32# -> y:float32# -> float32#
end

module type Prepared_oracle = sig @@ portable
  module type S = S

  type t : value mod contended portable

  val wrap
    : ('a : value mod contended portable).
    (module S with type t = 'a) @ portable -> 'a -> t

  val sample : t -> x:float32# -> y:float32# -> float32# @@ portable
end
