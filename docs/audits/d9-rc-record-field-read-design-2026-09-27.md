# D9: retained named-record field reads

Status: measured attribution and proposed bounded proof. No production change.
Scope is Stage 4 performance acceptance; no default transition or WP-5 work.

## Current evidence

Source `49c6ca07bbba8b35cda4436b831327ac40c8fc87` was built by root as an
immutable Debug compiler, SHA-256
`49a8df2d575b65b16d3e7b455a8b0d6a3aa11ac4eccc13ad34dc3eeb8b54ebd5`.
The existing guest cache was reused to build unchanged full Lox VM binary_trees
N10 for actual QBE and LLVM O3/full LTO. CPU3 median-three retired instructions
are 170,830,570,344 and 128,311,807,042. The corresponding archival accepted-GC
references are 7,243,227,886 and 3,433,157,037: **23.584868× and 37.374290× GC**.
These are current-source observations, not an isolated candidate improvement.
All six hardware observations ran at 100%, and all outputs match the oracle.

Separate counted executions agree across backends: 184,812,386 H pairs,
44,407,747 O acquires, 48,758,355 O releases, 4,350,608 heap allocations and
retirements, 1,095,889 clone shells, 20,836,904 uniqueness checks. No saturation.
The full archive and live verifier are
`experiments/d9-rc-record-field-read-20260927/`.

Fixed-period instruction sampling throttled on every recorded sample: 335 QBE
and 253 LLVM records, no lost records. Attribution is **qualitative only**;
neither helper percentages nor speedup projections are justified. Deduplicated
branch-stack site presences nevertheless repeatedly identify these exact calls:

| Guest | QBE call offsets / presences | LLVM call offsets / presences |
|---|---|---|
| `vm::run`, code field | `+0x240a`:43, `+0x2515`:42 | `+0x1658`:50, `+0x16f8`:51 |
| `vm::read_byte`, code field | `+0x203`:24, `+0x2fa`:24 | `+0x1cc`:36, `+0x276`:36 |

These are sampled branch-stack presences, not dynamic call counts. The VM pair's
descriptor argument is independently verified in both disassemblies as
`myl_t_1535267fc5a418ed8053a9a6290354ebfcee0a92538bece7aa6b84967f8fb527`
(`list[int]`), and its address originates in the named ExecFrame code field.
Whole-function machine call ordering is not used as a source-map shortcut.

Current VM emission retains 50 static native-loan sites. The 28 read sites are
14 pairs: only one pair uses a named ExecFrame; the other 13 use caller-storage
Runtime fields. The other 22 calls concern write receivers. This first proposal
targets only the named case, despite the additional caller-storage opportunities.

## Exact first interval

In current `vm::run`, `vm.my:473` is `instruction = frame.code[frame.ip]`.
`dbgloc` encodes PC+1 for emitted calls. An additional accounted emission retains
every `%position` store; both complete emissions and interval extracts are archived.
The following bytecode roles are visible in that lowering (the future proof must
query the typed instructions and states, not recognize this source spelling):

| PCs | Physical operation |
|---|---|
| 22 | Load named inline ExecFrame local4 into empty operand0. |
| 23 | Project field1, offset8, yielding its list[int] pointer. Loan to operand0. |
| 24 | Store compiler receiver local5. Current private publication loans again. |
| 25–27 | Load local4, project scalar ip at offset24, store scalar index local6. |
| 28–31 | Test index against zero; branch to PC37 for nonnegative indices. |
| 32–36 | Read local5 length, checked cast, add the negative index, store local6. |
| 37–38 | Load normalized index; checked read of local5's scalar element. |
| 39 | Store scalar instruction local7; actual edge cleanup drops receiver5. |

The root's later plain ip write starts after this interval. At PC23 the operand
journal position is logical operand0 (`rcs0`, physical entry offset1952,
guard offset488 in this exact build). Capture5 uses entry offset128/guard32.
Both retained entries begin empty at frame entry. Existing PC23 publication
sets operand0 to LOAN16; PC24 reacquires H, drops the operand loan, then guards
capture5 as LOAN16. PC39 releases capture5. A proposed raw path removes both H
acquisitions and their releases, while keeping these table entries and buffers.

## Proposed authority and bounds

Use the existing `rc_record_home.analyze` for named root authority. Require its
converged fact to be exactly O at the field read and throughout every admitted
path. Do not infer O from a source name, layout, semantic ownership role or an
initialized guard alone. This helper already accounts for canonical named stores,
typed mut-call forwarding, moves, pattern writers, aliases, hidden COW writers,
and arena/release edges. The existing named-write certificate for this root is
supporting evidence, not a substitute for querying this interval's facts.

Initial root admission remains canonical, private, nonparameter, nonmanaged inline
record storage with its original owning journal. Reject by-reference/callerStorage
roots, moved aliases, places, live views, raw unique/capability/callable authority,
and all failed or budget-exhausted home proofs. There is no ABI or frame-layout
change. Keep the same bounded root analysis (4096 instructions, 16 roots, 262144
charged work) and add a bounded interval scan, initially at most64 PCs. Whole
function capture-use checks and incoming-edge scans must charge the same budget.

Match one direct inline field of an ordinary list type. Initial elements are
plain scalar widths1/2/4/8, without counted/unique obligations; no dictionaries,
text construction, managed elements, nested collection reads or boxed paths.
The field result must go immediately to one private compiler receiver. Require
exact stack types and empty stack before the root load and after that store.

For the capture, prove exactly one reachable STORE in the entire function, no
parameter/pattern/ref/move/publication/alias/place/inout writer, and no other
physical spelling through `moves.resolve`. Every use must be a checked read or
length inside the closed interval; the scalar result is copied before it ends.
Reject return, semantic value-copy, saved/named list, argument, managed result,
unknown consumer and any use after an escaping CFG edge. Raw pointer bytes may
remain after the interval only in a permanently unguarded, never-read slot.

Prove capture guard zero by induction: zeroed at frame entry; the sole certified
STORE never arms it; no other writer exists. Preserve all original cleanup sites,
which then see zero. For operand0, require an empty entry stack and exact producer/
consumer use: LOAD does not publish a token, certified GET_FIELD does not publish
one, and immediate capture STORE does not arm it. Its later scalar reads cannot
inherit a stale token. Do not apply this reasoning to an arbitrary reused operand
with an independently owned value underneath it.

Index normalization may have its original forward conditional and join. Every
incoming edge to an interior PC must originate in the same interval, and every
successful outgoing edge must follow the final scalar read. External and loop
entries are allowed only before the root load, with the same empty-stack and
capture-writer induction. Refuse interior external/backward entries, unknown
joins, early returns and alternate capture definitions. A later loop iteration
cannot inherit an armed capture because no admitted execution arms it.

## Actual emission boundary

The proof must inspect final COW sites/captures and RC plans, after hidden receiver
liveness and alternate lowering are finalized. It is not enough to whitelist
bytecode operations. Refuse unique/unique_field, capture/fill, semantic shares,
read captures, loop uniqueness entries, active/beginning scopes, inline-origin
instructions, field transfers, dictionary tails, overlapping plain writes and
other emitter intercepts anywhere in the interval. Scalar field projections used
to compute the index may read the same retained inline root but cannot mutate it.

Examine all scheduled root/capture release edges conservatively; also consult
`qbe_rc_edges.releasesAt` for independent cleanup actually emitted at stores.
The current emitter executes fallthrough store releases only. Dictionary proofs
deliberately veto more planned edges; this proposal must not confuse planned
edges with runtime actions. Refuse every independent token cleanup even if its
source opcode is scalar. The target's own guard-clear cleanup is the single
explicit exception, and needs the whole-function induction above.

Inspect the resulting emitted span before accepting the prototype: it may contain
only raw field/slot loads, the original scalar index computation, original checks,
and guard tests whose false result has been proved. Every non-failure runtime call
must either disappear with the two private publications or cause refusal. Keep
ordinary lowering as the complete fallback; no shared runtime helpers change.
Keep `qbe_rc_ops.after`'s other consumers and `qbe_rc_locals` publication semantics
unchanged outside exact certified PCs. Retain all frame admission, guard/table
allocation, normal/trap cleanup and source root publication.

## Draining, limits and traps

Root retention alone does not justify removing a drain. The separate existing
contract in `native_rc.h` states that public ownership boundaries drain before
ordinary guest execution. Guest calls from a finalizer inherit `dead.active`;
nested drains do nothing until that outer drain resumes. Edge adapters cannot
call guests, and enqueue-only C callers must drain before ordinary guest entry.
Thus at a legal ordinary interval entry the queue is empty; during legal finalizer
reentry an outer drain is active. The admitted interval has no operation that can
enqueue a new independent death. Its old loan releases cannot kill the list:
the root's owning edge remains live (or the arena remains open). Omitted drains
therefore neither defer a legal ordinary callback nor reorder an active outer
drain. An arbitrary C caller that prequeues deaths and enters an ordinary guest
without draining violates this entry contract and is not an admitted authority.

For this concrete registered scalar-list path the flat loan needs no transfer
allocation: metadata is registered before the owning root exists, and the sole
edge has no unique/finalized payload. It acquires H and drains; unloan clears and
releases H and drains. Removing this temporary loan intentionally removes its H
traffic and its possible `R_REFERENCE_COUNT_LIMIT` admission failure. This is the
existing optimized physical-borrow contract, not exact count-limit equivalence.
All retained acquisitions continue to obey current dynamic limits; no counter or
status is bypassed. No semantic SHARED event is removed or invented.

Keep the original bounds/index normalization, arithmetic, step, logical frame,
physical stack and arena-failure sites. On a trap, the root's original journal
still owns all children; the raw capture has no independent cleanup obligation.
The proposal never authorizes mutation or region migration and has no new runtime
allocation. An enclosing arena is permitted only without any transition in the
interval, under the root's existing valid lifetime.

## Required prototype controls

- Positive named records with zero/negative indices, length reads, repeated loop
  entries, mixed scalar siblings, snapshots and replacement between complete
  intervals; exact emitted markers and raw guard-state checks.
- Refuse callback indices, root/field mutation, moves, aliases, live views, unique
  or opaque authority, nested managed elements/results, named capture publication,
  callerStorage/by-reference roots, multiple capture writers, interior external
  entries and an earlier iteration that can arm the same capture elsewhere.
- Typed CFG probes for normalization join, external backward entry, root empty/O
  join, planned and actually emitted independent releases, hidden COW capture,
  partial-body/pending ownership and generated-call veto.
- Both actual backends: unchanged output and exact error code/location for bounds,
  negative-index cast/arithmetic, frame/stack admission and step traps. Arena tests
  must cover an older root inside an inner region and a root defined in that region.
- Production-runtime reentrant finalizer control: dying object A enters the
  generated reader while sibling B remains queued under the active outer drain;
  B must remain unfinalized until A returns. Repeat with metadata registration in
  the callback, plus a normal guest entry after a public owner release has drained.
  Do not use an invalid prequeued inactive C entry as a claimed language control.
- Hold-limit control must distinguish the admitted no-H path from refused cases
  that still acquire H; compare ownership balance rather than promise the removed
  temporary admission can fail. Preserve count limits for unrelated live holds.

After peer review, implement the named-home-only certificate and exact field/store
hooks, then compare unchanged N10 and non-target controls against these immutable
receipts. No speedup is claimed before that experiment. Caller-storage field reads
such as `read_byte(mut frame)` remain a separate possible follow-up.
