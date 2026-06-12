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

module Phase_stats = struct
  (* Statistics for one phase path (e.g. "run/prepare-oracles/oracle:resample") of the
     collapsed [Phase_trace.Summary] recorded during each run, aggregated across the
     iterations of one cache state. [total] is the phase's summed duration within a run
     (lanes included, so under parallelism it can exceed wall clock); [self] excludes time
     spent in child phases. A path absent from some iteration (e.g. an oracle served from
     the cache) contributes a zero sample to that iteration. *)
  type t =
    { path : string
    ; mean_count : float (* mean number of collapsed spans per run *)
    ; total : Stats.t
    ; self : Stats.t
    }
  [@@deriving sexp]
end

module Case = struct
  (* One cache state (cold/hot/warm): wall-clock stats plus the per-phase breakdown. *)
  type t =
    { time : Stats.t
    ; phases : Phase_stats.t list
    }
  [@@deriving sexp]
end

module Benchmark_result = struct
  (* Each [Sdf_runner.run_tiled] is timed in three cache states:

     - [cold]: a source the runner has never seen, evaluated at a fresh region, so it
       re-parses, re-compiles, prepares, and evaluates the whole grid.
     - [hot]: the same source at the same region as the previous run, so the runner serves
       a cached result without re-evaluating.
     - [warm]: the same source at a slightly shifted region, so the parse/compile/prepare
       results are reused but the grid is re-evaluated. *)
  type t =
    { name : string
    ; iterations : int
    ; cold : Case.t
    ; hot : Case.t
    ; warm : Case.t
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
