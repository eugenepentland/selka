# Combined collection and numeric body schema 9

This merge combines committed numeric producer `3e0bed229` with parser producer
`c55770b19`, preserving ROOT `653ae191d` graph optimizations. It also applies the
exact committed native set-key snapshot donor
`5a18be34b5daec06c0025d3c0c904924912fb576`. No structural recipe or schema-10
contract is introduced.

The source is stable and reviewable. Qualification of the final combined host
is still pending. All 473 selected producer pure tests passed normally; the
release lane is running separately for every module with fact/leak checks.
Exact per-file public test counts are required. The installed pre-donor combined
package passed both B9 366-operation lanes and 35/168 supplemental comparisons.
These passing pre-donor receipts do not substitute for the final combined-host
replay. The corrected 27 authentic hostile refusals also passed on schema 9.

The earlier B8 34/246 replay failed at operation 200, `set_comprehension.my`,
because this native foundation lacked `5a18be34b`'s canonical set-key snapshot
validator. Both failed lanes are archived; the genuine host is being rebuilt
with that donor for a complete replay. No authenticated capture header is
rewritten. Private B8 harness rollover changes only the required package/frame
schema and the hostile inventory's schema field; immutable source fixtures and
all native comparisons remain intact.

The complete pure inventory found a record-closure helper regression: an extra
float identity scan required full record names from intentionally minimal helper
catalogs. The checker now passes its already authenticated float identity into
closure, preserving the helper's existing default input contract. All six
record-type tests passed after the fix. Source success is still checked against
the native oracle and host validators.

Two stale native B9 tests now assert schema-9 behavior: canonical u32 list
descriptors are retained and validated; same-width u64 multiplication validates,
while mixed i64/u64 operands remain rejected. Their native coverage is pending
in this branch. The tests carry the numeric specification tag.

The two earlier unbounded directory pure-test attempts were interrupted by
`earlyoom`, which recorded RSS of 16874 MiB and 15613 MiB before sending SIGTERM.
The journal is archived. The established gate runs each sorted `*tests.my`
module separately, with the same special profile/index budgets, all seven
boundaries in reference mode, the unchanged qualified seed, zero cached/skipped
checks and exact declared test counts. This bounded inventory passed normally
and is the release run now in progress.

[The archived receipt](evidence/selka-body-combined9-20261011/receipt.json)
contains the source snapshot, failed and passing intermediate receipts and
native/harness donor identities. Final combined-host verdicts will follow in an
evidence commit. The dictionary generator-pair extension remains an explicit
profile refusal awaiting structural recipe authority; the strict ten-case
extension corpus remains pending. Compiler bootstrap, full language/backend
coverage, production activation and the 1.5x performance goal are outstanding.
