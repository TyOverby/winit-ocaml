open! Core
open Sdf

(** Values in the interpreter. During "supercompilation", we fully expand function calls
    and variable declarations, producing a plain [Expr_tree.t]. Functions exist only at
    compile time and are eliminated. *)
type value =
  | Expr of Expr_tree.t
  | Closure of
      { params : string list
      ; body : Ast.block
      ; env : env
      }
  | Cond of
      { condition : Expr_tree.t
      ; then_ : value
      ; else_ : value
      }
  | String of string

and env = value Map.M(String).t

let dummy_loc : Source_code_position.t = Stdlib.Lexing.dummy_pos

(** Force a value down to an [Expr_tree.t]. Closures cannot be forced and produce an
    error. Cond values are recursively forced and produce [Expr_tree.cond]. *)
let rec force_expr (v : value) : Expr_tree.t Or_error.t =
  match v with
  | Expr e -> Ok e
  | String s -> Or_error.error_s [%message "cannot use string as expression" (s : string)]
  | Closure _ -> Or_error.error_s [%message "cannot use function as expression"]
  | Cond { condition; then_; else_ } ->
    let loc = condition.loc in
    let%bind.Or_error then_ = force_expr then_ in
    let%bind.Or_error else_ = force_expr else_ in
    Expr_tree.cond ~loc ~condition ~then_ ~else_
;;

(** Call a value as a function with the given arguments. Closures are directly applied.
    Cond values are "lifted": both branches are called with the same arguments, and the
    results are wrapped in a new Cond. *)
let rec call_value (func : value) (args : value list) : value Or_error.t =
  match func with
  | Closure { params; body; env } ->
    (match
       List.fold2 params args ~init:env ~f:(fun env name arg ->
         Map.set env ~key:name ~data:arg)
     with
     | Ok env -> eval_block env body
     | Unequal_lengths ->
       Or_error.error_s
         [%message
           "wrong number of arguments"
             ~param_count:(List.length params : int)
             ~arg_count:(List.length args : int)])
  | Cond { condition; then_; else_ } ->
    let%bind.Or_error then_ = call_value then_ args in
    let%map.Or_error else_ = call_value else_ args in
    Cond { condition; then_; else_ }
  | Expr _ -> Or_error.error_s [%message "cannot call a non-function value"]
  | String _ -> Or_error.error_s [%message "cannot call a string"]

and eval_expr (env : env) (expr : Ast.expr) : value Or_error.t =
  let loc = expr.loc in
  match expr.kind with
  | Float_lit f ->
    let%map.Or_error e = Expr_tree.float_literal ~loc (Float32_u.of_float f) in
    Expr e
  | Bool_lit b ->
    let%map.Or_error e = Expr_tree.bool_literal ~loc b in
    Expr e
  | String_lit s -> Ok (String s)
  | Ident name ->
    (match Map.find env name with
     | Some v -> Ok v
     | None -> Or_error.error_s [%message "unbound variable" (name : string)])
  | Placeholder ->
    Or_error.error_s [%message "placeholder _ outside of function call arguments"]
  | Unary_neg inner ->
    let%bind.Or_error v = eval_expr env inner in
    let%bind.Or_error e = force_expr v in
    let%map.Or_error e = Expr_tree.neg ~loc e in
    Expr e
  | Binop (op, lhs_ast, rhs_ast) ->
    let%bind.Or_error lhs = eval_expr env lhs_ast in
    let%bind.Or_error rhs = eval_expr env rhs_ast in
    eval_binop ~loc lhs rhs op
  | Call (func_expr, arg_exprs) -> eval_call env func_expr arg_exprs
  | Method_call (obj_expr, method_name, arg_exprs) ->
    (* x.f(args) => f(x, args) *)
    let func_expr = { Ast.loc = expr.loc; kind = Ident method_name } in
    eval_call env func_expr (obj_expr :: arg_exprs)
  | If (cond_expr, then_block, else_block) ->
    let%bind.Or_error cond_val = eval_expr env cond_expr in
    eval_if env cond_val then_block else_block
  | Fn (params, body) ->
    let param_names = List.map params ~f:(fun (p : Ast.param) -> p.name) in
    Ok (Closure { params = param_names; body; env })

and eval_binop ~loc (lhs : value) (rhs : value) (op : Ast.binop) : value Or_error.t =
  let%bind.Or_error lhs = force_expr lhs in
  let%bind.Or_error rhs = force_expr rhs in
  let%map.Or_error e =
    match op with
    | Add -> Expr_tree.add ~loc lhs rhs
    | Sub -> Expr_tree.sub ~loc lhs rhs
    | Mul -> Expr_tree.mul ~loc lhs rhs
    | Div -> Expr_tree.div ~loc lhs rhs
    | Lt -> Expr_tree.lt ~loc lhs rhs
    | Gt -> Expr_tree.gt ~loc lhs rhs
    | Lte -> Expr_tree.lte ~loc lhs rhs
    | Gte -> Expr_tree.gte ~loc lhs rhs
    | And -> Expr_tree.and_ ~loc lhs rhs
    | Or -> Expr_tree.or_ ~loc lhs rhs
  in
  Expr e

and eval_call (env : env) (func_expr : Ast.expr) (arg_exprs : Ast.expr list)
  : value Or_error.t
  =
  (* Check for placeholders to create partial application *)
  let has_placeholders =
    List.exists arg_exprs ~f:(fun (e : Ast.expr) ->
      match e.kind with
      | Placeholder -> true
      | _ -> false)
  in
  if has_placeholders
  then eval_partial_app env func_expr arg_exprs
  else (
    match func_expr.kind with
    | Ident name ->
      (* User-defined names shadow builtins *)
      (match Map.find env name with
       | Some func ->
         let%bind.Or_error args = eval_args env arg_exprs in
         call_value func args
       | None ->
         if String.equal name "var"
         then eval_builtin_var ~loc:func_expr.loc env arg_exprs
         else if is_builtin name
         then (
           let%bind.Or_error args = eval_args env arg_exprs in
           eval_builtin ~loc:func_expr.loc name args)
         else Or_error.error_s [%message "unbound function" (name : string)])
    | _ ->
      let%bind.Or_error func = eval_expr env func_expr in
      let%bind.Or_error args = eval_args env arg_exprs in
      call_value func args)

and eval_args (env : env) (arg_exprs : Ast.expr list) : value list Or_error.t =
  List.map arg_exprs ~f:(eval_expr env) |> Or_error.all

and eval_builtin_var ~loc (env : env) (arg_exprs : Ast.expr list) : value Or_error.t =
  match arg_exprs with
  | [ arg_expr ] ->
    let%bind.Or_error v = eval_expr env arg_expr in
    (match v with
     | String name ->
       (* Type must come from context; we default to Float here.
          The let-binding type annotation should override this. *)
       let%map.Or_error e = Expr_tree.var ~loc name Expr_tree.Type.Float in
       Expr e
     | _ -> Or_error.error_s [%message "var() expects a string argument"])
  | _ -> Or_error.error_s [%message "var() expects exactly one argument"]

and is_builtin (name : string) : bool =
  match name with
  | "sqrt" | "abs" | "neg" | "sign" | "sin" | "cos" | "round" | "min" | "max" | "xor" ->
    true
  | _ -> false

and eval_builtin ~loc (name : string) (args : value list) : value Or_error.t =
  match name, args with
  (* Unary float builtins *)
  | "sqrt", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.sqrt ~loc a in
    Expr e
  | "abs", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.abs ~loc a in
    Expr e
  | "neg", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.neg ~loc a in
    Expr e
  | "sign", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.sign ~loc a in
    Expr e
  | "sin", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.sin ~loc a in
    Expr e
  | "cos", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.cos ~loc a in
    Expr e
  | "round", [ arg ] ->
    let%bind.Or_error a = force_expr arg in
    let%map.Or_error e = Expr_tree.round ~loc a in
    Expr e
  (* Binary float builtins *)
  | "min", [ a; b ] ->
    let%bind.Or_error a = force_expr a in
    let%bind.Or_error b = force_expr b in
    let%map.Or_error e = Expr_tree.min ~loc a b in
    Expr e
  | "max", [ a; b ] ->
    let%bind.Or_error a = force_expr a in
    let%bind.Or_error b = force_expr b in
    let%map.Or_error e = Expr_tree.max ~loc a b in
    Expr e
  (* Boolean builtin *)
  | "xor", [ a; b ] ->
    let%bind.Or_error a = force_expr a in
    let%bind.Or_error b = force_expr b in
    let%map.Or_error e = Expr_tree.xor ~loc a b in
    Expr e
  | _, _ ->
    let arg_count = List.length args in
    Or_error.error_s
      [%message "wrong number of arguments to builtin" (name : string) (arg_count : int)]

and eval_partial_app (env : env) (func_expr : Ast.expr) (arg_exprs : Ast.expr list)
  : value Or_error.t
  =
  let%bind.Or_error func = eval_expr env func_expr in
  (* Single pass: evaluate non-placeholder args once, collect param names for placeholders *)
  let counter = ref 0 in
  let%bind.Or_error processed =
    List.map arg_exprs ~f:(fun (arg_expr : Ast.expr) ->
      match arg_expr.kind with
      | Placeholder ->
        let name = sprintf "__partial_%d" !counter in
        Int.incr counter;
        Ok (name, true, None)
      | _ ->
        let%map.Or_error v = eval_expr env arg_expr in
        let name = sprintf "__captured_%d" !counter in
        Int.incr counter;
        name, false, Some v)
    |> Or_error.all
  in
  (* Build param names (placeholders only) and closure env (captured values) *)
  let param_names =
    List.filter_map processed ~f:(fun (name, is_placeholder, _) ->
      if is_placeholder then Some name else None)
  in
  let closure_env =
    List.fold processed ~init:env ~f:(fun acc (name, _is_placeholder, value_opt) ->
      match value_opt with
      | Some v -> Map.set acc ~key:name ~data:v
      | None -> acc)
  in
  (* Build the body that calls func with the processed arg names.
     Synthetic AST nodes use dummy_loc since they don't correspond to source text. *)
  let mk e = { Ast.loc = dummy_loc; kind = e } in
  let body_arg_idents = List.map processed ~f:(fun (name, _, _) -> mk (Ident name)) in
  let body_expr =
    match func_expr.kind with
    | Ident func_name -> mk (Call (mk (Ident func_name), body_arg_idents))
    | _ -> mk (Call (mk (Ident "__partial_func"), body_arg_idents))
  in
  let closure_env =
    match func_expr.kind with
    | Ident _ -> closure_env
    | _ -> Map.set closure_env ~key:"__partial_func" ~data:func
  in
  Ok
    (Closure
       { params = param_names
       ; body = { stmts = []; expr = body_expr }
       ; env = closure_env
       })

and eval_if
  (env : env)
  (cond_val : value)
  (then_block : Ast.block)
  (else_block : Ast.block)
  : value Or_error.t
  =
  match cond_val with
  | Expr cond_expr ->
    (match cond_expr.kind with
     | Bool_literal true -> eval_block env then_block
     | Bool_literal false -> eval_block env else_block
     | _ ->
       (* Runtime condition: evaluate both branches and wrap in Cond *)
       let%bind.Or_error then_val = eval_block env then_block in
       let%map.Or_error else_val = eval_block env else_block in
       Cond { condition = cond_expr; then_ = then_val; else_ = else_val })
  | _ -> Or_error.error_s [%message "condition must be a boolean expression"]

and eval_block (env : env) (block : Ast.block) : value Or_error.t =
  let%bind.Or_error env = eval_stmts env block.stmts in
  eval_expr env block.expr

and eval_stmts (env : env) (stmts : Ast.stmt list) : env Or_error.t =
  List.fold stmts ~init:(Ok env) ~f:(fun acc stmt ->
    let%bind.Or_error env = acc in
    eval_stmt env stmt)

and eval_stmt (env : env) (stmt : Ast.stmt) : env Or_error.t =
  match stmt with
  | Let { loc = _; name; type_annot; value = value_expr } ->
    let%map.Or_error v = eval_let env name type_annot value_expr in
    Map.set env ~key:name ~data:v
  | Fn_decl { loc = _; name; params; body } ->
    let param_names = List.map params ~f:(fun (p : Ast.param) -> p.name) in
    let closure = Closure { params = param_names; body; env } in
    Ok (Map.set env ~key:name ~data:closure)

and eval_let
  (env : env)
  (_name : string)
  (type_annot : Ast.type_annot option)
  (value_expr : Ast.expr)
  : value Or_error.t
  =
  (* Special case: var("name") with type annotation *)
  match value_expr.kind with
  | Call ({ kind = Ident "var"; _ }, [ { kind = String_lit var_name; _ } ]) ->
    let loc = value_expr.loc in
    let type_ =
      match type_annot with
      | Some Float_type -> Expr_tree.Type.Float
      | Some Bool_type -> Expr_tree.Type.Bool
      | None -> Expr_tree.Type.Float
    in
    let%map.Or_error e = Expr_tree.var ~loc var_name type_ in
    Expr e
  | _ -> eval_expr env value_expr
;;

let compile_program (program : Ast.program) : Expr_tree.t Or_error.t =
  let env = Map.empty (module String) in
  let%bind.Or_error env = eval_stmts env program.stmts in
  let%bind.Or_error export_val = eval_expr env program.export in
  force_expr export_val
;;
