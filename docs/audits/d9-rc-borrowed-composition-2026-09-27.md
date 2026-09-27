# Composed physical borrowed returns

The optional physical return certificate now composes complete direct-callee
proofs. Schematic `innerPin` calls `partPin` twice, compares scalar fields and
`depth` results, then returns a pin anchored to its caller's pin list. Its new
borrowed entry can pass those intermediate bits directly through the complete
proved activation. Canonical, indirect and exported calls retain owned results.

This is a bounded compiler change after fixed-point loops `3b867d50`; no runtime,
allocator, collection helper or emitter hook changes. Its independently reviewed
[design](d9-rc-borrowed-composition-design-2026-09-27.md) records the preimplementation
contract. Measurements below compare consecutive RC slices, not the complete
WP-4 acceptance corpus against GC.

## Call proof and emission agreement

At every direct call, the proof validates the actual argument count and physical
types against the exact callee signature. A complete callee answer contains its
physical result type and either one parameter anchor or immortal-only edges.
The caller maps that parameter to the actual argument's converged anchor. It
keeps an immortal actual immortal; different mapped caller parameters still
refuse at any join or return, including facts introduced only by a backedge.
No semantic return-origin or copy-elision flag substitutes for this proof.

Internal integer, boolean and unit helpers use the same closed whole-body
analysis. Fresh constructors, mutation, callbacks, indirect/host calls, arena
changes and unique contents remain refused even if their result is scalar or
later discarded. Public alternate discovery skips scalar results. The canonical
scalar entry remains in use, with its normal call checks and return ABI. The
emitted regression verifies that the admitted scalar helper has no native
ownership calls or ownership frame entry, while the raw managed caller invokes
the managed helper's separate borrowed symbol twice. Inline return bits use the
existing return storage before the callee stack disappears.

Each root query retains at most 16 completed dependency answers, keyed by exact
function index in one unchanged program/catalog/ABI. An entry contains only the
abstract value and dependency hash; it stores no arena-owned analysis pointer.
A reserved incomplete entry refuses reentry, and the existing active-code guard
also rejects recursive calls. There is no eviction. Depth 16, 65,536 total state
cells and 524,288 work cells still bound the complete query. Repeated calls and
final hashing reuse the immutable answer; distinct bodies pay their full proof
cost. Exhaustion declines the optional optimization rather than changing legal
program behavior.

A callee independently queried for alternate emission has a subset of the
accepted caller's acyclic dependency graph and a fresh full budget. No-eviction
memoization ensures the caller cannot gain admission by repeatedly discarding
and recomputing dependencies in a way unavailable to that independent query.
Permanent tests certify both a large helper and its repeated caller near the
state bound, then verify that both alternate symbols are actually emitted.
Sixteen distinct callees accept and a seventeenth refuses.

Policy v6 invalidates prior certificate identities. The final ascending-PC scan
hashes each complete transitive callee identity and mapped parameter anchor.
Queue visits and memo reuse do not replace that deterministic final hash. A
warm/cold fragment regression changes an immortal nested fallback into fresh
bytes, checks caller invalidation and refusal, and restores the original source
with identical fresh/reused output.

## Matched exact schematic result

The immutable loop-only predecessor is `3b867d50`, compiler SHA-256
`54f19f6b7d0229727d21e8474dadba7a2aaacc4366568223105e614210765518`.
The final candidate Debug compiler is
`504d4d0643cbbad8b9fc527554b0b9bfcb53e8e1553c3db39ca0c6ab69aa7679`.

The driver uses unchanged source/provider, project inputs and `pc.py` build/run/
check commands. LLVM explicitly selects `--backend llvm --llvm-opt 3 --lto`.
Each normal binary runs three times on CPU 3 with unscaled
`cpu_core/instructions/u`; all 36 observations report 100% event running time.
Every normal/counting check and measured run verifies the complete SVG hash.
Separate counted binaries agree exactly between backends.

| Backend | Exact workload | Before instructions | After instructions | After / before |
| --- | --- | ---: | ---: | ---: |
| QBE | fixture | 932,122,046 | 891,392,312 | 0.95630 |
| QBE | changed-net | 934,478,070 | 893,149,623 | 0.95577 |
| QBE | changed-value | 931,762,302 | 891,948,584 | 0.95727 |
| LLVM | fixture | 778,723,771 | 738,593,666 | 0.94847 |
| LLVM | changed-net | 774,082,477 | 738,715,938 | 0.95431 |
| LLVM | changed-value | 773,878,456 | 742,811,759 | 0.95986 |

Fixture/value O acquisitions fall from 168,193 to 152,897; releases fall from
168,349 to 153,053. H pairs fall from 343,278 to 335,630. Changed-net O falls
from 168,165/168,321 to 152,869/153,025 and H from 343,520 to 335,872.
Every run retains 156 heap allocations and retirements, one clone, no arena
allocation, no refusal and no saturation. Uniqueness remains 16,776 (changed-net
16,806). All ownership balances hold.

`innerPin_rc_borrow` now exists and contains zero native loan, retain or take
calls; it calls `partPin_rc_borrow` for both managed results and canonical
`depth` for scalar results. The canonical functions remain unchanged. The
original outer caller still establishes an independent result before releasing
its input anchors. This bounded composition removes intermediate traffic while
preserving that ownership boundary.

## Validation and evidence

The focused `RC-BORROW` suite passes 34/34: 23 named tests and 11 common unnamed
blocks. Added cases cover exact reordered mappings, distinct callee parameters
mapping to one caller anchor, backedge conflicts, discarded allocating scalar
helpers, complete memo bounds, actual independent alternate entries and
transitive cache loss/restoration. Existing recursion, freshness, unique,
unavailable-local and bounded-work controls remain green.

Five standalone assertions run under GC stress and counted RC on both actual
backends. They cover nested helper results after parent replacement, genuine
snapshots, immortal fallback, reordered arguments, caller arena escape, indirect
owned results and the conflicting-anchor negative. Bounds, step and frame trap
controls run inside a caller arena on both runtimes and both backends, preserving
the prior output marker and counted cleanup. Both RC backends agree: 52 heap allocations and retirements, O23+52=75,
H15 pairs and 10 arena objects for the five assertions. Each trap control
allocates six arena objects, retires all heap/O/H obligations (zero here) and
retains the expected trap. The final compiler reran every control; earlier
successful evidence is separately preserved and excluded from these totals.

The final Debug build passes Guardian's 88 checks. Initial findings for a long
fixture line, a compound boolean and extra test-body loops were corrected by
splitting the fixture and naming/extracting the relevant helpers. No baseline or
rule changed. The integration parent owns the joined full gate and complete
corpus runs. Commands, source delta, IL, compiler identities, raw counters and an
independent verifier are in the
[archive](../../experiments/d9-rc-borrowed-composition-20260927/README.md).
