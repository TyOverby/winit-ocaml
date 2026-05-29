open! Core

let grid_width = 1000
let grid_height = 1000

let measure f =
  let start = Time_ns.now () in
  let result = f () in
  let elapsed = Time_ns.Span.to_sec (Time_ns.diff (Time_ns.now ()) start) in
  result, elapsed
;;

type timing =
  { parse_and_compile_s : float
  ; tree_to_graph_s : float
  ; eval_grid_s : float
  }

type strategy =
  | Pixel
  | Batch

let run_one ~source ~filename ~strategy =
  let tree, parse_s =
    measure (fun () -> Neo.compile ~filename source |> Or_error.ok_exn)
  in
  let (instructions, _final_register, register_count, x_idx, y_idx, num_vars), graph_s =
    measure (fun () ->
      let ~instructions, ~final_register, ~register_count, ~var_mapping =
        Sdf.Expr_graph.from_tree tree
      in
      let ~instructions, ~final_register, ~register_count =
        Sdf.Expr_graph_register_minimizer.minimize
          ~instructions
          ~final_register
          ~register_count
      in
      let x_idx = Hashtbl.find_exn var_mapping "x" in
      let y_idx = Hashtbl.find_exn var_mapping "y" in
      let num_vars = Hashtbl.length var_mapping in
      instructions, final_register, register_count, x_idx, y_idx, num_vars)
  in
  let (), eval_s =
    measure (fun () ->
      match strategy with
      | Pixel ->
        for y = 0 to grid_height - 1 do
          let variables = Sdf.Value.Array.create ~len:num_vars in
          let registers = Sdf.Value.Array.create ~len:register_count in
          Sdf.Value.Array.set_float variables y_idx (Float32_u.of_float (Float.of_int y));
          for x = 0 to grid_width - 1 do
            Sdf.Value.Array.set_float
              variables
              x_idx
              (Float32_u.of_float (Float.of_int x));
            Sdf.Expr_graph_eval.run ~variables ~instructions ~registers
          done
        done
      | Batch ->
        let register_bank =
          Sdf.Expr_graph_batch_eval.Register_bank.create ~register_count ~width:grid_width
        in
        let variable_bank =
          Sdf.Expr_graph_batch_eval.Variable_bank.create ~num_vars ~width:grid_width
        in
        for y = 0 to grid_height - 1 do
          let y_val = Sdf.Value.of_float (Float32_u.of_float (Float.of_int y)) in
          for x = 0 to grid_width - 1 do
            Sdf.Expr_graph_batch_eval.Variable_bank.set_variable
              variable_bank
              ~var:y_idx
              ~px:x
              y_val;
            Sdf.Expr_graph_batch_eval.Variable_bank.set_variable
              variable_bank
              ~var:x_idx
              ~px:x
              (Sdf.Value.of_float (Float32_u.of_float (Float.of_int x)))
          done;
          Sdf.Expr_graph_batch_eval.run
            ~variable_bank
            ~instructions
            ~register_bank
            ~width:grid_width
        done)
  in
  { parse_and_compile_s = parse_s; tree_to_graph_s = graph_s; eval_grid_s = eval_s }
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
            (optional_with_default "pixel" string)
            ~doc:"STRATEGY evaluation strategy: pixel (default) or batch"
        in
        fun () ->
          let strategy =
            match strategy with
            | "pixel" -> Pixel
            | "batch" -> Batch
            | s ->
              eprintf "Unknown strategy: %s (expected pixel or batch)\n" s;
              exit 1
          in
          let files = discover_neo_files dir in
          if List.is_empty files
          then (
            eprintf "No .neo files found in %s\n" dir;
            exit 1);
          (* Estimation pass: run each benchmark once *)
          eprintf "Running estimation pass...\n%!";
          let benchmarks =
            List.map files ~f:(fun path ->
              let name = Filename.basename path in
              let source = In_channel.read_all path in
              let est = run_one ~source ~filename:path ~strategy in
              let est_total =
                est.parse_and_compile_s +. est.tree_to_graph_s +. est.eval_grid_s
              in
              eprintf "  %s: %.3fms\n%!" name (est_total *. 1e3);
              name, source, path, est, est_total)
          in
          let total_est =
            List.sum (module Float) benchmarks ~f:(fun (_, _, _, _, t) -> t)
          in
          let iterations = Int.max 1 (int_of_float (budget /. total_est)) in
          eprintf
            "Estimated time per pass: %.3fms\nRunning %d iterations...\n%!"
            (total_est *. 1e3)
            iterations;
          (* Benchmark pass *)
          let results =
            List.map benchmarks ~f:(fun (name, source, path, est, _) ->
              eprintf "  %s: %d iterations... %!" name iterations;
              let timings =
                List.init iterations ~f:(fun _ ->
                  run_one ~source ~filename:path ~strategy)
              in
              eprintf "done\n%!";
              let all_timings = est :: timings in
              let n = List.length all_timings in
              let parse_samples =
                List.map all_timings ~f:(fun t -> t.parse_and_compile_s)
              in
              let graph_samples = List.map all_timings ~f:(fun t -> t.tree_to_graph_s) in
              let eval_samples = List.map all_timings ~f:(fun t -> t.eval_grid_s) in
              let total_samples =
                List.map all_timings ~f:(fun t ->
                  t.parse_and_compile_s +. t.tree_to_graph_s +. t.eval_grid_s)
              in
              { Bench_types.Benchmark_result.name
              ; iterations = n
              ; parse_and_compile = compute_stats parse_samples
              ; tree_to_graph = compute_stats graph_samples
              ; eval_grid = compute_stats eval_samples
              ; total = compute_stats total_samples
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
              print_stat "parse+compile" b.parse_and_compile;
              print_stat "tree->graph" b.tree_to_graph;
              print_stat "eval (1000x1000)" b.eval_grid;
              print_stat "total" b.total;
              printf "\n")))
;;
