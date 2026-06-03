open! Core
include Prepared_oracle_intf

type inner =
  | T :
      { impl : (module S with type t = 'a)
      ; value : 'a
      }
      -> inner

type t = inner portended

let wrap
  (type a : value mod contended portable)
  (impl : (module S with type t = a))
  (value : a)
  : t
  =
  { portended = T { impl; value } }
;;

let sample { portended = T { impl = (module M); value } } ~x ~y = M.sample value ~x ~y
