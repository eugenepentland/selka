# P1 decision log

## 2026-10-09 · Resume — baseline and retained evidence

- **Question:** Which source and evidence directory anchor the resumed package?
- **Options:** Start a second date directory; replace earlier results; continue the original package and preserve both stops.
- **Evidence:** `codex/concurrency-p1` fast-forwarded from `a867944a5` to requested `0ee93b396`. Local `main` remains `12bf3f60b`, already the second parent of `54eda9012`. Revision 3's launch instruction explicitly supersedes the previous stop.
- **Choice:** Continue in `experiments/concurrency-p1-2026-10-08`, putting new raw results under `r3/`. Keep `54eda9012` as the comparison baseline and backport only the measurement switch into its isolated source archive. No additional main merge is needed now. Keep old gate results labelled historical; the report's progress section describes the current run. Compress evidence without discarding outcomes if the 10 MB package cap needs it.
- **Reversibility:** Easy; evidence and source identities remain explicit.

## 2026-10-09 · P1-1 redo — measurement controls and cache identity

- **Question:** How should R9's variants and R10's switch be implemented without adding a public surface or changing baseline semantics?
- **Options:** Add CLI options; rebuild source variants; silently reuse native objects between alignments.
- **Evidence:** `src/core/driver.zig` assembles both unit and runtime clang commands; unit keys already include the runtime ABI digest, and program keys include runtime-object identities. `src/core/build_replay.zig:138` hashes the complete relevant environment, so replay already distinguishes the switch.
- **Choice:** Implement `MYLANG_CORE_LAYOUT=4|5|6` in `driver.zig`, validate it before native work, add the flag to both clang compile paths, and salt the runtime ABI with those compile options so runtime/unit/program caches all distinguish layouts. No front-end or frozen IR/ownership file changes. Build B and C as isolated source variants and retain the better five-cell geomean, as R9 requires. Existing `root_test.zig` and shared-count tests may be updated to wire/verify the new behavior; these are test-only changes within Core.
- **Reversibility:** Easy; the internal switch is opt-in and default compilation keeps its original flags and key.

## 2026-10-09 · P1-1 redo — complete corpus timing harness

- **Question:** How should CE-X's timings be repeated at all three paired layouts without modifying its or Claude's working files?
- **Options:** Modify the shared harnesses; invoke their complete multi-language builds repeatedly; use local adapters over their exact case registries and commands.
- **Evidence:** CE-X's `part3.sh` uses 10 EDA rounds, 3 Lox rounds and 9 parity rounds; the row harness uses 7 rounds and 3 startup samples. The checked-in registries yield 34 EDA cases, 26 Lox engine/script cells and 45 mylang parity arms. Earlier P1 measured only rows.
- **Choice:** Add `tools/tax_layout.py` and `tools/tax_corpora.py` within this package. Build each base/candidate at K=4,5,6, then acquire the CPU-10 lock for interleaved paired measurements, recording all samples, load, hashes, golden verification and per-alignment ratios. Include every mylang parity variant and all 26 Lox cells; no reference-language timing is needed for a compiler-against-base tax. Keep CE-X's rounds and inputs. The existing `driver_cache_test.zig` fixture verifies layout object/runtime/program/replay separation without another test module.
- **Reversibility:** Easy; harnesses and compiler variants are isolated. The initial archive setup exposed that `git apply` from inside an untracked nested archive can skip paths; explicit copies of the changed files now prepare archives before builds, and all three compilers are rebuilt before timing. No samples came from those initial builds.

## 2026-10-09 · P1-1 redo — main moved during preparation

- **Question:** Which base prevents the newly landed PM counting instrumentation from contaminating P1's comparison?
- **Options:** Keep timing the old main; compare P1 against the new main alone; merge the same main into both P1 and the original comparison baseline.
- **Evidence:** Local `main` advanced to `cafe7fea7`, adding NEW-CORE-COUNTERS-6/7 instrumentation and PM evidence. The ordinary paths are intended unchanged, but counting gates must cover the integrated tree. The merge was conflict-free.
- **Choice:** Commit the reviewable R9/R10 work as `9477f7673`, then merge main into P1 with real merge commit `42041fa45`. Build the comparison from the separate two-parent merge `94dc1c3a2` (parents `54eda9012`, `cafe7fea7`), retained as local `codex/concurrency-p1-base-r3`; it contains no P1 implementation. Its archive receives only the recorded R10 measurement backport. Rebuild all three compilers under fresh install prefixes and rerun the current step's checks. No timing was taken before this merge. The source identities are retained in `r3/source-identities.json`.
- **Reversibility:** Easy; all source and comparison commits are local and named. Neither main nor any Claude branch/worktree was modified.

## 2026-10-09 · P1-1 redo — overlap independent checks

- **Question:** Can independent correctness checks use the otherwise free gate slot while the three comparison compilers build?
- **Options:** Leave the gate idle until all timing finishes; run the full gate on variant B while its comparison binaries build.
- **Evidence:** §9.1 permits reordering, the shared wrapper admits three build jobs plus one gate, and the full Debug gate on integrated `42041fa45` completed with 88/88 steps successful and 2,100 executed tests passing (19,524 shard exclusions). No timed process was running.
- **Choice:** Retain that result as the variant-B integrated full gate. If R9 selects C, rerun it after the emitter changes. Do not overlap fuzz with the full gate or start measurements while this run's build jobs are active. The later P1-6 gate still covers the final package tree.
- **Reversibility:** Easy; a source change invalidates this checkpoint and triggers the required rerun.

## 2026-10-09 · P1-1 redo — short guest-build admission

- **Question:** Should the repeated tiny native benchmark builds pay the wrapper's five-second admission settling delay?
- **Options:** Keep that default for all jobs; bypass the wrapper; retain its slot/memory/CPU checks while setting its documented settle option to zero for tax guest builds only.
- **Evidence:** The three compiler builds completed under the defaults. Guest builds compile a few native units and hold at most the wrapper's three build slots; available memory was 16.6 GiB even with the full gate and three compiler builds. The first 36 guest builds spend much of their time waiting on the serialized settle delay.
- **Choice:** Future invocations in the two tax adapters set `MYLANG_SLOT_SETTLE=0` only on guest `mylang build` commands. They still use `scripts/build-slot.sh build`, its global slot locks, memory threshold and exclusion of timing CPUs. Compiler builds and correctness gates keep the default. Already running guest-build batches finish unchanged.
- **Reversibility:** Easy; remove the adapter's environment override. Timing is unaffected because no build is admitted during this run's timing phase.

## 2026-10-09 · P1-1 redo — choose R9 variant B

- **Question:** Which approved preserve-most slow path should remain?
- **Options:** B: one cold call for every nonplain count, including immortals; C: inline the immortal test before the same call.
- **Evidence:** CPU-10 locked, seven interleaved samples per cell at each K=4,5,6: B five-cell geomean 0.9970614425, C 0.9977732714, neither with a median cell above 1.03. B JSON/4096 is 1.02608 and JSON/64 is 1.01787; C is 1.02178 and 1.02153. `json::read_value` sizes at K=4/5/6 are baseline 7068/7052/7020 bytes, B 8061/8061/8061, C 8472/8472/8472. Full samples and every alignment ratio are in `r3/results/five-cell.json.gz` and `.md`; sizes are in `json-read-value-size.json`.
- **Choice:** Keep B, as R9 directs for the better five-cell geomean. The difference between variants is small, but no extra tie-break rule is needed. The existing full gate and fmt result cover this selected code. Continue with all 92 row cells, 34 EDA cases, 26 Lox cells and 45 parity arms, then the remaining P1-1 correctness gates.
- **Reversibility:** Easy; `r3/variant-C.patch` reproduces C against B and both compiler hashes and install paths are retained.

## 2026-10-09 · P1-1 redo — freeze evidence before fuzz

- **Question:** How should the frozen fuzz driver's clean-tree requirement handle ongoing evidence updates?
- **Options:** Bypass its clean-tree guard; defer every evidence update; checkpoint the completed evidence and keep live build logs untracked until they finish.
- **Evidence:** Qualification passed on unchanged `42041fa45` code: 509 Core tests and conformance 1518/0/0 in both modes. The first fuzz launch refused to start because report/harness edits were tracked and uncommitted; it executed no cases.
- **Choice:** Commit the completed checkpoint now, then run 9×50 followed by 9×200 without changing HEAD or tracked files. Keep currently written build logs out of the index until completed. No gate is bypassed; the qualification compiler's SHA-256 is retained and the implementation remains identical to the qualified merge.
- **Reversibility:** Easy; this changes only evidence scheduling.

## 2026-10-09 · P1-1 redo — optimized native fixtures must keep assertions

- **Question:** Why did the first isolated P1-2 thread probe exit successfully with no output and no `pthread_create` symbol?
- **Options:** Treat the empty output as a runtime bug; inspect the fixture's compiled execution; trust its zero exit status.
- **Evidence:** `zig cc -O2 -dM -E -x c /dev/null` reports `#define NDEBUG 1`. Both the earlier P1 shared-count fixture and the new isolated probe used `assert(pthread_create(...))`, so optimized compilation removed the thread creation and validation. Adding `#undef NDEBUG` before `<assert.h>` restores `pthread_create` in the binary. With live assertions the staged 8-thread probe passes cross-thread frees, retired-thread leak accounting, TLS trace/site isolation, signal masks/stacks, 8,000 serialized clock updates and 16 noninterleaved 70,001-byte print units.
- **Choice:** Add the same explicit assertion enablement to `shared_counts_test.zig` and all new native fixtures. Rerun the full gate with the real shared-count contention and saturation checks. Earlier native-C contention/TSan claims are superseded and are not evidence for final P1. The frozen fuzz matrices are independent: both 9×50 and 9×200 completed successfully with unchanged compiler/source identities before this test-only fix; compiler implementation and timing binaries did not change.
- **Reversibility:** Do not remove the assertion enablement. The isolated P1-2 prototype is still outside the package implementation and will be applied only after the P1-1 checkpoint; its tests will then be integrated into the Core suite.

## 2026-10-09 · P1-1 investigation — internal release-call preservation

- **Question:** What explains the remaining tax misses, and what should be tried before P1-2?
- **Options:** Stop at a cell miss; accept it without investigation; inspect the emitted/runtime count paths and measure a local refinement.
- **Evidence:** The complete initial B sweep gives rows 1.001778, EDA 1.029827, Lox tree 1.021800, Lox VM 1.010745, and parity 0.999173. No corpus crosses 1.03. `string_join/64` is 1.295063; disassembly shows an immortal separator released each iteration and B's helper saving nine registers before calling ordinary-convention `count_release_shared`. The selected R9 helper itself already uses preserve-most. An isolated internal preserve-most boundary reduces that outer save to RAX plus stack alignment.
- **Choice:** Test internal preservation for `count_release_shared` and a last-owner-only preserve-most free adapter. R9's emitted B/C paths and R11's CAS loops remain unchanged. Build both variants with this common runtime refinement and compare the five cells again, then examine full rows and EDA/Lox. Keep every initial failure in the report. The staged P1-2 runtime has not been adopted during this investigation.
- **Reversibility:** Easy; the experiment is an isolated archive plus `r3/helper-preservation.patch` until measured and chosen.

## 2026-10-09 · P1-1 evidence and slow-step investigation

- **Question:** How should repeated long corpus checks and the 10 MB evidence limit be handled?
- **Options:** Drop raw samples or shorten gate inputs; retain exact inputs and samples with verified compression; rerun every corpus for each diagnostic.
- **Evidence:** Recorded process samples account for 985.3 seconds of the Lox sweep and 395.7 seconds of parity, versus 152.8 for rows and 98.3 for EDA. Lox VM invocation, properties and method calls account for 275.6 seconds. These are timed workload execution under the mandated rounds, not a stuck compiler or harness. All own build jobs finished before the sweep. Raw fuzz text and repeated per-program counter JSON dominate evidence size.
- **Choice:** Keep gate workloads/rounds intact; use focused diagnostics before a changed implementation's full checkpoint. Compress completed logs/fuzz to xz, timing JSON to gzip, and aggregate decoded counter JSON into one xz archive. Verify file bytes against the source before moving unpacked copies into the private worktree cache. Preserve failure evidence and hashes. Package size at this checkpoint is 9,819,740 bytes before the updated report; further compression will precede later evidence commits.
- **Reversibility:** Easy; archives extract to original package-relative paths. Counter JSON is byte-identical to the original output; only its gzip container is removed.

The historical fuzz archives were also transcoded from gzip to xz with identical uncompressed tar bytes, and historical `.log` files were gzip-compressed with verified contents. Report links were updated and `r3/historical-recompression.json` records the tar hashes. This reduces the package to 7.78 MB and leaves room for the remaining steps without dropping evidence.

## 2026-10-09 · P1-1 investigation — adopt refined C

- **Question:** Which approved path should remain after the helper refinement, and are the misses a hard stop?
- **Options:** Keep the original B despite the newly measured refinement; use refined B; use refined C under the same R9 selection rule.
- **Evidence:** Both refined variants ran the same 92 cells, three paired layouts and seven rounds. Their R9 five-cell geomeans are B1 1.023796 and C1 1.013078, selecting C1. Full-row geomeans are 0.998804/0.996360; `string_join/64` is 1.011527/0.996833, resolving original B's 1.295063 miss. EDA improves to B1 1.015979 and C1 1.004482 (C1 has no cell above 1.03). C1 retains six row misses listed in REPORT.md. JSON `read_value` remains 8061 bytes for B1 and 8472 for C1 at each K. The internal helper experiment passes three focused shared-count tests with live assertions. The adopted C tree passes the full Debug gate (88 steps, 2101 executed tests), fmt, pre-commit qualification (510 Core tests; both conformance modes 1518/0/0), both Lox conformance modes/65 tests, EDA 310 tests/all goldens and all 132 counted/plain cells.
- **Choice:** Adopt refined C, requalify the committed implementation and run both frozen fuzz matrices, then finish its Lox/parity tax. Continue into P1-2 if no corpus exceeds the §9.1 hard stop after investigation. Do not erase initial or refined-B failures. The ordinary/refined code and R9's variant selection are both measured; none of C1–C7 or R1–R11 changes. The short-guest build settle=0 setting is also used for this repeated counted/plain build; slot/memory/CPU admission still applies.
- **Reversibility:** Easy; all three compiler hashes, the C emitter patch, the helper patch, complete samples and prior commits are retained. No frozen IR or ownership pass is edited.

## 2026-10-09 · P1-1 checkpoint — committed qualification, fuzz and evidence

- **Question:** How should source identity, lengthy admission and the evidence cap be handled before the remaining tax runs?
- **Options:** Rely only on dirty-tree qualification, bypass shared slots, or retain a committed qualification and both full matrices with verified compression.
- **Evidence:** `73737b94f` passes 510 Core tests and both 1518/0/0 conformance modes with compiler SHA-256 `29403c1f5044779991e607b4c44fa957c4f8514575b845cee4920d8a9af2c117`. Both frozen matrices are complete and qualified with source/oracles unchanged. The 50-case matrix took 210.69 s; the 200-case matrix took 733.13 s, with individual kinds 70.69–254.05 s. A separate native probe waited 597 s before obtaining a slot, then compiled and ran promptly. Another lane was using the same three build slots.
- **Choice:** Keep admission unchanged; this is queue delay, not a reason to reduce the workload. Store all six historical/current fuzz runs in one solid xz archive, preserving original package-relative paths and every member byte. Store the two resumed counter runs together, with exact decoded JSON. Retain original archives privately and record replacement hashes in `r3/evidence-archives.json`; the fuzz member manifest is `r3/fuzz-history-manifest.json.xz`. The package is 9.65 MB at this point. Later prototypes remain in ignored scratch files while C1 is measured.
- **Reversibility:** Easy: archives restore every original member; no gate or raw measurement was discarded.

## 2026-10-09 · P1-2 prototype — last-owner synchronization visible to TSan

- **Question:** Why does the first real scheduler TSan run report a race between the last owner's free-list write and another thread's release CAS?
- **Options:** Suppress the report; replace every shared release with acquire-release; acquire on the last-owner CAS instead of the trailing acquire fence.
- **Evidence:** The 8-thread million-submit prototype reports this exact edge in `.tmp/p1-task-stage/tsan-run.log`. The pinned toolchain's `lib/libtsan/tsan_interface_atomic.cpp:486–492` implements `OpFence::Atomic` with a hardware fence and `FIXME: not implemented`, without recording synchronization. The original release-RMW plus acquire-fence is the intended C11 synchronization, but this TSan cannot observe the fence. Moving the acquire to only the last-owner compare-exchange passes the same million-submit workload and three additional repeats (4.25–4.85 s each), with zero reports and zero live blocks.
- **Choice:** Carry the equivalent last-owner acquire-release CAS in the P1-2 draft. Other releases remain release CAS, retains remain relaxed, and saturation remains sticky. No suppression, annotation or sanitizer-only behavior is added. This is an implementation detail of R11's accepted CAS protocol. P1-1's selected C code and its tax binaries remain unchanged; P1-2 adoption and P1-6's binding gates will include this adjustment. Preserve the failed probe as well as the successful reruns.
- **Reversibility:** Easy at source level, but reverting would restore a known TSan reporting gap. Final acceptance still requires the full C and emitted-IR suite, 100 repetitions at eight threads.

## 2026-10-09 · P1-1 investigation — Lox VM crosses the premise boundary

- **Question:** Does refined C's Lox result permit the P1-1 checkpoint to close?
- **Options:** Pool the two engines; stop immediately; investigate the approved paths and their cold-path placement before applying the hard stop.
- **Evidence:** C1's completed sweep gives tree 0.9972673812 and VM 1.0313247132, with VM per-alignment geomeans 1.0301348688, 1.0319328087 and 1.0359049233. All goldens pass. Combining engines gives 1.0141530929 but would hide the VM failure. Static inspection of K4 `my.vm::run` gives baseline 30,451 bytes, B1 32,723 and C1 34,275; C1 adds 161 slow-call sites and its inline immortal checks increase instruction count. This is consistent across alignments, not a flaky-looking run.
- **Choice:** Treat each engine as its own corpus. Preserve this failure; compare B1 directly, and try a less extreme cold-branch weight while retaining the required unlikely slow branch, inline plain path and preserve-most ABI. The existing count branch assumes 2000:1 plain/nonplain, although immortal values also take the nonplain branch; the plan does not fix that probability. No checkpoint is declared passed, and no later prototype is adopted until the investigation resolves or reaches §9.1's hard stop. R9 still selects between B and C using the same five cells; a diagnostic on Lox alone cannot override it.
- **Reversibility:** Easy: use isolated source variants, retain patches, binaries and every measured table. No thresholds, inputs or rounds change.

## 2026-10-09 · P1-3 draft — saturation must preserve the publication invariant

- **Question:** Can the share walk stop at an immortal aggregate that saturated while still plain?
- **Options:** Walk every immortal root (including read-only literals); weaken the invariant; share a plain aggregate's descendants before making its count immortal.
- **Evidence:** The count helper currently changes a plain saturated aggregate directly to `UINT32_MAX`, although its children can still have plain counts. A later `myl_core_share(root)` must stop at that root under §4.2 and would miss its children. Shared saturation is already safe because publication has marked the graph. Literal immortals are immutable and must never be written.
- **Choice:** Prepare a cold preserve-most plain-saturation adapter that calls the same iterative share walk before storing the immortal sentinel. This establishes the existing invariant instead of changing stop-at-immortal or sticky saturation. The draft adds a separate heap-backed boundary fixture: immortal box, shared leaf, repeated publication and eight real child retain/release workers. Its two permanently live blocks are intentional and isolated from leak-free differential cases. Adoption remains part of P1-3 after the P1-1 investigation.
- **Reversibility:** Local and easy at source level; reverting would reintroduce the demonstrated publication gap. Ordinary plain counts and shared CAS semantics are unchanged.

## 2026-10-09 · P1-1 reporting — separate engine verdicts

- **Question:** How should the harness prevent a combined Lox summary from obscuring an engine failure?
- **Options:** Keep manual engine calculations only; present separate engine results alongside the combined diagnostic figure.
- **Evidence:** Refined C's combined 1.014153 figure obscures VM 1.031325. The raw files already retain every engine/script cell, so separate calculations need no new samples.
- **Choice:** The timing adapter and renderer now calculate each engine's geomean and verdict. The current comparison was already running with the earlier adapter and retains its original raw summary; its full per-cell data yields the same separate-engine calculations in the renderer. No samples or thresholds change.
- **Reversibility:** Easy; this adds explicit reporting and tightens the harness's summary to the existing per-corpus rule.


## 2026-10-09 · P1-1 investigation — select B with a 32:1 count branch

- **Question:** Does a still-unlikely, less extreme count-branch probability resolve refined C’s Lox VM premise failure?
- **Options:** Keep the 2000:1 C path; measure both approved paths at 32:1; change the R9 selection corpus.
- **Evidence:** With the common refined runtime and 32:1 probability, B2 wins the prescribed five cells: 1.0227152622 versus C2 1.0307566171. JSON read_value sizes are B2 8052/8052/8052 and C2 8466/8466/8466 bytes. Lox’s engine geomeans are B2 tree 1.0140140429 and VM 1.0165376601, below the 1.03 premise boundary; C2’s VM remains 1.0328550234. B1’s control gives tree 1.0127688215 and VM 1.0151924911. Complete samples and failures remain in count-weight-five/lox.json.gz and their rendered tables.
- **Choice:** Select B2 by R9, retaining the unlikely single preserve-most slow call and unchanged sticky CAS semantics. Complete its remaining rows/EDA/parity sweep and correctness gates before P1-2. The Lox target is still missed, with seven B2 cells above 1.03; these remain recorded for the binding P1-6 investigation. No threshold or corpus is changed.
- **Reversibility:** Easy: exact B2/C2 patches, source/compiler hashes, symbol sizes and all paired samples are retained.

## 2026-10-09 · P1-1 evidence capacity

- **Question:** How can further required gates fit beneath the package’s 10 MB evidence limit?
- **Options:** Omit historical raw evidence; keep the existing 8 MiB xz dictionary; recompress the same exact tar bytes with a 64 MiB dictionary.
- **Evidence:** Verified decompression equality reduces fuzz-history.tar.xz from 4,945,788 to 4,224,712 bytes and counter-history.tar.xz from 1,090,692 to 1,054,960. Completed probability-run JSON is also gzip-compressed without changing samples. The package is 8,925,908 bytes before this entry. Compression completed before this lane’s next timing started.
- **Choice:** Retain the smaller archives, record old/new compressed hashes and uncompressed tar hashes in evidence-archives.json, and keep originals in the private cache. No raw gate output is removed.
- **Reversibility:** Exact decompressed bytes and original containers remain available.

## 2026-10-09 · P1-4/P2-0 draft — exact range-item trap sites

- **Question:** How does a generated range thunk report the actual failing item after its first iteration?
- **Options:** Report only the submitted range start; add a Core IR operation; use an internal runtime helper from existing ordinary calls.
- **Evidence:** P2-0’s range proof loops over several items, while the submit ABI captures only the range’s starting item. A failure at item 17 in a range starting at 16 would otherwise name 16. Section 3.4 requires the actual map item, and R5 requires the exact unknown-site fallback.
- **Choice:** Add the internal `myl_core_task_item(index)` helper in the scheduler draft; generated range thunks call it before each body. Existing nested-task context save/restore also preserves the cursor. Known map sites use `in parallel.map item N at PATH:LINE:COL`; unknown sites retain `in task submitted at <unknown>` with the item appended. Plain submits pass −1. Prepare an emitted-IR trap test for item 17 at 1/2/8 threads, including the multi-item range case. This completes the existing semantics without changing frozen IR/front-end files. Adoption/validation remains pending.
- **Reversibility:** A local ABI addition, easy to change before P2 lowering; omitting an equivalent cursor update would leave the required report incorrect.

## 2026-10-09 · P1-1 checkpoint — continue with B2 after complete tax investigation

- **Question:** Should the early performance investigation continue after B2 resolves the premise failure but misses the target?
- **Options:** Spend the remainder of the roughly six-hour allowance tuning code that P1-2 will change; stop despite §5’s checkpoint rule; retain measured misses and proceed to correctness/P1-2.
- **Evidence:** Complete B2 results are rows 0.9990390412 (five cell misses), EDA 1.0207970965 (one), Lox tree 1.0140140429 (three), Lox VM 1.0165376601 (four), parity 1.0005911305 (none). All outputs/checksums match. The investigation tried both approved count paths, internal helper preservation and the revised count probability; B2 wins R9’s five-cell criterion. No selected corpus exceeds 1.03. The EDA sweep also waited for another lane’s CPU-10 lock; rounds were not shortened.
- **Choice:** Adopt the exact measured B2 emitter, retain all target misses, rerun correctness and then continue into P1-2. The investigation is bounded by “up to” about six hours, not a requirement to consume it; P1-6 will investigate the final runtime’s binding measurements. Compiler source equivalence was checked against the isolated archive, with only the alternative emitter and older test source differing.
- **Reversibility:** Easy through the retained commits/patches/compiler identities. This accepts only an early checkpoint miss, not a final target pass.

Guardian’s whole-tree commit check caught that SHARED-COUNTS-1 still described the C alternative’s inline immortal skip after B2 adoption. The specification now describes the measured B path’s single slow call, including immortals; existing tests already exercise those calls on read-only literals and live shared counts. The change-classification gate is rerun without exemptions.


## 2026-10-09 — P1-1: close B2 correctness and preserve evidence

- **Question:** How should a qualification launch collision and the growing evidence bundle be handled?
- **Options:** Delete the older private qualification state, retry under a unique name, or weaken/skip qualification. For evidence, retain separate compressed runs or consolidate exact bytes.
- **Evidence:** The generic `qualify` basename collided with `.mylang-cache/s5/integration-qualify/qualify/tmp` before compilation. The unique retry passed 510 Core tests and both 1518/0/0 conformance modes. At `9c2559a45`, full Debug is 88/88 with 2,101 tests; frozen 9×50 and 9×200 matrices are qualified, complete and source/oracle-stable. Lox, EDA, parity and all 132 counted/plain cells pass.
- **Choice:** Keep the failed launch, use a tag-specific qualification name in `tools/checkpoint.py`, and explicitly pass the committed source identity to fuzz. Consolidate the two new fuzz runs and B2 counters into existing archives, verifying every decoded member before moving unpacked copies into this worktree's private cache. Compress verbose logs losslessly. No tests, samples or failure evidence are discarded. This experiment helper is outside the runtime expected list and changes orchestration only.
- **Reversal:** Easy; original bytes and manifests are retained.

## 2026-10-09 — P1-2: preserve the main stack guard during lazy pool startup

- **Question:** Should lazy pool startup reinstall the main thread's stack-floor handler?
- **Options:** Remap the signal stack and remeasure the current frame, or make the startup-only installation idempotent.
- **Evidence:** Review found that a second `core_floor_install` leaked its earlier 256 KiB alternate stack and reset the approximate main stack top at the deeper first-submit frame. The isolated native fixture verifies that a repeated installation preserves both the alternate-stack pointer and main stack top; all six thread-runtime tests pass.
- **Choice:** Add a startup-only `core_floor_ready` flag. Worker installation remains per-thread. This is included when P1-2 is adopted and changes no accepted concurrency semantics.
- **Reversal:** Small local change, but restoring repeated installation would restore the defect.

## 2026-10-09 — P1-5 preparation: salt foreign-object manifests for TSan

- **Question:** How should the internal sanitizer switch separate foreign C objects?
- **Options:** Rely on the runtime ABI salt, or include sanitizer compile arguments in the independent foreign-source manifest key.
- **Evidence:** The isolated integration's cache regression expected four units plus runtime, foreign source and link processes (seven); the sanitized build ran only six. `driver.zig:foreignKey` hashes its own settings without the runtime ABI. Its stale foreign object was reused even though the compile path accepted `-fsanitize=thread`. The other nine emitted-code tests passed, including actual LLVM TSan and task/map error locations.
- **Choice:** Hash sanitizer arguments directly in `foreignKey`; preserve the strict regression. The focused rerun passes, including ordinary-to-sanitized-to-ordinary reuse and rejection of invalid switch values. Adopt with P1-5, not as an untested production change.
- **Reversal:** Easy; cache entries naturally separate by key.


## 2026-10-09 — P1-4/P1-5: keep stress coverage within the existing memory allowance

- **Question:** How should the million-submit sanitizer stress fit the existing 1 GiB test-process allowance?
- **Options:** Increase the allowance, reduce submissions, or join bounded groups while preserving the complete submission count and nesting tests.
- **Evidence:** The isolated one-group run passed all assertions with zero TSan reports but Zig reported 1,961,353,216 bytes peak RSS, above 1,073,741,824. The process returned success despite that diagnostic, so it is not accepted as a clean gate. One hundred groups of 10,000 preserve a million simple submits, plus 10,000 dropped-group tasks, binary depth 12, chain depth 2,048, repeated result ownership and post-close results. The rerun passes at 578 MiB reported RSS with zero reports.
- **Choice:** Batch the fixture's million submissions; leave runtime behavior and the memory allowance unchanged. Preserve both logs. Each group still exercises growth and shared environments, and the ordinary 1/2/8 matrix will use the same fixture.
- **Reversal:** Easy, but a single million-result group requires more sanitizer metadata than the existing allowance permits.

## 2026-10-09 — P1 evidence: lossless compression choices

- **Question:** How can all historical evidence fit the unchanged 10 MB package limit?
- **Options:** Discard cases (rejected), increase xz's dictionary, chunk large files, or compress remaining verbose text.
- **Evidence:** Eight complete fuzz matrices contain about 320 MB of raw files. Corresponding-path ordering with a 128 MiB xz dictionary reduced their archive from 5.79 to 5.24 MB. A byte-verified 64 KiB chunk experiment was worse at 5.60 MB and was not adopted.
- **Choice:** Keep a standard tar.xz with original paths and byte-verified members. Losslessly gzip remaining qualification logs and xz large timing JSON, preserving the rendered per-cell tables and raw sample bytes. Original copies remain in this worktree's private cache; references use the new extensions.
- **Reversal:** Standard gzip/xz tools recover exact originals. No cases, failures or measurements are discarded.


## 2026-10-09 — P1-2: adopt per-thread runtime state

- **Question:** How should the existing inline allocator, output and counters retain their single-threaded behavior while becoming safe for tasks?
- **Options:** Lock every fast-path operation or keep per-thread mutable state with narrow shared synchronization. Use initial-exec TLS provisionally, comparing local-exec before final selection.
- **Evidence:** The adopted runtime passes 18 focused thread/shared-count/counting tests. Eight real workers exercise cross-thread frees, retired-thread leak accounting, private traces and sites, signal masks/stacks, 8,000 provider clock operations, and sixteen indivisible 70,001-byte print units. Fatal fixtures verify a single winner, held-provider-lock avoidance, bounded stream-lock fallback, and worker stack-floor reporting. Dynamic print options preserve `1|2!`.
- **Choice:** Move allocation cursors/free lists, traces, sites, stack metadata, text counters and counting slots into TLS. A persistent pthread-key registry snapshots retired free lists and sums only after quiescence. Shared heap/live-byte accounting uses atomics; provider operations use one IO mutex. Output stages complete units after pool start; fatal handling has a bounded try-lock/raw-fd fallback and skips IO/Host cleanup. Preserve startup behavior and the selected B2 emitter. Adopt the previously logged last-owner acquire CAS and idempotent main stack installation.
- **Files outside the expected list:** `src/core/build_cap.zig` wraps dynamic print writes in begin/end helpers after evaluating arguments, so one print remains one output unit. `src/core/root_test.zig` imports the new focused tests. `src/core/driver.zig` adds pthread runtime compile/link flags (the plan permits flags wherever assembled). No front-end, `ir.zig`, `own.zig` or Host implementation changes.
- **Reversal:** Local to the runtime/emitter and internal builder; TLS-model selection remains reversible and will be measured using committed source archives.


## 2026-10-09 — P1-3: one child iterator for publication and destruction

- **Question:** How should sharing cover every managed edge without diverging from destruction?
- **Options:** Maintain separate walks per block kind or share one callback-based child enumeration with independent share/release worklists.
- **Evidence:** The isolated differential fixture checks explicit edge multiplicities and ownership decrements for aliases, nested union guards, dictionary tombstones, boxed views, IO authority/resource/provider pairs, nulls and read-only immortals. A 100,000-deep graph is marked and freed iteratively, with exactly 100,033 marks overall and no managed leak. The separate plain-saturation fixture marks its two blocks (128 bytes) before eight threads retain/release the immortal root's child.
- **Choice:** Use one iterator; keep dictionary storage finalization after its children are enumerated and provider pair release in the iterator. Mark each plain block before queuing it, stopping at already shared/immortal values. Adopt the previously logged saturation adapter so later publication can safely stop at an immortal aggregate.
- **Files:** `native_fixture.zig` is shared test support; `root_test.zig` imports the new tests. Runtime dictionary/IO changes are precisely the permitted common child enumeration and finalization changes. No frozen file changes.
- **Reversal:** Local and reversible, but independent walks would require duplicating the verified edge rules.


## 2026-10-09 — P1-3: satisfy whole-tree fixture checks at the step boundary

- **Question:** How should shared fixture support be introduced before its P1-5 export consumer exists?
- **Options:** Add an artificial use/exemption, or introduce the export method with its real later consumer and fix initialization cleanup now.
- **Evidence:** The whole-tree commit gate caught `dead-pub` on `native_fixture.exportBinary` and `errdefer-in-init` on the environment map in `Fixture.init`. Focused build gates were diff-scoped and did not cover that newly staged file until commit.
- **Choice:** Defer the export method to P1-5, where sanitizer repetitions use it; add `errdefer environment.deinit()` after constructing the environment. No exemptions or dummy references. Retain the failed commit-gate log and rerun focused tests/formatting after the helper change.
- **Reversal:** Easy; the export method is already staged for its actual consumer.


## 2026-10-09 — P1-4: scheduler implementation and ABI bridge

- **Question:** Which concrete queue, wait, lifetime and bridge details implement the accepted fork/join design?
- **Options:** Recursive blocking waits or helping waits; reclaim resized deque rings eagerly or keep old rings until process exit; LLVM linkonce_odr or an externally retained weak definition for the bridge.
- **Evidence:** Native tests at 1/2/8 threads pass 1,010,000 simple submits, binary nesting depth 12, a 2,048-level chain, waits with work on the caller's own deque, repeated results after group release, and zero live blocks. Separate modes verify no workers for empty groups, budget-forced sequential execution and rejection of batch-parent start/post-pool fork. Isolated actual LLVM tests prove the C-to-fastcc call path and exact range-item reporting; production integration follows in P1-5.
- **Choice:** Use Chase–Lev deques with atomic slots, signed indices, retained old rings, round-robin victims, 32 bounded search spins and futex epochs sampled before completion/search. Wake on both enqueue and completion. The first submit starts N−1 workers with inherited stack limits, guard pages and SIGALRM blocked. One-thread tasks borrow their environment synchronously; parallel tasks share/retain it and publish a shared result with release/acquire. Group-owned handle lists keep queued tasks alive; close and finalization join before release. Global pending reaches zero only after per-thread runtime writes, providing the report barrier.
- **Bridge:** `weak_odr hidden` survives LLVM dead stripping when only the separately compiled C runtime calls it, and still merges across units. Native-only C fixtures supply an explicit C adapter; actual IR tests exercise the real fastcc bridge. No IR vocabulary change.
- **Files:** `src/core/driver.zig` includes the new runtime asset; existing native fixtures receive C adapters and `root_test.zig` imports scheduler tests. These integration/test changes are allowed outside the runtime expected list and do not touch the front end or ownership pass.
- **Reversal:** Private runtime details are reversible. Memory ordering, task lifetime, fork guards and the bridge must preserve the tested semantics.


## 2026-10-09 — P1-4/P1-5: pass test allocators through fixture helpers

- **Question:** How should the stress and emitted-IR matrix helpers allocate their arenas?
- **Options:** Use a hardcoded testing allocator inside a helper or pass the allocator from each test body.
- **Evidence:** The P1-4 whole-tree commit gate rejected `task_scheduler_test.matrix` under `allocator-hygiene`; review found the same pattern in P1-5's matrix/fatal helpers.
- **Choice:** Pass `std.mem.Allocator` from the actual test blocks to each helper. Preserve the failed gate and rerun the affected matrix. No allocator exemption or test reduction.
- **Reversal:** Straightforward, but the explicit dependency is the repository's required style.


## 2026-10-09 — P1-5: real emitted-code instrumentation and repeated evidence

- **Question:** How can the final sanitizer gate cover guest code as well as C without changing frozen Core IR?
- **Options:** Instrument only C, or add LLVM sanitize_thread attributes to every definition and link the matching sanitizer runtime.
- **Evidence:** The integrated 11-test matrix passes actual fastcc mixed captures/results, parent copy-on-write, repeated results, counted/verified ownership at 1/2/8 threads, ordered range results, submission-PC/unknown-site reports, exact failing map item 17, actual LLVM TSan and the million-submit native TSan fixture. The foreign-cache regression previously exposed and fixed an independent missing sanitizer salt.
- **Choice:** Add the validated internal `MYLANG_CORE_SANITIZE=thread` switch in `driver.zig`, instrument emitted LLVM and C, and salt all relevant cache layers. Keep invalid values fatal before compilation. Restore `native_fixture.exportBinary` with its real P1-5 consumer. Export exact tested binaries through an experiment-only environment variable and use `tools/repeat_tsan.py` to record all 100 repetitions for each of native stress, mixed captures and range tasks at eight threads, including stdout, stderr, status and hashes. No suppressions, retries or sanitizer-only runtime behavior.
- **Files outside the expected list:** `driver_cache_test.zig` verifies independent object/replay cache separation; `root_test.zig` imports the tests; experiment helpers record outcomes. `tools/inventory.py` gains an output argument so final review preserves P1-0's original inventory. The sanitizer text helper and hand-built IR fixtures are new Core test/support files. No front-end, `ir.zig` or `own.zig` edit is needed.
- **Reversal:** Internal build/test machinery is reversible. The 100-repetition gate remains pending until its recorded run completes.


## 2026-10-09 — P1-5: format the emitter test options explicitly

- **Question:** How should the new test's 257-character emitter call satisfy Guardian's 240-character hard limit?
- **Options:** Exempt the line or split the options initializer.
- **Evidence:** The whole-tree commit gate rejected only `task_ir_test.zig:31` under `line-length`; behavioral tests were green.
- **Choice:** Expand the initializer across lines and rerun fmt. No behavioral change or exemption.
- **Reversal:** Formatting only.


## 2026-10-09 — P1-2: select local-exec TLS from the paired row sweep

- **Question:** Does this executable runtime benefit from initial-exec or local-exec TLS?
- **Options:** Keep provisional initial-exec or use local-exec in both LLVM declarations and the C macro.
- **Evidence:** Both ReleaseFast source archives match all 569 `src` files of `9d2524f5e`, except the three intended TLS-model replacements. All 92 row/size cells ran in paired K=4/5/6 batches, with matching checksums, CPU 10 locked and no own concurrent builds. Initial-exec/base GM is **1.0150306005** (20 cells >1.03); local-exec/base is **1.0124433780** (18 cells >1.03). Direct paired LE/IE GM is **0.9979028166**. One-minute load spans 0.47–1.98. Neither arm passes the tax target; all raw samples and per-alignment cells are retained.
- **Choice:** Select local-exec for this statically owned executable runtime, changing both emitters and `MYL_TLS` together. This completes the required TLS comparison; P1-6 measures the final shared-walk/scheduler runtime again and investigates remaining misses. `tools/layout_table.py` now reads xz as well as gzip so the compressed historical evidence remains renderable; no metric changed.
- **Reversal:** A three-file substitution; the complete initial-exec comparison remains available.


## 2026-10-09 — P1-6 preparation: complete package review and preserve inventory identities

- **Question:** Is the integrated runtime ready for final qualification and binding measurement?
- **Options:** Rely on focused tests alone or recheck all count/global/fatal paths against the original inventory and revisions.
- **Evidence:** SELF-REVIEW.md covers every original static-state family and the new scheduler/registry/counter state. A fresh typed AST lists 128 static declarations and exactly 8 managed-count access lines, all confined to helpers, initialization and sharing. The native object compile passes; the known pinned AST-wrapper FileNotFound diagnostic is retained. Local-exec integration passes 15 thread/share/emitted-IR/TSan tests and fmt. The read-only P2-0 analysis has executable capture/range proofs and identifies no IR or ownership-pass gap.
- **Choice:** Proceed to the full final gates and binding tax, keeping exact runtime-file hashes and the three-file source diff hash in the fresh inventory. Preserve P1-0's inventory. Fix repeated `.gz` suffixes introduced during report-link compression. P2-0 remains analysis only; P2 is not started.
- **Reversal:** Documentation/evidence changes are reversible; any new correctness finding must still be fixed and regated before timing counts.


## 2026-10-09 — P1-2 TLS closeout: record the selected model in the runtime spec

- **Question:** Where should the final C/LLVM TLS model choice be recorded with its emitter change?
- **Options:** Treat it as report-only metadata or make the runtime spec state the actual selected model.
- **Evidence:** The whole-tree commit gate's change-classification check required a same-change spec/test update for the TLS declarations; the 15 focused tests and paired measurements were already green/recorded.
- **Choice:** Add local-exec to the existing RUNTIME-THREADS-1 contract, matching the implementation and measured selection. Preserve the rejected commit log. No test exemption or artificial coverage.
- **Reversal:** Documentation follows any later measured model change.


## 2026-10-09 — P1-6: repair the remaining native-only task bridges

- **Question:** Why did the first final Debug gate fail two older allocator/ownership fixtures?
- **Options:** Weaken the runtime bridge dependency, or supply the explicit C adapter required by native-only harnesses.
- **Evidence:** P1-final-01 passed 2,119 executed tests but failed both C harness links in `src/core/own_test.zig` with undefined `myl_core_task_call`. Those harnesses include the runtime without any emitted LLVM unit. All emitted-code and scheduler tests passed. The two focused repaired tests pass, including the million-deep iterative release and allocator live-count assertions.
- **Choice:** Add the same C-only adapter used by the new native fixtures to both older harnesses. `own_test.zig` is a test outside the expected list; the forbidden `own.zig` is untouched. Preserve the failed full-gate log and rerun the full gate/qualification/frozen matrices on a fresh committed head. Production sources are byte-identical to f4eb26606, so retain that ReleaseFast compiler and its external results with explicit source equivalence.
- **Infrastructure:** The scratch external-build orchestrator also used an invalid `--corpus` argument; preserve its status-2 log, then resume the three corpus builds with the documented positional argument. All 132 counted/plain comparisons, Lox conformance/65 port tests and EDA 310 tests already passed. No timing or gate was waived.
- **Reversal:** Test linkage and orchestration corrections only; no runtime/ABI behavior changes.


## 2026-10-09 — P1-6: assert native fixture link and execution status

- **Question:** How should the older native fixture tests verify their required runtime linkage?
- **Options:** Continue inferring success from stderr/stdout, or assert both compiler and executable exit status explicitly.
- **Evidence:** Guardian rejected the first bridge-only test-file change under change-classification because it changed fixture constants outside a tagged test body. Review found that both old harness tests checked output without explicit successful exit status.
- **Choice:** Assert successful linking, successful execution and empty execution stderr in both harness paths, including the existing NEW-CORE-RC-6 tagged test. Preserve the rejected gate log and rerun the two substantive tests and fmt. No dummy assertion or spec exemption.
- **Reversal:** Test strengthening only.


## 2026-10-09 — P1-6: qualify the repaired tree and begin binding timing

- **Question:** Which implementation and compiler identity does the binding tax measure?
- **Options:** Rebuild the identical production compiler after a test-only change, or prove production-source equality and retain the already validated ReleaseFast binary.
- **Evidence:** At `98cb3a49f`, full Debug is 88/88, fmt passes, qualification is 530 Core tests plus conformance 1518/0/0 twice, and both frozen 9×50/9×200 matrices are complete with unchanged source/oracles. All 300 actual native/emitted TSan executions pass at eight threads, with zero reports/leaks and exact output. The only source difference from the ReleaseFast compiler's f4eb26606 tree is the two repaired old C harnesses in own_test.zig; all 577 other source files are byte-identical. External checks and all 132 counted/plain cells passed.
- **Choice:** Retain the compiler and prebuilt K=4/5/6 binaries, with their original source/hash identities and explicit source-equivalence metadata. Start timing only after correctness, sanitizer stress and evidence packing finish; no own builds or stress run beside timing. Every corpus remains mandatory and both Lox engines have separate verdicts.
- **Reversal:** A new production change requires rebuilding and regating; test-only source equivalence does not excuse a runtime change.


## 2026-10-09 — P1-6: investigate allocation and child-traversal overhead

- **Question:** Which added runtime work explains the final row/EDA target misses?
- **Options:** Accept the measured misses after investigation, specialize the shared source iterator at compile time, or additionally remove repeated registration calls and locked accounting before workers exist.
- **Evidence:** The initial binding sweep gives rows GM 1.0246636851 (25 cells above 1.03) and EDA GM 1.0269590951 (11 misses). Allocation-retained rows are 1.242857/1.224735, split rows 1.205813/1.199199. Final code calls the generic child visitor out of line and calls core_thread_register on every small runtime allocation; K=5 block_alloc grew from 389 to 554 bytes. Every carved/large allocation also uses a locked live_blocks increment, even before the pool exists. Lox/parity measurements are still running and will be retained before any new builds.
- **Choice:** Prepare two private, source-pinned candidates: A forces compile-time specialization of the common child iterator/release visitor; B additionally makes registration's TLS check inline with a cold preserve-most initializer and uses atomic load/store for live accounting before pool startup, retaining atomic RMW after startup. The scheduler publishes core_pool_started before pthread_create, and the native multi-thread runtime fixture does likewise. Keep the same atomic object and exact accounting; heap ceilings and shared counts are unchanged. Measure both after the current sweep, then choose from all-corpus evidence and rerun final correctness for any adopted runtime change. Production remains unchanged until that choice.
- **Reversal:** Local runtime-only changes; no frozen file, accepted semantic, threshold or gate is altered. The common child enumeration remains one source of truth despite inlining.


## 2026-10-09 — P1-6: retain all fuzz and counter evidence below the package limit

- **Question:** How can all historical and final raw outcomes fit within the 10 MB package budget?
- **Options:** Drop duplicate historical successes, or use a reversible representation before solid compression.
- **Evidence:** Decoding base64 stdout/stderr and packing exact elapsed doubles reduced the eight historical matrices from 5,239,092 to 3,846,964 bytes; all 214,000 original command records and 9,304 original members round-tripped byte for byte. With both final matrices, the archive is 4,780,592 bytes for 11,630 members / 391,496,600 original bytes. All restored SHA-256 values match. The merged counter archive retains 528 original JSON documents in 1,101,700 bytes.
- **Choice:** Retain every matrix and outcome; mark transformed command members `.decoded` and supply tools/fuzz_archive.py to restore exact original files. Preserve per-member hashes in xz manifests, verification metadata and the archive ledger. Move unpacked final evidence and prior archives into this worktree's private disk cache after verification. Timing JSON is compressed losslessly and its readable tables regenerated. EVIDENCE.md documents extraction. No gate or sample is removed.
- **Reversal:** The supplied decoder reconstructs exact original bytes; earlier archive versions and unpacked final evidence also remain in the private cache.


## 2026-10-09 — P1-6: separate dictionary inlining from the allocation improvements

- **Question:** Does forcing dictionary traversal into the free/share callers explain the EDA regression?
- **Options:** Keep all iterator inlining, leave only the dictionary traversal out of line, or retain the original traversal structure with the allocation improvements alone.
- **Evidence:** The paired A/B sweep gives row GM 1.0146208208 for A and 1.0065124883 for B, versus the original final 1.0246636851. EDA instead worsens to 1.0625164386 / 1.0315034862, versus the original 1.0269590951. Both candidates pass 20 focused ownership/thread/share/scheduler/IR/TSan tests. The K=5 free routine grows from 620 to 1,015 bytes when the generic and dictionary loops are forcibly inlined. A/B are unadopted experiments; their remaining corpus results will also be preserved.
- **Choice:** Prepare C with B's allocation changes and inline generic/release traversal but an ordinary dictionary iterator; prepare D with B's allocation changes and the original traversal structure. Build only after A/B timing finishes, test both, then compare every corpus against the same base. These are final-runtime candidates, distinct from R9's earlier emitted-count variants: all retain the selected B2 emitter.
- **Reversal:** Local runtime changes; no source semantics, count ordering, frozen file or threshold changes. A candidate above the 1.03 premise boundary is not adopted while this investigation is in progress.


## 2026-10-09 — P1-6: consolidate completed logs without losing failure detail

- **Question:** How should verbose repeated gate/build logs fit alongside every timing table and fuzz matrix?
- **Options:** Keep independent gzip layers, discard historical success logs, or compress decoded logs together.
- **Evidence:** The first probe reduced 524 completed logs from 1,606,542 stored bytes to a 119,172-byte tar.xz while preserving all 3,480,688 decoded bytes. The subsequent consolidation also includes completed A/B logs, with every original and decoded hash checked. Active C/D logs are excluded. An additional command-interleaving fuzz probe saved only 125,548 bytes and was rejected to keep the existing decoder simple.
- **Choice:** Use a standard log archive and explicit path/hash manifest; retain complete failed logs and original unpacked files in the private cache. Markdown links point to the archive, and EVIDENCE.md explains original-member lookup. Preserve the existing v1 fuzz encoding, already verified byte for byte.
- **Reversal:** Extract the standard tar for original log text; prior storage-layer hashes and private originals are retained.


## 2026-10-09 — P1-6: reference committed historical raw fuzz evidence

- **Question:** How can final candidate validation fit below 10 MB without losing the earlier raw evidence?
- **Options:** Add a more complex compression format, discard old raw data, or reference the already committed immutable archive for superseded successful matrices.
- **Evidence:** The working package reached 9,919,627 bytes before the next final validation. The simple interleaving probe saved only 125,548 bytes. Commit `98cb3a49fff3ba4ad438cb9087f86aa517a32760` already contains the complete eight historical matrices in a 5,239,092-byte archive with SHA-256 `d250c551b5d8c2e23124534bbe3f61e709bf4f0ecf370871bad68535a354faad`. Every one of the 9,072 referenced raw/source members was checked against that object. The current archive retains every historical summary/manifest plus complete P1-final-02 raw evidence, with 2,558 verified members in 1,378,596 bytes, saving 3,401,996 bytes.
- **Choice:** Record the exact Git object, member hashes and restore command in EVIDENCE.md and the archive ledger. Keep all failed measurements and the current final raw evidence in the working package. This supersedes the earlier storage choice to duplicate all historical raw streams in its current archive; no gate, outcome or recoverable evidence is removed. Additional final validation will be stored in full.
- **Reversal:** Restore the ordinary tar archive directly with git show; complete ten-matrix copies also remain in the private disk cache.


## 2026-10-09 — P1-6: hoist redundant allocator registration checks

- **Question:** Can the remaining allocation-heavy misses be reduced without changing the common traversal semantics?
- **Options:** Keep C/D unchanged, tune unrelated emitted code again, or remove redundant TLS registration checks where registration is already established.
- **Evidence:** The C/D row comparison gives C GM 1.0027158207 with 12 cells above 1.03, and D GM 1.0124092025 with 17. C still has allocation-retained/64 at 1.106406; D is 1.175115/1.158536 on retained allocation. EDA favors D (1.0013986091; full pass) over C (1.0190069662; no cell >1.03). small_alloc checks registration even on a populated free list; the iterative destructor checks it again for every block. All writes that populate a list already register the owning thread, and scheduler workers register before guest code.
- **Choice:** Prepare E from D and F from C. Pop a nonempty free list before the registration check; register once at iterative destruction entry and use a private already-registered free helper within that walk. Other free callers retain their registration wrapper. Preserve exact accounting, cold initialization, child enumeration and synchronization. Queue builds only after all C/D timing completes, then run focused tests and every paired corpus. This is the last planned runtime optimization round unless it exposes a correctness issue or a premise violation.
- **Reversal:** Runtime-only source patches from the same immutable source. Existing candidates remain recoverable, and no candidate is adopted until complete corpus comparison and fresh final qualification.


## 2026-10-09 — P1-6: preserve counter instrumentation through the free-helper split

- **Question:** Does the registered-free helper preserve every counting hook?
- **Options:** Leave the old textual anchor, or update it to the common helper that still executes every actual free.
- **Evidence:** `src/core/count_runtime.zig` inserts `myl_count_free` immediately after the old block_free declaration and class computation. The E/F split moves that body into block_free_registered; the old anchor would correctly fail with AnchorMissing, and instrumenting only the wrapper would miss iterative frees.
- **Choice:** Include the one-line anchor rename in both private candidates and explicitly run the existing test that requires every hook exactly once and rejects moved anchors. Counted thread and emitted-capture tests remain mandatory. This was caught in source review before E/F compilation; the waiting build orchestrator was restarted with both changed source paths in its identity proof.
- **Reversal:** The anchor follows the selected function name; all counting behavior and slots are unchanged.


## 2026-10-09 — P1-6: reclaim rejected candidate source archives

- **Question:** How should final validation retain sufficient disk headroom after repeated compiler archives?
- **Options:** Remove shared caches or other lanes, retain every reconstructible private copy, or remove only completed rejected candidate copies.
- **Evidence:** E/F preparation reduced free disk to about 8.2 GiB. The A/B source archives occupy about 1.4 GiB each, are not worktrees, have no active process, and are reconstructible from immutable `98cb3a49f` plus their retained patches. Both are rejected by their EDA results. Their compiler binaries still match the recorded hashes.
- **Choice:** Delete only the A/B private source directories after verifying their runtime bytes and compiler identities. Retain all raw measurements, logs, patches, source identities and measured binaries. The earlier A–D local build-cache cleanup also touched only these private completed builds.
- **Reversal:** Recreate either archive from Git and apply its checked-in patch; no source or evidence depends on the deleted cache.


## 2026-10-09 — P1-6: verify positive live accounting, not only final zero

- **Question:** What regression check distinguishes correct parallel accounting from equal lost increments and decrements?
- **Options:** Rely on final leak-zero checks, or also inspect an exact positive count while every worker is paused.
- **Evidence:** The existing runtime fixture checks 18 counted allocations/frees and zero live blocks after eight worker retirements. Atomic load/store pairs could legally evade TSan while losing concurrent updates, and equal lost increments/decrements could cancel at exit. The selected allocation refinement retains RMW after pool publication, so this boundary deserves a direct invariant check.
- **Choice:** Prepare a native accounting mode with eight workers holding 128 alternating small/large blocks each. Two nine-party barriers let main verify baseline + 1,024 before any free, baseline after retirement, then zero after releasing the two capability blocks. Its counted test requires exactly 1,026 allocations/frees and zero live bytes. The ordinary fixture additionally checks its eight outstanding transferred blocks. Adopt these tests with the selected runtime and run them in its fresh checkpoint; they are not yet claimed as passed.
- **Reversal:** Test-only strengthening; no product behavior or benchmark changes.


## 2026-10-09 — P1-6: one final targeted check of the remaining per-block free call

- **Question:** Is the remaining out-of-line free call avoidable in the specialized iterative destructor?
- **Options:** End the investigation with C/D/E as available alternatives, or make one small follow-up to the failed F experiment based on its generated assembly.
- **Evidence:** F improves row GM to 1.0006356946 with eight misses, but EDA reaches 1.0302100374 with 16 misses, so F is ineligible for adoption. K=5 disassembly shows both C and F still call a separate free helper once per destroyed block. F's already-registered helper is 154 bytes; it remains out of line in the cold walk. Its ordinary registration wrapper already incorporates the helper body. The call is a remaining deallocation cost, not proof of EDA's regression cause. C and D remain below 1.03 in all corpora.
- **Choice:** Prepare only G: F with the private already-registered helper forced inline, and its counting anchor updated to the attributed declaration. Preserve the same registration and accounting invariants. This is the one follow-up justified by F's premise-boundary failure and assembly evidence after the previously planned final round. Build after E/F timing, run the same 21 focused tests and every paired corpus, then choose an eligible measured runtime and finish qualification. No further performance variant is planned; targets and failure evidence are unchanged.
- **Reversal:** Two source files in a private archive; C/D remain valid fallbacks and no production source has changed.

## 2026-10-09 — P1-6: integrate main and honor the user's performance waiver

- **Question:** Main advanced from `cafe7fea7` to `35df839be` during the last runtime experiment. The user asked: “Could you merge in without redoing the performance checks, or come up with some proxy that doesn't depend on the hardware being idle?”
- **Options:** Repeat the complete timed suite after integration; use hardware-independent evidence; or retain completed historical timings with an explicit unverified final performance verdict.
- **Evidence:** Candidate C completed all five old-base corpora below the 1.03 premise boundary, although rows, EDA, parity and Lox tree miss strict targets. Candidate G finished only rows and EDA before main moved. Its own parity orchestration was terminated (status -15), and Lox never began. No other lane's processes were stopped.
- **Choice:** The user's direct instruction supersedes the plan's mandatory repeated timing gate and corresponding §9.1 gate-relaxation stop. Merge main with a real merge commit, adopt the simpler, fully measured candidate C, and run all final correctness gates. Do not schedule another timed suite or wait for idle hardware. Retain all earlier timings, including partial G, as historical evidence. Use exact counted/plain outputs, allocation counts and generated-code invariants as deterministic proxies; these cannot certify elapsed-time overhead. Report merged-version performance as unverified, never as a passed tax gate.
- **Reversal:** Easy: the timing tools, inputs, earlier raw evidence and candidate patches remain available for a later explicitly requested measurement. No numeric threshold is changed.

## 2026-10-09 — main integration: preserve F1/S1 and P1 metadata

- **Question:** Incoming F1 reserves LLVM metadata nodes 11–22 for scalar element TBAA; P1 previously used 11 for the 32:1 count branch hint.
- **Options/evidence:** Dropping either metadata family would discard an accepted optimization. The only merge conflict is in the allowed emitter; all frozen files merge exactly to incoming main.
- **Choice:** Preserve upstream nodes 11–22 and its free-path compiler barrier. Move P1's branch-weight node and countBlock reference to 23, and start dynamically allocated fact nodes after it. Keep the task bridge and place the allocator comment directly above its paths. Auto-merged text cache writes retain P1's shared/immortal guard, and the new span-counting hook is retained.
- **Reversal:** Straightforward metadata renumbering; no semantic change.

## 2026-10-09 — reclaim completed private candidate archives

- **Question:** Available disk fell to 5.6 GB after other workspace activity; final correctness needs working space.
- **Evidence/choice:** Delete only this task's `.tmp/p1-final-C-src` through `-G-src` reconstructed source archives and their local caches (about 8.5 GB). Their committed source pins, patches, compiler hashes/binaries and evidence are retained. No live own candidate build remains. No shared caches or another lane's files are touched.
- **Reversal:** Reconstruct from the recorded commit and patch.
