open! Core

let command =
  Command.group ~summary:"Neon sdf evaluator" [ "ui", Ui.command; "svg", Svg.command ]
;;

let () = Command_unix.run command
