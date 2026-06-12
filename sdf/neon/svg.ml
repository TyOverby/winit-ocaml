open! Core

let oracle_registry : unit -> (string * (module Sdf.Oracle.S) portable) list =
  fun () ->
  [ "passthrough", { portable = (module Sdf_passthrough_oracle) }
  ; "resample", { portable = (module Sdf_resample_oracle) }
  ]
;;

let command =
  Command.basic
    ~summary:"Export SDF contour lines as SVG"
    (let%map_open.Command scene_file = anon ("SCENE_FILE" %: string)
     and output_file =
       flag "-o" (optional_with_default "output.svg" string) ~doc:"FILE Output SVG path"
     and x =
       flag "-x" (optional_with_default "0.0" string) ~doc:"FLOAT Top-left X coordinate"
     and y =
       flag "-y" (optional_with_default "0.0" string) ~doc:"FLOAT Top-left Y coordinate"
     and width = flag "-width" (optional_with_default 256 int) ~doc:"INT Width in pixels"
     and height =
       flag "-height" (optional_with_default 256 int) ~doc:"INT Height in pixels"
     and filled =
       flag
         "-filled"
         (optional_with_default true bool)
         ~doc:"BOOL Fill closed contours (default true); false exports only line segments"
     and trace_file =
       flag
         "-trace-file"
         (optional string)
         ~doc:"FILE write a Perfetto trace (.fxt) of the export to FILE"
     in
     fun () ->
       let source = In_channel.read_all scene_file in
       (* One world unit per pixel, so the sample resolution is just the pixel
          width/height and [dx = dy = 1]. *)
       let x = Float32_u.of_string x
       and y = Float32_u.of_string y in
       let region =
         let open Float32_u in
         { Sdf.Sample_region.start_x = x
         ; end_x = x + of_int width
         ; samples_x = width
         ; start_y = y
         ; end_y = y + of_int height
         ; samples_y = height
         }
       in
       let runner = Sdf_runner.create () in
       List.iter (oracle_registry ()) ~f:(fun (name, { portable = oracle }) ->
         Sdf_runner.add_oracle runner ~name oracle);
       let trace =
         match trace_file with
         | None -> Phase_trace.null ()
         | Some _ -> Phase_trace.create ~name:"neon-svg" ()
       in
       let ~segments:march_output, ~length:count, ~stats =
         Sdf_runner.run_contour runner ~trace ~region ~filename:scene_file source
       in
       let shapes =
         Phase_trace.span trace "line-join" ~f:(fun () ->
           Line_join.f march_output ~length:count)
       in
       (match trace_file with
        | None -> ()
        | Some filename ->
          Phase_trace_perfetto.write_file (Phase_trace.finish trace) ~filename;
          printf "Wrote Perfetto trace to %s (open at https://ui.perfetto.dev)\n" filename);
       let stroke_width = 0.5 in
       let x = Float32_u.to_float x
       and y = Float32_u.to_float y in
       let world_x px = x +. px in
       let world_y py = y +. py in
       Out_channel.with_file output_file ~f:(fun oc ->
         Printf.fprintf
           oc
           {|<svg xmlns="http://www.w3.org/2000/svg" viewBox="%f %f %f %f">
|}
           x
           y
           (Float.of_int width)
           (Float.of_int height);
         List.iter shapes ~f:(fun shape ->
           let points =
             match shape with
             | Line_join.Connected.Joined pts | Disjoint pts -> pts
           in
           let is_closed =
             match shape with
             | Joined _ -> true
             | Disjoint _ -> false
           in
           let points_str =
             List.map points ~f:(fun { Line_join.Point.x; y } ->
               sprintf "%f,%f" (world_x x) (world_y y))
             |> String.concat ~sep:" "
           in
           if is_closed && filled
           then
             Printf.fprintf
               oc
               {|  <polygon points="%s" fill="black" stroke="black" stroke-width="%f"/>
|}
               points_str
               stroke_width
           else
             Printf.fprintf
               oc
               {|  <polyline points="%s" fill="none" stroke="black" stroke-width="%f"/>
|}
               points_str
               stroke_width);
         Printf.fprintf oc "</svg>\n");
       printf
         "Wrote %d shapes (%d line segments) to %s\n"
         (List.length shapes)
         count
         output_file;
       printf
         "Culling skipped %d of %d tiles (%d samples evaluated)\n"
         stats.Sdf_contour.Stats.tiles_culled
         stats.tiles_total
         stats.samples_evaluated)
;;
