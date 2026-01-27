The high level mli is hard to read due to how many enums and bitsets there are in the API.
I'd like for you to make the code generator produce `enums.{ml,mli}` and `bitsets.{ml,mli}`
which are then included in the primary `wgpu.{ml,mli}` files.

After that, let's upgrade the interface for these files to be a bit more user friendly.

`enums.mli` should start like this:

```ocaml
module type S = sig
  type t

  val to_int : t -> int
  val of_int : int -> t

  val to_string: t -> string 
end

module An_example_enum : sig
  type t = Some_enum | Example_constructors
  include S with type t := t
end

...
```

and `bitset.mli` should start like this:

```ocaml
module type S = sig
  module Item : sig
    type t
  end

  type t

  val singleton : Item.t -> t
  val of_list : Item.t list -> t
  val is_member : t -> Item.t -> bool
end

module An_example_bitset : sig
  module Item : sig
    type t = A | B | C
  end
  include S with module Item := Item
end
```
