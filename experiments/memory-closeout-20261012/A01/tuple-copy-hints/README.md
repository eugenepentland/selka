# Tuple copy argument-hint repair

`hintBufferArguments` inspected `collection.kind == .list` and unconditionally
unwrapped `shape.buffer`. A tuple has the default kind but no element buffer,
so an admitted `pair.copy()` could panic before normal method checking. The fix
requires the receiver to satisfy `isCollection()` before applying element hints.
It changes no move, borrow, copy or Result obligation contract.

The exact managed tuple `.copy()`/unpack frontend regression passes. A tuple
carrying `Result[str, str]` can be copied when both obligations are explicitly
acknowledged; dropping the copied obligation still refuses with
`E_RESULT_UNHANDLED`. Existing Result-list and recursive symbolic obligation
checks also pass. The final focused invocation exited 0 with 11/11 tests passed
(four named matches and seven unconditional root blocks). `final.log.gz` preserves
its full output and command; admission wait is not test runtime.

Earlier test runs are retained. The first new pending-Result fixture used
`Result.ok(...)`, which is invalid constructor spelling and reported
`E_GENERIC_ARITY`. Correcting that fixture to contextual `Ok(...)` resolved the
failure; no compiler semantics were changed for it. Source hashes are recorded
in `source-identities.json`.

This frontend check does not substitute for native managed tuple independence
coverage owned by A06 or final integrated compiler qualification. A06 preserved
the original Support5 panic stacks in its guest-migrations/after-support5 report.
