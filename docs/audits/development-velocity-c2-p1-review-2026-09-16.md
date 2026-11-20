# C1R / C2 / P1 completion review — 2026-09-16

## Verdict

C2's ordinary-body persistence and P1's unfinished-production workflow work in
the focused probes. This step still needs a corrective pass: four regressions
affect selective test reuse, repeated compilation, type compatibility/discovery,
and persistent-cache population. The broader claim that invalidation gaps are
closed is also premature.

Reviewed source: `codex/velocity-integration` at `6a99ef4b15470c3c1572ad8a37ea9a27f459e3ca`.
The changes after code gate `88691e7b3c5d6dea0a05e82ffadb375bd865981f` are documentation only.

The findings below were reproduced with a pinned copy of the existing executable
from the clean `final-debug` worktree at the code gate commit. Its advertised
compiler identity is `3c2bb209b69eb9829ead395093f08bd8a8034f3efdef93d410ab5b3fc03c7110`;
binary SHA-256 is `a88a7068495a3b5d3778bdb7ec2b0cc60bb5a2ad91a03a064d61dce84cff91f8`.
The initial workspace executable had a different compiler identity, so its
measurements are not the acceptance evidence used here.

Commands, source variants, outputs, work receipts, and child-process traces are
in [the probe evidence](development-velocity-c2-p1-review-2026-09-16-probes.json).
These are focused checks; the full Zig, documentation, and Guardian gates were
not rerun. No implementation files were changed.

## New findings

### R1 — P2: whole-project source identity defeats selective test reuse

Locations: `src/native_test_command.zig:89` and `src/native_test_receipts.zig:64`.

Every receipt now compares `source` against the identity of the entire captured
source inventory. This adds a whole-project invalidation condition on top of
the existing per-test semantic dependency key.

A fixture has two tests calling different helpers, plus one unused helper:

| Run | Executed | Cached | Dependency keys |
| --- | ---: | ---: | --- |
| Initial | 2 | 0 | Initial keys |
| Unchanged | 0 | 2 | Both unchanged |
| Change unused helper | 2 | 0 | **Both unchanged** |
| Change first helper; restore unused helper | 2 | 0 | Only first test's key changes |

The unused-helper edit alone is sufficient to demonstrate the regression. This
contradicts the existing unaffected-result reuse behavior and makes unrelated
edits expensive even when the dependency planner is correct.

**Repair:** bind receipt acceptance to the selected test/provider dependency
closure. Keep whole-snapshot identity for detecting source changes during an
invocation. Continue validating original declarations and replacement contracts
before accepting a receipt.

**Acceptance:** unused edits execute zero tests; editing one used helper executes
only its dependent case; relevant provider/contract changes still invalidate or
reject as appropriate.

### R2 — P2: share preparation across cases with the same selected graph

Locations: `src/native_test_command.zig:101-105`, in the loop at line 68.

The original shared `Project` was removed. Each case now gets a new `Project`
from `session.check`, whose implementation invokes full-project
`emit-project-qbe`. Its executor starts empty, so each executing case also builds
a separate native library. Previously ordinary cases shared both preparation
and the executor.

Child-process tracing of the two-test fixture confirms:

- An entirely cached run still invokes `emit-project-qbe` twice on the same snapshot.
- A forced run invokes `build` twice and `emit-project-qbe` four times, including
  the emission performed inside each build.

This introduces repeated whole-project work proportional to the number of
cases. It is a regression in existing behavior, independently of the deferred
C4 work to make preparation itself incremental and lowering lazy.

**Repair:** memoize checked projects and executors per selected provider graph
within the invocation. Perform declaration-first validation before creating
each graph. Share a graph's prepared code across cases while retaining isolated
test execution.

**Acceptance:** two ordinary cases share one preparation and one native library;
identical provider graphs also share; distinct graphs remain isolated. Warm
receipts should not multiply whole-project preparation by case count.

### R3 — P2: use resolved type meaning in discovery and provider comparison

Locations: `src/interfaces.zig:635-693`, `src/native_test_contracts.zig:101`
and `src/native_test_contracts.zig:150`.

The new declaration manifest retains scalar spellings such as `int` and `i64`
and renders an alias as a declaration identity rather than resolving its
transparent target. Discovery and provider validation then compare these
strings as though they were checked types.

Two concrete failures:

1. A valid exported `type Truth = bool` and `test_alias() -> Truth` produce
   `result: "bool"` in `schema-project --no-cache`, but `mylang test` exits 2
   with `MissingTestExpectation`. Previously discovery consumed the checked
   schema and recognized the boolean default expectation.
2. Production `sample() -> int` accepts a matching fake returning `int`, but an
   otherwise identical fake returning `i64` exits 2 with `IncompatibleProvider`.
   Those are equivalent scalar types in the language.

**Repair:** build canonical declaration-level type descriptors that normalize
builtin aliases and expand transparent aliases, while preserving genuinely
nominal identities. Use them for both test discovery and contract comparison
without checking unselected production bodies.

**Acceptance:** boolean aliases discover normally; equivalent `int`/`i64`
providers pass; genuinely different scalar types and nominal domains reject.

### R4 — P2: persistent-cache eviction performs quadratic directory work

Locations: `src/semantic_store.zig:383` and `src/semantic_store.zig:434-446`.

Every successful body publication calls `trim`. That scans and stats every file
in the namespace and allocates an entry list even when the cache is below its
bounds. Publishing N bodies therefore visits approximately
`1 + 2 + ... + N` cache entries.

`strace -f -c` on fresh, independent namespaces measured:

| Ordinary functions | `statx` calls |
| ---: | ---: |
| 128 | 8,389 |
| 256 | 33,157 |
| 512 | 131,845 |

These are syscall counts, not uninstrumented latency benchmarks. Their growth
confirms the source-level quadratic path. A large existing namespace also adds
a full scan to each subsequently published body.

**Repair:** amortize inventory and eviction across a publication batch, or track
bounded accounting with reconciliation. Preserve safe concurrent publication
and the advertised retention bounds.

**Acceptance:** initial namespace population has approximately linear filesystem
inventory work; budget enforcement, races, and damaged-entry behavior retain
their existing correctness tests. Then repeat the actual scale benchmark.

## Previously identified gaps that remain

### Exported mutation contracts are still absent from API fingerprints

`src/incremental.zig` was unchanged in this step. `writeTypedFunction` does not
include the mutation footprint, and `functionSpan` stops before the `mutates`
clause. With `--no-cache`, changing an exported declaration from `mutates(a)` to
`mutates(b)` still produces the same function interface hash:

`78c90dacfcb18683b74217f24cb1144ea10598eab2f26e7eea257f82abb42c46`

The public interface identity and project interface hash also remain unchanged.
This is a carried-forward gap, not a newly introduced regression. C1R's own
semantic dependency context and mandatory mutation/origin pass are separate
mechanisms; this probe does not demonstrate stale C2 acceptance. It does show
that the public API fingerprint is still incomplete. Cover declared mutation
positions and the intended return-origin contract before relying on it for
additional specialization/test-preparation reuse.

### Warm compiler-build invalidation is still open

`final-status.md` explicitly retains the stale generated `qbe_build_assets`
limitation and requires cold build gates. This review did not attempt a warm
compiler rebuild. A cold green suite does not establish that this prerequisite
has been fixed.

## Positive evidence

- Three ordinary bodies, across separate processes: seed `performed=3/reused=0`;
  helper edit `performed=1/reused=2`; unchanged `performed=0/reused=3`;
  `--no-cache` `performed=3/reused=0`.
- Corrupting one stored entry falls back successfully to
  `performed=1/reused=2`.
- A matching fake passes while production contains `todo[int]()`. A forced fake
  test also passes with a production body type error. A cold real production
  check rejects that same body with `E_TYPE`.
- An incompatible fake return type and a malformed original public interface
  both reject.

These support the core C2/P1 functionality. They do not validate the deferred
generic reuse, full corruption/concurrency matrix, scale targets, or productivity
trial independently of the reported gates.

## Recommended next step

Land a focused correction for R1–R4 and close the outstanding public-contract
hash and warm-build invalidation gaps. Preserve the passing C2/P1 cases above.
Then proceed with C3/C4 and remeasure S1, followed by D2 reconciliation and the
productivity trial. Do not mark the performance or general invalidation work
complete based on the current report.
