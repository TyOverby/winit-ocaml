open! Core

let instr_inputs (instr : Expr_graph.instr) : Expr_graph.Register.t list =
  match instr with
  | Float_literal _ | Bool_literal _ | Var _ -> []
  | Read r | Sqrt r | Abs r | Neg r | Sign r | Sin r | Cos r | Round r -> [ r ]
  | Add (a, b)
  | Mul (a, b)
  | Sub (a, b)
  | Div (a, b)
  | Min (a, b)
  | Max (a, b)
  | Lt (a, b)
  | Gt (a, b)
  | Lte (a, b)
  | Gte (a, b)
  | And (a, b)
  | Or (a, b)
  | Xor (a, b) -> [ a; b ]
  | Condition { cond; then_ = _; else_ = _ } -> [ cond ]
;;

(* Returns the set of registers used as inputs within [instrs] (recursively
   through nested Condition branches) that are NOT defined within [instrs].
   These are registers that must come from an outer scope. *)
let rec collect_outer_inputs (instrs : Expr_graph.t) : Int.Set.t =
  let defined = Int.Set.of_array (Iarray.to_array (Iarray.map instrs ~f:fst)) in
  let outer = ref Int.Set.empty in
  let add_if_outer r = if not (Set.mem defined r) then outer := Set.add !outer r in
  Iarray.iter instrs ~f:(fun (_out, instr) ->
    List.iter (instr_inputs instr) ~f:add_if_outer;
    match instr with
    | Condition { then_; else_; _ } ->
      Set.iter (collect_outer_inputs then_) ~f:add_if_outer;
      Set.iter (collect_outer_inputs else_) ~f:add_if_outer
    | _ -> ());
  !outer
;;

(* For each register DEFINED in [instructions] that is also used as an input,
   compute the index of the instruction where it is last used. Only registers
   that are defined in this block are tracked — outer-scope registers (used but
   not defined here) are managed by the enclosing scope.

   Uses of outer-scope registers inside Condition branches are attributed to
   the position of the Condition instruction, so that the enclosing scope
   keeps those registers alive through the branch. *)
let compute_last_use (instructions : Expr_graph.t) : int Int.Table.t =
  let defined = Int.Set.of_array (Iarray.to_array (Iarray.map instructions ~f:fst)) in
  let last_use = Int.Table.create () in
  Iarray.iteri instructions ~f:(fun pos (_out, instr) ->
    let mark r = if Set.mem defined r then Hashtbl.set last_use ~key:r ~data:pos in
    List.iter (instr_inputs instr) ~f:mark;
    match instr with
    | Condition { then_; else_; _ } ->
      Set.iter (collect_outer_inputs then_) ~f:mark;
      Set.iter (collect_outer_inputs else_) ~f:mark
    | _ -> ());
  last_use
;;

type state =
  { mapping : int Int.Table.t
  ; free_pool : Int.Set.t ref
  ; next_reg : int ref
  }

let alloc state =
  match Set.min_elt !(state.free_pool) with
  | Some r ->
    state.free_pool := Set.remove !(state.free_pool) r;
    r
  | None ->
    let r = !(state.next_reg) in
    incr state.next_reg;
    r
;;

let free state r = state.free_pool := Set.add !(state.free_pool) r

let lookup state r =
  match Hashtbl.find state.mapping r with
  | Some phys -> phys
  | None -> raise_s [%message "register not mapped" (r : int)]
;;

(* Rewrite an instruction's register operands using the mapping. Condition
   branches are NOT translated here; they are handled separately by the
   block-level processing. *)
let translate_instr state (instr : Expr_graph.instr) : Expr_graph.instr =
  let l = lookup state in
  match instr with
  | Float_literal _ | Bool_literal _ | Var _ -> instr
  | Read r -> Read (l r)
  | Sqrt r -> Sqrt (l r)
  | Abs r -> Abs (l r)
  | Neg r -> Neg (l r)
  | Sign r -> Sign (l r)
  | Sin r -> Sin (l r)
  | Cos r -> Cos (l r)
  | Round r -> Round (l r)
  | Add (a, b) -> Add (l a, l b)
  | Mul (a, b) -> Mul (l a, l b)
  | Sub (a, b) -> Sub (l a, l b)
  | Div (a, b) -> Div (l a, l b)
  | Min (a, b) -> Min (l a, l b)
  | Max (a, b) -> Max (l a, l b)
  | Lt (a, b) -> Lt (l a, l b)
  | Gt (a, b) -> Gt (l a, l b)
  | Lte (a, b) -> Lte (l a, l b)
  | Gte (a, b) -> Gte (l a, l b)
  | And (a, b) -> And (l a, l b)
  | Or (a, b) -> Or (l a, l b)
  | Xor (a, b) -> Xor (l a, l b)
  | Condition { cond; then_; else_ } ->
    (* Branches are placeholders here; the caller replaces them *)
    Condition { cond = l cond; then_; else_ }
;;

(* Process a branch (then_ or else_ of a Condition). Creates a copy of the
   outer state so that the branch's local allocations do not interfere with
   the outer scope or the sibling branch. Returns the minimized branch
   instructions and the high-water mark for next_reg. *)
let rec minimize_branch state (instructions : Expr_graph.t) : Expr_graph.t * int =
  let branch_state =
    { mapping = Hashtbl.copy state.mapping
    ; free_pool = ref !(state.free_pool)
    ; next_reg = ref !(state.next_reg)
    }
  in
  let result = minimize_block branch_state instructions in
  result, !(branch_state.next_reg)

(* Forward pass over an instruction block. Allocates physical registers for
   outputs, translates operands, and frees registers after their last use. *)
and minimize_block state (instructions : Expr_graph.t) : Expr_graph.t =
  let last_use = compute_last_use instructions in
  let result = ref [] in
  Iarray.iteri instructions ~f:(fun pos (out, instr) ->
    (* Allocate the output register. If [out] already has a mapping (e.g.
       a branch writing to the Condition's output register), reuse it. *)
    let new_out =
      match Hashtbl.find state.mapping out with
      | Some r -> r
      | None ->
        let r = alloc state in
        Hashtbl.set state.mapping ~key:out ~data:r;
        r
    in
    let new_instr =
      match instr with
      | Condition { cond; then_; else_ } ->
        let new_cond = lookup state cond in
        let saved_next_reg = !(state.next_reg) in
        let new_then, then_next = minimize_branch state then_ in
        state.next_reg := saved_next_reg;
        let new_else, else_next = minimize_branch state else_ in
        state.next_reg := Int.max then_next else_next;
        Expr_graph.Condition { cond = new_cond; then_ = new_then; else_ = new_else }
      | _ -> translate_instr state instr
    in
    result := (new_out, new_instr) :: !result;
    (* Free registers whose last use is at this position *)
    Hashtbl.iteri last_use ~f:(fun ~key:reg ~data:last_pos ->
      if last_pos = pos
      then (
        match Hashtbl.find state.mapping reg with
        | Some phys -> free state phys
        | None -> ())));
  Iarray.of_list_rev !result
;;

let minimize ~instructions ~final_register ~register_count:_ =
  let state =
    { mapping = Int.Table.create (); free_pool = ref Int.Set.empty; next_reg = ref 0 }
  in
  let instructions = minimize_block state instructions in
  let final_register = lookup state final_register in
  let register_count = !(state.next_reg) in
  ~instructions, ~final_register, ~register_count
;;
