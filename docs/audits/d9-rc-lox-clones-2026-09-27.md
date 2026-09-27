# Lox clone attribution and closed field extraction

The reduced Lox VM benchmark spends most of its sampled RC work cloning lists,
not recursive boxes. At N5, the object table accounts for 8,814 clone shells and
543,928,336 bytes of logical list contents. Only two of those requests have the
semantic `SHARED` bit set; 8,813 have more than one physical owner. The generated
setter introduces an extra owner while the original field remains owning. This
is the next mechanism to address before tuning the shape walker.

This is diagnostic evidence, not WP-4 performance acceptance. N4/N5 are bounded
reductions of the existing binary-trees Lox script, not replacements for the
required N10 corpus case. No production source changes accompany this report.
The accepted GC baseline and all existing binaries remain unchanged.

## Matched controls

The unchanged port and scripts are archived under
[the experiment](../../experiments/d9-rc-lox-clone-audit-20260927/README.md).
The production compiler is the Debug argv-corrected `66054aab`, SHA-256
`18a74046f8788f498af28c0f640c25b145fa8d28b50f2a4bece4b5debf8ef11e`.
Actual QBE and LLVM (`--backend=llvm --llvm-opt=3 --lto`) runs produce identical
stdout and identical counters within each runtime. The GC build uses
`MYLANG_COW_COUNTING=1`; the RC build uses `--rc-runtime=stats`. Each process has
its own 15-second deadline and process group. No timed-out process was retried
with an unbounded deadline.

| Diagnostic | N4 | N5 |
| --- | ---: | ---: |
| GC successful COW copies | 1,932 | 3,020 |
| GC copied bytes | 1,087,651 | 1,366,179 |
| GC pinned copies | 0 | 0 |
| RC clone shells | 9,745 | 18,451 |
| RC allocations = retirements | 103,577 | 203,635 |
| RC owner acquisitions | 3,817,632 | 12,320,013 |
| RC owner releases | 3,921,209 | 12,523,648 |
| RC hold acquisitions = releases | 3,118,545 | 6,152,191 |

All RC counts balance after the [argv correction](d9-rc-argv-ownership-2026-09-26.md).
The historical sampling artifact predates that correction and has its documented
constant four-allocation/six-owner exit gap. Its sampled VM behavior remains
useful attribution evidence, but it is not a clean shutdown acceptance result.

The GC copy counter and RC shell counter have different definitions. In
particular, one cannot assume an RC shell is a collection rather than a boxed
body. The separate diagnostic probe resolves that distinction below. GC copied
bytes and probe logical list extents also exclude different bookkeeping, so they
are not claims about equal allocator traffic or exact `memcpy` instruction bytes.

## Bounded diagnostic probe

Only the isolated diagnostic runtime changes: an archived patch to
`native_rc_transfer.c` records `schedule_clone` requests, successful shell
creation, memo reuse, and transaction completion or rollback. It uses 128 static
classification rows and 16 static active-operation records, with explicit
overflow counters. Hot hooks allocate no memory. Layout facts are snapshotted
while descriptors are alive; exit reporting never dereferences retired type
metadata. The counters distinguish committed shells from shells discarded when
the enclosing transfer fails. Commit here means successful clone transaction,
not a later guest store.

The probe has its own Debug compiler, bundled runtime and symbolic QBE binary.
Their SHA-256 values and the exact patch are in the experiment identities. The
probe is intentionally QBE-only; actual LLVM production counters above are
independently matched. Probe timing and instructions must never be used for
performance acceptance.

Both probe runs match every existing RC counter and the complete stdout of the
unmodified production run. Neither bounded table overflows. Every shell is a
list clone, and every shell commits: there are zero boxed-body or dictionary
header clones, rollback shells, memo reuses, pinned requests, or arena requests.
The immediate caller of every request is `clone_payload`; the probe does not
claim per-guest-callsite counts.

| List contents | N4 clones | N5 clones | N4 logical bytes | N5 logical bytes |
| --- | ---: | ---: | ---: | ---: |
| 56-byte `object.Obj` variant | 4,462 | 8,814 | 139,422,864 | 543,928,336 |
| 32-byte table entry record | 4,386 | 8,740 | 1,134,080 | 2,249,216 |
| All other list layouts | 897 | 897 | 809,434 | 809,434 |
| Total | 9,745 | 18,451 | 141,366,378 | 546,986,986 |

The Obj element descriptor is
`myl_t_a83873657e77deb1bf51281383ae925ccb1b4b6510284b93a36500031c0efc14`,
also used by the archived `set_object_field` IL. The source declares eleven
Obj cases, ten with payload metadata. The table entry descriptor is
`myl_t_6443eeba4e1a2dfcf7724374c49aee7d6088d8d2ed268a8e00cf676e7411a0da`.

Obj requests have `SHARED` set twice at each input size, but have O > 1 on
4,461/8,813 requests and a nonzero hold count on 4,436/8,788 requests. These are
marginal counters, not a joint-state histogram: at least 4,459/8,811 Obj requests
therefore have both O > 1 and `SHARED` clear. Holds do not enter uniqueness. The
size of the copied table grows with the workload, explaining why counting
shells alone understates the amplification.

## Source and generated-code mechanism

The unchanged source setter extracts `rt.objects` into the named local
`objects`, calls `set_object_field(mut objects, ...)`, then assigns `objects`
back to `rt.objects`. The existing semantic field-return proof suppresses the
source-level SHARE events for this closed sequence.

The archived GC outer setter loads the field directly into local `l5` and
checks its existing sharing state. In the RC outer setter:

1. Field projection creates a `LOAN` obligation (`rc-outer.il`, line 147).
2. Storing into named local `l5` goes through the non-owner path and calls
   `myl_rc_native_retain` (line 248).
3. It releases the loan and publishes an ordinary local owner (line 302).
4. `myl_qbe_rc_unique_local` (line 312) sees the extra O while the original
   field still owns its value. `myl_rc_unique` correctly refuses O > 1,
   regardless of whether `SHARED` is clear, and `unique_owned` clones.

No semantic history helper is emitted in this outer function. This is an extra
physical owner introduced by lowering, not evidence that uniqueness should
ignore live owners. Runtime uniqueness must remain unchanged: other live owners
can represent real snapshots. The sample's dominant guest call chain runs from
`heap::set_instance_field` through `unique_local`, `unique_owned`,
`clone_payload`, and the list shell/completion walkers. The probe establishes
payload and source-state totals; the IL independently establishes this concrete
cause. It does not attribute every clone to this single setter.

## Sampling limits and deferred runtime alternatives

The earlier uninstrumented QBE N5 sample reports about 51.7% self samples in
`walk`, 16.6% in `visit`, and 4.5% in descriptor lookup. Call chains include list
shell seeding and clone completion. Sampling recorded no lost samples but did
record substantial THROTTLE/UNTHROTTLE events. These are approximate hotspot
indications, not precise unbiased shares or an optimization gain estimate.
The original raw perf data, decoded samples and event statistics are preserved.

Inspection shows the walkers already traverse registered child shape pointers;
they do not perform a hash lookup at every child. Resolution still happens at
API boundaries and some per-element adapter calls. List shell creation seeds
its logical elements before completion seeds each slot again, and variant walks
scan inactive arms. Both are bounded runtime candidates, but reducing a
redundant O-driven full-table clone should precede optimizing the cost of that
clone. No walker patch has been made.

## Proposed next proof boundary

A compiler implementation should export an explicit physical certificate for a
closed field extraction and return, including source storage, exact field path,
local target, extraction point and all commit points. The current two semantic
`copy=false` booleans do not prove safe physical movement or establish cleanup
ownership. They must not be reused as sufficient physical authorization.

A conservative first implementation may transfer the field's owner to a guarded
local, clear the owning source slot, mutate the local, and transfer it back at
the certified commit. It must prove that no reachable read, callback, alias or
second mutable argument observes the temporarily cleared source. Every exit
must either restore the field or have the local journal perform the single
required unwind cleanup. Failure to prove this keeps the existing lowering.
An implementation may instead keep the root owner and use a certified mutable
place, but that needs equally explicit write-back and trap ownership; a plain
borrowed pointer is insufficient.

Required positive and negative controls include nested field paths, repeated
mutations, empty and nonempty lists, preexisting snapshots, live H views and
iteration observers, source rebinding, observed source between extraction and
commit, callback access, duplicate mutable arguments, early/error returns,
arena boundaries, count/allocation refusal and traps during the callee. The
first slice should exclude unique/finalized resources and uncertain roots.
Validation must preserve GC-visible history and compare both actual backends,
full output, owner/hold balance, clone counts and independent uninstrumented
instruction measurements. This report supplies evidence and a proof boundary;
it does not authorize loosening the value model or claim WP-4 completion.
