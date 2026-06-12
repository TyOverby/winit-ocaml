open! Core

let rec run ~variables ~instructions ~registers ~oracles ~x ~y =
  let len = Iarray.length instructions in
  for i = 0 to len - 1 do
    let out, instruction = Iarray.unsafe_get instructions i in
    let value =
      match (instruction : Expr_graph.instr) with
      | Float_literal f -> Value.of_float f
      | Bool_literal b -> Value.of_bool b
      | Coord_x -> Value.of_float x
      | Coord_y -> Value.of_float y
      | Var i -> Value.Array.get variables i
      | Oracle i ->
        let oracle = Iarray.get oracles i in
        Value.of_float (Prepared_oracle.sample oracle ~x ~y)
      | Condition { cond; then_; else_ } ->
        if Value.Array.get_bool registers cond
        then run ~variables ~instructions:then_ ~registers ~oracles ~x ~y
        else run ~variables ~instructions:else_ ~registers ~oracles ~x ~y;
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
        (* Division is total: x / 0 = 0 (for either sign of zero). *)
        Value.of_float
          (if Float32_u.(b = zero) then Float32_u.zero else Float32_u.(a / b))
      | Sqrt a ->
        let a = Value.Array.get_float registers a in
        (* Sqrt is total: sqrt of a negative is 0. *)
        Value.of_float (if Float32_u.(a < zero) then Float32_u.zero else Float32_u.sqrt a)
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
        Value.of_float (Float32_u.round_nearest_half_to_even a)
      | Min (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        (* On a tie ([a = b] is only true for equal values, including -0 = +0) take the
           sign-OR of the bits so that min(-0, +0) = -0, matching the SIMD backend's
           hardware min. Equal non-zero values have identical bits, so the OR is a no-op. *)
        if Float32_u.O.(a = b)
        then
          Value.of_float
            (Float32_u.of_bits Int32_u.O.(Float32_u.to_bits a lor Float32_u.to_bits b))
        else Value.of_float (Float32_u.min a b)
      | Max (a, b) ->
        let a = Value.Array.get_float registers a in
        let b = Value.Array.get_float registers b in
        (* Sign-AND on ties: max(-0, +0) = +0, matching the SIMD backend. *)
        if Float32_u.O.(a = b)
        then
          Value.of_float
            (Float32_u.of_bits Int32_u.O.(Float32_u.to_bits a land Float32_u.to_bits b))
        else Value.of_float (Float32_u.max a b)
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

module Single = struct
  module Variable_idx = String

  type t =
    { instructions : Expr_graph.t
    ; final_register : int
    ; register_count : int
    ; var_mapping : (string * int) list
    ; num_vars : int
    ; oracle_keys : Oracle_key.t iarray
    }

  let of_tree tree =
    let ~instructions, ~final_register, ~register_count:_, ~var_mapping, ~oracle_keys =
      Expr_graph.from_tree tree
    in
    let ~instructions, ~final_register, ~register_count =
      Expr_graph_register_minimizer.minimize ~instructions ~final_register
    in
    let num_vars = Hashtbl.length var_mapping in
    let var_mapping = Hashtbl.to_alist var_mapping in
    { instructions; final_register; register_count; var_mapping; num_vars; oracle_keys }
  ;;

  let lookup_variable _t name = name

  let run t ~vars ~oracles ~x ~y =
    let variables = Value.Array.create ~len:t.num_vars in
    (* Variables the program doesn't mention are ignored; program variables absent from
       [vars] keep the array's zero default. *)
    Map.iteri vars ~f:(fun ~key ~data ->
      match List.Assoc.find t.var_mapping key ~equal:String.equal with
      | Some idx -> Value.Array.set variables idx (Value.unbox data)
      | None -> ());
    let registers = Value.Array.create ~len:t.register_count in
    let oracles = Iarray.map t.oracle_keys ~f:(fun key -> Map.find_exn oracles key) in
    run ~variables ~instructions:t.instructions ~registers ~oracles ~x ~y;
    Value.Array.get registers t.final_register
  ;;
end

module Private = struct
  let run = run
end
