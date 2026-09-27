# Anchored immutable dictionary keys

The unchanged two-million-update `dict_count` now executes 0.3300 times its
previous QBE instructions and 0.2717 times its previous LLVM instructions.
It still exceeds Stage 4's per-program limit: 2.1617 times accepted GC on QBE
and 2.0052 times accepted GC on LLVM. Another 39.862% / 35.169% reduction is
needed to reach 1.3. This component does not establish the 43-program geomean,
per-program or RSS acceptance requirements; RSS was not measured here.

## Bounded authority and publication

The implementation follows the reviewed
[design](d9-rc-dictionary-key-design-2026-09-27.md). It composes with an already
admitted dictionary tail, then atomically changes its key authority from
`canonical` to an explicit `anchored` certificate. Failed composition keeps the
complete previous lowering. It does not leave a canonical-O premise attached
to a key whose ordinary token publication was removed.

The exact benchmark has a named `list[str]` O home, a hidden capture, forward
negative-index normalization, a string read, one named key store, builtin
dictionary get/scalar arithmetic and the existing five-op write tail. The
certificate covers every use and writer of both capture and key across the
whole function. Each has one static definition, empty entry ownership and no
other explicit or implicit publication. Outside control flow cannot enter the
interval's interior; backedges reenter through capture. Thus both local guards
and the affected operand guards remain empty on every iteration, including
the first. The allocated entries, guards, storage, cleanup schedule, frame
linkage and step checks remain in place.

The named list source must have a dominating canonical O store, no reference,
move, drop, pattern, caller/parameter/alias or rebound home. Its original
definition cannot be intercepted by another lowering certificate. Ordinary
pre-capture COW during list setup can replace its payload transactionally but
preserves the canonical named O home; source role is not inferred merely from
the entry plan. The complete capture-to-write interval excludes source or
alias mutation, calls, scope/history events, arena transitions, hidden clone
installations and any actual planned release of the source or other owner.
Only the independently empty capture/key guards may retain harmless scheduled
drops. Every key use must be inside that interval.

The source is exactly builtin unboxed `list[str]`; the result is builtin
immutable `str`, including view-backed strings. The list's surviving ordinary
edge owns the string header and canonical backing. The projected value is a
pointer copied to private storage, not an address into reallocatable backing.
The distinct builtin list/dictionary layouts establish the required storage
separation during dictionary growth. Root, key insertion and value journals
remain real, as do the first dictionary uniqueness check and original terminal
write with their failure/drain behavior.

The existing nonheld helper supplies ordinary-input authority without widening
its original scalar-list caller. Existing read-loan scalar grammar and raw
store/result mechanics are reused. Shared dictionary-effect checks cover COW,
captures, scopes, other emission certificates and actual edge cleanup. The
exact input bypass runs before function-wide H handling: the benchmark's
later genuine list iterator still installs and releases H tokens. Uncertain
held string roles refuse. This is a whole-local empty-token proof, not an
inference from a local's name or semantic borrow role.

Functions over 4096 instructions and intervals over 256 instructions refuse.
The existing 262144 tail allowance accounts candidate code after preflight;
it is not a bound on primitive analysis operations. Source/definition/effect
preflights also perform finite scans. Parameters, pattern bindings, repeated
definitions, additional uses, callbacks, unknown operations, interior entries,
managed/custom key representations and alternate borrowed contexts keep the
old path.

Builtin strings introduce no mutable SHARE event or guest finalizer authority.
Compiler and runtime peer review found no blocker. Ordinary public guest entry
has no pending deaths; reentrant finalizer entry inherits an active drain, so
the omitted empty-token cleanup cannot advance queued sibling callbacks. The
original write still stages/acquires actual inserted keys. The allowed removal
of private token-budget failures is the existing read-borrow elision contract;
actual dictionary allocation, region, count and insertion failures remain.
Manually queued arbitrary C entry is not a new admitted boundary.

## Immutable comparison

The branch real-merged prior tail `3c4251e8` with correctness checkpoint
`869538de` at `aa452a04c686689e76701a0fa925ce264e7f3e4f`. A fresh matched control
was built before production edits; the design-only HEAD was `05e25c4c`.
The original tail compiler remains untouched. Its emitted benchmark main is
byte-identical to the fresh joined control, but the new control was used for
all before/after comparisons.

Both compiler installations are Debug and immutable:

| Side | Worktree-relative path | Compiler SHA-256 |
| --- | --- | --- |
| Before | `.tmp-rc/install-dict-key-before/bin/mylang` | `aaae8bf645d70343f44b5ea61ee7fa09b3f9637c9ce41ace7d605330f0d76adf` |
| After | `.tmp-rc/install-dict-key-prototype/bin/mylang` | `106bd30f12bcedc96d040822039088adb46ce01ff1b648d83bf36c1c443a73b2` |

The workload source SHA-256 is
`227510603349ab558eed1a9a456bb6cf3c53b725de87a1436a41b35f58844324`.
Three observations per side/backend ran on CPU 11, QBE ReleaseFast and actual
LLVM O3 with full LTO. Every one of the 18 instruction observations has exactly
one active `cpu_core` event at 100.00% running. All 22 timed/counted executions
print the exact expected `779967` line. Backend manifests and accepted-GC
native binary hashes are retained.

| Backend | Accepted GC median | Before median | After median | After/before | After/GC |
| --- | ---: | ---: | ---: | ---: | ---: |
| QBE | 661,305,033 | 4,331,539,566 | 1,429,539,240 | 0.330030 | 2.161694 |
| LLVM O3/LTO | 441,034,624 | 3,254,366,046 | 884,367,218 | 0.271748 | 2.005210 |

Separate counted executions agree exactly across backends:

| Counter | Before | After |
| --- | ---: | ---: |
| O acquire | 2,002,001 | 2,001 |
| O release | 2,004,030 | 4,030 |
| H acquire and release, each | 4,002,001 | 2,001 |
| Heap allocate and retire, each | 2,029 | 2,029 |
| Clone shells | 0 | 0 |
| Uniqueness checks | 2,001,000 | 2,001,000 |

All remaining counters are unchanged and cleanup balances. The measured delta
matches one ordinary and two hold pairs per update. Unlike the preceding tail
slice, this slice has no allocation delta. The retained 2,001,000 uniqueness
checks are a separate potential target, not removed by this certificate.

Native-policy main IL shrinks from 55,789 to 45,480 bytes. It gains the two key
markers while retaining the prior tail marker. Static loan calls fall 5 to 3,
retain calls 2 to 1 and hold-acquire calls 4 to 3; first uniqueness, native write
and frame-enter sites remain 2, 1 and 1. Disassembly of the actual QBE main
confirms the corresponding changes (loan calls 4 to 2 after native lowering).
No runtime/C source was changed. QBE archive cache identities differ with the
generated closure, so runtime archive byte identity is not claimed.

## Validation and preserved negative

The focused certificate suite passes 19 tests; the broader `RC ` unit selection
passes 84. Whole-tree Guardian passes 88 checks and formatting passes. Earlier
compile/test-fixture and Guardian rejections are archived, including the stale
cache attempt before a fresh-cache successful run. Test input declarations
include both the real benchmark and permanent key fixture.

The current four-file guest selection passes 152 uncached assertions across
GC stress/RC and both actual backends. It covers eleven permanent key cases,
the prior tail cases, semantic history and real iteration identity. The
initial ten-key matrix (148 assertions) and final eleven-key rerun (44) are
both preserved. Controls include negative indices, view-backed keys, growth,
preexisting snapshots, inherited arenas, callback fallback, later key use,
parameters, user loop bindings, held string iteration, rebinding/empty loops
and an already-owned key reassigned on a backedge.

The completed trap/budget matrix contains 118 executions: 26 successful budget
controls and 92 expected failures. Both RC compilers preserve logical outputs
and non-growth/non-physical-floor traces. The cases cover bounds, overflow,
inherited arenas, eight step limits, seven growth budgets, logical frame limit
and RC physical stack floor. All RC owner/hold/retire totals balance. The 384K
RC growth control reaches `before` and then reports `R_MEMORY_BUDGET`; 512K
succeeds. Earlier initialization failures remain recorded controls.

Four before/after public-boundary finalizer-reentry executions pass on QBE and
LLVM. A finalizer queues a sibling, reenters the dictionary update with
view-backed keys and verifies the sibling remains deferred until the outer
drain. Exact output is `status=0 phase=2 observed=1 bad=0 result=10`; all RC
counts balance.

**Preserved timeout:** an extra candidate QBE GC ReleaseFast recursion probe
with `MYLANG_OPTIONS=' --gc-stress '`, `MYLANG_MEMORY_LIMIT=128M`, stack limit
262144 bytes and depth 100000 exceeded its 60-second observation limit. It is
not counted as a passing control. The exact candidate build command, partial
receipt and timeout log are archived. A prior-control build using the same
options produces a byte-identical complete binary, SHA-256
`dd2e601288e25f5bcc5ba203b51374c9139bb5a9f8c55584ae061689b06e7061`;
both `.text` hashes are
`ba7abce2fe055b6a7216e9ab858760f8d57b1aaef0452f5407ccdde52176745a`.
This establishes unchanged generated behavior for that limited stress probe;
the timeout itself was not repeated. GC Debug logical-frame checks and both
RC physical-floor pairs completed separately.

The [archive](../../experiments/d9-rc-dictionary-key-20260927/README.md)
contains complete raw receipts, drivers, sources, emitted/native main text,
identities, rejected attempts and an independent verifier. No broad gate,
default transition or Stage 4 acceptance is claimed by this component.
