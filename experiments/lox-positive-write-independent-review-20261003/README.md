# Independent positive indexed-write proof review

No actionable certificate defect was found in the author's stable source
hashes recorded in `review.json`. This is a read-only source review, separate
from author compiler/native qualification and root performance acceptance.
The source was explicitly declared stable by its author; the final candidate
commit and broad check receipts were pending at this review freeze. Copies of
the new proof, shared normalizer and tests preserve the exact reviewed version.

The shortcut's signed test `index >= 0` is exactly the false edge of the
canonical normalizer's `index < 0`. For that edge, the original nine-instruction
prefix leaves the preexisting operand stack unchanged and does not write the
index local. The certificate verifies equal start/join stack heights and types,
with no dropping or tracing layouts. A successful guard goes to the original
index reload at `start+9`. A negative guard goes to the original `start`, so
length casting and checked negative-index addition remain on their original
path. Unlike the read shortcut, this guard performs no payload read and needs
no unsigned length argument; the two-byte element stride gate is conservative.

The `start+10` RHS reload, `start+11` buffer write, and subsequent result and
cleanup protocol remain unchanged. Their source positions, bounds test, COW
detach/publication, ownership roles, arena behavior and root handling run at
the original PCs. The prepended guard performs one ordinary scalar local load,
comparison and branch: no allocation, callback, publication or trap. Its index
must be an i64 temporary without reference/caller storage. The aggregate move
alias planner excludes scalar types, so this direct load uses the same physical
slot as the original normalizer's load.

The proof requires a native RC plan before consulting `inertReceiver.proven`.
That existing whole capture-to-write certificate supplies a unique temporary
receiver definition, one write, and a named owning root kept alive through the
closed interval. Its bounded scans reject callbacks, unknown effects, receiver
replacement, backward edges, outside entries, and ownership gaps. Receiver
references, caller storage and direct aliases refuse; named mut-list aliases
can carry a pin outside the pending-place captures array, so the explicit alias
refusal is necessary. A callback that already ended a pending place can leave
such a pin, which is why a quiet nine-PC prefix alone is insufficient.

Every skipped PC additionally rejects capture/fill/read-capture/share work,
uniqueness work, COW loop entries, active or beginning pending scopes and actual
RC local releases. The canonical prefix contains no call, allocating opcode,
arena transition or receiver write, so its ordinary after-instruction receiver cleanup
cannot conceal a callback or write scope. Plain temporary operand values do
not publish ownership edges. The checked write itself still executes its full
before/after protocol.

CFG refusals include all existing explicit edges. Interior prefix PCs require
no branch target; the final join separately rejects noncanonical jumps,
conditional jumps, Result error targets and variant-switch arms through shared
`extraEntry`. Only the exact canonical conditional at `start+3` may enter that
join. Versioned/original loop copies refuse. Quiet loop-entry checks prevent
the shortcut from skipping COW entry blocks; ordinary incoming edges can still
enter the original body and safely miss the optimization. The shared read
normalizer refactor preserves its old consuming read/length owner identity and
all old read acceptance checks.

GC, step-accounted, reference, alias, callback, managed/live-view, byte/zero
stride, pending scope and unsupported receiver paths retain the original code.
The five new compiler tests inspect admission/refusal, counting/GC fallback,
exact native bounds details and traces for signed extremes/empty lists, and
snapshot/alias/callback behavior under stress. Three new language cases cover
record and detached snapshots, callback replacement, and nested writes.
Existing shared CFG tests include forward/backward Result entries. The review
does not claim independent test execution or exhaustive synthetic plan coverage.

The result depends on validated typed bytecode and finalized stack, COW, RC,
liveness and ownership plans, plus the existing inert receiver proof. It does
not broaden the ABI, native frame maps, unwind protocol, allocator or payload
write implementation. Those files remain unchanged by this candidate. No
compiler candidate, root manifest, guest, input or performance measurement was
modified during review.
