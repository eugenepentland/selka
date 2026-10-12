# Checked ownership migration

Status: command support is under qualification; ordinary defaults and legacy RC
retirement have not been applied. During this stage use
`--experimental-zero-rc` on build, run, run-project, check, dump-ir and test.

Assignments and returns move an owner. Keep reading a value through ordinary
parameters; make `value.copy()` when both independent values must outlive a move.
For example, replace `const backup = values` with `const backup = values.copy()`
when later code updates or reads both lists. Copies recursively duplicate managed
children. Do not add copies to read-only arguments.

Named `match` payloads borrow. Return a copied selected child, or match directly
on a fresh producing call to transfer its payload once. Immediate whole-field
patterns split that fresh payload; arbitrary partial moves from an ordinary record
are outside the current contract. Text/byte `.borrow(start, end)` produces an
immutable local view; `.copy()` materializes its independently owned contents.
Owner mutation, movement, replacement and view escape are diagnosed.

`parallel.map(values, function)` borrows input elements, preserves order and joins
before returning an independent owned output. It does not expose task handles.
Root capabilities own their providers and scoped resources borrow them through
cleanup. Keep early/error exits inside that scope; do not return a live file or
dependent capability.

The checked source rules apply to test functions, property inputs, providers and
directory workers. An ordinary RC test receipt cannot substitute for checked
ownership. Diagnose a source refusal before measuring; no fallback is provided.

Run this directory's `command_matrix.py` under shared build admission against a
complete installation for runnable positive/negative examples. Its fixtures
include explicit copies, borrowed generated arguments, Result success/error,
invalid use after a move, directory workers and cached receipts. The experiment
keeps the original fixture identity and exact compiler SHA-256 in each report.

Candidate memo/persistence migrations preserve snapshot independence through explicit
copies. `memo.message`, `persistent_memo.message` and `durable.message` now copy
borrowed dynamic error text into independent returned storage, so these calls may
allocate. Remove an old `effects()` narrowing when that allocation is needed; the
compiler derives the ordinary ceiling without a new annotation. Literal-only error
branches remain allocation-free.
`memo.call` copies stored keys/results and independently returned hits; callers must
copy a cache, pool or generator when both snapshots remain observable. These are
source/library changes, not compiler-only performance wins.
