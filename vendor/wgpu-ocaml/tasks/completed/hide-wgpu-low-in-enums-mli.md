# Hide Wgpu_low in enums.mli

## Problem

The generated `high/enums.mli` exposes the internal dependency on `Wgpu_low` by using `include module type of Wgpu_low.X`:

```ocaml
module Adapter_type : sig
  include module type of Wgpu_low.Adapter_type

  val to_string : t -> string
end
```

This leaks implementation details into the public API. Users of the high-level bindings shouldn't need to know about `Wgpu_low`.

## Solution

Change the `.mli` to:
1. Redeclare the type explicitly with all its variants
2. Use `include S with type t := t` for the common operations (`to_int`, `of_int`, `to_string`)

No changes needed to `enums.ml` - it can continue using `include Wgpu_low.X` as an implementation detail.

### Before (enums.mli)

```ocaml
module type S = sig
  type t
  val to_int : t -> int
  val of_int : int -> t
  val to_string : t -> string
end

module Adapter_type : sig
  include module type of Wgpu_low.Adapter_type

  val to_string : t -> string
end
```

### After (enums.mli)

```ocaml
module type S = sig
  type t
  val to_int : t -> int
  val of_int : int -> t
  val to_string : t -> string
end

module Adapter_type : sig
  type t =
    | Discrete_gpu
    | Integrated_gpu
    | Cpu
    | Unknown

  include S with type t := t
end
```

## Benefits

1. **Cleaner public API** - Users see only what they need, not internal module structure
2. **Better documentation** - The variants are visible directly in the `.mli`
3. **Decoupled** - Changes to `Wgpu_low` module structure won't affect the public API signature

## Files to Modify

- `codegen/gen_high.ml` - Update the enum interface generation to output the explicit type and `include S with type t := t`

## Implementation Notes

The codegen already has access to the enum variants (since it generates `to_string`). It just needs to:
1. Generate `type t = | Variant1 | Variant2 | ...` with the full variant list
2. Generate `include S with type t := t` instead of `include module type of Wgpu_low.X` + `val to_string`

Comments/docstrings (like those on `Callback_mode`, `Composite_alpha_mode`, etc.) should be preserved and placed before the type definition.

## Testing

1. Run `dune build` to regenerate the bindings
2. Run `dune build @check` to ensure no warnings
3. Verify `high/enums.mli` no longer mentions `Wgpu_low`
4. Verify each module has explicit `type t = ...` with variants
5. Verify each module uses `include S with type t := t`
6. Run `dune exec test/test_compute.exe` to confirm tests pass

## Validation Criteria

1. `dune build` succeeds
2. `dune fmt > /dev/null || true` runs without error
3. `dune build @check` reports no warnings
4. Generated `high/enums.mli` contains no references to `Wgpu_low`
5. Each enum module has explicit type definition with variants
6. Each enum module uses `include S with type t := t`
7. All existing tests pass

---

## Implementation Plan

The change needs to modify the `gen_enum_with_to_string` function in `codegen/gen_high.ml`.
Currently in the `Interface` case, it generates:
```ocaml
  include module type of Wgpu_low.X
  val to_string : t -> string
```

The fix:
1. In the `Interface` case of `gen_enum_with_to_string`, generate the explicit type definition with all variants (the code already has access to `enum.entries`)
2. Replace `include module type of Wgpu_low.X` + `val to_string` with `include S with type t := t`

The `.ml` file generation remains unchanged - it can continue using `include Wgpu_low.X` as an implementation detail.

### Validation Criteria
1. `dune build` succeeds
2. `dune fmt > /dev/null || true` runs without error
3. `dune build @check` reports no warnings
4. Generated `high/enums.mli` contains no references to `Wgpu_low`
5. Each enum module has explicit type definition with variants
6. Each enum module uses `include S with type t := t`
7. All existing tests pass
