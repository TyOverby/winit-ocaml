open! Core
open Sdf
open Sdf_for_testing
open Helpers

let make_test (module Implementation : Executor.S_single) =
  let module A = struct
    module Implementation = Implementation

    let (default_env @ portable) t =
      let add_var name value map =
        match Implementation.lookup_variable t name with
        | idx -> Map.set map ~key:idx ~data:value
        | exception _ -> map
      in
      Map.empty (module Implementation.Variable_idx)
      |> add_var "b" (Value.Boxed.T (Value.of_bool true))
    ;;

    let oracle_registry : (unit -> (string * (module Oracle.S)) list) @ portable =
      fun () -> [ "passthrough", (module Sdf_passthrough_oracle) ]
    ;;

    let run tree =
      let scheduler = Parallel_scheduler.create () in
      Fiber_stack.parallel scheduler ~f:(fun par ->
        let oracle_registry = oracle_registry () in
        let oracles =
          Oracle_dependencies.extract_deps tree
          |> List.join
          |> List.fold
               ~init:(Map.empty (module Oracle.Key))
               ~f:(fun prepared ((key, tree) as oracle_key) ->
                 let module M =
                   (val List.Assoc.find_exn oracle_registry ~equal:String.equal key)
                 in
                 let p =
                   M.create tree
                   |> M.prepare
                        ~par
                        ~trace:(Phase_trace.null ())
                        ~oracles:prepared
                        ~sample_region:(Sdf.Sample_region.point ~x:#0.0s ~y:#0.0s)
                 in
                 Map.set prepared ~key:oracle_key ~data:p)
        in
        let t = Implementation.of_tree tree in
        let value =
          Or_error.try_with (fun () ->
            Value.box
              (Implementation.run ~vars:(default_env t) ~oracles ~x:#1.0s ~y:#5.0s t))
        in
        match value with
        | Ok v -> v |> Value.unbox |> Value.to_float |> Float32_u.sexp_of_t |> print_s
        | Error e -> print_s (Error.sexp_of_t e))
    ;;

    let%expect_test "no oracles" =
      let tree = add (f #1.s) (f #2.s) in
      run tree;
      [%expect {| 3 |}]
    ;;

    let%expect_test "single oracle with no dependencies" =
      let x = coord_x in
      let tree = oracle "passthrough" [ x ] in
      run tree;
      [%expect {| 1 |}]
    ;;

    let%expect_test "two independent oracles" =
      let x = coord_x in
      let y = coord_y in
      let a = oracle "passthrough" [ x ] in
      let b = oracle "passthrough" [ y ] in
      let tree = add a b in
      run tree;
      [%expect {| 6 |}]
    ;;

    let%expect_test "oracle depending on another oracle" =
      let x = coord_x in
      let blur_x = oracle "passthrough" [ x ] in
      let tree = oracle "passthrough" [ blur_x ] in
      run tree;
      [%expect {| 1 |}]
    ;;

    let%expect_test "chain of three oracles" =
      let x = coord_x in
      let a = oracle "passthrough" [ x ] in
      let b = oracle "passthrough" [ a ] in
      let tree = oracle "passthrough" [ b ] in
      run tree;
      [%expect {| 1 |}]
    ;;

    let%expect_test "duplicate oracle appears once" =
      let x = coord_x in
      let blur_x = oracle "passthrough" [ x ] in
      (* Same oracle used in two places *)
      let tree = add blur_x blur_x in
      run tree;
      [%expect {| 2 |}]
    ;;

    let%expect_test "same name different args are different oracles" =
      let x = coord_x in
      let y = coord_y in
      let blur_x = oracle "passthrough" [ x ] in
      let blur_y = oracle "passthrough" [ y ] in
      let tree = add blur_x blur_y in
      run tree;
      [%expect {| 6 |}]
    ;;

    let%expect_test "oracle nested inside arithmetic" =
      let x = coord_x in
      let o = oracle "passthrough" [ x ] in
      let tree = mul (add o (f #1.s)) (sub o (f #2.s)) in
      run tree;
      [%expect {| -2 |}]
    ;;

    let%expect_test "oracle inside cond branches" =
      let x = coord_x in
      let o1 = oracle "passthrough" [ x ] in
      let o2 = oracle "passthrough" [ x ] in
      let tree = cond ~condition:(lt o1 (f #0.s)) ~then_:o1 ~else_:o2 in
      run tree;
      [%expect {| 1 |}]
    ;;
  end
  in
  ()
;;

module Batch_eval_single = Executor.Batch_to_single (Expr_graph_batch_eval)

let () = make_test (module Expr_tree_eval.Single : Executor.S_single)
let () = make_test (module Expr_graph_eval.Single : Executor.S_single)
let () = make_test (module Batch_eval_single : Executor.S_single)
