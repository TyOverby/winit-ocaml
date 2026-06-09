@@ portable

open! Core
include Executor.S

module Private : sig
  val run
    :  variables:Value.Array.t
    -> instructions:(int * Expr_graph.instr) iarray
    -> registers:Value.Array.t
    -> oracles:Prepared_oracle.t iarray
    -> x:Float32_u.t
    -> y:Float32_u.t
    -> unit
end
