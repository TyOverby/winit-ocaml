#include <stdlib.h>
#include <caml/mlvalues.h>

/* Bytecode fallback — SIMD operations are only available in native code. */
void sdf_simd_unreachable() {
  abort();
}

/* Weak definitions for builtin symbols. The compiler replaces calls to these
   with inline SIMD instructions in native code, but the linker may still
   reference the symbols. CAMLweakdef provides overridable fallbacks. */
#define BUILTIN(name) \
  CAMLweakdef void name() { abort(); }

/* vec128 cast */
BUILTIN(caml_vec128_cast)

/* float32x4 scalar conversion */
BUILTIN(caml_float32x4_low_of_float32)

/* amd64 shuffle (used for broadcast) */
BUILTIN(caml_sse_vec128_shuffle_32)

/* arm64 broadcast */
BUILTIN(caml_neon_int32x4_dup)

/* Bitwise */
BUILTIN(caml_sse_vec128_and)
BUILTIN(caml_sse_vec128_or)
BUILTIN(caml_sse_vec128_xor)
BUILTIN(caml_neon_int32x4_bitwise_and)
BUILTIN(caml_neon_int32x4_bitwise_or)
BUILTIN(caml_neon_int32x4_bitwise_xor)

/* int32x4 compare equal */
BUILTIN(caml_sse2_int32x4_cmpeq)
BUILTIN(caml_neon_int32x4_cmpeq)

/* float32x4 arithmetic */
BUILTIN(caml_sse_float32x4_add)
BUILTIN(caml_sse_float32x4_sub)
BUILTIN(caml_sse_float32x4_mul)
BUILTIN(caml_sse_float32x4_div)
BUILTIN(caml_sse_float32x4_sqrt)
BUILTIN(caml_sse_float32x4_min)
BUILTIN(caml_sse_float32x4_max)
BUILTIN(caml_neon_float32x4_add)
BUILTIN(caml_neon_float32x4_sub)
BUILTIN(caml_neon_float32x4_mul)
BUILTIN(caml_neon_float32x4_div)
BUILTIN(caml_neon_float32x4_sqrt)
BUILTIN(caml_neon_float32x4_min)
BUILTIN(caml_neon_float32x4_max)

/* Rounding */
BUILTIN(caml_sse41_float32x4_round)
BUILTIN(caml_neon_float32x4_round_near)

/* float32x4 comparisons */
BUILTIN(caml_sse_float32x4_cmp)
BUILTIN(caml_neon_float32x4_cmgt)
BUILTIN(caml_neon_float32x4_cmge)
BUILTIN(caml_neon_float32x4_cmlt)
BUILTIN(caml_neon_float32x4_cmle)
