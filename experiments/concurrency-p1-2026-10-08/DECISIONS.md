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
- **Evidence:** CPU-10 locked, seven interleaved samples per cell at each K=4,5,6: B five-cell geomean 0.9970614425, C 0.9977732714, neither with a median cell above 1.03. B JSON/4096 is 1.02608 and JSON/64 is 1.01787; C is 1.02178 and 1.02153. `json::read_value` sizes at K=4/5/6 are baseline 7068/7052/7020 bytes, B 8061/8061/8061, C 8472/8472/8472. Full samples and every alignment ratio are in `r3/results/five-cell.json` and `.md`; sizes are in `json-read-value-size.json`.
- **Choice:** Keep B, as R9 directs for the better five-cell geomean. The difference between variants is small, but no extra tie-break rule is needed. The existing full gate and fmt result cover this selected code. Continue with all 92 row cells, 34 EDA cases, 26 Lox cells and 45 parity arms, then the remaining P1-1 correctness gates.
- **Reversibility:** Easy; `r3/variant-C.patch` reproduces C against B and both compiler hashes and install paths are retained.

## 2026-10-09 · P1-1 redo — freeze evidence before fuzz

- **Question:** How should the frozen fuzz driver's clean-tree requirement handle ongoing evidence updates?
- **Options:** Bypass its clean-tree guard; defer every evidence update; checkpoint the completed evidence and keep live build logs untracked until they finish.
- **Evidence:** Qualification passed on unchanged `42041fa45` code: 509 Core tests and conformance 1518/0/0 in both modes. The first fuzz launch refused to start because report/harness edits were tracked and uncommitted; it executed no cases.
- **Choice:** Commit the completed checkpoint now, then run 9×50 followed by 9×200 without changing HEAD or tracked files. Keep currently written build logs out of the index until completed. No gate is bypassed; the qualification compiler's SHA-256 is retained and the implementation remains identical to the qualified merge.
- **Reversibility:** Easy; this changes only evidence scheduling.
