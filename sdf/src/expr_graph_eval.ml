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

module Batch_impl : Executor.S_batch = struct
  module Variable_idx = struct
    type t = int
  end

  module Prepared = struct
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

    let lookup_variable { var_mapping; _ } s =
      match List.Assoc.find var_mapping s ~equal:String.equal with
      | Some v -> v
      | None -> raise_s [%message "variable not found" (s : string)]
    ;;
  end

  module Result = struct
    type t = Value.Array.t

    let get_output t ~px = Value.Array.get t px
  end

  module Batch = struct
    type t =
      { prepared : Prepared.t
      ; variables : Value.Array.t
      ; registers : Value.Array.t iarray
      ; x_coords : int32# array
      ; y_coords : int32# array
      ; len : int
      }

    let create (prepared : Prepared.t) (region : Sample_region.t) =
      let len = region.samples_x * region.samples_y in
      let variables = Value.Array.create ~len:prepared.num_vars in
      let registers =
        Iarray.init len ~f:(fun _ -> Value.Array.create ~len:prepared.register_count)
      in
      let x_coords = Array.create ~len #0l in
      let y_coords = Array.create ~len #0l in
      for i = 0 to len - 1 do
        let col = i mod region.samples_x in
        let row = i / region.samples_x in
        Array.set x_coords i (Float32_u.to_bits (Sample_region.x_at region col));
        Array.set y_coords i (Float32_u.to_bits (Sample_region.y_at region row))
      done;
      { prepared; variables; registers; x_coords; y_coords; len }
    ;;

    let set_variable t ~var value = Value.Array.set t.variables var value

    let run
      { prepared = { instructions; final_register; oracle_keys; _ }
      ; variables
      ; registers
      ; x_coords
      ; y_coords
      ; len
      }
      ~oracles
      =
      let oracles = Iarray.map oracle_keys ~f:(fun key -> Map.find_exn oracles key) in
      let out = Value.Array.create ~len in
      for i = 0 to len - 1 do
        let registers = Iarray.get registers i in
        let x = Float32_u.of_bits (Array.get x_coords i) in
        let y = Float32_u.of_bits (Array.get y_coords i) in
        run ~variables ~instructions ~registers ~oracles ~x ~y;
        Value.Array.set out i (Value.Array.get registers final_register)
      done;
      out
    ;;
  end
end

module Single : Executor.S_single = Executor.Batch_to_single (Batch_impl)
module Batch : Executor.S_batch = Batch_impl
module Parallel : Executor.S_parallel = Executor.Batch_to_parallel (Batch_impl)
