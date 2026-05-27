# SDF

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

### 7. `test/helpers.ml`

Add a convenience constructor that wraps the `Expr_tree` smart constructor with `ok_exn`.

### 8. `test/test_bisimulation.ml`

Add the new operator to the quickcheck generators (`gen_float_expr` or `gen_bool_expr`) so it is covered by bisimulation testing. Use `binop` for binary ops or `unop` for unary ops.

### 9. `test/test_expr_tree.ml` and `test/test_expr_graph.ml`

Add at least one expect test for the new operator in each file.

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
