(** Intermediate Representation for WebGPU API types.

    This module defines the core data types that represent the WebGPU API specification
    after parsing from the YAML file. These types form the intermediate representation
    (IR) used by the code generators.

    The IR closely mirrors the structure of the webgpu.yml specification, with types for
    primitives, enums, bitflags, structs, callbacks, functions, methods, and objects. *)

(** Primitive types in the WebGPU API.

    These map to basic C types in the FFI layer and OCaml types in the high-level
    bindings. *)
type primitive =
  | Bool (** C bool, OCaml bool *)
  | Uint32 (** C uint32_t, OCaml int *)
  | Uint64 (** C uint64_t, OCaml int64 *)
  | Int32 (** C int32_t, OCaml int *)
  | Int64 (** C int64_t, OCaml int64 *)
  | Float32 (** C float, OCaml float *)
  | Float64 (** C double, OCaml float *)
  | Usize (** C size_t, OCaml int64 *)
  | String (** C WGPUStringView, OCaml string *)
  | Out_string (** Output string parameter *)
  | String_with_default_empty (** String that defaults to empty when omitted *)
  | C_void (** C void*, OCaml nativeint *)
[@@deriving sexp_of]

(** Type references in the API.

    A type_ref represents a reference to a type, which may be a primitive, a named type
    (enum, bitflag, struct, object, callback), or a compound type (array, optional,
    pointer). *)
type type_ref =
  | Primitive of primitive
  | Enum of string (** Reference to an enum by name *)
  | Bitflag of string (** Reference to a bitflag by name *)
  | Struct of string (** Reference to a struct by name *)
  | Object of string (** Reference to an object by name *)
  | Callback of string (** Reference to a callback by name *)
  | Array of
      { elem : type_ref (** Element type *)
      ; pointer : [ `Mutable | `Immutable ] option (** Pointer semantics *)
      }
  | Optional of type_ref (** Optional (nullable) type *)
  | Pointer of
      { mutable_ : bool (** Whether the pointer target is mutable *)
      ; inner : type_ref (** Pointed-to type *)
      }
[@@deriving sexp_of]

(** A constant value definition. *)
type constant =
  { name : string (** Constant name in snake_case *)
  ; value : string (** Constant value as a string *)
  ; doc : string (** Documentation string *)
  }
[@@deriving sexp_of]

(** An entry in an enum or bitflag type. *)
type enum_entry =
  { name : string (** Entry name in snake_case *)
  ; doc : string (** Documentation string *)
  ; value : int option (** Explicit value if specified *)
  }
[@@deriving sexp_of]

(** An enum type definition. *)
type enum =
  { name : string (** Enum name in snake_case *)
  ; doc : string (** Documentation string *)
  ; entries : enum_entry list (** Enum variants *)
  }
[@@deriving sexp_of]

(** A bitflag type definition.

    Bitflags are similar to enums but their values are powers of 2 and can be combined
    with bitwise OR. *)
type bitflag =
  { name : string (** Bitflag name in snake_case *)
  ; doc : string (** Documentation string *)
  ; entries : enum_entry list (** Flag variants *)
  }
[@@deriving sexp_of]

(** A member of a struct definition. *)
type struct_member =
  { name : string (** Member name in snake_case *)
  ; type_ : type_ref (** Member type *)
  ; optional : bool (** Whether this member is optional *)
  ; doc : string (** Documentation string *)
  ; pointer : [ `Mutable | `Immutable ] option (** Pointer semantics if any *)
  }
[@@deriving sexp_of]

(** Struct type classification.

    WebGPU structs are categorized based on how they participate in the extension chain
    mechanism and whether they are used for input or output. *)
type struct_type =
  | Base_in (** Input struct with nextInChain for extensions *)
  | Base_out (** Output struct with nextInChain for extensions *)
  | Base_in_out (** Struct used for both input and output *)
  | Standalone (** Struct without nextInChain *)
  | Extension_in of { extends : string list }
  (** Input extension struct, lists base structs it can extend *)
  | Extension_out of { extends : string list }
  (** Output extension struct, lists base structs it can extend *)
[@@deriving sexp_of]

(** A struct definition. *)
type struct_ =
  { name : string (** Struct name in snake_case *)
  ; doc : string (** Documentation string *)
  ; type_ : struct_type (** Struct classification *)
  ; free_members : bool (** Whether members need explicit freeing *)
  ; members : struct_member list (** Struct members *)
  }
[@@deriving sexp_of]

(** A function or method argument. *)
type arg =
  { name : string (** Argument name in snake_case *)
  ; type_ : type_ref (** Argument type *)
  ; optional : bool (** Whether this argument is optional *)
  ; doc : string (** Documentation string *)
  ; pointer : [ `Mutable | `Immutable ] option (** Pointer semantics if any *)
  }
[@@deriving sexp_of]

(** A return type specification. *)
type return_type =
  { type_ : type_ref (** The return type *)
  ; doc : string (** Documentation string *)
  }
[@@deriving sexp_of]

(** A callback definition.

    Callbacks are used for asynchronous operations in WebGPU. *)
type callback =
  { name : string (** Callback name in snake_case *)
  ; doc : string (** Documentation string *)
  ; args : arg list (** Callback arguments *)
  ; style : string (** Callback style (e.g., "callback_mode") *)
  }
[@@deriving sexp_of]

(** A standalone function definition.

    These are top-level functions not associated with any object. *)
type function_ =
  { name : string (** Function name in snake_case *)
  ; doc : string (** Documentation string *)
  ; args : arg list (** Function arguments *)
  ; returns : return_type option (** Return type if not void *)
  }
[@@deriving sexp_of]

(** A method on an object.

    Methods are functions that operate on a specific object type. *)
type method_ =
  { name : string (** Method name in snake_case *)
  ; doc : string (** Documentation string *)
  ; args : arg list (** Method arguments (excluding self) *)
  ; returns : return_type option (** Return type if not void *)
  ; callback : string option (** Callback name if this is an async method *)
  }
[@@deriving sexp_of]

(** An object type definition.

    Objects are opaque handles with associated methods. Examples include Device, Buffer,
    Texture, etc. *)
type object_ =
  { name : string (** Object name in snake_case *)
  ; doc : string (** Documentation string *)
  ; methods : method_ list (** Methods on this object *)
  }
[@@deriving sexp_of]

(** The complete API specification.

    This type represents the entire WebGPU API as parsed from webgpu.yml. *)
type api =
  { constants : constant list
  ; enums : enum list
  ; bitflags : bitflag list
  ; structs : struct_ list
  ; callbacks : callback list
  ; functions : function_ list
  ; objects : object_ list
  }
[@@deriving sexp_of]
