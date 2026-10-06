# S3 Wave A review: S3-0 and D2

Status: **Wave A complete; stopped for the user's review go on Wave B.**
S3-0 and S3-L are committed and merged, with all package and merge gates green.
Wave B has not started. This is the Wave A review record; the S3 exit report in
plan §7 remains due after Waves B/C/X.

## Scope and commits

Integration branch: `codex/new-core-s3-integration`, created from the exact
requested S2 base `92590700cb0bf5e4dc19cc1f0c836c3a41693f64`.

| Change | Commit |
|---|---|
| User's amended rebuild rule | `427f2f25266ae4f8fa6e3e30dfe10c301e4ce901` |
| Approved S3-0 source/design | `dc1a583109be06c3e699a433be24cbcd6e5d3816` |
| S3-0 qualification | `643858e3da7b1e3a2c4f31b1a13430ab3906cd0e` |
| S3-0 integration merge | `e39ad11d3b2d95d537b1526f7e4abfb4b0feeb76` |
| S3-L source/qualification | `225bee07da44dc57ae322d3b6c1f0f68aebb404f` |
| S3-L integration merge | `f5ba28e585a7c06cb80dc6c81b96fa946c55ad2a` |

Both packages use separate locked worktrees. The original dirty checkout and
the protected runtime baseline remain untouched. No branch was pushed and
nothing was merged into `main`.

## Approved design and frozen IR

[`docs/design/new-core-s3.md`](../../../docs/design/new-core-s3.md) covers all
nine required areas: capabilities/resources/extern, bytes and blobs, number
text, remaining text methods, generics, standard-library imports, the test
runner, numeric operations/facts, and recursive equality/aggregate operators.

The S3-0 foundation adds three counted pointer leaves (`byte_buffer`,
`capability`, `resource`) without changing existing compound type IDs. Nine
operations are appended without renumbering existing operations:

| Shape | Operations |
|---|---|
| Mutable bytes | `buffer_new`, `buffer_copy`, `buffer_set`, `buffer_push`, `buffer_pop` |
| Integer operations | `shift_left`, `shift_right`, `saturating_add` |
| Float operations | `float_unary`, selecting sqrt/floor/ceil/trunc/abs/sin/cos |

Runtime helpers use `runtime_c` linkage, which passes capability tokens;
source `extern_c` retains its existing Host-erasing scalar contract. The
verifier, layout, ownership/COW handling and dispatch cover the new shapes.
Fourteen hand-built IR tests cover every new operation, malformed signatures
and selectors, capability passage versus extern erasure, managed layouts and
verified COW. New operation emitters fail closed until their Wave B owner
implements them. No runtime feature is admitted merely because its IR exists.

`src/core/ir.zig` is frozen at S3-0 source commit `dc1a5831`; its diff against
the combined source merge `f5ba28e5` is empty. Record phis retain
their ownership. Fresh/copy buffer uniqueness has verify assertions; no new
scalar fact is assumed by a stub. The runtime uses the new core's own objects,
with legacy algorithms serving as the porting reference.

Float text will use a port of the old formatter's Zig algorithm. In S3-T2,
measure the cold first-program build cost of its Zig runtime unit separately
and cache the object by all helper content hashes, Zig version and relevant
target/build options. This is a binding Wave B obligation.

## D2 and the review corrections

The shared checker rejects stored dictionary projections with `E_VIEW_STORED`.
Direct iteration/comprehensions and immediate `len`, `in`, `list`, `set` and
`sorted` remain legal. Snapshot suggestions preserve the exact projected
expression. Inferred bindings and list literals receive structured fixes;
declarations requiring a type/API migration receive the diagnostic and
suggestion. Builtin identity prevents user-defined names from being mistaken
for dictionary views; `DictItem` remains an ordinary storable value.

The resumed package implements all five requested corrections:

1. Keys membership and `not in` use the dictionary hash-membership operation;
   the checked-tree test requires contains operations with no generated loop.
   Values/items membership scan entries without allocating a snapshot.
2. The inline-take `held` and plain-record `Held` fixtures and their assertions
   are deleted. They are not converted to list fixtures. Other now-unreachable
   stored-view declaration cases are retired while unrelated defensive RC
   checks remain.
3. The python-core snapshot fixture expects `item_total == 33`.
4. Parameter, return, record-field and collection-element view annotations
   fail at the declaration in ordinary and unused generic checking, including
   nested/phantom arguments and zero-length arrays.
5. Immediate-consumer nodes are indexed once per check and reused by generic
   checking. Each view validation performs a table lookup.

Tests formerly using stored views now use explicit snapshots or rejection
checks. Four original stored-view modules are archived under
`test/fixtures/view-storage/`; `language/converted-tests.txt` retains all 35
former test names. Three stored-view SPEC rules are retired. Their unreachable
old-compiler machinery may remain until S5. Two core-builder refusal tests
now expect the shared checker's `SourceError`, before core lowering, with no
core refusal substituted for the D2 error.

Read-only projection audits found no stored views in examples, benchmarks or
the inspected external Lox checkout. The additional explicit-annotation audit
also found no view-type names in those corpora; its unavailable secondary Lox
path is recorded as historical evidence only. No external checkout was edited.

## Qualification

Every repeated command uses a fresh log. Core rebuild timings below exclude
build-slot admission and other-build contention. The core measurement holds
all build slots and the gate lock to exclude a concurrently running gate.
Old-compiler rebuilds are not subject to the amended ten-second core budget.

| Check | S3-0 package | S3-L package | Final integration |
|---|---|---|---|
| Uncontended core rebuild | source rebuild 1.67 s | 1.58 s | 1.67 s |
| Held eight-shard core suite | 219/219, 79.19 s; longest shard 76.35 s | 205/205, 74.17 s; longest shard 72.37 s | 219/219, 68.31 s; longest shard 66.81 s |
| Full debug/release conformance | each 1224 matching, 0 mismatching, 316 unsupported | each 1243 matching, 0 mismatching, 275 unsupported | each 1243 matching, 0 mismatching, 275 unsupported; 132.77 s |
| Strict leak/fact-verify conformance | same counts, no failures | same D2 counts, exit/stdout/leak/verify checks pass | package sweeps plus merge checks |
| Own-feature strict fuzz | S0: 50 cases, 750 comparisons, no failures | dict: 50 cases, 750 comparisons, no failures | package evidence |
| Complete emitted-definition identity | all 35 unchanged from `92590700` | coordinator-owned final check | all 35 unchanged; exit 0, 8.36 s |
| Full old-core gate | S3-L owns shared-change gate | all four steps green | qualified package plus merge checks |
| Guardian | 88/88 | 88/88 at package commit | 88/88 at both merge checks/commits |

The initial four-shard S3-0 suite passed in 126.81 s but exceeded the roughly
90-second shard guideline. The eight-shard package rerun resolves this; no
budget was relaxed. Shard RSS is checked separately from the runner's green
verdict because an overrun can leave a build step green.

S3-L's largest old-gate step, `zig build test`, passes 115/115 steps with
3001 tests in 951.61 s; build-slot admission is excluded. `test-qbe` passes
51/51 steps and 519/519 tests in 84.14 s. `test-qbe-build` passes 29/29 steps
in 3.00 s and `fmt-check` passes 2/2 in 0.23 s. The old gate's duration is not
the new core's five-minute edit-loop budget. The strict dictionary fuzz run
also checks 1000 native executions and
24 matching trap comparisons, with no rejection, refusal or execution failure.

After the S3-0 merge at `e39ad11d`, all required merge checks passed:
uncontended core rebuild 2.91 s, held eight-shard suite 219/219 in 76.94 s,
and debug/release conformance each 1224 matching, 0 mismatching, 316 unsupported.
The full Guardian scan passed 88/88. Complete records are in
[`integration/after-s3-0-run01/summary.json`](integration/after-s3-0-run01/summary.json).
After the S3-L merge at `f5ba28e5`, the required merge checks also passed:
uncontended core rebuild 1.67 s, held eight-shard suite 219/219 in 68.31 s,
and debug/release conformance each 1243 matching, 0 mismatching, 275 unsupported
of 1518. The longest core shard is 66.81 s; the maximum reported shard RSS is
`201M`, below the unchanged 2.5 GiB ceiling. No RSS-overrun notice is present.
The source remained at that merge commit for every check. The full command,
time, exit and RSS validation record is in
[`integration/after-s3-l-run01/summary.json`](integration/after-s3-l-run01/summary.json).
The final identity log is
[`integration/code-identity-final-run01.txt`](integration/code-identity-final-run01.txt).
This proves the 35 rows' complete emitted function definitions are unchanged;
no new benchmark timing or S3-X performance-table claim is made here.

The initial migration failures and the superseded rebuild hold remain labeled
in the package evidence. The resumed core run that expected a stored view to
reach lowering failed 204/205; its fixture was changed to expect D2's earlier
`SourceError`, then the corrected 205-test run passed. A compound Guardian
commit workflow was canceled during its redundant test phase; it did not
commit anything. The final package and merge commits use ordinary Git with
the required whole-tree 88-check hook enabled.

## Coverage and remaining limits

Base checked coverage is 3185/3627 accepted function names. The D2 package's
checked scan accepts 3213/3595, with all four corpus child processes successful;
no stored-dictionary-view refusal remains. Only the language corpus changes:
46 names are removed (6 previously accepted), 14 names are added (all accepted),
and 20 existing refused names are now accepted. No accepted name becomes
refused. Thus the accepted count rises by 28 while the total falls by 32.
The final integration scan confirms the same 3213/3595 result in 3.69 s,
with every corpus child exiting 0. All 382 remaining refused names are accounted
for by the complete reason table in
[`integration/remaining-coverage-refusals-final-run01.md`](integration/remaining-coverage-refusals-final-run01.md).
The exact removed, added, admitted and regressed name lists are in
[`integration/coverage-name-delta-final-run01.json`](integration/coverage-name-delta-final-run01.json).
Raw corpus outputs and checked child statuses remain in
[`integration/coverage-final-run01/summary.json`](integration/coverage-final-run01/summary.json).

Conformance counts test cases separately from coverage's functions/helpers.
The archived modules' 35 runtime cases become 12 snapshot cases; one immediate
membership test is added. The active conformance total therefore changes from
1540 to 1518, with matching cases rising by 19 and unsupported falling by 41.
These changes are recorded by name in the package evidence, not treated as
execution of the retired view protocol.

Runtime capabilities/I/O, mutable byte source lowering, the remaining text and
numeric methods, float text, generic admissions and application workloads are
still assigned to Waves B/C. The final 40-row measurements, full 200-case fuzz
matrix and S3 exit qualification remain S3-X work. User modules/interfaces and
incremental per-module compilation remain S4. Arenas remain retired. No
persisted format shape is changed in Wave A; the consumer index is transient
per-check state.

## Evidence and review boundary

- [`s3-0/README.md`](s3-0/README.md): approved source commit and qualification commands/results.
- [`language/README.md`](language/README.md): D2 source commit, migrations, full old gate and strict qualification.
- [`integration/`](integration/): command logs, exact merge commits, timings and RSS validation.
- [`STOP.md`](STOP.md): superseded rebuild hold and its historical evidence.

Both package merges and their gates are complete. **Stop here for the user's
go on Wave B.** The plan's §7 S3 exit report and later S4 go/stop decision remain
required after Waves B/C/X.
