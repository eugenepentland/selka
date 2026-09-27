# Record-field snapshot evidence

Run `python3 experiments/d9-record-field-snapshots-20260927/verify.py` from any
checkout containing this archive. It reads no external binaries or caches.

`identity.json` identifies the unchanged corrected Debug compiler, its preserved
installation files, source base and exact patch, and every receipt artifact.
The large binaries remain at their recorded isolated-worktree paths. JSON and
logs are compressed without timestamp variation; the copied drivers preserve the
original commands and paths rather than pretending to be portable build tools.

`baseline-*` receipts intentionally retain failures. Frozen prior GC fails the
heap and arena reducer; prior RC fails the arena reducer but physical heap owners
mask its missing semantic share. The prior and scalar-record compiler each fail
all four arena configurations. These negatives are not acceptance passes.

The corrected `guests` and `controls` receipts contain 188 standalone Boolean
assertion executions, including 24 formatting-only repeats, and exact printed
reducers. `traps` contains 16 expected failures with balanced RC cleanup. Both
actual backends are recorded in manifests. See the audit report for scope,
analysis proof and the still-separate parent integration gate.
