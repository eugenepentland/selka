# Interior mutable dictionary argument diagnosis

This is a reproducible compiler blocker on Support6, not a language migration or
implemented fix. Production files are unchanged. The exact source/compiler hashes
and bounded admission receipts are in `summary.json`; complete argv, statuses and
wall durations excluding queue wait are in `inspection.json` and `reductions.json`.
No runtime speed, RSS, or five-mode qualification is claimed.

A03's frozen `mut_dictionary_arguments.my` is preserved as `original.my`, along
with its original build failure. All seven sources pass ownership `check`.
`child.my` reduces the problem to eight lines: update a dictionary reached through
`mut original[0]`. Its unoptimized native build refuses `E_ZERO_RC_LOWERING`.
`list-child.my` proves the same defect when the parent is a list. The eleven-line
`returned-child.my` retains the original call's independently copied managed result
and refuses both release and debug. `returned-list-child.my` also refuses release.
The same callee with a whole-root mutable argument (`returned-root.my`) builds and
runs in release, prints 7 twice, has RC0 and exit-live0, and passes LLVM/symbol audits.
Three `release_unique` sites are direct destruction and are deliberately not RC.

## Exact ownership path

In `original-dump-ir-facts.stdout`, b7 contains:

```text
%34 = dict_entry_value dict[i64, i64] %24, %27
retain %34
%35 = call record{dict[i64, dict[i64, i64]], dict[i64, i64]} clone_during(%34, %25)
...
%37 = record_get dict[i64, i64] %35, field1
%38 = dict_set_value dict[i64, dict[i64, i64]] %24, %27, %37
```

`callTarget` obtains the mutable child through `readPlace`, which emits an ordinary
borrowed `dict_entry_value` (or `list_get`). The callee's mutable parameter consumes
one owner. Ownership correctly inserts a retain because no transfer was represented.
`verifyLowered` correctly rejects that retain; suppressing the verifier is unsafe.
The source's explicit `source.copy()` is independent and is not the cause.

The smaller unit-return function is inlined in release. Its facts dump replaces
in-place mutation with `dict_copy` of the borrowed scalar child. That avoids a
retain in this particular dump but does not establish correct general mutable
argument ownership or no-copy behavior. Debug retains the call and exposes the
same refusal. A regression must cover both modes and a non-inlined managed result.

## Proposed owner patch and regression contract

A07 owns `src/core/build.zig`. Add a bounded zero-RC mutable-call preparation path,
analogous to `writableReceiverOf`, after source-order argument evaluation:

1. Capture each admitted stable interior path's parent references and selected
   children once. Mark owned indexed child transfers with `flags.place_read`.
2. Pass the final transferred child to the existing owned mutable parameter ABI.
3. Rebuild the saved parent path from the returned child, pairing reads and writes
   by exact parent/index references. This makes `flags.transferredSlot` suppress
   destruction of the already-transferred old slot.
4. Keep ordinary mode's existing capture/orphan semantics and zero-RC source overlap
   guards. Do not silently copy an ancestor or reinterpret a borrowed read globally.

Merely marking the final `readPlace` instruction is insufficient for a deeper path:
`storeInto` currently re-reads parent children and could manufacture a second owned
transfer. Reuse the saved path as `writeOwner` already does for receiver operations.
`arguments()` maintains the mutable root loan across later arguments; still test
source-order evaluation and refusal boundaries explicitly.

Expected registered coverage: original assertions unchanged; direct and callback
calls; unit and independently owned managed returns; dictionary/list parents;
managed children that grow or are replaced; deeper mixed dictionary/list/record
paths; empty/missing-key trap; source arguments evaluated once; early return; and
same-root overlapping argument refusal. All five native modes must preserve outputs,
RC0/live0, and structural absence of retain/is_unique/shallow managed COW copies.
No runtime/header helper is proposed. If implementation needs a shared declaration
or source-rule change, coordinate it with root rather than weakening the guard.

## Handoff

A07 and root received the reduced sources and exact Core diagnosis. Parent requested
read-only diagnosis, so this evidence does not contain a speculative production
patch. Preserve A03's historical inputs; rerun its exact fixture on the next frozen
compiler after the owner fix. Native binaries remain disposable under
`.tmp/memory-closeout/A02/mut-dictionary-diagnosis/`; the passing binary and LLVM
hashes are recorded in `summary.json`.
