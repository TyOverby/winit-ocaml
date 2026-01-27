# Cache Enum Constants at Module Initialization

The generated enum and bitset code in `low/wgpu_low.ml` makes FFI calls on every conversion between OCaml variants and C integers. This is unnecessarily slow since the values are compile-time constants in C.

## Problem

### 1. FFI calls for constant values on every `to_int` conversion

```ocaml
external adapter_type_discrete_gpu : unit -> int = "caml_wgpu_adapter_type_discrete_gpu"

let to_int = function
  | Discrete_gpu -> adapter_type_discrete_gpu ()  (* C call every time! *)
  | Integrated_gpu -> adapter_type_integrated_gpu ()
  ...
```

Each conversion crosses the OCaml/C boundary just to return a constant like `Val_int(WGPUAdapterType_DiscreteGPU)`.

### 2. O(n) linear search with FFI calls in `of_int`

```ocaml
let of_int = function
  | x when x = adapter_type_discrete_gpu () -> Discrete_gpu    (* C call *)
  | x when x = adapter_type_integrated_gpu () -> Integrated_gpu (* C call *)
  | x when x = adapter_type_cpu () -> Cpu                       (* C call *)
  ...
```

For an enum with N variants, finding the last variant requires N FFI calls. Large enums like `Texture_format` have 90+ variants.

### 3. Bitset `list_to_int` compounds the problem

```ocaml
let list_to_int flags = List.fold_left (fun acc f -> acc lor to_int f) 0 flags
```

Each flag in the list triggers an FFI call.

## Solution

Modify the code generator to compute and cache the integer values once at module initialization time:

```ocaml
(* Call FFI once at module load, store as constants *)
let discrete_gpu_int = adapter_type_discrete_gpu ()
let integrated_gpu_int = adapter_type_integrated_gpu ()
let cpu_int = adapter_type_cpu ()
let unknown_int = adapter_type_unknown ()

let to_int = function
  | Discrete_gpu -> discrete_gpu_int  (* No FFI call! *)
  | Integrated_gpu -> integrated_gpu_int
  | Cpu -> cpu_int
  | Unknown -> unknown_int

let of_int = function
  | x when x = discrete_gpu_int -> Discrete_gpu
  | x when x = integrated_gpu_int -> Integrated_gpu
  | x when x = cpu_int -> Cpu
  | x when x = unknown_int -> Unknown
  | n -> failwith (Printf.sprintf "Adapter_type.of_int: unknown value %d" n)
```

## Files to Modify

- `codegen/gen_low.ml` - Update `gen_ml_enum` and `gen_ml_bitflag` functions to generate cached constants

## Testing

1. Run `dune build` to regenerate the low-level bindings
2. Run `dune build @check` to ensure no warnings
3. Run existing tests to verify correctness
4. Optionally: add a micro-benchmark comparing before/after performance
