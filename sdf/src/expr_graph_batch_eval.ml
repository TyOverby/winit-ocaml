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

(* Scalar helpers for tail pixels *)
let[@inline always] get_sf (arr : int32# array) (px : int) : float32# =
  Float32_u.of_bits (Array.unsafe_get arr px)
;;

let[@inline always] set_sf (arr : int32# array) (px : int) (v : float32#) : unit =
  Array.unsafe_set arr px (Float32_u.to_bits v)
;;

let copy_array (src : int32# array) (dst : int32# array) ~width ~simd_end =
  let px = ref 0 in
  while !px < simd_end do
    store_i dst !px (load_i src !px);
    px := !px + 4
  done;
  for px = simd_end to width - 1 do
    Array.unsafe_set dst px (Array.unsafe_get src px)
  done
;;

let rec run ~variable_bank ~instructions ~(register_bank : register_bank) ~width =
  let len = Iarray.length instructions in
  let simd_end = width land lnot 3 in
  for i = 0 to len - 1 do
    let out, instruction = Iarray.unsafe_get instructions i in
    let out_arr = Array.unsafe_get register_bank out in
    match (instruction : Expr_graph.instr) with
    | Float_literal f ->
      let v = Simd.f32x4_set1 f in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px v;
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px f
      done
    | Bool_literal b ->
      let bits = if b then #1l else #0l in
      let v = Simd.i32x4_set1 bits in
      let px = ref 0 in
      while !px < simd_end do
        store_i out_arr !px v;
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        Array.unsafe_set out_arr px bits
      done
    | Var idx ->
      let src = Array.unsafe_get variable_bank idx in
      copy_array src out_arr ~width ~simd_end
    | Read reg ->
      let src = Array.unsafe_get register_bank reg in
      copy_array src out_arr ~width ~simd_end
    | Add (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_add (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px Float32_u.(get_sf a_arr px + get_sf b_arr px)
      done
    | Sub (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_sub (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px Float32_u.(get_sf a_arr px - get_sf b_arr px)
      done
    | Mul (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_mul (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px Float32_u.(get_sf a_arr px * get_sf b_arr px)
      done
    | Div (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_div (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px Float32_u.(get_sf a_arr px / get_sf b_arr px)
      done
    | Sqrt a ->
      let a_arr = Array.unsafe_get register_bank a in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_sqrt (load_f a_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px (Float32_u.sqrt (get_sf a_arr px))
      done
    | Abs a ->
      let a_arr = Array.unsafe_get register_bank a in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_abs (load_f a_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px (Float32_u.abs (get_sf a_arr px))
      done
    | Neg a ->
      let a_arr = Array.unsafe_get register_bank a in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_neg (load_f a_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px (Float32_u.neg (get_sf a_arr px))
      done
    | Sign a ->
      let a_arr = Array.unsafe_get register_bank a in
      let zero = Simd.f32x4_zero in
      let one = Simd.f32x4_one in
      let neg_one = Simd.f32x4_neg one in
      let px = ref 0 in
      while !px < simd_end do
        let v = load_f a_arr !px in
        let pos_mask = Simd.f32x4_gt v zero in
        let neg_mask = Simd.f32x4_lt v zero in
        let result = Simd.f32x4_select pos_mask ~fail:zero ~pass:one in
        let result = Simd.f32x4_select neg_mask ~fail:result ~pass:neg_one in
        store_f out_arr !px result;
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a = get_sf a_arr px in
        let z = #0.0s in
        set_sf
          out_arr
          px
          (if Float32_u.(a > z)
           then #1.0s
           else if Float32_u.(a < z)
           then Float32_u.neg #1.0s
           else z)
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
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_round_nearest (load_f a_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px (Float32_u.round_nearest (get_sf a_arr px))
      done
    | Min (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_min (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px (Float32_u.min (get_sf a_arr px) (get_sf b_arr px))
      done
    | Max (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_f out_arr !px (Simd.f32x4_max (load_f a_arr !px) (load_f b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        set_sf out_arr px (Float32_u.max (get_sf a_arr px) (get_sf b_arr px))
      done
    | Lt (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < simd_end do
        let mask = Simd.f32x4_lt (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a = get_sf a_arr px in
        let b = get_sf b_arr px in
        Array.unsafe_set out_arr px (Value.to_int (Value.of_bool Float32_u.(a < b)))
      done
    | Gt (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < simd_end do
        let mask = Simd.f32x4_gt (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a = get_sf a_arr px in
        let b = get_sf b_arr px in
        Array.unsafe_set out_arr px (Value.to_int (Value.of_bool Float32_u.(a > b)))
      done
    | Lte (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < simd_end do
        let mask = Simd.f32x4_le (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a = get_sf a_arr px in
        let b = get_sf b_arr px in
        Array.unsafe_set out_arr px (Value.to_int (Value.of_bool Float32_u.(a <= b)))
      done
    | Gte (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < simd_end do
        let mask = Simd.f32x4_ge (load_f a_arr !px) (load_f b_arr !px) in
        store_i out_arr !px (Simd.i32x4_and mask one_i);
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a = get_sf a_arr px in
        let b = get_sf b_arr px in
        Array.unsafe_set out_arr px (Value.to_int (Value.of_bool Float32_u.(a >= b)))
      done
    | And (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_i out_arr !px (Simd.i32x4_and (load_i a_arr !px) (load_i b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a_bool = not (Int32_u.equal (Array.unsafe_get a_arr px) #0l) in
        let b_bool = not (Int32_u.equal (Array.unsafe_get b_arr px) #0l) in
        Array.unsafe_set out_arr px (if a_bool && b_bool then #1l else #0l)
      done
    | Or (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_i out_arr !px (Simd.i32x4_or (load_i a_arr !px) (load_i b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a_bool = not (Int32_u.equal (Array.unsafe_get a_arr px) #0l) in
        let b_bool = not (Int32_u.equal (Array.unsafe_get b_arr px) #0l) in
        Array.unsafe_set out_arr px (if a_bool || b_bool then #1l else #0l)
      done
    | Xor (a, b) ->
      let a_arr = Array.unsafe_get register_bank a in
      let b_arr = Array.unsafe_get register_bank b in
      let px = ref 0 in
      while !px < simd_end do
        store_i out_arr !px (Simd.i32x4_xor (load_i a_arr !px) (load_i b_arr !px));
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        let a_bool = not (Int32_u.equal (Array.unsafe_get a_arr px) #0l) in
        let b_bool = not (Int32_u.equal (Array.unsafe_get b_arr px) #0l) in
        Array.unsafe_set out_arr px (if Bool.( <> ) a_bool b_bool then #1l else #0l)
      done
    | Condition { cond; then_; else_ } ->
      let cond_arr = Array.unsafe_get register_bank cond in
      (* Run then_ branch for all pixels *)
      run ~variable_bank ~instructions:then_ ~register_bank ~width;
      (* Save then_ results *)
      let then_results = Array.create ~len:width #0l in
      copy_array out_arr then_results ~width ~simd_end;
      (* Run else_ branch for all pixels *)
      run ~variable_bank ~instructions:else_ ~register_bank ~width;
      (* Blend: if cond true, use then_ result; else keep else_ result *)
      let one_i = Simd.i32x4_set1 #1l in
      let px = ref 0 in
      while !px < simd_end do
        let c = load_i cond_arr !px in
        let mask = Simd.i32x4_cmpeq c one_i in
        let then_v = load_i then_results !px in
        let else_v = load_i out_arr !px in
        store_i out_arr !px (Simd.i32x4_select mask ~fail:else_v ~pass:then_v);
        px := !px + 4
      done;
      for px = simd_end to width - 1 do
        match Array.unsafe_get cond_arr px with
        | #0l -> () (* keep else_ result already in out_arr *)
        | _ -> Array.unsafe_set out_arr px (Array.unsafe_get then_results px)
      done
  done
;;
