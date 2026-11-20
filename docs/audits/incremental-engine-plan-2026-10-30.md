# Incremental engine, part 1: inventory, spec, core and first consumer (30 October 2026)

The proposal (artifact "Selka Incremental Engine", 29 October; memory note
`unified-incremental-engine-idea-2026-10-29`) recommends one shared incremental core used by two layers: the
compiler's fine-grained work, and the coarse layer of tests, the gate and the edit check. Its order has five steps.
This plan runs the first three, and the language features of step 2 beside them:

1. inventory every cache and write the language-neutral spec (N0, N1);
2. add the language features a Selka outer layer needs (L1, in parallel, independent);
3. build the engine core in the Zig host (C1) and move one consumer onto it, shadowed, then switched (C2).

Steps 4 (the outer layer in Selka) and 5 (porting the compiler's engine with the driver after self-hosting stage 4)
are later plans. This plan starts when the compiler dev-loop part 2 wave has closed (main `9f3a8abb1` or later).

Sonnet lanes implement (`subagent_type: sonnet-lane`); the coordinator (Claude) writes the spec, reviews every lane,
runs the gate and shadow, and lands on main.

## 1. Goal and exit

**Goal.** One engine core in the compiler repository, specified, tested and measured, with one real consumer running
on it in place of its own cache code. It is the base the later consumers (the gate's declared inputs, the compiler's
stage records, the self-hosting component seams) move onto.

**Exit of part 1.**
- The spec `docs/design/incremental-engine.md` is accepted by the user, with test vectors in the repository.
- The core lands on main with unit tests, test vectors and a property test (incremental results equal from-scratch
  results over random edit sequences).
- The first consumer runs on the core: shadowed until its decisions agree with the old code's (§5), then switched,
  and the code it replaces is deleted (net lines removed).
- Its measured cost is no worse than today on the standard edit sequence (§6): unchanged rerun, rerun after a
  compiler edit, restore against recompute, peak memory.
- L1's language features land with tests, documentation and `features.json` entries.

## 2. Where things stand

- About 110 non-test files and 30,000 lines are named for caches, stores, receipts, identities or digests; 11 `src/`
  files (non-test) take locks. The largest pieces: `scripts/verify_cache.py` 2,455 lines, `src/core/stage_pack.zig`
  1,239, `src/core/test_runner_receipt.zig` 1,214, `src/semantic_cache.zig` 1,081, `src/native_cache_retention.zig`
  979, `src/frontend_cache.zig` 696, `src/shared_artifact_store.zig` 675, `src/core/work_retention.zig` 669,
  `src/core/unit_cache.zig` 662, `src/core/test_shared_store.zig` 640, `build_test_inputs.zig` 513.
- Code identity exists in three hand-built forms: the whole compiler identity, M1's stage identities
  (`src/build_identity_rules.zig` `stage_roots`, five stages since E6 added `test-runner`), and the runner identity.
- Retention exists five times: the store timer, `scripts/cache_retention.py`, `core_store_gc.py`,
  `scripts/prune-caches.sh` and `mylang cache gc`, plus build-slot admission's trims (`worktree_cache_trim.py`) and
  the work directory's own sweep (`work_retention.zig`, now with the ownership identity retirement).
- Part 2's last findings belong to the same classes: the ownership store admitted every compiler generation's packs
  (a key scheme with no identity partition); test caches grew without a bound (now capped at admission); the
  compile-time rule of the edit check read text, not references.
- The language (R-6 in `docs/audits/eda-port-roadmap-2026-10-22.md`) holds still from G2 only against breaking
  changes. L1's features are additive, so they need no exemption.

## 3. Packages

### N0. Inventory (Sonnet lane, read-mostly; about 4-6 hours)

One row per cache or store, in `experiments/incremental-engine-20261030/N0/INVENTORY.md` (data in the evidence
archive):

| Column | What it records |
| --- | --- |
| Name, files | the module(s), the on-disk path, the store type (pack, loose files, JSON, database) |
| What it holds | the computation it saves, and its consumers |
| Key inputs | each input of the key, marked declared (listed by hand), recorded (read through code that records it) or implicit (assumed: the compiler identity, the working directory) |
| Code identity | whole compiler, a stage, the runner, none |
| Concurrency | locks, leases, claims, and what waits on them |
| Retention | which of the mechanisms above bounds it, and its bound |
| Bug history | fixes in `git log` that touched it (stale result, too coarse a key, contention, growth), with commit ids |
| Measured | hit rate, restore time and recompute time where measurable, on the standard edit sequence (§6) |

Also: every place a computation reads a file, an environment variable or a tool outside any key (the soundness
risks the engine's recorded reads close), and the three to five consumers best suited to go first, scored on bug
history, CPU share and how self-contained they are.

Exit: every file of the name sweep (`cache|store|receipt|identity|digest|replay|retention|lease|lock|key` under
`src/`, `scripts/`, `build*.zig`) and every lock site is a row or is listed as not a cache, and the top ten by CPU
share have measured hit rates.

### N1. Spec (coordinator; about half a day after N0; user review)

`docs/design/incremental-engine.md`, language-neutral, so the Zig core and a later Selka core share formats and
vectors:

- **Data model.** A query kind names its implementation (its code identity, derived like M1's stage identities from
  the import closure of its roots). A query's key is its kind's code identity plus its argument; its record lists
  every read with the digest it saw, and its result digest.
- **Reads.** Every read goes through an engine context: files, directory listings, environment variables, tool
  identities, other queries. In Zig the context is the only handle engine code gets to the filesystem and the
  environment, so a read that bypasses it is a compile error, not a silent stale result.
- **Early cutoff.** A recomputed query whose result digest is unchanged leaves its dependents valid.
- **Validation.** Which of the two the core uses, decided on N0's restore measurements: validate on demand (walk a
  query's reads and compare digests, Salsa's model) or walk outward from the changed files over a persisted reverse
  graph (Skyframe's). The resident-server experiment (28 October) and the warm `mylang test` regression show that
  a detailed graph can cost more to load than to recompute; the spec fixes a granularity rule with a measured
  budget.
- **Store.** One content-addressed object store plus per-kind records: the layout, the digest (BLAKE3, fixed 32
  bytes), the record codec, atomic publication, partitioning by code identity (the ownership-store lesson), leases
  and retention (one design that replaces the per-store ones as consumers move).
- **Verify mode.** Recompute a sample of served queries and compare result digests, on in Debug compilers and gates.
- **Component protocol.** How a query is computed by another process (the self-hosting stages' Selka components):
  inputs passed by digest, outputs returned by digest, shadow mode as "compute both, compare".
- **Test vectors.** Record bytes and key derivations for a small fixed set of queries, checked by the Zig tests and
  later by the Selka port.
- **Decision log.** Each choice with the N0 evidence behind it.

The user accepts the spec before C1 starts (decision D5).

### C1. Engine core in the Zig host (Sonnet lane; about 2-3 days)

`src/engine/` (reachable from the Guardian roots), to the spec: the context and its recorded reads, query
execution with early cutoff, code identity per kind (from `build_identity_rules.zig`), the store, leases, verify
mode. No consumer yet.

Tests:
- unit tests and the spec's test vectors;
- a property test: a random graph of queries over an in-memory filesystem, random edit sequences, and after each
  edit the incremental results equal a from-scratch evaluation; the number of recomputed queries is checked against
  the minimum the edit requires (early cutoff works);
- a soundness test: a query that reads outside its context fails.

Budgets, measured and recorded in the lane's notes: overhead per recorded read, per served query on restore, and
the store's peak memory on a 100,000-query graph. The budgets themselves come from the spec.

### C2. First consumer, shadowed then switched (Sonnet lane; about 2-3 days plus the shadow period)

Default: the `mylang test` receipts (`src/core/test_runner_receipt.zig`, `test_shared_store.zig`,
`native_receipt.zig`): coarse-grained, self-contained, with a measurable hit rate and a history of the bug classes
(whole-identity keys before E6, claims that made other gates wait about 250 s, warm runs slower than cold ones).
N0's scoring may name a better first consumer; the coordinator decides and records it (D2).

1. Each test execution becomes a query: its reads are the linked program's digest, the runner identity, the
   settings and the environment it sees; its result is the verdict and output digest.
2. **Shadow.** Both the old receipts and the engine decide for every test in every gate and edit check, and each
   disagreement is logged. An engine reuse where the old code reruns is a soundness disagreement: a hard stop
   until explained. An engine rerun where the old code reuses is an efficiency loss: counted and fixed or accepted.
3. **Switch** after the shadow period (D4), then delete the old receipt paths.

Exit: §1's measurements no worse than today; zero unexplained soundness disagreements.

### L1. Language features for a Selka outer layer (Sonnet lane, in parallel; about 3-5 days)

Independent of N0-C2; the outer layer (step 4) needs them, and the bootstrap rule (`selfhost/README.md`) lets
compiler-adjacent Selka code use a feature only one release after stage 0 ships it, so they should land early.

- **A process capability**: start a program, wait for it, read its exit status and output; granted like the
  others (`mylang run` grants it unless `--restrict`; an explicit `--allow-...` flag). Its exact shape is D3.
- **Filesystem additions**: atomic rename, stat (size, modification time, inode), and an advisory lock or lease.
- **A digest value**: a fixed 32-byte digest type and BLAKE3 in `hashes`, within the 1.10x parity rule against Zig.
- **A binary record codec** over the byte builders, within the same parity rule.

Each lands with `tests/lang` tests, a documentation section with a runnable example, and a `features.json` entry
(`mylang doc-coverage .`).

## 4. Order and lanes

| When | Lane | Package |
| --- | --- | --- |
| Day 0, after part 2 closes | A (Sonnet) | N0 inventory |
| Day 0 | B (Sonnet) | L1 language features (after D3) |
| After N0 | coordinator | N1 spec, then the user's review (D5) |
| After the spec is accepted | C (Sonnet) | C1 core |
| After C1 lands | C (continued, it knows the core) | C2 first consumer: shadow, switch, delete |

Rough calendar: N0 half a day to a day; N1 half a day plus review; C1 two to three days; C2 two to three days plus the
shadow period; L1 three to five days beside them. Part 1 takes about one and a half to two weeks of elapsed time.

Worktrees: the part-2 lane worktrees (`mylang-devloop`, `mylang-hotfix`, `mylang-gate`), each cleaned and locked with
the lane's reason before reuse; `mylang-editcheck` stays the measurement worktree.

## 5. Lane rules

- `source ~/.config/mylang/dev-env.sh` in the worktree; builds, focused tests and gates through
  `scripts/build-slot.sh`; the gate is `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete`, run
  directly; no `build-slot.sh timing` windows.
- Kill only processes you started, by the PID you recorded. Never by pattern: `pgrep -f` matches the command that
  runs it.
- Memory: `earlyoom` runs on this machine and sends SIGTERM to the largest process at 10% available memory. An
  unexplained exit 143, SIGTERM or "zig failed" is checked against `journalctl | grep earlyoom` first. A tool or test
  run should stay under about 2 GB; at most two memory-heavy jobs at a time.
- Evidence outside git (`~/ai/canopy/mylang-evidence-archive/experiments/incremental-engine-20261030/<lane>/`),
  write-ups and small scripts in `experiments/incremental-engine-20261030/<lane>/`, decisions in that directory's
  `DECISIONS.md` (decide, log, continue; stop only on a hard stop).
- Guardian's rules (`CLAUDE.md`): a behavioural change ships with a test change; at most seven fields per struct
  and six parameters per function; `///` on every `pub` declaration; no `@import` cycles; new files reachable from
  the roots; straight-line test bodies.
- The coordinator lands: review, complete gate, `scripts/edit_check_shadow.py` on the gate log, fast-forward or
  merge to main, then `python3 scripts/edit_check_refresh.py`.

## 6. Measurement

The standard edit sequence is `experiments/compiler-dev-loop-20261029/final/final_measure.sh` (three small edits,
three central edits, two rounds, a new tag prefix per run) plus an unchanged rerun, on `mylang-editcheck` at the
commit under test, with the map at that commit. Each comparison runs base and branch alternately on the same
machine state; the store timer's collection and other sessions' load are recorded with each run.

## 7. Hard stops

- A soundness disagreement in C2's shadow that the lane cannot explain.
- The first consumer's restore is slower than its recompute by more than 10%, or the core's overhead on an unchanged
  edit check exceeds 5%.
- The property test finds an incremental result that differs from the from-scratch result.

A hard stop ends the lane's work; the coordinator reports to the user, who decides.

## 8. Decisions for the user

- **D1. Scope.** Steps 1-3 now, L1 beside them; the Selka outer layer and the port are later plans.
- **D2. First consumer.** The `mylang test` receipts, unless N0's scoring shows a better one (the alternatives:
  the gate's declared inputs, `build_test_inputs.zig`, larger payoff but it needs the reads of test processes
  recorded; the front-end caches, the largest CPU share but the most entangled).
- **D3. The process capability's shape**: its name (`Process`), its grant flag, and that outer-layer tools built by
  stage 0 never run the compiler under test except as the program being tested.
- **D4. The shadow period** before C2 switches: five clean complete gates and twenty edit checks over at least two
  days of ordinary traffic.
- **D5. Spec review.** C1 starts only after you accept `docs/design/incremental-engine.md`.

## 9. What part 1 does not do

It does not make cold work cheaper (the compiler's own Debug build, work that grows with program size), it does not
replace Zig's build cache, and it does not touch the edit check's coverage map. Moving the gate's declared inputs,
the compiler's stage records and the self-hosting seams onto the core are later parts, each with its own plan.
