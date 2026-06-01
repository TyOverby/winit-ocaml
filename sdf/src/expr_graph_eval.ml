open! Core

let rec run ~variables ~instructions ~registers =
  let len = Iarray.length instructions in
  for i = 0 to len - 1 do
    let out, instruction = Iarray.unsafe_get instructions i in
    let value =
      match (instruction : Expr_graph.instr) with
      | Float_literal f -> Value.of_float f
      | Bool_literal b -> Value.of_bool b
      | Var i -> Value.Array.get variables i
      | Condition { cond; then_; else_ } ->
        if Value.Array.get_bool registers cond
        then run ~variables ~instructions:then_ ~registers
        else run ~variables ~instructions:else_ ~registers;
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
      | Sqrt a ->
        let a = Value.Array.get_float registers a in
        Value.of_float (Float32_u.sqrt a)
      | Abs a ->
        let a = Value.Array.get_float registers a in
        Value.of_float (Float32_u.abs a)
      | Neg a ->
        let a = Value.Array.get_float registers a in
        Value.of_float (Float32_u.neg a)
      | Sign a ->
        let a = Value.Array.get_float registers a in
        let zero = Float32_u.of_float 0.0 in
        Value.of_float
          (if Float32_u.(a > zero)
           then Float32_u.of_float 1.0
           else if Float32_u.(a < zero)
           then Float32_u.of_float (-1.0)
           else zero)
      | Sin a ->
        let a = Value.Array.get_float registers a in
        Value.of_float (Float32_u.sin a)
      | Cos a ->
        let a = Value.Array.get_float registers a in
        Value.of_float (Float32_u.cos a)
      | Round a ->
        let a = Value.Array.get_float registers a in
        Value.of_float (Float32_u.round_nearest a)
      | Min (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_float (Float32_u.min a b)
      | Max (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        Value.of_float (Float32_u.max a b)
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
    Value.Array.set registers out value
  done
;;

let run' ~instructions ~variables ~final_register ~register_count =
  let registers = Value.Array.create ~len:register_count in
  run ~instructions ~variables ~registers;
  Value.Array.get registers final_register
;;

let run_tree tree =
  let ~instructions, ~final_register, ~register_count, ~var_mapping =
    Expr_graph.from_tree tree
  in
  ~var_mapping, ~run:(run' ~instructions ~final_register ~register_count)
;;

module Batched : Batch_backend_intf.S = struct
  module Variable_idx = struct
    type t = int
  end

  module Prepared = struct
    (* [var_mapping] is an immutable association list (rather than a [Hashtbl]) so that
       [t] mode-crosses contention and can be shared across parallel worker domains. *)
    type t =
      { instructions : Expr_graph.t
      ; final_register : int
      ; register_count : int
      ; var_mapping : (string * int) list
      ; num_vars : int
      }

    let of_tree tree =
      let ~instructions, ~final_register, ~register_count:_, ~var_mapping =
        Expr_graph.from_tree tree
      in
      let ~instructions, ~final_register, ~register_count =
        Expr_graph_register_minimizer.minimize ~instructions ~final_register
      in
      let num_vars = Hashtbl.length var_mapping in
      let var_mapping = Hashtbl.to_alist var_mapping in
      { instructions; final_register; register_count; var_mapping; num_vars }
    ;;

    let lookup_variable { var_mapping; _ } s =
      List.Assoc.find_exn var_mapping s ~equal:String.equal
    ;;
  end

  module Result = struct
    type t = Value.Array.t

    let get_output t ~px = Value.Array.get t px
  end

  module Batch = struct
    type t =
      { prepared : Prepared.t
      ; variables : Value.Array.t iarray
      ; registers : Value.Array.t iarray
      ; len : int
      }

    let create (prepared : Prepared.t) ~len =
      let variables =
        let variable_count = prepared.num_vars in
        Iarray.init len ~f:(fun _ -> Value.Array.create ~len:variable_count)
      in
      let registers =
        Iarray.init len ~f:(fun _ -> Value.Array.create ~len:prepared.register_count)
      in
      { prepared; variables; registers; len }
    ;;

    let set_variable t ~var ~px value =
      Value.Array.set (Iarray.get t.variables px) var value
    ;;

    let run { prepared = { instructions; final_register; _ }; variables; registers; len } =
      let out = Value.Array.create ~len in
      for i = 0 to len - 1 do
        let variables = Iarray.get variables i in
        let registers = Iarray.get registers i in
        run ~variables ~instructions ~registers;
        Value.Array.set out i (Value.Array.get registers final_register)
      done;
      out
    ;;
  end
end
