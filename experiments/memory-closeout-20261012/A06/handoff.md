# A06 application handoff

Base: `fbfcaa7a923186a8e773c3760f81c10aa345a432` (C0). Worker branch:
`codex/memory-closeout-20261012-A06`. Proposed implementation is the commit
containing this handoff; the coordinator records its exact SHA when integrating.

Owned changes: `examples/python-word-count/{main.my,README.md}` and this A06
experiment directory. No shared production files were changed. The word-count
example explicitly copies the split word when transferring a dictionary key.
This changes one application source line and adds one `.copy()` site. The original
source is preserved and its C0 ownership refusal is recorded in `migration.json`.

Four new application shapes and frozen small/large datasets are documented in
`README.md`. Every shape has a local helper module. `manifest.json` pins all
application and dataset hashes, sizes and independent expected checksums.
`originals/programs/` preserves the corresponding RC-source forms; these are new
workloads, not a claim to reproduce historical user programs. Timing entrypoints
in `timing/` reuse byte-identical helpers and expose repetitions in `argv[0]`.
`timing-manifest.json` gives A09 exact identities and accumulated checksums.

## Qualification status at this commit

Frozen compiler: A09's complete C0 installation at
`.tmp/memory-closeout/A09/C0/bin/mylang` in the A09 worktree. Compiler SHA256:
`324e0023f643e4949f72086d13744054f4b5bf7a38975822807f1d74ead2ec4a`.
Source revision is exactly C0. The shared pinned Zig is used via `$ZIG`.

| Check | Status |
| --- | --- |
| Word count, C0 release, small/large | Pass: exact outputs, RC0, managed exit-live0, clean ABI marker and symbols |
| Nested JSON, C0 release, small/large | Pass: exact outputs, RC0, managed exit-live0, clean ABI marker and symbols |
| Resource files, C0 release, small/large | Pass: exact outputs, RC0, managed exit-live0, clean ABI marker and symbols |
| Parallel primality, C0 release, 1/2/8 workers, small/large | Pass: exact outputs, RC0, managed exit-live0, clean ABI marker and symbols |
| Existing migrated word-count, domain-codec and external-capability source checks | Pass |
| Existing generic-resource source check | Refused at line52 acquire_resource passed through handle; A07 bounded provider-origin support pending integration |
| Timing helper hashes and accumulated-output oracles | Pass |
| Integrated candidate, all five pipelines | Pending frozen coordinator candidate |
| Ordinary default commands / retirement requalification | Pending coordinator stages C2/C3 |

Commands used:

```sh
python3 -B experiments/memory-closeout-20261012/A06/qualify.py \
  --compiler "$C0_INSTALL/bin/mylang" --zig "$ZIG" \
  --output .tmp/memory-closeout/A06/c0-release --modes release
python3 -B experiments/memory-closeout-20261012/A06/qualify.py \
  --compiler "$C0_INSTALL/bin/mylang" --zig "$ZIG" \
  --output .tmp/memory-closeout/A06/c0-release-rest --modes release \
  --cases file_processing,parallel
```

The first run was checkpointed after word count and JSON to adopt the centrally
approved two-build-slot budget. Only a still-queued wrapper was canceled; no active
compile or completed evidence was lost. `harness-c0-smoke.py` preserves the exact
initial harness hash. The continuation has its own output directory and hashes.
Committed raw word/JSON records are in `evidence/C0-word-json/`, with losslessly
compressed counter/build/run JSON and a hash manifest. Resource/parallel raw records
are committed in `evidence/C0-file-parallel/`, completing all 12 C0 release runs.
No historical reports were changed.

All values below are whole-program managed counters, not traffic inferred from
peaks, RSS, or isolated kernel measurements:

| Large workload | Allocations | Cumulative bytes including realloc growth | Peak live managed bytes |
| --- | ---: | ---: | ---: |
| Word count | 65,572 | 4,458,128 | 99,152 |
| Nested JSON | 42,596 | 3,385,656 | 828,184 |
| Resource files | 16,440 | 1,236,568 | 49,680 |
| Parallel, 1 worker | 1,576 | 118,968 | 65,976 |
| Parallel, 2 workers | 1,576 | 118,968 | 56,248 |
| Parallel, 8 workers | 1,576 | 118,968 | 51,832 |

No performance saving is claimed from these baseline observations. A09 owns the
uninstrumented paired runtime/RSS measurements. Build elapsed fields include
admission wait and are not compile-time measurements. The resource workload uses
the deterministic in-memory filesystem provider and does not measure disk I/O.

## Remaining work and requests

The candidate must run `qualify.py` without `--modes` for all five pipelines:
release, unoptimized debug, verified release, optimized debug and release without
facts. A complete pass is 20 binaries and 60 counted executions. Promotion uses
`--ownership default`. The harness keeps every refused lane in its result report.
No baseline result qualifies a different compiler revision.

All four new application shapes pass the completed C0 runs. The existing generic-resource example is a source-admission blocker owned by A07; its exact original source remains unchanged. `evidence/C0-example-source-checks.json` preserves its E_SINGLE_OWNER_UNSUPPORTED diagnostic.
The original word-count refusal correctly rejects transferring a borrowed key, but
C0's `E_SINGLE_OWNER_OVERLAP` message says "a list" for a string. A07 accepted
ownership of the proposed wording correction to "a value". The initial application batch required no shared helper contract or spec change. Later source-migration work adds the coordinator-registered `src/core/a06_nested_write_test.zig`; see the following section.

The existing external-capabilities and generic-resource examples are source-check
probes only, because exact live-provider outcomes are not deterministic. They are
not substituted for the fully executable resource application matrix.


## Secondary guest migration and compiler reproducers

The coordinator subsequently reserved 64 existing guest sources (the initial 65
list transferred `frontend_type_helpers.my` to A01). `guest-migrations/README.md`
and `ledger.json` preserve every current admission status, exact compiler/source
hashes, source burden and remaining owners. Frozen C0 original sources are stored
as deterministic gzip files. Every original assertion line and public test function
is preserved. These are source migrations, not compiler-only performance results.

`nested-write/` contains source-admission reproducers and exact proposed checker
patches for A07. Regression commit `6dd39d631` adds the original nested-field case;
its extended tests cover list-slot reconstruction, tuple deep copies and original
unsupported traversal/view boundaries. A01 owns the tuple method exception; A07
owns applying and qualifying the ownership/lowering changes. Guardian passed 88
checks on the first regression commit. Native counted tests await those compiler
fixes and must pass on the integrated candidate before qualification is claimed.

The initial 64-source migration is commit `9cc6d7758` (Guardian 88/88). It also
includes the coordinator-authorized test-root registration and native linked-symbol
audit. Followup regression commits `836017c42` and `741218971` add dynamic signed
array index capture, side-effect evaluation count, IR live-alias controls and
explicit refusal boundaries. Each commit passed Guardian; A07 owns production
normalization/transfer fixes and their native qualification.

The coordinator added 23 registered Core guest fixtures. Their frozen originals,
support3 baseline and source checks are in `additional-migrations/`. The approved
depth-40 DAG-to-owned-tree change and ancestor-write cancellation migrations are
documented there. Neither reduces assertion coverage or claims a same-source
performance improvement. Native RC/COW oracle review belongs to the coordinator
and A09; A06 edits only its reserved guest fixtures and unique regression module.

Support4 exploratory application validation uses source
`66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`.
All four shapes pass all five modes, both inputs and the parallel 1/2/8-worker
matrix: 20 binaries and 60 counted executions preserve checksums, have zero RC
events and zero exit-live managed bytes, and pass the harness's ABI-marker and
linked-helper checks. `evidence/support4-applications.json` combines exact hashes,
managed totals and links to every raw report. The complete structural ABI audit
remains A07/A10's responsibility. These results are not final C1/C2/C3 qualification.
Completed evidence is preserved before every checkpoint, and resumed mode batches
use distinct output directories. The initial 64-source ledger currently admits
52 sources on exploratory compilers and retains all 12 pending lanes. The
additional 23-source ledger admits 18 and retains five nested-slot failures.

`migration-native.py` extracts immutable C0 registered output constants, identified
by the original Zig test file hash, to exercise sensitive source migrations.
`v_snapshot`, `v_mut_window` and `u1_state` pass counted Support4 release with exact
original outputs, zero RC events and no managed leaks. `ce2_effects` builds and
passes the linked-helper audit but aborts with `free(): invalid size` (status -6),
before stdout/counters flush. This is a correctness blocker owned by A07, not a
tradeoff or a qualified run. Raw results are in `evidence/support4-native-*`.
Support5 requalification of the same source reproduces the abort; `evidence/support5-native-ce2/` preserves its compiler/source hashes and raw build/run records. The Support4 failure is also preserved. Native qualification remains required for all migrated fixtures.

Regression followups `928172f79` and `65026bad3` make the conservative array IR
controls executable roots, call them with runtime input and restrict retain
assertions to the intended function. Both passed Guardian 88/88; A07 owns running
them against the production array-transfer patch. No unexecuted control is counted
as passing.


## Support5 safety reduction and interpreter migration

Support5 reproduces the admitted `ce2_effects` native abort. Regression/evidence
commit `935789ec2810b224e51070c3e1c3395c6649c290` passed Guardian 88/88 and
preserves the full failing run plus a 29-line red/green reduction. A child record
copy, a sibling scalar update, and a whole-parent snapshot are sufficient to expose
incorrect shared memory homes. Removing the scalar update or shrinking the child
out of memory passes; inlining the callee still fails. A07 owns the bounded
region-origin fix in `emit_homes.zig`. The registered A06 test checks counted debug
and verified release with and without that sibling update; a following dynamic
branch regression exercises both phi outcomes. These tests need the fixed compiler.

With coordinator approval and after A09 released its frozen-source lease,
`ce_cow.my` replaces three whole-Runtime temporary patterns with direct mutable
field calls. The original migrated source and its A09 evidence are preserved.
Both source identities pass identical three-line native output and cleanup on the
same Support5 release compiler. Cumulative allocation plus growth falls from
1,661,693,688 to 4,914,944 bytes; managed peak stays 227,784 bytes. This is a source
migration improvement, not a compiler-only or RSS/runtime claim. Exact source,
compiler, Zig, binary, LLVM and harness hashes and raw evidence are in
`evidence/ce-cow-projection/`. A09 owns the all-five-mode registered oracle checks.

The final Support5 source checkpoint admits 55/64 reserved guest sources and 18/23 additional fixtures. All original assertion/public-test names remain unchanged. The initial group now has 348 added explicit copy sites, 569 added and 378 removed lines across 56 changed files. The additional group has 162 added copy sites, 204 added and 180 removed lines across all 23 files. Every remaining refusal stays in the denominator; Support6 must recheck the tuple and exact-slot fixes.
