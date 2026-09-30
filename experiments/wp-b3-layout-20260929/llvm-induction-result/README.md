# LLVM induction-result evidence

`receipt.json` identifies frozen source 178dad48, both installed tool hashes,
the actual float/VM/QBE code-shape checks, and the three excluded trials.
`raw-evidence.tar.gz` carries original and symbol-preserving float executables,
their allocated-section equality receipts, raw Callgrind data, source IR,
assembly, all 410 QBE unit comparisons, scripts, focused gate logs, trial source
patches and all 895 independently reviewed receipt members. Root and this lane
both verified those review hashes; neither claims a duplicate execution.
`manifest.json` inside the archive hashes every other member;
the archive was reopened and every member's size/hash verified before publication.

To inspect without using any shared cache, extract into a fresh owned scratch
directory and read `code-shape-receipt.json`, `float-attribution/inputs.json`,
`float-attribution/exact-counts.json` and `rejected-trials/receipt.json`.
The embedded scripts preserve their original absolute execution paths and exact
commands. Adapt only the owned output/cache paths for replay; keep the recorded
frozen inputs and compiler identities. QBE comparison scripts can run with the
recorded frozen installed QBE, or one rebuilt from the recorded source.

Simulated profiles diagnose instructions and block execution. They do not replace
root's dev/full instruction acceptance, smoke output/cap checks or final gate.
Rejected trials have their own namespaces and must not be treated as 178dad48
acceptance evidence. Old experimental compilers remain in their original owned
worktrees, with exact hashes recorded; the bundle does not duplicate those tools.
`followup-text-hints/` records read-only source/IR scope against the distinct cfee
and combined 5535 compilers. It is separate from the frozen 178 functional proofs
and makes no text execution or timing claim. Root's combined stage still fails
its full LLVM text row and is retained as a rejected performance checkpoint.
