# A new compiler core, grown from the microbenchmarks — plan, 2026-10-05

**Status:** the user accepted N1–N5 on 2026-10-05, as recommended in §4. N6 (arenas) is
decided during S1. Nothing here is implemented yet.

**Runtime decision (R1, the user, 2026-10-05): the new core keeps its own runtime.**
- It grows S0's `src/core/runtime/core_rt.c`: 32-byte blocks with one saturating 32-bit count.
- It never links the shared runtime, which has two counts, the GC and a QBE-shaped ABI.
- The shared runtime's algorithms (text and UTF-8, dictionaries and sets, number
  formatting and parsing, I/O and capabilities) are ported into it as S1–S3 need them.

**Cache cleanup done the same day (DL-5):** the finished spike's 29 GB `.tmp` was removed.

**Base:** `claude/runtime-levers-plan` (the campaign's `ac72a905` plus the runtime-levers plan
and its experiments).

**Related documents:**
- `docs/audits/runtime-language-levers-2026-10-04.md` — decisions L1–L4 and D1–D4, WP-0..WP-10;
- `experiments/runtime-ideal-ladder-20261004/` — the pilot and the nine-case ladder study;
- `claude/llvm-direct-spike-20261004` — the WP-8 direct-emitter spike and its README;
- `experiments/devloop-20261005/` — the measurement scripts behind §2.

## 1. Summary

Development is slow mainly for three measured reasons:

1. **The full gate takes 38–60 minutes, and one gate slot serves every lane.**
   - The Codex coordinator's last two integration runs of `zig build test` took 37.6 and
     60.1 min.
   - The coordinator runs it with `-j2`. Its total step work (31.6 and 57.7 min) is close to
     its wall time, so it runs almost serially.
   - In the lane that changed the compiler, the gate and waiting for the slot took 42% of a
     3.7-hour run. Compiler builds took 2%, focused tests 3% and guest builds 2%.
2. **Every compiler edit rebuilds the whole compiler (20–31 s) and invalidates every guest
   test result.** The 1,579-test language suite reruns in full (78 s) after a comment-only
   change.
3. **The compiler carries back-end machinery built for rules that have since been reversed.**
   About 54k lines of QBE/RC code generation, build driver and translator serve QBE
   performance, the GC, two reference counts, the memory budget and exact trap order.

The proposal:
- Build a **new compiler core**: a new back end behind today's front end, grown from the
  microbenchmarks as the user suggested.
- Run it beside the old core, which stays the production compiler and the correctness
  oracle until the new one covers real programs.
- Fix the dev-loop items in §3 now, independent of the new core, because they slow both
  cores.

## 2. Dev-loop measurements, 2026-10-05

**Setup.**
- Host: i7-12700H, 20 threads, 30 GB.
- About nine agent lanes shared it (seven Codex, two Claude) during the run.
- Worktree: `claude-llvm-direct-spike-20261004`, with a warm Zig cache, a Debug compiler,
  and the slot wrapper `scripts/build-slot.sh` (3 build slots, **1 gate slot**).
- Script: `experiments/devloop-20261005/measure.sh`.

| Step | Time |
|---|---:|
| `zig build -Dcompiler-only` with nothing changed | 1.9–4.7 s |
| One-line edit in a back-end file → `zig build -Dcompiler-only` | 19.5–28.9 s |
| One-line edit → `zig build` (all five binaries) | 30.5–30.8 s |
| One-line edit in a front-end file → `zig build -Dcompiler-only` | 21.4 s |
| One-line edit → `zig build test-units -Dtest-filter=arena` (61 tests; includes the test-binary build) | 33.9 s |
| One-line edit → `zig build test-cli -Dtest-filter=fmt` (4 tests) | 17.5 s |
| `mylang test` on one `.my` file (12 tests), empty cache / warm | 2.5 s / 0.2 s |
| `mylang test tests/lang` (1,579 tests in 239 programs), empty cache | 103.8 s |
| `mylang test tests/lang`, everything cached (no work) | 17.8 s |
| `mylang test tests/lang` after a **comment-only compiler edit** | **78.2 s, 0 cached** |
| Full gate `zig build test` (Codex coordinator integration runs, 2026-10-04, `-j2`) | **37.6 and 60.1 min** |
| `test-qbe` + `test-qbe-build` + `fmt-check` after that | about 2.3 min |
| Gate-slot waits seen in the spike lane's logs (4 runs) | 2, 5, 19 and 30 min |
| My own gate probe, 2026-10-05 01:00 UTC | Waited 22 min for the slot behind a coordinator run, then cancelled |

**What the gate spends its time on** (parsed from the coordinator's `--summary all` logs;
the second run in brackets):

| Item | Time |
|---|---:|
| Zig test shards (12 unit + 6 CLI; 1–2.5 min each; many compile and link `.my` programs) | 22.6 min (40.8) |
| `mylang` run steps (`test-lang`, doctest, doc-coverage, drivers) | 8.2 min (15.7) |
| All compiles | 0.7 min (1.1) |
| **Total step work** | **31.6 min (57.7)**, against 37.6 (60.1) wall |

The 2026-09-18 profile measured 31 s for this gate at default parallelism. Both the test
suite and the host load have grown since.

**Where a compiler-changing agent's time went** (`agent_time.py` over the WP-8 spike
transcript; 3.67 h wall, 348 tool calls):

| Activity | Share of wall time |
|---|---:|
| Full gate and waiting for the gate slot | 42.5% |
| Benchmark measurement and fuzzing | 11.9% |
| Focused Zig tests | 2.6% |
| Compiler builds | 2.2% |
| Guest builds | 2.0% |
| Model (thinking/writing) and other | ~35% |

The WP-9 ladder lane changed no compiler code and spent 15% on measurement, with no gate.

**Guest-program build costs** (`mylang build`, ReleaseFast compiler, runtime library cached,
one program built cold; from 2026-10-04):

| Program | QBE build | LLVM -O0 build | LLVM O3+LTO build |
|---|---:|---:|---:|
| `compute` | 0.8 s | 1.1 s | 3.6 s |
| `collections` | 7.7 s | 3.1 s | 9.5 s |
| `text` | 4.1 s | 5.2 s | 11.7 s |

- QBE's code generation alone is 3–7× faster than LLVM -O0 (0.3–1.0 s against 0.9–4.5 s).
- But the QBE pipeline spends 7–10 s in its frontend phase on `collections`, against 0.35 s on
  the LLVM path. This is filed as a separate task.

**What the numbers say.**
- **The inner loop is not the main problem,** but it is not fast either: a 20–30 s rebuild
  per edit, and a 34 s focused test.
- **The expensive part is verification after a compiler change:**
  - every guest result is invalidated (78 s for the language suite);
  - the full gate is 38–60 min of nearly serial work;
  - only one gate can run at a time across about nine lanes, so waits of 20–30 minutes
    appear.

  With nine lanes, one gate slot can serve roughly one compiler change per lane every few
  hours.
- **A new core shortens all three only once it has its own small gate and the old back end
  is deleted.** During the transition both cores live in one repository, so §3 matters
  regardless.

## 3. Dev-loop fixes to make now (independent of the new core)

| ID | Fix | Evidence | Expected effect |
|---|---|---|---|
| DL-1 | **Tiered gate.** Each lane runs a *lane gate* in a build slot, targeting 5 min or less: Guardian, the roots its change touches (focused filters), and a conformance subset. The coordinator runs the full gate only when integrating, and can run it at full parallelism off-peak or on a separate machine or CI runner. | Full gate 38–60 min, nearly serial at -j2; 42.5% of a compiler lane's time; slot waits up to 30 min | The largest single saving for compiler lanes |
| DL-1b | **Make the Zig test roots cheaper.** Move behaviour tests that compile `.my` snippets inside Zig tests to `tests/lang`, as `docs/tooling/test-layout.md` already recommends. Keep Zig tests for diagnostics and host behaviour. | The test shards are 23–41 min of gate work; each shard runs about 230 tests | Removes most of the gate's work |
| DL-2 | **Key guest test results by what they run** (emitted code, runtime archive, linker and policy identity), not by the compiler's identity. A compiler edit then reruns only the tests whose code changed. | 1,579 of 1,579 tests reran after a comment-only edit (78 s) | Most compiler edits: seconds instead of 78 s |
| DL-3 | **Adopt `zig build --watch -fincremental` for the inner loop, with a guard.** The plain `-fincremental` flag without `--watch` gave 34–41 s, no better than today. Use watch mode for edit-and-test only, and require a clean non-incremental build before any gate. | Measured 2026-10-05 by changing the `build` usage text: the new text appeared in the rebuilt binary after **0.9, 13 and 17 s**, against 20–31 s for a normal rebuild | Sub-second to about 15 s per edit. Zig's incremental mode is experimental, hence the clean build before gating. |
| DL-4 | **Fix the QBE pipeline's 7–10 s frontend phase.** This is filed as a separate task. | `collections`: QBE 7.7 s vs LLVM -O0 3.1 s | QBE debug builds 2–5× faster than LLVM -O0, as code generation suggests |
| DL-5 | **Clean caches.** One finished lane left 27 GB in `.tmp`. Make `scripts/prune-caches.sh` part of lane hand-off. | Disk filled once before (2026-09-27) | Prevents disk-full stalls |

DL-1 and DL-2 matter for both cores. Under the new core they become design rules: a small
gate of its own, and test results keyed by code.

## 4. Decisions for the user

All of N1–N5 were accepted on 2026-10-05. **N6 was decided on 2026-10-05: retire arenas** (Option B in `docs/design/new-core-s1.md` §11 on `claude/new-core-s1-20261005`). The new core treats `with arena()` as a plain block now. Removing arenas from the old core and the `mylang fix` migration are a later lane.

| ID | Decision | Recommended | Why |
|---|---|---|---|
| **N1** | Build a new compiler core beside the old one | **Yes**, staged (§6) with stop/go points | The spike reached hand-written speed in 2.7k lines. The old back end is 54k lines built for reversed rules. |
| **N2** | Ship the new core as a separate executable that imports the front end as a Zig module, rather than inside today's binary | **Separate executable** (`mylang-core`, used by `mylang build --core=new`) | A smaller compile unit gives faster rebuilds, its own gate, and no risk to the old core. Merge them once the old back end is deleted. |
| **N3** | Which front-end output the new core starts from | **`typed.Program`** (the typed tree) | Bytecode drops types on loads, stores and calls, and makes the ownership decision inside QBE emission. The typed tree has types, spans, mutability and ownership summaries per local. S0 confirms this choice by lowering three kernels. |
| **N4** | What happens to the running Codex campaign | **Continue the language and runtime items** (WP-0 gate reporting, WP-4 memory budget, WP-5 one-count RC). **Finish in-flight WP-10 items, then stop new old-back-end performance work** (WP-1 policy work, WP-3 Stages A–C, WP-10c–e, and the proposed WP-11). | Both cores need L3 and one-count RC. Tuning the old back end is lost when it is replaced. |
| **N5** | Debug builds and tests in the new core | **LLVM -O0 with per-function object caching.** No QBE in the new core. Revisit an in-process interpreter only if S1 measurements demand it. | One code generator means one set of semantics. Incremental caching hides most of LLVM -O0's cost; an interpreter would be a second semantics to keep in sync. |
| **N6** | `with arena()` in the new core | **Decide in S1.** Either support it as a region allocator under RC, or retire it with a `mylang fix` migration. | It depends on the RC design. *Correction, 2026-10-05:* the Lox port has 0 arena blocks and the EDA tree has no `.my` files. All 156 `tests/lang` blocks test the feature itself. **Decided: retire.** |

## 5. Architecture of the new core

```
source ─ lexer ─ parser ─ sema/effects ─► typed.Program      (reused front end, 48.6k lines)
                                             │
                                             ▼
                                   Core IR (typed SSA)        new
                                             │  fact analysis: immutability, intervals,
                                             │  trip counts, element ranges, runtime guards
                                             │  ownership: one count, borrow inference, uniqueness
                                             ▼
                                   LLVM IR (typed pointers, noalias, narrow types,
                                            vector reductions, unions as SSA pairs/in place,
                                            trap regions, PC-table traces)
                                             │
                    -O0 + per-function cache (debug, tests)   │   O3 + LTO (release)
```

**Reused from today:**
- lexer, parser, sema, effects and capabilities, `typed.Program`, the module front end with
  its `.myi` facts, diagnostics and the CLI (front end: 140 files, 48.6k lines);
- the runtime library's *algorithms* for collections, text, bytes and I/O (about 10k lines of C),
  **ported** into the new core's own runtime (R1), not linked;
- the stdlib `.my` sources;
- `tests/lang` (1,579 tests) as the conformance suite.

**New:**
- Core IR and its builder from `typed.Program`;
- the fact analysis, porting the spike's interval and immutability analysis;
- ownership and RC insertion (one count, D1–D4 built in);
- LLVM emission, the trap and trace mechanism, and the build and cache driver.

The spike agent sized a function-level emitter including RC, COW, traces and ABI at roughly
25–35k lines.

**Not carried over:**
- QBE IL emission and the QBE-only passes;
- the QBE IL → LLVM translator;
- the tracing GC;
- the memory budget;
- exact-order trap fallbacks;
- two-count RC lowering.

**Built in from day one:**
- L1–L4 and D1–D4;
- **L2 trap regions,** with exact traps in Debug builds;
- **guards over immutable data,** which the ladder study showed recover the vector gain for
  file data;
- **constructing unions and records in place;**
- **typed collection operations.**

**Correctness oracle during the transition: the old core.** Every program the new core
accepts must produce byte-identical output and exit status to the old core's build of the
same program. That covers checksums, `tests/lang` outcomes and trap kinds; trap position is
allowed to differ under L2. Generalize the spike's differential fuzzer to whole programs.

## 6. Stages: grow from the microbenchmarks

Each stage has an exit check. The user decides go or stop at S0 and S2.

| Stage | Scope | Exit check |
|---|---|---|
| **S0 Skeleton** (about 1–2 weeks) | `mylang-core` executable; `typed.Program` → Core IR → LLVM for scalar code, calls, `if`/`while`/`for range`, immutable `list[int]`/`list[float]` reads; the spike's facts. Programs: the compute benchmark's scalar kernels (`integer_math`, `float_math`, `call_direct`, `branch_*`, `binary_search`) as single-kernel programs, then the unmodified `compute/main.my` if it is within reach. | Checksums identical to the old core. Kernels at or below the spike's cycles per element. **Dev-loop baseline for the new core recorded:** rebuild after a one-line edit, its unit tests, its conformance subset, its gate. **Go/stop point: the user decides.** |
| **S1 Values** | Records, `Option`/`Result` (error traces), unions in place, unique and immutable lists with append, pop and index, one-count RC on the shared runtime (WP-5), `mut` parameters, the N6 decision. Rows: the rest of compute, `tagged_stack`, `mutate_*`, `list_*`, `record_*`, `alloc_*`. | Those `tests/lang` files pass under the new core. Differential fuzz clean. Microbenchmark rows measured against the L1 gate (Zig ReleaseSafe). |
| **S2 Collections and text** | Dictionaries and sets (the WP-10e table layout designed here, not in the old core), `str`/`bytes` with a UTF-8 cursor, short strings, views and borrowed `encode()`. Rows: `dict_*`, `set_dedup`, `string_*`, `int_parse`, `int_format`, `sort_*`. | All 35 microbenchmarks build under the new core. Conformance for these areas passes. **Coverage sweep:** the share of real-program functions and loops the new core accepts, reported per refusal reason. **Go/stop point: the user decides whether to commit to S3–S5.** |
| **S3 Applications** | Effects and capabilities at run time (`Stream`, files, clock), the stdlib (`json.my`), `word_count`, `csv_aggregate`, `json_transform`, `lox_eval`. | The five application rows build and match. `tests/lang` passes in full under the new core. |
| **S4 Projects** | Modules and `.myi`, incremental per-module builds, `mylang test` on projects, the Lox port, an EDA slice. | The Lox port and the EDA slice pass their tests under the new core, with build and test times at or below the old core's. |
| **S5 Switch and delete** | Make the new core the default for release builds, then for debug builds. Delete QBE IL emission, the translator, the GC, two-count RC and the old ownership lowering. | The full gate on the new core alone. A deletion count, and a compiler rebuild time below S0's baseline. |

**Status, 2026-10-05 10:30 UTC.**

- **S0** is complete.
- **S1** is complete except two refusals parked as language questions for the user. Branch `claude/new-core-s1-20261005`:
  - full `tests/lang`: 745 of 1,470 tests supported, all matching the old core at debug and release;
  - leak and verify sweeps clean;
  - all 14 S1 rows at or below Zig ReleaseSafe;
  - coverage 2,269 of 3,509 functions.
- **The S2 design** is `docs/design/new-core-s2.md`.
- **S2 accepted by the user (2026-10-05).** It goes ahead with function values and fixed arrays. Hashing stays unseeded, short strings are deferred, the view ABI is evaluated only on a `string_split` gate miss, and O(n/32) non-ASCII indexing is accepted. A language change, `MUT-OVERLAP-RECEIVER-1`, is accepted too.
- **Codex implements S2** from `docs/audits/new-core-s2-implementation-plan-2026-10-05.md` on branch `claude/new-core-s2-20261005`.
- **Also accepted, 2026-10-05:**
  - `MUT-REBIND-CALLER-1`: rebinding a `mut` list, dict or set parameter reaches the caller, as for records.
  - D1 holds regardless of sharing.
  - Both go into S2 packages S2-La/S2-Lb (old core first) and S2-I (new core).

**Overfitting guard.** Benchmark-first growth admitted 0 of 143 real loops in the spike. From
S1 on, every stage reports the coverage sweep over `examples/`, `bench/`, the Lox port and
EDA sources (functions accepted, refusal reasons), next to the benchmark rows. Grow the
vocabulary by the refusal list, not only by the next benchmark.

## 7. Dev-loop targets for the new core

S0 measures these first; the targets below are then the budget each stage must hold:

| Loop | Old core today | New-core target |
|---|---:|---:|
| Rebuild after a one-line edit | 20–31 s (0.9–17 s with DL-3 watch mode) | ≤ 10 s (separate executable plus DL-3) |
| Focused unit tests after an edit | 17–34 s | ≤ 15 s |
| Conformance rerun after a compiler edit | 78 s (everything) | Only the tests whose emitted code changed (DL-2 by design) |
| Lane gate | Full gate 38–60 min, plus slot waits up to 30 min | ≤ 5 min in a build slot; the full gate only at integration |

## 8. Lanes

- **S0:** one design-and-implementation lane (Opus) for the Core IR and the first emitter.
  The IR's shape decides everything after it.
- **S1 and later:** up to three implementer lanes (Sonnet or Codex) per stage, split by area
  (values, collections, text, effects/IO). One owner per shared file per stage.
- **Alongside:** DL-1 to DL-5 as small lanes on the old core now.
- **Every lane:** its own locked worktree.
- **Builds:** through `scripts/build-slot.sh`, which keeps the timing CPUs 2, 3, 10 and 11
  free.
- **Timing:** campaign numbers only through the runner on CPU 2; exploratory numbers pinned
  to CPU 10.

## 9. Risks

- **Second-system risk.** The front end, stdlib and tests are reused, but the back end must
  still reach the old core's breadth before S5. S0 and S2 are explicit stop points.
- **Two cores during the transition** means duplicated maintenance and two gates. That is
  why DL-1 and DL-2 come first.
- **`typed.Program` may lack facts that `lower.zig` (909 lines) and `prelude_builtins.zig`
  (908) add while desugaring:** the `for` forms, `sum`, `zip`, `enumerate`. The new core may
  need to reuse or port that desugaring. S0 checks this.
- **Runtime: decided, R1.** The new core has its own runtime, so porting text, Unicode,
  dictionary and I/O algorithms is S1–S3 work. It is no longer coupled to WP-5.
- **LLVM -O0 debug builds** cost 1–4.5 s of code generation per program cold, against QBE's
  0.3–1 s. Per-function caching must keep the edit-and-test loop fast; S1 measures it.

## 10. If accepted: what to tell the Codex coordinator

**Continue:**
- WP-0 (gate reporting);
- WP-4 (memory budget);
- WP-5 / one-count (GC retirement and RC on the shared runtime);
- DL-1 to DL-5.

**Finish what is in flight, then stop new old-back-end performance work:**
- WP-1's alignment policy;
- WP-3 Stages A–C;
- WP-10c–e;
- the proposed WP-11 typed-region route.

**Keep correctness and real-program fixes on the old core** (Lox, EDA) until S4.
