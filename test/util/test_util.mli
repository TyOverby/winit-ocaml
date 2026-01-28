open! Core

(** Get output path for test artifacts. When running via dune runtest (cwd is in _build),
    writes next to the executable. When running via dune exec (cwd is not in _build),
    writes to the source directory. *)
val output_path : string -> string

(** Write RGBA pixel data to a PPM file (P6 binary format). The data is expected to be
    RGBA with 4 bytes per pixel. Only RGB channels are written to the output. *)
val write_ppm
  :  filename:string
  -> width:int
  -> height:int
  -> data:(int, Bigarray.int8_unsigned_elt, Bigarray.c_layout) Bigarray.Array1.t
  -> bytes_per_row:int
  -> unit

(** Convert PPM to PNG using ImageMagick. Raises if ImageMagick convert command fails. *)
val ppm_to_png : ppm_file:string -> png_file:string -> unit
