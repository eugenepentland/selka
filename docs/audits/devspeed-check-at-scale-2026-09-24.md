# Development-speed lane: check at scale — 24 September 2026

Branch `devspeed/check-at-scale`, from `devspeed/integration` `fc742bd4` (full gate
green). It implements recommendation 6 of the
[development-speed audit](development-speed-2026-09-23.md) and the part of
recommendation 1 that the wave-1 report left under "What remains": the check an edit
pays, in `check` and inside `build`. The two other wave-2 lanes own QBE emission, the
driver and the link (`build-residue`) and the `mylang test` runner (`test-loop-scale`).

## Result

ReleaseFast compilers: *before* is the shared baseline
`trials/devspeed-20260923-private/compilers/integration-fc742bd4`, *after* is a
ReleaseFast `-Dcompiler-only` build of this branch. Generated ladder (`gen_scale.py`,
50k = `120 38`, 200k = `480 38`), `taskset -c 0-11`, minimum of 3 samples in each of two
rounds, driver `.tmp/cas/final.py` (below). Seconds.

| Row | 50k before | **50k after** | 50k target | 200k before | **200k after** | 200k target |
| --- | --- | --- | --- | --- | --- | --- |
| edit → check (body edit, middle module) | 0.672 | **0.119** | ≤ 0.25 met | 2.818 | **0.440** | ≤ 1.0 met |
| interface → check (append a public function) | 0.666 | **0.116** | ≤ 0.35 met | 2.771 | **0.442** | ≤ 1.3 met |
| no-op check | 0.091 | **0.020** | no regression, met | 0.364 | **0.070** | no regression, met |
| bodies re-checked after a body edit (`checked_bodies.performed`) | 3,686 of 4,684 | **2** | edited body only | 17,726 of 18,724 | **2** | same |
| cold check | 0.934 | 0.374 | — | 3.53 | 1.65 | — |
| edit → build (Debug/QBE, `--project`) | 1.267 | **0.879** | ≤ 1 (joint) | 5.317 | **3.167** | ≤ 3 (joint) |
| interface → build | 1.295 | 0.868 | — | 5.021 | 3.041 | — |
| peak RSS, edit → check | 523 MB | 116 MB | — | 2.09 GB | 442 MB | — |

The two re-checked bodies are the edited one and the entry point, which is always
checked. The machine was shared with the other two lanes: the 1-minute load average was
4.1–7.4 during these rounds (and 9.3 at the end of the last 200k one), so every *before*
figure is above the quiet-machine numbers in the lane brief (0.56 / 2.46 s). An earlier
round at load 0.7–1.5 measured the baseline at 0.538 / 2.371 s edit → check and
0.073 / 0.295 s no-op. Earlier builds of this branch measured 0.113 s edit → check at
50k (load 4.6) and 0.419 / 0.066 s edit → check / no-op at 200k (load 2.1). For comparison, the lane brief
gives Go `vet` 0.13 / 0.47 s and Zig 0.41 / 1.10 s after the same edit: `check` is now at
or below Go at both tiers.

Edit → build gains 0.39 s at 50k and 2.15 s at 200k from this lane alone (the build
frontend's check fell from about 2.3 s to 0.72 s at 200k). The remaining build time is
mostly the other lanes' (see *Where the time goes*).

## Why check was proportional to the project

Measured on the baseline with `--timings=json` and `perf` (inline-expanded with a
batch `addr2line`; the scripts are in `.tmp/cas/`).

1. **The interned-record bypass no longer occurs at this base.** With the retention
   budget lifted (`MYLANG_SEMANTIC_BUDGET`), 4,681 of 4,682 bodies were reused at 50k.
   The 3,685 re-checks all had reason `no-retained-body`: the 16 MiB in-memory budget
   holds the first 998 bodies. **Lifting the budget did not help**: the edit check stayed
   at 0.56 s, because loading a retained tree (19 µs per body, one file each) and
   relocating it (14 µs) cost as much as checking the body fresh (30 µs). A reuse path
   that materializes checked trees cannot make `check` scale.
2. **Lexing was 37% of a 200k edit check** (0.95 s): header discovery lexed every module,
   the unused-import warning lexed every module a second time, and name resolution ran
   the full lexer (allocation plus layout pass) on every qualified name in every checked
   body. The keyword test compared each identifier against about 90 spellings in turn,
   and layout lowering scanned back to the line start for every token.
3. **The whole-program passes walked every body six or more times** (effects 20%, 0.52 s
   at 200k). The mutation pass also searched every declaration to find each function's
   syntax (quadratic, 7% at 200k).
4. **Dependency keys walked every body's syntax** (6%), and the project arena regrew and
   recopied the merged syntax and the checked tables.
5. **Hashing is not the bottleneck on this path.** A 200k edit check hashes about 32 MB
   with SHA-256 (the module digests, the syntax keys and the verdict key over 6.9 MB of
   source, and the per-function contexts) and about 65 MB with BLAKE3 (51 MB of cached
   syntax checksums, 7 MB of region digests, the 6.6 MB summary slot). The profile puts
   SHA-256 at about 11 ms and BLAKE3 at about 21 ms of the 0.44 s. No hash site changed.

## What changed

Six commits before this report.

1. **Lex once, resolve names without the lexer (`fcf60448`, CHECK-SCALE-LEX-1).**
   Keywords and removed spellings come from comptime string maps. Layout lowering finds
   line starts in one forward pass. Header discovery records which import each dotted
   reference qualifies, from the tokens it already holds, so `recoverImportUsage` no
   longer lexes. `quickQualifiedName` normalizes a spelling of identifier bytes and dots
   without lexing it (anything else still goes through the lexer). The merged syntax and
   the checked tables are sized once. `declaringFunction` runs only when a mutation
   diagnostic is reported. 50k: 0.54 → 0.31 s; 200k: 2.37 → 1.31 s.
2. **Check summaries (`cff5b25f`, CHECK-SUMMARY-1, SEMANTIC-KEY-IDENTITY-1).** New
   `src/semantic_summary.zig` (the stored form) and `src/sema_summaries.zig` (planning,
   verification and production inside `checkCached`).
   - After a successful `check`, every ordinary function gets a summary in one
     frontend-cache slot per entry. It holds the stable key, the dependency context, the
     region's length and BLAKE3 digest, the propagated effect mask and mutation summary,
     the diagnostics the function contributed (split by phase, spans relative to the
     region), and its direct callees.
   - The next `check` stands a summary in for every body whose context and region digest
     are unchanged. The function gets its checked signature and parameters over an empty
     body. The effect and mutation passes seed it with the stored facts and skip its walk
     and its diagnostics, and its stored diagnostics are replayed at the region's new
     offset.
   - After the passes, every checked body that has a summary must still have exactly its
     stored facts, and no call cycle may run through both a checked and a stood-in body.
     A violation, or any error the passes report, makes `Compilation.checkWithCache`
     repeat the check in full with no summaries, from the same diagnostics and restored
     work counters. So `check`'s output never depends on the summaries. A body that fails
     to check is reported directly: a stood-in body had no errors and its inputs are
     unchanged.
   - Always checked: the entry point, constants, conversions, host and foreign
     declarations, and bodies whose checked tree names a specialization, a lambda or a
     type interned while checking.
   - Declaration fingerprints now name the defining module and a function's
     `@deprecated` reason. Without that, an import alias retargeted to another module's
     byte-identical declaration, or a newly deprecated callee, left its users' contexts
     unchanged. That was already a gap for the retained-tree reuse path.
3. **Lowering commands and key names (`25007fb4`, CHECK-SUMMARY-2, CHECK-SCALE-KEYS-1).**
   - `emit-project-qbe` (the build frontend), `run` and `run-project` read the same
     summaries but check every body, because lowering needs the tree. Summaries stand in
     only for pass facts, so the passes walk only changed bodies. These commands publish
     summaries only when they had none or repeated in full.
   - A request served by summaries neither loads nor publishes retained checked trees.
     Finding 1 says they cost as much as checking, and publishing every fresh body from a
     build would have added file writes.
   - Dependency-key preparation records each function's region digest and the names its
     syntax references; the summaries keep both. While the digest matches, the next
     preparation resolves the stored names instead of walking the syntax, which gives
     identical digests (key preparation at 200k: 160 → 70 ms).
4. **Constant factors (`3a28b806`).**
   - Header lexing uses a scratch arena that is reset for each module.
   - Cached syntax is decoded in place instead of from a copy of its payload.
   - A one-shot optimized compiler exits without tearing its project arena down page by
     page. A `check-session` request still releases it.
5. **Docs (`1ff1a06d`).** `docs/tooling/caches.md#check-summaries`, feature
   `check-summaries`, and a work-report note.
6. **Determinism (`1eb0e8fe`).** The header scratch arena starts with one 1 MiB chunk and
   reports a failed release. Growing arena chunks in place made
   `incremental_test`'s allocation-failure sweep nondeterministic, because in-place
   growth depends on the backing allocator's address history. The checker reserves its
   tables up front only for programs of at least 16k syntax nodes. A full retry keeps the
   request's lowering mode.

### Correctness tests

- `src/check_scale_test.zig` checks an in-memory three-module project three ways: with
  the summaries of a successful check, as a lowering command, and cold. It asserts
  identical rendered diagnostics, and identical published effect and mutation facts for
  every function, in each of these cases:
  - a body edit: 2 bodies checked, 5 stood in, the stood-in unused-binding warning
    replayed;
  - an unchanged project: 1 body checked, 6 stood in;
  - **a record shape edit**, a new defaulted field: exactly the body that builds the
    record re-checks. A field type edit gives the same error as a cold check;
  - a callee that starts allocating under a stood-in `noalloc` caller: the check repeats
    in full, and `E_EFFECT_BOUND` matches cold;
  - an import alias retargeted to a byte-identical declaration elsewhere. **This test
    fails without the identity fix;**
  - deprecating a callee, which yields `W_DEPRECATED`. **This test fails without the
    fix;**
  - both lowering-mode cases, including the repeat that publishes;
  - dependency keys from recalled names equal walked ones, and a stale digest is ignored;
  - summary payload round-trip and refusal of a foreign payload.
- The lexer-free name path is compared against `qualifiedName(lex(...))` over a corpus
  that includes keywords, removed spellings, `::`, spaces and digits.
- **Ratchet** (`test/integration.zig`, *check after a one-body edit re-checks only that
  body when retention cannot hold the project*):
  - It generates a 4 × 6 ladder whose bodies build `list[int]`, with
    `MYLANG_SEMANTIC_BUDGET=65536`, which pins the condition a 50k project hits at the
    default budget.
  - It checks the project, edits one body, and asserts `checked_bodies.performed == 2`
    and `reused == 23`, with diagnostics equal to a `--no-cache` check.
  - The baseline compiler performs 21 there (`.tmp/cas/ratchet_probe.py`), so the test
    fails on `fc742bd4`.

## Where the time goes now

Edit → check, final compiler, in-process phases (`--timings=json`, best of 3 at load
6.5–6.8), ms:

| Phase | 50k | 200k |
| --- | --- | --- |
| source load + header lex | 14 | 59 |
| cached syntax replay (decode) | 22 | 85 |
| source merge | 17 | 69 |
| dependency keys | 16 | 70 |
| summary slot load / store | 4 / 3 | 14 / 13 |
| bodies checked + effect/mutation passes + summaries | 2 | 10 |
| in-process total | 92 | 375 |
| wall clock (process start, verdict and syntax writes, untimed catalog work) | 119 | 440 |

What is left is whole-project plumbing, all linear: each module's cached AST is decoded,
merged into one program and keyed. Removing it needs lazily loaded module bodies, so
that a stood-in body's syntax is never decoded. That is the next step if check has to
fall further.

Build frontend after an edit at 200k (`emit-project-qbe --timings=json`): 1.65 s, made
up of

- check 0.72 s, of which fresh body checks are 0.36 s: a lowering command still checks
  every body;
- lowering 0.24 s;
- emission 0.59 s.

The rest of the 3.2 s build is the driver, codegen and the link. To stand bodies in
inside `build`, the per-function fragment reuse would have to be keyed without lowering
the function, which is `build-residue` territory. About a quarter of the remaining
body-check time is page faults on the 1.6M-node checked program.

## For the integrator

- **Files outside the listed scope**, all on the check path; no other lane owns them:
  - `lexer.zig`, `removed_names.zig`, `python_layout.zig`, `project.zig`,
    `project_syntax.zig`, `interfaces.zig` and `module_names.zig` (lexing and name
    resolution);
  - `effects.zig` and `origins.zig` (stand-in facts in `Request`, and `seedFunction` /
    `mutationPass` split out of `effects.check` for the complexity limit);
  - `semantic_key.zig` (the `prepare` signature, identity fingerprints, name recall);
  - `compiler.zig` (the `semantic_summary` export), `features.json`, docs.
- **`main.zig`**, all in `listModulesWithCache` and its helpers:
  - `openSummaries` / `closeSummaries` / `rememberSummaries`;
  - the new `Lifetime` parameter;
  - `listModules` passes `.process` and `check-session` passes `.session`.
- **Minimal hooks in other lanes' areas.** None in emission, the driver, the fragment
  store or the test runner. But the build frontend (`emit-project-qbe`) now uses
  summaries for pass facts and no longer reads the retained-tree store, so its
  `checked_bodies` counts change: every body is performed and none reused.
  `native-test-*` commands are untouched.
- **Conflict risks.**
  - `sema.zig`: `checkCached` gained `openPlan`, `checkInstance`, `retryOr` and the pass
    wiring; `checkFunction` is split into `beginFunction` / `finishFunction` /
    `standInFunction`.
  - `project_compile.zig`: `checkWithCache` retry.
  - `semantic_cache.zig`: `Context.summaries`, `Reuse.stood_in`, `Session.standIn`.
  - `frontend_cache.zig`: the summaries slot and `readEntry`.
  - SPEC bullets: CHECK-SCALE-LEX-1, CHECK-SUMMARY-1, CHECK-SUMMARY-2,
    SEMANTIC-KEY-IDENTITY-1, CHECK-SCALE-KEYS-1.
- **Caches.**
  - `semantic-functions-v6` and `decl-v4` change every dependency context, so the
    retained-tree store and the C3 entries miss once.
  - The summaries slot is `check-summaries-v2` inside the unchanged
    `mylang-frontend-cache-v4` namespace.
- **One existing test adjusted.** In `semantic_cache_test.zig` (*shared budget honors the
  ordinary one-entry hash minimum boundary*), the fresh-cache below-cost case now uses
  `exact - 64`. A fresh entry's arena cost depends on whether the backing allocator
  extends a chunk in place, which the lexer's allocation changes shifted by 8 bytes. The
  one-byte boundary is still asserted on the transferred entry.
- **Measurement scripts** are in the worktree's `.tmp/cas/`:
  - `final.py` (the table above) and `checkloop.py`;
  - `noop.py`, `emit_probe.py` (build frontend phases) and `ratchet_probe.py`;
  - `fold.py` / `tree.py` (perf with inline frames);
  - the raw `final*-*.json`.

## Known gaps and follow-ups

- **`build`, `run` and `test` still check every body**, for the reason above.
- **Syntax replay and the merge are linear in the project** (0.15 s at 200k), and so is
  key preparation's per-function resolution (70 ms).
- **The retained-tree store never replays body-phase warnings such as `W_DEPRECATED`.**
  This was already true before the lane. `check` no longer uses the store; single-file
  `check`, `lint`, `context` and the other inspectors still do.
- **The summary slot is rewritten after every successful check** (13 ms at 200k, 6.6 MB).
  Writing only changed entries would need a per-module layout.
- **`mylang.json` lint settings are applied after the check** (they only read
  diagnostics), so they are not part of the summary key. If a future setting changes
  what the checker itself reports, it has to join the dependency contract.

## Gate (at `1eb0e8fe`)

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 90/90 steps, 1,864 tests run, 0 failed |
| `zig build test-qbe --summary all` | 51/51 steps, 361/361 tests |
| `zig build test-qbe-build --summary all` | 33/33 steps |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |
