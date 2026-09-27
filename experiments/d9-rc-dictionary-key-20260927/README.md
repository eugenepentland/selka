# Dictionary key lifetime evidence

Run `python3 experiments/d9-rc-dictionary-key-20260927/verify.py` from any checkout.
The verifier uses the archived receipts; it performs no build or measurement.
See the [report](../../docs/audits/d9-rc-dictionary-key-2026-09-27.md) for proof,
limits, identities and the preserved GC stress timeout.

`identity.json` identifies the matched Debug compilers, source and production
files. JSON receipts retain exact commands, backend manifests, binary hashes,
stdout, stderr and raw perf strings. Accepted GC hashes come from the unchanged
formal baseline archive. The `.ssa.gz` and `.asm.gz` files retain both emitted
and linked-main checks. `controls-initial-partial.json.gz` and the timeout log
preserve the unsuccessful extra stress probe; they are not passing controls.

The Python drivers are the original scratch drivers, with paths relative to
the compiler worktree. They document reproduction commands rather than acting
as portable CI tests. `controls.py` resumes its existing receipt. Do not rerun a
timing driver without assigning a private CPU and fresh output/cache paths.
Compiler binaries and guest native binaries remain in their immutable scratch
prefixes listed in the receipts; they are deliberately not duplicated here.

The initial guest matrix used ten key assertions. The final matrix adds the
preowned-key/backedge negative and reruns all eleven key assertions in each of
four runtime/backend combinations. Combining the latest key runs with the
unchanged other three guest files gives 152 current assertions. The archived
initial 148 and final 44 runs are both retained.
