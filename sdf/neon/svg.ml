open! Core

let command =
  Command.basic
    ~summary:"Export SDF contour lines as SVG"
    (let%map_open.Command scene_file = anon ("SCENE_FILE" %: string)
     and output_file =
       flag "-o" (optional_with_default "output.svg" string) ~doc:"FILE Output SVG path"
     and min_x =
       flag "-min-x" (optional_with_default (-5.0) float) ~doc:"FLOAT Min X coordinate"
     and min_y =
       flag "-min-y" (optional_with_default (-5.0) float) ~doc:"FLOAT Min Y coordinate"
     and max_x =
       flag "-max-x" (optional_with_default 5.0 float) ~doc:"FLOAT Max X coordinate"
     and max_y =
       flag "-max-y" (optional_with_default 5.0 float) ~doc:"FLOAT Max Y coordinate"
     and resolution =
       flag "-resolution" (optional_with_default 256 int) ~doc:"INT Grid resolution"
     in
     fun () ->
       let source = In_channel.read_all scene_file in
       let tree = Neo.compile ~filename:scene_file source |> Or_error.ok_exn in
       let module B = Sdf.Expr_graph_batch_eval.Parallel in
       let prepared = B.Prepared.of_tree tree in
       let scheduler = Parallel_scheduler.create () in
       let width = resolution in
       let height = resolution in
       let dx = (max_x -. min_x) /. Float.of_int width in
       let dy = (max_y -. min_y) /. Float.of_int height in
       let grid =
         Parallel_scheduler.parallel scheduler ~f:(fun par ->
           let batch = B.Batch.create prepared ~width ~height in
           Option.iter (B.Prepared.lookup_variable prepared "x") ~f:(fun var ->
             B.Batch.set_affine batch ~var ~base:min_x ~dx ~dy:0.0);
           Option.iter (B.Prepared.lookup_variable prepared "y") ~f:(fun var ->
             B.Batch.set_affine batch ~var ~base:min_y ~dx:0.0 ~dy);
           let result = B.Batch.run batch ~par ~oracles:Sdf.Oracle.Key.Map.empty in
           let grid : float32# array = Array.create ~len:(width * height) #0.0s in
           for y = 0 to height - 1 do
             for x = 0 to width - 1 do
               grid.((y * width) + x) <- Sdf.Value.to_float (B.Result.get result ~x ~y)
             done
           done;
           grid)
       in
       let march_output : float32# array =
         Array.create ~len:(width * height * 2 * 4) #0.0s
       in
       let count = March.run grid march_output width height in
       let shapes = Line_join.f march_output ~length:count in
       let stroke_width = Float.min dx dy *. 0.5 in
       let world_x px = min_x +. (px *. dx) in
       let world_y py = min_y +. (py *. dy) in
       Out_channel.with_file output_file ~f:(fun oc ->
         Printf.fprintf
           oc
           {|<svg xmlns="http://www.w3.org/2000/svg" viewBox="%f %f %f %f">
|}
           min_x
           min_y
           (max_x -. min_x)
           (max_y -. min_y);
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
           if is_closed
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
         output_file)
;;
