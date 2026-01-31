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

## Plan

I will modify the code generator to create separate enums.{ml,mli} and bitsets.{ml,mli} files that are then included in wgpu.{ml,mli}.

### Steps:

1. Understand current enum/bitset generation in gen_high.ml
2. Create new generation functions for separate enum/bitset files:
   - gen_enums_ml and gen_enums_mli
   - gen_bitsets_ml and gen_bitsets_mli
3. Update gen_bindings.ml to call these new generators and write the new files
4. Modify wgpu generation to use `include` statements instead of inline definitions
5. Update the dune file to build the new modules
6. Test that everything builds and tests pass

### Validation Criteria:

- `dune build` succeeds without errors
- `dune build @check` passes with no warnings
- `dune exec test/test_compute.exe` passes all tests
- The generated enums.mli has the module type S with to_int, of_int, and to_string
- Each enum module in enums.mli has the variant type and includes S
- The generated bitsets.mli has the module type S with singleton, of_list, and is_member
- Each bitset module has an Item submodule and includes S
- wgpu.{ml,mli} include the enums and bitsets files instead of inline definitions
- The high-level wgpu.mli is significantly shorter and easier to read
