# A provable build cache (plan, 2026-10-26)

**Status:** added to the plan at the user's request on 2026-10-26, with its own track
in the ownership-certificates tracker. Not started. Claude runs it with Sonnet and Haiku
lanes, as for `docs/audits/ownership-certificates-plan-2026-10-26.md`, and shares that
plan's Lean project and gate wiring.

**The guarantee.** For every `mylang build`, `run`, `test` and `check` (application
projects included), a build that reuses cached work produces byte-identical results to
a clean build of the same inputs: the same program, diagnostics and test verdicts.
"Same inputs" means every file, flag, environment variable, toolchain and compiler
identity the build reads.

Today that holds only as far as each cache's hand-built key happens to cover what its
step reads. The project has been bitten twice:
- a stale runtime object, fixed on 2026-09-23;
- the Zig configure cache ignoring the build root.

## 1. What exists

| Cache | Key today | Risk |
| --- | --- | --- |
| Unit objects (`units-v1`), runtime and number-text objects | The unit's exact LLVM text, optimization level, target, CPU, toolchain, runtime | Low: the key is the step's whole input |
| Linked programs (`programs-v1`) | Every linked object's bytes plus link settings | Low, the same reason |
| `--link` C objects (`foreign-v1`) | The source and every header its depfile listed | Low: the depfile is a trace |
| Replay records (`replay-v1`) | **A trace**: every file the build read, with its digest. Plus compiler identity, flags, working directory, entry, configuration, toolchain and environment, less `_`, `SHLVL` and `OLDPWD` | Medium: the trace is complete only if every read was recorded; there is a stat fast path |
| Front end: syntax, exact verdict, function bodies, persistent frontend cache, checked-body store (stage packs), check summaries and stand-ins | `cache_key.Contract` (six dimensions) plus content and context digests chosen per cache | **High**: each digest is assembled by hand, apart from the code that reads |
| Lowering, optimization, emission and ownership caches | Per-cache digests | High, the same reason |
| Test receipts (Core IR tier, then linked-program-and-runner tier), shared test store, shared compiler artifacts | Per-cache digests; the shared stores log determinism mismatches | Medium |
| Compiler identity | Zig sources by tokens (`build_identity_rules.zig` keeps `@src()` and source reflection out), other files by bytes | Low, and already enforced by a rule |

**Existing safety nets:**
- `--verify-cache` recompiles every served unit and compares bytes;
- `--no-cache`;
- the shared stores' `mismatches.log`;
- `cache_plan_reference_v2.zig`, an independent oracle that re-derives which tests can be admitted for reuse.

## 2. Design

**T1: tracked inputs.** Every cached step receives an inputs handle, not raw I/O.
Steps include checking a module, checking a function body, lowering a unit, compiling,
linking and running a test. Everything the step reads goes through the handle:
- files;
- environment variables;
- flags;
- the toolchain;
- the compiler identity;
- another step's output.

The handle records each input with its digest. Enforcement is by construction: step
functions take the handle in place of `std.Io` and the environment, and a Guardian rule
or a test forbids raw file and environment access in step modules, as
`build_identity_rules.zig` already forbids `@src()`.

**T2: records and reuse.** A step's record holds:
- its kind and code identity;
- the inputs it read, each with its digest;
- its output digest.

The record is reused only when every recorded input still has its recorded digest. The
stat fast path stays (decision E2): an unchanged stat tuple outside the racy-write
window stands for unchanged bytes. When a step re-runs and produces the same output
digest, the steps that read it keep their records (early cutoff).

**T3: function-body stand-ins.** A body's check is a step whose recorded inputs are
what that check read: the signatures and declarations it resolved, and the names it
looked up. This is the hardest part, because the checker must read declarations
through the handle per function. If the tracking costs more than stand-ins save
(budget below), stand-ins stay outside the proof and are labelled "reuse not covered by
the proof" in the report and the docs (decision E3).

**T4: the proof.** `proofs/cache/` is a Lean model:
- an input store with digests (SHA-256 collision-free is the one axiom);
- steps as deterministic functions of the inputs they read;
- records;
- the build algorithm: dynamic dependencies, verified records, early cutoff, and the
  admission rule `cache_plan_reference_v2` implements.

**Theorem:** every output a warm build produces equals the clean build's.
`lake exe cacheplan` runs the same algorithm, and the gate compares its reuse decisions
with the Zig planner's on recorded traces, the way `certcheck` is compared with the
ownership validator.

**T5: determinism.** Lean cannot prove that Zig steps are deterministic, so it is
checked instead:
- a gate action rebuilds a rotating sample of steps served from cache in the gate's
  corpus from scratch and compares bytes, extending `--verify-cache` from unit objects
  to diagnostics, summaries, lowering and test receipts;
- the shared stores' mismatch counts must stay at zero.

## 3. Packages

| Package | Work | Exit | Estimate |
| --- | --- | --- | --- |
| **K0** | **Read audit.** `scripts/audit_cache_reads.py` runs cache misses under `strace -f` (openat, stat, readlink, execve) and logs the environment variables each step reads, attributing reads to steps by markers the compiler prints under `MYLANG_CACHE_AUDIT=1`. Each step's actual reads are compared with what its key or record covers, on the repo corpus, EDA and selka. Each gap found becomes its own fix with a regression test. | A report listing every uncovered read, with each one fixed or explained | 6–10 h, plus fixes |
| **K1** | Tracked inputs and records for replay and the native steps (units, foreign objects, programs, link). | Replay and native steps read only through the handle; the rule passes | 10–16 h |
| **K2** | Front-end steps on tracked inputs: syntax, verdicts, checked-body store, summaries; stand-ins per T3. | Output equal to `--no-cache` on the full equality suite of 25 October (both EDA trees, edit scenarios, markdown fix) | 16–30 h |
| **K3** | Test receipts and the shared stores on records. | As K2, for `mylang test` | 6–10 h |
| **K4** | Lean model, theorem, `cacheplan`, and the differential test against the Zig planner. | `lake build` with no `sorry`; decisions agree on recorded traces | 12–24 h |
| **K5** | Determinism gate action, the enforcement rule, cost measurement, docs (`docs/tooling/caches.md`, `native-build.md`). | Complete gate passes; budgets met | 6–10 h |

The total is about 56–100 agent hours plus the gap fixes K0 finds.

**Order:**
- K0 does not depend on the certificates work and can start at any time.
- K1–K3 are the refactor.
- K4 can start once T2's record format is fixed.
- K5 comes last.

## 4. Budgets

| Case | Budget |
| --- | --- |
| Unchanged rebuild (replay) | No slower than today, plus the toolchain check: about +1 ms, accepted by the user on 2026-10-26 after K1 (selka markdown 2.4 → 3.3 ms, EDA stage 2 within noise of 8.0–8.5 ms; `experiments/cache-k1-tracked-native-20261026/REPORT.md`) |
| Re-check of an unchanged project | At most +2% |
| Cold build (recording every read) | At most +2% |
| Gate: determinism sample | At most 30 s added, on a rotating sample |

## 5. Decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| E1 | **The guarantee:** byte-identical programs, diagnostics and test verdicts compared with a clean build of the same inputs. Determinism is checked, not proved. | As stated. |
| E2 | **Stat fast path:** keep it under the existing racy-window rule, stated as an assumption. The alternative is to hash every input on every build, which is slower. | Keep it. |
| E3 | **Stand-ins:** bring them under the proof with per-function tracking. Leave them outside the proof, labelled, only if tracking breaks the budget. | As stated. |
| E4 | **Start:** K0 now if you want it, since it finds real gaps cheaply; K1–K5 after certificates stage 1 lands, sharing its lanes and Lean setup. | K0 first. |
| E5 | **Out of scope:** the gate's own evidence cache (`scripts/verify_cache.py`) and Zig's build cache. | Later, separately. |

## 6. Hard stops (report and wait for Claude)

- A gap whose fix changes what a build prints, or which tests run.
- A step that cannot be made to read through the handle without changing results.
- Any Python or Lean in `src/` or the install graph. The audit script and the gate
  drivers are developer tools.
