open! Core

type loc = Source_code_position.t [@@deriving sexp_of]

type type_annot =
  | Float_type
  | Bool_type
[@@deriving sexp_of]

type param =
  { name : string
  ; type_annot : type_annot option
  }
[@@deriving sexp_of]

type binop =
  | Add
  | Sub
  | Mul
  | Div
  | Lt
  | Gt
  | Lte
  | Gte
  | And
  | Or
[@@deriving sexp_of]

type expr =
  { loc : loc
  ; kind : expr_kind
  }
[@@deriving sexp_of]

and expr_kind =
  | Float_lit of float
  | Bool_lit of bool
  | String_lit of string
  | Ident of string
  | Placeholder
  | Binop of binop * expr * expr
  | Unary_neg of expr
  | Call of expr * expr list
  | Method_call of expr * string * expr list
  | If of expr * block * block
  | Fn of param list * block
[@@deriving sexp_of]

and block =
  { stmts : stmt list
  ; expr : expr
  }
[@@deriving sexp_of]

and stmt =
  | Let of
      { loc : loc
      ; name : string
      ; type_annot : type_annot option
      ; value : expr
      }
  | Fn_decl of
      { loc : loc
      ; name : string
      ; params : param list
      ; body : block
      }
[@@deriving sexp_of]

type program =
  { stmts : stmt list
  ; export : expr
  }
[@@deriving sexp_of]
