# Borrowing a scalar mutation receiver without a temporary scope

A bounded physical proof now omits the extra RC hold/pin scope for a compiler
list receiver when its ordinary owner remains stable through the one consuming
mutation. All ordinary uniqueness checks remain. The proof does not enable
semantic COW loop hoists or change GC lowering.

The accepted path contains at most eight list headers, ending in an ordinary
named local or parameter that remains live at the mutation. Each receiver has
one static definition and one consuming mutator. The interval has at most 256
instructions in a function of at most 4,096 instructions. Every explicit edge
is checked: incoming edges bypassing the capture, backwards edges, escaping
branches, returns, calls, arena boundaries and unrecognized operations decline.
Trap edges retain the existing caller/frame cleanup protocol.

The interval permits plain scalar computation and the managed read immediately
stored into a descendant receiver on the same path. It cannot replace an
owning ancestor, publish a managed snapshot, or retain an unrelated managed
operand. Both the terminal element layout and mutation arguments/results must
have no counted or unique-drop edges. Dictionary, live-view, record-field and
recursive-box paths keep the complete existing protocol. Earlier callback
scopes preparing a receiver are independent and remain intact.

This rests on the finalized COW liveness and the existing physical receiver
anchor preservation from `c4066c99`. Ordinary named locals keep their guarded
owner until cleanup; read-only parameters retain the caller's loan. A receiver
used after the mutation retains the same physical anchor as before, since the
old mutation scope also ended at that point.

Validation on the final Debug compiler:

- Focused structural tests: 12/12, proving scalar and nested indexed writes
  omit pins, uniqueness remains, and callback/managed writes retain scopes.
- Guardian whole-tree checks: 88/88; no ratchet changes.
- 25 existing pending-receiver/array-callback assertions and 38 combined
  ownership, aggregate, borrowed-return, read-loan and new receiver assertions
  pass on each actual QBE and LLVM ReleaseFast backend (126 assertions total).
  Counts match between backends, with balanced heap retirements and holds.
- A separate out-of-bounds nested write retains `R_LIST_BOUNDS` on both
  backends and retires all six allocations without receiver holds.

The paired depth-12 matrix diagnostic changes only `n = 500` to `n = 12` in
the parity source. The control compiler has the same joined code/runtime and
only the three scope-elision hooks disabled. Both sides include scalar read
loans and runtime pointer fast paths. Every stdout is exactly
`41383\n485891\n`. Counted ReleaseFast guests, median three retired-instruction
samples on CPU 10:

| Backend | Control | Candidate | Ratio |
| --- | ---: | ---: | ---: |
| QBE | 14,466,079 | 8,895,227 | 0.6149 |
| LLVM O3/full LTO | 9,676,922 | 6,018,997 | 0.6220 |

Each run removes all 10,368 hold acquisitions and releases. The remaining
traffic is unchanged: 9,345 owner acquisitions, 9,477 releases, 132 heap
allocations/retirements, one clone and 5,652 uniqueness checks. This isolates the
scope change, but is a small counted diagnostic, not the mandated RC acceptance
corpus or an RSS result. Substantial loop ownership overhead remains.

[Compressed evidence](evidence/d9-rc-inert-receivers.json.gz) records source,
compiler/binary hashes, commands, raw counters, instruction samples and drivers.
`taskset` wraps `perf` so both execute on CPU 10; only the single counted hybrid
PMU row is accepted. LLVM commands never append a QBE selector. The root
integration owns the combined full gate and formal performance acceptance.
