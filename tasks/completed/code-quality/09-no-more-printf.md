# Create Code Builder Abstraction

## Problem

Code generation uses raw string concatenation with `sprintf` throughout, leading to:
- Hard-to-read generation code
- Inconsistent indentation
- Mixing of concerns (structure vs formatting)

## Current Pattern

```ocaml
sprintf
  "module %s = struct\n\
  \  type t =\n\
   %s\n\n\
   %s\n\n\
  \  let to_int = function\n\
   %s\n\n\
  \  let of_int = function\n\
   %s\n\
  \    | n -> failwith (Printf.sprintf \"%s.of_int: unknown value %%d\" n)\n\
   end\n"
  module_name
  variants
  externals
  to_int_cases
  of_int_cases
  module_name
```

This is:
- Hard to read (escaped newlines)
- Error-prone (easy to mix up %s with arguments)

## Proposed Fix

Use `ppx_string` with the inline ppx multiline string syntax, like so:

```ocaml

{%string|
module %{module_name} = struct
  type t = 
    %{variants}

  %{externals}

  let to_int = function 
    %{to_int_cases}

  let of_int = function 
    %{of_int_cases}
    | n -> failwith (Printf.sprintf \"%s.of_int: unknown value %%d\" n)
end
|}

```

## Estimated Impact

- Medium value: Improves readability of generation code
- Medium effort: Requires rewriting most generation functions
