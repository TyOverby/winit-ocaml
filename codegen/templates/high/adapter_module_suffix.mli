
  (** Poll the device for completed work *)
  val poll : t -> ?wait:bool -> unit -> unit
end

module Adapter : sig
  type t

  val get_info : t -> Adapter_info.t
  val release : t -> unit
  val request_device : t -> Device.t
  val has_feature : t -> feature:Feature_name.t -> bool
end
