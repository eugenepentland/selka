# S3-C property runner hold checkpoint — 2026-10-06

Status: **held for the parent’s S3 §2 old-answer accident review**. No runner integration or exit claim. No implementation, build, or qualification ran after the hold instruction. No runner-owned process remained running at the checkpoint.

## Source and preservation

- Worktree: `/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-runner`.
- Branch: `codex/new-core-s3-runner`.
- Committed HEAD: `f58da8e375d1005a33f626e684bf79953c7f47c0`, the resolved C/M/T1/T2 dependency merge. Its normal commit passed all 88 Guardian checks; it is not a qualified runner implementation.
- Runner changes remain in the index/worktree, including new untracked modules and fixtures. They are not ready for a source commit. Preserve staged and unstaged changes together; do not reset or overwrite them.
- `stash@{0}`, named `s3-runner-before-combined-dependency`, remains as a pre-merge backup. It has already been restored and conflicts resolved. Do not pop it again or touch older shared stashes.
- The ignored checkpoint archive `.mylang-cache/s3-runner/hold-checkpoint-run01.tar.gz` contains all modified tracked source, new runner source, fixtures, and runner evidence. `hold-source-run01.patch` captures the complete tracked diff against HEAD. `hold-status-run01.txt` captures index/worktree status.
- Frozen IR and public formats are unchanged. Source-aware `buildRootsSource(... checked.src ...)` and C/M/T1/T2 runtime embeds were retained during the dependency merge. No `test/lang` edits or `main` merges occurred.

## Implementation present, not yet qualified

The core-owned generator, type graph, shrinker, and counterexample renderer port the old primary algorithms. The property runner keeps the old name seed, defaults (100 trials, 10× discard limit, 2,000 shrink attempts), source parameter order, refill/batch decisions, and property evidence fields. Private copied values use two little-endian u64 words per node; this is private runner transport, not an old wire ABI import or public format change.

The dispatcher builds typed Core decode/encode adapters, injects ordinary test stand-ins in source parameter order, and includes reachable record-invariant roots. Each selected test owns a private random cache directory. A bounded outer batch forks each trial because Core traps exit the process; this keeps fatal-trap cleanup intact while allowing own preconditions/invariants to discard an input. The latest unbuilt C edit forwards fatal signals from the child through the batch parent so the old algorithm can retry the incomplete prefix. Copied stdout/stderr and Result traces are recorded per trial. Fork count and provider reset behavior still need direct old/new evidence.

Files:

- New generation/model modules: `src/core/property_value.zig`, `property_types.zig`, `property_generate.zig`, `property_shrink.zig`, `property_render.zig`, `property_schema.zig`, `property_codec.zig`.
- New Core execution modules: `src/core/property_ir.zig`, `property_execute.zig`, `test_builder.zig`, `test_runner_batch.zig`, `test_runner_property.zig`, and `runtime/core_test.c`.
- Existing runner changes: `test_runner.zig`, `test_runner_entry.zig`, `test_runner_report.zig`, `test_runner_test.zig`, `main.zig`, `driver.zig`, `root_test.zig`, and `SPEC.md`.
- New meaningful regression tests: `runner_property_test.zig` and `test/core/c_runner_{properties,failures,standins,signal}.my`; linked signal helper `experiments/new-core-s3-20261006/wave-b/s3-runner/c_runner_signal.c`.

## Completed observations

These are diagnostic probes of WIP, not old/new qualification:

| Command log | Observed result |
| --- | --- |
| `logs/core-run01.txt` / `.time` | Mechanical Zig errors; 2.47 s. |
| `logs/core-run02.txt` / `.time` | Core rebuild succeeded; 1.75 s. |
| `logs/core-run03.txt` | Canceled while waiting for build admission; compiler did not execute, no rebuild timer. |
| `logs/core-run04.txt` / `.time` | Combined C/M/T1/T2 plus runner rebuild succeeded; **2.87 s**, 329,560 KB. The outer gate waited 275 s; all three build slots were held during the measured compiler run and no gate ran concurrently. |
| `logs/runner-cases-run02.txt` | Six passing cases, four expected failing cases, zero unsupported; the ordinary generated-data case actually ran 100 inputs. |
| `logs/properties-run01.txt` | Eight passing generated-shape tests, one real `InvalidIr` collection-decoder defect, zero unsupported. Own precondition: 12 passed/9 discarded/2 batch processes. Record invariant: 12 passed/11 discarded/3 batch processes. Recursive values, Option/fixed array, text/bytes, Result(true), and trial-local stdout/stderr passed 12 trials each. |
| `logs/failures-run01.txt` | Integer failure reduced 27→8 after three passes, four shrinks, 25 attempts, seven batch processes. Impossible own precondition discarded 121/121 inputs and failed. Helper precondition failed instead of discarding. Property False/Ok(False)/Err and ordinary Ok(False)/Err failed. List shrink case hit the same collection `InvalidIr` and therefore has not tested shrinking. |
| `.mylang-cache/s3-runner/merge-dependency-commit-run01.txt` | Committed dependency merge passed Guardian 88/88. |
| `logs/guardian-run03.txt` | Runner WIP gate still fails **2/88**: one unused public generator version and nine deliberate old-algorithm allocator-name divergences (`context.arena` versus `context.allocator`). No runner source commit has been attempted. |

The latest `--link` parser addition, compiler-wrapper trace-frame filtering, and child-signal forwarding are newer than `core-run04`; do not assume they have compiled or run.

## Known work left when review permits resume

1. Fix the collection decoder phi construction in `property_ir.zig` near line 221. The assignment obtains a pointer into `function.insts` before `b.constant(...)` on the right can reallocate it. Compute the zero constant and extra operands first, then assign `insts.items[index.index()].data` by a fresh index. Re-run the failing list/dict generation and actual list shrinking tests. This diagnosis is not yet verified by an edit/run.
2. Resolve the Guardian unused version declaration and explicitly document each deliberate independent-Core algorithm divergence flagged by `twin-drift`. Preserve old algorithm bodies; sharing old-backend lowering is forbidden. The existing `draw` annotation already explains the two-word private node representation.
3. Rebuild the latest source with uncontended core timing before using `zig-out/bin/mylang-core`.
4. Compare actual seed-7/runs-12 reports with the D2-qualified old oracle, including seed, passes, discards, processes, original/minimal inputs, shrink/attempt counts, returned Result grading, reasons, and trace presentation. No exact old-report comparison has run yet.
5. Run stand-in reset/persistence evidence with Clock, Entropy, FS, Environment, and Streams. The fixture exists but has not run. Do not modify the reviewed Environment provider behavior during the hold.
6. Run the linked fatal-signal fixture against both compilers and compare incomplete-prefix retry/shrink behavior. Check stdout copied before fork, empty-stderr nonzero exits, and leaked-handle outcomes. The signal fixture exists but has not run.
7. Inspect timeout cleanup: the parent batch has a 60 s bound and child alarm, but a timed-out parent could leave a child until its alarm. Ensure any cleanup belongs only to this runner process group. Inspect `property_execute.zig` fatal leak reporting: appending an extra outcome beyond the submitted input count must not index past property inputs.
8. Check owner-directory cleanup and exact ordinary Result trace wording. The private directories are isolated but currently remain in the CLI cache until cache cleanup; test tmp directories are removed by their owner.
9. Run the new regression tests, existing runner tests, full `test-core` with eight shards (or more if a shard exceeds the plan limit), strict focused property/capability conformance, and full strict conformance with leak/fact verification. Every real S3 data-parameter test must execute; unsupported is not a qualification result.
10. Commit only after Guardian 88 and required gates pass. Send the source and evidence IDs to the parent; the parent owns integration, final full gates, and the serialized Guardian feedback commit.

Optional dependency `4cfafc8df` adds C owner limits, cleanup order, and clock overflow checks, and has not been cherry-picked. Coordinate with C/root before taking it. C’s later source-render followup may change `textOf` signatures; do not edit C/M/T2 files uncoordinated.

## Exact resume commands (after explicit parent/user resume)

Run from the runner worktree. Use the next run suffix; never overwrite a prior log. First make the source fixes above, then:

```bash
zig fmt src/core/property_ir.zig src/core/property_generate.zig src/core/test_runner_property.zig > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/fmt-run10.txt 2>&1
/home/epentland/ai/canopy/guardian-zig/zig-out/bin/guardian-check all . --gate --verbose > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/guardian-run04.txt 2>&1
scripts/build-slot.sh gate -- bash -c '"$@"; result=$?; exit "$result"' -- scripts/build-slot.sh build -- python3 experiments/new-core-s3-20261006/wave-a/exclusive_core.py -- /usr/bin/time -f '%e seconds; %M KB' -o experiments/new-core-s3-20261006/wave-b/s3-runner/logs/core-run05.time zig build core --summary all > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/core-run05.txt 2>&1
scripts/build-slot.sh build -- env MYL_CORE_LEAKCHECK=1 zig-out/bin/mylang-core test test/core/c_runner_properties.my --json --seed 7 --property-runs 12 --cache-dir .mylang-cache/s3-runner/resume-properties --release --verify-facts > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/properties-run02.txt 2>&1
scripts/build-slot.sh build -- env MYL_CORE_LEAKCHECK=1 zig-out/bin/mylang-core test test/core/c_runner_failures.my --json --seed 7 --property-runs 12 --cache-dir .mylang-cache/s3-runner/resume-failures --release --verify-facts > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/failures-run02.txt 2>&1
scripts/build-slot.sh build -- env MYL_CORE_LEAKCHECK=1 zig-out/bin/mylang-core test test/core/c_runner_standins.my --json --seed 7 --property-runs 12 --cache-dir .mylang-cache/s3-runner/resume-standins --release --verify-facts > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/standins-run01.txt 2>&1
scripts/build-slot.sh build -- env MYL_CORE_LEAKCHECK=1 zig-out/bin/mylang-core test test/core/c_runner_signal.my --json --seed 7 --property-runs 12 --cache-dir .mylang-cache/s3-runner/resume-signal --link experiments/new-core-s3-20261006/wave-b/s3-runner/c_runner_signal.c > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/signal-run01.txt 2>&1
```

The failure fixture intentionally exits 1; retain and inspect its complete JSON. Use the same seed/run arguments for the old oracle with a separate cache/log for each command. D2 oracle path:

`/home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-integration/.mylang-cache/s3/d2-oracle/mylang`

SHA256: `feb7914ba50d0649180a5257b11f1a821930b40afd18b4f48f0d503127a80073`. The sibling `s3/oracle/mylang` is stale before D2 and must not be used.

After the focused failures and old/new comparisons are resolved:

```bash
scripts/build-slot.sh gate -- scripts/build-slot.sh build -- /usr/bin/time -f '%e seconds; %M KB' -o experiments/new-core-s3-20261006/wave-b/s3-runner/logs/test-core-run01.time zig build test-core -Dcore-shards=8 --summary all > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/test-core-run01.txt 2>&1
scripts/build-slot.sh build -- python3 experiments/new-core-s2-20261005/wave-b/integration/conformance_checked.py --set all --why --jobs 4 --mylang /home/epentland/ai/canopy/mylang-worktrees/codex-new-core-s3-integration/.mylang-cache/s3/d2-oracle/mylang --core zig-out/bin/mylang-core --cache-dir .mylang-cache/s3-runner/conformance --leakcheck --verify > experiments/new-core-s3-20261006/wave-b/s3-runner/logs/conformance-run01.txt 2>&1
```

Coordinate full gates and commits with the parent. Hold the plan’s stop rules throughout; a compiler admission wait is not the uncontended rebuild timer.
