open! Core

let grid_width = 1000
let grid_height = 1000

(* The available evaluation backends, each a [(module Sdf.Executor.S)], selected by the
   [-strategy] flag. These mirror the backends offered by the neon UI. *)
let backends : (string * (module Sdf.Executor.S) portable) list =
  [ "batch", { portable = (module Sdf.Expr_graph_batch_eval) }
  ; "graph", { portable = (module Sdf.Expr_graph_eval) }
  ; "tree", { portable = (module Sdf.Expr_tree_eval) }
  ]
;;

(* Oracles that the example scenes may reference (e.g. [resample(...)]). Registering them
   lets the runner compile scenes that depend on them. *)
let oracle_registry : (string * (module Sdf.Oracle.S) portable) list =
  [ "passthrough", { portable = (module Sdf_passthrough_oracle) }
  ; "resample", { portable = (module Sdf_resample_oracle) }
  ]
;;

(* A 1000x1000 sample region shifted by [offset] samples in both axes. Shifting the region
   leaves the grid size unchanged but defeats the runner's per-region result cache, forcing
   the grid to be re-evaluated. *)
let region_of offset =
  let open Float32_u in
  { Sdf.Sample_region.start_x = of_int offset
  ; end_x = of_int offset + of_int grid_width
  ; samples_x = grid_width
  ; start_y = of_int offset
  ; end_y = of_int offset + of_int grid_height
  ; samples_y = grid_height
  }
;;

let measure f =
  let start = Time_ns.now () in
  let result = f () in
  let elapsed = Time_ns.Span.to_sec (Time_ns.diff (Time_ns.now ()) start) in
  result, elapsed
;;

(* Time a single [Sdf_runner.run]. The grid is evaluated eagerly inside [run]; the callback
   does no work so we measure only the runner's pipeline, not pixel readback. *)
let time_run runner ~region ~filename source =
  let (), elapsed =
    measure (fun () ->
      Sdf_runner.run runner ~region ~filename source ~f:(fun _par _result _get -> ()))
  in
  elapsed
;;

(* Region offsets are drawn from a monotonically increasing counter so that successive
   warm/cold runs always sample a region the runner has not just cached. The "hot" region is
   fixed at offset 0 and never reused for warm/cold. *)
let next_offset = ref 0

let fresh_offset () =
  incr next_offset;
  !next_offset
;;

type sample =
  { cold_s : float
  ; hot_s : float
  ; warm_s : float
  }

(* Drive [runner] through the three cache states for [source] and return their timings.

   The runner is stateful, so order matters:
   - Prime with the canonical source at offset 0 (untimed) to populate the cache.
   - [hot]: same source, same region -> served from cache.
   - [warm]: same source, fresh region -> grid re-evaluated, compile reused.
   - [cold]: a uniquely-perturbed source at a fresh region -> full recompile + re-eval. The
     trailing newlines change the source string (forcing a recompile) without changing the
     compiled tree, so the perturbation costs nothing beyond the recompile itself. *)
let sample_one runner ~filename ~source =
  let hot_region = region_of 0 in
  let (_ : float) = time_run runner ~region:hot_region ~filename source in
  let hot_s = time_run runner ~region:hot_region ~filename source in
  let warm_s = time_run runner ~region:(region_of (fresh_offset ())) ~filename source in
  let cold_s =
    let offset = fresh_offset () in
    let perturbed = source ^ String.make offset '\n' in
    time_run runner ~region:(region_of offset) ~filename perturbed
  in
  { cold_s; hot_s; warm_s }
;;

let compute_stats samples =
  let sorted = List.sort samples ~compare:Float.compare |> Array.of_list in
  let n = Array.length sorted in
  let sum = Array.fold sorted ~init:0.0 ~f:( +. ) in
  let mean = sum /. Float.of_int n in
  let variance =
    Array.fold sorted ~init:0.0 ~f:(fun acc x ->
      let diff = x -. mean in
      acc +. (diff *. diff))
    /. Float.of_int n
  in
  { Bench_types.Stats.mean_s = mean
  ; min_s = sorted.(0)
  ; max_s = sorted.(n - 1)
  ; median_s = sorted.(n / 2)
  ; stddev_s = Float.sqrt variance
  }
;;

let discover_neo_files dir =
  Sys_unix.ls_dir dir
  |> List.filter ~f:(String.is_suffix ~suffix:".neo")
  |> List.sort ~compare:String.compare
  |> List.map ~f:(fun f -> Filename.concat dir f)
;;

let make_runner backend =
  let runner = Sdf_runner.create backend in
  List.iter oracle_registry ~f:(fun (name, { portable = oracle }) ->
    Sdf_runner.add_oracle runner ~name oracle);
  runner
;;

let () =
  Command_unix.run
    (Command.basic
       ~summary:"Run SDF benchmarks"
       (let%map_open.Command dir =
          flag
            "-dir"
            (optional_with_default "sdf/bench/examples" string)
            ~doc:"DIR directory containing .neo files (default: sdf/bench/examples)"
        and budget =
          flag
            "-budget"
            (optional_with_default 10.0 float)
            ~doc:"SECONDS time budget for benchmarking (default: 10)"
        and dump_sexp = flag "-dump-sexp" no_arg ~doc:" output results as sexp"
        and strategy =
          flag
            "-strategy"
            (optional_with_default "graph" string)
            ~doc:"STRATEGY evaluation backend: graph (default), batch, tree"
        in
        fun () ->
          let backend =
            match List.Assoc.find backends strategy ~equal:String.equal with
            | Some backend -> backend
            | None ->
              eprintf
                "Unknown strategy: %s (expected %s)\n"
                strategy
                (String.concat ~sep:", " (List.map backends ~f:fst));
              exit 1
          in
          let files = discover_neo_files dir in
          if List.is_empty files
          then (
            eprintf "No .neo files found in %s\n" dir;
            exit 1);
          let runner = make_runner backend.portable in
          let sources =
            List.map files ~f:(fun path ->
              Filename.basename path, path, In_channel.read_all path)
          in
          (* Warmup pass: spin up worker domains and populate caches. *)
          eprintf "Warming up %s backend...\n%!" strategy;
          List.iter sources ~f:(fun (_name, path, source) ->
            let (_ : sample) = sample_one runner ~filename:path ~source in
            ());
          (* Estimation pass: one sample per file to size the iteration count. *)
          eprintf "Running estimation pass...\n%!";
          let estimates =
            List.map sources ~f:(fun (name, path, source) ->
              let s = sample_one runner ~filename:path ~source in
              let est_total = s.cold_s +. s.hot_s +. s.warm_s in
              eprintf "  %s: %.3fms\n%!" name (est_total *. 1e3);
              name, path, source, s, est_total)
          in
          let total_est =
            List.sum (module Float) estimates ~f:(fun (_, _, _, _, t) -> t)
          in
          let iterations = Int.max 1 (int_of_float (budget /. total_est)) in
          eprintf
            "Estimated time per pass: %.3fms\nRunning %d iterations...\n%!"
            (total_est *. 1e3)
            iterations;
          (* Benchmark pass. *)
          let results =
            List.map estimates ~f:(fun (name, path, source, est, _) ->
              eprintf "  %s: %d iterations... %!" name iterations;
              let samples =
                List.init iterations ~f:(fun _ -> sample_one runner ~filename:path ~source)
              in
              eprintf "done\n%!";
              let all = est :: samples in
              let n = List.length all in
              { Bench_types.Benchmark_result.name
              ; iterations = n
              ; cold = compute_stats (List.map all ~f:(fun s -> s.cold_s))
              ; hot = compute_stats (List.map all ~f:(fun s -> s.hot_s))
              ; warm = compute_stats (List.map all ~f:(fun s -> s.warm_s))
              })
          in
          let suite =
            { Bench_types.Suite_result.benchmarks = results
            ; time_budget_s = budget
            ; grid_width
            ; grid_height
            }
          in
          if dump_sexp
          then print_s [%sexp (suite : Bench_types.Suite_result.t)]
          else
            List.iter results ~f:(fun b ->
              printf "=== %s (%d iterations) ===\n" b.name b.iterations;
              let print_stat label (s : Bench_types.Stats.t) =
                printf
                  "  %-20s  mean: %10.3fms  stddev: %10.3fms  min: %10.3fms  max: \
                   %10.3fms  median: %10.3fms\n"
                  label
                  (s.mean_s *. 1e3)
                  (s.stddev_s *. 1e3)
                  (s.min_s *. 1e3)
                  (s.max_s *. 1e3)
                  (s.median_s *. 1e3)
              in
              print_stat "cold (recompile)" b.cold;
              print_stat "warm (re-eval)" b.warm;
              print_stat "hot (cached)" b.hot;
              printf "\n")))
;;
