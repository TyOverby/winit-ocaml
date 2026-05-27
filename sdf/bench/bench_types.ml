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
  type t =
    { name : string
    ; iterations : int
    ; parse_and_compile : Stats.t
    ; tree_to_graph : Stats.t
    ; eval_grid : Stats.t
    ; total : Stats.t
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
