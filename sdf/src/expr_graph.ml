open! Core

module Register : sig
  type t = int [@@deriving sexp_of, equal, compare, hash]
  type allocator

  val create_allocator : unit -> allocator
  val fresh : allocator -> t
  val count : allocator -> int
end = struct
  type t = int [@@deriving sexp_of, equal, compare, hash]
  type allocator = int ref

  let create_allocator () = ref 0

  let fresh t =
    let ret = !t in
    incr t;
    ret
  ;;

  let count t = !t
end

type instr =
  | Float_literal of Float32_u.t
  | Bool_literal of bool
  | Var of int
  | Read of Register.t
  | Add of Register.t * Register.t
  | Mul of Register.t * Register.t
  | Sub of Register.t * Register.t
  | Div of Register.t * Register.t
  | Condition of
      { cond : Register.t
      ; then_ : t
      ; else_ : t
      }
  | Lt of Register.t * Register.t
  | Gt of Register.t * Register.t
  | Lte of Register.t * Register.t
  | Gte of Register.t * Register.t
  | And of Register.t * Register.t
  | Or of Register.t * Register.t
  | Xor of Register.t * Register.t

and t = (Register.t * instr) list [@@deriving sexp_of, equal, compare]

module Bindings = struct
  type t =
    | Base of (Expr_tree.t, Register.t, Expr_tree.comparator_witness) Map.t
    | Level of
        { up : t
        ; map : (Expr_tree.t, Register.t, Expr_tree.comparator_witness) Map.t
        }

  let empty () = Base (Map.empty (module Expr_tree))
  let new_level t = Level { up = t; map = Map.empty (module Expr_tree) }

  let rec lookup t tree =
    match t with
    | Base map -> Map.find map tree
    | Level { up; map } ->
      (match Map.find map tree with
       | Some register -> Some register
       | None -> lookup up tree)
  ;;

  let insert t ~key ~data =
    match t with
    | Base map -> Base (Map.set map ~key ~data)
    | Level { up; map } -> Level { up; map = Map.set map ~key ~data }
  ;;
end

let from_tree tree =
  let register_allocator = Register.create_allocator () in
  let var_mapping = Hashtbl.create (module String) in
  let next_var =
    let next = ref 0 in
    fun () ->
      let r = !next in
      incr next;
      r
  in
  let rec loop (tree : Expr_tree.t) ~(instrs : t) ~(env : Bindings.t)
    : instrs:t * env:Bindings.t * Register.t
    =
    match Bindings.lookup env tree with
    | Some register -> ~instrs, ~env, register
    | None ->
      let output_register = Register.fresh register_allocator in
      let ~instr, ~instrs, ~env =
        match tree.kind with
        | Float_literal f -> ~instr:(Float_literal f), ~instrs, ~env
        | Bool_literal b -> ~instr:(Bool_literal b), ~instrs, ~env
        | Var (name, _) ->
          (match Hashtbl.find var_mapping name with
           | None ->
             let i = next_var () in
             Hashtbl.set var_mapping ~key:name ~data:i;
             ~instr:(Var i), ~instrs, ~env
           | Some i -> ~instr:(Var i), ~instrs, ~env)
        | Add (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Add (a, b)), ~instrs, ~env
        | Mul (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Mul (a, b)), ~instrs, ~env
        | Sub (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Sub (a, b)), ~instrs, ~env
        | Div (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Div (a, b)), ~instrs, ~env
        | Cond { condition; then_; else_ } ->
          let ~instrs, ~env, cond = loop condition ~instrs ~env in
          let ~instrs:then_instrs, ~env:_, then_ =
            loop then_ ~instrs:[] ~env:(Bindings.new_level env)
          in
          let then_instrs = (output_register, Read then_) :: then_instrs in
          let ~instrs:else_instrs, ~env:_, else_ =
            loop else_ ~instrs:[] ~env:(Bindings.new_level env)
          in
          let else_instrs = (output_register, Read else_) :: else_instrs in
          ( ~instr:(Condition
                      { cond; then_ = List.rev then_instrs; else_ = List.rev else_instrs })
          , ~instrs
          , ~env )
        | Lt (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Lt (a, b)), ~instrs, ~env
        | Gt (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Gt (a, b)), ~instrs, ~env
        | Lte (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Lte (a, b)), ~instrs, ~env
        | Gte (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Gte (a, b)), ~instrs, ~env
        | And (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(And (a, b)), ~instrs, ~env
        | Or (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Or (a, b)), ~instrs, ~env
        | Xor (a, b) ->
          let ~instrs, ~env, a = loop a ~instrs ~env in
          let ~instrs, ~env, b = loop b ~instrs ~env in
          ~instr:(Xor (a, b)), ~instrs, ~env
      in
      let env = Bindings.insert env ~key:tree ~data:output_register in
      let instrs = (output_register, instr) :: instrs in
      ~instrs, ~env, output_register
  in
  let ~instrs, ~env:_, register = loop tree ~instrs:[] ~env:(Bindings.empty ()) in
  ( ~instructions:(List.rev instrs)
  , ~final_register:register
  , ~register_count:(Register.count register_allocator)
  , ~var_mapping )
;;

let pp_instructions instructions =
  let buf = Buffer.create 256 in
  let rec pp ~indent instrs =
    let pad = String.make (indent * 2) ' ' in
    List.iter instrs ~f:(fun (out, instr) ->
      match (instr : instr) with
      | Float_literal f ->
        Buffer.add_string buf (sprintf "%s$%d <- %s\n" pad out (Float32_u.to_string f))
      | Bool_literal b -> Buffer.add_string buf (sprintf "%s$%d <- %b\n" pad out b)
      | Var i -> Buffer.add_string buf (sprintf "%s$%d <- var(%d)\n" pad out i)
      | Read r -> Buffer.add_string buf (sprintf "%s$%d <- $%d\n" pad out r)
      | Add (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- add $%d $%d\n" pad out a b)
      | Sub (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- sub $%d $%d\n" pad out a b)
      | Mul (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- mul $%d $%d\n" pad out a b)
      | Div (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- div $%d $%d\n" pad out a b)
      | Lt (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- lt $%d $%d\n" pad out a b)
      | Gt (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- gt $%d $%d\n" pad out a b)
      | Lte (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- lte $%d $%d\n" pad out a b)
      | Gte (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- gte $%d $%d\n" pad out a b)
      | And (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- and $%d $%d\n" pad out a b)
      | Or (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- or $%d $%d\n" pad out a b)
      | Xor (a, b) -> Buffer.add_string buf (sprintf "%s$%d <- xor $%d $%d\n" pad out a b)
      | Condition { cond; then_; else_ } ->
        Buffer.add_string buf (sprintf "%s$%d <- cond $%d\n" pad out cond);
        Buffer.add_string buf (sprintf "%s  then:\n" pad);
        pp ~indent:(indent + 2) then_;
        Buffer.add_string buf (sprintf "%s  else:\n" pad);
        pp ~indent:(indent + 2) else_)
  in
  pp ~indent:0 instructions;
  Buffer.contents buf
;;
