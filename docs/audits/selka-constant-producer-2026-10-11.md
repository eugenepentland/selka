# Scalar constant producer closure

This isolated worktree starts at coherent schema-10 commit `4069e037e`.
Numeric schema-9 source and completed bounded pure evidence remain frozen in
the numeric worktree. No compiler/bootstrap or performance completion is claimed.

Native authority is `src/constant_values.zig`, `src/integers.zig`, `src/floats.zig`
and the constant dispatch in `src/sema.zig` and `src/sema_calls.zig`.
The initial producer accepted only scalar literal getters. The candidate adds
bounded scalar source interpretation, all eight integer widths, binary64,
dependent constants and nongeneric integer/bool source-function calls. Unit
constants now retain the native `E_CONSTANT_TYPE` diagnostic. No native literal
or per-body computed-answer fallback is used.

The required source inventory covers:

- All eight integer widths, bool, float and transparent aliases; direct signed
  minima, upper-u64 values, expected-width adoption and sibling evaluation order.
- Forward and imported dependencies, private initializer dependencies, caching,
  self/mutual cycles, namespace/privacy errors and unused invalid declarations.
- A validation pass over all operands before short-circuit evaluation; dead
  names, cycles and effects diagnose, while dead arithmetic does not execute.
- Checked integer operators, division/remainder rounding, bitwise/shift,
  wrapping/saturating operations and casts, with exact arithmetic diagnostics.
- Strict binary64 operations, mixed integers, signed zero, infinities, canonical
  NaNs, float intrinsics and checked float/integer conversions.
- Nongeneric free source-function calls with scalar integer/bool parameters and
  results: argument binding/defaults/keywords, locals, assignments, branches,
  while/range loops, break/continue, return checks and bounded recursion.
- The native depth limit of 256 and work budget of 65536, including validation
  work, dependency name lookup and function execution.
- Retained ordinary type checking of unevaluated initializer operands before
  publishing a folded getter and folded reads at their use spans.

Managed str/bytes literal getters retain their existing rules. General scalar
evaluation will use the qualified seed's public language semantics and direct
source interpretation; it receives no native computed per-body answers.

Owned touchpoints are new constant-specific helpers/tests, localized engine
constant dispatch, and `functions.check`'s constant folding branch. Stepped, narrow and unsigned
`for_range` lowering is also owned here as an interpreter dependency; general
`for_each` and comprehension work remains separate. Parser array
regions and runtime chained-comparison lowering are owned by their agents.
Actual native/component/shadow source, full typed graph, runtime and diagnostic
comparisons remain required before claiming this inventory qualified.

The authentic initial 79-case deployment matched source checking and every
subsequent successful typed/runtime comparison after correcting the probe's
obsolete keyword-only syntax and process-status assertions. The preserved
111-case range replay completed 1038 operations; its original cases and all
known strides match, while three dynamic strides still disagree in hidden
canonical graph fields. Printed native/component typed output is identical.
Original authentic request/reply frames are retained unchanged in the private
cache. This is pending qualification, not an admission claim.

The expanded selection now contains 136 entry fixtures (70 expected successes,
66 diagnostics) and an independently hashed imported support module. It covers
aliases, imported/public/private dependencies, source function defaults and
keywords, signature rejection, native immutable iteration diagnostics, work
and recursion budgets, numeric boundaries and diagnostics. Final fresh
installed normal/release comparisons and the bounded full producer suite are
still required. The candidate ports only the committed `f47c2d72f` thin block
checking fix and its exact depth-boundary regression from the integrated root.

The first fresh 131-case normal and release matrices each completed 1206
operations with one diagnostic difference (`support.MISSING`). Every dynamic
range now matches the native canonical graph and execution. The native oracle
confirmed that the old dynamic replies differed only in the stride local's
two declaration-span fields. The corrected candidate preserves this result.

Constant lookup now applies the native top-level/qualified-name policy before
requesting function resolution. Unknown import aliases/symbols, private
functions and wrong declaration kinds retain their native diagnostic and
related declaration span. Five additional controls qualify these boundaries.
A fresh install and complete normal/release matrices remain pending for this
correction. The obsolete queued pure gate was cancelled before admission; no
producer test or unrelated process was terminated.

Selected source qualification is now complete for committed source
`3a75ed2916e67d8c133848497c6d25f46571329c`: all 136 fixtures passed 1236
normal and 1236 release/fact/leak operations in reference, shadow and component
modes, with zero differences, profiles or skips. The unchanged native10 host
SHA is `65b5c4b61ea02208b285376313f9ab868ccbe8771d9405ec9016e8d2e6eff7df`;
body package key is `fdab24233e99a93f73210c0ec5ae84a6e28d03d309cb23e8c35486f0153dce01`
and artifact SHA is `55fef067d3c1b4e35d5ac105feb496be675e8507abc894b1b95fdb9a421d65d6`.
The qualified seed remains `c4f1ea0b6618cb7b146bbb8e035220eb36b99ff078d4a959d8bf0948d0c6d98b`.

Fresh dynamic range request payloads are identical to the native oracle's
inputs; every field in the resulting complete canonical output now matches.
Original nonce-bearing request/reply headers are preserved unchanged for each
exchange. The immutable package receipt, all producer source bytes, both final
reports, earlier failed reports and authentic captures are archived under
`docs/audits/evidence/selka-body-constants-20261011`. The frozen bounded producer
suite passed all 88 modules: 532 public tests in normal mode and 532 in
release/facts/leak-check mode, with zero failures or skips. The final archive
verifies all 175 producer source files against the installed body-package
source receipt and retains every per-file command, public-count assertion,
output and source hash. No broader completion is claimed.

Integration coverage must retain valid chained constant expressions after the
f47 runtime-chain merge, and aggregate array/capability type resolution in
rejected source signatures (`FixedArray`, `Filesystem`, `Stream`,
`byte_buffer`). The 4069 source has no producer array source catalog, so these
remain explicit integrated-source controls rather than inferred passes.
