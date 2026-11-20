# Front end and caches: what would make the edit loop faster (audit, 2026-10-26)

**Status:** audit with measurements. No compiler code was changed. Two temporary
diagnostic builds of the compiler were made and their source changes reverted (section 4.2).

**Question:** what would make incremental builds (the edit loop) faster, against a
Go-like target: an edit to one function rebuilds in well under a second at 100k lines?

**Compiler:** ReleaseFast build of main `a25bae10e`, installed at
`~/ai/.home-cache/mylang-pins/main-a25bae10e-rf`.

**Evidence:** `~/ai/canopy/mylang-evidence-archive/experiments/frontend-cache-audit-20261026/`
holds the records, logs, stamps, profile summaries and diagnostic output. The drivers are in
`experiments/frontend-cache-audit-20261026/`.

## 1. Summary

At 99k lines (the stage-2 EDA port), after a one-line body edit:

| Command | Measured |
| --- | --- |
| `mylang check` | 0.8–0.9 s (0.6 s CPU) |
| Debug `mylang build`, steady state | 2.7–4.8 s (2.8–3.9 s for the hub edit) |
| Debug `mylang build`, when the build falls back | 6.9–33 s |
| `mylang test` of the edited module | 0.15–0.6 s |
| `mylang test` of a module that depends on the edited hub | 5.3–9.4 s, and 6.2–9.5 s even with nothing changed |

At 400k lines (the N=24 scaled tree):

| Command | Measured |
| --- | --- |
| Check | 3.8–4.7 s (5.7–7.1 s after the enum edit) |
| Debug build, steady state | 11–18 s (12.4 s for the hub edit) |
| Debug build, when it falls back | 21–58 s |

The check is within a factor of 2 to 10 of the target. The build is not close.

How a 99k debug build after a one-function edit splits, in seconds. Builds 2 and 3 of the
hub edit, which compile no unit:

| Stage | Seconds |
| --- | --- |
| Front end | 0.62 |
| Lowering | 0.29 |
| Optimizer | 1.16 |
| Emission | 0.57 |
| Native | 0.11–0.15 |

The optimizer and emission stages do almost no new work. They restore all 3,472
optimized functions from the store and load 55 MB of LLVM text, which decodes about 156 MB
from zlib. At 400k the same restore is 15,197 functions, 173 MB of LLVM text and 342–404 MB
decoded.

The five largest improvements, measured or estimated per build:

| # | Change | Saving | Effort |
| --- | --- | --- | --- |
| 1 | **Stop the demand fallback.** A third of edit builds, and every build after a function is added, abandon the demand path and run the front end and lowering twice. The demand build and the eager build disagree on the size of the function table (3,717 against 3,718 at 99k). | 2.5–29 s at 99k and 9–36 s at 400k on the builds that fall back. Measured. | 4–10 h |
| 2 | **Make the optimizer shortcut fire.** It was designed to skip unchanged functions, and it bypassed nothing in any measured build. Its saved index never matches a lowered key (`key_match=0`), and any program that calls `split` turns it off outright. | About 1 s at 99k and 3 s at 400k (estimate). | 6–12 h after #1 |
| 3 | **Unit-level early cutoff in debug builds.** Serve an unchanged unit's object without restoring its optimized IR or loading its LLVM text. | 1.7–2.4 s at 99k and 5–7 s at 400k (estimate from the stage terms). | 24–40 h |
| 4 | **Re-run only what a test needs.** A test that reads live inputs gets no receipt, and its whole program pipeline runs on every `mylang test`. Add a test-program replay record, and let test sessions use check summaries. | 5–8 s at 99k on every rerun of such a test (estimate from the measured 6.2–9.5 s unchanged rerun). | 8–16 h |
| 5 | **Narrow the replay key.** Key replay on the environment variables the build reads, and keep more than one record per settings key. One unrelated environment variable turns a 0.01 s replay into a 4 s rebuild at 99k (measured). Undoing an edit also rebuilds, in 2.7–11 s at 99k and 13–56 s at 400k (measured). | Those times, whenever it happens. | 3–6 h |

Items 1, 2 and 5 are quick wins. Items 3 and 4 are structural. Section 5 ranks the full
list, and section 6 says how each one relates to the provable-cache plan.

## 2. Method

### Subjects

Both subjects are private copies under `~/ai/.home-cache/frontend-cache-audit/`; the
originals were not touched.

**The stage-2 EDA port, at 99k lines.**
- Source: `eda-bench` `g2p/integration` at `ef4bb16`, directory `stage2/mylang`.
- `src/` holds 317 `.my` files with 104,193 lines, 142 of them test files.
- `src/main.my` reaches 178 modules with 3.92 MB of source.

**The N=24 scaled tree, at 400k lines.**
- Source: a copy of `~/ai/.home-cache/scale-remeasure-20261022/n24`.
- 400,603 lines.
- `src/main.my` reaches 1,057 modules with 10.8 MB of source.

The scaled tree no longer checked on today's main, so it was migrated before measuring:
- `mylang fix src/` made 6,082 edits in 1,088 files over 50 rounds, in 22 minutes with an
  RSS of 1.9 GB.
- It exited with 24 `E_OWN_MARKER` errors that it could not repair. All 24 are the same
  site, `content = data`, where `data` is a match payload binding, repeated in each copy of
  `export_kicad_model.my`.
- Four sites in that module were repaired by hand (`copy(data)`, `copy(obj[...])`,
  `own transform`, `copy(name)`), and the file was regenerated for the other 23 copies.
- The tree then checks clean. `mylang fix` leaving a payload move unrepaired is a gap in
  `fix`, not in the edit loop. It is recorded here, and the log is in `n24-migration/`.

### Scenarios

Each scenario is one realistic edit, applied with a fresh nonce for every rep.
- `noop`: no edit.
- `comment_hub`: a comment line inserted at line 2 of `sexpr_parser.my`. This is the hub
  module: 21 modules import it at 99k and 362 at 400k.
- `leaf_body`: `_ = N` inserted in the body of `spread` in `kicad_sch_stagger.my`
  (`p01_kicad_sch_stagger.my` at 400k), a module with one importer.
- `hub_body`: `_ = N` inserted in the body of `sexpr_parser.parse_inner`.
- `hub_body_dep`: the same edit, measured on a test of a module that depends on the hub:
  - at 99k, `eval_evaluator_test.my`, which reaches the evaluator;
  - at 400k, `p01_kicad_sch_shape_test.my`.
- `type_edit`: the interface change. A new variant is added to the public enum
  `ParseError`, plus its arms in the two `match` statements over it. Every function that
  `fails ParseError` changes signature.
- `add_func`: a new public function appended to the hub.
- `test_edit`: `_ = N` inserted in `test_parse_simple_list` in `sexpr_parser_test.my`.

### Commands

For each scenario the driver runs three commands:
- `mylang check src/main.my --timings=json --report`;
- `mylang build src/main.my -o … --report`, a debug build;
- `mylang test <the affected module's test> --json`, with the EDA's frames, steps and memory
  budget.

### Protocol (`measure.py`)

1. Each command kind has its own cache directory and its own per-user object store
   (`XDG_CACHE_HOME`). A timed command therefore sees exactly its warm state plus one edit,
   and nothing one command caches can help another.
2. Two untimed warm passes run first.
3. Then, per scenario and rep:
   1. apply the edit;
   2. run the scenario's commands inside **one `build-slot.sh timing` admission**, each command
      stamped separately (`stamp_many.py`);
   3. revert the edit and check the file's sha256;
   4. re-warm every command on the reverted tree, in one `build` admission.
4. Reps: 3 at 99k, 2 at 400k.
5. The tables report wall time and CPU (user plus system) of the `mylang` process. Medians
   are given with the range in parentheses.

### Limits of the measurements

- **Code-identical reps.** `_ = N` and a comment generate the same code whatever `N` is. Only
  rep 1 of an edit compiles a native unit; reps 2 and 3 find that unit's object already in
  the store, so they show the floor without native compilation. The tables mark which rep
  compiled.
- **A shared host.** A timing window drains admitted builds and gates, not the other
  sessions' unadmitted processes. The 1-minute load average at the end of the timed
  commands was 2.4 to 16, and part of that is the build's own threads. Wall time is up to
  twice CPU time on some rows. Compare CPU across rows where wall varies.
- **One aborted run.** The first timing run passed the build-slot admission markers to the
  timed commands but not to the warm runs. That changed the replay key (finding F7) and was
  discarded (`runs/eda-timing-aborted-env/`). The stamp helpers now strip the markers for
  every command.
- **Explore runs.** The breakdowns from runs under ordinary `build` admission
  (`runs/eda-explore1`, `runs/n24-explore1`) are used only to explain behaviour, never as
  the timed numbers.

## 3. Measurements

### 3.1 EDA stage 2 (99k lines), 3 reps, timing windows

| Scenario | check | debug build | test of the module |
| --- | --- | --- | --- |
| noop | 0.16 (0.06–0.43), CPU 0.05 | 0.06 (0.01–0.22), replayed | 0.04 (0.01–0.12), all cached |
| comment_hub | 1.54 (0.98–1.62), CPU 0.74 | 7.48 (4.62–7.95), CPU 3.33 | 0.32 (0.08–0.47) |
| leaf_body | 0.89 (0.77–1.53), CPU 0.60 | 4.22 (2.74–10.63), CPU 2.91 | 0.26 (0.15–0.63) |
| hub_body | 0.81 (0.80–0.87), CPU 0.58 | 2.93 (2.82–3.90), CPU 2.79 | 0.18 (0.14–0.37) |
| hub_body_dep (`eval_evaluator_test`) | — | — | 6.82 (5.28–9.40), CPU 6.38 |
| type_edit | 1.18 (0.97–1.28), CPU 0.72 | 4.81 (3.72–10.18), CPU 4.69 | 0.10 (0.09–0.47) |
| add_func | 1.20 (0.86–4.00), CPU 0.90 | 7.70 (6.89–33.42), CPU 5.73 | 0.07 (0.04–0.08), cached |
| test_edit | 0.04, verdict hit | 0.01, replayed | 0.24 (0.10–0.41) |

The debug build per rep. "Units" is compiled out of 465. The stage times are in seconds.

| Scenario, rep | wall | front end | lowering | optimizer | emission | native | units compiled | lowered | fallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| comment_hub r1 | 7.48 | 3.05 | 0.50 | 2.11 | 0.95 | 0.71 | 1 | 158 | no |
| comment_hub r3 | 4.62 | 1.25 | 0.44 | 1.69 | 0.72 | 0.45 | 0 | 0 | no |
| leaf_body r1 | 10.63 | 7.43 | 0.69 | 1.28 | 0.68 | 0.46 | 1 | 3 | **yes** |
| leaf_body r2 | 2.74 | 0.51 | 0.29 | 1.16 | 0.57 | 0.15 | 0 | 1 | no |
| hub_body r1 | 3.90 | 0.96 | 0.34 | 1.30 | 0.75 | 0.48 | 1 | 1 | no |
| hub_body r3 | 2.82 | 0.62 | 0.29 | 1.16 | 0.57 | 0.11 | 0 | 1 | no |
| type_edit r1 | 10.18 | 4.07 | 0.97 | 2.37 | 1.07 | 1.52 | 1 | 3,459 | **yes** |
| type_edit r2 | 3.72 | 1.00 | 0.28 | 1.38 | 0.77 | 0.20 | 0 | 30 | no |
| add_func r1 | 33.42 | 28.72 | 0.89 | 2.43 | 0.70 | 0.46 | 0 | 1,980 | **yes** |
| add_func r2 | 6.89 | 3.63 | 0.45 | 1.57 | 0.71 | 0.42 | 0 | 0 | **yes** |

Notes on the rows:
- comment_hub r1 lowered 158 functions. 153 of them are a one-time cost of the first non-replay
  build after a cold build, seen in every run. A comment edit by itself re-lowers about 5
  functions (400k, below).
- add_func r1 is the worst single build. Its front end spent 16.2 s in `ordinary_body_replay`
  under load, against 1.3–1.5 s in reps 2 and 3.

Storage in a steady build (hub_body r2):
- 37 MB packed and 156 MB decoded, returning 113 MB of payload;
- 3,472 optimized functions restored and 1 optimized fresh;
- 55 MB of LLVM text loaded, 1 unit rendered, and 128 units served by object handle.

Check: 927–1,060 bodies are type-checked on every check, whatever the edit; the other
3,442–3,574 stand in from summaries. The largest phases are:
- `syntax_replay`, 0.12–0.50 s;
- `fresh_body_check`, 0.19–0.21 s;
- `specialization_body_replay`, 0.08–0.27 s;
- `checked_command`, 0.05–0.16 s.

Memory: the build peaks at 484–692 MB RSS, the check at 326–336 MB.

### 3.2 N=24 scaled tree (400k lines), 2 reps, timing windows

| Scenario | check | debug build | test of the module |
| --- | --- | --- | --- |
| noop | 0.44 (0.16–0.72), CPU 0.20 | 0.07 (0.03–0.11), replayed | 0.01, cached |
| comment_hub | 4.14 (3.79–4.49), CPU 3.49 | 12.87 (11.14–14.60), CPU 9.24 | 0.20 (0.11–0.30) |
| leaf_body | 4.39 (4.06–4.71), CPU 3.37 | 19.62 (18.43–20.81), CPU 12.11 | 0.64 (0.25–1.04) |
| hub_body | 4.38 (4.21–4.55), CPU 3.73 | 12.37 (12.36–12.39), CPU 10.28 | 0.25 (0.17–0.33) |
| hub_body_dep (`p01_kicad_sch_shape_test`) | — | — | 0.79 (0.55–1.03), receipts hit |
| type_edit | 6.38 (5.66–7.11), CPU 3.93 | 37.88 (17.81–57.95), CPU 18.43 | 0.22 (0.11–0.34) |
| add_func | 4.34 (4.21–4.47), CPU 3.76 | 23.85 (22.89–24.81), CPU 15.40 | 0.06, cached |
| test_edit | 0.20, verdict hit | 0.20, replayed | 0.40 (0.15–0.66) |

The debug build per rep. "Units" is compiled out of 1,282.

| Scenario, rep | wall | front end | lowering | optimizer | emission | native | units compiled | lowered | fallback |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| comment_hub r1 | 11.14 | 4.19 | 0.69 | 3.52 | 2.07 | 0.46 | 1 | 5 | no |
| leaf_body r1 | 20.81 | 14.30 | 1.25 | 2.98 | 1.63 | 0.33 | 1 | 3 | **yes** |
| leaf_body r2 | 18.43 | 5.34 | 1.51 | 4.94 | 3.20 | 3.16 | 0 | 1 | no |
| hub_body r1 | 12.39 | 5.35 | 0.73 | 3.32 | 2.05 | 0.68 | 1 | 1 | no |
| hub_body r2 | 12.36 | 4.13 | 0.99 | 4.06 | 2.05 | 0.81 | 0 | 1 | no |
| type_edit r1 | 57.95 | 40.63 | 4.13 | 8.40 | 2.41 | 2.06 | 1 | 15,026 | **yes** |
| type_edit r2 | 17.81 | 4.62 | 1.32 | 5.27 | 2.88 | 3.50 | 0 | 132 | no |
| add_func r1 | 24.81 | 15.13 | 2.91 | 3.14 | 1.92 | 1.38 | 0 | 8,445 | **yes** |
| add_func r2 | 22.89 | 14.75 | 1.19 | 3.59 | 1.96 | 1.08 | 0 | 0 | **yes** |

Notes on the rows:
- In type_edit r1, `ordinary_body_replay` took 23.8 s of the 40.6 s front end. The fallback
  check replays every body from the checked-body store.
- In leaf_body r2 and type_edit r2, the native stage took 3.2–3.5 s with no unit compiled.
  The profile below puts that time in hashing every unit's LLVM text to form its object key
  (`unit_cache.key`) and checking the stored objects (`unit_cache.Store.checked`).

Storage in a steady build (hub_body r2):
- 92 MB packed and 404 MB decoded, returning 359 MB of payload;
- 15,197 optimized functions restored;
- 173 MB of LLVM text loaded, and 681 units served by handle.

Check: 4,305–4,718 bodies are checked fresh on every check, out of 23,823. The largest
phases are:
- `fresh_body_check`, 1.67–2.00 s;
- `syntax_replay`, 0.39–2.40 s;
- `sema_session_open`, 0.29–0.37 s, of which dependency keys are 0.26–0.34 s;
- `specialization_body_replay`, 0.16–1.06 s.

A no-op check spends 0.12–0.80 s in `source_load_parse`: it reads, lexes for imports and
hashes all 1,057 modules before it finds the verdict.

Memory: the build peaks at 1.45–2.12 GB RSS, the check at 1.19–1.22 GB.

Against F2b's numbers: its leaf build was 13.6–14.3 s, from a different migration and on a
loaded host. Today's steady hub build is 12.4 s and its 2.3 s quiet check is now 4.1–4.4 s.
The trees differ (this copy is migrated to today's ownership rules), so the comparison is
not like for like.

### 3.3 Profiles of a steady debug build after a hub body edit

Recorded with `perf record --call-graph lbr`, which gives callers. Without frame pointers the
DWARF stacks did not unwind. Summaries are in `profiles/`.

At 99k, self time with flat sampling:

| Symbol | Share |
| --- | --- |
| `compress.flate` (decode) | 17.7% |
| `crypto.blake3` | about 17% |
| `memcpy` | 10.5% |
| `lowering_finish.function` | 4.0% |

The callers of that time:
- **BLAKE3** is mostly `canonical_ir.Canon.functionDigest` called from
  `optimization_cache.Context.key` (in `passes.inlineCached`) and from `emission_key`. The
  optimizer digests every function's IR to form its stage keys, even when every key will
  hit.
- **The decode** is mostly `stage_store.Store.loadValue` from `emit_units.EmissionJob.run`
  (the LLVM artifacts), then `passes.cachedFinal` (the optimized functions) and
  `build.buildRootsCached` (the lowered functions).
- **Load:** `lexer.tokenize` (about 10%) and `sha256_portable` (about 6%) sit under
  `project.Project.load`. Every build lexes every module for import discovery and hashes it
  with SHA-256 before any cache is consulted.

At 400k, inclusive on the performance cores:

| Caller | Share |
| --- | --- |
| `sema.checkProgram` | 33.6% |
| `passes.runInternal` (optimizer) | 19.8% |
| `stage_store.Store.loadExpected` | 19.7% |
| BLAKE3 | 18.0% |
| `emit_units.emitCached` | 14.7% |
| `build.buildRootsCached` (lowering) | 11.5% |
| `stage_compression.decode` | 10.0% |
| `record_layouts.validate` | 6.7% |
| `ownership_cache.Cache.validate` | 3.4% |

On the efficiency cores, the optimizer's parallel part is 49%, with `optimization_cache.Context.key`
alone at 18.5%. `driver.unitObjects` is 7.9%, mostly `unit_cache.key` hashing LLVM text.

### 3.4 Tests

A test of the edited module is fast at both sizes: 0.1–0.6 s.

A test of a module that depends on the hub is not, at 99k. `eval_evaluator_test` takes
6.2–9.5 s **with nothing changed** (the warm passes) and 5.3–9.4 s after the hub edit.
- None of its 32 tests can be cached. Each reports `cache.reason
  shared-private-live-or-unknown-input`, because the tests use a filesystem.
- So every run builds the test program again, though the program is `reused`, no unit is
  compiled and native takes 0.07 s. In one run:
  - optimizer 0.88 s;
  - emission 2.11 s;
  - the rest in the front end, where `sema.checkProgram` is 38% of samples, because test
    sessions do not use check summaries;
  - lowering (`build.buildRootsCached`), 10.6%;
  - the trial processes.

At 400k, the dependent test `p01_kicad_sch_shape_test` is served by execution receipts in
0.55–1.03 s.

## 4. Where incremental work is lost

### 4.1 Invalidation broader than the edit needs

- **F1. Interface edits re-lower most of the program.**
  - Adding a public function re-lowers 1,980 of 3,473 functions at 99k and 8,445 of 15,198
    at 400k.
  - Adding an enum variant re-lowers 3,459 and 15,026, and every optimizer stage misses.
  - Yet the linked program is `reused` and one unit at most is compiled.
  - The cause is the one F2b recorded (`experiments/eda-roadmap-20261022/lanes/f2b.md`, D6
    and D7): lowered artifacts name their callees by positional index, so every function
    after the insertion point changes key.
  - Cost: the lowering term rises from 0.29 s to 0.97 s and the optimizer from 1.16 s to
    2.37 s at 99k; at 400k, from about 1 s to 4.1 s and from about 4 s to 8.4 s.
- **F2. The always-fresh bodies.**
  - Every check type-checks 927–1,060 bodies at 99k and 4,305–4,718 at 400k, whatever the
    edit.
  - These are the bodies summaries cannot stand in for: constants, which `admitsStandIn`
    refuses; bodies that call a generic specialization (concrete instances have no place in
    the summary table); and bodies that touch a record interned during checking. The 99k
    tree has 453 top-level constants and the 400k tree 2,742.
  - This is F2's finding B, unchanged.
  - Cost: `fresh_body_check` is 0.19–0.21 s at 99k and 1.67–2.00 s at 400k, the largest
    term of a 400k check.
- **F3. The replay key covers the whole environment** (`build_replay.environmentInto`).
  - Every variable except `_`, `SHLVL`, `OLDPWD` and `MYLANG_PROFILE_DIR` goes into the key.
  - Measured on a fresh EDA copy (`envprobe/`): the unchanged tree replays in 0.01 s. With
    `MYLANG_ADMISSION_KIND=timing` added and nothing else changed, the build ran in full
    (front end 1.21, lowering 0.43, optimizer 1.57, emission 0.81 s) and re-lowered 153
    functions.
  - Any shell or agent harness that differs in one unrelated variable pays that. So do the
    build-slot admission markers. `src/environment_identity.zon` already classifies those
    markers as placement, not identity.
- **F4. One replay record per settings key.**
  - `build_replay.remember` writes the record at a path derived from the settings alone.
    Undoing an edit therefore never replays: the record now describes the edited tree.
  - Measured as the re-warm build after each revert: 2.7–11.0 s at 99k (CPU 2.7–5.7) and
    12.7–56.0 s at 400k (CPU 9.2–20.6).
  - Undoing an edit, switching branches and bisecting are common in agent loops.

### 4.2 Work redone although its inputs did not change

- **F5. The demand fallback.**
  - The debug build first tries its demand path, which omits unchanged checked bodies. A
    `CacheMiss` anywhere in that attempt makes `build_retry.run` discard it and run the whole
    front end and lowering again, eagerly.
  - Frequency: 5 of 15 non-replay edit builds at 99k, 4 of 10 at 400k, and 3 of 9 in the
    explore run. Every `add_func` build falls back, including reps whose lowering had
    nothing to do (`lowered=0`, `fallbacks=1`).
  - A diagnostic build (`shortcut-diag2/`, patch archived, source reverted) printed each
    build's function table:

    | Build | Function table |
    | --- | --- |
    | Eager (cold, or after a fallback) | 3,718 functions |
    | Demand | 3,717 functions |

  - Consecutive leaf edits alternate: fallback, fallback, clean, fallback.
  - The demand path declares one function fewer than the eager path, and the positional
    tables keyed against the previous build's layout then miss.
  - Not identified: which declaration differs. The first thing to find.
- **F6. The optimizer shortcut never fires.**
  - `optimizer_shortcut.zig` exists to bypass validated prepasses for unchanged
    (`green`) functions and leave their final IR unloaded. Every measured build at both
    sizes reports `bypassed 0` and `unloaded 0`.
  - The diagnostic shows why: the saved demand index is found (`saved=true`, 3,718 entries),
    but **none** of its 3,474 internal entries has the same lowered key as the current build
    (`key_match=0`). No key is null on either side. The table-size alternation (F5) shifts
    every positional entry, and the eager and demand builds key differently.
  - Separately, `passes.prepareOptimizer` turns the shortcut off for any program whose
    catalog has `myl_core_str_split` or a whitespace split (`eager_splits`), which includes
    `bytes.split`.
  - On a two-module probe (`split_probe.sh`) the shortcut bypasses a function, and one
    `strings.split` call drops it to 0.
  - The EDA port calls split in four modules. Removing all four (`exp/eda-nosplit`) still
    left it at 0, which is F5 again.
- **F7. Every build restores everything.**
  - Even when the shortcut misses, the stages restore per function rather than per unit:
    - all optimized functions (3,472 at 99k, 15,197 at 400k), each keyed by a BLAKE3 digest
      of its canonical IR at each optimizer stage;
    - all LLVM text (55 MB, 173 MB), loaded to form unit and object keys;
    - every unit's text hashed again for the object store.
  - This is the 1.7–2.4 s of optimizer and emission in a steady 99k build, and 5–7 s plus
    up to 3.5 s of native key hashing at 400k.
  - Profile shares are in section 3.3.
- **F8. Bodies the build replays.**
  - The build's front end replays from the checked-body store the bodies that lowering
    needs and summaries do not stand in for (`ordinary_body_replay`).
  - Steady: 0.04–0.38 s at 99k and 0.65–2.17 s at 400k.
  - In a fallback attempt every body replays: up to 16.2 s at 99k and 23.8 s at 400k.
- **F9. Test programs are rebuilt when their tests must run.**
  - A test that cannot be cached (live inputs) still needs its program, and there is no
    record of a test program by its inputs, so the whole pipeline runs: the front end without
    summaries, then lowering, optimizer and emission restores.
  - Cost: 6.2–9.5 s per run for `eval_evaluator_test`, even unchanged.

### 4.3 Cache reads that cost more than they save

- **F10. Decoding and hashing.**
  - A steady build decodes 156 MB from zlib at 99k (404 MB at 400k) to return 113 MB
    (359 MB) of payload.
  - flate and memcpy are about 28% of a 99k build's self time, and BLAKE3 key hashing
    another 17%.
  - Most of these reads exist only to recompute keys whose answer is "unchanged" (F7).
- **F11. Source loading.**
  - Every command lexes every module for import discovery and hashes each with SHA-256
    (`project.Project.intern`) before it consults a cache.
  - A no-op check at 400k: 0.12–0.80 s of `source_load_parse`.
  - An edit check: 0.42 s.
  - The build's load phase: 1.66 s at 400k under the explore load.
  - The portable SHA-256 F2 introduced is about 10x faster than the standard library's on
    this host, but it still runs on every byte of every command.
- **F12. Syntax decoding.**
  - `syntax_replay` decodes the cached syntax of every unchanged module on every command:
    0.12–0.50 s at 99k and 0.39–2.40 s at 400k.

### 4.4 Process start-up and memory

- **Start-up is not the problem.** A replayed build takes 0.01–0.07 s, a verdict-hit check
  0.04–0.16 s and a cached test 0.01–0.04 s. The exception is the 400k no-op check (F11).
- **The in-process session is slower than one-shot commands at this size.**
  `mylang check-session` on the 99k tree (`session/`):

  | Session budget | Per edit | Bodies reused |
  | --- | --- | --- |
  | Default (`MYLANG_SEMANTIC_BUDGET` 16 MiB) | 3.67–3.98 s | 812 of 4,502 |
  | 2 GB | 1.75–2.08 s | 4,415 |

  - Both are slower than a one-shot check (0.8 s), which uses check summaries.
  - The session's syntax cache has a fixed 256-entry, 16 MiB limit (`syntax_cache.Limits`)
    and missed all 178 modules on every request.
  - The session also does not use check summaries.
  - A resident server is the usual route to a Go-like loop, and today's session would be a
    step back.
- **Memory is moderate.** A 99k build peaks at about 0.5–0.7 GB, a 400k build at 1.45–2.12 GB.
  The 128 MiB block cache from F2b is inside these figures. Memory does not limit the edit
  loop; the decode volume does.

## 5. Ranked improvements

Savings are per build, against the measured medians above. "Measured" means the term
exists in the reports and goes away. "Estimate" means the term would shrink by an amount
the reports bound but do not prove.

### Quick wins

**Q1. Stop the demand fallback (F5).**
- **Work:** find the declaration present in the eager function table and absent from the
  demand one (3,718 against 3,717 at 99k; the shortcut diagnostic prints the counts). Then
  make both paths declare the same table, or make the tables that the demand lookups and
  the shortcut index key on independent of position.
- **Evidence:** section 3, the fallback rows, and `shortcut-diag2/`.
- **Saving:** the extra front end and lowering on the builds that fall back. Measured:

  | Build | Front end with the fallback | Front end without | Saved |
  | --- | --- | --- | --- |
  | 99k leaf edit | 7.43 s | 0.51–1.13 s | 6.3–6.9 s |
  | 99k added function | 3.63–28.7 s | about 0.6 s (the steady hub build; no added-function build avoided the fallback) | 3–28 s |
  | 400k leaf edit | 14.3 s | 5.3 s | 9 s |
  | 400k enum variant | 40.6 s | 4.6 s | 36 s |
  | 400k added function | 14.75–15.13 s | about 4.5 s | about 10 s |

  About a third of edit builds, and every added function, benefit.
- **Effort:** 4–10 agent hours.
- **Risk:** medium. The fix touches what the demand path declares or how it is keyed. The
  existing guards are `build_retry` (NEW-CORE-DEMAND-1), the demand and lowering-key tests,
  and `--verify-cache` on both trees. Add a test that two consecutive edit builds both take
  the demand path.
- **Provable cache:** independent of T1/T2, and needed either way. Under T2 a step's record
  says what it read, so a retry that discards the attempt should become rare by design. The
  fix keeps today's behaviour exact and only stops the wasted attempt.

**Q2. Make the optimizer shortcut fire (F6), after Q1.**
- **Work:**
  - match the saved index entries by stable function identity, not by position;
  - record the eager and demand lowered keys identically;
  - lift or narrow the `eager_splits` guard, which turns the shortcut off for every program
    that calls `split`.
- **Saving (estimate):** up to the optimizer stage for unchanged functions. That is 1.16 s
  of a steady 99k build and 3.3–4.1 s at 400k. The shortcut still inspects dirty callers
  and keeps checkpoints, so a realistic saving is perhaps 0.8–1.0 s at 99k and 2.5–3 s at
  400k. Emission also shrinks if the unloaded finals feed its compact receipts.
- **Effort:** 6–12 agent hours. The guard needs to be understood first: it came with the C9
  span work (`885be5a2c`).
- **Risk:** medium. The shortcut already has its own validation (`reusableEntry`,
  `invalidateCallers`). The change makes it used, so its tests must cover a program with
  split.
- **Provable cache:** aligned. T2 records need stable step identities; positional matching
  is what T2 replaces.

**Q3. Narrow the replay key and keep several records (F3, F4).**
- **Work:**
  - hash only the variables the build reads, or the keyed variables of
    `environment_identity.zon`, instead of the whole environment less four names;
  - keep the last few records per settings key, keyed by the source digests, so undoing an
    edit or switching branches replays.
- **Saving:** a whole rebuild whenever it applies. Measured: 4.1 s at 99k for one unrelated
  variable; 2.7–11.0 s at 99k and 12.7–56.0 s at 400k after undoing an edit.
- **Effort:** 3–6 agent hours.
- **Risk:** low to medium. A variable the build reads must not be dropped. The
  identity-classified list exists, and the K0 read audit is the check.
- **Provable cache:** this is T1 in miniature: record the environment variables a step
  reads. Do the projection now consistently with `environment_identity.zon`; K1 later
  replaces it with recorded reads. Keeping several records is T2's record store. There is
  no conflict.

**Q4. Stat-keyed source memo (F11).**
- **Work:** keep, per module path, the stat tuple (size, mtime, ctime, inode) against the
  source digest and the import list. Re-lex and re-hash only modules whose tuple changed or
  falls inside the racy-write window.
- **Saving:** measured terms. At 400k, 0.12–0.80 s of a no-op check, about 0.4 s of an edit
  check, and up to about 1.5 s of a build's load. At 99k, about 0.1–0.3 s of a build.
- **Effort:** 4–8 agent hours.
- **Risk:** low. The same assumption as replay's stat fast path.
- **Provable cache:** exactly decision E2 (the stat fast path under the racy-window rule).
  Implement it as the T2 stat fast path, or so that T2 can adopt it unchanged.

**Q5. Session budgets that scale with the project (section 4.4).**
- **Work:**
  - size the `check-session` syntax and semantic budgets from the loaded project, or raise
    the fixed 16 MiB defaults;
  - then give the session the check summaries the one-shot path uses.
- **Saving:** measured. 3.7–4.0 s to 1.75–2.1 s per edit at 99k from the budget alone.
  With summaries, probably near the one-shot 0.6–0.8 s or below, since nothing has to be
  decoded.
- **Effort:** 2–3 hours for the budgets, 8–16 hours for summaries in the session.
- **Risk:** low for budgets (more memory) and medium for summaries.
- **Provable cache:** neutral. An in-memory reuse needs the same recorded inputs as a
  persisted one.

### Structural changes

**S1. Unit-level early cutoff for debug builds (F7, F10).**
- **Work:** a debug unit's object depends on:
  - its functions' lowered keys;
  - the final IR of the callees it inlined;
  - the layout and runtime inventory;
  - the settings.

  When none of these changed, serve the object (or the linked program) directly: no
  optimized-IR restore, no LLVM load, no per-unit text hash. The pieces exist in part: the
  128 and 681 native handles, compact receipts and the shortcut's call graph.
- **Saving (estimate from the stage terms):**
  - At 99k: most of the 1.16 s optimizer and 0.57 s emission, and the 0.1–0.5 s native key
    work, so 1.7–2.4 s. The 2.8–2.9 s steady hub build would become about 0.9–1.2 s.
  - At 400k: 5–7 s plus up to 3.5 s of native key hashing. The 12.4 s build would become
    about 5–6 s, most of it the front end.
- **Effort:** 24–40 agent hours.
- **Risk:** medium to high. Cross-unit inlining makes a unit depend on other units' bodies.
  A missed dependency serves a stale object, so this needs the invalidation tests F2b named:
  a callee edit rebuilds its inliners, and an unrelated edit rebuilds nothing. It also needs
  `--verify-cache` runs on both trees.
- **Provable cache:** this is T2's early cutoff. Build the unit record as a T2 record
  (inputs: the lowered keys, the inlined callees' final digests, the layout, the settings;
  output: the object digest), not as another hand-built key. If it lands before K1–K3, it
  lands in the "High risk" row of the plan's table, so the order matters.

**S2. Stable identities in lowering artifacts and keys (F1).**
- **Work:** name callees by module and declaration, or by a content identity, instead of by
  checked index, in the artifact, the reach key and the stored references. This is F2b's
  open step 2.
- **Saving (measured terms):**

  | Edit | Lowering and optimizer when re-lowering | Steady | Saved |
  | --- | --- | --- | --- |
  | 99k enum variant | 0.97 s and 2.37 s | 0.29 s and 1.16 s | about 1.9 s |
  | 400k enum variant | 4.1 s and 8.4 s | about 1 s and 4 s | about 7.5 s |
  | 400k added function | 2.9 s of lowering | — | about 1.9 s, plus the misses that follow |
- **Effort:** 16–32 agent hours.
- **Risk:** medium. It needs tests that a renamed or changed callee re-lowers its callers.
- **Provable cache:** a prerequisite for T2 records that survive an unrelated insertion.
  Aligned.

**S3. Summaries for constants, specialization callers and interned records (F2).**
- **Work:**
  - store a constant's value in its summary;
  - give concrete instances a place in the summary table;
  - name records interned during checking.
- **Saving (measured terms):** at 400k, most of the 1.67–2.00 s of `fresh_body_check` (a
  check would go from 4.1–4.4 s towards about 2.5 s). At 99k, 0.19–0.21 s, about a third
  of a check's CPU.
- **Effort:** 16–24 agent hours.
- **Risk:** medium. It changes the summary format, and a stood-in constant must carry its
  value exactly.
- **Provable cache:** this is T3 territory (stand-ins under the proof). The new summary
  fields are exactly the reads T3 would record per function. Either design them as T3's
  recorded inputs, or land them after K2 so that K2 covers them. Landing them first with
  another hand-built digest is the one place where this audit's advice conflicts with the
  plan's ordering.

**S4. Skip unchanged modules in the front end (F8, F12).**
- **Work:** keep a per-module record of what the module exports (declarations and their
  fingerprints) and of its bodies' summaries. Then an unchanged module is neither re-lexed
  nor syntax-decoded, and its bodies are not replayed unless lowering demands one.
- **Saving (measured terms):**
  - At 99k: `syntax_replay` 0.12–0.50 s plus `ordinary_body_replay` 0.04–0.38 s.
  - At 400k: `syntax_replay` 0.39–2.40 s plus 0.65–2.17 s.
  - So 0.2–0.9 s at 99k and 1–4.5 s at 400k.
- **Effort:** 24–40 agent hours.
- **Risk:** medium to high. Declaration fingerprints are the hand-built digests the plan
  calls high risk.
- **Provable cache:** build it after K2, as K2 records per module, or with K0's read audit
  covering it.

**S5. Test programs on records (F9).**
- **Work:**
  - record a test program by its inputs, as build replay does (sources, settings, linked
    program, test plan), so a test that must re-execute does not rebuild its program;
  - let the test session use check summaries.
- **Saving:** at 99k, 5–8 s of the 6.2–9.5 s unchanged rerun of `eval_evaluator_test`
  (measured: no unit is compiled and the tests themselves run for thousands of steps). After
  a hub edit the front end part remains, so expect about 2–4 s (estimate).
- **Effort:** 8–16 agent hours.
- **Risk:** low to medium.
- **Provable cache:** this is K3 (test receipts on records). Build it as K3's first record
  kind.

**S6. A resident compile server (the Go-like endgame).**
- **Work:** keep the checked program, the lowered and optimized IR and the unit objects in
  memory across requests (`check-session` grown to build and test). An edit then costs only
  the changed functions plus the whole-program passes, with no decode, no key hashing and no
  per-process load.
- **Prerequisites:** Q5 first. Today's session is slower than a one-shot check.
- **Saving (estimate):** combined with Q1, S1 and S3, a 99k one-function edit could rebuild in
  about 0.5 s (front end and passes about 0.3 s, one unit compiled in 0.1–0.5 s). The
  current architecture's floor with S1 alone is about 1 s.
- **Effort:** weeks.
- **Risk:** medium.
- **Provable cache:** a server needs tracked inputs to invalidate correctly; T1/T2 are its
  invalidation model, so they are compatible and helpful.

### Order

1. **Q1, then Q2.** Q2 cannot be judged until Q1 stops the alternation.
2. **Q3 and Q4.** They are small and independent.
3. **S5.** It is contained and large for tests.
4. **S1 and S2,** on the T2 record format.
5. **S3, S4 and S6,** with or after K2.

Expected steady debug build at 99k after Q1–Q4 and S1: about 1.0–1.3 s for a body edit, and
the same for an interface edit once S2 lands. It is under 1 s only with S3/S4 or a resident
server.

## 6. Relation to the provable-cache plan (`docs/audits/provable-cache-plan-2026-10-26.md`)

| Item | Rides on | Conflict |
| --- | --- | --- |
| Q1 demand fallback | Independent; a correctness-preserving fix of a hand-built path | None |
| Q2 optimizer shortcut | T2 stable step identities | None |
| Q3 replay key and records | T1 (environment reads) and T2 (record store); K1 replaces the projection | None |
| Q4 stat memo | T2 stat fast path, decision E2 | None |
| Q5 session budgets | Neutral | None |
| S1 unit early cutoff | T2 early cutoff; build the unit record as a T2 record | Before K1–K3 it would be one more hand-built key, the plan's "High risk" row |
| S2 stable identities | Prerequisite for T2 records | None |
| S3 summary fields | T3 (stand-ins under the proof) | Landing new summary digests before K2 adds hand-built keys K2 must then cover; design them as T3 recorded reads |
| S4 module records | K2 | Hand-built declaration fingerprints; do it with or after K2 |
| S5 test program records | K3 | None |
| S6 resident server | T1/T2 as its invalidation model | None |

The budgets in the plan (re-check of an unchanged project at most +2%, cold build at most +2%)
are compatible with every item here. Q4 and S4 make the unchanged re-check cheaper. F3 is
the opposite of what K0 looks for: a key broader than its reads, which costs speed, not
soundness. K0's environment logging is the evidence Q3 needs.

## 7. Files

Drivers in `experiments/frontend-cache-audit-20261026/`:

| File | What it does |
| --- | --- |
| `measure.py` | The scenario driver |
| `stamp.py`, `stamp_many.py` | Per-command stamps after admission |
| `summarize.py` | `--detail` and `--table` summaries |
| `session_probe.py` | The `check-session` probe |
| `perf_build.sh`, `perf_test.sh` | The profiled build and test |
| `env_probe.sh` | The replay environment probe |
| `split_probe.sh` | The optimizer-shortcut split probe |
| `shortcut_diag.sh` | Runs the diagnostic compiler |

The evidence archive, under `~/ai/canopy/mylang-evidence-archive/experiments/frontend-cache-audit-20261026/`:

| Path | Contents |
| --- | --- |
| `runs/eda-timing/`, `runs/n24-timing/` | The timed runs: records, logs, stamps and developer-history profiles. The environment-bearing `*.jobs.json` files were left out. |
| `runs/*-explore1/` | The explore runs |
| `runs/eda-timing-aborted-env/` | The discarded run |
| `profiles/` | perf summaries |
| `shortcut-diag/`, `shortcut-diag2/` | The diagnostic patches and their output |
| `envprobe/` | The replay environment probe |
| `session/` | The check-session probes |
| `n24-migration/` | The `mylang fix` log |
| `load-sampler.log` | Host load during the runs |
