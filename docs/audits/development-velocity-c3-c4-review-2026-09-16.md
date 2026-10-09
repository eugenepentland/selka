# C3/C4 integration review — 2026-09-16

## Decision

**The implemented reuse paths work, but a correction pass is required before
sign-off.** Four findings remain: a misplaced reduced graph can admit a stale
successful test receipt, directory tests ignore `--no-cache`, session clearing
leaves generic entries alive, and the new in-memory generic tables do not enforce
the advertised shared byte budget.

C4 meets its warm-unchanged fast-path milestone. It is **partial against the
original plan**: changed snapshots still emit the full project, and executing any
uncached case builds the full selected-provider library. Per-function lazy
lowering remains a separate deliverable, as the completion report acknowledges.

## Scope

Reviewed changes from `81cd79bb` through `b819277b`. Probes use a pinned copy of
the clean `final3-release2` ReleaseFast compiler at code gate
`c3cf37c66a20559c8e713a5ee31c61bf0e05f4de`. Implementation sources and build files
match the reviewed HEAD; subsequent commits only change documentation.

- Executable SHA-256:
  `2a8bde219d625e807f970bbf8d0d3d284ab0cd344289e67a8e3c744919601d8e`.
- Advertised compiler identity:
  `0ff14c743d462aca78f94474aaabda27e04a079e0411a7703d4c5032eb9ce3de`.
- Native guest builds use Debug mode and the pinned Zig/QBE tools.
- All fixtures, deliberate cache damage and retention experiments are private
  temporary files. No implementation files were changed.
- The full Zig/Guardian gates were not rerun. The gate totals remain the
  implementation pass's reported evidence; this review adds targeted probes and
  source inspection. The preserved retention/remap WIP was not merged or tested.

Commands, outputs, traces, source fixtures and review drivers are preserved in
[the probe evidence](development-velocity-c3-c4-review-2026-09-16-probes.json).
Recorded single-run timings are diagnostic observations, not S1 measurements.

## Findings

### G1 — P1: bind a reduced graph to its requested input key

Location: `src/native_test_graph.zig:119-130`, with publication at lines 134-141.

The graph filename is derived from the requested input key, but its stored
wrapper contains only a version, a payload checksum and the payload. Loading
verifies that the payload is intact, not that it belongs to the requested key.
Copying an intact entry from another source snapshot therefore passes validation.

Reproduction, using one boolean test and an unchanged public signature:

1. Test returns `True`: execution passes and publishes its graph and receipt.
2. Change it to `False`: execution correctly fails and publishes a different graph.
3. Copy the complete first graph file over the second graph's filename, without
   changing any payload or checksum bytes.
4. Rerun: **exit 0, cached=1, executed=0**, despite the test still returning `False`.
5. Run with `--no-cache`: **exit 1, failed=1, executed=1**.

The fresh validity check only establishes that the current program type-checks;
it cannot establish that the loaded dependency facts describe that program.
The stale graph reconstructs the old receipt key and admits the old success.
This is a foreign-entry/misplacement failure, not an observed normal cache-key
collision or a claim that ordinary edits alone produce stale green results.

**Repair:** store and verify the requested key/input fingerprint inside the
integrity-protected graph envelope. Bump the wire version so old entries miss.
Validate the graph/schema/dependency structure before use; incompatible or
malformed entries must fall back to fresh preparation.

**Acceptance:** repeat the complete-entry substitution above and observe a miss
and the real failure. Cover foreign compiler/source/provider entries, truncated
and invalid payloads, and an unchanged valid hit with zero emission/build.

### N1 — P2: forward `--no-cache` to directory test children

Location: `src/native_test_directory.zig:98-112`.

The directory command parses the new flag but its child argv builder only
forwards `force`. The children therefore run with normal durable caching.

Independent two-program suite:

- Seed: 2 executed / 0 cached.
- Rerun directory with `--no-cache`: **0 executed / 2 cached**.
- Run directory with `--no-cache` and an empty cache directory: executes both,
  but publishes **two graph files and two successful result receipts**.
- Direct entry-file `--no-cache` correctly executes and publishes no graph/result
  files, showing this is specific to directory fan-out.

**Repair:** propagate cache policy to every child. Keep the documented directory
work-report aggregation behavior explicit; do not silently alter it while fixing
this flag.

**Acceptance:** directory `--no-cache` against both seeded and empty caches must
execute every selected case, admit no durable results/graphs, and leave existing
durable cache contents untouched. Test more than one worker as well as `--jobs 1`.

### C3R1 — P2: clear the new generic tables with the rest of the session

Location: `src/semantic_cache.zig:158-172`.

The symbolic and specialization tables are cleared only by `deinit`.
`Cache.clear`, used by `check-session clear`, still clears only ordinary entries.

With two concrete specializations, the session sequence
`check`, `clear`, `check`, `quit` reports:

- First check: **3 bodies checked / 0 reused**.
- Check immediately after clear: **1 checked / 2 reused**.

This session has no durable semantic store attached, so those two replays come
from memory that `clear` failed to release. The reported retained bytes are zero.

**Repair:** put generic-table release into the common clear operation and keep
deinitialization safe. Preserve cumulative work counters if that is the existing
reporting contract, but report the actual retained storage.

**Acceptance:** after clear, the same source checks all bodies/templates fresh;
both generic indexes are empty and their arenas are released. Returned programs
must remain valid across clearing, as with ordinary entries.

### C3R2 — P2: enforce the shared retention budget on generic entries

Locations: `src/semantic_cache.zig:176-191`,
`src/generic_cache.zig:335-348`, and
`src/generic_specializations.zig:227-237`.

The cache says ordinary bodies, symbolic templates and concrete specializations
share `reuse.max_bytes`. In practice, both generic backends receive only
`enabled = max_bytes != 0`; their tables have no byte accounting or eviction.
Publication and durable-hit promotion append entries regardless of their retained
size. `functions.retained_bytes` omits both tables.

A bounded session experiment repeatedly checks a 120-statement generic function.
Both cohorts change the ordinary caller on every iteration; one keeps the same
const-length specialization, while the other introduces a distinct length each
time. After 900 checks:

| Cohort | Process RSS | Reported function-cache bytes |
| --- | ---: | ---: |
| Same specialization | 38,732 KiB | 0 |
| Distinct specializations | 67,832 KiB | 0 |

The syntax cache's separate 16 MiB budget evicts entries in both cohorts. Generic
retention has no corresponding bound. These RSS numbers include other allocations
and are not exact generic arena sizes; the absence of enforcement is established
by the source paths, with the controlled growth experiment as supporting evidence.

**Repair:** account for owned arenas, keys and indexes across all three semantic
entry kinds, enforce a defined combined budget during promotion/publication, and
expose accurate retained-byte/eviction data. Oversized entries should bypass
retention without changing acceptance. Include failure/rollback ownership paths.

**Acceptance:** use a deliberately small budget and many distinct templates/type
or length arguments in a long-lived session. Assert retained storage stays bounded,
eviction produces fresh checks, zero budget disables reuse, and output/diagnostics
match a fresh check. Cover both durable-hit promotion and newly checked entries.

## Positive evidence

| Probe | Observed result |
| --- | --- |
| C3 seed, two templates/two specializations | Bodies 3 checked/0 reused; symbolic templates 2/0; specialization bodies 2/0 |
| C3 fresh-process unchanged or caller-body edit | Bodies 1/2; symbolic templates 0/2; specialization bodies 0/2 |
| C3 edit one template | Bodies 2/1; symbolic templates 1/1; specialization bodies 1/1 |
| C3 change one concrete argument | Bodies 2/1; symbolic templates 0/2; specialization bodies 1/1 |
| C3 `--no-cache` | All bodies/templates/specializations fresh |
| Unused malformed generic | Same `E_GENERIC_TYPE` rejection with and without caching |
| C4 warm unchanged | 0 executed/2 cached, 0 QBE emissions, 0 builds |
| C4 unused-helper edit | 0 executed/2 cached, 1 whole-project preparation emission, 0 builds |
| C4 used-helper edit | 1 executed/1 cached, 1 build and 2 total emissions |
| Reversed provider-map order | Forced: 1 prepared graph/1 build; warm: 0 emissions/0 builds |
| Invalid selected body or signature | Rejects with the located compiler diagnostic preserved |

The suspected diagnostic-forwarding regression was ruled out:
`qbe_build_io.Context.capture` already forwards child stderr. Removing the extra
forwarding from the session avoids duplicate diagnostics.

One completion-summary clarification: `--force` skips graph/result reuse but
**does publish replacement graphs and successful receipts**. Only `--no-cache`
suppresses those durable writes. The forced probe produced one graph and two
receipts. This matches a refresh workflow; the summary should distinguish it.

## Recommended next work

1. **Correction pass:** G1, N1, C3R1 and C3R2, with focused regressions followed
   by the combined Debug/ReleaseFast gates.
2. **Review and rebase the preserved retention/remap WIP** (`4fa44aa3`) against
   the new C3 tables and ownership rules. Its presence on a WIP branch is not
   evidence that the large-project retention problem is fixed.
3. **Rerun S1** on one identified corrected commit: ordinary and generic 10k/100k
   projects, unchanged checks, body/interface/provider edits, cached and forced
   tests, actual reused/performed counts, p50/p95 latency and peak memory. Use the
   prior speed report as the before baseline; do not mix it with new-tree results.
4. **Finish C4 lazy lowering** as its own milestone: derive checked dependency
   facts without whole-project emission and build only the uncached selection's
   required closure. Keep the working unchanged fast path as a regression gate.
5. **D2, productivity trial and final acceptance.** Reconcile the status heading,
   stale C3/deferred text, force/no-cache wording, measured limits and feature
   claims with the final executable. Full velocity completion remains open.

Self-hosting lexer/parser/diagnostics work can continue independently on a pinned
stage-0 compiler. The findings above should be resolved before treating the new
cache paths as trusted release infrastructure.
