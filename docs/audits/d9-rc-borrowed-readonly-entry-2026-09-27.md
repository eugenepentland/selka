# Raw borrowed and immortal entries: measured schematic frame removal

This compiler-only slice removes the empty RC journal from independently certified
borrowed entries, and adds a distinct constant-result entry for zero-argument
helpers. The three unchanged schematic workloads use 7.9–8.7% fewer QBE
instructions and 4.3–6.6% fewer LLVM instructions. Ownership counters and full SVG
outputs are identical. This is progress, not Stage 4 acceptance: the candidate
still costs 11.12–11.14× accepted GC on QBE and 16.54–16.82× on LLVM, above the
1.3× per-workload cap. RSS was not measured in this isolated slice.

The reviewed designs are [borrowed entries](d9-rc-borrowed-readonly-entry-design-2026-09-27.md)
and [immortal entries](d9-rc-immortal-entry-design-2026-09-27.md). Their proposal
status and initial refusal evidence are historical; this report records the
implemented scope and validation. Root and both runtime/compiler peers reviewed
the proof, routing, return storage and physical preflight.

## Authority and actual target

An existing public `BorrowCertificate` remains necessary for `_rc_borrow`.
A second optional, physically quiet readonly proof permits that alternate to
omit its empty ownership journal. Canonical and function-value calls retain the
owned convention. Managed root recursion, unique/finalized/opaque/callable/live
view contents, Result-return error traces and unsupported physical plans refuse
this optional optimization.

The initial prototype correctly refused the actual `sexpr::at` and
`layout::partPin` alternates: their fallback calls to zero-argument `text::empty`
had no public parameter anchor. The private borrow analyzer's answer was not
used as a calling convention. Those original manifests and refusal receipts
remain archived.

`ImmortalCertificate` now provides separate public authority. Its first grammar
is call-free, straight-line, fully initialized typed constants, local bit
loads/stores, and complete inline records/arrays containing frozen builtin
immutable byte literals. Dynamic `bytes(...)`, `str`, mutable buffers, resources,
boxes, views, variant construction, arithmetic, references and external producers
remain refused. No scalar wrappers were needed or added. A shared
`constant_literal.frozen` predicate is used by the public proof, existing borrow
proof and actual literal emitter; it cannot admit an allocator fallback.

The dedicated `_rc_immortal` Unit has separate symbol/metadata attribution.
Readonly calls save exact PC, target, result layout and tagged public certificate;
emission chooses that alternate before `frame.get`. A missing managed route is
an invariant failure, never a canonical owned-call fallback. Canonical
`text::empty` remains owned. The readonly policy is v4 and the immortal policy
v1; cache keys bind successful and refused queries, literal bytes, complete
layouts, route kind, ABI and transitive readonly dependencies.

Actual final emission confirms `at_rc_borrow` and `partPin_rc_borrow` have zero
RC frame-enter calls, zero loans and zero retains, with one and two actual calls
to `text::empty_rc_immortal`, respectively. The immortal entry has zero frame,
loan or retain calls. `innerPin_rc_borrow` was already raw. `form` remains raw.
The original admission summary accidentally counted the immortal declaration as
a call; it is preserved, and `admission.json` corrects the summary using actual
`call` instructions from the complete final manifest.

## Bounds and physical effects

The immutable public query has independent standalone limits: 128 instructions,
32 locals, stack depth 128, 256 distinct visited types and 4096 logical units.
Logical units charge instructions, newly visited types, record fields and
constructor operands. Bounded duplicate/type lookup and at-most-128 stack/field
checks are additional composed work, not claimed to be individually charged.
Its native IR/liveness/ownership/COW preflight uses the existing exact production
planner and independent physical input-volume limits.

Readonly composition retains at most 16 completed analyzed bodies and 16
managed targets shared across the entire root composition, including both
borrowed and immortal kinds; active depth is 16 and logical instruction allowance
is 65536. A supplied borrowed root requires an extra independent public query;
that does not enlarge the managed-callee allowance. Standalone public borrowed
queries keep their existing bounds. For the shared physical allowance, each
completed immortal dependency charges its preflight dimensions again to the
root budget; standalone proof validity is never inferred from remaining root
budget. The per-body cap is 1024 instructions/256 locals. Shared limits are
65536 cells (`n*(n+locals)`) and 4194304 input-volume units
(`cells*(locals+1)`), not a count of every inner planner operation.

Early selection and final physical verification use the same quiet-planning
contract. Unsupported COW places, captures, shares, checks, mutation paths and
implicit ownership effects refuse before raw selection. Final verification also
checks the exact entry result certificate and return error-trace veto. Ordinary
stack/frame admission and step checks remain. Small heap-frame return bytes are
copied to return storage before release; results above 4096 bytes use the caller's
`%out` storage before release. Saved results survive subsequent calls.

No runtime ownership helper, drain policy or allocator changes are included.
The removed cleanup had no owning/held tokens or scopes. Legal public ownership
boundaries already drain pending deaths; reentry from an active finalizer leaves
the existing drain active. The C embedding controls exercise both cases,
including a sibling queued by an active finalizer that remains deferred until
the outer drain resumes. They do not forge a finalized guest payload into an
admitted type.

## Immutable identities and measurements

The source is base `833865253e2f460fb1d1a2fb7b5ca3e547fe34a5` plus the archived
source patch and file hashes. The immutable before compiler is production
`c07016f308422b76cfe55607b26243efe0b4257e`, SHA256
`db9d8791fb56a9c07e5db529b5abe54b2689966364095de89e2abcaca4409b2b`.
The final Debug compiler is
`e22a3d742351b9ba827a6f5fd07a7f201a098bfd76506dfaba7ff1159bf2e814`.
Their install and guest paths are in `identity.json`; measured binaries remain
fixed. No guest source, input, accepted GC binary or expected output changed.

CPU2, interleaved median-three, 36 raw `perf stat` instruction rows, all at
100% counter running. Guest manifests establish actual QBE and LLVM O3/LTO.
The exact accepted GC denominators come from the archived
`helpers-word-c07016f3/results.json` receipt and its original accepted binaries;
the paired before measurements here are new samples, not silently substituted
historical samples.

| Workload | Backend | Before instructions | After instructions | After/before | After/accepted GC |
|---|---|---:|---:|---:|---:|
| fixture | QBE | 227,044,922 | 207,215,746 | 0.912664 | 11.143407 |
| changed-net | QBE | 225,107,246 | 206,884,998 | 0.919051 | 11.120358 |
| changed-value | QBE | 224,460,434 | 206,719,790 | 0.920963 | 11.117023 |
| fixture | LLVM | 159,827,863 | 149,787,197 | 0.937178 | 16.535304 |
| changed-net | LLVM | 160,780,484 | 150,225,551 | 0.934352 | 16.575372 |
| changed-value | LLVM | 159,200,136 | 152,345,418 | 0.956943 | 16.819194 |

All 12 counted workload executions balance and match before/after and both
backends exactly: 156 heap allocations/retirements, one clone shell, 93,402 owner
acquires/93,558 releases. Fixture and changed-value have 248,006 hold pairs and
16,389 uniqueness checks; changed-net has 248,296 and 16,419. This slice removes
empty framework work rather than these remaining ownership operations.

## Correctness and evidence limits

Focused final-source Zig runs passed 18/18 immortal/OOM cases, 26/26 existing
readonly cases and 15/15 raw-entry/return cases (each total includes 11 common
harness tests). Cases cover public proof mismatches/refusal, exact 128-instruction
and mixed 16-target boundaries, recursion, allocated results, error traces,
complete Unit routing and return-storage ordering. Whole Guardian passed 88
checks; `fmt-check` passed. Root owns the subsequent combined full gate.

Actual QBE and LLVM controls passed:

- Eight ReleaseFast GC-stress/RC executions, three assertions each: saved
  borrowed/immortal results, repeated calls, caller arenas and canonical function
  values. RC counts balance.
- Eight RC ABI executions: a small result from a large heap frame and a 4816-byte
  result via `%out`, each saved across another call; all counts balance.
- Eight paired legal-boundary/reentrant-finalizer runs and four native-floor
  trap runs; final candidate was rebuilt and re-executed for all six candidate
  combinations after the last source change.
- Twenty exact Debug step/frame/bounds/overflow traps and eight successes in
  the initial paired receipt. The final compiler's 14 candidate runs were
  repeated and compared with the original before receipt, including exact
  non-count stderr and stdout. All counts balance.
- Six warm/cold cache emissions covering changed literal bytes and loss of the
  immortal certificate through a plain intermediary, plus four actual native
  fallback executions. The cache receipt names the earlier candidate compiler;
  the final production difference only propagates route lookup/layout OOM and
  has its own focused failure tests.

The last production change preserves `OutOfMemory` from route catalog/layout
queries. Eight ReleaseFast controls/ABI binaries rebuilt with the final compiler
match the earlier candidate byte-for-byte. Debug shared-library and trap binary
identity assertions failed; their original logs, section hashes and failed
assertions are retained. No binary-equivalence claim is made for those builds.
Actual final-compiler finalizer/floor and Debug trap reruns supply the required
behavioral evidence instead. The bridge receipt intentionally ends at its later
failed trap-identity assertion; its six successful finalizer/floor executions
are checked individually. Initial Guardian/style and mock-test failures are
also retained rather than counted as successes.

The archive is [d9-rc-borrowed-readonly-entry-20260927](../../experiments/d9-rc-borrowed-readonly-entry-20260927).
Run `python3 experiments/d9-rc-borrowed-readonly-entry-20260927/verify.py --live`
for receipt, exact output, count, identity and live-artifact verification. The
three schematic workloads are this slice's measured target; no new full Lox,
full-corpus, RSS or default-runtime acceptance claim is made.
