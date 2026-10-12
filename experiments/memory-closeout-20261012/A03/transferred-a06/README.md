# Three transferred A06 migrations

The coordinator transferred these three source reservations from A06 to A03.
`C0/`, `prior-A06/`, `incoming/`, and `reviewed/` preserve each source stage;
`identities.json` records hashes, explicit-copy counts and changed lines. Original
oracles remain unchanged. This work is separate from the pinned 81+6 census.

Qualification uses Support6 source
`5167c588be79dd43d21d5013c36db15110bf239b`, compiler SHA-256
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`.
This intermediate Debug compiler has legacy Support5 installed components; these
results do not qualify the installed package or a final C1/C2/C3 candidate.

| Source | Explicit copies C0 / prior A06 / incoming / reviewed | Five-mode result |
| --- | --- | --- |
| `rc_owning_element_borrows.my` | 0 / 15 / 21 / 21 | All pass; eight Boolean tests per mode |
| `row_cow.my` | 0 / 17 / 31 / 58 | All pass; unchanged 57-line stdout |
| `v_nested.my` | 0 / 2 / 3 / 3 | All native builds refuse; source check admits |

The ten admitted executions match their frozen outputs, execute zero RC events,
leave zero managed bytes at exit, and pass emitted LLVM/linked-symbol audits.
Modes are release, unoptimized debug, verified release, optimized debug and
release without facts. Counts, peaks, commands, sources and exact binary hashes
are in `summary.json` and the three archived runs. Managed memory is not RSS;
these correctness executions are not runtime measurements.

The incoming `row_cow` first refused the borrowed child stored in `ke` at line
175. Its snapshots now use explicit copies. `row_s20` returns `xs[i].copy()` and
declares `managed_allocation`; its callback effect type declares the same
allocation. The coordinator approved this changed source contract. Effects are
not waived: independent storage really allocates. `shape_s21` now indexes the
current collection and copies that iteration's selected child before mutation.
This preserves the original per-iteration observations (`10 9`). Snapshotting
the whole iteration source would instead produce `4 9`. The original live
borrowed loop remains in the preserved sources, and registered borrow/mutation
negative coverage remains in `src/core/a03_migration_boundaries_test.zig`.

All public test signatures and Boolean return expressions are preserved. The
read-only/mutable argument test explicitly copies its read-only argument before
the mutable call. These migrations change ownership and allocation semantics;
unchanged output does not establish identical borrowing behavior or a
compiler-only performance improvement. From C0 the three sources together add
85 lines and remove 84, with 82 explicit copies. From the incoming transfer,
only `row_cow` changes: 30 added lines, 29 removed, and 27 additional copies.

`v_nested` is a compiler blocker owned by A07/coordinator (A02 informed). Every
native mode reports `E_ZERO_RC_LOWERING` at line 20,
`b.items[1].code = 77`, after nested payload assignment and append. The owner is
already an independent `b0.copy()`. No extra copy hides this legitimate in-place
write. `v-nested-repro/sequence.my` reduces the sequence to 17 lines and reproduces
the refusal in unoptimized native compilation. Its raw and facts Core dumps
succeed, so a successful dump is not evidence that native ownership lowering
passed. Original and reduced IR, exact commands and diagnostics are retained.
This defect is distinct from the pending interior mutable-call transfer fix.

Run the frozen reviewed sources through the harness, which owns bounded shared
build admission (do not add a build-slot wrapper):

```bash
source /home/epentland/.config/mylang/dev-env.sh
python3 -B experiments/memory-closeout-20261012/A03/assigned-migrations.py \
  --manifest experiments/memory-closeout-20261012/A03/transferred-a06/reviewed-manifest.json \
  --compiler /path/to/complete/install/bin/mylang --compiler-commit FULL_SHA \
  --zig "$ZIG" --output .tmp/memory-closeout/A03/transferred-a06-final
```

The incoming checks, accepted-source run and reviewed-row run retain all
failures. A separate empty `transferred-a06-copy-pass` temporary directory came
from an incorrect compiler path that failed before any compiler invocation; it
is a harness invocation error, not a language refusal. No historical report or
A06 checkout was modified. Final integrated qualification remains required.
