open! Core

module Stats = struct
  type t =
    { mean_s : float
    ; stddev_s : float
    ; min_s : float
    ; max_s : float
    ; median_s : float
    }
  [@@deriving sexp]
end

module Benchmark_result = struct
  (* Each [Sdf_runner.run] is timed in three cache states:

     - [cold]: a source the runner has never seen, evaluated at a fresh region, so it
       re-parses, re-compiles, prepares, and evaluates the whole grid.
     - [hot]: the same source at the same region as the previous run, so the runner serves
       a cached result without re-evaluating.
     - [warm]: the same source at a slightly shifted region, so the parse/compile/prepare
       results are reused but the grid is re-evaluated. *)
  type t =
    { name : string
    ; iterations : int
    ; cold : Stats.t
    ; hot : Stats.t
    ; warm : Stats.t
    }
  [@@deriving sexp]
end

module Suite_result = struct
  type t =
    { benchmarks : Benchmark_result.t list
    ; time_budget_s : float
    ; grid_width : int
    ; grid_height : int
    }
  [@@deriving sexp]
end
