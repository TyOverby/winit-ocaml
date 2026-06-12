open! Core

(* Registers hold intervals, stored across two parallel [Value.Array]s ([lo] / [hi]).
   Float registers hold the interval endpoints; bool registers hold a three-valued boolean
   as its (smallest, largest) possible value, with [false < true]. *)

let[@inline] get_f lo hi r : Interval.t =
  #{ Interval.lo = Value.Array.get_float lo r; hi = Value.Array.get_float hi r }
;;

let[@inline] set_f lo hi r (#{ Interval.lo = l; hi = h } : Interval.t) =
  Value.Array.set_float lo r l;
  Value.Array.set_float hi r h
;;

let[@inline] get_b lo hi r : Interval.Bool.t =
  #{ Interval.Bool.can_be_false = not (Value.Array.get_bool lo r)
   ; can_be_true = Value.Array.get_bool hi r
   }
;;

let[@inline] set_b
  lo
  hi
  r
  (#{ Interval.Bool.can_be_false; can_be_true } : Interval.Bool.t)
  =
  Value.Array.set_bool lo r (not can_be_false);
  Value.Array.set_bool hi r can_be_true
;;

let rec run ~variables ~instructions ~lo ~hi ~oracles ~(x : Interval.t) ~(y : Interval.t) =
  let len = Iarray.length instructions in
  for i = 0 to len - 1 do
    let out, instruction = Iarray.unsafe_get instructions i in
    match (instruction : Expr_graph.instr) with
    | Float_literal f -> set_f lo hi out (Interval.of_point f)
    | Bool_literal b -> set_b lo hi out (Interval.Bool.of_point b)
    | Coord_x -> set_f lo hi out x
    | Coord_y -> set_f lo hi out y
    | Var i ->
      (* Variables are scalars, not ranges: a point interval, whatever the type. *)
      let v = Value.Array.get variables i in
      Value.Array.set lo out v;
      Value.Array.set hi out v
    | Oracle i ->
      let oracle = Iarray.get oracles i in
      set_f lo hi out (Prepared_oracle.sample_range oracle ~x ~y)
    | Condition { cond; then_; else_ } ->
      let c = get_b lo hi cond in
      if Interval.Bool.definitely_true c
      then run ~variables ~instructions:then_ ~lo ~hi ~oracles ~x ~y
      else if Interval.Bool.definitely_false c
      then run ~variables ~instructions:else_ ~lo ~hi ~oracles ~x ~y
      else (
        (* The condition can go either way within the box: evaluate both branches and join
           their results. This is sound because we run the graph straight out of
           [Expr_graph.from_tree] (see [of_tree] below), where the two branches write
           disjoint registers.

           The join works on the raw register bits through the float view: float intervals
           join by IEEE min/max (a NaN endpoint, i.e. "top", propagates), and bools are
           stored as bits 0/1, which read as +0.0 and a positive denormal — ordered the
           same way as the bools they encode. *)
        run ~variables ~instructions:then_ ~lo ~hi ~oracles ~x ~y;
        let t_lo = Value.Array.get_float lo out
        and t_hi = Value.Array.get_float hi out in
        run ~variables ~instructions:else_ ~lo ~hi ~oracles ~x ~y;
        let e_lo = Value.Array.get_float lo out
        and e_hi = Value.Array.get_float hi out in
        Value.Array.set_float lo out (Float32_u.min t_lo e_lo);
        Value.Array.set_float hi out (Float32_u.max t_hi e_hi))
    | Read r ->
      Value.Array.set lo out (Value.Array.get lo r);
      Value.Array.set hi out (Value.Array.get hi r)
    | Add (a, b) -> set_f lo hi out (Interval.add (get_f lo hi a) (get_f lo hi b))
    | Mul (a, b) -> set_f lo hi out (Interval.mul (get_f lo hi a) (get_f lo hi b))
    | Sub (a, b) -> set_f lo hi out (Interval.sub (get_f lo hi a) (get_f lo hi b))
    | Div (a, b) -> set_f lo hi out (Interval.div (get_f lo hi a) (get_f lo hi b))
    | Sqrt a -> set_f lo hi out (Interval.sqrt (get_f lo hi a))
    | Abs a -> set_f lo hi out (Interval.abs (get_f lo hi a))
    | Neg a -> set_f lo hi out (Interval.neg (get_f lo hi a))
    | Sign a -> set_f lo hi out (Interval.sign (get_f lo hi a))
    | Sin a -> set_f lo hi out (Interval.sin (get_f lo hi a))
    | Cos a -> set_f lo hi out (Interval.cos (get_f lo hi a))
    | Round a -> set_f lo hi out (Interval.round (get_f lo hi a))
    | Min (a, b) -> set_f lo hi out (Interval.min (get_f lo hi a) (get_f lo hi b))
    | Max (a, b) -> set_f lo hi out (Interval.max (get_f lo hi a) (get_f lo hi b))
    | Lt (a, b) -> set_b lo hi out (Interval.lt (get_f lo hi a) (get_f lo hi b))
    | Lte (a, b) -> set_b lo hi out (Interval.lte (get_f lo hi a) (get_f lo hi b))
    | Gt (a, b) -> set_b lo hi out (Interval.gt (get_f lo hi a) (get_f lo hi b))
    | Gte (a, b) -> set_b lo hi out (Interval.gte (get_f lo hi a) (get_f lo hi b))
    | And (a, b) -> set_b lo hi out (Interval.Bool.and_ (get_b lo hi a) (get_b lo hi b))
    | Or (a, b) -> set_b lo hi out (Interval.Bool.or_ (get_b lo hi a) (get_b lo hi b))
    | Xor (a, b) -> set_b lo hi out (Interval.Bool.xor (get_b lo hi a) (get_b lo hi b))
  done
;;

module Variable_idx = Int

type t =
  { instructions : Expr_graph.t
  ; final_register : int
  ; register_count : int
  ; var_mapping : (string * int) list
  ; num_vars : int
  ; oracle_keys : Oracle_key.t iarray
  ; type_ : Expr_tree.Type.t
  }

let of_tree (tree : Expr_tree.t) =
  let ~instructions, ~final_register, ~register_count, ~var_mapping, ~oracle_keys =
    Expr_graph.from_tree tree
  in
  (* Deliberately no [Expr_graph_register_minimizer] pass: evaluating both branches of an
     uncertain [Condition] is only sound when the branches touch disjoint registers.
     Straight out of [from_tree] every instruction writes a fresh register (only a
     [Condition]'s output register is written more than once); the minimizer breaks that
     property by reusing registers. *)
  let num_vars = Hashtbl.length var_mapping in
  let var_mapping = Hashtbl.to_alist var_mapping in
  { instructions
  ; final_register
  ; register_count
  ; var_mapping
  ; num_vars
  ; oracle_keys
  ; type_ = tree.type_
  }
;;

let lookup_variable { var_mapping; _ } s =
  match List.Assoc.find var_mapping s ~equal:String.equal with
  | Some v -> v
  | None -> raise_s [%message "variable not found" (s : string)]
;;

let run_to_registers t ~vars ~oracles ~x ~y =
  let variables = Value.Array.create ~len:t.num_vars in
  Map.iteri vars ~f:(fun ~key ~data -> Value.Array.set variables key (Value.unbox data));
  let oracles = Iarray.map t.oracle_keys ~f:(fun key -> Map.find_exn oracles key) in
  let lo = Value.Array.create ~len:t.register_count in
  let hi = Value.Array.create ~len:t.register_count in
  run ~variables ~instructions:t.instructions ~lo ~hi ~oracles ~x ~y;
  lo, hi
;;

let run t ~vars ~oracles ~x ~y : Interval.t =
  match t.type_ with
  | Bool ->
    let () =
      raise_s
        [%message "Expr_graph_range_eval.run: expression has type bool; use [run_bool]"]
    in
    Interval.top
  | Float ->
    let lo, hi = run_to_registers t ~vars ~oracles ~x ~y in
    get_f lo hi t.final_register
;;

let run_bool t ~vars ~oracles ~x ~y : Interval.Bool.t =
  match t.type_ with
  | Float ->
    let () =
      raise_s
        [%message "Expr_graph_range_eval.run_bool: expression has type float; use [run]"]
    in
    Interval.Bool.maybe
  | Bool ->
    let lo, hi = run_to_registers t ~vars ~oracles ~x ~y in
    get_b lo hi t.final_register
;;
