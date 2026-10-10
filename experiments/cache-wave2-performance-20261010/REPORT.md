# Cache Wave2 performance investigation, 2026-10-10

This correctness pass is complete. Implementation `07927a094` passed 2,550
executed full-gate tests, 198 shadow qualification calls, 40 focused tests and all
88 whole-tree Guardian commit-hook checks. Paired measurements and the optimized
after-profile are deferred at the user's request: "Defer measurements and finish
this pass." The benchmark never acquired admission; no optimization speedup,
memory improvement or shorter lock duration is established.

The before-change frozen Wave2 candidate spends a large fraction of sampled user cycles in
hashing, including after reverting a shared helper and reusing every test result.
This supports investigating repeated catalog hashing. The available samples do
not recover the caller stacks needed to attribute that cost quantitatively to a
particular hash caller.

The diagnostic uses the populated synthetic 510,436-line fixture, changes the
shared helper from `1` to fresh token `9000001`, then restores its original bytes.
Both invocations use the same candidate-zlib cache and compiler environment as
the completed benchmark. Source hashes before and after match. The compiler
SHA-256 is `92dd45fc92a79bca7eb2f273ec9ffdf6cac454526302b521b5bf33b88e0bc8c6`.

| Profile | Verdicts | Wall s | User s | System s | Max process RSS KiB | BLAKE3 self % | SHA2 self % | TreeHash self % |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Shared helper edit | 662 passed | 17.181 | 17.61 | 13.21 | 677,048 | 43.68 | 1.70 | 3.09 |
| Restore original helper | 662 cached | 10.825 | 11.42 | 7.42 | 677,064 | 55.78 | 3.00 | 2.61 |

BLAKE3 plus SHA2 accounts for 45.38% of helper samples and 58.78% of revert
samples. Including direct self samples in named `lowering_cache.TreeHash.value`
functions gives 48.47% and 61.39%. These disjoint self categories can be added;
the numbers represent rounded event-weighted samples, not fractions of wall time.
For the helper, the largest individual symbols are `crypto.blake3.compressPre`
(24.55%), `crypto.blake3.ChunkState.update` (11.81%), `memcpyFast` (6.05%),
`test_runner.rootsFor` (5.79%) and `crypto.blake3.Blake3.update` (5.68%). For the
revert, the top three BLAKE3 symbols account for 54.58% before other BLAKE3
functions are included. The host executable accounts for 86.64% of helper samples
and 98.70% of revert samples; Zig accounts for 11.67% and 0%, respectively.

The command requested inherited process samples at 99 Hz with `cycles:u` and
`--call-graph dwarf,8192`, on CPU affinity 2 and 10. Perf records 1,664 helper and
1,106 revert samples, with zero reported lost samples. Only one helper sample has
a named recovered stack, and no revert sample does. The major host symbols have
identical children and self percentages. They provide useful flat symbols but
cannot establish top callers or cumulative catalog-hash costs.

Planner memfd samples remain unresolved offsets: 0.32% of helper samples and
0.45% of revert samples. All unresolved symbols, including Zig, total 13.07% and
1.24%. Exact host/component binaries and bounded process maps are retained.
Neither binary has an ELF GNU build ID; `perf buildid-cache` returned zero while
printing "Couldn't add" diagnostics. Perf header decoding also reports an
`Invalid HEADER_EVENT_DESC` warning, although symbol reports succeed. Component
timing therefore should not be inferred from named function samples alone.

Admission queue time is 139.622 seconds, recorded separately from 29.748 seconds
held by the whole diagnostic batch. The per-command wall/CPU values include
profiling and process-snapshot overhead. RSS is GNU time's maximum individual
process RSS. These single diagnostic measurements identify hotspots; improvement
claims require the paired uninstrumented benchmark.

Raw evidence is under
`.mylang-cache/cache-wave2-performance-20261010/profile-helper-510k/`: `results.json`,
`profile-summary.json`, helper/revert `.perf.data`, symbol reports, timing files,
raw test reports, and process maps. `run_with_admission.py` can wrap the existing
benchmark driver through the standard build slot and retain aggregate queue,
held, wall, CPU and RSS evidence without introducing compiler environment values.
Invoke that wrapper directly, because it acquires the build slot itself.

## Implementation and provenance

The implementation is committed locally as
`07927a094ae9e9c6d534834ab46c6abec4da635a`,
`perf(cache): share checked catalog hashing across test roots` (nine source files,
442 additions and 36 deletions). The experiment scripts and evidence are separate
from this implementation commit. The frozen Debug/Release binaries and full gate
precede one subsequent comment clarification in `cache_plan_adapter.zig`; it
preserves line count and changes no executable behavior. It clarifies that full
deployment validation still runs before and after planner execution. Binary
hashes in the evidence identify the actual frozen executables used.

Directory roots sharing one immutable checked program now borrow the same
`lowering_cache.Catalog` declaration-hash prefix. Ordinary and shared preparation
hash the same ordered declaration inputs. Borrowing requires matching table
pointers and lengths and the same main function; a different checked snapshot
hashes its own catalog. Source paths, original locations, assets and discovery
guards remain per-root inputs. The catalog is prepared only when the durable
shared facts path will consume it, and its lifetime follows the checked snapshot.

Planner binding now retains the exact executable bytes that manifest validation
verified, and launches sealed snapshots from those bytes. Deployment validation
before and after execution remains active. This removes the additional executable
read/hash inside each launch. Tests cover borrowed bindings, same-length
replacement, same-size replacement with restored timestamps, and allocation
failure cleanup. Plain test root selection also skips generated-invariant schema
work when no selected test has generated parameters; root order and duplicates
remain intact.

The final focused Debug install reports 26/26 steps and 40/40 tests passing
(29 planner/component and 11 core tests). Catalog tests cover equivalent ordinary
fingerprints, per-root origins and assets, changed signatures/effects/defaults/
records, changed table snapshots, and replay involving defaults and generic calls.
The log is
`.mylang-cache/cache-wave2-performance-20261010/focused-and-debug-install-final/command.stderr.log`.

The optimized Debug binary completed all 99 shadow qualification invocations:
86 main, four selected-private, six warning and three concurrent-edit commands.
The compiler SHA-256 is
`18c497235540973b56235675863949bac23ba857d740aaa3d759f84c1ad4d442`.
This run uses raw storage (`compression=none`), no baseline compiler, and the
independent planner shadow oracle. All 43 main candidate/forced pairs match keys,
normalized verdicts and warning bytes, including deliberately failing cases.
The same-line private edit has one fresh fact, seven reused facts, zero unrelated
raw materializations, one reused test and two planned tests; the unchanged test
retains its original key. Metadata corruption affects 65 payload files, followed
by successful corruption/eviction fallback checks. Allocation warning bytes match
across cold/file/directory replay and each forced execution. The synchronized
concurrent mutation exits with `SourceChanged` and publishes no success; the
current revision and forced execution both report two failures with identical
keys, verdicts and warning bytes.

Debug admission waiting is 0.047 seconds; the aggregate held interval is 84.156
seconds, with 84.131 seconds command wall time excluding admission. These are
correctness-run context, not paired performance results. Machine-readable evidence
is `qualification-summary.json` in this experiment directory, generated by
`qualification_summary.py`; additional completed runs can be added with a new
`--label`, their qualification directory and admission directory.

ReleaseFast with zlib also completed all 99 shadow invocations. Its compiler
SHA-256 is `df45161f422a6421a7f945163c412a61617f782fa2464e9bce30419bafde1c54`.
Independent evidence checks reproduce the 43 main forced agreements, the selected
private reuse counts, all 65 corrupted payloads, and concurrent `SourceChanged`
handling without success publication. All six warning outputs are identical
265-byte diagnostics, also matching the Debug/raw run. Release admission waiting
is 0.042 seconds, held time is 50.225 seconds and command wall is 50.191 seconds.
The qualification summary retains both binary hashes and all checks separately;
Debug/raw versus Release/zlib qualification times do not establish an optimization
speedup. Paired performance conclusions are deferred.

The full `zig build test fmt-check` gate completed successfully: 104/104 steps,
2,550 executed passing tests and no failures. Its exact final summary reads
`2550/25857 tests passed (23307 skipped)`; skipped instances reflect shard
selection rather than additional executed tests. The 29 Guardian test-result
blocks independently total 2,550 passed and zero failed. The final build graph
reports `fmt-check success` and `zig fmt --check success`; live `.my` formatting
checks are cached/reused. Noalloc and embedded migration staging gates succeed.

Guardian reports 88 checks passed, diff-scoped against
`e9011d9c6513f63ae02881d0cfc8258c668e6b5e`: 41/625 source files are in scope for
the 50 per-file checks, while 38 whole-tree checks read everything. This is not
a whole-tree Guardian verification. The implementation commit's hook subsequently
passed all 88 Guardian checks over the whole tree, as reported by the coordinating
agent; the preserved build log remains the earlier diff-scoped evidence.
Admission waiting is 35.120 seconds, the held interval is 1,123.323 seconds and
command wall time is 1,123.296 seconds. `full-gate-summary.txt` preserves the
complete final Build Summary graph, and `full-gate-summary.json` retains the
exact summary, raw evidence hashes, scope, counts and timing context.

## Deferred measurements and next qualification

The three-way 510k benchmark waited behind another worktree's authorized full
gate and never acquired its slot. At the user's request, only this queued wrapper
was cancelled: exit `-15`, no admitted/completed command record, null queue/held
measurements and zero benchmark invocations. `deferred-measurements.json` retains
the cancelled request, evidence hash and explicit user decision. No optimized
after-profile ran. This closes the current correctness pass; it does not leave a
measurement running or reinterpret queue waiting as command time.

Resume the paired benchmark and optimized profile before judging performance or
advancing integration. Then-current-main integration needs its own qualification.
The harness and frozen compiler identities remain available for that next pass.

The retained benchmark plan uses three contemporaneous ReleaseFast arms on the same
fixture source paths: pre-Wave2 `baseline`, frozen Wave2 `comparison`, and
optimized `candidate-zlib`. Each has a separate zlib cache and native store; the
candidate forced-execution oracle has a fourth store. The benchmark records each
compiler path and SHA-256, fixture origins and source hashes, actual test verdicts,
guest/runtime object counts, producer/planner work, and per-command wall/CPU/RSS.
Admission queue and aggregate held time are recorded by `run_with_admission.py`.

"Cold" means the first invocation with that arm's new application/native cache
and isolated Zig local/global cache directories. The installed compilers,
toolchain, operating-system page cache and machine state are already present;
they are not reset between arms. This is not a machine-cold or freshly installed
Zig comparison. The experiment holds the runtime/toolchain and fixture setup
fixed; later integration against then-current main requires separate
qualification and must not be inferred from these frozen installs.

Use the existing `benchmark.py` with `--comparison` pointing to the frozen Wave2
install and `--candidate` pointing to the optimized install, together with
`--candidate-encodings zlib --small-rounds 3 --large-rounds 3`. The normal four
fixtures are current-source EDA and Lox plus the 191,416- and 510,436-line synthetic
reachable chains. Three arms require 69 compiler invocations per fixture, or 276
for all four: cold/no-op, three fresh edits per round, their reverts, and the
candidate forced-execution oracle. Arm order reverses on alternating rounds.
Every edited arm must change an eligible original key and execute at least one
passing test; repeated edited key sets are rejected. Cross-compiler comparison
uses normalized outcomes, because compiler identity is part of the cache key.

Report cold and no-op separately from private/helper/three-file edit medians, with
all three raw samples and ranges, without statistical-significance claims.
Revert measurements isolate reuse of existing success
receipts. The corpora edits insert reachable assertions and can invalidate later
source locations; synthetic literal edits stay on the same line. Synthetic totals
measure a large directory of bounded per-module graphs, rather than one large
planner batch. RSS remains the largest individual process, not simultaneous
process-tree memory. Forced oracle runs and cache inventory scans occur outside
each measured edit interval. Profiler measurements remain separate from this
unprofiled comparison.

Existing candidate-zlib cache evidence retains approximately 0.35 GB for EDA,
0.12 GB for Lox, 0.45 GB for the smaller synthetic fixture and 1.10 GB for the
larger fixture, using allocated bytes. Four full stores across the same workloads
can therefore require roughly 8 GB before additional source/raw data and build
temporaries; compiler arms do not all retain identical metadata. Schedule and
retain disposable stores with disk headroom in mind. Do not copy populated caches
between compiler arms or substitute historical fixture sources.

After the optimized profile, possible next investigations are repeated discovery
scans across the shared function catalog, stage-pack load sequences and backing
file access for header/fact hits, the planner's remaining deployment-validation
hashes and memfd copy per batch, and per-root graph copies/transposes. These are
review leads, not measured conclusions or additional changes in this pass.
