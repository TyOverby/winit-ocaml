open! Core

(** Shared predicates for code generation *)

(** Check if a method uses callbacks (async). Async methods have a callback argument and
    need special handling (sync wrappers or manual implementation). *)
let method_is_async (method_ : Ir.method_) : bool = Option.is_some method_.callback
