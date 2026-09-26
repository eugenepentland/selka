# Publish completed Lox VM closures

The VM previously allocated and published a closure with an unfilled upvalue
list, captured its upvalues into a separate list, and replaced the heap entry.
Value semantics shared the first list at publication, so filling it required
a copy. The optimized migration now publishes the closure after filling its
captures. A scalar `heap.function_upvalue_count` reader also avoids returning
the entire FunctionObj just to read its count. The change is confined to that
reader and `vm.make_closure`; it retains the bytecode, call-frame and error
reporting contracts.

During capture, new open upvalues are rooted by Runtime.open_upvalues; inherited
upvalues are rooted by the executing frame's closure. The function itself is
reachable through that frame's constants. The completed closure is allocated
and immediately pushed onto the value stack. A local function that captures
itself may create an open upvalue for its future stack slot; capture does not
read that slot before publication. Targeted self-recursive, sibling and nested
open/closed captures verify these cases with both garbage collectors stressed.

## Matched measurement

Both sides use the frozen Debug compiler `5bdd99ea` (SHA-256
`ceb38b6e1fb1a23f20d92580b3cd7f07f635f5752311f27d477f9792e388b7d5`).
Both include the smaller interpreter helpers, scalar environment/instance
readers, direct frame loads and corrected assignment RHS migration. Only the
two closure-related source changes differ. Guest binaries use ReleaseFast;
LLVM uses opt 3 and full LTO. The mandated pc.py calibrated VM inputs run three
times per side on CPU 2, with exact output checks.

| VM case | Change / prior QBE | Change / prior LLVM |
| --- | ---: | ---: |
| binary trees | 1.0000 | 1.0010 |
| closures | 0.9510 | 0.9233 |
| fib | 1.0000 | 1.0034 |
| trees | 1.0000 | 1.0020 |

The closure case saves 4.9% QBE and 7.7% LLVM; the other measured cases stay
within 0.35%. This four-case comparison is not the full stage 3 gate.
[Raw instruction samples and binary hashes](evidence/d9-lox-closure-publication-perf.json).

## Validation and reproduction

The composed source passes 65 port tests in each semantics mode, 104 smoke runs
(13 scripts, two engines, two backends, two modes), and 184 exact VM error-trace
comparisons against `60b668cf` under native GC stress, with Lox GC stress toggled.
An additional 64 runs exercise 13 VM smoke scripts plus three capture probes
on both backends/modes with native and Lox GC stress enabled simultaneously.
The three probes also match the original `60b668cf` implementation. Value-mode
validation uses the Debug `5bdd99ea` compiler; legacy validation uses the isolated
Debug default candidate `17540b57` with explicit --legacy-sharing.

`docs/audits/d9-stage3d-migrations/apply-lox.sh WORK --optimized` reconstructs
the patch from the corrected class-free base. A clean replay matches every
`.my` module byte-for-byte. The compiler's joined gate and complete performance
sweep remain separate requirements.
[Validation logs, program text, traces and source hashes](evidence/d9-lox-closure-publication-runs.json.gz).
