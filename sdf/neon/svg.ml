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
       let stroke_width = Float.min dx dy *. 0.5 in
       Out_channel.with_file output_file ~f:(fun oc ->
         Printf.fprintf
           oc
           {|<svg xmlns="http://www.w3.org/2000/svg" viewBox="%f %f %f %f">
|}
           min_x
           min_y
           (max_x -. min_x)
           (max_y -. min_y);
         for i = 0 to count - 1 do
           let px1 = Float32_u.to_float march_output.(i * 4) in
           let py1 = Float32_u.to_float march_output.((i * 4) + 1) in
           let px2 = Float32_u.to_float march_output.((i * 4) + 2) in
           let py2 = Float32_u.to_float march_output.((i * 4) + 3) in
           let wx1 = min_x +. (px1 *. dx) in
           let wy1 = min_y +. (py1 *. dy) in
           let wx2 = min_x +. (px2 *. dx) in
           let wy2 = min_y +. (py2 *. dy) in
           Printf.fprintf
             oc
             {|  <line x1="%f" y1="%f" x2="%f" y2="%f" stroke="black" stroke-width="%f"/>
|}
             wx1
             wy1
             wx2
             wy2
             stroke_width
         done;
         Printf.fprintf oc "</svg>\n");
       printf "Wrote %d line segments to %s\n" count output_file)
;;
