# SDF

An OCaml compiler and evaluator for signed-distance field (SDF) expressions. It takes programs written in a custom language called Neo (`.neo` files), compiles them through several intermediate representations, and efficiently evaluates the resulting expressions over pixel grids.

## Overview

### The Neo Language

Neo is a small functional DSL for defining SDF scenes. It supports `let` bindings, first-class functions, partial application (via `_` placeholders), method-call syntax (`x.f(args)` desugars to `f(x, args)`), conditionals, and a library of math builtins (`sqrt`, `sin`, `cos`, `min`, `max`, etc.). Programs end with an `export` statement that produces the final expression. Variables like `x` and `y` are introduced via a `var("name")` builtin and represent the pixel coordinates at evaluation time.

### Compilation Pipeline

```
.neo source
  → [Lexer/Parser]    lang/src/lexer.mll, parser.mly   → Ast.program
  → [Compiler]         lang/src/compile.ml               → Expr_tree.t
  → [Graph Builder]    src/expr_graph.ml                  → Expr_graph.t
  → [Register Min.]    src/expr_graph_register_minimizer.ml
  → [Evaluator]        src/expr_graph_eval.ml             → Value.t per pixel
```

1. **Parsing**: An ocamllex lexer and Menhir parser produce an `Ast.program`.
2. **Supercompilation** (`compile.ml`): All function calls are inlined and eliminated, variable bindings are substituted, and the result is a flat `Expr_tree.t` — a typed expression tree with no functions, just math operations, literals, variables, and conditionals.
3. **Graph compilation** (`expr_graph.ml`): The tree is lowered to a register-based instruction list (`Expr_graph.t`). Common subexpression elimination (CSE) deduplicates repeated subtrees during this pass.
4. **Register minimization**: A liveness-based pass reduces the number of registers needed.
5. **Evaluation** (`expr_graph_eval.ml`): The instruction list is executed for each pixel, reading input variables (e.g. x, y coordinates) and writing a final float or bool result.

There is also a tree-based interpreter (`expr_tree_eval.ml`) used mainly for testing.

### Type System

Two types: `Float` and `Bool`. Type checking is enforced both during compilation and by the `Expr_tree` smart constructors (which return `Or_error.t`). Comparisons produce bools from float operands; conditionals require matching branch types.

### Runtime Representation

Values are unboxed 32-bit integers (`Int32_u.t`) reinterpreted as either `Float32_u.t` or `bool` depending on the static type. This avoids allocation overhead during grid evaluation.

### Key Modules

| Module | Location | Purpose |
|--------|----------|---------|
| `Ast` | `lang/src/ast.ml` | Parsed syntax tree |
| `Compile` | `lang/src/compile.ml` | Neo → Expr_tree (supercompilation) |
| `Expr_tree` | `src/expr_tree.ml` | Typed expression tree with smart constructors |
| `Expr_graph` | `src/expr_graph.ml` | Register-based instruction IR + CSE |
| `Expr_graph_register_minimizer` | `src/expr_graph_register_minimizer.ml` | Liveness-based register optimization |
| `Expr_tree_eval` | `src/expr_tree_eval.ml` | Tree interpreter (for testing) |
| `Expr_graph_eval` | `src/expr_graph_eval.ml` | Graph evaluator (for production/benchmarks) |
| `Value` | `src/value.ml` | Unboxed 32-bit runtime values |

## Adding new operators

To add a new operator, make changes in the following files:

### 1. `src/expr_tree.mli`

Add the new variant to the `kind` type and a smart constructor to the signature.

### 2. `src/expr_tree.ml`

Add the new variant to the `kind` type definition and implement the smart constructor. Use `both_float` for binary float ops, `both_bool` for binary bool ops, or a direct `match` on `a.type_` for unary ops. The constructor should validate operand types and return `t Or_error.t`.

Add an exception-throwing version to `Expr_tree.Direct`.

### 3. `src/expr_tree_eval.ml`

Add the new case to `eval_float` (if it produces a float) or `eval_bool` (if it produces a bool). Also add it to the error arm of the *other* function (e.g. a float op must appear in the catch-all error case in `eval_bool`).

### 4. `src/expr_graph.mli`

Add the new variant to the `instr` type. Graph instructions use `Register.t` instead of `t` for operands.

### 5. `src/expr_graph.ml`

Three places to update:

- Add the variant to the `instr` type definition.
- Add a case in the `loop` function inside `from_tree` to compile the tree node into graph instructions (allocate registers for operands, emit the instruction).
- Add a case in `pp_instructions` for pretty-printing the new instruction.

### 6. `src/expr_graph_eval.ml`

Add a case to the `run` function to evaluate the new instruction, reading operands from the register array and writing the result.

### 7. `src/expr_graph_register_minimizer.ml`

Add the new operator to two exhaustive pattern matches:

- `instr_inputs`: extracts input registers from an instruction.
- `translate_instr`: rewrites register operands during minimization.

### 8. `test/helpers.ml`

Add a convenience constructor that wraps the `Expr_tree` smart constructor with `ok_exn`.

### 9. `test/test_bisimulation.ml`

Add the new operator to the quickcheck generators (`gen_float_expr` or `gen_bool_expr`) so it is covered by bisimulation testing. Use `binop` for binary ops or `unop` for unary ops.

### 10. `test/test_expr_tree.ml` and `test/test_expr_graph.ml`

Add at least one expect test for the new operator in each file.

### 11. Neo language support (if the operator should be usable from `.neo` files)

If the operator maps to new syntax or a new builtin function name, also update:

- **`lang/src/ast.ml`**: Add a variant to `binop` (for binary operators).
- **`lang/src/lexer.mll`** and **`lang/src/parser.mly`**: Add token and parsing rules for new syntax.
- **`lang/src/compile.ml`**: Add a case to `eval_binop` (for binary ops) or add the name to `is_builtin` and handle it in `eval_builtin` (for unary builtins).

## Testing
All tests are built into the `@runtest` alias, so from the root of the repo, you can run `dune build @sdf/runtest` 
to build and run them all.

### Style
Most tests are built using Jane Street's "expect test" framework, meaning that the expected output is included in the file.
Please continue to write tests of this form, and for new tests, just leave the `[%expect {||}]` block empty.  `dune build @sdf/runtest --auto-promote` will fix it up.

## Benchmarks

Benchmarks live in `bench/` and measure the full pipeline: parsing `.neo` files, compiling to expression graphs, and evaluating on a 1000x1000 pixel grid.

### Running benchmarks

```bash
# Run with default 10s budget (from repo root)
dune exec sdf/bench/bench.exe --profile=release

# Shorter budget for quick checks
dune exec sdf/bench/bench.exe --profile=release -- -budget 3

# Custom examples directory
dune exec sdf/bench/bench.exe --profile=release -- -dir path/to/neo/files
```

### Comparing results

```bash
# Save baseline
dune exec sdf/bench/bench.exe --profile=release -- -dump-sexp > before.sexp

# ... make changes ...

# Save new results and compare
dune exec sdf/bench/bench.exe --profile=release -- -dump-sexp > after.sexp
dune exec sdf/bench/compare.exe -- before.sexp after.sexp
```

### Adding benchmark files

Add `.neo` files to `bench/examples/`. They are discovered automatically.
