(* Handwritten functor for bitset operations *)

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

module Make (Item : Item_intf) : S with module Item = Item = struct
  module Item = Item

  type t = int

  let singleton item = Item.to_int item
  let of_list items = List.fold_left (fun acc item -> acc lor Item.to_int item) 0 items
  let is_member t item = t land Item.to_int item <> 0
  let empty = 0
  let all = of_list Item.all
  let union a b = a lor b
  let inter a b = a land b
  let diff a b = a land lnot b
  let to_int t = t
  let to_list t = List.filter (fun item -> is_member t item) Item.all

  (* Backwards compatibility alias *)
  let list_to_int = of_list
end
