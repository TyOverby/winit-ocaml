open! Core

(* Get output path for test artifacts. When running via dune runtest (cwd is in _build),
   write next to the executable. When running via dune exec (cwd is not in _build),
   write to the source directory. *)
let output_path filename =
  let cwd = Stdlib.Sys.getcwd () in
  let in_build = String.is_substring cwd ~substring:"_build" in
  if in_build
  then filename
  else (
    let filename = Filename.concat "/tmp/" filename in
    print_endline ("writing to " ^ filename);
    filename)
;;

(* Write RGBA pixel data to a PPM file (P6 binary format) *)
let write_ppm ~filename ~width ~height ~data ~bytes_per_row =
  Out_channel.with_file filename ~f:(fun oc ->
    (* PPM header: P6 for binary RGB *)
    Out_channel.fprintf oc "P6\n%d %d\n255\n" width height;
    (* Write RGB data (skip alpha) *)
    for y = 0 to height - 1 do
      for x = 0 to width - 1 do
        let offset = (y * bytes_per_row) + (x * 4) in
        let r = Bigarray.Array1.get data offset in
        let g = Bigarray.Array1.get data (offset + 1) in
        let b = Bigarray.Array1.get data (offset + 2) in
        Out_channel.output_char oc (Char.of_int_exn r);
        Out_channel.output_char oc (Char.of_int_exn g);
        Out_channel.output_char oc (Char.of_int_exn b)
      done
    done)
;;

(* Convert PPM to PNG using ImageMagick *)
let ppm_to_png ~ppm_file ~png_file =
  (* Exclude timestamp chunks to ensure reproducible output *)
  let cmd =
    sprintf "convert %s -define png:exclude-chunks=date,time %s" ppm_file png_file
  in
  match Core_unix.system cmd with
  | Ok () -> ()
  | Error e ->
    Error.raise_s
      [%message "Error: ImageMagick convert failed" (e : Core_unix.Exit_or_signal.error)]
;;

(* Load a PNG file into RGBA pixel data using ImageMagick.
   Returns (width, height, data) where data is a Bigarray of RGBA bytes. *)
let load_png ~filename =
  (* Use ImageMagick to get dimensions *)
  let identify_cmd = sprintf "identify -format '%%w %%h' %s" filename in
  let width, height =
    let ic = Core_unix.open_process_in identify_cmd in
    let line = In_channel.input_line_exn ic in
    (match Core_unix.close_process_in ic with
     | Ok () -> ()
     | Error _ -> failwith "identify command failed");
    match String.split line ~on:' ' with
    | [ w; h ] -> Int.of_string w, Int.of_string h
    | _ -> failwith "Failed to parse image dimensions"
  in
  (* Convert to raw RGBA and read *)
  let convert_cmd = sprintf "convert %s -depth 8 rgba:-" filename in
  let ic = Core_unix.open_process_in convert_cmd in
  let data_size = width * height * 4 in
  let data = Bigarray.Array1.create Bigarray.int8_unsigned Bigarray.c_layout data_size in
  let bytes_read = ref 0 in
  (try
     while !bytes_read < data_size do
       let c = In_channel.input_char ic in
       match c with
       | Some ch ->
         Bigarray.Array1.set data !bytes_read (Char.to_int ch);
         incr bytes_read
       | None -> failwith "Unexpected end of image data"
     done
   with
   | End_of_file -> failwith "Unexpected end of image data");
  (match Core_unix.close_process_in ic with
   | Ok () -> ()
   | Error _ -> failwith "convert command failed");
  width, height, data
;;
