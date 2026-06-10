open! Core

type t = Sample_region.t * Oracle_key.t [@@deriving sexp_of, compare]

include Comparator.S [@mode portable] with type t := t
