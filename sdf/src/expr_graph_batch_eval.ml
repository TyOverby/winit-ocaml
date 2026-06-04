open! Core

module Register_bank = struct
  type t = int32# array array

  let create ~register_count ~width =
    Array.init register_count ~f:(fun _ -> Array.create ~len:width #0l)
  ;;

  let get_result t ~reg ~px = Value.of_int (Array.unsafe_get (Array.unsafe_get t reg) px)
end

module Variable_bank = struct
  type t = int32# array array

  let create ~num_vars ~width =
    Array.init num_vars ~f:(fun _ -> Array.create ~len:width #0l)
  ;;

  let set_variable t ~var ~px value =
    Array.unsafe_set (Array.unsafe_get t var) px (Value.to_int value)
  ;;
end

(* SIMD helpers: load/store 4 pixels at a time *)
let[@inline always] load_f (arr : int32# array) (px : int) : float32x4# =
  Simd.float32x4_of_int32x4 (Simd.arr_load arr ~idx:px)
;;

let[@inline always] store_f (arr : int32# array) (px : int) (v : float32x4#) : unit =
  Simd.arr_store arr ~idx:px (Simd.int32x4_of_float32x4 v)
;;

let[@inline always] load_i (arr : int32# array) (px : int) : int32x4# =
  Simd.arr_load arr ~idx:px
;;

let[@inline always] store_i (arr : int32# array) (px : int) (v : int32x4#) : unit =
  Simd.arr_store arr ~idx:px v
;;

(* Scalar helpers for ops without SIMD paths (sin, cos) *)
let[@inline always] get_sf (arr : int32# array) (px : int) : float32# =
  Float32_u.of_bits (Array.unsafe_get arr px)
;;

let[@inline always] set_sf (arr : int32# array) (px : int) (v : float32#) : unit =
  Array.unsafe_set arr px (Float32_u.to_bits v)
;;

let[@inline always] simd_loop ~width f =
  let px = ref 0 in
  while !px < width do
    f !px;
    px := !px + 4
  done
;;

let copy_array (src : int32# array) (dst : int32# array) ~width =
  simd_loop ~width (fun px -> store_i dst px (load_i src px))
;;

(* SIMD-only run: assumes width is a multiple of 4 *)
let rec run_simd
  ~variable_bank
  ~instructions
  ~(register_bank : Register_bank.t)
  ~width
  ~oracles
  ~x_var_idx
  ~y_var_idx
  =
  let len = Iarray.length instructions in
  for i = 0 to len - 1 do
    let out, instruction = Iarray.unsafe_get instructions i in
    let out_arr = Array.unsafe_get register_bank out in
    match (instruction : Expr_graph.instr) with
    | Float_literal f ->
      let v = Simd.f32x4_set1 f in
      simd_loop ~width (fun px -> store_f out_arr px v)
    | Bool_literal b ->
      let bits = if b then #1l else #0l in
      let v = Simd.i32x4_set1 bits in
      simd_loop ~width (fun px -> store_i out_arr px v)
    | Var idx ->
      let src = Array.unsafe_get variable_bank idx in
      copy_array src out_arr ~width
    | Read reg ->
      let src = Array.unsafe_get register_bank reg in
      copy_array src out_arr ~width
    | Oracle idx ->
      let oracle = Iarray.get oracles idx in
      for px = 0 to width - 1 do
        let x = get_sf (Array.unsafe_get variable_bank x_var_idx) px in
        let y = get_sf (Array.unsafe_get variable_bank y_var_idx) px in
        set_sf out_arr px (Prepared_oracle.sample oracle ~x ~y)
      done
    | Add (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_add (load_f a_arr px) (load_f b_arr px)))
    | Sub (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_sub (load_f a_arr px) (load_f b_arr px)))
    | Mul (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_mul (load_f a_arr px) (load_f b_arr px)))
    | Div (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_div (load_f a_arr px) (load_f b_arr px)))
    | Sqrt a ->
      let a_arr = Array.unsafe_get register_bank a in
      simd_loop ~width (fun px -> store_f out_arr px (Simd.f32x4_sqrt (load_f a_arr px)))
    | Abs a ->
      let a_arr = Array.unsafe_get register_bank a in
      simd_loop ~width (fun px -> store_f out_arr px (Simd.f32x4_abs (load_f a_arr px)))
    | Neg a ->
      let a_arr = Array.unsafe_get register_bank a in
      simd_loop ~width (fun px -> store_f out_arr px (Simd.f32x4_neg (load_f a_arr px)))
    | Sign a ->
      let a_arr = Array.unsafe_get register_bank a in
      let zero = Simd.f32x4_zero in
      let one = Simd.f32x4_one in
      let neg_one = Simd.f32x4_neg one in
      simd_loop ~width (fun px ->
        let v = load_f a_arr px in
        let pos_mask = Simd.f32x4_gt v zero in
        let neg_mask = Simd.f32x4_lt v zero in
        let result = Simd.f32x4_select pos_mask ~fail:zero ~pass:one in
        let result = Simd.f32x4_select neg_mask ~fail:result ~pass:neg_one in
        store_f out_arr px result)
    | Sin a ->
      let a_arr = Array.unsafe_get register_bank a in
      for px = 0 to width - 1 do
        set_sf out_arr px (Float32_u.sin (get_sf a_arr px))
      done
    | Cos a ->
      let a_arr = Array.unsafe_get register_bank a in
      for px = 0 to width - 1 do
        set_sf out_arr px (Float32_u.cos (get_sf a_arr px))
      done
    | Round a ->
      let a_arr = Array.unsafe_get register_bank a in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_round_nearest (load_f a_arr px)))
    | Min (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_min (load_f a_arr px) (load_f b_arr px)))
    | Max (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_f out_arr px (Simd.f32x4_max (load_f a_arr px) (load_f b_arr px)))
    | Lt (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      simd_loop ~width (fun px ->
        let mask = Simd.f32x4_lt (load_f a_arr px) (load_f b_arr px) in
        store_i out_arr px (Simd.i32x4_and mask one_i))
    | Gt (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      simd_loop ~width (fun px ->
        let mask = Simd.f32x4_gt (load_f a_arr px) (load_f b_arr px) in
        store_i out_arr px (Simd.i32x4_and mask one_i))
    | Lte (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      simd_loop ~width (fun px ->
        let mask = Simd.f32x4_le (load_f a_arr px) (load_f b_arr px) in
        store_i out_arr px (Simd.i32x4_and mask one_i))
    | Gte (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      simd_loop ~width (fun px ->
        let mask = Simd.f32x4_ge (load_f a_arr px) (load_f b_arr px) in
        store_i out_arr px (Simd.i32x4_and mask one_i))
    | And (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_i out_arr px (Simd.i32x4_and (load_i a_arr px) (load_i b_arr px)))
    | Or (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_i out_arr px (Simd.i32x4_or (load_i a_arr px) (load_i b_arr px)))
    | Xor (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      simd_loop ~width (fun px ->
        store_i out_arr px (Simd.i32x4_xor (load_i a_arr px) (load_i b_arr px)))
    | Condition { cond; then_; else_ } ->
      let cond_arr = Array.unsafe_get register_bank cond in
      run_simd
        ~variable_bank
        ~instructions:then_
        ~register_bank
        ~width
        ~oracles
        ~x_var_idx
        ~y_var_idx;
      let then_results = Array.create ~len:width #0l in
      copy_array out_arr then_results ~width;
      run_simd
        ~variable_bank
        ~instructions:else_
        ~register_bank
        ~width
        ~oracles
        ~x_var_idx
        ~y_var_idx;
      let one_i = Simd.i32x4_set1 #1l in
      simd_loop ~width (fun px ->
        let c = load_i cond_arr px in
        let mask = Simd.i32x4_cmpeq c one_i in
        let then_v = load_i then_results px in
        let else_v = load_i out_arr px in
        store_i out_arr px (Simd.i32x4_select mask ~fail:else_v ~pass:then_v))
  done
;;

let run ~variable_bank ~instructions ~register_bank ~width ~oracles ~x_var_idx ~y_var_idx =
  let simd_width = width land lnot 3 in
  if simd_width > 0
  then
    run_simd
      ~variable_bank
      ~instructions
      ~register_bank
      ~width:simd_width
      ~oracles
      ~x_var_idx
      ~y_var_idx;
  if simd_width < width
  then (
    let num_vars = Array.length variable_bank in
    let register_count = Array.length register_bank in
    let variables = Value.Array.create ~len:num_vars in
    let registers = Value.Array.create ~len:register_count in
    for px = simd_width to width - 1 do
      for v = 0 to num_vars - 1 do
        Value.Array.set_int
          variables
          v
          (Array.unsafe_get (Array.unsafe_get variable_bank v) px)
      done;
      Expr_graph_eval.run
        ~variables
        ~instructions
        ~registers
        ~oracles
        ~x_var_idx
        ~y_var_idx;
      for r = 0 to register_count - 1 do
        Array.unsafe_set
          (Array.unsafe_get register_bank r)
          px
          (Value.Array.get_int registers r)
      done
    done)
;;

module Batch_impl : Executor.S_batch = struct
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
      ; oracle_keys : Oracle_key.t iarray
      ; x_var_idx : int
      ; y_var_idx : int
      }

    let of_tree tree =
      let ~instructions, ~final_register, ~register_count:_, ~var_mapping, ~oracle_keys =
        Expr_graph.from_tree tree
      in
      let ~instructions, ~final_register, ~register_count =
        Expr_graph_register_minimizer.minimize ~instructions ~final_register
      in
      let num_vars = Hashtbl.length var_mapping in
      let x_var_idx = Hashtbl.find var_mapping "x" |> Option.value ~default:0 in
      let y_var_idx = Hashtbl.find var_mapping "y" |> Option.value ~default:0 in
      let var_mapping = Hashtbl.to_alist var_mapping in
      { instructions
      ; final_register
      ; register_count
      ; var_mapping
      ; num_vars
      ; oracle_keys
      ; x_var_idx
      ; y_var_idx
      }
    ;;

    let lookup_variable { var_mapping; _ } s =
      match List.Assoc.find var_mapping s ~equal:String.equal with
      | Some v -> v
      | None -> raise_s [%message "variable not found" (s : string)]
    ;;
  end

  module Batch = struct
    type t =
      { prepared : Prepared.t
      ; variables : Variable_bank.t
      ; registers : Register_bank.t
      ; len : int
      }

    let create (prepared : Prepared.t) ~len =
      let variables =
        let num_vars = prepared.num_vars in
        Variable_bank.create ~num_vars ~width:len
      in
      let registers =
        let register_count = prepared.register_count in
        Register_bank.create ~register_count ~width:len
      in
      { prepared; variables; registers; len }
    ;;

    let set_variable t ~var ~px value =
      Variable_bank.set_variable t.variables ~var ~px value
    ;;

    let run
      ({ prepared =
           { instructions; oracle_keys; x_var_idx; y_var_idx; _ }
       ; variables
       ; registers
       ; len
       } as t)
      ~oracles
      =
      let oracles = Iarray.map oracle_keys ~f:(fun key -> Map.find_exn oracles key) in
      run
        ~instructions
        ~variable_bank:variables
        ~register_bank:registers
        ~width:len
        ~oracles
        ~x_var_idx
        ~y_var_idx;
      t
    ;;
  end

  module Result = struct
    type t = Batch.t

    let get_output t ~px =
      let reg = t.Batch.prepared.final_register in
      Register_bank.get_result t.registers ~reg ~px
    ;;
  end
end

module Single : Executor.S_single = Executor.Batch_to_single (Batch_impl)
module Batch : Executor.S_batch = Batch_impl
module Parallel : Executor.S_parallel = Executor.Batch_to_parallel (Batch_impl)
