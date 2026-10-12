# Progressive self-hosting with performance parity: plan (2026-10-12)

Status: proposed, 12 October 2026. Written against the development-loop
integration branch `claude/lane-a-env-identity-20261012` at `7313c483e`, which
holds D1 to D6 of the
[output-keyed shared receipts plan](output-keyed-shared-receipts-plan-2026-10-12.md),
and against a read-only inspection of the self-hosting branch
`codex/selka-bootstrap-20261011` at `dff9304b9` (11 October, 20:45 UTC; merge
base `1d202d41b`; 3,944 files and 261,871 insertions ahead of `main`
`4892aaba4`). Nothing in this plan is implemented. No production source
changed. The codex worktrees were read, not edited.

The plan answers three questions the user asked after the development-loop
audit: how to move the compiler into Selka incrementally until it hosts itself,
how to keep performance parity throughout, and how to know at any moment what has
moved, what is left, and whether the benchmarks still hold.

## 1. Summary

Keep the Zig backend and the pinned Zig toolchain. Move the frontend into one
Selka program that reads sources and emits Core IR, prove each stage by shadow
comparison against the live Zig implementation, flip the default stage by stage,
and delete the Zig stage one release after each flip. Do not restart a
whole-tree port, and do not keep adding per-seam process components in their
current shape: that shape fails its own performance policy for architectural
reasons (process launch, artifact authentication, frame serialization and
unoptimized seed builds), not because Selka-generated code is slow.

Three instruments make the parity promise checkable. Macro benchmarks discover
regressions and micro benchmarks guard fixes, under a written reduction rule
(§7.1). Benchmark results become output-keyed receipts so that after any change
only the rows whose binaries changed are re-timed (§7.2). A machine-readable
ownership inventory and a local dashboard report what has moved, what is left
and the latest benchmark state, computed from artifacts rather than maintained by
hand (§8).

## 2. Where we start

### 2.1 Two prior approaches

| Approach | State | Lesson |
| --- | --- | --- |
| Whole-frontend port P0 to P6, September 2026 ([pause record](selfhost-pause-and-salvage-2026-09-17.md)) | Paused 17 September at checkpoint 32; 1,005 `.my` files, 19,243 lines; tag `selfhost-paused-2026-09-17` | It tracked a frozen stage-0 oracle while the language moved, so every language change had to be made twice. |
| Progressive components, codex lane, `codex/selka-bootstrap-20261011` ([wave 1](selka-selfhost-wave1-2026-10-09.md), [parallel work brief](selka-incremental-selfhost-parallel-work-2026-10-10.md)) | Seven seed-built Selka components behind a framed process protocol, each with `reference`, `shadow` and `component` modes; all seven default to `reference` | Shadow against the live Zig implementation cures the stale-oracle problem. The process shape does not meet the branch's own 1.5× policy. |

### 2.2 The components on the bootstrap branch

Lines are from `git show dff9304b9:…`, `.my` files only.

| Component | Lines | Files | Mode variable | Built by the seed as |
| --- | ---: | ---: | --- | --- |
| `lexer_pilot` | 1,263 | 8 | `MYLANG_LEXER_MODE` | debug, -O0 |
| `parser_pilot` | 6,908 | 42 | `MYLANG_PARSER_MODE` | debug, -O0 |
| `declaration_index` | 1,326 | 7 | `MYLANG_DECLARATION_MODE` | debug, -O0 |
| `type_interface` | 2,150 | 18 | `MYLANG_TYPE_INTERFACE_MODE` | debug, -O0 |
| `body_check` | 33,175 (20,084 checker, 12,831 tests, 260 adapter) | 207 | `MYLANG_BODY_CHECK_MODE` | `--release` |
| `cache_plan` | 854 | 6 | `MYLANG_CACHE_PLAN_MODE` | debug, -O0 |
| `test_index` | 199 | 4 | `MYLANG_TEST_INDEX_MODE` | debug, -O0 |

The seed is the frozen compiler in `selfhost/component-seed.json`; the admitted
source profile is `component-v1` ([bootstrap profiles](../bootstrap-v1.md)), which
is why the lexer pilot spells token kinds as strings rather than an enum. Installed
component executables are 1.3 to 9.1 MB each.

### 2.3 The branch's performance policy and its results

`selfhost/tests/measure_performance_ratio.py` requires every row's median and
nearest-rank p95 to be at most 1.5× the frozen Zig host, 36 rows over six
two-module workloads ([budget](../tooling/selfhost-performance-budget.md)).

| Row (B4 record audit, 11 October, `BODY_CHECK=component`) | Native median | Selka median | Ratio |
| --- | ---: | ---: | ---: |
| compile, fresh application cache | 17.5 ms | 76.4 ms | 4.37× |
| check | 1.07 ms | 4.86 ms | 4.54× |
| compile, warm | 1.76 ms | 9.00 ms | 5.11× |
| test, cold | 18.8 ms | 82.7 ms | 4.39× |
| test, warm | 1.81 ms | 12.7 ms | 7.02× |
| runtime of the generated program | 1.03 ms | 1.11 ms | 1.08× |

Other measurements on the branch: a release-built producer instead of the seed's
-O0 roughly halves the overhead (list workload: compile-fresh 6.19× to 3.49×,
check 6.37× to 3.65×) but stays above budget; an edited body producer rebuilt
uncached in 49.9 s, against 2 to 7 s for a Zig compiler rebuild
([development-loop audit](development-loop-audit-2026-10-12.md) §2). The native
baselines are one to nineteen milliseconds, so the ratios measure fixed
per-exchange cost. No compiler-shaped input (the component's own 33k-line
source, a 191k-line project) has been timed in component mode; the body profile
does not yet admit them.

### 2.4 What is still native after all seven components

From the branch's own ownership inventory (the file
`docs/audits/selka-semantic-ownership-boundary-2026-10-11.md` on the bootstrap
branch; it is not on this branch): catalog and declarations in `sema.checkProgram`, generic contracts, executable
entry, foreign declarations and aliases, effects and origins, domain codecs,
binding and import diagnostics, removal repairs, and incremental semantic
retention. In component mode `sema.checkProgram` sets its cache to null, so
component mode has no incremental reuse at all. The branch's typed-to-Core audit
names the next contract: "native Core snapshot plus exact module deltas".

### 2.5 The Zig compiler by stage (non-test lines at `7313c483e`)

| Stage | Files | Lines |
| --- | --- | ---: |
| Lexer, parser, syntax tree, type identity, interfaces | `lexer`, `parser`, `ast`, `records`, `type_identity`, `interfaces` | ≈5.9k |
| Semantics: catalog, bodies, generics, contracts, effects, origins, entry, codecs | `sema*`, `generic_bodies`, `nominal_templates`, `effects`, `origins`, `value_semantics_check`, `prelude_builtins`, `constant_values`, `entry_adapter`, `domain_codecs`, `c_abi`, `typed` | ≈18.4k |
| Incremental semantic retention | `incremental`, `invalidation`, `semantic_cache`, `semantic_key`, `semantic_store`, `semantic_entry`, `frontend_cache` | ≈6.6k |
| Lowering to Core IR | `core/build`, `core/build_dict` | ≈2.9k |
| Core passes, ownership, emission, IR | `core/passes`, `inline`, `version`, `facts`, `vector`, `own`, `single_owner`, `zero_rc`, `emit_llvm`, `emit_homes`, `emit_units`, `ir`, `verify_ir`, `canonical_ir`, `ir_snapshot` | ≈16.1k |
| Driver, caches, test runner, CLI | `core/driver`, `pipeline`, `test_runner*`, `lowering_cache`, `optimization_cache`, `stage_*`, `unit_cache`, `build_replay`, `main`, `core/main` | ≈13k |
| Tooling that consumes the frontend | `lint`, `doctest_command`, `navigation`, `context`, `format_spec`, interface files, `fix` | ≈8k |
| Whole frontend tree `src/*.zig` | | 77,662 |
| Whole backend `src/core/*.zig` | | 55,432 |
| C runtime `src/core/runtime` | | 9,269 |

### 2.6 Selka today

Generated code is at parity: the 27-program parity suite ran at 0.74× Zig
ReleaseSafe on 9 October, with text operations at 2.61×, the Lox VM at 1.62× and
the EDA application at 1.21× ([wave 3](runtime-parity-wave3-2026-10-09.md)).
Compilation of a 191k-line project after a helper edit takes 3.1 to 4.5 s, of
which the Zig frontend is 1.1 to 1.3 s; an unchanged build replays in 14 ms; a
cold native build at that size is 219 s (development-loop audit §2). The
language has records, tagged unions with recursive boxed payloads, generics with
structural and named constraints, noncapturing lambdas, dictionaries, sets,
bytes, byte buffers, `Result`/`Option` with `fails`/`try`/`fail`, capabilities,
fifteen embedded standard modules, scalar `extern func`, and experimental
zero-RC and single-owner ownership modes. It has no raw pointers, no capturing
closures and no stored references; values are one-count reference counted with
copy-on-write.

## 3. Decisions

- **H1. Core IR is the frontend/backend contract and canonical digests are the
  parity oracle.** The Selka frontend ends by emitting a Core IR snapshot in the
  `ir_snapshot` wire form. The host validates it with `verify_ir` and compares
  `canonical_ir` function digests with the native lowering during migration.
  Identical canonical IR yields identical LLVM text, identical objects and
  identical linked programs by construction, so generated-program performance
  stays at parity for free until the backend itself moves. Until lowering is
  ported, the contract is the typed batch the body checker already produces.
- **H2. One Selka frontend program, resident for the duration of a compiler
  invocation.** It owns source reading, lexing, parsing, declarations, types,
  bodies, contracts, effects and origins, diagnostics ordering and, last,
  lowering. The host sends a file list and options over the existing framed
  envelope on pipes and receives diagnostics plus the contract of H1. The
  executable is authenticated once per invocation, not once per exchange. This
  is the interop plan's milestone 4 ("qualified binary-input worker") brought
  forward, and it stays within [D6](../adr/D6-runtime-boundary.md): values cross
  the boundary, nothing else, and the worker is qualified for cancellation,
  deadline, crash, restart and identity change like the batch components.
- **H3. Shadow against the live Zig implementation is the only parity oracle.**
  No frozen stage-0 oracle. [D7](../adr/D7-feature-delay.md)'s one-release delay
  applies to the full compiler; components are re-seeded at every stage flip from
  a tagged, receipted build of the current compiler, qualified by building every
  component with both seeds and requiring identical outputs over the corpus.
  Compiler code may then use enums, dictionaries, sets, unions, generics and the
  zero-RC modes.
- **H4. Two build policies for Selka compiler code.** Development: the current
  compiler, optimized debug, one unit per module, through the shared
  content-keyed unit store (path-free after D2), no reproducibility rebuild.
  Qualification and production: `--release` whole-program with the
  reproducibility check, built by the qualified seed, in the gate only.
- **H5. A stage flips when its gate (§6.2) is green, stays shadowed by the Zig
  stage for one release, and the Zig stage is then deleted.** Deletion is where
  the development-loop win comes from: a smaller Zig compiler rebuilds faster
  and has fewer tests to re-verify.
- **H6. Benchmark results are output-keyed receipts.** A row's receipt is keyed
  by the bytes of the binaries that ran, the harness and suite identities, the
  machine identity and a baseline epoch. After a change, each arm is replayed,
  digests are compared, and only rows whose bytes changed are re-timed, both
  arms interleaved. This does not depend on the compiler's implementation
  language; the Zig monolith only means the compiler is rebuilt before the
  replay.
- **H7. Macro discovers, micro guards.** Every micro benchmark has a macro
  parent, a Zig twin, a byte-identical expected output, a ratio threshold and a
  provenance note. A reduction is accepted only when its ratio matches the share
  attributed in the macro. The thresholded micro set stays small; saturated
  micros retire to dated evidence.
- **H8. Progress is computed, never hand-maintained.** A committed ownership
  inventory lists each stage's Zig and Selka sources, mode variable, default,
  flip dates and gate status. A collector derives line counts at `HEAD`, reads
  the latest benchmark artifacts and receipts, and a standard-library-only
  local server shows the result.

## 4. Architecture

### 4.1 Data flow

Today, in component mode for the body checker, the host lexes and parses, then
ships raw syntax trees, sources, declaration facts and catalog descriptors to a
fresh `body-check` process on every command (schema 11, frames up to 64 MiB,
up to 2,097,152 graph values), materializes the returned typed batch, and runs
contracts, effects, origins, codecs and diagnostics itself. Five input schemas
exist, one per seam, each with its own hostile-reply inventory.

Target:

```
mylang (Zig host: CLI, caches, backend, driver, test runner)
   │  spawn once per invocation, authenticate once, framed pipes
   ▼
selka-frontend worker (Selka)          ──► diagnostics
   read sources → lex → parse → declare → type → check bodies
   → contracts → effects/origins → lower   ──► Core IR snapshot (H1)
   ▲
   │  during migration the host computes the same stage natively and compares
   │  at the current seam (shadow); the seam moves outward as stages flip
```

One output schema (`frontend-reply-v1`: diagnostics, typed batch or Core IR
snapshot, cache facts, work counters) replaces the per-seam input schemas. The
host keeps the per-stage mode variables during migration for shadow and
fallback-free component selection, but every exchange runs through the one
resident worker.

### 4.2 The worker

The worker reuses what exists: `component_launch` for the sealed executable and
bounded child lifecycle, the 64-byte envelope with a new magic, `component_session`
for authenticated bytes. New: a request loop on stdin/stdout pipes, one request
in flight, a per-request deadline, kill and reap on timeout or host exit (the
audit found three test shards hung since 21 September on a path with no timeout;
the worker must not add a fourth), and a `quit` message. One worker per compiler
process; `check-session` keeps its worker for the session's lifetime. No
cross-process worker sharing in version 1.

### 4.3 Build policy and seed cadence

`selka-components --dev` (and `zig build components-dev`) builds every component
with the current `zig-out/bin/mylang`, `--optimize-debug`, per-module units via
the shared store, and installs into a development component directory that
`MYLANG_COMPONENT_DIR` selects. `zig build components` keeps the qualified seed,
`--release`, the reproducibility rebuild and the production manifest. Expected
cost of a one-module frontend edit under the development policy: well under the
2 to 7 s Zig loop, to be measured in Lane S2 (the 191k-line project's helper edit
costs 3.1 to 4.5 s today, most of it in the Zig frontend and optimizer).

Re-seeding (H3) is a documented procedure with a script: tag the commit, build
the seed, record its receipt, build all components with old and new seed,
require identical corpus outputs and identical qualification results, switch
`selfhost/component-seed.json`, keep the previous pin in history.

## 5. Stage order

| Order | Stage | Zig today | Selka today | Oracle | Deleted after flip |
| --- | --- | ---: | ---: | --- | --- |
| 1 | Lexer, parser, declarations, type interface | ≈5.9k | 11.6k across four pilots | token and syntax fixtures; declaration tables; signature diagnostics; shadow over the corpus | `lexer.zig`, `parser.zig`, `ast.zig`, declaration and signature halves of `sema.zig` and `interfaces.zig` |
| 2 | Bodies, generic contracts, effects, origins, entry, codecs, diagnostics ordering, incremental retention | ≈18.4k + 6.6k | 20k checker on a narrow profile | typed batch and diagnostics equal; semantic cache hit rates equal | the rest of `sema*`, `generic_bodies`, `effects`, `origins`, the semantic caches |
| 3 | Lowering to Core IR | ≈2.9k | none | canonical digest per function equal; `verify_ir` passes; forged snapshots refused | `core/build*.zig`; the whole Zig frontend is gone after this step |
| 4 | Core passes, ownership, emission | ≈16.1k | none | Core IR in, Core IR out by digest; LLVM text byte-equal | `core/passes`, `own`, `emit_*` |
| 5 | Driver, caches, test runner, CLI | ≈13k | none | behavioural fixtures; receipts unchanged | last, or kept as a thin Zig launcher; `zig cc` and the C runtime stay external |

Tooling that consumes the frontend (lint, doctest, navigation, context, interface
files, fix; ≈8k lines) follows stage 2 or 3, whichever produces the trees it reads.

## 6. Flip gate and deletion

### 6.1 Corpus C

Every shadow comparison runs over the same corpus: `tests/lang` (337 programs),
`test/core`, `tests/value_semantics`, `tests/goldens`, `examples`, the EDA
application sources under `experiments/velocity-evidence/v1/application-sources`,
the parity suite, the Lox ports, every component's own source, and the
`selfhost/` fixtures. Additions to C are allowed at any time; removals need a
written reason.

### 6.2 Gate conditions, per stage

| Gate | Condition | Measured by |
| --- | --- | --- |
| G1 parity | Shadow equal over all of C: diagnostics byte-equal in code, span, message, notes, repairs and order; for lowering, canonical function digests equal and `verify_ir` clean | shadow run in the gate, nightly over C |
| G2 performance | Every row of the 36-row sweep and the compiler-shaped rows (§7.3 C1 to C3) at or under 1.5× median and p95 for the flip; at or under 1.0× within the paired bootstrap interval before deletion | `measure_performance_ratio.py` in an exclusive timing window |
| G3 edit loop | Selka stage edit to a ready component under the development policy at or under the Zig edit loop measured the same day | Lane S2 harness |
| G4 incremental | Semantic cache and specialization replay hit rates in component mode within 1 % of reference on the 40-edit cohort; test receipts unaffected | the cohort runner |
| G5 qualification | The branch's hostile-reply, malformed-frame, deployment-failure and edit-rebuild inventories pass for the worker | `test-selfhost-*` targets |

### 6.3 Deletion

After the flip the Zig stage remains selectable as `reference` and runs under
nightly shadow over C for one release, or fourteen days with zero mismatches,
whichever is longer. Then the Zig stage is deleted in one commit that records the
lines removed and the `zig build` and gate time before and after. The ownership
inventory records both dates.

## 7. Benchmarks

### 7.1 Macro discovers, micro guards (H7)

Macro suites, the discovery instruments: the parity suite and library scans in
`bench/parity`, the 40-case runtime suite in `benchmarks/runtime`, the
applications (EDA, Lox, S-expression parser), and the compiler-shaped rows of
§7.3. Micro suite, the guard: the eleven kernels in `bench/parity/micro` plus
whatever the rule below admits. The 22 September audit is the standing caution:
the micro set sat at 1.36× Zig while the real programs sat at 5.8×, because the
micros measured mechanisms already fixed.

The rule for every slow finding:

1. **Record it in the macro first.** The workload enters the suite with its Zig
   twin; its ratio is the number to move.
2. **Attribute before reducing.** Profile, `--stats`, `--timings=json` and the
   counters name the mechanism. Price it as the parity audit did: edit the
   emitted LLVM with the suspected cost removed, rebuild with the same toolchain,
   re-time. That bounds what the fix can buy in the real program.
3. **Reduce to the mechanism, not the syntax.** Keep the data-size regime, the
   sharing pattern that triggers a copy, the function size and the module
   boundary. A reduction is accepted only when its ratio to the twin matches the
   share attributed in the macro within the bootstrap interval. A micro at 1.0×
   for a macro at 3× has lost the mechanism and is not added.
4. **Add it as a thresholded pair**: twin, byte-identical expected output, an
   entry in `bench/parity/thresholds.json`, and a provenance note in `MICRO.md`
   (source workload, commit, before and after ratios, mechanism). Where the slow
   thing is an obvious spelling with a fast alternative, carry both spellings.
5. **The fix must move the macro.** Re-measure both, then tighten the micro's
   threshold to the new ratio.
6. **Curate.** Merge micros that share a mechanism; retire a micro whose macro
   parent is gone or that has sat at parity for a release to the dated evidence
   under `experiments/`, as the suite already separates maintained benchmarks
   from evidence.
7. **Compile time reduces the same way.** A generated program that reproduces the
   shape (N records of M fields, deep nesting, one wide generic) measured with
   the frontend phase profile and the build report. The budget is the Zig
   frontend's time on the same input while it exists, and a scaling exponent
   afterwards.

Timing assertions never enter `zig build test`; thresholds are checked by the
opt-in parity step inside an exclusive timing window on a pinned core.

### 7.2 Output-keyed benchmark receipts and affected selection (H6)

A receipt (`bench-receipt-v1`) is keyed by: the row identity (suite, benchmark,
size, arm set); the digest of the suite specification and expected output; the
harness identity (a digest over the harness sources, like `runner_identity`);
the binary digest of every arm in order; the machine identity (CPU model and
microcode, kernel release, governor and energy preference, the pinned CPU list,
the SMT sibling policy, memory size); and the baseline epoch. Its value is the
samples, median, p95, paired ratio with its interval, the date and the compiler
commit.

| What changed | Rows re-timed |
| --- | --- |
| Compiler source; a benchmark's emitted LLVM unchanged | none for that row: same bytes, receipt reused |
| Compiler source; a benchmark's LLVM changed | that row, both arms, interleaved in one session |
| Runtime C source or toolchain | every row: the runtime object is linked into every program |
| Benchmark source or expected output | that row |
| Harness, suite specification or thresholds | every row |
| Machine identity | every row; a new epoch begins |

Procedure for `bench_parity.py run --affected` and `runner.py --affected`: build
every arm (a replay when nothing changed: milliseconds, no process), digest the
binaries, look up receipts, time only the misses with their twins in the same
interleaved session, merge reused rows into the report marked `reused`, apply
thresholds to every row, write receipts for the rows timed. A weekly baseline run
re-times everything and opens a new epoch, bounding drift that reuse would
otherwise hide. Both harnesses already compute the binary digests they need
(`binary_sha256` per arm; the runtime manifest's `binary_hashes`), and the
driver already carries the program key in `Outcome.program_key`; printing it in
`cache-report-v1` is optional, since hashing the output binary is exact.

### 7.3 Compiler-shaped rows and compile-time receipts

Four macro rows measure the compiler as a workload. C1: the body checker (or the
worker) checking its own source. C2: a 191k-line project check (Zig frontend:
1.1 to 1.3 s today). C3: the worker checking all of `tests/lang` as one batch.
C4: a one-module edit of the Selka frontend to a ready component under the
development build policy, against the Zig edit loop measured the same day.

Compile-time rows cannot key on the generated program, since the artifact under
test is the compiler. They key on a frontend identity: first a listed subset of
sources in the style of `runner_identity`, later the transitive import closure
of the phase's entry module computed by `build_identity.zig`, which makes it
exact. A self-hosted, module-granular compiler gets this for free from its unit
keys; it is the one development-loop advantage self-hosting adds that the Zig
compiler cannot match, and it is narrow.

## 8. Progress tracking (H8)

### 8.1 Ownership inventory

`selfhost/ownership.json`, committed, one entry per stage of §5 plus the two
cache components:

```json
{"version":"selfhost-ownership-v1","stages":[
 {"id":"lexer","title":"Lexer",
  "zig_sources":["src/lexer.zig"],
  "selka_sources":["selfhost/components/lexer_pilot"],
  "mode_variable":"MYLANG_LEXER_MODE","default_mode":"reference",
  "gate":{"G1":false,"G2":false,"G3":false,"G4":false,"G5":true},
  "flipped_on":null,"deleted_on":null}]}
```

Facts a lane sets when it lands (default mode, flip and deletion dates, gate
booleans) live here and are checked by a unit test against the code's defaults
in `config/component_runtime.zig`. Everything numeric is computed.

### 8.2 Collector

`scripts/progress/collect.py` (standard library only) computes, at `HEAD`: Zig
non-test lines per stage from the inventory's file lists (so the figure cannot
drift from the tree), Selka lines per stage, lines deleted since the plan's base;
reads the newest parity and runtime JSON reports, the newest
`measure_performance_ratio` JSON, the receipt store (rows reused against rows
re-timed per run, current epoch, machine identity), and the latest shadow run
over C; writes `progress/data.json` and appends one line to
`progress/history.jsonl`. It runs after every baseline and shadow run and
nightly. It never runs inside the gate or the install graph.

### 8.3 Dashboard

`scripts/progress/serve.py --port 8765` serves `progress/index.html`,
`data.json` and `history.jsonl` from `http.server` on `127.0.0.1`; `--render
out.html` writes one self-contained page for sharing. No external scripts or
fonts: the page must work offline. Sections:

1. **Headline**: stages default-on (count, and weighted by Zig lines), Zig lines
   remaining on the default path, Zig lines deleted, days since the last shadow
   run with zero mismatches.
2. **Stages**: one row per inventory entry with default mode, shadow equality
   over C, worst performance ratio, G1 to G5, flip and deletion dates.
3. **Macro benchmarks**: latest ratio per row against its threshold, a trend
   from `history.jsonl`, the epoch and machine identity, reused against re-timed
   rows for the latest run.
4. **Micro benchmarks**: the same, plus each micro's macro parent.
5. **Development loop**: C1 to C4 and the Zig edit loop over time.
6. **Freshness**: collection time, commit, and a warning when any source is
   older than seven days.

## 9. Lanes

Each lane runs in its own worktree and branch, never on `main`, never pushed, and
never in a codex checkout. Lanes that need the bootstrap branch start from a
private worktree of `codex/selka-bootstrap-20261011` at `dff9304b9` or its later
integration, with the codex lane told which files are being changed.

| Lane | Deliverable | Depends on | Start |
| --- | --- | --- | --- |
| **S0 Measurement** | Three arms of the 36-row sweep (seed -O0, current-compiler release, release as a resident prototype) plus C1 and C2; a cost decomposition into launch, authentication, serialization, -O0 and algorithm; report | bootstrap branch, timing windows | now |
| **S1 Resident worker** | The worker of §4.2 with its qualification; all seven seams routed through it; one output schema | S0's numbers; agreement with the bootstrap owner | after S0 |
| **S2 Build policy and seed cadence** | `--dev` builds through the shared store; re-seed script and procedure; profile widened and requalified; C4 measured | D2 landed (it is) | now, in parallel with S0 |
| **S3 Frontend flip 1** | Lexer, parser, declarations, type interface default-on by §6; the worker reads sources itself for these stages; deletion commit prepared | S1, S2 | after S1 |
| **S4 Semantics** | Body checker widened to the whole language; contracts, effects, origins, entry, codecs, diagnostics ordering and incremental retention in Selka; G4 green | S3 | after S3 |
| **S5 Lowering** | Core IR snapshot contract frozen; Selka lowering; digest oracle over C; `verify_ir` and forged-snapshot refusal; Zig frontend deletion | S4 | after S4 |
| **S6 Benchmark receipts and discipline** | §7.1 rules in `MICRO.md`; receipts and `--affected` in both harnesses; compile-time rows C1 to C4 and the frontend identity; weekly baseline job | D1 landed (it is) | now |
| **S7 Progress dashboard** | §8: inventory, collector, server, render; the inventory test | nothing | now |
| **S8 Backend** | Passes, ownership, emission by IR-in/IR-out; LLVM text equality; driver last | S5 | later |

S0, S2, S6 and S7 are independent of one another and of the codex lane's active
checkout, and can start today.

## 10. Acceptance matrix

| # | Claim | Method | Passes when |
| --- | --- | --- | --- |
| 1 | Launch cost is the dominant term in the 4.4× to 7.2× | S0's three arms on the 36 rows | the resident release arm is within 1.5× on every row |
| 2 | Compiler-shaped inputs are measured | C1 and C2 in all arms | numbers recorded with intervals; no claim of parity until G2 |
| 3 | The worker is qualified | §6.2 G5 inventories against the worker | cancellation, crash, oversize, restart and identity change each fail closed |
| 4 | The development build policy beats the Zig loop | C4 against `zig build` after a one-line `src/parser.zig` edit, same day, same window | median and p95 of C4 at or under the Zig loop |
| 5 | Re-seeding is safe | build all components with old and new seed | identical outputs over C and identical qualification results |
| 6 | Stage 1 parity | G1 over C for lexer, parser, declarations, type interface | zero mismatches |
| 7 | Stage 1 flip | defaults changed; gate green; nightly shadow installed | all of G1 to G5 green; inventory updated |
| 8 | Deletion pays | `zig build` and gate time before and after the first deletion commit | both recorded; neither worse |
| 9 | Incremental parity | 40-edit cohort in component and reference modes | hit rates within 1 %; test receipts identical |
| 10 | Lowering parity | canonical digests over C | equal for every function; `verify_ir` clean; a forged snapshot is refused |
| 11 | Benchmark receipts select exactly | a comment-only compiler edit; an edit changing one program's LLVM; a runtime C edit; a governor change | 0 rows, that row's arms, every row, every row with a new epoch |
| 12 | Micro discipline | a new micro admitted under §7.1 | twin, expected, threshold, provenance and macro parent present; reduction ratio within the attributed share |
| 13 | Dashboard | `serve` offline on localhost; `render` twice on the same inputs | all six sections populated from artifacts; byte-identical renders; inventory test green |
| 14 | No regression in generated code | parity suite under receipts after every stage flip | every row within threshold; identical binaries reuse receipts |

## 11. Measurement protocol

Timing runs only in exclusive timing windows (`scripts/build-slot.sh timing`),
pinned to the CPUs the harness reserves, with the sibling idle check recorded.
Twenty samples per row; medians and nearest-rank p95; paired ratios with 95 %
bootstrap intervals; arms interleaved within every round; fact verification and
leak checks disabled consistently in both arms during timing; the machine
identity of §7.2 recorded with every result. Compile-time rows report the
compiler's own phase timings beside wall time. Nothing is claimed from a
measurement taken beside a gate.

## 12. Coordination and risks

- **Two agent teams.** The codex closeout plan of 12 October assigns S04
  ("narrow producer identity with a real adopted boundary") and S09 ("integrate
  the existing self-hosting work"). One owner should hold the worker protocol
  and the ownership inventory so the teams do not define two. With output-keyed
  receipts, a parity-proven frontend swap is invisible to the test caches, which
  is correct; producer identity belongs in the frontend stage caches and in
  diagnostic parity, not in execution verdicts.
- **Selka compile throughput at scale is unmeasured.** C2 may need two or three
  of the runtime levers already in the tree before it is within budget: flat
  index tables in the style of `typed.Program` rather than recursive boxed
  unions for trees, zero-RC or single-owner ownership for owned tables, borrowed
  text and byte views so the lexer allocates nothing per token, enum kinds,
  borrowed-key dictionary probes for symbol tables, the byte builder for
  emission.
- **Profile widening against seed trust.** H3's re-seed procedure is the
  control; a widened profile is never adopted before the two-seed equivalence
  check passes.
- **Worker lifecycle.** A resident process adds hang and leak modes; G5 and the
  kill-and-reap rule of §4.2 are mandatory, not optional.
- **Receipts hiding drift.** Epochs and the weekly baseline bound it; a receipt
  is never reused across machine identities.
- **Dashboard rot.** Numbers are computed from the tree and the artifacts; the
  only hand-set fields are checked by a test.

## 13. Calendar (estimate)

At the current agent throughput: two to three weeks for S0, S2, S6 and S7
together; S1 in parallel once S0's numbers are in; two to three months to flip
the frontend through bodies (S3, S4); one to two months for S5 and the deletion
of the Zig frontend; the backend after that. The long pole is widening the body
checker from its profile to the whole language plus the natively owned stages.
These are estimates, not commitments; the acceptance matrix, not the calendar,
decides when a stage flips.

## 14. What changed from the conversation version

The architecture, order and gates are unchanged. Added: the macro/micro rule
(§7.1, H7); output-keyed benchmark receipts with affected selection (§7.2, H6);
compile-time rows and the frontend identity (§7.3); the ownership inventory,
collector and dashboard (§8, H8); lanes S6 and S7; acceptance rows 11 to 14.
