# D9 indexed payload return proof — 2026-09-26

A mutable collection field extracted from a private union payload can omit its
sharing transfer when a unique outer list immediately regains that value through
a proved same-index replacement. This targets instance-table updates while
retaining private match payload storage and the ordinary final list write.

## Proof boundary

The parent must be a `mut list` parameter, and the function must have no second
mutable parameter. The existing caller protocol makes this outer list unique and
pins it before the callee reads an element. If the caller has an outer snapshot,
that detachment marks shared children before the temporary field is mutated.
Record-held lists and ordinary local list values are deliberately excluded.

The extraction must be the first use of this parent in the function, and no
control edge may revisit the read. This excludes earlier match and iteration
bindings, which can retain an unmarked borrow even though their ownership role
is `owned` and their parent provenance is no longer available. A regression with
two nested matches of the same element verifies this boundary both with and
without a caller snapshot.

The selected payload copy must already be elided by the ordinary ownership
analysis. Before the field extraction, the payload may provide scalar fields
only. The extracted local has one definition and must die at the final write.
The parent, its tracked aliases and the original payload cannot be observed
between extraction and replacement. The signed index cannot change, and the
read and write must use the same checked negative-index normalization.

The existing closed-region CFG proof requires every continuing edge to reach
the replacement, with no external entry. Returns, escaping breaks/continues and
error-result propagation keep the transfer. The payload prologue additionally
rejects alternate branch and fallthrough entries. Runtime trap behavior and
private storage remain unchanged. Intermediate mutations may still allocate;
live roots and the existing collection uniqueness checks remain in force.

## Validation

- Full gate: 93/93 steps, 2116 main tests; QBE 428/428, build 29/29,
  format 2/2. Guardian 88 checks pass with no ratchet growth.
- Focused COW suite: 28/28 tests. Structural IL checks prove the selected
  transfer disappears while an observing case retains a transfer.
- Twenty permanent guest probes pass on QBE and LLVM with native GC stress.
  Coverage includes outer snapshots, earlier match/iteration borrows, readonly
  and mutable parameter aliases, parent/payload observations, early return,
  break/continue, index changes, parent growth, surviving temporaries, ordinary
  local parents and an allocating closed loop.
- Independent review reran eight adversarial guest probes on each backend with
  GC stress, all passing.
- [All 44 switch-off IL comparisons](d9-indexed-return-off-il.json) compile
  successfully and are byte-identical to exact `60b668cf`.

The frozen Debug compiler SHA-256 is
`6e82c879fdeb5a8c1cb337291f444e4a32027ddddaf18b7f61aba4aeaeae3993`,
built on `f6b5de09`. The Lox setter-helper source and its paired performance
evidence are a separate change. Final acceptance requires the complete joined
43-workload run; this compiler validation does not claim that acceptance.
