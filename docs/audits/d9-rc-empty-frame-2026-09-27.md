# Bounded omission of empty ownership-frame linkage

The experimental RC emitter can now omit its ownership-frame link, normal
cleanup scan and unlink when a bounded physical proof establishes that every
local journal entry stays empty. The ordinary emitter remains active. It still
reserves and initializes the four private entries used by `advance`, and retains
native/logical frame admission, instruction-budget checks, failure traces and
the caller's active pin scope. GC lowering is unchanged.

This slice starts from joined `7d68202d59cf834bf9649fd77df2000f548ffec9`, including
the empty-local, unused receiver-scope and scalar replacement changes. It does
not generalize ordinary-owned local roots or change RC uniqueness.

## Proof and defensive checks

`qbe_rc_empty_frame.zig` runs after the finalized physical loop and empty-local
proofs. Initial admission requires one stable mutable list parameter whose
logical elements have neither counted nor unique-drop edges, and otherwise
plain scalar parameters and a plain scalar result. The exact existing
`stableMutParameter` predicate proves the caller has detached and pinned that
payload for the activation and that the parameter is never rebound.

All other managed locals require the existing explicit `emptyLocal` certificate.
Every managed operand is an unguarded load immediately consumed by one of those
certified stores, without an intervening branch target or semantic publication.
The remaining instruction whitelist admits plain arithmetic/control flow,
plain record projections, direct scalar record replacements, and proved inert
list reads/writes. The replacement check matches the actual no-pending-token
arm: a nonzero inline plain base and nonzero scalar plain updated fields.

Unknown instructions, calls/callbacks, alternate borrowed entries, entry points,
by-reference or caller-storage locals, managed results/construction, pattern
bindings, parameter rebinding, arena transitions, semantic sharing and pending
receiver scopes decline the proof. Implicit COW sites are audited separately:
no field or loop detachment, capture/share event, or runtime unique installation
is admitted. Only the existing no-op stable parameter check is allowed. Code
and local counts are each bounded at 4096; operand-state inspection is limited
to 262,144 cells. Uncertain functions keep the complete protocol.

A separate journal `unlinked` fact controls only runtime linkage. It never sets
`state.active = false`, never changes semantic ownership, and never aliases a
missing entry. All existing private entry/address/guard assumptions remain.
`initialized(true)`, scope begin and runtime uniqueness publication refuse with
`InternalError` if reached after certification. The explicit runtime
unique-field refusal is tested before address/helper emission, as are generic
publication and scope refusal. Clear-only stores remain legal.

In `advance`, the parameter guard begins clear, every read receiver is already
certified empty, and the scalar replacement change removed all nine pending
guard publications. Internal scratch is only cleared. Thus the four remaining
entries never contain O, H, LOAN or unique-drop obligations. `sqrt`'s scalar
helper neither allocates nor calls guest code; cold checked conversions, bounds,
overflow and budget failures preserve ordinary trace/unwind behavior.

## Lifetime and heap-frame boundaries

No scope is created in an admitted body. The caller's mut-argument scope stays
linked throughout return and failure. An empty `frame_cleanup` would neither
drop a value nor close a scope: its scope-unwind loop is empty and every guard
is zero. Removing it therefore does not move a finalizer/drain boundary.

The proof is independent of native-versus-heap lowering. All conservative frame
byte estimates and storage remain, so a retry cannot add unaccounted storage.
A dedicated plain record containing `[1024]int` forces `edit` onto a 706,480-byte
heap execution frame while retaining the certificate. Its normal and bounds
failure paths are checked before/after on both backends. `frame_allocations` is
a separate runtime ownership chain: the existing frame-release path frees it
normally, and the runtime's longjmp teardown releases the chain on traps. RC
owner counts do not measure those raw frame blocks; the unchanged allocation/
release emission and runtime chain are part of this boundary audit.

## Full unchanged nbody measurement

Both compilers are Debug builds. Guests use QBE ReleaseFast or LLVM O3/full LTO;
all measurements use CPU10 and three runs per binary, with exact stdout checked.

| Backend | Before instructions | After instructions | After / before |
| --- | ---: | ---: | ---: |
| QBE | 63,085,261,939 | 62,150,260,991 | 0.985179 |
| LLVM | 16,660,251,024 | 13,710,248,694 | 0.822932 |

All four counted executions have identical physical counters: two allocations
and retirements, O acquire/release 1/3, H acquire/release 10,000,005 each, zero
clone shells, and 10,000,007 uniqueness checks. No owner/hold count limits fire.
This is a matched component improvement, not Stage 4 acceptance.

Before compiler SHA256:
`7decd168a86694b21d9c69eda88f7097a351e161b033c18c8270225129460b48`.
After compiler SHA256:
`c165923d2a5c5fe974f8849fe3ee3cf10607206c734c1b003f00f876115ba043`.

## Validation

Focused structural/refusal tests pass 16/16 (five named and eleven imported
blocks); the broader `RC ` filter passes 65/65. The structural tests retain all
four private slots, physical admission and checked bounds, and reject rebind,
callback, arena, managed-return, reference, pattern, H iterator and unique input
cases. The existing empty-local tests now explicitly check their composition
with the stronger complete-body certificate.

The permanent guest `rc_empty_frames.my` covers caller snapshots, negative
indices, older receivers called within arenas, arena-owned callers and callback
fallback. Nine uncached guest suites pass 320 assertions and four expected
bounds traps across RC/GC-stress and both actual backends. Paired standalone
validation passes 32 executions from 28 builds: normal snapshot/arena, bounds,
overflow, step, logical frame, physical stack floor, and heap-frame normal/trap.
All statuses, stdout and source traces match exactly. Counts match exactly
except for the LLVM physical-floor case described next.

The physical-floor run retains R_FRAME_LIMIT and complete cleanup, but LLVM
reduces the recursive caller's machine stack reservation from 504 to 264 bytes
(the common saved-register prefix remains). More activations fit before the
native floor: H acquisitions/releases increase from 149,562 to 261,732, still
balanced; all other counters match. The mapped guest stack is independent of
the host RLIMIT_STACK set by the driver. Logical frame and step-limit tests
retain identical complete counters and traces. The initial overstrict physical
count-equality assertion is preserved separately; `verify.py` checks the
recorded boundary explicitly without rerunning or discarding any execution.

The root integration agent owns the cumulative full gate. This branch runs
focused checks, formatting and the whole 88-check Guardian gate.

Evidence: [experiments/d9-rc-empty-frame-20260927](../../experiments/d9-rc-empty-frame-20260927/README.md).
