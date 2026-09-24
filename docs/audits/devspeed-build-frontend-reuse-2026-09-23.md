# Development-speed lane: build-frontend reuse — 23–24 September 2026

Branch `devspeed/build-frontend-reuse`. It started from `base/devspeed-impl-20260923`
(`371dbd17`), merged `devspeed/integration` at `5c150f02` (main + defaults-and-docs) and
again at `bacb4667` (after `devspeed/codegen-throughput` landed). It implements the
frontend half of recommendation 1 of the
[development-speed audit](development-speed-2026-09-23.md): everything from source to
the IL the object builder receives. The build frontend reuses checked facts and emitted
units, an unchanged build does no work, and the 200k-line tier now builds.

## Result

Combined result (this lane over `bacb4667`), Debug/QBE, ReleaseFast compilers, generated
ladder, P-cores (`taskset -c 0-11`), `run_scale.py --langs mylang-debug`, minimum of 3
samples (2 for the baselines). Seconds.

| Step | 10k 5c150f02 | 10k bacb4667 | **10k lane** | 50k 5c150f02 | 50k bacb4667 | **50k lane** | 200k 5c150f02 | 200k bacb4667 | **200k lane** |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| cold build | 35.60 | 1.63 | **1.29** | 446.9 | 7.86 | **6.41** | OOM | OOM (6.1 s, 5.75 GB) | **26.19** (3.49 GB peak) |
| no-op build | 0.95 | 0.86 | **0.025** | 5.22 | 4.33 | **0.105** | — | — | **0.42** |
| edit → check | 0.122 | 0.119 | 0.112 | 0.643 | 0.603 | 0.560 | — | 2.61 | 2.46 |
| edit → build | 1.06 | 0.94 | **0.273** | 5.56 | 4.57 | **1.18** | — | — | **4.65** |
| interface → build | 1.66 | 0.95 | **0.266** | 8.20 | 4.57 | **1.19** | — | — | **4.63** |
| edit → test | 0.61 | 0.51 | 0.471 | 2.19 | 1.95 | 1.80 | — | 15.8 | 14.5 |

Load average (1-minute) was 1.2–2.4 for every row above (lane ladder 06:46–06:49 UTC,
`bacb4667` 06:35–06:37, `5c150f02` 05:31–05:40). The `5c150f02` compiler is the shared
baseline at `trials/devspeed-20260923-private/compilers/integration-5c150f02`; the
`bacb4667` one is a ReleaseFast build of an export of that commit (its install step
tripped the build runner's `max_rss` bound at 3.32 GB after the binary was written, so
the prebuilt runtime archive was copied from this lane's install — the runtime sources
of the two trees are identical).

Acceptance (audit rec 1, judged on the combined result):

| Row | Target | Result |
| --- | --- | --- |
| 50k no-op build | ≤ 0.3 s | **met**, 0.105 s |
| 50k edit → build | ≤ 1 s | **not met**, 1.18 s (was 5.56) — see *What remains* |
| 50k cold build | ≤ 30 s | **met**, 6.41 s (mostly the codegen lane) |
| 200k builds under the default 8 GiB ceiling | builds | **met**, 26.2 s cold, 3.49 GB peak |
| 200k edit → build | ≤ 3 s | **not met**, 4.65 s (check alone is 2.46 s) |
| `run` after an edit | like build | lean and fragment-reusing; see below |
| incremental build == clean build | test | **added**, CLI test passes |

## What changed

Seven commits on the lane (two of them merges).

1. **Per-function unit reuse (`QBE-FRAGMENT-REUSE-1`, `src/qbe_fragments.zig`).**
   - A function's QBE unit is keyed by exactly what its text reads:
     - its lowered body, policy, signature and locals;
     - the name, policy, signature and parameter locals of every function it names
       (callees, function values, inline origins);
     - the full schema of every record reachable from those;
     - the whole-program switches (step/frame accounting, checks, arenas, entry);
     - for the second emission pass, each named function's allocation fact and
       parameter-write facts, and for a unit that invokes a function value, the
       program's function-value target set.
   - Record and function ordinals are written as their names and source spans are
     skipped, so an edit that shifts ids or lines elsewhere leaves a key unchanged.
   - The store (under `<frontend cache>/fragments/<compiler identity>/`) keeps each
     unit's text by BLAKE3 digest, plus one pack per entry of key → answer (text
     digest, build facts, checked dependency facts). A hit skips both emission passes
     for that function. Emission now runs per function in a scratch arena reset after
     each unit, and the guest-symbol lookup in `unitAllocates` is a hash set instead
     of a scan of every unit (it was quadratic).
2. **Lean manifests.** `build --project` passes an internal `--lean-manifest`; `run`,
   `run-project` and the native-test session are always lean. A lean unit carries
   `il_digest`/`il_file`/`il_facts` instead of `il`. The facts are the `dbgfile`,
   `# myl-lit` and top-level `data` lines, which are all the driver reads without
   compiling. The driver names objects by `digestKey(digest)` and reads a text only
   to build a missing object (`src/qbe_build_units.zig`).
3. **Compact positions (`BUILD-POSITIONS-1`).**
   - A lean unit carries its per-instruction positions as a path table plus one
     `path:line:column` string, and its assertion messages as `[pc, message]` pairs.
   - `qbe_build_units.Positions` reads either spelling. `metadataAssembly` (batches)
     and `metadata` (LLVM) use it.
   - The 50k lean manifest is 8.7 MB, against 152 MB for the old inline one; at 200k
     it is 35 MB.
4. **Replay (`EMIT-REPLAY-1`).** An unchanged project replays its last lean manifest and
   warnings after loading its sources. There is one slot per entry and configuration, so
   the store does not grow by a manifest per edit.
5. **Build receipt (`BUILD-NOOP-1`, `src/qbe_build_receipt.zig`).**
   - The key covers the manifest, the build environment and generation, and every
     flag. It also records the output's inode, size and mtime.
   - A matching receipt ends the build before the manifest is parsed.
   - If something replaced the output, the build deletes it and relinks. The link's
     own reuse check would otherwise trust the sidecar.
6. **Driver memory (`BUILD-MEMORY-1`).**
   - A missed batch is staged one member at a time: read the text, check its size,
     write it out (`batch.stage`, `Input.files`).
   - The assembly annotation and the object fingerprint read through a per-step scratch
     arena.
   - The 200k cold build previously ran the driver out of its 8 GiB address space. It
     now peaks at 3.49 GB, and that peak is in the frontend child.
7. **Hashing.**
   - Fragment keys, unit digests, replays and native-test implementation hashes use
     BLAKE3.
   - Frontend-cache and checked-body-store payload checksums use the leading 8 bytes of
     BLAKE3 (`CACHE-CHECKSUM-1`; frontend cache format bumped to v4).
   - See *Findings* for why.
8. **Reporting.** `work-report-v1` counts a unit answered from the store as a reused,
   not an emitted, fragment (run, emit and the native-test session). The run manifest
   cache stores its fragment count beside its checksum instead of parsing the manifest,
   and it misses when a stored text it names is gone.
9. **Docs.** `docs/tooling/native-build.md` has a new *Incremental frontend* section.
   The README and `docs/experiments/incremental-qbe.md` no longer say builds re-lower
   the whole program.

### Correctness checks

- `qbe_fragments_test.zig` emits a two-module project through a store that is reopened
  every time. It covers the cold build, then a warm rebuild, a body edit, a new function
  ahead of every declaration (every id and offset shifts), a signature edit, a record
  schema edit, and a return to the original. Each manifest is required to be
  **byte-identical to a fresh emission**, and the hit and miss counts are asserted.
- The CLI test *"an incremental build after body, signature and interface edits builds
  the program a clean build builds"* (`test/integration.zig`) rebuilds over one cache
  after each of the three edits and builds the same version from an empty cache. It
  requires identical guest object keys, identical program output, and a narrower
  rebuild for the one-module edit.
- A second CLI test checks that a no-op build keeps the executable's inode and mtime,
  runs no codegen or link, and rebuilds an executable that someone replaced.

## Phase split after one body edit

| Tier | frontend child | driver: manifest, plan, stage | codegen tools | link | total |
| --- | --- | --- | --- | --- | --- |
| 50k | 0.90 s (check 0.55, lower 0.05, schema 0.04, emit 0.14) | 0.20 s | 0.14 s | 0.14 s | 1.2–1.45 s |
| 200k | 3.4–3.8 s (check ≈ 2.3, lower 0.18, emit 0.67) | ≈ 0.8 s | 0.64 s | 0.8–1.5 s | 4.6–6.1 s |

The 50k row comes from `strace -f -tt` on one edit build. The 200k row comes from
`--timings=json` of `build` and of `emit-project-qbe`.

## What remains

- **50k edit → build is 1.18 s, not 1.0.** About 0.55 s of the frontend is the edited
  project's check. That is fresh body checks after the interned-record bypass (3,683 of
  4,681 bodies re-check), effect passes and warnings, which is recommendation 6's work.
  The rest is roughly:
  - 0.25 s of lowering, schema and emission that is still whole-program: every body's
    key is recomputed, and the schema is re-rendered;
  - 0.2 s for the driver to parse the manifest and plan batches;
  - 0.14 s for the link.

  Cutting the remaining 0.2 s needs one of these:
  - key functions from the checked-body cache without lowering them;
  - cache the rendered schema;
  - hand the driver the manifest in memory: fold `emit-project-qbe` into the build
    process, which saves the pipe, the JSON parse and one process start.
- **200k edit → build is 4.65 s, not 3.** The check alone is 2.46 s after an edit, and
  the link is 0.8–1.5 s at this size. Neither can move in this lane.
- **The fragment store has no eviction.**
  - Unit texts accumulate by about 28 KB per changed function per build, much as
    per-function objects did before batching.
  - Packs are bounded to 4× the entries a build used.
  - Replays keep one slot per entry and configuration.
  - A sweep that keeps only the texts some pack or replay names is follow-up work. It
    needs a lease, like the object generations have, so it never deletes a text a
    concurrent build is about to read.
- **`--drop-debug` has no effect on the project path, and never did.** `lowerForReceipt`
  lowers with `drop_debug = false` before `emitQbeWithOptions` would honour the switch.
  With QBE as the default in every mode, ReleaseFast project builds keep `debug`
  lines. Not changed here.
- **A single-file `build` (no `--project`) still emits inline.** Only project emissions
  use the fragment store.

## Findings for other lanes

- **`std.crypto.hash.sha2.Sha256` hashes 25 MB in about 1.8 s on this host's
  P-cores** (about 14 MB/s), against 11 ms for BLAKE3 (`perf stat`: one microcode
  assist per two instructions). On the E-cores the same 25 MB takes 13 ms. SHA-NI's legacy-SSE instructions run next
  to AVX2 message loads in std's `round`, and the rate depends on the calling context.
  The cold emission here spent 70% of its time in it before the digests moved to
  BLAKE3. The compiler has about 170 other SHA-256 call sites, including
  `Cache.identity`, `fs.hash` and the frontend and semantic cache keys. None was
  pathological in the profiles above, but any one of them can be.
- **`std.hash.XxHash3` runs at about 25 MB/s on the E-cores** and 370 MB/s on the P-cores
  (the codegen lane measured about 20 MB/s). Its uses in the frontend caches are gone
  (`CACHE-CHECKSUM-1`); `fs.digest` already moved to Wyhash in the codegen lane.
- **ReleaseFast `-Dcompiler-only` builds of both `bacb4667` and this branch exceed the
  compile step's declared `max_rss`** (3.26–3.32 GB against 3.22 GB). The binary is
  written, but the install graph reports failure, and the runtime-archive step after it
  never runs.

## For the integrator

- **Interface with the codegen lane** (all in the driver):
  - units are keyed by `cache.digestKey(lean.digest(unit))`. That is a new `Cache`
    method: `identity("function-digest", hex)`. Their `unitKey(il)` is kept for the LLVM
    arm's `stage` path and its tests.
  - batches are planned from `lean.facts(unit)`, which drives `definesData`, the frame
    map and the literal scan;
  - a missed batch's texts go to QBE through `batch.stage` → `Input.files`;
  - `fitsQbe(unit, text)` now takes the text.
- **Conflict risk.**
  - `src/qbe.zig`: the emission passes (`firstPass`/`secondPass`/`Reuse`) and
    `Unit.jsonStringify`.
  - `src/main.zig`: `openFragments`, `replayManifest`/`rememberManifest`,
    `leanManifestOption`, `recordEmission`.
  - `src/qbe_build.zig`: the receipt, `compileBatches`/`compileUnits`, `MemberTexts`.
  - `src/qbe_build_batch.zig`: `Input.files`, `stage`, scratch arenas in `advance`.
  - `src/qbe_build_outputs.zig`: `Positions` readers.
  - `frontend_cache.zig`, `semantic_store.zig`, `persist_codec.zig`: the checksum.
  - `native_test_dependencies.zig`: BLAKE3 implementation hashes.
  - `native_run_cache.zig`: the digest file now carries the fragment count.
  - SPEC bullets: `QBE-FRAGMENT-REUSE-1`, `EMIT-REPLAY-1`, `BUILD-NOOP-1`,
    `BUILD-MEMORY-1`, `BUILD-POSITIONS-1`, `CACHE-CHECKSUM-1`.
- **Every cache key the lane touches changed** (fragments, objects, run manifests,
  frontend cache v4). A compiler built from this branch starts cold once.
- **Measurement scripts** are in the worktree's `.tmp/lane/`: `run_scale.py`
  (compiler from `MYLANG_BIN`), `ladder.sh`, `steps.sh`, `phase.sh`, `edit.sh`,
  `trace_build.sh`, and the raw `ladder-*.out` results.

## Gate

See the reply that accompanies this report for the gate results at the final head.
