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

## Addendum: false-clean incremental check (commit `c9fde868`)

The coordinator found, with a differential harness, that an incremental `check` could
stay green over a program a cold check rejects. It reproduced with the baseline
compiler `fc742bd4` too, where a cached `build` also linked the stale program, so the
hole predates this lane.

### Cause

A body's dependency context is a digest over the declarations its syntax names,
folded transitively through those declarations' own references. Four gaps let a
dependency drop out:

1. **Composite type spellings resolved to nothing.** A field typed `list[Inner]`,
   `dict[str, Inner]`, `Option[Inner]`, a tuple, an array or a callback type is one span
   that is not an identifier, so `Outer`'s fingerprint never referenced `Inner`.
   `user.first(o: shapes.Outer)` reads `o.items[0].x`. It names only `Outer`, and
   renaming `Inner.x` left its context unchanged. The same applies to a return type used
   in a chained call (`shapes.make().items[0].x`).
2. **A type declaration's own text was not in its fingerprint.** Only the names it
   resolved were. A field changed to a different composite type, a default value, or
   `record` ↔ `class` did not change it.
3. **Cycles were order-dependent.** A declaration met again while its own fingerprint
   was being computed contributed zeros, and the memo kept the result. With `A ↔ B`,
   `B`'s fingerprint could lack `A`'s content, depending on which body was keyed first.
4. **A facade re-export (`export shapes.A`) was a negative lookup** in the facade
   module, so `api.A`'s users never depended on `A`.

### Fix

There are two independent guards, and each one alone fixes every regression case below.
I checked this by running the tests with the new transitive keys but constant shape
digests, and with the old keys but real shape digests. Both pass. With neither, three
tests fail.

- **Transitive keys** (`semantic_key.zig`, SEMANTIC-KEY-TRANSITIVE-1):
  - A declaration's fingerprint is its own digest plus the sorted own digests of every
    declaration reachable from it, so it no longer depends on key order and a cycle
    folds every member into every member.
  - Composite type spellings are indexed from the parser's `TypeExpressions` tables by
    exact span and expand to their component types.
  - Type declarations frame their source text.
  - Re-exported names are registered in the facade module.
- **Touched shapes** (`semantic_key.Shapes`, CHECK-SHAPES-1):
  - A record's transitive shape digest covers its schema and the schema of every record
    its fields, cases, elements and callback slots reach, in name order.
  - A summary stores the records its checked tree touched and the combined digest of
    their shapes. The digest is order-independent, keyed by record name.
  - Retained checked trees and retained specializations store a shape per record
    reference.
  - A mismatch against the fresh catalog prevents the stand-in, or misses as
    `record-shape-changed`. This guard catches a dependency however the body reached it,
    because it reads the checked tree rather than the syntax.
  - The store format is now `semantic-cache-v2` and the summary format
    `check-summaries-v3`, so old entries miss.

### Tests

- The coordinator's exact repro is a CLI test (`test/integration.zig`, *a cached check
  sees a field renamed in a record reached only through a list element*): cached and
  `--no-cache` stderr must be byte-identical, and include `user.my:5:14
  E_UNKNOWN_FIELD`.
- In `src/check_scale_test.zig`, each case compares against a cold check in both check
  and lowering mode:
  - a field reached only through a list element, a dictionary value, an Option payload
    and a return type is renamed, then retyped from `int` to `float`: all four users are
    re-checked;
  - a managed field is added to the reached record: the lowering facts equal the cold
    ones;
  - a type cycle `A ↔ B`, where `B` is keyed from inside the cycle first, plus a facade
    re-export of `A`: all three users re-check.
- Direct tests of the shape guard:
  - a summary with a tampered shape digest is not stood in;
  - retained trees with tampered record shapes miss with `record-shape-changed`.
- **The in-repo differential harness** (`tests/incremental_diff.py`,
  `tests/fixtures/incremental/`, `zig build test-incremental`):
  - The fixture is five modules with records nested in lists, dicts, Options,
    `tuple[...]`, a union with a named-field case, class fields, an enum, a recursive
    class, a facade re-export and a `mut` parameter.
  - Its mutations: rename or retype a field (`int` → `float`/`bool`, `list` →
    `Option`), rename a case, retype a case payload, rename a def, add a parameter, drop
    `mut`, remove `public`, insert a type error or a no-op line, and change an integer
    literal.
  - Each step warms the cache on the unmutated project, applies one or two mutations,
    and requires cached and cold `check` to agree on status, stdout and stderr byte for
    byte.
  - **It is part of `zig build test`:** 120 steps, seed 1, about 9 s with the Debug
    compiler, cached like the other drivers.

### Before and after

The in-repo harness on its fixture:

| Compiler | Seeds × steps | Mismatches |
| --- | --- | --- |
| baseline `fc742bd4` | 1–3 × 150 | 12, 13, 16 |
| this lane before the fix (`8e17ed05`) | 1–3 × 150 | 14, 14, 19 |
| this lane after the fix (Debug) | 1–6 × 400 | **0 of 2,400** |

The coordinator's harness on the Lox port (`check_diff.py`, entry `main.my`, fixed
ReleaseFast compiler):

| Run | Steps | Mismatches | cold clean / rejected |
| --- | --- | --- | --- |
| seed 7, `8e17ed05` (coordinator's run) | 300 | 9, all field renames | 43 / 257 |
| seed 7, fixed | 300 | **0** | 43 / 257 (same mutation sequence) |
| seed 11, fixed | 300 | **0** | 47 / 253 |

Replaying the coordinator's nine snapshots (`cd2/mismatch-*`) with the fixed compiler
gives byte-identical cached and cold output for all nine. The `8e17ed05` compiler still
differs on them: in snapshot 1 it reports 4 errors against the cold check's 6.

### Cost

Edit → check with ReleaseFast compilers, min of 5 at load 2.2–3.1:

| Tier | before fix | after fix |
| --- | --- | --- |
| 50k | 0.102 s | 0.111 s |
| 200k | 0.448 s | 0.489 s |

Both stay well inside the targets. At 200k the added time is:

- dependency keys, +20 ms: composite types now resolve their components, and closures
  are walked;
- stand-in planning, +5 ms: shape comparison;
- the summary slot load and store, +6 ms: record lists.

No-op check is unchanged (0.017 / 0.073 s).

### Gate at `c9fde868`

| Step | Result |
| --- | --- |
| `zig build test --summary all --maxrss 8000000000` | 92/92 steps, 1,870 tests run, 0 failed; includes `test-incremental` (120 steps, 0 mismatches) |
| `zig build test-qbe --summary all` | 51/51 steps, 361/361 tests |
| `zig build test-qbe-build --summary all` | 33/33 steps |
| `zig build fmt-check` | clean |
| `zig-out/bin/mylang test tests/lang` | 569 passed across 106 programs |
