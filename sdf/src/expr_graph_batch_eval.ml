open! Core

type register_bank = int32# array array
type variable_bank = int32# array array

let create_register_bank ~register_count ~width =
  Array.init register_count ~f:(fun _ -> Array.create ~len:width #0l)
;;

let create_variable_bank ~num_vars ~width =
  Array.init num_vars ~f:(fun _ -> Array.create ~len:width #0l)
;;

let set_variable bank ~var ~px value =
  Array.unsafe_set (Array.unsafe_get bank var) px (Value.to_int value)
;;

let get_result bank ~reg ~px =
  Value.of_int (Array.unsafe_get (Array.unsafe_get bank reg) px)
;;

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

let copy_array (src : int32# array) (dst : int32# array) ~width =
  let px = ref 0 in
  while !px < width do
    store_i dst !px (load_i src !px);
    px := !px + 4
  done
;;

(* SIMD-only run: assumes width is a multiple of 4 *)
let rec run_simd ~variable_bank ~instructions ~(register_bank : register_bank) ~width =
  let len = Iarray.length instructions in
  for i = 0 to len - 1 do
    let out, instruction = Iarray.unsafe_get instructions i in
    let out_arr = Array.unsafe_get register_bank out in
    match (instruction : Expr_graph.instr) with
    | Float_literal f ->
      let v = Simd.f32x4_set1 f in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px v;
        px := !px + 4
      done
    | Bool_literal b ->
      let bits = if b then #1l else #0l in
      let v = Simd.i32x4_set1 bits in
      let px = ref 0 in
      while !px < width do
        store_i out_arr !px v;
        px := !px + 4
      done
    | Var idx ->
      let src = Array.unsafe_get variable_bank idx in
      copy_array src out_arr ~width
    | Read reg ->
      let src = Array.unsafe_get register_bank reg in
      copy_array src out_arr ~width
    | Add (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_add (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done
    | Sub (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_sub (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done
    | Mul (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_mul (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done
    | Div (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_div (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done
    | Sqrt a ->
      let a_arr = Array.unsafe_get register_bank a in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_sqrt (load_f a_arr !px));
        px := !px + 4
      done
    | Abs a ->
      let a_arr = Array.unsafe_get register_bank a in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_abs (load_f a_arr !px));
        px := !px + 4
      done
    | Neg a ->
      let a_arr = Array.unsafe_get register_bank a in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_neg (load_f a_arr !px));
        px := !px + 4
      done
    | Sign a ->
      let a_arr = Array.unsafe_get register_bank a in
      let zero = Simd.f32x4_zero in
      let one = Simd.f32x4_one in
      let neg_one = Simd.f32x4_neg one in
      let px = ref 0 in
      while !px < width do
        let v = load_f a_arr !px in
        let pos_mask = Simd.f32x4_gt v zero in
        let neg_mask = Simd.f32x4_lt v zero in
        let result = Simd.f32x4_select pos_mask ~fail:zero ~pass:one in
        let result = Simd.f32x4_select neg_mask ~fail:result ~pass:neg_one in
        store_f out_arr !px result;
        px := !px + 4
      done
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
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_round_nearest (load_f a_arr !px));
        px := !px + 4
      done
    | Min (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_min (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done
    | Max (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_f out_arr !px (Simd.f32x4_max (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done
    | Lt (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < width do
        let mask = Simd.f32x4_lt (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done
    | Gt (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < width do
        let mask = Simd.f32x4_gt (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done
    | Lte (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < width do
        let mask = Simd.f32x4_le (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done
    | Gte (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < width do
        let mask = Simd.f32x4_ge (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done
    | And (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_i out_arr !px (Simd.i32x4_and (load_i a_arr !px) (load_i b_arr !px));
        px := !px + 4
      done
    | Or (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_i out_arr !px (Simd.i32x4_or (load_i a_arr !px) (load_i b_arr !px));
        px := !px + 4
      done
    | Xor (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < width do
        store_i out_arr !px (Simd.i32x4_xor (load_i a_arr !px) (load_i b_arr !px));
        px := !px + 4
      done
    | Condition { cond; then_; else_ } ->
      let cond_arr = Array.unsafe_get register_bank cond in
      run_simd ~variable_bank ~instructions:then_ ~register_bank ~width;
      let then_results = Array.create ~len:width #0l in
      copy_array out_arr then_results ~width;
      run_simd ~variable_bank ~instructions:else_ ~register_bank ~width;
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < width do
        let c = load_i cond_arr !px in
        let mask = Simd.i32x4_cmpeq c one_i in
        let then_v = load_i then_results !px in
        let else_v = load_i out_arr !px in
        store_i out_arr !px (Simd.i32x4_select mask ~fail:else_v ~pass:then_v);
        px := !px + 4
      done
  done
;;

let run ~variable_bank ~instructions ~register_bank ~width =
  let simd_width = width land lnot 3 in
  if simd_width > 0
  then run_simd ~variable_bank ~instructions ~register_bank ~width:simd_width;
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
      Expr_graph_eval.run ~variables ~instructions ~registers;
      for r = 0 to register_count - 1 do
        Array.unsafe_set
          (Array.unsafe_get register_bank r)
          px
          (Value.Array.get_int registers r)
      done
    done)
;;
