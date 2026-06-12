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
   leaves the grid size unchanged but defeats the runner's per-region result cache,
   forcing the grid to be re-evaluated. *)
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

module Phase_row = struct
  type t =
    { total_s : float
    ; self_s : float
    ; count : int
    }
end

(* One timed frame: its wall-clock time plus the per-phase breakdown of the trace recorded
   during it, flattened to "parent/child" paths. *)
type timed =
  { elapsed_s : float
  ; phases : (string * Phase_row.t) list
  }

(* The benchmark mirrors the neon UI's default (grayscale) frame as closely as possible: a
   sparse tiled evaluation with the constant-outside cull, then a per-pixel copy of the
   result into a canvas. [color_grayscale] is copied from sdf/neon/ui.ml. *)
let cull = Sdf.Tile_scheduler.Cull.Constant_outside { below = 0.; above = 1. }

let color_grayscale (dist : float) : Int32_u.t =
  if Float.(dist <= 0.0)
  then #0xFF000000l
  else if Float.(dist <= 1.0)
  then (
    let component = dist *. 255.0 |> Float.to_int |> Int32_u.of_int_trunc in
    Int32_u.(
      component lor shift_left component 8 lor shift_left component 16 lor #0xFF000000l))
  else #0xFFFFFFFFl
;;

let copy_pixels result ~canvas =
  Sdf.Tiled_eval.Result.iter
    result
    ~fill:(fun ~x0 ~y0 ~samples_x ~samples_y interval ->
      let #{ Sdf.Interval.lo = _; hi } = interval in
      let color = if Float32_u.O.(hi <= #0.s) then #0xFF000000l else #0xFFFFFFFFl in
      for y = y0 to y0 + samples_y - 1 do
        for x = x0 to x0 + samples_x - 1 do
          Image_buf.set canvas ~x ~y color
        done
      done)
    ~draw:(fun ~x0 ~y0 ~samples_x ~samples_y ~get ->
      for j = 0 to samples_y - 1 do
        for i = 0 to samples_x - 1 do
          let dist =
            Float32_u.to_float (Sdf.Value.to_float (get ((j * samples_x) + i)))
          in
          Image_buf.set canvas ~x:(x0 + i) ~y:(y0 + j) (color_grayscale dist)
        done
      done)
;;

let flatten_phases summary =
  let rec go prefix acc (nodes : Phase_trace.Summary.t list) =
    List.fold nodes ~init:acc ~f:(fun acc (node : Phase_trace.Summary.t) ->
      let path = if String.is_empty prefix then node.name else prefix ^ "/" ^ node.name in
      let row =
        { Phase_row.total_s = Time_ns.Span.to_sec node.total
        ; self_s = Time_ns.Span.to_sec node.self
        ; count = node.count
        }
      in
      go path ((path, row) :: acc) node.children)
  in
  List.rev (go "" [] summary)
;;

(* Time one UI-equivalent frame: [Sdf_runner.run_tiled] plus the pixel copy. The trace is
   created and summarized outside the measured section. *)
let time_run runner ~canvas ~region ~filename source =
  let trace = Phase_trace.create () in
  let (), elapsed =
    measure (fun () ->
      let result = Sdf_runner.run_tiled runner ~trace ~region ~filename source ~cull in
      Phase_trace.span trace "copy-pixels" ~f:(fun () -> copy_pixels result ~canvas))
  in
  let summary = Phase_trace.Summary.of_captured (Phase_trace.finish trace) in
  { elapsed_s = elapsed; phases = flatten_phases summary }
;;

(* Region offsets are drawn from a monotonically increasing counter so that successive
   warm/cold runs always sample a region the runner has not just cached. The "hot" region
   is fixed at offset 0 and never reused for warm/cold. *)
let next_offset = ref 0

let fresh_offset () =
  incr next_offset;
  !next_offset
;;

type sample =
  { cold : timed
  ; hot : timed
  ; warm : timed
  }

(* Drive [runner] through the three cache states for [source] and return their timings.

   The runner is stateful, so order matters:
   - Prime with the canonical source at offset 0 (untimed) to populate the cache.
   - [hot]: same source, same region -> served from cache.
   - [warm]: same source, fresh region -> grid re-evaluated, compile reused.
   - [cold]: a uniquely-perturbed source at a fresh region -> full recompile + re-eval.
     The trailing newlines change the source string (forcing a recompile) without changing
     the compiled tree, so the perturbation costs nothing beyond the recompile itself. *)
let sample_one runner ~canvas ~filename ~source =
  let hot_region = region_of 0 in
  let (_ : timed) = time_run runner ~canvas ~region:hot_region ~filename source in
  let hot = time_run runner ~canvas ~region:hot_region ~filename source in
  let warm =
    time_run runner ~canvas ~region:(region_of (fresh_offset ())) ~filename source
  in
  let cold =
    let offset = fresh_offset () in
    let perturbed = source ^ String.make offset '\n' in
    time_run runner ~canvas ~region:(region_of offset) ~filename perturbed
  in
  { cold; hot; warm }
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

(* Aggregate the per-run phase rows of one cache state into per-path statistics. Paths are
   kept in first-appearance order across runs; a run that lacks a path (e.g. an oracle
   served from the cache) contributes zeros for it. *)
let aggregate_phases (runs : timed list) : Bench_types.Phase_stats.t list =
  let n = List.length runs in
  let order =
    let seen = Hash_set.create (module String) in
    List.concat_map runs ~f:(fun r -> List.map r.phases ~f:fst)
    |> List.filter ~f:(fun path ->
      if Hash_set.mem seen path
      then false
      else (
        Hash_set.add seen path;
        true))
  in
  List.map order ~f:(fun path ->
    let rows =
      List.map runs ~f:(fun r -> List.Assoc.find r.phases path ~equal:String.equal)
    in
    let totals =
      List.map rows ~f:(function
        | Some (r : Phase_row.t) -> r.total_s
        | None -> 0.0)
    in
    let selfs =
      List.map rows ~f:(function
        | Some (r : Phase_row.t) -> r.self_s
        | None -> 0.0)
    in
    let count =
      List.sum (module Int) rows ~f:(function
        | Some r -> r.count
        | None -> 0)
    in
    { Bench_types.Phase_stats.path
    ; mean_count = Float.of_int count /. Float.of_int n
    ; total = compute_stats totals
    ; self = compute_stats selfs
    })
;;

let compute_case (runs : timed list) : Bench_types.Case.t =
  { time = compute_stats (List.map runs ~f:(fun r -> r.elapsed_s))
  ; phases = aggregate_phases runs
  }
;;

(* Render the per-phase stats of one cache state as a box-drawing tree, rebuilding the
   nesting from the "parent/child" paths. Children keep their first-appearance order,
   which is the order the phases first executed. *)
let phase_tree_lines (phases : Bench_types.Phase_stats.t list) ~indent =
  let module Node = struct
    type t =
      { mutable stats : Bench_types.Phase_stats.t option
      ; mutable children_rev : (string * t) list
      }

    let create () = { stats = None; children_rev = [] }
  end
  in
  let root = Node.create () in
  let find_or_add (node : Node.t) seg =
    match List.Assoc.find node.children_rev seg ~equal:String.equal with
    | Some child -> child
    | None ->
      let child = Node.create () in
      node.children_rev <- (seg, child) :: node.children_rev;
      child
  in
  List.iter phases ~f:(fun p ->
    let node = List.fold (String.split p.path ~on:'/') ~init:root ~f:find_or_add in
    node.stats <- Some p);
  let label seg (stats : Bench_types.Phase_stats.t option) =
    match stats with
    | None -> seg
    | Some p ->
      let n =
        if Float.( = ) p.mean_count 1.0 then "" else sprintf " n=%.0f" p.mean_count
      in
      sprintf
        "%s: %.3fms self=%.3fms%s"
        seg
        (p.total.mean_s *. 1e3)
        (p.self.mean_s *. 1e3)
        n
  in
  let rec to_tree seg (node : Node.t) : Expectree.t =
    let children =
      List.rev node.children_rev |> List.map ~f:(fun (seg, child) -> to_tree seg child)
    in
    match children with
    | [] -> Expectree.Leaf (label seg node.stats)
    | children -> Expectree.Branch (label seg node.stats, children)
  in
  let roots =
    List.rev root.children_rev |> List.map ~f:(fun (seg, child) -> to_tree seg child)
  in
  let rendered =
    match roots with
    | [] -> ""
    | [ tree ] -> Expectree.to_string tree
    | trees -> Expectree.to_string (Expectree.Split trees)
  in
  String.split_lines rendered |> List.map ~f:(fun line -> String.make indent ' ' ^ line)
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
          let canvas = Image_buf.create ~width:grid_width ~height:grid_height #0l in
          let sources =
            List.map files ~f:(fun path ->
              Filename.basename path, path, In_channel.read_all path)
          in
          (* Warmup pass: spin up worker domains and populate caches. *)
          eprintf "Warming up %s backend...\n%!" strategy;
          List.iter sources ~f:(fun (_name, path, source) ->
            let (_ : sample) = sample_one runner ~canvas ~filename:path ~source in
            ());
          (* Estimation pass: one sample per file to size the iteration count. *)
          eprintf "Running estimation pass...\n%!";
          let estimates =
            List.map sources ~f:(fun (name, path, source) ->
              let s = sample_one runner ~canvas ~filename:path ~source in
              let est_total = s.cold.elapsed_s +. s.hot.elapsed_s +. s.warm.elapsed_s in
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
                List.init iterations ~f:(fun _ ->
                  sample_one runner ~canvas ~filename:path ~source)
              in
              eprintf "done\n%!";
              let all = est :: samples in
              let n = List.length all in
              { Bench_types.Benchmark_result.name
              ; iterations = n
              ; cold = compute_case (List.map all ~f:(fun s -> s.cold))
              ; hot = compute_case (List.map all ~f:(fun s -> s.hot))
              ; warm = compute_case (List.map all ~f:(fun s -> s.warm))
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
              let print_case label (c : Bench_types.Case.t) =
                let s = c.time in
                printf
                  "  %-20s  mean: %10.3fms  stddev: %10.3fms  min: %10.3fms  max: \
                   %10.3fms  median: %10.3fms\n"
                  label
                  (s.mean_s *. 1e3)
                  (s.stddev_s *. 1e3)
                  (s.min_s *. 1e3)
                  (s.max_s *. 1e3)
                  (s.median_s *. 1e3);
                List.iter (phase_tree_lines c.phases ~indent:6) ~f:print_endline
              in
              print_case "cold (recompile)" b.cold;
              print_case "warm (re-eval)" b.warm;
              print_case "hot (cached)" b.hot;
              printf "\n")))
;;
