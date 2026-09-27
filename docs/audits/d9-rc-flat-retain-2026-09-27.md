# D9 WP-4: bounded physical retain for admitted flat values

This runtime-only slice removes repeated native unique inspection, shape
resolution, seeding and generic traversal from physical retention of admitted
small values. It does not change semantic SHARE, pin cloning, ordinary/hold
roles, compiler emission, allocator policy or metadata ABI. Large records,
variants, held edges and typed boxes retain the original generic implementation.

## Proof and implementation

The parent and collections worker reviewed the
[proof](d9-rc-flat-retain-plan-2026-09-27.md); the worker then reviewed the concrete
`native_rc_values.c` diff without blockers. An already registered binding must
have the existing `flat.loanable` admission, nonzero size and disjoint storage.
That flag proves the native inline unique predicate false, at most eight
ordinary pointer leaves and depth within the generic transfer's eight local
frames. It conservatively refuses even NULL typed boxes. Existing plain-byte
retention remains unchanged ahead of the new dispatch.

The helper copies all bytes, clears owner offsets and acquires/publishes each
leaf in the original order. Every region check precedes acquisition. It retains
pinned identity and arena marks, acquires O rather than H, and does not import
loan's additional dynamic-finalizer prohibition: an opaque managed pointer to a
finalized payload remains legal where the original physical retain allowed it.
Later refusal releases exactly the published prefix through the existing
no-drain flat owner release, zeros the whole output, then drains once. Success
also drains once. Sticky status is recorded after callbacks, as before. No
binding is accessed after that callback boundary.

No bound is imposed on generic traversal or release. Cold metadata, deep/wide
layouts, zero size and non-disjoint storage use the existing path; this change
does not add an overlapping-storage contract. The same-address invariant remains
an internal error. No allocation, callback or hidden semantic transfer occurs
between the admitted copy and its final drain.

## Isolated measurements

Control is the joined `636524b81562e30285b15e297078fac24ffccb58` Debug compiler,
SHA256 `32e272cf75968d2fe913f636739d4b11d83701448e515f057dfa87f1ed8cba46`.
Candidate Debug compiler SHA256 is
`7f82f5c30b52ebedfdecec95747d619116d29e89396202aec7f4950ae506bd9f`.
The candidate's only production source change is `native_rc_values.c`.
All 128 emitted schematic functions and the entire emitted metadata JSON match
the control exactly. The admitted helper changes runtime work, not token traffic.

Actual QBE and LLVM O3/full-LTO binaries run on CPU2, alternating before/after
order over three repetitions. Inputs are the unchanged three schematic fixtures
and full Lox VM binary_trees N10. Counting binaries run separately and must match
the immutable control's complete counter records, in addition to exact outputs.

| Input | Backend | Before | After | After / before |
| --- | --- | ---: | ---: | ---: |
| schematic fixture | QBE | 551,272,085 | 348,470,636 | 0.632121 |
| schematic changed-net | QBE | 551,813,940 | 348,337,310 | 0.631259 |
| schematic changed-value | QBE | 549,669,244 | 348,557,125 | 0.634122 |
| Lox VM binary_trees N10 | QBE | 852,016,052,298 | 807,376,960,774 | 0.947608 |
| schematic fixture | LLVM | 428,809,780 | 252,857,663 | 0.589673 |
| schematic changed-net | LLVM | 431,663,756 | 254,287,367 | 0.589087 |
| schematic changed-value | LLVM | 428,790,865 | 252,298,155 | 0.588394 |
| Lox VM binary_trees N10 | LLVM | 712,500,946,714 | 670,575,444,017 | 0.941157 |

All 48 production samples report 100% counter running. All eight candidate
counting runs exactly match the complete control records, including allocation,
retirement, O/H, clone and uniqueness counters.

These improvements do not constitute WP-4 acceptance. The
[joined GC comparison](d9-rc-flat-borrow-joined-2026-09-27.md) remains the relevant
negative baseline evidence; this slice leaves the large Runtime record's generic
loans intact. The separate compiler lifetime/projection audit addresses those
operations.

## Protocol and integration evidence

The 42-case production history fixture and 14-case loan fixture pass against
both the unchanged 636 runtime and candidate with ASan, UBSan and counting.
Seven added history cases cover exact duplicate-limit prefix traffic, O=0/H>0
pinned acquisition, padding, heap/arena/literal/null mixtures, late and invalid
region refusal, callback visibility and order, reentrant metadata/allocation,
first-failure precedence, opaque finalized-pointer success, NULL typed-unique
rejection, same-address invariant rejection, cold metadata/budget refusal, zero
size, depth-nine transfer-stack refusal and nine-owner generic-width rollback.

The first handwritten wide fixture supplied array metadata with only `element`
and no native `fields` table. Both old and new runtimes crashed on that malformed
fixture in the existing native unique walker. Both raw failures and its source
are retained. The final fixture uses a nine-field record to test the intended
width refusal; no array metadata/runtime change was bundled into this slice.

Production sanitizer controls also pass for contract (22), collections (39),
arena (10), holds (12), execution/stats, codec and host lifecycle suites. The
focused Debug wrapper passes 12 tests. Sixteen actual paired guest rows cover
both compilers, both backends, GC stress and RC counting: the plain-retain and
broader runtime drivers execute 58 assertions per compiler/backend/mode, with
identical output and complete RC counter records. Guardian's 88 checks pass
during the Debug build; no ratchet or acceptance requirement changes.

Commands, compiler/binary/source hashes, manifests, individual samples, counter
stderr, old/new sanitizer receipts, rejected fixture evidence and emitted JSON
identity are in
[`experiments/d9-rc-flat-retain-20260927`](../../experiments/d9-rc-flat-retain-20260927/).
The validation driver reuses the preceding private `loan-validation` directory;
the permanent before/after receipts are archived separately here.
