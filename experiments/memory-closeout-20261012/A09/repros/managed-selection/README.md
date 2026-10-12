# Managed selection refuses before the explicit copy

Support6 source revision `5167c588`, compiler SHA-256
`bc6432a75fc1fa0dbcbd2048a5c8dbe2909d7590e90ae729688ed4f6e69978d4`,
rejects seven managed selections with `E_SINGLE_OWNER_MOVED` naming a hidden
`<collection>` local. This is a current support blocker, not an intentional
ownership boundary or a completed fix. No production file was edited.

The nine-case matrix contains list min/max with a borrowed text-list parameter
and explicit `.copy()`, min of a fresh text list followed by `.copy()`, two-text
min/max with `.copy()`, optional-parameter `unwrap_or(...).copy()`, the original
optional iteration/concatenation shape, integer min and integer unwrap_or. The
seven managed cases refuse; both scalar controls pass. Ordinary `dump-typed`
succeeds for all nine, pinning the generated source shape without an ownership
check. These are source/typed diagnostics, not native or timing qualification.

## Same-container selection

In `prelude_builtins.zig::extremeOfList`, hidden result `%4` initially borrows
`owner[0]`, then may be assigned `owner[i]` in the loop. Both loans root in the
same list. `single_owner.zig::merge` at Support6 line851 nonetheless makes the
result unavailable when `view_definition` differs. The loop exit then makes the
final read of `%4` fail before the enclosing explicit `.copy()` can execute.

`list-extrema-proposed.patch` is an exact, **unapplied and unqualified** alternative
for the frontend owner: carry a scalar selected index, compare `owner[best]`
against `owner[i]`, and read the chosen element only at the end. Keep an initial
index-zero read to retain the empty-list trap and its source location. The patch
applies cleanly to the pinned source. It does not relax ownership joins, add
copies, or change source syntax. `list-extrema-proposed.json` lists required
source/native/negative qualification; scalar and float semantics still require
regression coverage. `min_scalar_index_reference.my` is a diagnostic reference
for that lowering, not a proposed user-source migration. Its Support6 checked
source validation passes with status0; no production-patch/native qualification
is inferred from that control.

An alternative checker fix must preserve the exact-slot/provenance guards:
ignoring a changed `view_definition` without clearing invalid reconstruction
information would weaken the recently added parent-slot checks. No general
join relaxation is proposed here.

## Different possible parents

Two-text min/max initializes its hidden result from `a` then conditionally
rebinds it from `b`. `Option.unwrap_or` joins a borrowed Some payload and its
eagerly evaluated fallback. Those joins have different roots, not merely two
read sites of one root. They need separate source and Core lifetime treatment.
The list-index patch does not fix them.

Patch request to the coordinator/ownership owner: represent the generated
selection's possible borrowed parents soundly and keep all of them available
through reads and argument evaluation until the selected value is copied or its
last borrow ends. Keep managed returns/stores requiring independent ownership,
resource boundaries and stored/escaping view refusals. Do not replace the joined
root with `none` and call the result an owner: a call such as
`consume(min(a, b), mutate(mut a))` must still reject the overlapping borrow.
Preserve eager fallback evaluation, left-to-right two-argument evaluation, first
selection on equality and empty-list traps. Passing source checks is insufficient;
IR borrow cleanup, emitted ABI and counted native early/error paths must agree.

No caller workaround, public-export removal, default promotion or performance
claim is included in this evidence. The existing release-inventory failures stay
open until the owning implementation is integrated and qualified.


The ordinary Core dump contains a borrowed string loop phi and replacement phi
for list selection, and a payload-versus-fallback string phi for the optional.
Those raw dumps are archived as diagnostics only. Their ordinary-mode copy and
cleanup behavior is not a checked-runtime control. The followup admission waited
321 seconds behind an external DL timing window; that delay is neither compiler
time nor guest performance. A09 did not hold a timing lease.
