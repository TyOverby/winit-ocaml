open! Core
module Id = Unique_id.Int ()

type t =
  { dict : Line.t Id.Table.t
  ; starts : Id.t list Point.Table.t
  ; ends : Id.t list Point.Table.t
  }

let parse (segments : float32# array) ~length =
  let dict = Id.Table.create () in
  let starts = Point.Table.create () in
  let ends = Point.Table.create () in
  for i = 0 to length - 1 do
    let x1 = Float32_u.to_float segments.(i * 4) in
    let y1 = Float32_u.to_float segments.((i * 4) + 1) in
    let x2 = Float32_u.to_float segments.((i * 4) + 2) in
    let y2 = Float32_u.to_float segments.((i * 4) + 3) in
    let p1 = { Point.x = x1; y = y1 } in
    let p2 = { Point.x = x2; y = y2 } in
    let line = { Line.p1; p2 } in
    let id = Id.create () in
    Hashtbl.add_exn dict ~key:id ~data:line;
    Hashtbl.update starts p1 ~f:(function
      | Some ids -> id :: ids
      | None -> [ id ]);
    Hashtbl.update ends p2 ~f:(function
      | Some ids -> id :: ids
      | None -> [ id ])
  done;
  { dict; starts; ends }
;;

let is_empty { dict; _ } = Hashtbl.is_empty dict
let lookup_line { dict; _ } id = Hashtbl.find_exn dict id

let remove t id =
  match Hashtbl.find_and_remove t.dict id with
  | Some { Line.p1; p2 } ->
    let cleanup tbl key =
      match Hashtbl.find tbl key with
      | Some ids ->
        let ids = List.filter ids ~f:(fun i -> not (Id.equal i id)) in
        if List.is_empty ids
        then Hashtbl.remove tbl key
        else Hashtbl.set tbl ~key ~data:ids
      | None -> ()
    in
    cleanup t.starts p1;
    cleanup t.ends p2
  | None -> ()
;;

let first { dict; _ } =
  let least = ref None in
  Hashtbl.iter_keys dict ~f:(fun id ->
    match !least with
    | None -> least := Some id
    | Some a when Id.( < ) id a -> least := Some id
    | _ -> ());
  Option.value_exn !least
;;

let find_and_remove ~tbl point =
  match Hashtbl.find tbl point with
  | Some (id :: rest) ->
    (match rest with
     | [] -> Hashtbl.remove tbl point
     | _ -> Hashtbl.set tbl ~key:point ~data:rest);
    Some id
  | Some [] | None -> None
;;

let find_by_start t point = find_and_remove ~tbl:t.starts point
let find_by_end t point = find_and_remove ~tbl:t.ends point
