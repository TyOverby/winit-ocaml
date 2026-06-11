@@ portable

open! Core

(** A range (interval) evaluator for the instruction graph.

    Where {!Expr_graph_eval} evaluates the program at a single (x, y) point, this
    evaluator takes inclusive coordinate ranges and returns an interval guaranteed to
    contain every value the scalar evaluator can produce at any point of the box.
    Variables remain scalars; only the coordinates (and therefore oracles, via
    {!Prepared_oracle.sample_range}) are ranges. *)
include Executor.S_range
