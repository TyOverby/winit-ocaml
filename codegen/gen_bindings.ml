open! Core

module Kind = struct
  type t =
    | C
    | Ml
    | Mli

  let arg =
    Command.Arg_type.create (fun s ->
      match String.lowercase s with
      | "c" -> C
      | "ml" -> Ml
      | "mli" -> Mli
      | _ -> failwith "kind must be 'c', 'ml' or 'mli'")
  ;;
end

module Level = struct
  type t =
    | High
    | Low

  let arg =
    Command.Arg_type.create (fun s ->
      match String.lowercase s with
      | "high" -> High
      | "low" -> Low
      | _ -> failwith "level must be 'high' or 'low'")
  ;;
end

let command =
  Command.basic
    ~summary:"Example command that produces a (kind * level) value"
    (let%map_open.Command level = anon ("LEVEL" %: Level.arg)
     and kind = anon ("KIND" %: Kind.arg) in
     fun () ->
       (* TODO: implement data model parsing in separate .ml file, and then put low level and high level code generation in their own files too. *)
       match kind, level with
       | Ml, Low -> print_endline "(* low level ml *)"
       | Mli, Low -> print_endline "(* low level mli *)"
       | Ml, High -> print_endline "(* high level ml *)"
       | Mli, High -> print_endline "(* high level mli *)"
       | C, Low -> print_endline "// C stubs go here"
       | C, High -> failwith "no c bindings in high level module")
;;

let () = Command_unix.run command
