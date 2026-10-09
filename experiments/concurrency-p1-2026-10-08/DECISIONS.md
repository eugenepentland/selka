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
