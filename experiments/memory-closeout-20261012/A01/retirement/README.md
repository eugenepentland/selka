# A01 retirement draft — not applied or qualified

This reviewable patch is prepared against the file identities in source-identities.json.
It is not part of the active implementation and does not complete retirement. Apply
only after the coordinator authorizes the post-C2 retirement stage, reconcile runtime
owner changes, then compile and run the full affected matrices.

The patch removes task-runtime RC/share/count alternatives and makes the old public
submit/result/close bridge functions private implementation details. Owned capture
transfer, take-once results, mandatory joins and pending-work synchronization remain.
The parallel library comment is updated to describe the single supported behavior.

Legacy scheduler fixtures are migrated without losing their scheduling checks:
million submissions, deep tree/chain recursion, own-deque waits, lazy startup,
budget/frame sequential restrictions, forbidden fork/batch, and discarded outputs.
Legacy escaping/double-read task handles are explicitly retired; the checked
replacement tests independent transferred result survival and refusal of a second take.

The emitted-IR fixture draft uses explicit list/text copies for independent mixed
capture snapshots, owned submit/take/end contracts and no escaping task-handle list.
Its existing output, fastcc bridge, trap source location and current-item diagnostics
remain asserted. These draft edits have not been compiled or tested.

Original files are stored as deterministic gzip snapshots, preserving exact bytes
and keeping archival RC code separate from active source inventories. The patch
contains all proposed changes; no original fixture or test is silently deleted.

After application: run the existing scheduler/emitted-task/zero-RC suites, the new
A01 owned million-submit checks, the source map matrix using ordinary commands,
ThreadSanitizer and structural runtime/LLVM/symbol audits. Final C3 verification
and installed-component qualification remain the coordinator's responsibility.
