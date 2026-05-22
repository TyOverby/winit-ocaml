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

let rec eval_float (t : Expr_tree.t) : Float_result.t =
  match t.kind with
  | Float_literal v -> Ok v
  | Add (a, b) ->
    (match eval_float a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a + b)))
  | Sub (a, b) ->
    (match eval_float a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a - b)))
  | Mul (a, b) ->
    (match eval_float a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a * b)))
  | Div (a, b) ->
    (match eval_float a with
     | Error _ as e -> e
     | Ok a ->
       (match eval_float b with
        | Error _ as e -> e
        | Ok b -> Ok Float32_u.O.(a / b)))
  | Cond { condition; then_; else_ } ->
    (match eval_bool condition with
     | Error e -> Error e
     | Ok c -> if c then eval_float then_ else eval_float else_)
  | Var (name, _) ->
    Error
      (Error.create_s
         [%message
           "unbound variable" (name : string) ~loc:(t.loc : Source_code_position.t)])
  | Bool_literal _ | Lt _ | Gt _ | Lte _ | Gte _ | And _ | Or _ | Xor _ ->
    Error
      (Error.create_s
         [%message "expected float, got bool" ~loc:(t.loc : Source_code_position.t)])

and eval_bool (t : Expr_tree.t) : bool Or_error.t =
  match t.kind with
  | Bool_literal v -> Ok v
  | Lt (a, b) ->
    (match eval_float a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a < b)))
  | Gt (a, b) ->
    (match eval_float a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a > b)))
  | Lte (a, b) ->
    (match eval_float a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a <= b)))
  | Gte (a, b) ->
    (match eval_float a with
     | Error e -> Error e
     | Ok a ->
       (match eval_float b with
        | Error e -> Error e
        | Ok b -> Ok Float32_u.O.(a >= b)))
  | And (a, b) ->
    let%bind.Or_error a = eval_bool a in
    let%map.Or_error b = eval_bool b in
    a && b
  | Or (a, b) ->
    let%bind.Or_error a = eval_bool a in
    let%map.Or_error b = eval_bool b in
    a || b
  | Xor (a, b) ->
    let%bind.Or_error a = eval_bool a in
    let%map.Or_error b = eval_bool b in
    Bool.( <> ) a b
  | Cond { condition; then_; else_ } ->
    let%bind.Or_error c = eval_bool condition in
    if c then eval_bool then_ else eval_bool else_
  | Var (name, _) ->
    Error
      (Error.create_s
         [%message
           "unbound variable" (name : string) ~loc:(t.loc : Source_code_position.t)])
  | Float_literal _ | Add _ | Sub _ | Mul _ | Div _ ->
    Error
      (Error.create_s
         [%message "expected bool, got float" ~loc:(t.loc : Source_code_position.t)])
;;

let eval (t : Expr_tree.t) : Result.t =
  match t.type_ with
  | Float ->
    (match eval_float t with
     | Ok f -> Ok (Value.of_float f)
     | Error e -> Error e)
  | Bool ->
    (match eval_bool t with
     | Ok f -> Ok (Value.of_bool f)
     | Error e -> Error e)
;;
