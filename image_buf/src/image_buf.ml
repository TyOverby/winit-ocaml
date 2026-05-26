open Stdlib_upstream_compatible
open! Base

module Rect = struct
  type t =
    #{ x : int
     ; y : int
     ; w : int
     ; h : int
     }
end

type t =
  { (* a bigarray of size width*height of int32 where
       each element represents a pixel in AARRGGBB format *)
    buffer : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
  ; width : int
  ; height : int
  ; transparency : bool
  }

let create ?(transparency = false) ~width ~height color =
  let buffer = Bigarray.Array1.create Bigarray.Int32 Bigarray.C_layout (width * height) in
  let color_boxed @ local = Int32_u.to_int32 color in
  Bigarray.Array1.fill buffer color_boxed;
  { buffer; width; height; transparency }
;;

let from_external ?(transparency = false) ~width ~height buffer =
  { buffer; width; height; transparency }
;;

let width { width; _ } = width
let height { height; _ } = height
let transparency { transparency; _ } = transparency

let get t ~x ~y =
  let a @ local = Bigarray.Array1.get t.buffer ((y * t.width) + x) in
  Int32_u.of_int32 a
;;

let set t ~x ~y v =
  let v @ local = Int32_u.to_int32 v in
  Bigarray.Array1.set t.buffer ((y * t.width) + x) v
;;

let blit ~from ~(region : Rect.t) ~to_ ~x:dst_x ~y:dst_y =
  (* Fast path: full-buffer blit when source and dest are the same size,
     region covers the entire source, and destination offset is zero. *)
  let #{ Rect.x = src_x; y = src_y; w; h } = region in
  if dst_x = 0
     && dst_y = 0
     && src_x = 0
     && src_y = 0
     && w = from.width
     && h = from.height
     && from.width = to_.width
     && from.height = to_.height
  then Bigarray.Array1.blit from.buffer to_.buffer
  else (
    (* Clip source to from's bounds (left/top) *)
    let dst_x, w, src_x =
      if src_x < 0 then dst_x - src_x, w + src_x, 0 else dst_x, w, src_x
    in
    let dst_y, h, src_y =
      if src_y < 0 then dst_y - src_y, h + src_y, 0 else dst_y, h, src_y
    in
    (* Clip destination to to_'s bounds (left/top) *)
    let src_x, w, dst_x =
      if dst_x < 0 then src_x - dst_x, w + dst_x, 0 else src_x, w, dst_x
    in
    let src_y, h, dst_y =
      if dst_y < 0 then src_y - dst_y, h + dst_y, 0 else src_y, h, dst_y
    in
    (* Clip source to from's bounds (right/bottom) *)
    let w = if src_x + w > from.width then from.width - src_x else w in
    let h = if src_y + h > from.height then from.height - src_y else h in
    (* Clip destination to to_'s bounds (right/bottom) *)
    let w = if dst_x + w > to_.width then to_.width - dst_x else w in
    let h = if dst_y + h > to_.height then to_.height - dst_y else h in
    (* If nothing to blit, return early *)
    if w <= 0 || h <= 0
    then ()
    else
      (* Copy row by row using Bigarray.blit *)
      for row = 0 to h - 1 do
        let src_row_start = ((src_y + row) * from.width) + src_x in
        let dst_row_start = ((dst_y + row) * to_.width) + dst_x in
        let src_row = Bigarray.Array1.sub from.buffer src_row_start w in
        let dst_row = Bigarray.Array1.sub to_.buffer dst_row_start w in
        Bigarray.Array1.blit src_row dst_row
      done)
;;

module For_testing = struct
  let to_string t =
    let buf = Buffer.create ((t.width + 1) * t.height) in
    for y = 0 to t.height - 1 do
      for x = 0 to t.width - 1 do
        let pixel = Int32_u.to_int (get t ~x ~y) in
        let alpha = (pixel lsr 24) land 0xFF in
        let rgb = pixel land 0xFFFFFF in
        let c =
          if alpha = 0
          then '_'
          else (
            match rgb with
            | 0xFF0000 -> 'R'
            | 0x00FF00 -> 'G'
            | 0x0000FF -> 'B'
            | 0x000000 -> '_'
            | _ -> '?')
        in
        Buffer.add_char buf c
      done;
      if y < t.height - 1 then Buffer.add_char buf '\n'
    done;
    Buffer.contents buf
  ;;
end
