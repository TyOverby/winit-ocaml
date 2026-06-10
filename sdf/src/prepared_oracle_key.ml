open! Core

type t = Sample_region.t * Oracle_key.t [@@deriving sexp_of, compare]

include functor Comparator.Make [@mode portable]
