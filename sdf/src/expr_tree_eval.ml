open! Core

module Result = struct
  type t =
    | Ok of Value.t
    | Error of Error.t
  [@@deriving sexp_of]
end

module Float_result = struct
  type t =
    | Ok of Float32_u.t
    | Error of Error.t
  [@@deriving sexp_of]
end

let rec eval_float
  : ( env:(string, Value.Boxed.t, String.comparator_witness) Map.t
   -> oracles:Oracle.Prepared.t Oracle.Key.Map.t -> Expr_tree.t -> Float_result.t)
  @ portable
  =
  fun ~env ~oracles t ->
  match t.kind with
  | Float_literal v -> Float_result.Ok v
  | Add (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a + b)))
  | Sub (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a - b)))
  | Mul (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a * b)))
  | Div (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a / b)))
  | Sqrt a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a -> Ok (Float32_u.sqrt a))
  | Abs a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a -> Ok (Float32_u.abs a))
  | Neg a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a -> Ok (Float32_u.neg a))
  | Sign a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       let zero = Float32_u.of_float 0.0 in
       Ok
         (if Float32_u.(a > zero)
          then Float32_u.of_float 1.0
          else if Float32_u.(a < zero)
          then Float32_u.of_float (-1.0)
          else zero))
  | Sin a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a -> Ok (Float32_u.sin a))
  | Cos a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a -> Ok (Float32_u.cos a))
  | Round a ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a -> Ok (Float32_u.round_nearest a))
  | Min (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error _ as e -> e
        | Ok b -> Ok (Float32_u.min a b)))
  | Max (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error _ as e -> e
        | Ok b -> Ok (Float32_u.max a b)))
  | Cond { condition; then_; else_ } ->
    (match eval_bool ~env ~oracles condition with
     | Error e -> Error e
     | Ok c ->
       if c then eval_float ~env ~oracles then_ else eval_float ~env ~oracles else_)
  | Oracle (name, exprs) ->
    let oracle = Map.find_exn oracles (name, exprs) in
    let x = Map.find_exn env "x" |> Value.unbox |> Value.to_float
    and y = Map.find_exn env "y" |> Value.unbox |> Value.to_float in
    Oracle.Prepared.sample oracle ~x ~y |> Ok
  | Var (name, _) ->
    (match Map.find env name with
     | Some (T value) -> Ok (Value.to_float value)
     | None ->
       Error
         (Error.create_s
            [%message
              "unbound variable" (name : string) ~loc:(t.loc : Source_code_position.t)]))
  | Bool_literal _ | Lt _ | Gt _ | Lte _ | Gte _ | And _ | Or _ | Xor _ ->
    Error
      (Error.create_s
         [%message "expected float, got bool" ~loc:(t.loc : Source_code_position.t)])

and eval_bool
  : ( env:(string, Value.Boxed.t, String.comparator_witness) Map.t
   -> oracles:Oracle.Prepared.t Oracle.Key.Map.t -> Expr_tree.t -> bool Or_error.t)
  @ portable
  =
  fun ~env ~oracles t ->
  match t.kind with
  | Bool_literal v -> Ok v
  | Lt (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a < b)))
  | Gt (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a > b)))
  | Lte (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a <= b)))
  | Gte (a, b) ->
    (match eval_float ~env ~oracles a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float ~env ~oracles b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a >= b)))
  | And (a, b) ->
    let%bind.Or_error a = eval_bool ~env ~oracles a in
    let%map.Or_error b = eval_bool ~env ~oracles b in
    a && b
  | Or (a, b) ->
    let%bind.Or_error a = eval_bool ~env ~oracles a in
    let%map.Or_error b = eval_bool ~env ~oracles b in
    a || b
  | Xor (a, b) ->
    let%bind.Or_error a = eval_bool ~env ~oracles a in
    let%map.Or_error b = eval_bool ~env ~oracles b in
    Bool.( <> ) a b
  | Cond { condition; then_; else_ } ->
    let%bind.Or_error c = eval_bool ~env ~oracles condition in
    if c then eval_bool ~env ~oracles then_ else eval_bool ~env ~oracles else_
  | Var (name, _) ->
    (match Map.find env name with
     | Some (T value) -> Ok (Value.to_bool value)
     | None ->
       Error
         (Error.create_s
            [%message
              "unbound variable" (name : string) ~loc:(t.loc : Source_code_position.t)]))
  | Oracle _
  | Float_literal _
  | Add _
  | Sub _
  | Mul _
  | Div _
  | Sqrt _
  | Abs _
  | Neg _
  | Sign _
  | Sin _
  | Cos _
  | Round _
  | Min _
  | Max _ ->
    Error
      (Error.create_s
         [%message "expected bool, got float" ~loc:(t.loc : Source_code_position.t)])
;;

let (eval @ portable)
  ~env
  ~(oracles : Oracle.Prepared.t Oracle.Key.Map.t)
  (t : Expr_tree.t)
  : Result.t
  =
  match t.type_ with
  | Float ->
    (match eval_float ~oracles ~env t with
     | Ok f -> Ok (Value.of_float f)
     | Error e -> Error e)
  | Bool ->
    (match eval_bool ~oracles ~env t with
     | Ok f -> Ok (Value.of_bool f)
     | Error e -> Error e)
;;

module Single : Executor.S_single = struct
  type t = Expr_tree.t

  module Prepared = Expr_tree
  module Variable_idx = String

  let of_tree = Fn.id
  let lookup_variable _ s = s

  let run t ~vars ~oracles =
    match eval t ~env:vars ~oracles with
    | Ok v -> v
    | Error e ->
      if true then Error.raise e;
      Value.of_bool false
  ;;
end

module Batch : Executor.S_batch = Executor.Single_to_batch (Single)
module Parallel : Executor.S_parallel = Executor.Batch_to_parallel (Batch)
