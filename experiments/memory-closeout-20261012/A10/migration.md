# Checked ownership migration

Status: command support is under qualification; ordinary defaults and legacy RC
retirement have not been applied. During this stage use
`--experimental-zero-rc` on build, run, run-project, check, dump-ir, test,
check-project, check-module, check-session, lint, cost, coverage and doctest.
The latter analysis paths are covered by the command-stage followup evidence;
the final integration must rerun them against its exact compiler.

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
cleanup. Keep early/error exits inside that scope. A returned dependent owner
must remain anchored to one unambiguous input provider; the checker rejects a
dependent owner escaping a local provider or an ambiguous provider choice.
Qualification of these narrow resource rules belongs to the integrated candidate.

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

Allocation diagnostics use the selected ownership contract too. Borrowing a local
view does not allocate managed storage; converting owned text to independent bytes
and reversing a byte buffer can allocate. Explicit `.copy()` remains an allocation
under a `noalloc` ceiling. An invalid move in a `noalloc` helper is rejected before
allocation analysis lowers that helper, including unused functions and cached test
commands.

The component packaging boundary remains separate: the historical seed manifest
is unchanged. The optional reviewed component-compiler route still needs a real
qualified compiler pin and component protocol/ABI results before it replaces the
installed legacy route. There is no claim that the installed package is RC-free.

Mutable child arguments use exclusivity at the root container. A single call with
multiple mutable children from the same list or dictionary is conservatively
refused even for different constant indices. Where the function only observes the
children, an explicit migration can copy each selected child, call with those
independent owners, then write the updated children back in source argument order.
Evaluate index expressions once and preserve named-argument evaluation order.
This is an explicit source transformation, not a guarantee of general path
independence; code that observes a root alias needs separate reasoning.
