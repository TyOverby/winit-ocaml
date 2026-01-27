open! Core

(** Regression tests using the real webgpu.yml file.

    These tests load the actual WebGPU API specification and generate code for specific
    items, capturing the output as expect test snapshots. This helps detect regressions
    when codegen changes affect real API types. *)

(** Find the webgpu.yml file relative to the test directory. Tests can run from various
    directories depending on the build system. *)
let find_yml_path () : string =
  let candidates =
    [ "webgpu.yml"
    ; "vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ; "../../../../vendor/wgpu-native/ffi/webgpu-headers/webgpu.yml"
    ]
  in
  match List.find candidates ~f:Stdlib.Sys.file_exists with
  | Some path -> path
  | None -> failwith "Could not find webgpu.yml"
;;

let webgpu_yml_path = find_yml_path ()

(** Lazily loaded API from the real webgpu.yml *)
let api = lazy (Parse_yml.load_file webgpu_yml_path)

(** {2 Lookup Functions} *)

let lookup_enum name =
  let api = Lazy.force api in
  match List.find api.enums ~f:(fun e -> String.equal e.name name) with
  | Some e -> e
  | None -> failwithf "Enum not found: %s" name ()
;;

let lookup_bitflag name =
  let api = Lazy.force api in
  match List.find api.bitflags ~f:(fun b -> String.equal b.name name) with
  | Some b -> b
  | None -> failwithf "Bitflag not found: %s" name ()
;;

let lookup_struct name =
  let api = Lazy.force api in
  match List.find api.structs ~f:(fun s -> String.equal s.name name) with
  | Some s -> s
  | None -> failwithf "Struct not found: %s" name ()
;;

let lookup_object name =
  let api = Lazy.force api in
  match List.find api.objects ~f:(fun o -> String.equal o.name name) with
  | Some o -> o
  | None -> failwithf "Object not found: %s" name ()
;;

let lookup_method obj method_name =
  match List.find obj.Ir.methods ~f:(fun m -> String.equal m.name method_name) with
  | Some m -> m
  | None -> failwithf "Method not found: %s.%s" obj.name method_name ()
;;

let all_structs () = (Lazy.force api).structs

(** {2 Print Helpers} *)

let print_enum_outputs enum =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_enum_constants enum);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_enum enum);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_enum enum);
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_enum enum);
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_enum enum)
;;

let print_bitflag_outputs bitflag =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_bitflag_constants bitflag);
  print_endline "=== High-level MLI ===";
  print_endline (Gen_high.For_testing.gen_mli_bitflag bitflag);
  print_endline "=== High-level ML ===";
  print_endline (Gen_high.For_testing.gen_ml_bitflag bitflag)
;;

let print_struct_outputs struct_ =
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_struct_stubs struct_);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_struct struct_);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_struct struct_)
;;

let print_method_outputs obj method_ =
  let structs = all_structs () in
  print_endline "=== Low-level C ===";
  print_endline (Gen_low.For_testing.gen_c_method_stub obj method_);
  print_endline "=== Low-level MLI ===";
  print_endline (Gen_low.For_testing.gen_mli_method obj method_);
  print_endline "=== Low-level ML ===";
  print_endline (Gen_low.For_testing.gen_ml_method obj method_);
  print_endline "=== High-level MLI ===";
  print_endline
    (Gen_high.For_testing.gen_mli_method structs obj method_
     |> Option.value ~default:"(none)");
  print_endline "=== High-level ML ===";
  print_endline
    (Gen_high.For_testing.gen_ml_method structs obj method_
     |> Option.value ~default:"(none)")
;;
