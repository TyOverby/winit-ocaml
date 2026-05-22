open! Core

let rec run ~instructions ~registers =
  List.iter instructions ~f:(fun (out, instruction) ->
    let value =
      match (instruction : Expr_graph.instr) with
      | Float_literal f -> Value.of_float f
      | Bool_literal b -> Value.of_bool b
      | Var _ -> assert false
      | Condition { cond; then_; else_ } ->
        if Value.Array.get_bool registers cond
        then run ~instructions:then_ ~registers
        else run ~instructions:else_ ~registers;
        Value.Array.get registers out
      | Read input_register -> Value.Array.get registers input_register
      | Add (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_float Float32_u.(a + b)
      | Mul (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_float Float32_u.(a * b)
      | Sub (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_float Float32_u.(a - b)
      | Div (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_float Float32_u.(a / b)
      | Lt (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_bool Float32_u.(a < b)
      | Lte (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_bool Float32_u.(a <= b)
      | Gt (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_bool Float32_u.(a > b)
      | Gte (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_bool Float32_u.(a >= b)
      | And (a, b) ->
        let a = Value.Array.get_bool registers a in
        let b = Value.Array.get_bool registers b in
        Value.of_bool (a && b)
      | Or (a, b) ->
        let a = Value.Array.get_bool registers a in
        let b = Value.Array.get_bool registers b in
        Value.of_bool (a || b)
      | Xor (a, b) ->
        let a = Value.Array.get_bool registers a in
        let b = Value.Array.get_bool registers b in
        Value.of_bool Bool.(a <> b)
    in
    Value.Array.set registers out value)
;;

let run ~instructions ~final_register ~register_count =
  let registers = Value.Array.create ~len:register_count in
  run ~instructions ~registers;
  Value.Array.get registers final_register
;;
