# Cache Enum/Bitflag FFI Calls at Module Initialization

## Problem

The generated low-level enum and bitflag modules call C external functions on every `to_int` and `of_int` conversion:

```ocaml
module Adapter_type = struct
  external adapter_type_discrete_gpu : unit -> int = "caml_wgpu_adapter_type_discrete_gpu"
  external adapter_type_integrated_gpu : unit -> int = "caml_wgpu_adapter_type_integrated_gpu"
  (* ... *)

  let to_int = function
    | Discrete_gpu -> adapter_type_discrete_gpu ()    (* FFI call *)
    | Integrated_gpu -> adapter_type_integrated_gpu () (* FFI call *)
    (* ... *)

  let of_int = function
    | x when x = adapter_type_discrete_gpu () -> Discrete_gpu    (* FFI call per guard! *)
    | x when x = adapter_type_integrated_gpu () -> Integrated_gpu
    (* ... *)
end
```

This is inefficient because:
1. C enum values are compile-time constants that never change
2. `of_int` evaluates guards sequentially, so matching the last variant requires N FFI calls
3. Bitflag `list_to_int` makes one FFI call per flag in the list

## Proposed Fix

Cache the external call results in `let` bindings at module initialization:

```ocaml
module Adapter_type = struct
  type t = Discrete_gpu | Integrated_gpu | Cpu | Unknown

  external adapter_type_discrete_gpu : unit -> int = "caml_wgpu_adapter_type_discrete_gpu"
  external adapter_type_integrated_gpu : unit -> int = "caml_wgpu_adapter_type_integrated_gpu"
  external adapter_type_cpu : unit -> int = "caml_wgpu_adapter_type_cpu"
  external adapter_type_unknown : unit -> int = "caml_wgpu_adapter_type_unknown"

  (* Cache values at module init - called once, not per conversion *)
  let discrete_gpu_int = adapter_type_discrete_gpu ()
  let integrated_gpu_int = adapter_type_integrated_gpu ()
  let cpu_int = adapter_type_cpu ()
  let unknown_int = adapter_type_unknown ()

  let to_int = function
    | Discrete_gpu -> discrete_gpu_int
    | Integrated_gpu -> integrated_gpu_int
    | Cpu -> cpu_int
    | Unknown -> unknown_int

  let of_int = function
    | x when x = discrete_gpu_int -> Discrete_gpu
    | x when x = integrated_gpu_int -> Integrated_gpu
    | x when x = cpu_int -> Cpu
    | x when x = unknown_int -> Unknown
    | n -> failwith (Printf.sprintf "Adapter_type.of_int: unknown value %d" n)
end
```

## Implementation

Modify `codegen/gen_low.ml` in the enum and bitflag generation functions:

1. After generating the `external` declarations, generate `let` bindings that call each external once
2. Update `to_int` to return the cached `let` values instead of calling externals
3. Update `of_int` to compare against the cached `let` values

## Impact

- **Before**: O(n) FFI calls per `of_int`, O(1) FFI call per `to_int`, O(k) FFI calls per `list_to_int` with k flags
- **After**: O(n) FFI calls total at module load time, O(0) FFI calls per conversion

## Validation

- All existing tests pass
- `dune build @check` passes with no warnings
- Generated code uses cached values instead of direct external calls
