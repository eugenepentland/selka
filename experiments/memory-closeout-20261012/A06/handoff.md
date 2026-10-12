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
| Existing generic-resource source check | Pending shared build admission |
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

No safety or in-scope application support defect has been found in completed runs.
The original word-count refusal correctly rejects transferring a borrowed key, but
C0's `E_SINGLE_OWNER_OVERLAP` message says "a list" for a string. A07 accepted
ownership of the proposed wording correction to "a value". No new shared helper
contract, spec entry, test-root registration or coordinator production edit is
required by A06 at this point.

The existing external-capabilities and generic-resource examples are source-check
probes only, because exact live-provider outcomes are not deterministic. They are
not substituted for the fully executable resource application matrix.
