# S5 exit report — 2026-10-08

**Status.** S5's final source is `ad8932de` on `claude/new-core-s5-integration`.
- `mylang` is now one binary that builds, runs and tests every program with the new
  core: Core IR → LLVM text → `zig cc`.
- The old back end is deleted: QBE and `vendor/qbe`, the QBE IL emission and the
  QBE→LLVM translator, bytecode, the GC and two-count RC with their C runtime, the old
  ownership lowering, the old native build driver, `invoke`, and the host apps.
- The full gate runs on the new core alone.
- Every S5 decision (D1–D8, accepted 2026-10-07) is carried out.
- Nothing was pushed or merged into `main`.
- S5 stops here for the user.

**Exit (plan §8).** Every check passes on `ad8932de`:
- the full gate runs on the new core alone, with no QBE, old runtime or old back end in the build;
- every `tests/lang` file passes through `mylang test` in debug and release;
- the Lox port and the EDA slice are at or below the old core in all 12 build and test cells, and at or better than S4;
- all 46 rows are within 1.10× Zig and 1.10× the old core (the old core is the archived oracle, measured interleaved);
- a compiler rebuild after a one-line edit takes 4.3–4.5 s, against S0's 20–31 s and the plan's 10 s target.

## Final receipts

| Check | Result | Evidence (`x/` unless noted) |
|---|---|---|
| Full gate, `zig build test` | **88/88 steps** in **155 s** on `ad8932de` (131 s on `6079efb2`); `fmt-check` green. The S4-exit gate took 878 s for `test` alone, plus 67 s for `test-qbe`. | `gate-final-summary.txt`, `gate-01-summary.txt` |
| Core tests (64 shards) | **436/436** in 37.9 s; longest shard 35.0 s | `qualify-final-03/` |
| Conformance with leak and fact verification, against the frozen old-core references | Debug and release each **1518 match, 0 mismatch, 0 unsupported**, 58.5 s | `qualify-final-03/full-conformance.log` |
| Frozen fuzz, 9 kinds × 200 | **1,800 cases, 25,800 comparisons, 0 mismatches**, 0 refused, 0 build failures, on `ad8932de` (and on `6079efb2` before it). Old-core outcomes come from the references; the new core runs in debug, release and verify. | `fuzz200-final/matrix.json`, `fuzz200-01/` |
| Unit tests (`test-units`) | 2,584/2,584 when C1 merged; inside the gate since | `../c1/test-units-c1merge-summary.txt` |
| CLI tests (`test-cli`) | 240/240 | lane C2 |
| `tests/lang` through `mylang test` | 1,524/1,524 per mode, plus `tests/value_semantics` 140/140 per mode, in debug and in release with leak check and `--verify-facts` (lane C3) | `../c3/` |
| Golden replay (`tests/goldens`) | 222 cases through the new `mylang`, 0 mismatches | lane C2 |
| Docs | `doc-coverage` 0 failures; `test-docs` green | lane D2, rerun by D1 |

## What was deleted

Counted against the S4 exit `cbb1d69b`:

| | S4 exit | S5 exit |
|---|---:|---:|
| `src/` outside `src/core` | 909 files, 252,934 lines | 386 files, 113,549 lines (**−55%**) |
| `src/core` | 44,943 lines | 48,128 lines |
| `vendor/qbe` | 16,326 lines | deleted |
| SPEC bullets | 1,479 | 924 |
| Binaries installed by `zig build` | `mylang`, `mylang-core`, `qbe`, `board-trial`, `schematic-svg`, `mylang-io` | `mylang` |

Lines removed by kind:

| Kind | Lines removed |
|---|---:|
| Old back end, Zig | 86,733 |
| Old back end, Zig tests | 31,517 |
| `tests/`, `test/` | 27,799 |
| Old C runtime, `src/*.c` and `src/*.h` | 22,697 |
| `vendor/qbe` | 16,326 |
| Other `src` files | 5,661 |
| Docs | 3,482 |
| SPEC.md | 650 |

In total S5 is +73,409 and −197,624 lines. Of the additions, 61,778 are evidence and tools under `experiments/`.

## Build and test times against the old core

**Ports.** Medians of three runs of a ReleaseFast `mylang` built from `ad8932de`, on CPU
10, using S4's protocols and the old-core baselines (`ports-final-{1,2,3}.json`,
`ports-final-median.json`):

| Program | Measure | Old core | S5 | New / old |
|---|---|---:|---:|---:|
| Lox port | build cold | 7.66 s | 6.76 s | 0.88 |
| | build unchanged | 0.0068 s | 0.0019 s | 0.29 |
| | build after a one-function edit | 0.195 s | 0.143 s | 0.73 |
| | tests cold | 22.0 s | 4.55 s | 0.21 |
| | tests unchanged | 0.145 s | 0.067 s | 0.46 |
| | tests after the edit | 0.648 s | 0.623 s | 0.96 |
| EDA Stage 1 | build cold | 81.1 s | 6.84 s | 0.08 |
| | build unchanged | 0.0165 s | 0.0031 s | 0.19 |
| | build after a one-function edit | 1.15 s | 0.658 s | 0.57 |
| | tests cold | 234.5 s | 26.6 s | 0.11 |
| | tests unchanged | 1.65 s | 0.350 s | 0.21 |
| | tests after the edit | 1.67 s | 0.552 s | 0.33 |

**Dev-loop targets.** Synthetic projects, ReleaseFast `mylang`. The build rows are from
`6079efb2` (`devloop-*.json`); later commits change run time, not compile time. The check
row is from `ad8932de` (`check-96k-final.json`):

| Measure | Target | S4 exit | S5 exit |
|---|---|---:|---:|
| Debug rebuild after a one-function edit, 48k lines | ≤ 2 s | 0.96 s | **0.97 s** |
| Debug rebuild after a one-function edit, 192k lines | reported | 3.3 s | **3.1 s** |
| Unchanged rebuild, debug 48k / 192k | no `zig cc` process | 5 / 13 ms, 0 processes | **5 / 14 ms, 0 processes** |
| Unchanged rebuild, release 48k / 192k | no `zig cc` process | 4 / 10 ms | **4 / 8 ms, 0 processes** |
| Check after a one-function edit, 96k lines | ≤ 0.45 s | 0.221 s | **0.226 s** |
| Release rebuild after a one-function edit, 48k lines | reported | 67.6 s | **51.5 s** |
| Cold release build, 192k lines | reported | 275 s | **213 s** |
| Compiler rebuild after a one-line edit (`zig build`, Debug, Guardian included) | below S0's 20–31 s; plan target 10 s | — | **4.3–4.5 s** (3.2–4.1 s for the binary alone) |

**The 46 rows** (`all46-03.json`, [`rows.md`](x/rows.md)):
- **92/92 cells are within both 1.10 gates.**
- Worst against the old core: `sort_int/4096` at 1.038.
- Worst against Zig: `int_parse/64` at 1.090.
- Geometric means: 0.354× the old core, 0.392× Zig. At S4 they were 0.35 and 0.39.

**How the rows got there.** The first S5-X row run (`all46-01.json.gz`, on `6079efb2`) missed
two cells:
- `packet_decode/64`: 1.11× the old core;
- `csv_aggregate/4096`: 1.105× Zig.

Both were 5–10% slower than at the S4 exit, yet their emitted code was the same and their
instruction counts were identical. Branch misses were about 30% higher, almost all in the
program's own code. Two other S5 runtime changes had moved code and data:
- C2's 256 KiB static signal stack moved where the heap starts;
- B3's text-cursor code shifted other runtime functions.

The fix (NEW-CORE-S5-RUNTIME-LAYOUT-1):
- compile the runtime with `-falign-functions=64`;
- map the signal stack when the program starts.

Both rows are then faster than at S4: `packet_decode` 14.1 vs 15.8 cycles/unit,
`csv_aggregate` 1,086 vs 1,096. The fix also removes the layout fragility for future
runtime edits.

On the way, the negative-index trap's recovery of the written index moved to the cold path
(NEW-CORE-S5-COLD-INDEX-1). It didn't change these measurements, but it belongs off the
hot path.

## What S5 did

| Package | What | Merge |
|---|---|---|
| S5-0 | Froze the old core's answers into `references/` and copied S3's qualification tools to read them. The old core and QBE are archived in `~/.cache/mylang/oracles/old-core-d36658db`. The frozen fuzz matrix runs in 2 min instead of 16. | `d0465586` |
| S5-A | One binary: `mylang build`, `run`, `run-project`, `test` and `doctest` on the new core, keeping CLAUDE.md's exit, grant and budget contract. Project `check` uses the merged check. Retired commands and flags are refused by name. | `86523ba1` |
| S5-B1 | Fixed arrays of capabilities. Sign/zero extension of narrow `extern` arguments (a real bug: `widen_i8(-5)` returned 251). | `6c107eec` |
| S5-B2 | The same extension for the C runtime helpers. `--affected`/`--against`, `--no-cache`, `--report` (the cache report as JSON) and `--timings` ported; `--explain-invalidation` and `--friction-log` retired. | `637b9160`, `bf5f185a` |
| S5-B3 | Text cursor: `find`/`rfind`/`index`/`count`/`startswith` with a moving bound, backward indexing, slices and `s[::-1]` were quadratic on non-ASCII text (40k chars: 1.32 s vs the old core's 0.014 s) and are linear again. Also: memory-bounded test fan-out, test statuses 3 and 2 restored, budget-trap traces capped at 16 frames, `debug()` dropped in `--release -o`, usage errors. | `fa20d41a` |
| S5-C1 | The 2,584 Zig unit tests run their programs through `mylang`. 8 new-core fixes; 58 tests deleted (29 old internals, 29 retired), 5 trimmed. | `ab52d77b` |
| S5-C2 | CLI tests 182/326 → 240/240; golden replay on the new core; 12 runner/runtime fixes (NaN canonicalization, `MYLANG_OPTIONS` at startup, qualified trace frames, provider contracts, contract trap records, stack-floor `R_FRAME_LIMIT`). 85 tests deleted, 39 trimmed. | `5e19f5be` |
| S5-C3 | The gate on the new core: `test-lang` in both modes, `test-core` in `zig build test`, the GC/legacy/value-semantics/module-compile steps gone, 104 arena tests deleted. | `f3c971f4` |
| S5-D1 | Deleted the old back end (715 files). The front end is cut loose (C0): legacy sharing, bytecode validators, VM values, `mut_abi` caller storage and the old typed fields are gone. `typed.Type` moved to `type_identity.zig`. `build_identity.zig` replaces the runtime-asset identity. `mylang fix` removes `with arena():`; `host def` is refused at check time. | `6079efb2` |
| S5-D2 | Docs, `features.json` (23 slugs retired), README and CLAUDE.md describe the new core only. | `e66e2abd` |
| Fixes found by S5's own gates | `len(d.keys())` returned an invalid IR type (found by C3's idiom gate). The runtime layout fix and the cold-path index recovery (S5-X's row run, see above). | `757dd6ea`, `f896758c`, `ad8932de` |

**S5-C classification** (how the old tests were handled):
- Zig unit tests: about 445 run programs and now run on the new core. About 814 test the front end only and stay. 815 asserted old back-end internals and 126 asserted retired features; those were deleted with their code.
- Of the 144 CLI tests failing after the switch: 19 were new-core gaps and were fixed, 75 asserted old internals, and 50 asserted retired features.
- Every deletion is listed with its class and reason in `c1/unit-deletions.md` and `c2/cli-deletions.md`.

## Remaining limits

1. **The unit-test suite builds every test program through the `mylang` binary.**
   - About 1,200 programs, each run as `mylang run`, because the test root cannot import the
     core module: `compiler.zig` would be in two modules.
   - A warm unsharded run takes 475 s.
   - A cold run after a compiler change takes tens of minutes unsharded, about 2 min across
     the gate's shards.
   - Batching the programs of one test file into one build is the obvious follow-up.
2. **Driver-case tests after an edit take 0.23 s against the old core's 0.040 s** (S4's limit,
   unchanged). The Lox tests column passes through the directory run. Keying receipts on
   checker fingerprints is the follow-up.
3. **Decisions made inside lanes that you may want to revisit:**
   - **Deleted tests:** 13 unit tests that spelled trusted provider intrinsics
     (`clock_now[...]`, `environment_get[...]`) were deleted as old internals. `mylang` refuses
     those names in user code; the intrinsics still work in the standard library.
   - **Runtime messages:**
     - grants are validated lazily: `--allow-bogus` is refused only when the program uses a
       capability;
     - the stack-floor guard catches overflow only when `RLIMIT_STACK` is finite;
     - every trap lists at most 16 frames;
     - the "rebuild it with --mode Debug" advice was dropped, because `--mode` is gone.
   - **Test statuses restored to the old core's:** an all-skipped run exits 3, and invalid
     cases exit 2.
4. **Format and CLI leftovers:**
   - `check-project --explain-invalidation` still lists the old lower/emit/link stages, which
     always report skipped. Removing them changes a versioned report format.
   - `mylang check` takes only `--cache-dir=DIR`, while build and test also take
     `--cache-dir DIR`.
   - Core output and comments still say "mylang-core:" in places.
5. **Leftover files:**
   - ungated Python drivers (`tests/application_comparison`, `development_velocity`);
   - the `examples/invoke`, `invoke-report` and `gc-default` examples;
   - 12 `tests/lang` files that still use `with arena()`, which now only warns.
6. **`scripts/affected_tests.py`:**
   - it does not map `tests/ported` or `tests/value_semantics`;
   - a `UnicodeDecodeError` on its default base was reported as pre-existing.
7. **Capabilities in lists** stay rejected by the checker, as in the old core. Fixed arrays of
   capabilities work.
8. **A release rebuild after an edit recompiles the whole program** (51.5 s at 48k lines), as
   decided for S4-1a. Debug builds are the edit loop.
9. **The old core lives only outside the repo**, in
   `~/.cache/mylang/oracles/old-core-d36658db`, with its frozen answers in
   `experiments/new-core-s5-20261007/references/`. Every S5 qualification tool runs without
   that directory except the 46-row tool, which builds the old core's rows. Its column at the
   S4 exit is kept in `references/rows-old-v1.json` for comparison, but the tool does not read
   it yet.

## Package lanes

Claude ran S5 as coordinator, at the user's request, with Opus lanes:
- S5-A, B1, B2, B3, C1, C2, C3, D1, D2;
- a read-only inventory and a test classification.

Each lane worked in its own locked worktree on `claude/s5-*`. Every merge was qualified on
the integration branch with the S5-0 tools: test-core, conformance against the references,
and frozen fuzz at 50 per kind. The C1 merge also ran `test-units`.
