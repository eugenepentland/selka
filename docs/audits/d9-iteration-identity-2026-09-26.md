# Managed iteration identity correction

Frozen integration `743fea73` silently accepted structural mutation of the
collection being iterated. The existing GC dictionary and set trap tests, and
one QBE golden case, expected `R_LIST_ITERATION_MUTATION` and instead returned
success. Independent counted RC execution of the same dictionary and set
programs also returned success and recorded one clone.

The [callback capture correction](d9-read-callback-captures-2026-09-26.md)
marked all read-only compiler receiver temporaries as GC snapshots. That
incorrectly included the hidden iteration source. RC separately stored that
source as an ordinary owner, so the next mutation detached from it. Keeping the
header alive and taking an independent value snapshot are different operations
here.

The correction identifies hidden iteration owners by their `iteration_check`
receiver. GC excludes those owners from callback-read sharing. RC acquires a
hold before releasing the incoming operand owner, then publishes that hold in
the existing guarded journal. Loads and moves retain the held role; publication
into an ordinary named binding still acquires an independent owner. Rebinding
the original variable keeps the selected iteration header alive. A preexisting
named snapshot continues to make a later write detach, as in the accepted GC
behavior. No runtime ABI or mutation check changes.

This covers lists, dictionaries, sets, bytes and text. Fixed arrays have no
managed iteration guard and retain their existing value-copy semantics. The
scalar/nested receiver-loan proof declines `iteration_check` and temporary
roots; it cannot replace these holds with unanchored loans. Broadening
`holds.mayHold` also keeps the immediate-owner proof conservative for collection
types that can occupy held iterator slots. Operand/pending journal addresses
remain `%rcsN` and `%rcwork`, compatible with the stable-metadata optimization.

The permanent positive fixture is
[iteration_identity.my](../../tests/lang/iteration_identity.my); the focused
emission tests are in [qbe_rc_views_test.zig](../../src/qbe_rc_views_test.zig).
The reproduction driver is
[run.py](../../experiments/d9-iteration-identity-20260926/run.py). Its actual
LLVM commands use `--backend llvm --llvm-opt 3 --lto` without `--qbe`, and GC
executables run with collection stress.

Validation: all 36 native executions passed across actual QBE/LLVM and GC/RC.
They comprise seven trap forms (dictionary, set, list, pinned list with
`continue`, reversed, zip and comprehension), seven iteration assertions and
ten existing callback-snapshot assertions in every runtime/backend pair:
28 expected traps and 68 positive assertions. Every counted RC execution had
balanced O/H and allocated/retired totals. The minimal dictionary now records
zero clones, four allocations/retirements and five matched holds, then traps.
[Archived commands, hashes, output and counters](../../experiments/d9-iteration-identity-20260926/results.json.gz)
identify the frozen Debug compiler used for every execution.

Both original failing GC unit tests pass (12/12 each including unconditional
harness blocks); the new focused iteration tests pass 13/13 (two named).
The Debug compiler install passes 12/12 and Guardian passes all 88 checks.
Zig formatting and `git diff --check` pass. The parent integration owns the
full gate and broader RC replay of trap goldens; these focused runs are not
WP-4 acceptance.
