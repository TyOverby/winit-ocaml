open! Core

let method_is_async (method_ : Ir.method_) : bool = Option.is_some method_.callback
