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
- **Choice:** Keep admission unchanged; this is queue delay, not a reason to reduce the workload. Store all six historical/current fuzz runs in one solid xz archive, preserving original package-relative paths and every member byte. Store the two resumed counter runs together, with exact decoded JSON. Retain original archives privately and record replacement hashes in `r3/evidence-archives.json`; the fuzz member manifest is `r3/fuzz-history-manifest.json.gz`. The package is 9.65 MB at this point. Later prototypes remain in ignored scratch files while C1 is measured.
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
