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
              let compare_stat
                label
                (bs : Bench_types.Stats.t)
                (a_s : Bench_types.Stats.t)
                =
                let ratio = bs.mean_s /. a_s.mean_s in
                let pct = (ratio -. 1.0) *. 100.0 in
                let direction = if Float.(pct >= 0.0) then "faster" else "slower" in
                printf
                  "  %-20s  %8.3fms -> %8.3fms  (%+.1f%% %s)\n"
                  label
                  (bs.mean_s *. 1e3)
                  (a_s.mean_s *. 1e3)
                  pct
                  direction
              in
              compare_stat "cold (recompile)" b.cold a.cold;
              compare_stat "warm (re-eval)" b.warm a.warm;
              compare_stat "hot (cached)" b.hot a.hot;
              printf "\n"
            | Some _, None -> printf "=== %s (only in before) ===\n\n" name
            | None, Some _ -> printf "=== %s (only in after) ===\n\n" name
            | None, None -> ())))
;;
