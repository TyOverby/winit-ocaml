# Extract Configuration Into a Dedicated Module

## Problem

`gen_high.ml` starts with ~100 lines of configuration that defines:
- Which methods are manually implemented
- Which methods are intentionally skipped
- The relationship between these sets

This configuration is mixed in with the generator logic, making it hard to:
1. Find all "special cases" in one place
2. Understand why certain methods need special handling
3. Add new special cases consistently

## Current State

```ocaml
let manual_implementations =
  Set.of_list
    (module Method_key)
    [ (* Instance methods - some manually implemented in instance_module *)
      "instance", "release" (* manually implemented *)
    ; "instance", "create_surface"
    ; ...
    ]

let intentionally_skipped =
  Set.of_list
    (module Method_key)
    [ (* Internal/advanced methods that typical users don't need *)
      "adapter", "request_adapter_info" (* deprecated, use get_info *)
    ; ...
    ]
```

## Proposed Fix

### Create a dedicated configuration module

```ocaml
(* codegen/config.ml *)

(** Method handling categories *)
type method_handling =
  | Manual of { reason : string }
  (** Method is implemented by hand in template code *)

  | Skipped of { reason : string }
  (** Method is intentionally not exposed *)

  | Auto
  (** Method is auto-generated *)

(** Method key: (object_name, method_name) *)
module Method_key = struct
  type t = string * string [@@deriving sexp, compare]
  include Comparator.Make(struct ... end)
end

(** Get handling for a method *)
val get_handling : object_name:string -> method_name:string -> method_handling

(** All manually implemented methods *)
val manual_methods : Method_key.t list

(** All skipped methods *)
val skipped_methods : Method_key.t list

(** Check if a method is accounted for (not auto-generated) *)
val is_accounted_for : object_name:string -> method_name:string -> bool
```

### Configuration as Data

```ocaml
(* codegen/method_config.ml *)

let method_config : (Method_key.t * method_handling) list = [
  (* Instance methods *)
  ("instance", "release"), Manual {
    reason = "Custom release logic with instance cleanup"
  };
  ("instance", "request_adapter"), Manual {
    reason = "Async method, we provide sync wrapper"
  };

  (* Deprecated methods *)
  ("adapter", "request_adapter_info"), Skipped {
    reason = "Deprecated, use get_info instead"
  };

  (* All other methods are Auto *)
]
```

### Benefits of Structured Configuration

1. **Reasons are Required**: Forces documentation of why each special case exists
2. **Single Source of Truth**: All method handling in one place
3. **Queryable**: Can easily list all manual/skipped methods
4. **Validation**: Can validate that configured methods actually exist in the API
5. **Reporting**: Can generate documentation of what's manual vs auto-generated

### Example: Validation

```ocaml
(** Validate that all configured methods exist in the API *)
let validate_config (api : Ir.api) : unit =
  let all_methods =
    List.concat_map api.objects ~f:(fun obj ->
      List.map obj.methods ~f:(fun m -> obj.name, m.name))
    |> Set.of_list (module Method_key)
  in
  List.iter method_config ~f:(fun ((obj, meth), _handling) ->
    if not (Set.mem all_methods (obj, meth)) then
      failwithf "Configured method %s.%s does not exist in API" obj meth ())
```

## Estimated Impact

- Medium value: Better organization and documentation
- Low effort: Straightforward extraction
