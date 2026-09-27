# Closed field ownership transfer in RC

A bounded compiler certificate now moves the existing owner of a direct list
field into its mutation local, then restores the field through ordinary
storeback. In the Lox object setter this removes an artificial second owner
which previously forced a whole object-table clone on every mutation. Runtime
uniqueness, semantic sharing, pins, descriptor traversal and allocation remain
unchanged.

This is a WP-4 optimization with focused correctness evidence. Reduced N4/N5
measurements are diagnostics, not substitutes for the unchanged mandated N10
workload or the full acceptance corpus. The accepted GC baseline is untouched.

## Physical certificate

`rc_field_transfer.zig` exports exact source-local, field-index, moved type,
target-local, extraction, local-store, writeback and final-commit positions.
It does not infer movement from the semantic copy-elision booleans. The initial
slice accepts only a direct list field of an inline, writable caller-owned
record parameter, a named local, a straight interval of plain argument setup
and direct mutable calls, and the complete ordinary field-storeback sequence.
There must be no branch target inside the sequence, no early exit, no arena
transition, no use of the source while empty, and no use of any writeback alias
after commit. A source redirected by the move planner is refused. Already-live
aliases of the source are refused. Other parameters must be plain numeric data.

The callee can allocate, detach the list, or trap. It receives only the moved
list and plain arguments: exactly one mutable whole-list operand, no second
managed operand or mutable parameter, no indirect function/callback or host/C
entry, and a plain result. A bounded reachability traversal rejects callable,
opaque/host handle, capability, cell, live-view or unique/resource authority
inside the moved value. Semantic type recursion is visited once with fixed
workspace; proof-size/work limits decline the optimization. An inaccessible
sealed capability sibling in the source record does not grant root authority
to the callee; this is why Lox's `Runtime.clock` is permitted. Source records
containing live views or unique finalization are independently refused.

The initial root load is a raw borrowed read of caller-owned inline storage,
with an empty operand stack. Its ordinary projection therefore has no live
operand obligation to replace. Emitted-IL tests assert no preceding retain or
loan call and retain the runtime uniqueness/frame calls. The handoff writes
the projected pointer into operand zero's stable storage, clears the actual
source field to null, then publishes that operand's typed ordinary guard. These
instructions cannot call, allocate or trap. Header sharing/pin bits are never
modified. A null list pointer is a valid empty cleanup representation.

The ordinary local store consumes this guarded operand and releases an already
initialized target exactly once. During the mutation, the local journal owns
the one moved token. A caller snapshot still has its own owner, so existing
uniqueness correctly detaches; this change never suppresses a real O>1 or pin
check. A failure leaves a null source field plus the existing guarded local or
operand, so frame unwind releases exactly one owner. Caller arenas retain their
normal region and scope behavior.

Successful ordinary storeback prepares and owns the replacement before the
certificate drops the now-dead target. The caller-storage store has already
called `myl_rc_native_drop` on the counted inline root, which drains queued work,
then blits the replacement and clears pending ownership without a callback.
Thus the dead-target drop does not move an unrelated pending finalizer across
a new callback boundary; reentrant draining remains deferred by the same runtime
guard. Unique/finalizer-bearing values are excluded. The second-extraction
regression verifies that no artificial local owner survives the first commit.

## Evidence and identities

The base is the real two-parent join `19232b8a`, including frozen integration
`7d68202d59cf834bf9649fd77df2000f548ffec9`. Its immutable Debug compiler is
`install-scope-scalar/bin/mylang`, SHA-256
`7decd168a86694b21d9c69eda88f7097a351e161b033c18c8270225129460b48`.

The measured prototype Debug compiler is SHA-256
`b75bd0541dc27d503672857a0c2c000f490efecba0480fe8e45cd7c1f9036694`.
The final compiler, adding conservative source/role/authority refusals, is
SHA-256 `50e8fce3df6ef293d933a75f338eca4dd7d49c3a9038d7fbbefc83a33a564d69`.
All four final Lox binaries (normal/counting, QBE/LLVM) are byte-identical to
the measured prototype binaries. Final N4/N5 runs repeat their exact counters.
The experiment archive records the final source patch, compiler and guest identities,
actual backend manifests, commands, full stdout/stderr, counters and perf output.
All LLVM builds explicitly use `--backend=llvm --llvm-opt=3 --lto`.

The unchanged Lox port and reduced scripts are the inputs archived in the
[preceding clone audit](../../experiments/d9-rc-lox-clone-audit-20260927/README.md).
Uncounted retired instructions are median-of-three on CPU 3; counted binaries
are separate. Each reduced process has a 15-second deadline.

| Backend | Input | Before instructions | After instructions | After / before |
| --- | --- | ---: | ---: | ---: |
| QBE | N4 | 11,512,993,153 | 4,356,188,137 | 0.37837 |
| QBE | N5 | 36,549,333,786 | 8,536,894,296 | 0.23357 |
| LLVM | N4 | 10,386,561,486 | 3,707,916,044 | 0.35699 |
| LLVM | N5 | 33,364,171,143 | 7,257,850,884 | 0.21753 |

Both actual backends have identical counts and exact matching output:

| Counter | N4 before | N4 after | N5 before | N5 after |
| --- | ---: | ---: | ---: | ---: |
| Clone shells | 9,745 | 5,401 | 18,451 | 9,755 |
| Heap allocations = retirements | 103,577 | 94,889 | 203,635 | 186,243 |
| Owner acquisitions | 3,817,632 | 1,299,390 | 12,320,013 | 2,547,995 |
| Owner releases | 3,921,209 | 1,394,279 | 12,523,648 | 2,734,238 |
| Hold acquisitions = releases | 3,118,545 | 3,105,513 | 6,152,191 | 6,126,103 |
| Uniqueness checks | 101,193 | 101,193 | 183,917 | 183,917 |

Owner acquisitions plus heap allocations equal owner releases throughout.
Neither counter saturation nor owner/hold refusal occurs. Remaining clones and
visitor costs are not claimed to be eliminated.

## Validation

- Focused Zig tests: 14/14 (three named tests and 11 unconditional imports),
  including complete physical proof/refusal, unchanged GC lowering and a native
  counted normal/trap/arena/budget driver.
- Nine standalone language assertions in GC stress and counted RC, on actual
  QBE and LLVM: 36/36. They cover snapshots, repeated and initialized-target
  extractions, early return, observed source, aliases, caller arenas, nested
  fallback and a source containing a live dictionary view. RC counts agree:
  80 allocations/retirements, O35+80=115 and H81 pairs.
- Twelve standalone failure controls: heap and caller-arena bounds traps plus
  allocation refusal, in both runtimes/backends. Exact output and trap codes
  match. Every RC execution balances allocation, owner and hold counts. The
  budget failure occurs inside the called mutator before storeback, with a
  caller snapshot still alive.
- Four additional first-detachment refusal controls use a 40,001-element
  caller snapshot under a 1 MiB budget. Both backends/runtimes trap with
  `R_MEMORY_BUDGET` after the entry marker. RC creates no successful clone shell
  and balances 12 allocations/retirements, O2+12=14 and H5 pairs.
- All 88 Guardian checks pass; no ratchet or baseline changed. The first test
  draft used illegal `list[Clock]` and was replaced with a legal list of
  callables to test reachable-authority refusal. A duplicate primary spec tag
  was corrected to `spec-case` before the green build.

The parent integration owns the joined full gate and language sweeps. This
slice does not claim they have run against the final joined source.

## Unchanged mandated N10 check

The exact existing `binary_trees.tree.lox` at N10 and complete expected output
are archived with hashes. Neither source nor expected output was adjusted. All
four final runs finish within the independent 120-second process deadline.
The counting and uncounted variants each match the complete expected output.

| Actual backend | Counted wall seconds | Uncounted wall seconds | Uncounted instructions |
| --- | ---: | ---: | ---: |
| QBE | 75.383 | 74.317 | 1,047,374,421,072 |
| LLVM | 67.508 | 61.960 | 890,662,688,180 |

These are single feasibility runs, not median acceptance measurements. Both
counted runs report exactly 22,906,609 allocations/retirements, 311,200,831 owner
acquisitions and 334,107,440 releases, 755,074,858 hold pairs, 1,095,889 clone
shells and 20,836,964 uniqueness checks; no saturation or count refusal occurs.
The remaining cost is substantial. The historical baseline N10 timeout was not
repeated or converted into an invented speedup.
