open! Core

let load_result path =
  In_channel.read_all path |> Sexp.of_string |> [%of_sexp: Bench_types.Suite_result.t]
;;

let () =
  Command_unix.run
    (Command.basic
       ~summary:"Compare two SDF benchmark results"
       (let%map_open.Command before_path = anon ("BEFORE" %: string)
        and after_path = anon ("AFTER" %: string) in
        fun () ->
          let before = load_result before_path in
          let after = load_result after_path in
          if before.grid_width <> after.grid_width
             || before.grid_height <> after.grid_height
          then
            eprintf
              "Warning: grid sizes differ (%dx%d vs %dx%d)\n%!"
              before.grid_width
              before.grid_height
              after.grid_width
              after.grid_height;
          let before_map =
            List.map before.benchmarks ~f:(fun b -> b.name, b) |> String.Map.of_alist_exn
          in
          let after_map =
            List.map after.benchmarks ~f:(fun b -> b.name, b) |> String.Map.of_alist_exn
          in
          let all_names = Set.union (Map.key_set before_map) (Map.key_set after_map) in
          Set.iter all_names ~f:(fun name ->
            match Map.find before_map name, Map.find after_map name with
            | Some b, Some a ->
              printf "=== %s (%d -> %d iterations) ===\n" name b.iterations a.iterations;
              let describe_change before_s after_s =
                let ratio = before_s /. after_s in
                let pct = (ratio -. 1.0) *. 100.0 in
                let direction = if Float.(pct >= 0.0) then "faster" else "slower" in
                sprintf "(%+.1f%% %s)" pct direction
              in
              (* Phases are compared by path: the per-phase mean total before and after,
                 plus entries that exist on only one side (a pipeline restructure). The
                 union is ordered by the larger of the two means, so the most expensive
                 phases come first. *)
              let compare_phases
                (b_phases : Bench_types.Phase_stats.t list)
                (a_phases : Bench_types.Phase_stats.t list)
                =
                let to_map phases =
                  List.map phases ~f:(fun (p : Bench_types.Phase_stats.t) -> p.path, p)
                  |> String.Map.of_alist_exn
                in
                let b_map = to_map b_phases
                and a_map = to_map a_phases in
                Map.keys b_map @ Map.keys a_map
                |> List.dedup_and_sort ~compare:String.compare
                |> List.map ~f:(fun path ->
                  path, Map.find b_map path, Map.find a_map path)
                |> List.sort
                     ~compare:
                       (Comparable.lift Float.descending ~f:(fun (_, bp, ap) ->
                          let mean p =
                            Option.value_map
                              p
                              ~default:0.0
                              ~f:(fun (p : Bench_types.Phase_stats.t) -> p.total.mean_s)
                          in
                          Float.max (mean bp) (mean ap)))
                |> List.iter ~f:(fun (path, bp, ap) ->
                  match bp, ap with
                  | Some (bp : Bench_types.Phase_stats.t), Some ap ->
                    printf
                      "      %-44s  %8.3fms -> %8.3fms  %s\n"
                      path
                      (bp.total.mean_s *. 1e3)
                      (ap.total.mean_s *. 1e3)
                      (describe_change bp.total.mean_s ap.total.mean_s)
                  | Some bp, None ->
                    printf "      %-44s  %8.3fms -> (gone)\n" path (bp.total.mean_s *. 1e3)
                  | None, Some ap ->
                    printf "      %-44s  (new) -> %8.3fms\n" path (ap.total.mean_s *. 1e3)
                  | None, None -> ())
              in
              let compare_case label bc ac =
                match bc, ac with
                | ( Some (bc : Bench_types.Case.t)
                  , Some (ac : Bench_types.Case.t) ) ->
                  printf
                    "  %-20s  %8.3fms -> %8.3fms  %s\n"
                    label
                    (bc.time.mean_s *. 1e3)
                    (ac.time.mean_s *. 1e3)
                    (describe_change bc.time.mean_s ac.time.mean_s);
                  compare_phases bc.phases ac.phases
                | Some (bc : Bench_types.Case.t), None ->
                  printf "  %-20s  %8.3fms -> (not run)\n" label (bc.time.mean_s *. 1e3)
                | None, Some (ac : Bench_types.Case.t) ->
                  printf "  %-20s  (not run) -> %8.3fms\n" label (ac.time.mean_s *. 1e3)
                | None, None -> ()
              in
              compare_case "cold (recompile)" b.cold a.cold;
              compare_case "warm (re-eval)" b.warm a.warm;
              compare_case "hot (cached)" b.hot a.hot;
              printf "\n"
            | Some _, None -> printf "=== %s (only in before) ===\n\n" name
            | None, Some _ -> printf "=== %s (only in after) ===\n\n" name
            | None, None -> ())))
;;
