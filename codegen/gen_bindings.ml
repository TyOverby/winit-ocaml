open! Core

let s = "hi"
let x = {%string|a %{s}|}

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

(** Find the webgpu.yml file relative to the executable or source tree *)
let find_yml_path () : string =
  (* Try relative to current directory first *)
  let candidates =
    [ "vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ]
  in
  match List.find candidates ~f:Sys_unix.file_exists_exn with
  | Some path -> path
  | None -> failwith "Could not find webgpu.yml"
;;

let command =
  Command.basic
    ~summary:"Generate wgpu OCaml bindings from webgpu.yml"
    (let%map_open.Command level = anon ("LEVEL" %: Level.arg)
     and kind = anon ("KIND" %: Kind.arg) in
     fun () ->
       let yml_path = find_yml_path () in
       let api = Parse_yml.load_file yml_path in
       match kind, level with
       | Ml, Low -> print_string (Gen_low.gen_ml api)
       | Mli, Low -> print_string (Gen_low.gen_mli api)
       | C, Low -> print_string (Gen_low.gen_c_stubs api)
       | Ml, High ->
         Gen_high.check_method_coverage api;
         print_string (Gen_high.gen_ml api)
       | Mli, High ->
         Gen_high.check_method_coverage api;
         print_string (Gen_high.gen_mli api)
       | C, High -> failwith "no c bindings in high level module")
;;

let () = Command_unix.run command
