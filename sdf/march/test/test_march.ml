open! Core

let make_grid ~width ~height ~(f : x:int -> y:int -> float32#) : float32# array =
  let n = width * height in
  let arr = Array.create ~len:n #0.0s in
  for i = 0 to n - 1 do
    arr.(i) <- f ~x:(i mod width) ~y:(i / width)
  done;
  arr
;;

let make_output ~width ~height : float32# array =
  Array.create ~len:(width * height * 2 * 4) #0.0s
;;

let pp_f32 (f : float32#) = Sexp.to_string (Float32_u.sexp_of_t f)

let print_lines (output : float32# array) count =
  for i = 0 to count - 1 do
    printf
      "  (%s, %s) -> (%s, %s)\n"
      (pp_f32 output.(i * 4))
      (pp_f32 output.((i * 4) + 1))
      (pp_f32 output.((i * 4) + 2))
      (pp_f32 output.((i * 4) + 3))
  done
;;

let%expect_test "uniform positive - no contour" =
  let w = 4
  and h = 4 in
  let input = make_grid ~width:w ~height:h ~f:(fun ~x:_ ~y:_ -> #1.0s) in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  [%expect {| lines: 0 |}]
;;

let%expect_test "uniform negative - no contour" =
  let w = 4
  and h = 4 in
  let input = make_grid ~width:w ~height:h ~f:(fun ~x:_ ~y:_ -> Float32_u.neg #1.0s) in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  [%expect {| lines: 0 |}]
;;

let%expect_test "vertical boundary" =
  let w = 4
  and h = 4 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y:_ ->
      if x < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 3
      (1.5, 0) -> (1.5, 1)
      (1.5, 1) -> (1.5, 2)
      (1.5, 2) -> (1.5, 3)
    |}]
;;

let%expect_test "horizontal boundary" =
  let w = 4
  and h = 4 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x:_ ~y ->
      if y < 2 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 3
      (1, 1.5) -> (0, 1.5)
      (2, 1.5) -> (1, 1.5)
      (3, 1.5) -> (2, 1.5)
    |}]
;;

let%expect_test "single negative cell in positive field" =
  let w = 3
  and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x = 1 && y = 1 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 4
      (0.5, 1) -> (1, 0.5)
      (1, 0.5) -> (1.5, 1)
      (1, 1.5) -> (0.5, 1)
      (1.5, 1) -> (1, 1.5)
    |}]
;;

let%expect_test "single positive cell in negative field" =
  let w = 3
  and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x = 1 && y = 1 then #1.0s else Float32_u.neg #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 4
      (1, 0.5) -> (0.5, 1)
      (1.5, 1) -> (1, 0.5)
      (0.5, 1) -> (1, 1.5)
      (1, 1.5) -> (1.5, 1)
    |}]
;;

let%expect_test "diagonal boundary" =
  let w = 5
  and h = 5 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if x + y < 4 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 7
      (3, 0.5) -> (2.5, 1)
      (3.5, 0) -> (3, 0.5)
      (2, 1.5) -> (1.5, 2)
      (2.5, 1) -> (2, 1.5)
      (1, 2.5) -> (0.5, 3)
      (1.5, 2) -> (1, 2.5)
      (0.5, 3) -> (0, 3.5)
    |}]
;;

let%expect_test "2x2 minimal grid - one corner negative" =
  let input : float32# array = [| Float32_u.neg #1.0s; #1.0s; #1.0s; #1.0s |] in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run input output 2 2 in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect {|
    lines: 1
      (0.5, 0) -> (0, 0.5)
    |}]
;;

let%expect_test "2x2 minimal grid - all corners negative" =
  let input : float32# array =
    [| Float32_u.neg #1.0s
     ; Float32_u.neg #1.0s
     ; Float32_u.neg #1.0s
     ; Float32_u.neg #1.0s
    |]
  in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run input output 2 2 in
  printf "lines: %d\n" count;
  [%expect {| lines: 0 |}]
;;

let%expect_test "checkerboard produces ambiguous cases" =
  let w = 3
  and h = 3 in
  let input =
    make_grid ~width:w ~height:h ~f:(fun ~x ~y ->
      if (x + y) mod 2 = 0 then Float32_u.neg #1.0s else #1.0s)
  in
  let output = make_output ~width:w ~height:h in
  let count = March.run input output w h in
  printf "lines: %d\n" count;
  print_lines output count;
  [%expect
    {|
    lines: 8
      (0.5, 1) -> (1, 0.5)
      (0.5, 0) -> (0, 0.5)
      (2, 0.5) -> (1.5, 0)
      (1, 0.5) -> (1.5, 1)
      (1, 1.5) -> (0.5, 1)
      (0, 1.5) -> (0.5, 2)
      (1.5, 2) -> (2, 1.5)
      (1.5, 1) -> (1, 1.5)
    |}]
;;

let%expect_test "varying sdf values affect interpolation" =
  (* Use non-uniform values so lerp produces different positions *)
  let input : float32# array = [| Float32_u.neg #2.0s; #1.0s; #1.0s; #1.0s |] in
  let output = make_output ~width:2 ~height:2 in
  let count = March.run input output 2 2 in
  printf "lines: %d\n" count;
  print_lines output count;
  (* Compare with uniform ±1 to show interpolation differs *)
  let input2 : float32# array = [| Float32_u.neg #1.0s; #1.0s; #1.0s; #1.0s |] in
  let output2 = make_output ~width:2 ~height:2 in
  let count2 = March.run input2 output2 2 2 in
  printf "lines: %d\n" count2;
  print_lines output2 count2;
  [%expect
    {|
    lines: 1
      (0.666666687, 0) -> (0, 0.666666687)
    lines: 1
      (0.5, 0) -> (0, 0.5)
    |}]
;;
