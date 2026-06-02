---
name: gpu-sdf-backend-divergence
description: How the GPU SDF backend bisimulation handles GPU-vs-CPU float divergence
metadata:
  type: project
---

The `sdf_gpu` backend (in `sdf/gpu/`) compiles `Expr_graph` to a WGSL compute shader and
runs it on the GPU (headless wgpu/lavapipe). It conforms to `Batch_backend_intf.S_parallel`.

Measured GPU(lavapipe)-vs-CPU divergence (spike over thousands of random trees):
- **Selection ops** — var, literal, min, max, abs, neg, sign, cond, comparisons, and/or/xor
  — are **bit-exact** vs the CPU backends, *provided no rounding arithmetic feeds them*
  (so `sign`/`cond`/comparisons never flip). The bisimulation test exploits this: it does
  an **exact** (bit-equal, both-NaN-ok) random bisimulation over this subset.
- **Rounding arithmetic** — `+ - * / sqrt sin cos` — diverges: lavapipe contracts
  multiply-add into fma (1 ULP; a bitcast<u32> round-trip does NOT stop the driver), div/
  sqrt are ~1 ULP, sin/cos ~5e-5 rel. Random arithmetic trees are unsound to compare
  (cancellation, overflow→inf, and especially `cond`/`sign` branch-flips give arbitrary
  divergence). So these ops are checked only on **curated, well-conditioned** expressions
  (real SDF shapes) with a relative+absolute tolerance.

Key gotcha fixed along the way: the wgpu binding's `create_shader_module`
(`wgpu/codegen/templates/high/adapter_module_prefix.ml`) stored a raw pointer into the
OCaml `wgsl` string via `set_code`, then did OCaml-allocating calls before
`device_create_shader_module` read it — a minor GC moved the string → corrupted shader
source under allocation churn. Fixed by making `set_code` the last call before the create,
with no allocation in between.
