open! Core
include Prepared_oracle_intf
module Key = Prepared_oracle_key

module type S = sig
  type t : value mod contended portable

  val sample : t -> x:float32# -> y:float32# -> float32#
end

type inner =
  | T :
      { impl : (module S with type t = 'a)
      ; value : 'a
      }
      -> inner

and t = inner portended

let wrap
  (type a : value mod contended portable)
  (impl : (module S with type t = a))
  (value : a)
  : t
  =
  { portended = T { impl; value } }
;;

let sample { portended = T { impl = (module M); value } } ~x ~y = M.sample value ~x ~y
