open! Core

module Register : sig
  type t = int [@@deriving sexp_of, equal, compare, hash]
  type allocator

  val create_allocator : unit -> allocator
  val fresh : allocator -> t
  val count : allocator -> int
end = struct
  include Int

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
  | Var of Expr_tree.Var_name.t * Expr_tree.Type.t
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

let from_tree tree =
  let register_allocator = Register.create_allocator () in
  let rec loop
    (tree : Expr_tree.t)
    ~(instrs : t)
    ~(env : (Expr_tree.t, Register.t, _) Map.t)
    : instrs:t * env:(Expr_tree.t, Register.t, _) Map.t * Register.t
    =
    match Map.find env tree with
    | Some register -> ~instrs, ~env, register
    | None ->
      let ~instr, ~instrs, ~env =
        match tree.kind with
        | Float_literal f -> ~instr:(Float_literal f), ~instrs, ~env
        | Bool_literal b -> ~instr:(Bool_literal b), ~instrs, ~env
        | Var (name, type_) -> ~instr:(Var (name, type_)), ~instrs, ~env
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
        | Cond _ -> assert false
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
          ~instr:(Or (a, b)), ~instrs, ~env
      in
      let register = Register.fresh register_allocator in
      let env = Map.set env ~key:tree ~data:register in
      let instrs = (register, instr) :: instrs in
      ~instrs, ~env, register
  in
  let ~instrs, ~env:_, register =
    loop tree ~instrs:[] ~env:(Map.empty (module Expr_tree))
  in
  ( ~instructions:(List.rev instrs)
  , ~final_register:register
  , ~register_count:(Register.count register_allocator) )
;;
