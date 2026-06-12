open! Core
open Sdf
open Helpers

(* The SIMD batch evaluator runs the first [width land lnot 3] pixels through vector
   instructions and the remainder through the scalar graph evaluator. The tiled sampling
   machinery (and [Batch.create_sub]'s contract) requires a sample's value to depend only
   on its coordinates, never on its lane position — so every primitive's vector
   implementation must be bitwise identical to the scalar one.

   This test pins that property at the operation level. The special values are fed in as
   literals (not coordinates: [Sample_region.x_at] on a degenerate region computes column
   0 differently from columns 1+, which would change the inputs between lanes), so in a
   width-5 batch every pixel executes the op on identical inputs, and pixels 0-3 (vector
   path) must hold the same bits as pixel 4 (scalar tail). Any divergence (round's
   tie-breaking, the sign of [neg 0.], NaN propagation) shows up as a px0/px4 mismatch
   naming the op and inputs. *)

let special_values =
  [ "0.5", 0.5
  ; "-0.5", -0.5
  ; "1.5", 1.5
  ; "2.5", 2.5
  ; "-2.5", -2.5
  ; "0.0", 0.0
  ; "-0.0", -0.0
  ; "1.0", 1.0
  ; "-1.0", -1.0
  ; "nan", Float.nan
  ; "inf", Float.infinity
  ; "-inf", Float.neg_infinity
  ; "denormal", 1e-40
  ; "8388607.5", 8388607.5 (* largest float32 with a fractional .5 *)
  ; "-8388607.5", -8388607.5
  ; "0.49999997", 0.49999997
  ; "1e30", 1e30
  ]
;;

let unary_ops =
  [ "round", round
  ; "neg", neg
  ; "abs", abs
  ; "sign", sign
  ; "sqrt", sqrt
  ; "sin", sin
  ; "cos", cos
  ]
;;

let binary_ops =
  [ "add", add; "sub", sub; "mul", mul; "div", div; "min", min; "max", max ]
;;

(* Width 5: pixels 0-3 take the vector path, pixel 4 the scalar tail. The tree is a
   constant expression, so all five pixels run the op on identical inputs. *)
let eval_width5 tree =
  let region =
    { Sample_region.start_x = #0.s
    ; end_x = #1.s
    ; samples_x = 5
    ; start_y = #0.s
    ; end_y = #0.s
    ; samples_y = 1
    }
  in
  let module B = Expr_graph_batch_eval in
  let prepared = B.Prepared.of_tree tree in
  let batch = B.Batch.create prepared region in
  let result = B.Batch.run batch ~oracles:(Map.empty (module Oracle.Key)) in
  let bits px = Int32_u.to_int32 (Value.to_int (B.Result.get_output result ~px)) in
  bits 0, bits 4
;;

let check ~op_name ~arg_names tree mismatches =
  let vector, tail = eval_width5 tree in
  if not (Int32.equal vector tail)
  then
    mismatches
    := sprintf
         "%s(%s): vector bits %lx, scalar-tail bits %lx"
         op_name
         arg_names
         vector
         tail
       :: !mismatches
;;

let%expect_test "every primitive agrees between SIMD vector path and scalar tail" =
  let mismatches = ref [] in
  List.iter unary_ops ~f:(fun (op_name, op) ->
    List.iter special_values ~f:(fun (name, v) ->
      let tree = op (f (Float32_u.of_float v)) in
      check ~op_name ~arg_names:name tree mismatches));
  List.iter binary_ops ~f:(fun (op_name, op) ->
    List.iter special_values ~f:(fun (name_a, a) ->
      List.iter special_values ~f:(fun (name_b, b) ->
        let tree = op (f (Float32_u.of_float a)) (f (Float32_u.of_float b)) in
        check ~op_name ~arg_names:(name_a ^ ", " ^ name_b) tree mismatches)));
  (match List.rev !mismatches with
   | [] -> print_endline "all primitives consistent"
   | mismatches -> List.iter mismatches ~f:print_endline);
  [%expect {| all primitives consistent |}]
;;

(* Comparisons feed a [Cond] so the result is observable as a float. *)
let%expect_test "comparisons agree between SIMD vector path and scalar tail" =
  let comparison_ops = [ "lt", lt; "lte", lte; "gt", gt; "gte", gte ] in
  let mismatches = ref [] in
  List.iter comparison_ops ~f:(fun (op_name, op) ->
    List.iter special_values ~f:(fun (name_a, a) ->
      List.iter special_values ~f:(fun (name_b, b) ->
        let tree =
          cond
            ~condition:(op (f (Float32_u.of_float a)) (f (Float32_u.of_float b)))
            ~then_:(f #1.s)
            ~else_:(f #2.s)
        in
        check ~op_name ~arg_names:(name_a ^ ", " ^ name_b) tree mismatches)));
  (match List.rev !mismatches with
   | [] -> print_endline "all comparisons consistent"
   | mismatches -> List.iter mismatches ~f:print_endline);
  [%expect {| all comparisons consistent |}]
;;
