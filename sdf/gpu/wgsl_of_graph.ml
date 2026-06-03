open! Core
open Sdf

let workgroup_size = 256

type var_kind =
  | Storage_buffer of { binding : int }
  | Inline_u32 of string

(* A WGSL [u32] literal holding the raw bits of a float32. We emit the bit pattern as a
   hex literal rather than printing the float decimally, so the GPU register starts with
   exactly the same bits the CPU backends would load — no decimal round-trip in between. *)
let f32_bits_literal (f : Float32_u.t) =
  let bits = Int32_u.to_int32 (Float32_u.to_bits f) in
  sprintf "0x%lxu" bits
;;

(* [bitcast<f32>(r{reg})] — read register [reg] back as a float. *)
let fref reg = sprintf "bitcast<f32>(r%d)" reg

(* Emit the body statements for one instruction list into [buf]. [next_temp] hands out
   fresh names for the [let] bindings a [Condition] needs to stash its then-branch value
   before the else-branch overwrites the shared output register. *)
let rec emit_instrs buf ~next_temp ~var_kinds instructions =
  for i = 0 to Iarray.length instructions - 1 do
    let out, instr = Iarray.unsafe_get instructions i in
    emit_instr buf ~next_temp ~var_kinds ~out instr
  done

and emit_instr buf ~next_temp ~var_kinds ~out (instr : Expr_graph.instr) =
  let line s = Buffer.add_string buf ("  " ^ s ^ "\n") in
  (* float-producing ops store [bitcast<u32>(...)]; comparisons store a 0u/1u flag. *)
  let store_f expr = line (sprintf "r%d = bitcast<u32>(%s);" out expr) in
  let fbin op a b = store_f (sprintf "%s %s %s" (fref a) op (fref b)) in
  let funary fn a = store_f (sprintf "%s(%s)" fn (fref a)) in
  let cmp op a b =
    line (sprintf "r%d = select(0u, 1u, %s %s %s);" out (fref a) op (fref b))
  in
  let ibin op a b = line (sprintf "r%d = r%d %s r%d;" out a op b) in
  match instr with
  | Float_literal f -> line (sprintf "r%d = %s;" out (f32_bits_literal f))
  | Bool_literal b -> line (sprintf "r%d = %du;" out (Bool.to_int b))
  | Var idx ->
    (match var_kinds.(idx) with
     | Storage_buffer _ -> line (sprintf "r%d = var%d[index];" out idx)
     | Inline_u32 expr -> line (sprintf "r%d = %s;" out expr))
  | Read reg -> line (sprintf "r%d = r%d;" out reg)
  | Add (a, b) -> fbin "+" a b
  | Sub (a, b) -> fbin "-" a b
  | Mul (a, b) -> fbin "*" a b
  | Div (a, b) -> fbin "/" a b
  | Sqrt a -> funary "sqrt" a
  | Abs a -> funary "abs" a
  | Neg a -> store_f (sprintf "-%s" (fref a))
  | Sign a ->
    (* Match the CPU's [Sign]: +1 for >0, -1 for <0, +0 otherwise (NaN included). Two
       nested [select]s give exactly that ordering without branching. *)
    store_f
      (sprintf "select(select(0.0, -1.0, %s < 0.0), 1.0, %s > 0.0)" (fref a) (fref a))
  | Sin a -> funary "sin" a
  | Cos a -> funary "cos" a
  | Round a -> funary "round" a
  | Min (a, b) -> store_f (sprintf "min(%s, %s)" (fref a) (fref b))
  | Max (a, b) -> store_f (sprintf "max(%s, %s)" (fref a) (fref b))
  | Lt (a, b) -> cmp "<" a b
  | Gt (a, b) -> cmp ">" a b
  | Lte (a, b) -> cmp "<=" a b
  | Gte (a, b) -> cmp ">=" a b
  | And (a, b) -> ibin "&" a b
  | Or (a, b) -> ibin "|" a b
  | Xor (a, b) -> ibin "^" a b
  | Condition { cond; then_; else_ } ->
    (* Evaluate both branches eagerly (no side effects), then pick. Both write the shared
       output register [out]; stash the then-value before the else-branch clobbers it.
       This mirrors the SIMD backend, which also evaluates both arms and blends. *)
    emit_instrs buf ~next_temp ~var_kinds then_;
    let tmp = next_temp () in
    line (sprintf "let t%d = r%d;" tmp out);
    emit_instrs buf ~next_temp ~var_kinds else_;
    line (sprintf "r%d = select(r%d, t%d, r%d != 0u);" out out tmp cond)
;;

let of_graph ~instructions ~final_register ~register_count ~var_kinds =
  let buf = Buffer.create 1024 in
  let add = Buffer.add_string buf in
  add "@group(0) @binding(0) var<storage, read_write> output_buf: array<u32>;\n";
  Array.iteri var_kinds ~f:(fun idx kind ->
    match kind with
    | Storage_buffer { binding } ->
      add
        (sprintf
           "@group(0) @binding(%d) var<storage, read> var%d: array<u32>;\n"
           binding
           idx)
    | Inline_u32 _ -> ());
  add (sprintf "\n@compute @workgroup_size(%d)\n" workgroup_size);
  add "fn main(@builtin(global_invocation_id) gid: vec3<u32>) {\n";
  add "  let index = gid.x;\n";
  add "  if (index >= arrayLength(&output_buf)) { return; }\n";
  (* Every register is a function-scope mutable [u32]; the register machine reuses slots,
     and a single uniform type lets that reuse work regardless of float/bool content. *)
  for r = 0 to register_count - 1 do
    add (sprintf "  var r%d: u32 = 0u;\n" r)
  done;
  let next_temp =
    let counter = ref 0 in
    fun () ->
      let n = !counter in
      incr counter;
      n
  in
  emit_instrs buf ~next_temp ~var_kinds instructions;
  add (sprintf "  output_buf[index] = r%d;\n" final_register);
  add "}\n";
  Buffer.contents buf
;;
