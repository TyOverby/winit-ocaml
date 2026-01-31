(** Shared predicates for code generation.

    This module provides common predicate functions used by both the low-level and
    high-level code generators to determine properties of API elements. *)

(** Check if a method uses callbacks (is asynchronous).

    Async methods have a callback argument and require special handling, such as
    synchronous wrappers or manual implementation.

    Returns [true] if [method_.callback] is [Some _]. *)
val method_is_async : Ir.method_ -> bool
