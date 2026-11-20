# Edit builds that do only the edit's work (plan, 2026-10-26)

**Status:** accepted on 2026-10-26: D1–D3 as recommended. D4 changed: Claude runs P0–P4
with Haiku lanes and reviews, gates and lands each package (§7). P0, P1 and P2 started. Written at the user's request the same day, after the three cache quick
wins landed (replay key 86f3b01ef, demand fallback 3421dadec, optimizer shortcut
aa59ab946). Measured first; nothing in `src/` has changed for it. The user asked for
two things: stop re-checking unchanged function bodies, and stop hashing every module
on every edit build. They also asked whether git or a file watcher could tell the
compiler what changed. Section 3 answers that.

Evidence: `~/ai/canopy/mylang-evidence-archive/experiments/frontend-edit-loop-20261026/`
(perf data, probe logs, run records, the Zig EDA logs). The scripts that produced it are
in `experiments/frontend-edit-loop-20261026/`.

## 1. Where an edit build's time goes now

The subjects are the ones the cache audit used
(`docs/audits/frontend-incremental-cache-audit-2026-10-26.md`):
- the 99k-line EDA stage-2 port;
- the 400k-line scaled tree, whose `main` reaches 1,057 modules.

Each build is a debug `mylang build` after one edit, with a ReleaseFast compiler that
includes the quick wins.

**Wall time.** Medians, timing windows.

| Edit | 99k (3 builds) | 400k (2 builds) |
| --- | --- | --- |
| Comment in the hub module | 1.79 s | 6.60 s |
| Leaf function body | 2.02 s | 5.25 s |
| Body in the hub module | 3.00 s | 8.92 s |
| Added function | 2.61 s | 9.12 s |
| Type change (new enum variant) | 5.01 s | 21.83 s |

The machine was loaded, and some wall times are inflated. For example, one 400k
added-function build took 13.6 s of wall time on 6.4 s of CPU. CPU for the non-type edits
at 400k is 5.2–7.5 s.

**Stages.** Medians of six non-type edit builds.

| Stage | 99k | 400k |
| --- | --- | --- |
| Front end | 0.56 s | 3.00 s |
| Lowering | 0.30 s | 0.83 s |
| Optimizer | 0.31 s | 0.92 s |
| Emission | 0.06 s | 0.23 s |
| LLVM and `zig cc` | 0.09 s | 0.28 s |
| Link | 0.00 s | 0.03 s |

LLVM is about 5% of an edit build, because one unit of 1,282 recompiles. In a cold build
it is 84% at 99k and 57% at 400k. Almost everything in an edit build is work in
proportion to the whole program, done to find and restore what did not change:
- lowering restores 15,197 cached functions to lower one;
- the optimizer skips 15,134 functions and runs 64.

**Front-end phases at 400k.** Medians, exclusive except where noted.

| Phase | Time | What it is |
| --- | --- | --- |
| `fresh_body_check` | 0.76 s | 209 bodies checked again on every build (section 2.1) |
| `dependency_key_preparation` | 0.31 s | A key and a dependency context for every declaration in the program |
| `ordinary_body_replay` | 0.18 s | About 4,500 bodies copied from the checked-body store |
| `load` | 0.17 s | Reading every source (10.8 MB) |
| `syntax_replay` | 0.13 s | Every module's cached syntax tree, 1,056 hits |
| `origin_passes` | 0.13 s | Whole-program passes after checking |
| `retention_store_io` | 0.09 s | Writing back the store |
| `specialization_body_replay` | 0.09 s | Generic instances replayed |
| `merge` | 0.09 s | Merging the modules into one program |
| `sema_session_open` | 0.34 s | **Includes** the key preparation above (the timers nest and double-count, P0) |

Summaries stand in for 19,104 bodies, so they are never read.

**Cold file cache.** When the stores are no longer in the OS page cache, as after an hour
of other work on the machine, the same 400k edit builds took:

| Phase | Stores in the page cache | Stores evicted |
| --- | --- | --- |
| `load` | 0.15 s | 0.9–1.7 s |
| `syntax_replay` | 0.11 s | 0.8–1.9 s |
| `ordinary_body_replay` | 0.16 s | 2.3–3.0 s |
| Front end in all | 2.6 s | 6.8–11.2 s |

**CPU profile.** perf with LBR call stacks, of a warm 400k added-function build:
4,825 P-core samples across every thread of the build.

| Work | Share of samples | Where |
| --- | --- | --- |
| The stage store | 23.9% | Mostly in `stage_store.Store.loadExpected` and `save` |
| — of which zlib decoding | 7.8% | `stage_compression.decode`, about 30 MB packed read, 117 MB decoded per build |
| — of which zlib encoding | 5.2% | `stage_pack.State.flush`, about 34 MB of saves prepared per build |
| Checking the 209 bodies | 15.8% | `checkFunction` |
| BLAKE3 | 11.8% | Lowering keys, store checksums, canonical IR digests, unit lookups |
| Whole-catalog validators | 8.0% | `record_layouts.validate` 6.7%, `view_cycles.validate` 1.3% (section 2.2) |
| Semantic keys | 5.6% | `semantic_key`, the key preparation |
| Kernel frames | 28% | Reads, page faults, process start for the one unit compiled |

## 2. Two causes found

### 2.1 The re-checked bodies all miss on one record kind

A probe compiler printed every body the checked-body store refused to replay, with the
reason:
- the 99k port: 85 bodies plus the edited one;
- the 400k tree: 208 plus the edited one.

The probe is in the evidence archive as `probe/probe-misses.patch` and is not on any
branch.

Every one misses with `missing_record`, and every missing record is an interned
`Result<T, E>`. Some examples:
- `main.run_model` names `Result<bytes, str>`;
- `bom.load_bom` names `Result<List<sexpr_ast::Node>, sexpr_parser::ParseError>`;
- `strings.pad_left` names `Result<str, strings::Error>`.

Each distinct `Result` instance appears exactly once. The body that misses is the first
one in check order to name it. A `Result<T, E>` record is interned when a body that
needs it is checked, so at replay time it is not yet in the catalog, and
`ReferenceBridge.resolveRecord` finds nothing. The bodies after it find the record and
replay.

So the same bodies are checked on every build, and stored again on every build
(`stored: 209`). The stored entry carries no recipe that would let replay materialize the
record. The `recipes` path in `semantic_cache.Session.copyEntry` exists for exactly this.

The `mylang check` command re-checks 4,305–4,718 bodies at 400k (the audit's F2), not
209. Its summaries refuse constants and generic-specialization callers. That is a
separate path, covered by P1's second exit check.

### 2.2 Interning a record re-validates the whole catalog

`nominal_catalog.Builder.complete` runs `record_layouts.validate` and
`view_cycles.validate` over every record whenever one is added. The profile attributes
both to:
- 279 samples from `instantiateLengths` ← `collection_lower.resultType`;
- 92 samples from `instantiateLengths` ← `dictionary_views.typeOf`.

That is the `Result` interning above, one whole-catalog pass per new record. The cost is
quadratic in the catalog, so it also weighs on cold builds and checks. Adding a record
cannot change an existing record's layout, and a new view cycle has to pass through a new
record, so validating the new records is enough.

## 3. Can git or a file watcher say what changed?

Yes, but knowing what changed removes less than it seems, unless the process also stays
resident.

**What change detection removes.** The work that only rediscovers that nothing changed:
- reading every source;
- replaying every module's syntax;
- re-deriving every declaration's key.

That is about 0.6 s of a warm 400k edit build. It is 3–4 s when the page cache is cold,
because those phases then read the stores from disk.

**How to detect it.** Git would be the wrong source:
- it needs a repository;
- it compares with a commit, not with the last build;
- it misses generated and untracked files.

Git itself decides what changed from each file's stat tuple, and that is the right
mechanism here. Record each source's size, mtime, ctime and inode at the end of a build.
A file whose tuple matches, with timestamps outside the racy-write window, counts as
unchanged without being read. This is decision E2 of
`docs/audits/provable-cache-plan-2026-10-26.md`, and `scripts/verify_cache.py` already
applies it to the gate's inputs. A file watcher (inotify) does the same in a resident
process, with no scan at all.

**What it does not remove.** Even when the changed file is known, a one-shot build still
reconstructs the whole program from its caches:
- 0.8 s of lowering restore;
- 0.9 s of optimizer bookkeeping;
- 0.2 s of emission;
- about 4,500 replayed bodies;
- the store decoding and checksums.

Only a process that keeps the checked, lowered and optimized program in memory between
edits stops paying for that. That is P5.

## 4. Packages

| Package | Work | Exit | Estimate |
| --- | --- | --- | --- |
| **P0** | **Honest timers and counts.** Make `sema_session_open` stop including `dependency_key_preparation`. Name the miss reasons in `--cache-report` text (the counts are already in `frontend_misses`). | The front-end phases sum to the front-end stage within 3%; a test pins the nesting | 1–2 h |
| **P1** | **Replay the first user of each `Result` instance.** Store a type recipe for every interned generic record a body references (`Result<T, E>` first, then any other record kind the probe finds), so `copyEntry` materializes it through `resolve_type` before copying. | A second edit build checks only the edited body on both trees (`checked: 1`). `fresh_body_check` under 0.05 s at 400k. Diagnostics and the linked program byte-identical to `--no-cache` (`exact.sh`, §7) on both trees. | 4–8 h |
| **P2** | **Validate only new records.** `Builder.complete` validates the records from `first` onward and the view cycles through them. | The diagnostic corpus for layout and cycle errors is unchanged. The validators are under 0.5% of a 400k edit build. A cold 400k check is measured before and after. | 2–5 h |
| **P3** | **Stop recompressing the store on every edit build.** Done 2026-10-27: blocks are uncompressed by default (`MYLANG_STAGE_CACHE_COMPRESSION=zlib` opts back in); 99k edit builds −12 to −19% CPU, cache 1.9x. Measure, then choose among: no compression for local packs, flate at its fastest level, or append-only packs compressed only when compacted. Also decode fewer blocks: 491 blocks and 117 MB are decoded to return 59 MB. | The stage store is under 8% of a 400k edit build. The store's size stays within the retention cap and at most 2x today's (D2). | 8–16 h |
| **P4** | **Stat check, per-module records, and the edit caches shared across worktrees** (added at the user's request on 2026-10-27). (a) The E2 stat check for every source. (b) A per-module record of its syntax and prepared keys, keyed by its bytes and the interface digests of its imports. An unchanged module is not read, replayed or re-keyed. The records follow the provable-cache plan's T2 format, so K2 later adopts them rather than replacing them. (c) The caches that make an edit build fast move from the work directory to a per-user store shared by every worktree, as the unit objects already are: the per-module records, the checked-body store, the lowering cache and the optimizer's stage packs. Each entry is content-keyed (the compiler identity, the inputs' digests, and no absolute path or worktree name), published atomically, read under process leases, and kept by the same retention as `compiler-artifacts`. A record whose bytes differ from what its key promises is a miss, counted in `shared_mismatches`. The work directory keeps only what names this tree: replay records and the stat memo. (d) Space, added at the user's request on 2026-10-27. On the 99k port after 15 edit builds, uncompressed, the stage packs held 253 MB in 13 packs: each edit build writes a new pack of about 10 MB, a cold or fallback build about 30 MB, and nothing compacts them. `MYLANG_CACHE_TIERS_CAP_GB` does not cover `stages-packed-v1/` (P3's lane found this). The fixes: compact superseded pack generations by copying live entries into a fresh pack, renaming it into place and unlinking the old ones; write only the index entries that changed, where today about 9 MB of whole-program indexes is rewritten on every edit build; keep the newest 4 linked programs per entry and hardlink the private copy to the shared one; and bring the stage packs and the checked-body store under the per-worktree cap and the shared store under per-user retention. (e) Collecting the shared store, user's question 2026-10-27. Correctness never depends on collection: entries are immutable and content-keyed, so one worktree's new version of a function and another's old one are different keys, and a missing entry is a miss. For liveness, each worktree registers a root manifest after each build: the shared keys its current build used, with its path and the time. The collector keeps every key named by the manifest of a worktree that still exists and built within 14 days, plus anything read in that window, and collects the rest oldest-first under the size cap. While builds run they hold the existing process leases, and the collector never deletes anything published or read since the oldest live lease began. Compaction writes a new pack and renames it, so a reader with the old pack open keeps reading it, and a reader that finds a key gone treats it as a miss. | At 99k, warm: `load` + `syntax_replay` + key preparation under 0.05 s. With a cold page cache, the front end within 1.5x of warm. A new worktree of an already-built commit: its first edit build is within 1.5x of a warm worktree's, and builds nothing cold. `exact.sh` and `--verify-cache` pass, and two worktrees building one commit at once leave no `shared_mismatches`. After 15 edit builds at 99k, the stage packs stay under 1.5x one build's live set; an edit build writes under 1 MB of index data; no executable is stored twice. Two worktrees share the store, A edits `f` and B keeps the old `f`: after a forced collection both rebuild with nothing cold beyond what each changed, and each equals its `--no-cache` build. | 36–60 h |
| **P5** | **A resident build process** (separate plan, after P1–P4; written 2026-10-28 as `docs/audits/resident-build-server-plan-2026-10-28.md`). It keeps the checked, lowered and optimized program and the unit objects in memory, takes changed paths from inotify or the stat check, and re-runs only the affected steps through P4's records. `check-session` is the precedent; the audit found it slower than a one-shot check at 99k, so it is fixed first. | A one-edit rebuild at 400k under 1 s, byte-identical to a one-shot build. Memory measured and budgeted. | 60–120 h |

**Expected result.** These are estimates from the measurements above, for a warm 400k
non-type edit build at about 5.3 s:
- P1 and P2 remove about 0.8–0.9 s: the fresh checks, the validation inside them, and
  re-storing their entries;
- P3 removes about 0.4–0.6 s;
- P4 removes about 0.4 s warm, and 3–4 s when the page cache is cold. Its shared store also means a new worktree's first edit build costs about what a warm worktree's does, instead of a cold front end, lowering and optimizer.

That brings the one-shot build to about 3.5 s at 400k and about 1.5 s at 99k. What
remains is the whole-program reconstruction, about 3 s at 400k. Only P5 removes it,
leaving roughly 0.3–0.6 s at 400k: the edited module's check, one unit compiled and the
link.

**For comparison.** On the same machine, the 669k-line Zig EDA spends 9–16 s compiling
`netlisp` after any edit, since plain `zig build` is not incremental. The whole
`zig build` takes 25–44 s because it also rebuilds the WASM DRC and runs Guardian. Zig's
`-fincremental --watch` was not measured.

**Order:**
- P0 first;
- P1 and P2 are independent and small;
- then P3;
- P4 after P1, because P1 changes what the body store records;
- P5 gets its own plan once P4's records exist.

## 5. Decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | **Scope now:** P0–P4 as one run, P5 as a later plan. | As stated. P0–P3 are about 15–30 h together and cut a third of a 400k edit build. |
| D2 | **Store size against speed (P3):** whether local packs may grow to 2x today's size uncompressed. | Allow up to 2x if that meets the 8% target. Otherwise use append-only packs. |
| D3 | **P5's shape:** a `mylang build --watch` mode, or a background server that one-shot `mylang build`, `check` and `test` use automatically when it is running, the way Gradle's daemon does. | The server, because agents run one-shot commands and would get the speed without changing them. Watch mode is a thin client of it. |
| D4 | **Who implements:** Codex, or Claude with lanes. | **Decided 2026-10-26: Claude with Haiku lanes.** Claude reviews, gates and lands each package. |

## 6. Hard stops (report and wait for Claude)

- Any build or check whose diagnostics, program bytes or test verdicts differ from
  `--no-cache`.
- A cold build or check more than 2% slower, other than through P2's own work.
- A stat-check rule weaker than E2's racy-window rule.
- Python in `src/` or in the install graph.

## 7. Operating rules for the lanes (P0–P2)

**This run's scope.** P0, P1 and P2, then P3's measurement only: the codec options and
the block-decoding numbers, logged, with no change under `src/`. P3's implementation and
P4 start after Claude's review.

**Lanes.** Claude coordinates Haiku lanes and lands their work:
- lane A: P0, then P1, in `~/ai/canopy/mylang-fix` on branch `edit-loop/p0-p1`;
- lane B: P2, in `~/ai/canopy/mylang-w2-r` on branch `edit-loop/p2`;
- then the P3 measurement, in whichever worktree is free.

**Autonomy.**
- Decide, log in `experiments/frontend-edit-loop-20261026/DECISIONS.md`, and continue.
  Each entry gives the question, the options, the evidence, the choice and whether it
  can be reversed.
- Commit at every step, with a progress section in `status.md`.
- Investigate a gate failure for up to about 6–8 h.
- Early measurements are checkpoints; the final one is binding.
- When your context runs low, commit a "Session handoff" section in `status.md` and stop.
  That is a handoff, not a blocked run.

**Measurement.**
- **Compilers:** ReleaseFast installs under `~/.cache/mylang/edit-loop-pins/<label>-<commit>`,
  built with `scripts/build-slot.sh build zig build -Doptimize=ReleaseFast --prefix …`.
  Build one for `main` at the start and one after each package.
- **Trees:** private copies of `~/ai/.home-cache/cache-quick-wins/eda/stage2/mylang` (99k)
  and `~/ai/.home-cache/cache-quick-wins/n24` (400k). Never run two drivers on one copy.
- **Edit builds:**
  `python3 experiments/frontend-cache-audit-20261026/measure.py eda|n24 TREE OUT --bin MYLANG --timing --reps N --cmds build --scenarios comment_hub,leaf_body,hub_body,type_edit,add_func`.
  Use 3 reps at 99k and 2 at 400k. Make the tables with
  `experiments/frontend-edit-loop-20261026/table.py OUT...`.
- **Exactness:** run `experiments/frontend-edit-loop-20261026/exact.sh MYLANG TREE CACHE`
  on both trees, through `scripts/build-slot.sh build`. It must print `IDENTICAL program`,
  `IDENTICAL diagnostics` and `verify-cache exit 0`.
- **The port's own tests:** with each package's compiler, in the 99k copy,
  `mylang test src --jobs 4 --max-frames 30000 --max-steps 4000000000 --max-memory 2G`
  passes all 1,250.
- **P2 also:** a cold 400k `mylang check src/main.my --timings=json`, before and after.
- **Miss reasons:** `frontend_misses` in the `--report` line, in the order of
  `semantic_cache.MissReason`. The probe patch in the evidence archive names the bodies
  and records when a count needs explaining.

**Tests per package.** These are Zig tests next to the code, and each ships in the same
diff as the change.
- **P0:** a test that the front-end phases are disjoint.
- **P1:** a body that first names a `Result` instance replays on the second check; the
  `checked` and `reused` counters say so; and its diagnostics are unchanged.
- **P2:** layout and view-cycle errors in a record interned late are still reported,
  with the same diagnostics.

**Hard stops.** Section 6, plus:
- touching another run's worktree, branch or processes: the ownership-certificates lanes,
  and the provable-cache lanes K1–K4 in their own worktrees;
- free space on `/home/epentland/ai` under 25 GB, or the machine swapping.

**Files.**
- Forbidden:
  - `SPEC.md`, which is frozen;
  - `src/core/validate_ownership*.zig`, `proofs/` and `src/core/build_replay.zig`, which
    other active runs own;
  - untracked files in the primary checkout, which belong to other sessions.
- The provable-cache plan's K2 is deferred while this run changes the front-end caches:
  `src/semantic_cache.zig`, `src/semantic_store.zig`, the cache paths of `src/sema.zig`,
  and `src/nominal_catalog.zig`. Store P1's record recipes in a shape K2 can track. A
  record's inputs are its recipe's declaration and argument types.

**Branches and landing.**
- Each lane works only in its own worktree and branch, both created from `main`.
- **Lanes do not land.** Claude reviews, gates and fast-forwards `main` to each package.
  A lane marks its package's last commit in `status.md` (`P1 ready: <sha>`), reports to
  Claude, and carries on with its next package.
- Merge `main` into the branch whenever it moves. Never push.
- Stage named paths only; never `git add -A` or `git add .`.

**Machine rules from `CLAUDE.md`.**
- Run `source ~/.config/mylang/dev-env.sh` in the worktree.
- Builds and focused tests go through `scripts/build-slot.sh`. Run
  `python3 scripts/verify_cache.py --zig "$ZIG" --profile complete` before marking a
  package ready, and never wrap it in a slot.
- At most four agents build the compiler on this machine; the two lanes count as two.
- Caches, `TMPDIR` and install prefixes go under `~/.cache` or `~/ai/.home-cache`,
  never `/tmp`.
- A behavioural change under `src/` ships with a test change in the same diff.
- Keep committed evidence under 10 MB. Data goes to
  `~/ai/canopy/mylang-evidence-archive/experiments/frontend-edit-loop-20261026/`.
- Never kill a process this run did not start.

**Finish** with `experiments/frontend-edit-loop-20261026/REPORT.md`. It covers:
- per package, the before and after tables for both trees: wall time, CPU, stage and
  phase times, and `checked`;
- the `exact.sh` results and the port's test results;
- the P3 measurement;
- the decisions logged.
