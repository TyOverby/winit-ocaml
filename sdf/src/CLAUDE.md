# `sdf/src` — the core library

This directory is the `sdf` library: the intermediate representations, the
evaluators, and the runtime that turn a compiled SDF expression into a grid of
sampled values. (The Neo front-end — lexer, parser, compiler — lives in
`sdf/lang`; see `../CLAUDE.md` for the end-to-end pipeline.) `sdf.ml` is the
public entry point and just re-exports the modules below.

## Intermediate representations

The expression flows through two IRs, both defined here:

- **`Expr_tree`** (`expr_tree.ml`) — a typed, immutable expression tree. The
  `kind` variant lists every operator (`Add`, `Min`, `Sqrt`, `Cond`, `Oracle`,
  …). Construction goes through smart constructors that type-check operands and
  return `t Or_error.t`; `Expr_tree.Direct` is the exception-raising version.
  Two types exist, `Float` and `Bool`. This is the IR the compiler emits and the
  one most tooling pattern-matches on.
- **`Expr_graph`** (`expr_graph.ml`) — a flat, register-based instruction list
  lowered from the tree by `from_tree`, which performs common-subexpression
  elimination as it goes. `Expr_graph_register_minimizer` then runs a
  liveness-based pass to shrink the register file.

## Evaluators

There is **one production evaluator**: `Expr_graph_batch_eval`, a SIMD register
VM that evaluates 4 pixels at a time (`float32x4#`). It exposes the batch
shape directly — `Prepared.of_tree`, `Batch.create`/`create_sub`,
`Batch.run`, `Result.get_output` — and everything that evaluates grids
(`Tiled_eval`, `Sdf_contour`) calls it by name; there is no executor
abstraction to swap implementations.

The scalar register VM, `Expr_graph_eval`, is also production code, in two
supporting roles:

- `Expr_graph_eval.Private.run` is the SIMD batch's **scalar tail** for widths
  not divisible by 4.
- `Expr_graph_eval.Single` evaluates one `(x, y)` point; the passthrough
  oracle samples through it.

Both must produce bitwise-identical results (see "Arithmetic Semantics" in
`../CLAUDE.md`). The reference tree interpreter (`Expr_tree_eval`) and the
module-type "shapes" (`S_single`/`S_batch`) that the bisimulation/differential
test suites functorize over live in `../for_testing` (library
`sdf_for_testing`), along with `Single_to_batch`/`Batch_to_single` adapter
functors — none of it ships in the `sdf` library.

Parallelism lives above the evaluator, in the tiled machinery: `Tiled_eval`
(driven by `Tile_scheduler`) runs one sub-batch per tile as a `Parallel.for_`
task. A `Tile_scheduler.Cull.Nothing` schedule degenerates to a dense,
every-sample parallel evaluation.

`Expr_graph_batch_eval` builds on `Simd` (`simd.ml` + `simd_stubs.c`), which
binds vec128 intrinsics: `float32x4#`/`int32x4#` arithmetic, comparisons,
bitwise ops, and a branchless `select` used to compile `Cond`. Ops without a
vector form (e.g. `sin`, `cos`) fall back to scalar loops over the lane.

## Runtime values & sampling

- **`Value`** (`value.ml`) — an untagged 32-bit union (`bits32`) of
  `float32#`/`int32#`/`bool`. There is no runtime tag; the static `Type.t`
  decides how to reinterpret the bits, which is what keeps grid evaluation
  allocation-free. `Value.Array` is the unboxed backing store for results, and
  `Value.Boxed` wraps a value when it must sit in a `Map`.
- **`Sample_region`** (`sample_region.ml`) — a rectangular sampling grid
  (`start/end` in x and y, plus sample counts). Helpers compute the step size
  and the coordinate of a given sample (`x_at`, `y_at`), carve out a single
  `row` or `point`, and `expand` the region by N samples. `Sample_result`
  pairs a region with its row-major `float32# iarray` of outputs.

## Oracles

An **oracle** is a named sub-expression (`Oracle of string * t list` in the
tree) whose value over a region is precomputed and then sampled, rather than
recomputed per pixel — useful when a sub-field is reused or feeds back into
later expressions.

- `Oracle_key` = `(name, args)`; `Prepared_oracle` is a first-class-module
  wrapper around something that can be `sample`d at `~x ~y` (kept
  `contended portable` so it can cross domains).
- `Oracle_dependencies.extract_deps` collects every oracle in a tree, builds the
  dependency graph between oracles, and topologically sorts them into levels
  (Kahn's algorithm) so independent oracles in the same level can be prepared in
  parallel; a cycle degrades to emitting the remainder as one group.
- `Oracle.S.prepare` takes a `Parallel.t`, the already-prepared upstream
  oracles, and a region, and produces a `Prepared_oracle.t`. Implementations
  evaluate with the production evaluators directly.

## File map

| File | Purpose |
|------|---------|
| `sdf.ml` | public re-exports |
| `expr_tree.ml` | typed expression tree + smart constructors |
| `expr_graph.ml` | register-IR lowering + CSE |
| `expr_graph_register_minimizer.ml` | liveness-based register reduction |
| `expr_graph_eval.ml` | scalar register-VM evaluator (SIMD tail + `Single` point evaluator) |
| `expr_graph_batch_eval.ml` | SIMD register-VM evaluator (the production path) |
| `value.ml` | unboxed 32-bit runtime value + arrays |
| `sample_region.ml` / `sample_result.ml` | sampling grid + results |
| `simd.ml` / `simd_stubs.c` | vec128 intrinsic bindings |
| `oracle*.ml`, `prepared_oracle*.ml` | named precomputed sub-fields + dependency ordering |


## Adding new operators

To add a new operator, make changes in the following files:

### 1. `src/expr_tree.mli`

Add the new variant to the `kind` type and a smart constructor to the signature.

### 2. `src/expr_tree.ml`

Add the new variant to the `kind` type definition and implement the smart
constructor. Use `both_float` for binary float ops, `both_bool` for binary bool
ops, or a direct `match` on `a.type_` for unary ops. The constructor should
validate operand types and return `t Or_error.t`.

Add an exception-throwing version to `Expr_tree.Direct`.

### 3. `for_testing/expr_tree_eval.ml`

Add the new case to `eval_float` (if it produces a float) or `eval_bool` (if it
produces a bool). Also add it to the error arm of the *other* function (e.g. a
float op must appear in the catch-all error case in `eval_bool`).

### 4. `src/expr_graph.mli`

Add the new variant to the `instr` type. Graph instructions use `Register.t`
instead of `t` for operands.

### 5. `src/expr_graph.ml`

Three places to update:

- Add the variant to the `instr` type definition.
- Add a case in the `loop` function inside `from_tree` to compile the tree node
  into graph instructions (allocate registers for operands, emit the instruction).
- Add a case in `pp_instructions` for pretty-printing the new instruction.

### 6. `src/expr_graph_eval.ml`

Add a case to the `run` function to evaluate the new instruction, reading
operands from the register array and writing the result.

### 7. `src/expr_graph_register_minimizer.ml`

Add the new operator to two exhaustive pattern matches:

- `instr_inputs`: extracts input registers from an instruction.
- `translate_instr`: rewrites register operands during minimization.

### 8. `test/helpers.ml`

Add a convenience constructor that wraps the `Expr_tree` smart constructor with `ok_exn`.

### 9. `test/test_bisimulation.ml`

Add the new operator to the quickcheck generators (`gen_float_expr` or
`gen_bool_expr`) so it is covered by bisimulation testing. Use `binop` for
binary ops or `unop` for unary ops.

### 10. `test/test_expr_tree.ml` and `test/test_expr_graph.ml`

Add at least one expect test for the new operator in each file.

### 11. Neo language support (if the operator should be usable from `.neo` files)

If the operator maps to new syntax or a new builtin function name, also update:

- **`lang/src/ast.ml`**: Add a variant to `binop` (for binary operators).
- **`lang/src/lexer.mll`** and **`lang/src/parser.mly`**: Add token and parsing rules for new syntax.
- **`lang/src/compile.ml`**: Add a case to `eval_binop` (for binary ops) or add the name to `is_builtin` and handle it in `eval_builtin` (for unary builtins).