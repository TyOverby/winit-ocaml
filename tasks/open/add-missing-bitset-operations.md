# Add Missing Bitset Operations

The high-level bitset modules in `high/bitsets.ml` have a minimal API. Adding common set operations would make them more ergonomic to use.

## Current API

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
```

## Proposed Additions

### 1. `empty` constant

```ocaml
val empty : t
```

Currently users must write `of_list []` to get an empty set.

### 2. `all` constant

```ocaml
val all : t
```

Pre-computed combination of all flags. Especially useful for `Color_write_mask.all`.

### 3. Set combination operations

```ocaml
val union : t -> t -> t
val inter : t -> t -> t
val diff : t -> t -> t
```

Allow combining and manipulating bitsets without converting to/from lists.

### 4. `to_list` for round-tripping

```ocaml
val to_list : t -> Item.t list
```

Convert a bitset back to the list of active flags. Useful for debugging and serialization.

### 5. `to_int` for passing to low-level APIs

```ocaml
val to_int : t -> int
```

Explicit conversion to the underlying integer representation.

## Proposed Full Signature

```ocaml
module type S = sig
  module Item : sig
    type t
    val all : t list
  end

  type t

  val empty : t
  val all : t
  val singleton : Item.t -> t
  val of_list : Item.t list -> t
  val to_list : t -> Item.t list
  val to_int : t -> int
  val is_member : t -> Item.t -> bool
  val union : t -> t -> t
  val inter : t -> t -> t
  val diff : t -> t -> t
end
```

## Implementation

These additional helper functions could all be implemented in a functor that is applied inside 
to each of the bitset modules

```ocaml
let empty = 0
let all = of_list Item.all
let union a b = a lor b
let inter a b = a land b
let diff a b = a land (lnot b)
let to_int t = t
let to_list t = List.filter (fun item -> is_member t item) Item.all
```

## Files to Modify

- `codegen/gen_high.ml` - Update bitset generation to include new operations

## Testing

1. Run `dune build` to regenerate the high-level bindings
2. Run `dune build @check` to ensure no warnings
3. Add unit tests for the new operations
4. Run existing tests to verify nothing broke
