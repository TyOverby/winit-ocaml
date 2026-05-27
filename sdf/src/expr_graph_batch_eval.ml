open! Core
module F = Ocaml_simd_sse.Float32x4
module I = Ocaml_simd_sse.Int32x4

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

let get_result bank ~reg ~px = Value.of_int (Array.unsafe_get (Array.unsafe_get bank reg) px)

(* SIMD helpers: load/store 4 pixels at a time *)
let[@inline always] load_f (arr : int32# array) (px : int) : float32x4# =
  F.of_int32x4_bits (I.Int32_u_array.unsafe_get arr ~idx:px)
;;

let[@inline always] store_f (arr : int32# array) (px : int) (v : float32x4#) : unit =
  I.Int32_u_array.unsafe_set arr ~idx:px (I.of_float32x4_bits v)
;;

let[@inline always] load_i (arr : int32# array) (px : int) : int32x4# =
  I.Int32_u_array.unsafe_get arr ~idx:px
;;

let[@inline always] store_i (arr : int32# array) (px : int) (v : int32x4#) : unit =
  I.Int32_u_array.unsafe_set arr ~idx:px v
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
  let len = Array.length instructions in
  let simd_end = width land lnot 3 in
  for i = 0 to len - 1 do
    let out, instruction = Array.unsafe_get instructions i in
    let out_arr = Array.unsafe_get register_bank out in
    (match (instruction : Expr_graph.instr) with
     | Float_literal f ->
       let v = F.set1 f in
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
       let v = I.set1 bits in
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
         store_f out_arr !px F.(load_f a_arr !px + load_f b_arr !px);
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
         store_f out_arr !px F.(load_f a_arr !px - load_f b_arr !px);
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
         store_f out_arr !px F.(load_f a_arr !px * load_f b_arr !px);
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
         store_f out_arr !px F.(load_f a_arr !px / load_f b_arr !px);
         px := !px + 4
       done;
       for px = simd_end to width - 1 do
         set_sf out_arr px Float32_u.(get_sf a_arr px / get_sf b_arr px)
       done
     | Sqrt a ->
       let a_arr = Array.unsafe_get register_bank a in
       let px = ref 0 in
       while !px < simd_end do
         store_f out_arr !px (F.sqrt (load_f a_arr !px));
         px := !px + 4
       done;
       for px = simd_end to width - 1 do
         set_sf out_arr px (Float32_u.sqrt (get_sf a_arr px))
       done
     | Abs a ->
       let a_arr = Array.unsafe_get register_bank a in
       let px = ref 0 in
       while !px < simd_end do
         store_f out_arr !px (F.abs (load_f a_arr !px));
         px := !px + 4
       done;
       for px = simd_end to width - 1 do
         set_sf out_arr px (Float32_u.abs (get_sf a_arr px))
       done
     | Neg a ->
       let a_arr = Array.unsafe_get register_bank a in
       let px = ref 0 in
       while !px < simd_end do
         store_f out_arr !px (F.neg (load_f a_arr !px));
         px := !px + 4
       done;
       for px = simd_end to width - 1 do
         set_sf out_arr px (Float32_u.neg (get_sf a_arr px))
       done
     | Sign a ->
       let a_arr = Array.unsafe_get register_bank a in
       let zero = F.zero in
       let one = F.one in
       let neg_one = F.neg one in
       let px = ref 0 in
       while !px < simd_end do
         let v = load_f a_arr !px in
         let pos_mask = F.(v > zero) in
         let neg_mask = F.(v < zero) in
         let result = F.select pos_mask ~fail:zero ~pass:one in
         let result = F.select neg_mask ~fail:result ~pass:neg_one in
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
         store_f out_arr !px (F.round_nearest (load_f a_arr !px));
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
         store_f out_arr !px (F.min (load_f a_arr !px) (load_f b_arr !px));
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
         store_f out_arr !px (F.max (load_f a_arr !px) (load_f b_arr !px));
         px := !px + 4
       done;
       for px = simd_end to width - 1 do
         set_sf out_arr px (Float32_u.max (get_sf a_arr px) (get_sf b_arr px))
       done
     | Lt (a, b) ->
       let a_arr = Array.unsafe_get register_bank a in
       let b_arr = Array.unsafe_get register_bank b in
       let one_i = I.set1 #1l in
       let px = ref 0 in
       while !px < simd_end do
         let mask = F.(load_f a_arr !px < load_f b_arr !px) in
         store_i out_arr !px I.(mask land one_i);
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
       let one_i = I.set1 #1l in
       let px = ref 0 in
       while !px < simd_end do
         let mask = F.(load_f a_arr !px > load_f b_arr !px) in
         store_i out_arr !px I.(mask land one_i);
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
       let one_i = I.set1 #1l in
       let px = ref 0 in
       while !px < simd_end do
         let mask = F.(load_f a_arr !px <= load_f b_arr !px) in
         store_i out_arr !px I.(mask land one_i);
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
       let one_i = I.set1 #1l in
       let px = ref 0 in
       while !px < simd_end do
         let mask = F.(load_f a_arr !px >= load_f b_arr !px) in
         store_i out_arr !px I.(mask land one_i);
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
         store_i out_arr !px I.(load_i a_arr !px land load_i b_arr !px);
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
         store_i out_arr !px I.(load_i a_arr !px lor load_i b_arr !px);
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
         store_i out_arr !px I.(load_i a_arr !px lxor load_i b_arr !px);
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
       let one_i = I.set1 #1l in
       let px = ref 0 in
       while !px < simd_end do
         let c = load_i cond_arr !px in
         let mask = I.(c = one_i) in
         let then_v = load_i then_results !px in
         let else_v = load_i out_arr !px in
         store_i out_arr !px (I.select mask ~fail:else_v ~pass:then_v);
         px := !px + 4
       done;
       for px = simd_end to width - 1 do
         (match Array.unsafe_get cond_arr px with
          | #0l -> () (* keep else_ result already in out_arr *)
          | _ -> Array.unsafe_set out_arr px (Array.unsafe_get then_results px))
       done)
  done
;;
