open! Base
open! Stdio
open Image_buf

let red = #0xFFFF0000l
let green = #0xFF00FF00l
let blue = #0xFF0000FFl
let black = #0xFF000000l
let transparent = #0x00000000l

let%expect_test "create fills with color" =
  let img = create ~width:3 ~height:2 red in
  print_endline (For_testing.to_string img);
  [%expect {|
    RRR
    RRR |}]
;;

let%expect_test "create with black" =
  let img = create ~width:4 ~height:3 black in
  print_endline (For_testing.to_string img);
  [%expect {|
    ____
    ____
    ____
    |}]
;;

let%expect_test "set individual pixels" =
  let img = create ~width:3 ~height:3 black in
  set img ~x:0 ~y:0 red;
  set img ~x:1 ~y:1 green;
  set img ~x:2 ~y:2 blue;
  print_endline (For_testing.to_string img);
  [%expect {|
    R__
    _G_
    __B
    |}]
;;

let%expect_test "fill_rect basic" =
  let img = create ~width:4 ~height:4 black in
  fill_rect img ~x:1 ~y:1 ~w:2 ~h:2 red;
  print_endline (For_testing.to_string img);
  [%expect {|
    ____
    _RR_
    _RR_
    ____
    |}]
;;

let%expect_test "fill_rect clips to the image's bounds" =
  let img = create ~width:4 ~height:4 black in
  fill_rect img ~x:(-1) ~y:(-1) ~w:3 ~h:3 red;
  fill_rect img ~x:2 ~y:2 ~w:3 ~h:3 green;
  print_endline (For_testing.to_string img);
  [%expect {|
    RR__
    RR__
    __GG
    __GG
    |}]
;;

let%expect_test "fill_rect completely outside does nothing" =
  let img = create ~width:4 ~height:4 black in
  fill_rect img ~x:4 ~y:0 ~w:2 ~h:2 red;
  fill_rect img ~x:0 ~y:(-2) ~w:2 ~h:2 red;
  fill_rect img ~x:0 ~y:0 ~w:0 ~h:3 red;
  print_endline (For_testing.to_string img);
  [%expect {|
    ____
    ____
    ____
    ____
    |}]
;;

let%expect_test "blit basic" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 0; y = 0; w = 2; h = 2 } ~to_:dst ~x:1 ~y:1;
  print_endline (For_testing.to_string dst);
  [%expect {|
    ____
    _RR_
    _RR_
    ____
    |}]
;;

let%expect_test "blit clips source region with negative x" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = -1; y = 0; w = 2; h = 2 } ~to_:dst ~x:0 ~y:0;
  print_endline (For_testing.to_string dst);
  [%expect {|
    _R__
    _R__
    ____
    ____
    |}]
;;

let%expect_test "blit clips source region with negative y" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 0; y = -1; w = 2; h = 2 } ~to_:dst ~x:0 ~y:0;
  print_endline (For_testing.to_string dst);
  [%expect {|
    ____
    RR__
    ____
    ____
    |}]
;;

let%expect_test "blit clips destination with negative x" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 0; y = 0; w = 2; h = 2 } ~to_:dst ~x:(-1) ~y:0;
  print_endline (For_testing.to_string dst);
  [%expect {|
    R___
    R___
    ____
    ____
    |}]
;;

let%expect_test "blit clips destination with negative y" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 0; y = 0; w = 2; h = 2 } ~to_:dst ~x:0 ~y:(-1);
  print_endline (For_testing.to_string dst);
  [%expect {|
    RR__
    ____
    ____
    ____
    |}]
;;

let%expect_test "blit clips source extending past bounds" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 1; y = 1; w = 3; h = 3 } ~to_:dst ~x:0 ~y:0;
  print_endline (For_testing.to_string dst);
  [%expect {|
    R___
    ____
    ____
    ____
    |}]
;;

let%expect_test "blit clips destination extending past bounds" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 0; y = 0; w = 2; h = 2 } ~to_:dst ~x:3 ~y:3;
  print_endline (For_testing.to_string dst);
  [%expect {|
    ____
    ____
    ____
    ___R
    |}]
;;

let%expect_test "blit with region completely outside source does nothing" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 10; y = 10; w = 2; h = 2 } ~to_:dst ~x:0 ~y:0;
  print_endline (For_testing.to_string dst);
  [%expect {|
    ____
    ____
    ____
    ____
    |}]
;;

let%expect_test "blit with destination completely outside does nothing" =
  let src = create ~width:2 ~height:2 red in
  let dst = create ~width:4 ~height:4 black in
  blit ~from:src ~region:#{ x = 0; y = 0; w = 2; h = 2 } ~to_:dst ~x:10 ~y:10;
  print_endline (For_testing.to_string dst);
  [%expect {|
    ____
    ____
    ____
    ____
    |}]
;;
