open! Core

module Point = Point
module Connected = Connected

let process_single bi_map =
  let first = Bi_map.first bi_map in
  let { Line.p1; p2 } = Bi_map.lookup_line bi_map first in
  Bi_map.remove bi_map first;
  (* Follow forward from p2: find lines whose p1 = current *)
  let rec follow_forward ~current ~acc =
    match Bi_map.find_by_start bi_map current with
    | None -> current, acc
    | Some next_id ->
      let { Line.p2 = next; _ } = Bi_map.lookup_line bi_map next_id in
      Bi_map.remove bi_map next_id;
      follow_forward ~current:next ~acc:(next :: acc)
  in
  let fwd_end, fwd_acc = follow_forward ~current:p2 ~acc:[ p2 ] in
  (* Follow backward from p1: find lines whose p2 = current *)
  let rec follow_backward ~current ~acc =
    match Bi_map.find_by_end bi_map current with
    | None -> acc
    | Some prev_id ->
      let { Line.p1 = prev; _ } = Bi_map.lookup_line bi_map prev_id in
      Bi_map.remove bi_map prev_id;
      follow_backward ~current:prev ~acc:(prev :: acc)
  in
  let bwd_acc = follow_backward ~current:p1 ~acc:[ p1 ] in
  (* bwd_acc is [..., b2, b1, p1] and fwd_acc is [p2, f1, f2, ...] (reversed) *)
  let points = bwd_acc @ List.rev fwd_acc in
  if Point.equal (List.hd_exn points) fwd_end
  then Connected.Joined points
  else Connected.Disjoint points
;;

let f segments ~length =
  let bi_map = Bi_map.parse segments ~length in
  let rec parse_all acc =
    if Bi_map.is_empty bi_map
    then acc
    else (
      let r = process_single bi_map :: acc in
      parse_all r)
  in
  parse_all []
;;
