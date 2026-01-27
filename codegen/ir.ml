open! Core

type primitive =
  | Bool
  | Uint32
  | Uint64
  | Int32
  | Int64
  | Float32
  | Float64
  | Usize
  | String
  | Out_string
  | String_with_default_empty
  | C_void
[@@deriving sexp_of]

type type_ref =
  | Primitive of primitive
  | Enum of string
  | Bitflag of string
  | Struct of string
  | Object of string
  | Callback of string
  | Array of
      { elem : type_ref
      ; pointer : [ `Mutable | `Immutable ] option
      }
  | Optional of type_ref
  | Pointer of
      { mutable_ : bool
      ; inner : type_ref
      }
[@@deriving sexp_of]

type constant =
  { name : string
  ; value : string
  ; doc : string
  }
[@@deriving sexp_of]

type enum_entry =
  { name : string
  ; doc : string
  ; value : int option
  }
[@@deriving sexp_of]

type enum =
  { name : string
  ; doc : string
  ; entries : enum_entry list
  }
[@@deriving sexp_of]

type bitflag =
  { name : string
  ; doc : string
  ; entries : enum_entry list
  }
[@@deriving sexp_of]

type struct_member =
  { name : string
  ; type_ : type_ref
  ; optional : bool
  ; doc : string
  ; pointer : [ `Mutable | `Immutable ] option
  }
[@@deriving sexp_of]

type struct_type =
  | Base_in (** Input struct with nextInChain *)
  | Base_out (** Output struct with nextInChain *)
  | Base_in_out (** Both input and output *)
  | Standalone (** No nextInChain *)
  | Extension_in of { extends : string list } (** Extension struct for input *)
  | Extension_out of { extends : string list } (** Extension struct for output *)
[@@deriving sexp_of]

type struct_ =
  { name : string
  ; doc : string
  ; type_ : struct_type
  ; free_members : bool
  ; members : struct_member list
  }
[@@deriving sexp_of]

type arg =
  { name : string
  ; type_ : type_ref
  ; optional : bool
  ; doc : string
  ; pointer : [ `Mutable | `Immutable ] option
  }
[@@deriving sexp_of]

type return_type =
  { type_ : type_ref
  ; doc : string
  }
[@@deriving sexp_of]

type callback =
  { name : string
  ; doc : string
  ; args : arg list
  ; style : string
  }
[@@deriving sexp_of]

type function_ =
  { name : string
  ; doc : string
  ; args : arg list
  ; returns : return_type option
  }
[@@deriving sexp_of]

type method_ =
  { name : string
  ; doc : string
  ; args : arg list
  ; returns : return_type option
  ; callback : string option
  }
[@@deriving sexp_of]

type object_ =
  { name : string
  ; doc : string
  ; methods : method_ list
  }
[@@deriving sexp_of]

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
