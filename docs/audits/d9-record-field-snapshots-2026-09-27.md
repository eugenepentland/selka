# Record-field snapshot correction — 2026-09-27

This is a correctness correction after the scalar-record performance slice
`6a75eb2a39686ccab91a981496f5520477abf34c`. That slice's evidence remains unchanged.
The failing snapshot is a **shared compiler-analysis defect**, with heap and arena
manifestations. It was already present in frozen integration
`468bd8e536b0e088ff71291cb9a3c92db8ebf448`; it is not caused by the scalar-record
RC optimization. Focused corrected executions pass; the parent integration gate
and Stage 4 acceptance remain separate requirements.

## Reproduction and applicability

```mylang
record State:
    values: list[int]

def main(out: Stream) -> int:
    with arena():
        state = State([12])
        saved = state
        state.values.append(14)
        out.print(saved.values)
        out.print(state.values)
    return 0
```

Expected output is `[12]` followed by `[12, 14]`. Prior output prints
`[12, 14]` twice, incorrectly changing the saved value. Removing the arena gives
the heap control. All observations below are native compiled CLI programs; there
is no interpreter result. QBE and actual LLVM (`--backend=llvm --llvm-opt=3 --lto`)
agree within each cell. GC runs use `--gc-stress`.

| Runtime | Prior heap control | Prior arena control | Corrected heap and arena |
| --- | --- | --- | --- |
| GC | Saved value changes incorrectly | Saved value changes incorrectly | Independent saved value |
| RC | Correct output; physical owners mask the missing mark | Saved value changes incorrectly | Independent saved value |

Frozen prior compiler SHA-256 is
`082edf36c3b1370debeccb4bdcbf3069fbf7829ad1852e8a7d0d5d7f2a34c67e`.
The scalar-record compiler
`ca907dc060c537aa9c527cbedab0494ad04c35828a14266a4a54e0ba6e345d52`
also reproduced all four arena failures. Those eight original before/after
receipts remain in
`experiments/d9-rc-plain-record-write-20260927/arena-minimal.json.gz`, with the
larger diagnostic and original failing assertion archived alongside them. The
new archive adds all four frozen-prior heap controls. It does not relabel any
historical failure as a pass or change the immutable accepted GC baseline.

## Cause and correction

The bytecode has a real `VALUE_COPY State assign` for `saved = state`.
Ownership analysis nevertheless classifies `saved` as borrowed and answers
`copy=false`. The hidden collection receiver for `state.values.append(...)` is
owned: field receivers deliberately do not use the ordinary path role.
`Context.writesTree` formerly followed only borrowed/path roles, so it could not
connect the collection mutation to `state`. Consequently it incorrectly proved
that the source record was never mutated while `saved` remained live. The
omitted sharing event explains both runtimes without changing native descriptor
tracing or arena uniqueness rules.

The correction changes only that write-origin query. A mutating buffer receiver
or uniquely loaded call argument may descend through known ordinary aliases and
through a compiler temporary with exactly one known source. A real named home
stops the temporary chain, as does a proven fresh value. Unknown/multiple/missing
source facts conservatively may write the queried root. The walk is bounded by
local count plus one; a cycle or exhausted walk also conservatively may write.
This adds no allocation, recursion, analysis field, ownership role, runtime API,
or native count operation. Existing through-path exclusions remain in place.

With the corrected query, the original snapshot is owned and its semantic copy
is retained; the field receiver remains owned. A real named copy such as
`copied = state.values; copied.append(14)` remains independent of `state`.
Read-only field access can still borrow. The correction restores the existing
language value contract instead of inventing an arena exception.

## Validation and immutable evidence

The corrected Debug compiler SHA-256 is
`4261318ea8a67676786f9488d9ca834e653177ee63c31b4c6fdd79b14475b790`.
Its source is the scalar-record commit plus the exact archived `source.patch.gz`.
The compiler and guest binaries remain in the isolated worktree's
`.tmp-arena-snapshot/`; the archive records every build command, backend manifest,
binary hash, output, status and counted RC receipt.

- Ownership-focused units: 47/47. Value-semantics units: 38/38. COW units: 17/17.
  These filtered totals each include the 11 common unnamed tests.
- The new permanent fixture covers heap and arena records, nested mut arguments,
  named copied homes, list/dictionary paths and loop receivers. The original
  failing arena assertion is restored permanently in `rc_plain_record_writes.my`.
- Each actual backend/runtime combination executes 41 distinct standalone
  assertions: eight new field snapshots, six scalar-record controls, nine closed
  field transfers, five recursive-box writebacks and thirteen semantic-history
  controls. Formatting-only final scalar-source confirmation repeats six of them
  in each combination. These are normal native programs, without test-harness
  accounting.
- The minimal arena, minimal heap and larger scalar/arena diagnostics produce
  exact corrected output in all four combinations.
- Sixteen field-receiver trap executions cover overflow, allocation budget,
  frame limit and step limit under both actual backends and both runtimes.
  Each prints only the pre-operation marker and reports its expected trap.
- Every counted RC normal and trap execution balances allocations/retirements,
  `owner_acquire + heap_allocate == owner_release`, and hold pairs, with no
  saturation. Backend counters agree. The minimal arena case now has one clone
  shell and five arena allocations, versus zero/three in the failing receipt.

The archive verifier checks these receipts and source identities. Whole-tree
Guardian passes all 88 checks; Zig/guest formatting passes and documentation
coverage reports zero failures. Their receipts are archived as well. The only
production change is the ownership-analysis query; this is not a runtime fast
path or a new performance acceptance result. Full Lox performance receipts in the
preceding commit still identify their original compiler and must not be read as
measurements of this later correctness revision.
