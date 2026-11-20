# PCB workbench: tool-wait audit, September 21, 2026

**The slow feeling is supported by the logs. The largest opportunities are less repeated verification, stable cache inputs, and avoiding whole-project native emission on every CLI invocation.** Small tool dispatch is a secondary cost. Mylang's incremental machinery does work, but this workflow frequently defeats or bypasses it.

Implementation and verification are recorded in [implementation.md](implementation.md). The audit below preserves the original findings and measurements.

## Measured scope

I snapshotted all **38 sessions** in `~/.dsh/sessions/--home-epentland-ai-canopy-pcb-workbench--`: one root, 27 children, 10 grandchildren; all used the **standard** preset. The 4,658 completed calls span **17:18:07–21:05:45 UTC**. There are no inherited calls, unmatched results, or decoding errors; one call was unfinished. All 38 snapshot hashes were checked. Logs were only read; no logged command was replayed.

There are **8.10 agent-hours** inside completed tools, or **3.43 elapsed hours** with at least one tool outstanding. These overlap across agents and are not interchangeable or additive. Another 6.18 agent-hours are in the logged pre-tool/model phase, including provider and generation latency. The figures below attribute a `job_output` wait to its launch command; background lifetime is not added again.

| Command family | Calls, including associated job reads | Observed agent-minutes |
|---|---:|---:|
| Mylang test commands | 546 | 146.4 |
| Full `guest/gate.sh` | 26 | 107.0 |
| Mylang run/build commands | 477 | 92.4 |
| CLI integration scripts | 13 | 36.1 |
| Coordination / polling | 19 | 35.3 |
| Mixed Mylang test and run | 23 | 24.4 |
| Reads/searches and mixed shell | 1,698 | 18.7 |
| Zig build/test/run | 326 | 10.7 |

These are whole-call command families, not process profiles: for example a run command that starts a server and waits for it includes that wait. [metrics.json](metrics.json) includes every family and exact evidence coordinates. [session-metrics.json](session-metrics.json) preserves source hashes and generic accounting; its older generic category names are less accurate for shell variables and scripts than the table above.

## 1. Stop forcing and duplicating the entire test suite during iteration

`pcb-workbench/guest/gate.sh` copies every module, loops over every file serially, and passes `--force` every time. In `src/native_test_command.zig`, `durableReuseAllowed()` makes force bypass both durable graph reuse and successful test-result receipts. Lower-level syntax/body/object caches can still help; force does not disable every cache.

The **26 gate-containing calls total 107.0 minutes**, with a **216-second median** and a **457-second maximum**. The root agent alone ran 22 of them. These are observations, not 107 minutes of proven waste: the project changed between many calls, and some were legitimate final checks.

There is also duplicate coverage. A module test includes exported tests in its imported graph. One logged `kit.my` invocation reports **120 tests**, while a second invocation counts just **14 kit-owned tests** (`dede3063…`, call 528). The gate repeats shared geometry/model/contract tests through multiple module roots and forces them to execute again.

On the captured current sources, there are **400 public test declarations across 21 modules**. An explicit suite importing all modules exposes exactly those 400 declarations; I verified its inventory through `list-interfaces --contracts`. A static traversal of the module imports estimates 2,085 test appearances when testing each root separately; the historical final gate reported 2,083 passes. Those are different source snapshots and neither count should be presented as unique test coverage. See [suite-inventory.json](suite-inventory.json), [test-overlap.json](test-overlap.json), and the [proposed suite entry](all_test.my.example). The suite entry's discovery was checked; its full execution was not run by this audit.

Recommended workflow:

- During edits, run the relevant module with a qualified filter, e.g. `mylang test guest/geom.my --filter 'geom::*' --cache-dir=<stable-cache> --report`. Use the project's established step budget where needed.
- For full acceptance, use an explicit suite entry that imports every intended module and verify its inventory. Run each unique test once. Keep a deliberate force mode for fresh final verification.
- Reuse results during intermediate checks; do not put unconditional `--force` in the normal edit loop.
- Capture output once and inspect that file. The logs repeatedly execute the same test command separately for its summary, warning count and module test count.

Do not simply replace the script with `mylang test guest`. Directory discovery in `src/native_test_directory.zig` selects files with a `main` or the `*_test.my` naming convention; it does not enumerate arbitrary test-bearing libraries. The current main project exposes 385 tests and misses the 15 in `edits.my`. Explicit inventory is needed to preserve coverage.

## 2. Fix overly broad cache identity and source invalidation

A controlled probe used a pinned compiler, a private source copy and the same cache and environment for successive runs:

| Geometry suite, 15 tests | Wall time | Tests executed / reused |
|---|---:|---:|
| Initially empty test cache | 4.000 s | 15 / 0 |
| Warm | 0.565 s | 0 / 15 |
| Warm again | 0.340 s | 0 / 15 |
| Warm with `--force` | 1.937 s | 15 / 0 |
| Add one unused environment variable | 4.143 s | 15 / 0 |
| Restore environment, edit unrelated `png.my` comment | 0.664 s | 0 / 15 |

These are individual diagnostic observations on a shared machine, not statistical speedup estimates or historical timing replacements. [test-probes.json](test-probes.json) includes actual work counters and argv; [probe-manifest.json](probe-manifest.json) identifies the compiler and sources. The compiler was copied without its installed runtime for these small test probes; all rows share that condition.

`src/native_test_environment.zig:capture()` hashes **every inherited environment key/value**. That fingerprint selects the graph/results identity and the object/frontend cache directory (`native_test_session.zig:objectsDirectory`). Changing the unused variable `PCB_AUDIT_IRRELEVANT` made all 69 bodies check afresh and all 15 tests execute. Stable source plus a nominally identical cache path is insufficient.

Separate compiler-affecting inputs, declared guest environment inputs, and shell/harness metadata. Keep loader overrides and undeclared external effects conservative. Do not broadly ignore the environment without preserving test soundness. Record which identity component missed without logging environment values. Until then, pin the runner's environment, working directory and cache path.

Source invalidation is similarly broad: `native_test_snapshot.zig:captureExcluding()` captures all `.my` files below the entry directory; `identity()` hashes the complete inventory, and `verify()` compares it again after execution. **31 direct test-containing shell calls returned `mylang: host failure: SourceChanged`, consuming 11.6 minutes.** Some contain several attempts. This excludes documentation reads, messages and job-output reads, so it is not every occurrence.

An unrelated comment caused fresh graph preparation in the probe, although semantic test receipts correctly retained all 15 passes. During concurrent editing, an unrelated file change can instead reject the run and prevent receipt publication. Key and verify the resolved dependency/configuration closure, with explicit invalidation for resolution-affecting additions, rather than every neighboring file. Report exactly what changed. A stable snapshot with its source identity is a useful immediate workaround; the logs' repeated `/tmp/v*` copies reflect this real friction, not merely poor cache discipline.

## 3. Avoid native emission before checking the executable cache

The CLI comparison scripts repeatedly call `mylang run /tmp/vm/main.my` with different application arguments. Examples in session `ff0433af…`:

- Call 507, job `bash-176`: four CLI operations in one script; completion bounded at 510.4 seconds.
- Call 602, job `bash-179`: a larger CLI comparison matrix; settlement notice after **1,584.1 seconds (26.4 minutes)**.
- Call 732, job `bash-182`: another integration script; completion bounded at 833.8 seconds.

A background job makes the agent available for independent work; it does not make the compilation inside it faster.

The source explains why an object/executable cache is insufficient: `src/main.zig:runProjectProgram()` calls `emitMeasuredNative()` before `runNative()`. Only then does `src/native_run.zig:publish()` look up the executable by its emitted manifest. Thus an executable hit can still pay project checking, lowering and native emission.

The initial large-project probe measured **80.58 seconds in `native_emission`** before a missing LLVM adapter in the private copied installation caused `ToolNotFound`. That failed setup run is not an end-to-end performance result, but the completed emission phase is evidence of substantial work before executable lookup. After completing the copied installation, both follow-up attempts exceeded the 180-second probe budget. They do not establish a successful warm-executable baseline. [run-probes.json](run-probes.json) retains all outcomes; no end-to-end native-run speedup is claimed.

Immediate change: build the application executable once per source snapshot and run that same executable for the entire status/observe/evaluate/render/usage matrix. Compiler change: retain the emitted manifest/fragments, or look up an executable using a validated project/toolchain identity before re-emitting. Preserve dependency, policy, runtime, backend and toolchain invalidation. Profile emission itself after eliminating identical repeated emissions; faster parsing alone cannot recover this phase.

## 4. Pin a working compiler while developing its applications

The workbench sessions use the mutable `mylang/zig-out/bin/mylang` while other work rebuilds it. This is visible, not hypothetical:

- `ff0433af…:775` records a newly modified compiler rejecting `return key` with an unrelated tuple-syntax error.
- Call 785 shows the canonical/focus binaries rejecting a small probe while named older binaries print `hello`.
- Call 810 starts a loop that retries the canonical compiler up to 80 times, sleeps 20 seconds between attempts, then reruns integration checks. A 300-second job wait is already recorded at snapshot cutoff.

Pin a tested compiler installation—including QBE, the LLVM adapter and runtime assets—for a workbench development session. Upgrade at explicit checkpoints, run a smoke test, and record compiler identity with results. This avoids both changing-language failures and unrelated toolchain cache invalidation. Do not share mutable temporary snapshot paths such as `/tmp/v` among independent agents either.

## 5. Make harness waits finish with the work

All 38 sessions used `standard`, so the guidance in the local `minimal-delegation` preset was not applied. The logs contain 70 managed background starts and 75 output reads, including 64 blocking reads. Background infrastructure is already available.

There are **25 shell timeout results totaling 43.0 agent-minutes**: 23 at about 60 seconds, plus two at about 600 seconds. One 600-second call is source-arrival coordination; the other is a network probe that also waits for a server. Timeout time is not automatically recoverable time, and it overlaps the command-family totals above.

For commands expected to exceed the foreground limit, start managed jobs directly; wait on completion when dependent work is all that remains. An inner shell `timeout 600` cannot extend the tool's outer 60-second timeout. Replace file-arrival sleep loops with existing agent completion messages. Scope recursive searches before execution: filtering `.git` out of grep's output does not prevent traversing it.

Keep process exit status when trimming output. The logged compiler rejection at call 775 is followed by `exit=0` because the pipeline reports `tail`'s status. The gate also derives success from its last output line rather than preserving the compiler status. Use captured exit codes and structured test reports, then trim the saved output.

## Priority and validation targets

1. **Workbench workflow:** stable compiler/environment/cache, focused non-forced tests, one explicit exhaustive suite, one compiled executable per CLI matrix. Verify all 400 current test declarations remain represented; time the complete matrix and gate on identical sources.
2. **Compiler fast path:** move reuse ahead of whole-project native emission. An unchanged main-project run should do no new lowering/emission; measure end-to-end wall time and emitted-function counts, not just object hits.
3. **Incremental correctness and scope:** narrow environment and source invalidation without masking real inputs. An unrelated metadata variable or unreachable file edit should cause zero body/codegen/test work; a real dependency change must rerun its affected tests.
4. **Harness:** zero avoidable foreground timeouts, no source-arrival sleep polling, reliable exit status and one output collection per completion.

No historically logged test command explicitly requested `--report`, so the logs alone cannot apportion their time among semantic checking, native emission, linking and execution. Add work reports plus phase timings to the normal evidence path; aggregate root/target, filter, source/compiler identity, relevant environment digest, cache misses, execution and completion timestamps. Many job completions are bounded by the terminal read rather than a settlement notice (52 of 69 completed jobs), so do not interpret their lifetimes as exact process timings.

## Reproduction and audit changes

The reusable analyzer now discovers `session.v3.jsonl.zstd`, recognizes managed-shell timeout markers, and parses completion notices containing multiline shell scripts. Without these changes it finds no logs in this folder and misses the long `bash-179` completion. **22 focused analyzer tests pass.**

For a fresh capture, copy each source log to a fixed-size private snapshot first, as the main analyzer does. The companion makes two passes and requires immutable inputs:

```sh
python3 scripts/audit_deepseek_tools.py \
  --logs /path/to/pcb-log-snapshot \
  --project /home/epentland/ai/canopy/pcb-workbench \
  --json-output /tmp/pcb-session-metrics.json

python3 docs/audits/pcb-workbench-tool-latency-2026-09-21/analyze.py \
  /path/to/pcb-log-snapshot /tmp/pcb-audit

python3 -m unittest discover -s tests -p 'test_deepseek_tool_audit.py' -q
```

This audit changed the analyzer/tests and added evidence/report files. It did not change the compiler, workbench gate, running agents or presets. The probes used private copies; no Guardian gate was exercised.
