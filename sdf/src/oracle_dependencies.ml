open! Core

(* Collect all unique oracle keys from an expression tree. *)
let collect_oracles tree =
  let seen = Set.empty (module Oracle_key) in
  let rec go acc t =
    match (t : Expr_tree.t).kind with
    | Oracle (name, args) ->
      let key = name, args in
      let acc = List.fold args ~init:acc ~f:go in
      Set.add acc key
    | Float_literal _ | Bool_literal _ | Coord_x | Coord_y | Var _ -> acc
    | Add (a, b)
    | Mul (a, b)
    | Sub (a, b)
    | Div (a, b)
    | Lt (a, b)
    | Gt (a, b)
    | Lte (a, b)
    | Gte (a, b)
    | Min (a, b)
    | Max (a, b)
    | And (a, b)
    | Or (a, b)
    | Xor (a, b) -> go (go acc a) b
    | Sqrt a | Abs a | Neg a | Sign a | Sin a | Cos a | Round a -> go acc a
    | Cond { condition; then_; else_ } -> go (go (go acc condition) then_) else_
  in
  go seen tree
;;

(* Find all oracle keys that appear anywhere within a list of expression trees. *)
let oracles_in_args args =
  List.fold
    args
    ~init:(Set.empty (module Oracle_key))
    ~f:(fun acc arg -> Set.union acc (collect_oracles arg))
;;

let extract_deps tree =
  let all_oracles = collect_oracles tree in
  (* Build a map from oracle key to the set of oracle keys it directly depends on. *)
  let deps =
    Set.fold
      all_oracles
      ~init:(Map.empty (module Oracle_key))
      ~f:(fun acc key ->
        let _name, args = key in
        let dep_keys = oracles_in_args args in
        Map.set acc ~key ~data:dep_keys)
  in
  (* Kahn's algorithm for topological sort with level grouping. *)
  let rec toposort remaining acc =
    if Map.is_empty remaining
    then List.rev acc
    else (
      (* Find all nodes whose dependencies have all been satisfied (not in remaining). *)
      let ready =
        Map.filteri remaining ~f:(fun ~key:_ ~data:dep_set ->
          Set.for_all dep_set ~f:(fun dep -> not (Map.mem remaining dep)))
      in
      if Map.is_empty ready
      then
        (* Cycle — just emit whatever is left in one group *)
        List.rev (Map.keys remaining :: acc)
      else (
        let level = Map.keys ready in
        let remaining = List.fold level ~init:remaining ~f:(fun m k -> Map.remove m k) in
        toposort remaining (level :: acc)))
  in
  toposort deps []
;;
