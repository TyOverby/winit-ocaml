# Simplify High-Level Enums Using Include

The generated high-level enum code in `high/enums.ml` redundantly redefines types and functions that are identical to the low-level versions, adding unnecessary indirection and compounding the FFI performance issues from the low-level layer.

## Problem

### 1. Redundant type redefinition

The high-level enums redefine identical variant types:

```ocaml
(* high/enums.ml *)
module Adapter_type = struct
  type t =
    | Discrete_gpu
    | Integrated_gpu
    | Cpu
    | Unknown

(* low/wgpu_low.ml - exactly the same! *)
module Adapter_type = struct
  type t =
    | Discrete_gpu
    | Integrated_gpu
    | Cpu
    | Unknown
```

### 2. Pointless variant reconstruction in `to_int`

```ocaml
let to_int = function
  | Discrete_gpu -> Wgpu_low.Adapter_type.to_int Discrete_gpu
  | Integrated_gpu -> Wgpu_low.Adapter_type.to_int Integrated_gpu
  | Cpu -> Wgpu_low.Adapter_type.to_int Cpu
  | Unknown -> Wgpu_low.Adapter_type.to_int Unknown
```

This matches a variant, then constructs the *same* variant to pass to the low-level function. Since the types are structurally identical, the function could simply delegate directly.

### 3. Double inefficiency in `of_int`

```ocaml
let of_int = function
  | x when x = Wgpu_low.Adapter_type.to_int Discrete_gpu -> Discrete_gpu
  | x when x = Wgpu_low.Adapter_type.to_int Integrated_gpu -> Integrated_gpu
  ...
```

Each comparison calls `Wgpu_low.Adapter_type.to_int`, which (until the low-level caching task is done) triggers FFI calls. This compounds the performance problem.

## Solution

Use `include` to re-export the low-level module and only add the new `to_string` function:

```ocaml
module Adapter_type = struct
  include Wgpu_low.Adapter_type

  let to_string = function
    | Discrete_gpu -> "Discrete_gpu"
    | Integrated_gpu -> "Integrated_gpu"
    | Cpu -> "Cpu"
    | Unknown -> "Unknown"
end
```

This:
- Eliminates redundant type definitions
- Reuses `to_int` and `of_int` directly (no extra indirection)
- Only adds the genuinely new functionality (`to_string`)

## Files to Modify

- `codegen/gen_high.ml` - Update the enum generation logic to use `include`

## Testing

1. Run `dune build` to regenerate the high-level bindings
2. Run `dune build @check` to ensure no warnings
3. Run existing tests to verify correctness

## Implementation Plan

1. Modify the `gen_enum_with_to_string` function in `codegen/gen_high.ml`:
   - For `Implementation` mode: Use `include Wgpu_low.Module_name` and only add `to_string`
   - For `Interface` mode: Use `include module type of Wgpu_low.Module_name` and add `to_string`

2. The generated output should look like:
   ```ocaml
   (* Implementation *)
   module Adapter_type = struct
     include Wgpu_low.Adapter_type

     let to_string = function
       | Discrete_gpu -> "Discrete_gpu"
       | ...
   end

   (* Interface *)
   module Adapter_type : sig
     include module type of Wgpu_low.Adapter_type
     val to_string : t -> string
   end
   ```

## Validation Criteria

1. `dune build` succeeds without errors
2. `dune build @check` produces no warnings
3. `dune exec test/test_compute.exe` passes all tests
4. The generated `high/enums.ml` uses `include Wgpu_low.X` instead of redefining types
5. The generated `high/enums.mli` uses `include module type of Wgpu_low.X`
