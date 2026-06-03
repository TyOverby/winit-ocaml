open! Core
open Sdf

module Variable_idx = struct
  type t = int
end

module Prepared = struct
  (* Everything here is immutable (and holds no GPU handles), so [t] mode-crosses
     contention and can be shared across the worker domains a caller might read the result
     from. The GPU pipeline for a given binding configuration is built lazily and cached in
     the (non-portable) [Context], keyed by the WGSL source string. *)
  type t =
    { instructions : Expr_graph.t
    ; final_register : int
    ; register_count : int
    ; num_vars : int
    ; var_mapping : (string * int) list
    }

  let of_tree tree =
    let ~instructions, ~final_register, ~register_count:_, ~var_mapping =
      Expr_graph.from_tree tree
    in
    let ~instructions, ~final_register, ~register_count =
      Expr_graph_register_minimizer.minimize ~instructions ~final_register
    in
    let num_vars = Hashtbl.length var_mapping in
    { instructions; final_register; register_count; num_vars
    ; var_mapping = Hashtbl.to_alist var_mapping
    }
  ;;

  let lookup_variable t name = List.Assoc.find t.var_mapping name ~equal:String.equal
end

(* Generate WGSL with all variables as storage buffers — the original code-gen path, used
   by [wgsl_of_tree] for tests and debugging. *)
let wgsl_of_tree tree =
  let p = Prepared.of_tree tree in
  let var_kinds =
    Array.init p.num_vars ~f:(fun i ->
      Wgsl_of_graph.Storage_buffer { binding = i + 1 })
  in
  Wgsl_of_graph.of_graph
    ~instructions:p.instructions
    ~final_register:p.final_register
    ~register_count:p.register_count
    ~var_kinds
;;

(* The result grid. Identical in spirit to the one [Make_parallel] builds: an [int32]
   bigarray (each element the raw bits of a {!Value.t}) wrapped in [Modes.Portended.t] so
   it mode-crosses contention and [get] can be called from worker domains. *)
module Grid = struct
  type inner =
    { data : (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t
    ; width : int
    }

  type t = inner Modes.Portended.t

  let create ~width ~height : t =
    let data = Bigarray.Array1.create Bigarray.Int32 Bigarray.C_layout (width * height) in
    { Modes.Portended.portended = { data; width } }
  ;;

  let[@inline] uncontended (t : t) =
    Stdlib.Obj.magic_uncontended t.Modes.Portended.portended
  ;;

  let get t ~x ~y =
    let inner = uncontended t in
    Value.of_int
      (Int32_u.of_int32 (Bigarray.Array1.get inner.data ((y * inner.width) + x)))
  ;;
end

module Result = struct
  type t = Grid.t

  let get = Grid.get
end

(* How a single variable is bound across the grid. Mirrors [Make_parallel]'s [binding]:
   grid buffers are wrapped in [Portended.t] so the binding list stays shareable. *)
type binding =
  | Uniform of int * int32
  | Affine of int * float * float * float
  | Grid_input of
      int
      * (int32, Bigarray.int32_elt, Bigarray.c_layout) Bigarray.Array1.t Modes.Portended.t

let binding_var = function
  | Uniform (v, _) | Affine (v, _, _, _) | Grid_input (v, _) -> v
;;

(* One lazily-initialised, process-wide GPU context. Building a [wgpu] device is expensive
   and there is no reason to have more than one; [run] is non-portable, so a shared
   non-portable context (with a mutable pipeline cache) is fine. Pipelines are cached by
   WGSL source so re-running the same scene across frames doesn't recompile the shader.

   The context also caches the output and readback buffers (keyed by byte size) so that
   repeated dispatches on the same grid dimensions avoid per-run buffer allocation. *)
module Context = struct
  type pipeline =
    { bind_group_layout : Wgpu.Bind_group_layout.t
    ; pipeline : Wgpu.Compute_pipeline.t
    }

  type cached_bufs =
    { byte_size : int64
    ; output_buf : Wgpu.Buffer.t
    ; readback_buf : Wgpu.Buffer.t
    }

  type t =
    { device : Wgpu.Device.t
    ; queue : Wgpu.Queue.t
    ; pipelines : (string, pipeline) Hashtbl.t
    ; mutable cached_bufs : cached_bufs option
    }

  let create () =
    let instance = Wgpu.Instance.create () in
    let adapter = Wgpu.Instance.request_adapter instance () in
    let device = Wgpu.Adapter.request_device adapter in
    let queue = Wgpu.Device.get_queue device in
    { device; queue; pipelines = Hashtbl.create (module String); cached_bufs = None }
  ;;

  let storage_entry ~binding ~read_only =
    let type_ : Wgpu.Buffer_binding_type.t =
      if read_only then Read_only_storage else Storage
    in
    Wgpu.Bind_group_layout_entry.create
      ~binding
      ~visibility:[ Wgpu.Shader_stage.Item.Compute ]
      ~buffer:
        (Wgpu.Bind_group_layout_entry.Buffer_binding_layout.create
           ~type_
           ~has_dynamic_offset:false
           ~min_binding_size:0L
           ())
      ()
  ;;

  let pipeline t ~wgsl ~num_storage_bindings =
    Hashtbl.find_or_add t.pipelines wgsl ~default:(fun () ->
      let shader = Wgpu.Device.create_shader_module t.device ~wgsl () in
      let entries =
        storage_entry ~binding:0 ~read_only:false
        :: List.init num_storage_bindings ~f:(fun i ->
             storage_entry ~binding:(i + 1) ~read_only:true)
      in
      let bind_group_layout = Wgpu.Device.create_bind_group_layout t.device ~entries () in
      let layout =
        Wgpu.Device.create_pipeline_layout
          t.device
          ~bind_group_layouts:[ bind_group_layout ]
          ()
      in
      let pipeline =
        Wgpu.Device.create_compute_pipeline
          t.device
          ~layout
          ~compute_module:shader
          ~compute_entry_point:"main"
          ()
      in
      { bind_group_layout; pipeline })
  ;;

  (* Return (output_buf, readback_buf) for the given byte size, creating them if the
     cached pair is absent or has a different size. *)
  let get_buffers t ~byte_size =
    match t.cached_bufs with
    | Some c when Int64.equal c.byte_size byte_size -> c.output_buf, c.readback_buf
    | _ ->
      Option.iter t.cached_bufs ~f:(fun c ->
        Wgpu.Buffer.release c.output_buf;
        Wgpu.Buffer.release c.readback_buf);
      let output_buf =
        Wgpu.Device.create_buffer
          t.device
          ~usage:[ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_src ]
          ~size:byte_size
          ~mapped_at_creation:false
          ()
      in
      let readback_buf =
        Wgpu.Device.create_buffer
          t.device
          ~usage:[ Wgpu.Buffer_usage.Item.Map_read; Wgpu.Buffer_usage.Item.Copy_dst ]
          ~size:byte_size
          ~mapped_at_creation:false
          ()
      in
      t.cached_bufs <- Some { byte_size; output_buf; readback_buf };
      output_buf, readback_buf
  ;;
end

let context = lazy (Context.create ())

(* A hex [u32] literal holding the float32 bit-pattern of a float64 value. *)
let f32_hex (f : float) =
  sprintf "0x%lxu" (Int32_u.to_int32 (Float32_u.to_bits (Float32_u.of_float f)))
;;

module Batch = struct
  type t =
    { prepared : Prepared.t
    ; width : int
    ; height : int
    ; mutable bindings : binding list
    }

  let create prepared ~width ~height = { prepared; width; height; bindings = [] }
  let add t b = t.bindings <- b :: t.bindings

  let set_uniform t ~var value =
    add t (Uniform (var, Int32_u.to_int32 (Value.to_int value)))
  ;;

  let set_affine t ~var ~base ~dx ~dy = add t (Affine (var, base, dx, dy))

  let set_grid t ~var data =
    add t (Grid_input (var, { Modes.Portended.portended = data }))
  ;;

  let run t ~scheduler:_ =
    let { prepared; width; height; bindings } = t in
    let len = width * height in
    let ctx = Lazy.force context in
    let byte_size = Int64.of_int (len * 4) in
    (* Build the per-variable access strategy. Affine and uniform variables are computed
       inline on-device (no buffer upload); only [Grid_input] variables need a storage
       buffer. *)
    let grid_inputs = Queue.create () in
    let next_binding = ref 1 in
    let var_kinds =
      Array.init prepared.num_vars ~f:(fun var ->
        match List.find bindings ~f:(fun b -> binding_var b = var) with
        | None -> Wgsl_of_graph.Inline_u32 "0u"
        | Some (Uniform (_, bits)) ->
          Wgsl_of_graph.Inline_u32 (sprintf "0x%lxu" bits)
        | Some (Affine (_, base, dx, dy)) ->
          let expr =
            sprintf
              "bitcast<u32>(bitcast<f32>(%s) + bitcast<f32>(%s) * f32(index %% %du) + \
               bitcast<f32>(%s) * f32(index / %du))"
              (f32_hex base)
              (f32_hex dx)
              width
              (f32_hex dy)
              width
          in
          Wgsl_of_graph.Inline_u32 expr
        | Some (Grid_input (_, ba)) ->
          let binding = !next_binding in
          incr next_binding;
          let src = Stdlib.Obj.magic_uncontended ba.Modes.Portended.portended in
          Queue.enqueue grid_inputs src;
          Wgsl_of_graph.Storage_buffer { binding })
    in
    let num_storage_bindings = !next_binding - 1 in
    let wgsl =
      Wgsl_of_graph.of_graph
        ~instructions:prepared.instructions
        ~final_register:prepared.final_register
        ~register_count:prepared.register_count
        ~var_kinds
    in
    let { Context.bind_group_layout; pipeline } =
      Context.pipeline ctx ~wgsl ~num_storage_bindings
    in
    let output_buf, readback_buf = Context.get_buffers ctx ~byte_size in
    (* Upload one storage buffer per grid-input variable. *)
    let var_bufs =
      Queue.to_array grid_inputs
      |> Array.map ~f:(fun data ->
           let buf =
             Wgpu.Device.create_buffer
               ctx.device
               ~usage:
                 [ Wgpu.Buffer_usage.Item.Storage; Wgpu.Buffer_usage.Item.Copy_dst ]
               ~size:byte_size
               ~mapped_at_creation:false
               ()
           in
           Wgpu.Queue.write_buffer ctx.queue ~buffer:buf ~offset:0L ~data;
           buf)
    in
    let bind_group =
      let entry ~binding buffer =
        Wgpu.Bind_group_entry.create ~binding ~buffer ~offset:0L ~size:byte_size ()
      in
      Wgpu.Device.create_bind_group
        ctx.device
        ~layout:bind_group_layout
        ~entries:
          (entry ~binding:0 output_buf
           :: Array.to_list
                (Array.mapi var_bufs ~f:(fun i buf -> entry ~binding:(i + 1) buf)))
        ()
    in
    let encoder = Wgpu.Device.create_command_encoder ctx.device () in
    let compute_pass = Wgpu.Command_encoder.begin_compute_pass encoder () in
    let ( (* dispatch one invocation per pixel *) ) =
      Wgpu.Compute_pass_encoder.set_pipeline compute_pass ~pipeline;
      Wgpu.set_bind_group compute_pass ~index:0 ~bind_group;
      let groups =
        (len + Wgsl_of_graph.workgroup_size - 1) / Wgsl_of_graph.workgroup_size
      in
      Wgpu.Compute_pass_encoder.dispatch_workgroups
        compute_pass
        ~workgroupCountX:groups
        ~workgroupCountY:1
        ~workgroupCountZ:1;
      Wgpu.Compute_pass_encoder.end_ compute_pass
    in
    Wgpu.Command_encoder.copy_buffer_to_buffer
      encoder
      ~source:output_buf
      ~source_offset:0L
      ~destination:readback_buf
      ~destination_offset:0L
      ~size:byte_size;
    let command_buffer = Wgpu.finish encoder () in
    let ( (* submit and wait for the GPU to finish *) ) =
      Wgpu.Queue.submit ctx.queue ~commands:[ command_buffer ];
      Wgpu.Device.poll ctx.device ~wait:true ()
    in
    let result = Grid.create ~width ~height in
    let ( (* map the readback buffer and copy it into the result grid *) ) =
      Wgpu.map_buffer
        readback_buf
        ~mode:[ Wgpu.Map_mode.Item.Read ]
        ~offset:0L
        ~size:byte_size;
      Wgpu.Device.poll ctx.device ~wait:true ();
      let mapped =
        Wgpu.get_const_mapped_range
          readback_buf
          ~offset:0L
          ~size:byte_size
          ~kind:Bigarray.int32
      in
      let dst = (Grid.uncontended result).data in
      Bigarray.Array1.blit mapped dst;
      Wgpu.Buffer.unmap readback_buf
    in
    let ( (* release per-run GPU resources; output/readback buffers are cached *) ) =
      Wgpu.Bind_group.release bind_group;
      Array.iter var_bufs ~f:Wgpu.Buffer.release;
      Wgpu.Command_buffer.release command_buffer;
      Wgpu.Compute_pass_encoder.release compute_pass;
      Wgpu.Command_encoder.release encoder
    in
    result
  ;;
end
