open! Core

(* Get output path for test artifacts. When running via dune runtest (cwd is in _build),
   write next to the executable. When running via dune exec (cwd is not in _build),
   write to the source directory. *)
let output_path filename =
  let cwd = Stdlib.Sys.getcwd () in
  let in_build = String.is_substring cwd ~substring:"_build" in
  if in_build
  then (
    (* Running in _build (e.g., dune runtest) - write next to executable *)
    let exe_dir = Filename.dirname Stdlib.Sys.executable_name in
    Filename.concat exe_dir filename)
  else (
    (* Running outside _build (e.g., dune exec) - write to source directory *)
    let exe_path = Stdlib.Sys.executable_name in
    (* exe_path is like _build/default/test/test_compute.exe *)
    (* Strip _build/default/ prefix to get test/test_compute.exe, then take dirname *)
    let relative =
      match String.substr_replace_first exe_path ~pattern:"_build/default/" ~with_:"" with
      | s when not (String.equal s exe_path) -> Filename.dirname s
      | _ -> Filename.dirname exe_path
    in
    Filename.concat relative filename)
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
