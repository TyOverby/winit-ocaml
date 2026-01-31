(* Handwritten functor interface for bitset operations *)

module type Item_intf = sig
  type t

  val to_int : t -> int
  val all : t list
end

module type S = sig
  module Item : Item_intf

  type t = int

  val singleton : Item.t -> t
  val of_list : Item.t list -> t
  val is_member : t -> Item.t -> bool
  val empty : t
  val all : t
  val union : t -> t -> t
  val inter : t -> t -> t
  val diff : t -> t -> t
  val to_int : t -> int
  val to_list : t -> Item.t list

  (* Backwards compatibility alias *)
  val list_to_int : Item.t list -> t
end

module Make (Item : Item_intf) : S with module Item = Item
