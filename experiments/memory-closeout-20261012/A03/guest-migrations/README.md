# Transferred guest migrations

The coordinator transferred A01's 36 reserved guest files to A03 after the C0
census. The base is `fbfcaa7a923186a8e773c3760f81c10aa345a432`; the exact incoming
patch and original/transferred hashes are retained here. The public test names,
signatures, expected constants, and assertions remain coverage requirements.
The source migration is additional work, separate from the 81-case census.

Assignments now move managed owners. Independent snapshots, inserted managed
dictionary keys reused later, and owned returns from borrowed parameters use
`.copy()`. Immediate `list(mapping.keys()/values()/items())` snapshots retain
their existing source API; manual comprehension rewrites were reverted once
the compiler gained the matching owned-snapshot contract. Scalar projections
remain borrowed reads and do not copy whole records to hide compiler refusals.

Some legacy tests implicitly saved a selected child while later call arguments
replaced its owner. Their migrated positives now evaluate the selected index,
copy the selected child, evaluate the replacement, and call the helper on that
independent owner. This changes the source ownership contract and explicitly
sequences the old observation order. An unchanged output does **not** prove
unchanged borrowing behavior or establish a compiler-only performance gain.
`src/core/a03_migration_boundaries_test.zig` retains nine negative borrow/write cases:
direct child/root overlap in both argument orders, indirect borrowed and mutable
child/root replacement, direct and indirect record-field invalidation, and
indirect dictionary-entry replacement, and a nested same-root mutable call.
Mutable argument loans last through the enclosing call, so the last case uses
explicit local staging even when the inner mutation currently touches only a
scalar. Mutation during dictionary iteration is also rejected; migrated
positives take a key snapshot and read the current value at each iteration.
This preserves the observed replacement order without keeping a view across
mutation. They all require
`E_SINGLE_OWNER_OVERLAP`. A positive snapshot case executes in debug and verified
release and audits emitted LLVM for RC operations.

The historical `gc_generations.length` cursor loop becomes a recursive borrowed
traversal, bounded to 201 nodes in these fixtures. Its algorithm and stack usage
changed; it is not an allocation or runtime speedup claim. `gc_footprint.total`
uses nested borrowed matches with the same absent-child behavior. Historical
collector-oriented test names remain identifiers, not descriptions of the new
runtime.

`guest-migrations.py` mirrors the complete test tree, preserves all test bodies,
renames any existing main only in the mirror, and appends a main invoking every
public zero-argument Boolean `test_*` in source order. Files containing only
helpers get a no-capability main for source checks. The runner records exact
source and derived-source hashes, compiler hash/revision, output, counters,
LLVM/symbol audits, and every refusal. It owns bounded shared build admission;
do not wrap it in another build-slot command. This combined run supplements
the registered guest-test runner; it does not replace the complete gate.

Review and qualification results are recorded alongside this document as they
become available. Compiler defects in legitimate in-place writes, optional
narrowing, and borrowed iteration must remain visible and be fixed by their
owners; removing the failing assertions or copying away those operations would
not qualify them.

The interim support2 compiler is revision
`245e892f8518943ee44a0cc6009ab4b4fa6bca43`, binary SHA-256
`3e9f7f2cd7e1ff7dc13b342dc812cb64b340cddc02b8b2b4b1ae8008cb203c7c`.
Its source sweep admitted 22/36 files and retained all 14 failures. After local
copy fixes, the native release subset built and ran 21/24 files containing 118
Boolean tests: all outputs matched, all RC counters were zero, no managed blocks
remained at exit, and LLVM/symbol audits passed. These are intermediate results;
per-row hashes and archived source mirrors identify the exact tested versions.
Later edits do not relabel these results as a completed full migration.

Three native failures remain in that subset: an interior dictionary mutable
argument needs ownership lowering, aggregate formatting requests an unaudited
render helper, and a managed-string destructuring swap is refused even with
explicit copied operands. A07 owns ownership/lowering investigation; A04 owns
the aggregate render audit. The source-only failures additionally preserve
nested writes, distinct mutable collection places, dictionary-item iteration,
fresh-value projections, and optional narrowing reproducers. The coordinator
has fixed the recorded scalar dictionary-snapshot compiler panic; it still
requires rechecking on the next integrated artifact.

Five registered boundary tests pass on this worktree: nine negative sources
and a positive snapshot source executed in debug and verified release. The
complete log is `boundaries-focused.log`. This focused result supplements the
required complete final gate. `qualification.json` and `review-identities.json`
record the source burden and unchanged 356 public test signatures.

The support3 native retest was stopped at a safe admission boundary after 30
completed build attempts (31 file records, the last without a mode result).
Successful source lowering reached a shared native-link `FileNotFound` defect;
there were no successful executions. `migration-support3-runtime.json.gz` keeps
every completed failure and its exact compiler identity. The coordinator/A01
repaired the object-lifetime issue in support4. The harness now stops at the
first non-diagnostic compiler/tool failure and supports `SIGUSR1` checkpoints
after completed lanes, preserving evidence and avoiding repeated infrastructure
failures. Minimal support2 ownership/lowering reproducers and their diagnostics
are archived separately; none were copied away to force admission.

After that exploratory result, the coordinator retained conservative whole-root
exclusivity for calls with multiple mutable children. General path-disjointness
analysis is outside this closeout. Two dict key0/key2 calls (including reordered
named arguments) and one row0/row1 call now copy child owners, call once, and write
back in source argument order. Their callees see an independent snapshot or fresh
arguments, never the parent root; no alias-index semantics are changed. The
original same-root list and dictionary calls remain explicit negative regressions,
and a positive case verifies each index is evaluated once, named argument order,
independent snapshots, and cleanup. This source update adds six explicit copies
and 15 added/3 removed lines relative to the first migration commit. It preserves
all public test signatures and return assertions; it is not an allocation saving.
`distinct-child-review.json` records the exact source identities.

The following Support4 exploratory results are archived in `support4-summary.json`:
36 assigned files, 30 attempted, 18 admitted/executed files containing 109 Boolean
tests, 11 source/lowering refusals, one compiler panic and six unmeasured files.
All executed files matched output/exit and had RC0, zero managed exit-live and
clean LLVM/symbol audits. The first 26 files use the earlier source snapshot; the
next four use the explicit distinct-child update, with exact per-row hashes.
The tail stopped on the first compiler failure: `providerStore` inspected a
resolved `Ref.none`. A07/coordinator identified a shared guard fix. The remaining
six files were not silently treated as passes; broad Support4 sweeps were paused
until the corrected integrated compiler.

The expanded boundary suite passes all seven registered tests: 11 negative
sources plus two positives executed in both debug and verified release, with
native managed-leak checks and emitted LLVM RC audits. The earlier run passed
all negative groups but both native positives hit the known C0 driver staging
defect. The coordinator authorized the already-integrated driver dependency
locally; the rerun then exited0 with7/7. The local duplicate driver commit
`90ce40266e589598a6e98ac9a2c88ec26e0cb233` must not be integrated again. Exact
test-source/test-runner identities and logs are retained in
`boundaries-distinct-qualification.json` and `boundaries-distinct-focused.log`.
A redundant queued CLI positive run was cancelled before admission, without
starting a compiler, when broad Support4 sweeps paused; its cancellation receipt
remains visible and it is not counted as a qualification run.
