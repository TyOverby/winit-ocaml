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
  (* Drive a grid-native {!Sdf.Batch_backend_intf.S_parallel} backend (the same interface
     [neon] uses), identified by a label. The GPU backend ONLY implements this interface;
     we run the CPU parallel backends through it too so the eval numbers are
     apples-to-apples. *)
  | Parallel of (module Sdf.Batch_backend_intf.S_parallel) * string

let parallel_backends : (string * (module Sdf.Batch_backend_intf.S_parallel)) list =
  [ "gpu", (module Sdf_gpu)
  ; "batch-parallel", (module Sdf.Expr_graph_batch_eval.Batch_parallel)
  ; "graph-parallel", (module Sdf.Expr_graph_eval.Batch_parallel)
  ; "tree-parallel", (module Sdf.Expr_tree_eval.Batch_parallel)
  ]
;;

(* A compiled program packed with the backend module that produced it (à la [neon]'s
   [Compiled]), so the [Prepared.t] can be evaluated later without losing its type. *)
type prepared_parallel =
  | Prepared_parallel :
      (module Sdf.Batch_backend_intf.S_parallel with type Prepared.t = 'p) * 'p
      -> prepared_parallel

let prepare_parallel (module B : Sdf.Batch_backend_intf.S_parallel) tree =
  Prepared_parallel ((module B), B.Prepared.of_tree tree)
;;

(* Evaluate the whole grid through the [S_parallel] interface, exactly the way [neon]
   does: bind [x] and [y] as affine functions of the pixel coordinate (so no per-pixel
   coordinate buffer is materialised) and evaluate in one shot.

   For the GPU backend the device/queue and the shader pipeline are created lazily inside
   [run] (the pipeline is cached, keyed by the WGSL source). So the FIRST call for a given
   expression pays a cold device-init + shader-compile cost; steady-state timings must
   exclude that by warming up once first (see [warm_parallel]). *)
let eval_parallel (Prepared_parallel ((module B), prepared)) ~scheduler =
  let batch = B.Batch.create prepared ~width:grid_width ~height:grid_height in
  Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:0.0 ~dx:1.0 ~dy:0.0);
  Option.iter (B.Prepared.lookup_variable prepared "y") ~f:(fun var ->
    B.Batch.set_affine batch ~var ~base:0.0 ~dx:0.0 ~dy:1.0);
  let (_ : B.Result.t) = B.Batch.run batch ~scheduler in
  ()
;;

let scheduler = lazy (Parallel_scheduler.create ())

(* Compile and evaluate once, untimed, so the GPU device exists and the shader for this
   expression is compiled and cached before we start the clock. Cheap no-op for the CPU
   parallel backends. *)
let warm_parallel backend ~source ~filename =
  let tree = Neo.compile ~filename source |> Or_error.ok_exn in
  let prepared = prepare_parallel backend tree in
  eval_parallel prepared ~scheduler:(Lazy.force scheduler)
;;

(* The [Parallel] path drives a grid-native backend through the [S_parallel] interface. We
   map its phases onto the same three timing slots the CPU pixel/batch path uses so the
   reporting/sexp format is unchanged:
   - [parse_and_compile_s]: [Neo.compile] (Neo source -> Expr_tree), as before;
   - [tree_to_graph_s]: the backend's [Prepared.of_tree] (its own lowering — for the GPU
     backend this includes generating the WGSL source, but NOT shader compilation, which
     happens lazily in [run]);
   - [eval_grid_s]: a WARM whole-grid [run]. The GPU device and the shader pipeline for
     this expression were created in the untimed [warm_parallel] pass, so this measures
     steady-state per-grid eval throughput (buffer alloc + input upload + dispatch +
     read-back), not the one-time setup. *)
let run_one_parallel ~source ~filename backend =
  let tree, parse_s =
    measure (fun () -> Neo.compile ~filename source |> Or_error.ok_exn)
  in
  let prepared, graph_s = measure (fun () -> prepare_parallel backend tree) in
  let (), eval_s =
    measure (fun () -> eval_parallel prepared ~scheduler:(Lazy.force scheduler))
  in
  { parse_and_compile_s = parse_s; tree_to_graph_s = graph_s; eval_grid_s = eval_s }
;;

let run_one_cpu ~source ~filename ~strategy =
  let tree, parse_s =
    measure (fun () -> Neo.compile ~filename source |> Or_error.ok_exn)
  in
  let (instructions, _final_register, register_count, x_idx, y_idx, num_vars), graph_s =
    measure (fun () ->
      let ~instructions, ~final_register, ~register_count:_, ~var_mapping =
        Sdf.Expr_graph.from_tree tree
      in
      let ~instructions, ~final_register, ~register_count =
        Sdf.Expr_graph_register_minimizer.minimize ~instructions ~final_register
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
        done
      | Parallel _ ->
        (* Dispatched by [run_one] before reaching here. *)
        assert false)
  in
  { parse_and_compile_s = parse_s; tree_to_graph_s = graph_s; eval_grid_s = eval_s }
;;

let run_one ~source ~filename ~strategy =
  match strategy with
  | Parallel (backend, _label) -> run_one_parallel ~source ~filename backend
  | Pixel | Batch -> run_one_cpu ~source ~filename ~strategy
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
            ~doc:
              "STRATEGY evaluation strategy: pixel (default), batch, or an S_parallel \
               backend (gpu, batch-parallel, graph-parallel, tree-parallel)"
        in
        fun () ->
          let strategy =
            match strategy with
            | "pixel" -> Pixel
            | "batch" -> Batch
            | s ->
              (match List.Assoc.find parallel_backends s ~equal:String.equal with
               | Some backend -> Parallel (backend, s)
               | None ->
                 eprintf
                   "Unknown strategy: %s (expected pixel, batch, gpu, batch-parallel, \
                    graph-parallel, or tree-parallel)\n"
                   s;
                 exit 1)
          in
          let files = discover_neo_files dir in
          if List.is_empty files
          then (
            eprintf "No .neo files found in %s\n" dir;
            exit 1);
          (* Warmup pass: for the GPU backend this creates the device/queue (process-wide,
             one-time) and compiles + caches the shader pipeline for each example, so
             those one-time costs are NOT charged to the timed estimation/benchmark passes
             below. Harmless (cheap) for the CPU backends. *)
          (match strategy with
           | Pixel | Batch -> ()
           | Parallel (backend, label) ->
             eprintf "Warming up %s backend (device init + shader compile)...\n%!" label;
             List.iter files ~f:(fun path ->
               let source = In_channel.read_all path in
               warm_parallel backend ~source ~filename:path));
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
