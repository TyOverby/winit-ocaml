# SDF

An OCaml compiler and evaluator for signed-distance field (SDF) expressions. It
takes programs written in a custom language called Neo (`.neo` files), compiles
them through several intermediate representations, and efficiently evaluates the
resulting expressions over pixel grids.

## Overview

### The Neo Language

Neo is a small functional DSL for defining SDF scenes. It supports `let`
bindings, first-class functions, partial application (via `_` placeholders),
method-call syntax (`x.f(args)` desugars to `f(x, args)`), conditionals, and a
library of math builtins (`sqrt`, `sin`, `cos`, `min`, `max`, etc.). Programs
end with an `export` statement that produces the final expression. Variables
like `x` and `y` are introduced via a `var("name")` builtin and represent the
pixel coordinates at evaluation time.

### Compilation Pipeline

```
.neo source
  → [Lexer/Parser]     lang/src/lexer.mll, parser.mly     → Ast.program
  → [Compiler]         lang/src/compile.ml                → Expr_tree.t
  → [Graph Builder]    src/expr_graph.ml                  → Expr_graph.t
  → [Register Min.]    src/expr_graph_register_minimizer.ml
  → [Evaluator]        src/expr_graph_eval.ml             → Value.t per pixel
```

1. **Parsing**: An ocamllex lexer and Menhir parser produce an `Ast.program`.
2. **Supercompilation** (`compile.ml`): All function calls are inlined and
   eliminated, variable bindings are substituted, and the result is a flat
   `Expr_tree.t` — a typed expression tree with no functions, just math operations,
   literals, variables, and conditionals.
3. **Graph compilation** (`expr_graph.ml`): The tree is lowered to a
   register-based instruction list (`Expr_graph.t`). Common subexpression
   elimination (CSE) deduplicates repeated subtrees during this pass.
4. **Register minimization**: A liveness-based pass reduces the number of registers needed.
5. **Evaluation** (`expr_graph_eval.ml`): The instruction list is executed for
   each pixel, reading input variables (e.g. x, y coordinates) and writing a final
   float or bool result.

There is also a tree-based interpreter (`expr_tree_eval.ml`) used mainly for testing.

### Type System

Two types: `Float` and `Bool`. Type checking is enforced both during compilation
and by the `Expr_tree` smart constructors (which return `Or_error.t`).
Comparisons produce bools from float operands; conditionals require matching
branch types.

### Arithmetic Semantics

Division and square root are total, deviating from IEEE: `x / 0 = 0` (for
either sign of zero) and `sqrt x = 0` for `x < 0`. All evaluator backends
implement this identically (the SIMD backend via compare + select). The point
is to keep NaN out of ordinary programs: NaN propagates through `min`/`max`
(the SDF union/intersection combinators), so under IEEE semantics a single
division by zero would force the interval evaluator
(`Expr_graph_range_eval`) to report "any value" for the whole scene.

### Runtime Representation

Values are unboxed 32-bit integers (`Int32_u.t`) reinterpreted as either
`Float32_u.t` or `bool` depending on the static type. This avoids allocation
overhead during grid evaluation.

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

### Further documentation

- **`src/CLAUDE.md`** — internals of the core library: the `Executor`
  abstraction (`Single`/`Batch`/`Parallel` shapes + adapter functors), the three
  interchangeable evaluator backends (including the SIMD `Expr_graph_batch_eval`),
  unboxed runtime values, sampling regions, and oracles (named precomputed
  sub-fields).
- **`lang/CLAUDE.md`** — how the Neo parser produces context-aware error
  messages via LRgrep, and how to add new error cases.


## Testing
All tests are built into the `@runtest` alias, so from the root of the repo, you
can run `dune build @sdf/runtest` to build and run them all.

### Style
Most tests are built using Jane Street's "expect test" framework, meaning that
the expected output is included in the file.  Please continue to write tests of
this form, and for new tests, just leave the `[%expect {||}]` block empty.
`dune build @sdf/runtest --auto-promote` will fix it up.

## Benchmarks

Benchmarks live in `bench/` and measure the full pipeline: parsing `.neo` files,
compiling to expression graphs, and evaluating on a 1000x1000 pixel grid.

### Running benchmarks

```bash
# Run with default 10s budget (from repo root)
dune exec sdf/bench/bench.exe --profile=release

# Shorter budget for quick checks
dune exec sdf/bench/bench.exe --profile=release -- -budget 3

# Custom examples directory
dune exec sdf/bench/bench.exe --profile=release -- -dir path/to/neo/files

# Select the evaluation backend: graph (default), batch (SIMD), or tree
dune exec sdf/bench/bench.exe --profile=release -- -strategy batch
```

### Comparing results

```bash
# Save baseline (redirect stderr to /dev/null — progress messages go to stderr
# and will corrupt the sexp file if not suppressed)
dune exec sdf/bench/bench.exe --profile=release -- -dump-sexp 2>/dev/null > before.sexp

# ... make changes ...

# Save new results and compare
dune exec sdf/bench/bench.exe --profile=release -- -dump-sexp 2>/dev/null > after.sexp
dune exec sdf/bench/compare.exe -- before.sexp after.sexp
```

### Adding benchmark files

Add `.neo` files to `bench/examples/`. They are discovered automatically.
