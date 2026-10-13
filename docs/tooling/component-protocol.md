# Component protocol v1

The first operation is `test-index-v1`, implemented by
`selfhost/components/test_index/main.my`. Invoke the built executable as
`COMPONENT --request FILE`. It reads at most 16 MiB plus one sentinel byte from
one immutable binary file, validates the entire request, and writes one framed
binary reply to stdout. A failure exits nonzero and diagnoses on stderr. No
success frame precedes validation or computation. The native host captures both
streams, applies timeout and output limits, and accepts a reply only after zero
exit and complete frame validation. There is no stdin or persistent-worker
protocol in this version.

All integers are unsigned little-endian. Counts and graph IDs are u32. The
header is exactly 64 bytes; payload lengths exclude it.

| Byte offset | Width | Meaning |
| --- | --- | --- |
| 0 | 8 | ASCII magic `SLKIDX01` |
| 8 | 4 | Envelope protocol version, exactly 1 |
| 12 | 4 | Operation schema `test-index-v1`, exactly 1 |
| 16 | 4 | Message kind: 0 request, 1 reply |
| 20 | 4 | Exact payload byte length |
| 24 | 8 | Request ID, echoed unchanged |
| 32 | 32 | Snapshot identity bytes, echoed unchanged |

The magic assigns the component/operation family; this version has no extra
operation tag. The schema version is independent of the envelope version and
component implementation digest. The host validates the selected executable
against its artifact manifest separately. Request IDs and snapshot bytes are
opaque to the component, including zero bytes and high-bit bytes.

The request payload is `node_count`, `test_count`, `test_count` function IDs,
then `node_count` adjacency lists. Each list starts with its edge count followed
by that many callee function IDs. Node IDs range from zero to `node_count - 1`.
Test IDs preserve discovery order and duplicates. Function names remain on the
native host; integer IDs have meaning only within this snapshot.

The reply payload is `node_count`, then one direct list and one reached list
for each node in node order. Each list starts with its count followed by test
function IDs. For each discovered test occurrence, every direct callee edge
adds that test to the callee's direct list, preserving repeated edges. Every
reachable node adds the test once to its reached list, including the test root.
Cycles terminate. Repeated test occurrences contribute repeatedly. Both list
orders follow test discovery order. The pure graph implementation assumes
validated graph IDs; the codec enforces this boundary.

Limits are 100,000 nodes, 100,000 test occurrences, 1,000,000 total adjacency
edges, 16,777,216 request bytes and 67,108,864 reply bytes, including headers.
The component checks the response budget while collecting results, before a
large result can be fully accumulated. The codec rejects unknown versions and
message kinds, bad magic, invalid indices, truncated counts or lists,
inconsistent payload length, oversize frames and trailing bytes. It consumes
exactly one frame; concatenated frames are invalid. No recursive nesting exists.

The empty request golden frame consists of the header with payload length 8,
followed by two zero u32 counts. Its reply has kind 1, payload length 4 and one
zero u32 node count. `tests.my:test_empty_protocol_golden` pins these octets and
uses all-255 identity bytes to cover unsigned identity echo. Host boundary tests
also exercise the native process and malformed frames. Run the pure library and
codec tests with `mylang test selfhost/components/test_index/tests.my --force`.

## Core cache planner v1

`selfhost/components/cache_plan/main.my` supports the legacy `cache-plan-v1`
exchange below and the incremental v2 exchange described in the next section.
Its installed manifest now declares protocol/schema 2. The
coordinator builds it independently with the same qualified seed and installs
`cache-plan` and `cache-plan.json` beside `test-index`. The host retains Core IR
canonicalization and graph extraction, including both calls and function
references. This graph is separate from the informational test-index graph.
Publication is atomic for each component manifest. The two components are
independently versioned; their installation is not one atomic bundle.
Fresh component builds use a private Zig global cache as well as private
compiler staging. The pinned Zig's cached libc startup objects can retain
debug paths from the working directory where they were first built; borrowing
the caller's global cache made otherwise identical rebuilds differ in their
debug sections. The private cache removes that dependency on caller cache
history. Every build, whatever its key and whichever worktree runs it,
compiles in one staging directory, `<component store>/staging/component`, with
its temporary and Zig local cache directories inside it; the builder lock
serializes its use. The seed embeds those paths in the debug sections, so a
key-named or caller-named directory would make otherwise identical builds
differ. The resolved component store root is part of the build identity,
because those debug paths still depend on it. Reproducibility checks compare
the complete executable bytes within that declared build context.

The build identity (format 3) names the builder by a location-free
`coordinator` record rather than the digest of the `selka-components`
executable, whose own debug information names the worktree that compiled it:
`sources_sha256` hashes the builder's source closure, embedded when it is
compiled (`selfhost/component_builder_identity.zig` lists it, and
`zig build test-component-support` fails when a builder source imports a file
the list omits), beside the Zig version, optimize mode, backend and target.
Worktrees at the same commit sharing one component store therefore select the
same key and install byte-identical executables and manifests.

The planner uses the same 64-byte envelope, with magic `SLKCP001`, protocol 1
and schema 1. The host sets the snapshot to SHA-256 of the complete request
payload and checks both the request ID and snapshot in the reply. IDs are local
to that immutable request and have no persistent meaning.

The request payload contains, in order:

1. Three u32 policy codes: computation `pure = 0`, retention `disposable = 0`,
   admission `success_only = 0`. Other codes are refused.
2. u32 node count and u32 batch count.
3. Each node's 32-byte canonical function digest, u32 edge count and edge IDs.
4. Each batch's u32 root count and ordered root IDs.

The reply payload contains the u32 batch count, then each batch's u32 nonroot
count and nonroot IDs. Traversal marks every root before following edges. It
returns every other reachable node once, sorted by unsigned digest bytes and
then node ID. Equal digests on distinct nodes remain distinct entries. Cycles
terminate, duplicate edges do not duplicate nodes, and batches are independent.

The Zig host contributes root digests in their original order, including
duplicates, then the existing little-endian u64 nonroot count and sorted
nonroot digests to the test key. This preserves the established reachable-IR
contribution. Planner identity is an additional settings dependency, so old
receipts are deliberately invalidated once when this contract is introduced.

The identities have separate purposes:

| Identity | Meaning in Wave 1 |
| --- | --- |
| Operation | `cache-plan-v1`, its schema and the declared pure/disposable policy |
| Producer | Verified planner binary digest, or the explicit host algorithm revision, plus execution mode |
| Snapshot | Complete immutable graph and ordered batch inputs; replies also echo a per-request correlation ID |
| Reusable computation | Existing test settings, canonical reachable IR, test roots/schema, source location and tracked inputs, now including producer identity |
| Receipt | Existing checksummed successful-result evidence under that computation key; whole-report replay additionally validates its dependency manifest |
| Execution occurrence | Reserved future application run/step identity; never inferred from a content hash or compiler receipt |

The component computes closures only. Zig decides receipt eligibility, verifies
stored evidence, executes tests and publishes successful results. Source,
toolchain and planner checks around publication prevent a result from being
presented as current after an observed input change. No graph IDs escape their
snapshot, and no component reply by itself asserts that a test passed.

Limits are 100,000 nodes, 100,000 batches, 1,000,000 total edges, 1,000,000 total
root occurrences, 16 MiB request and 64 MiB reply (including headers). A batch
request is also limited to 16,000,000 units of traversal work: each visited node
and each examined edge counts, including duplicate edges and repeated work in
different batches. Both the reference and Selka implementations refuse work
beyond that bound. Exceeding a bound is a command failure, never permission to
skip tests. The host rejects out-of-range, duplicate, root-containing or
noncanonical reply lists. Shadow mode additionally checks the exact closure.

`MYLANG_CACHE_PLAN_MODE` selects `component` (default), `reference` (explicit
host execution), or `shadow` (component plus exact reference comparison).
`MYLANG_COMPONENT_DIR` overrides deployment discovery. The host binds mode,
schema and verified implementation digest before test receipt lookup, including
directory tickets and whole-report replay, and revalidates before accepting
replay or publishing results. It runs a private executable snapshot whose digest
matches that binding. On the supported Linux host, the snapshot is a sealed
memory file: writes and size changes are prohibited before launch, and the host
holds its descriptor until the child has finished. This avoids the `ETXTBSY`
race where a concurrent fork briefly inherits a disk executable's writable
descriptor. The process has a 30-second deadline, bounded stdout and
stderr, and is killed and reaped on timeout. Component failure has no automatic
reference fallback.

`mylang test --json` adds a `cache` object to each verdict with `action`,
`reason`, `key`, `component`, `key_method` and optional `work` and
`execution_key`. `component` identifies the bound planner, including its mode.
Typical reasons are `no-success-receipt`, `receipt-hit`, `whole-receipt-hit`,
`whole-report-hit`, `exec-receipt-hit`, `whole-exec-receipt-hit`,
`shared-receipt-hit`, `force`, `native-links` and `live-effects`; fact
verification and leak checking are keyed modes, not refusals. Whole-report reuse reports the current reuse
decision rather than replaying the earlier execution reason. This explains
admission to existing test caches; it does not yet report every compiler stage
or schedule the entire toolchain.

The policy types reserve separate content identity and run/step occurrence
identity, disposable and durable retention, cache publication and durable
checkpoint commit, and pure recomputation versus effect replay/idempotency/
reconciliation. Wave 1 explicitly refuses the unsupported policies. It provides
no application journal, crash recovery or exactly-once external effects.

`zig build test-components` qualifies both components using the pinned seed,
forced pure tests, native debug/release builds and independent protocol oracles.
The host protocol/identity tests and Core edited-program receipt tests run in
`zig build test`. Python is used by qualification drivers only; source install
and installed compiler commands remain Python-free.

## Incremental Core cache planner v2

The envelope is 64 bytes with magic `SLKCP002`, protocol 2 and schema 2.
Correlation and policy codes retain the v1 meaning. The request payload is:

1. Three u32 policy codes, then a 32-byte ordered-topology digest.
2. u32 node, batch and changed-node counts, then u32 `has_prior` (0 or 1).
3. Each node's 32-byte canonical digest and counted u32 outgoing-edge list.
4. Each batch's u32 candidate flag and counted ordered u32 root list.
5. The changed node IDs, as u32 values.
6. When present, the prior 32-byte topology digest, one u32 group representative
   per node, and each node's counted u32 reverse-edge list.

The reply begins with seven u64 work counters: index nodes, index edges,
affected nodes, closure nodes, closure edges, reused tests and planned tests.
It then contains u32 node/batch counts, one u32 group representative per node,
counted reverse-edge lists, and each batch's u32 reuse flag plus counted nonroot
list. A reused batch has an empty list; Zig uses its already validated exact
key. A newly planned batch retains the v1 canonical key contribution.

Zig admits an entire prior graph generation before sending candidates. It binds
each old key to its test envelope, compares complete logical edges and canonical
digests, and remaps identities into current IDs. A topology change discards old
numeric indexes. Selka propagates changes through the current reverse graph and
shares closure work among recursive groups. Retained groups must be strongly
connected in both directions with an acyclic quotient; an invalid partition is
recomputed. The Zig shadow algorithm independently uses Tarjan grouping and
per-test traversal, and shadow key checks use fresh complete lowering.

Limits remain 100,000 nodes/batches and 1,000,000 edges/root occurrences. Requests
may occupy 32 MiB, replies 64 MiB, and aggregate index, propagation and closure
work is limited to 64,000,000 operations. There is one batch exchange per
provider group, with no resident process or persistent numeric handle. The
current complete graph is still validated and transmitted. Version 1 remains
available for the conservative full-lowering path.

The manifest version, schema, mode and verified artifact bind every early test
replay path. Only `cache-plan` changes to v2; `test-index` remains v1. Facts and
graph chunks are disposable metadata in source-specific packed stores beneath
`<cache>/test-keys`; their presence never certifies a passing test. Lost metadata
recomputes. The current-invocation `cache.work` report appears once per provider
group and is omitted on whole-report replay; see
[guest test work reporting](guest-tests.md#reusing-unaffected-results).
