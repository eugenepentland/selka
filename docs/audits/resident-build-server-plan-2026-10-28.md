# A resident build server (plan, 2026-10-28)

**Status:** written at the user's request on 2026-10-28, after the edit-loop plan's P0–P4
landed (`docs/audits/frontend-edit-loop-plan-2026-10-26.md`, main `b3e5d71ed`). It is P5 of
that plan, made into its own plan as the plan said. **Decided 2026-10-28** (§6): the server is on by
default from the start, all four commands use it, one shared 6 GiB budget per user (up to 8 GiB),
Claude with Haiku lanes, type edits separately; S4 is dropped. S0 started the same day.

**S0 result (2026-10-28): the hard stop (§7) is triggered.** Holding every record in memory, and the
decoded objects as well, makes a 400k one-line edit's second build 4.27 s wall / 3.64 s CPU, against the 1.5 s limit
(99k: 1.20 s / 1.15 s). The memo removes about 20% of CPU, because decoding and disk reads were never the large cost.
What remains is work proportional to the program, not to the edit: keys and digests of unchanged records (about 23% of
CPU), whole-module validation (about 14%), replay and restore of unchanged objects, and optimizer and emission
bookkeeping. One-shot builds pay the same. S1 and S3 are not built as scoped; see
`experiments/resident-server-s0-20261028/REPORT.md` (prototype on branch `server/s0`, not for merge).

Evidence: `~/ai/canopy/mylang-evidence-archive/experiments/frontend-edit-loop-20261026/runs/`
(`eda-p04`, `n24-p04` against `eda-base`, `n24-base`).

## 1. Why: what an edit build still costs

Debug edit builds on main `b3e5d71ed` (ReleaseFast compiler, timing windows). Medians, 3 builds
per edit on the 99k EDA port, 2 on the 400k scaled tree:

| Edit | 99k wall | 400k wall | 400k CPU |
| --- | --- | --- | --- |
| Comment in the hub module | 1.04 s | 4.19 s | 3.43 s |
| Leaf function body | 0.86 s | 3.08 s | 3.01 s |
| Body in the hub module | 1.11 s | 3.60 s | 3.43 s |
| Added function | 0.94 s | 3.32 s | 3.13 s |
| Type change (new enum variant) | 2.19 s | 6.7 s, or 21.6 s with a fallback | 12.8 s |

**Where a 400k one-line edit's 3.46 s goes** (median of 8 builds):

| Part | Time | What it is |
| --- | --- | --- |
| Front end | 1.52 s | whole-program work: stand-in planning 0.26 s, allocation contracts 0.17 s, body replay 0.15 s, origin passes 0.11 s, syntax replay 0.11 s, merge 0.07 s, specialization replay 0.07 s, warning derivation 0.06 s, … |
| Lowering | 0.69 s | restoring about 15,000 cached lowered functions to lower one |
| Optimizer | 0.62 s | bookkeeping to skip about 15,000 functions and run a few dozen |
| Emission | 0.19 s | |
| LLVM and `zig cc` | 0.12 s | the one changed unit at `-O0` |
| Outside the stages | 0.33 s | process start, store opening, the link and reporting |

About 85–90% of that is rebuilding the whole program's state from its caches. The edit's own
work is roughly 0.3 s: re-checking a few bodies, lowering one function, optimizing a few dozen,
emitting and compiling one unit, and the link. The cost grows with the program: about 1.0 s at
99k lines and 3.5 s at 400k. That extrapolates to about 6 s at the 669k lines of the EDA the
project means to port.

A process that keeps the program in memory between edits pays only for the edit. That process is
the subject of this plan.

## 2. Goal

- **Speed:** a one-line edit build at 400k lines under 1 s, with 0.5 s as the stretch; at 99k,
  under 0.4 s.
- **Exactness:** every result the server produces is byte-identical to what a one-shot command
  produces for the same inputs: program bytes, diagnostics, warnings, test verdicts and reports.
- **Transparency:** agents keep running `mylang build`, `run`, `test` and `check`. When a server
  is running for that work directory, the command uses it. When none is, or when anything about
  the server is wrong, the command does the work itself as today.

## 3. Design

**Shape.** `mylang build`, `run`, `test` and `check` become thin clients when a server is
available. One server runs per work directory (`.mylang-cache/core` or `--cache-dir`) and
compiler identity. It listens on a Unix socket inside the work directory, mode 0600, for the same
user only.

**What the client sends:**
- its argv;
- its working directory;
- the projected environment (`environment_identity.zon`'s keyed and placement variables, exactly
  what a one-shot build reads);
- the compiler identity of the binary the client is.

A request whose identity differs from the server's is refused, and the client runs it itself and
then replaces the server. So a rebuilt compiler never talks to an old server.

**Who runs guest code.** The server never runs guest programs. It builds them and returns the
program path, diagnostics, reports and exit status. `mylang run` and `mylang test` children run
in the client, under the client's capabilities, limits and environment, as they do today.

**What the server keeps:**
- the checked program: syntax, declarations, catalogs, checked bodies and summaries;
- the lowered module;
- the optimized IR with its demand state;
- emitted unit text and native handles;
- the per-module records (P4a).

Each object is held under exactly the key that one-shot uses to find it on disk (the stage store,
the semantic store, the module records). So reusing it in memory is the same decision a one-shot
build makes from disk, without the decode. That is what makes server results equal to one-shot
results by construction, and it is what the provable-cache plan's records (T2) need.

**Change detection.**
- Each request runs the same input checks a one-shot build does: the stat check with the
  racy-write rule (K3's `racy.zig` once it lands on main), and the module records' interface
  digests.
- `inotify` is a hint that lets the server start invalidating before the request arrives. It is
  never the authority.
- A request that finds nothing changed replays as today.

**Write-behind.** After the server has replied, it publishes the new records to the same on-disk
stores one-shot builds use: the private work directory and the shared per-user stage store. Then
a later one-shot command, a restarted server or another worktree finds them, exactly as if a
one-shot build had run. A server that dies loses only what it had not yet written; the next build
recomputes it.

**Whole-program passes.** Several front-end passes walk the whole program after checking: stand-in
planning, allocation contracts, origin passes and warning derivation. Holding the program in
memory does not by itself make them incremental. They become per-module passes with early
cutoff: a module whose inputs and interface digests are unchanged keeps its result. This is
package S2. Without it, the server would still pay about 0.6 s per edit at 400k for them.

**Concurrency.**
- Requests to one server are serialized per work directory, as builds in one worktree already are
  through the store locks.
- `mylang test --jobs N` sends one request for the whole run. The server builds the test programs
  it needs in parallel inside itself, and the client runs them.
- Two worktrees have two servers. They share only the per-user stores, which are already safe for
  concurrent use (P4d2).

**Lifecycle.**
- Started by `mylang server start`, or automatically by the first client command when D1 allows
  it.
- It stops after an idle timeout (D3), when its memory budget is exceeded and evicting cannot
  bring it back under, or when `mylang server stop` is run.
- `mylang server status` reports its memory, its uptime, the requests it has served and what it
  reused.
- It logs to the work directory.

**Memory.** The server holds a budget (D3). When it is over, it drops the least recently used
objects from memory. They are still on disk, so dropping one costs a reload, never a rebuild.

**What stays out of scope here:**
- **Type edits.** A changed type layout shifts every later function's type positions, so about
  15,000 functions really re-lower at 400k. A resident process does not change that. The fix is
  stable type positions in lowering, a separate package (§6, D5).
- **Fresh worktrees.** These are P4d3 (shared module records and checked bodies) and the
  content-addressed optimizer package.
- **Hot reload.** It builds on this server, but it is not part of this plan.

## 4. Packages

| Package | Work | Exit | Estimate |
| --- | --- | --- | --- |
| **S0** | **Measure the floor before building anything.** A developer-only mode that runs a build, applies an edit and runs a second build in the same process, reusing in-memory objects by their keys (a test harness or a hidden flag, never a user surface). | The in-process second build's time at 99k and 400k, by stage; the server's memory at 400k; the share left in the whole-program passes. Decide whether S1–S5 go ahead. | 6–10 h |
| **S1** | **In-memory memo layer.** Each stage's lookup consults an in-process memo keyed exactly like its store before decoding from disk, with memory accounting and least-recently-used eviction. One-shot behaviour is unchanged. | In the S0 harness, the second build reuses in memory everything a warm one-shot build would reuse from disk. Exactness tests: a memo hit equals a disk hit byte for byte, on both trees. | 16–24 h |
| **S2** | **Per-module whole-program passes.** Stand-in planning, allocation contracts, origin passes and warning derivation keep per-module results with early cutoff. | Diagnostics, warnings and programs unchanged on the corpus and both trees. These passes under 0.1 s at 400k for a one-line edit. | 12–24 h |
| **S3** | **The server and its client.** The socket protocol, identity check, projected environment, auto-start (D1), lifecycle, `mylang server start|stop|status`, write-behind, logs, and the fallback to one-shot on any server problem. | Every `build`, `run`, `test` and `check` result through the server equals one-shot on the gate's corpus, both trees and `exact.sh`. Killing the server mid-request makes the client finish the request itself. A changed compiler replaces the server. | 16–30 h |
| ~~S4~~ | **Dropped 2026-10-28.** Agents make an explicit `build` or `test` call, and with the server that call costs about 0.3–0.6 s at 400k, which a background pre-build would mostly hide inside the several seconds an agent takes between its edit and its next tool call, at the cost of building intermediate states. Revisit only if logs show agents waiting on slow builds (type edits). | — | — |
| **S5** | **Measurement, docs and gate coverage.** A gate action builds a corpus through the server and compares with one-shot. Memory and latency tables at 99k and 400k. `docs/tooling/` pages. | The goal's numbers measured (§2). The gate passes with the server action. | 8–12 h |

Total: about 58–100 agent hours. S0 comes first and can stop the plan. S1 and S2 are independent,
and S3 needs S1.

**Projected result** (estimates from §1, which S0 measures):
- **400k one-line edit:** 3.5 s today. After S1, about 1.2–1.6 s, since the reload goes but the
  whole-program passes and the process start remain. After S2 and S3, about 0.3–0.6 s.
- **99k:** about 1.0 s today, and about 0.15–0.3 s after S2 and S3.
- **The 669k EDA:** about 6 s today by extrapolation, and under 1 s after S2 and S3.

## 5. Interactions with other work

- **The provable-cache plan.** The server reuses objects only under the keys its records define.
  K2's tracked front-end inputs make those keys provable, and the server needs no separate
  argument. S1's memo is a cache over the same records, so T4's theorem covers it once the memo
  is modelled as "a record read without decoding".
- **The edit-loop plan.**
  - P4a's module records and P4d2's shared stage store are the server's persistence.
  - P4d3 (shared module records and checked bodies) and the optimizer package make fresh
    worktrees warm, and the server makes warm ones fast. They don't depend on each other.
- **`mylang check-session`.** The existing resident checker becomes a client of the server for
  `check` requests, or is retired in favour of it. The audit found it slower than one-shot at 99k
  because of a 16 MiB syntax-cache cap and no summaries. S1's memo replaces both of those limits.
- **The gate.** Gate actions keep running one-shot commands by default. S5 adds one action that
  runs a corpus through a server and compares the results.

## 6. Decisions

| # | Decision | Recommendation |
| --- | --- | --- |
| D1 | **Auto-start.** Should the first `mylang` command start a server automatically, Gradle-daemon style, or only `mylang server start` (or an environment variable) starts one? | **Decided: on by default from the start**, so real use finds the problems. `MYLANG_SERVER=0` turns it off. Every client falls back to doing the work itself when the server is missing, refuses, dies or misbehaves. |
| D2 | **Commands.** Which commands use the server? | **Decided:** `build`, `run`, `test` and `check`. |
| D3 | **Limits.** Memory budget and idle timeout. | **Decided:** one budget per user across all servers, 6 GiB by default and configurable up to 8 GiB (the machine has 30 GiB and the gate reserves up to 8). The least recently used server drops objects first. A 15-minute idle timeout. S0 measures the 400k working set. |
| D4 | **Who implements.** | **Decided:** Claude with Haiku lanes. Claude reviews, gates and lands each package. |
| D5 | **Type edits.** Stable type positions in lowering, so that a type change re-lowers only the functions that use the changed type. | **Decided:** a separate package after S0. |

## 7. Hard stops (report and wait for Claude)

- Any server result, whether program bytes, diagnostics, warnings, verdicts or reports, that
  differs from the one-shot result for the same inputs.
- The server running guest code, or holding capabilities beyond building.
- A socket or file the server creates that is readable or writable by another user.
- Python in `src/` or the install graph.
- S0 showing an in-process second build at 400k over 1.5 s. The plan is then re-scoped before S1.

## 8. After S0: the edit-cost packages (decided 2026-10-28)

S0 showed that a resident process saves about 20% and that the rest of an edit build scales with the program. The
user chose to stop the server and run four packages that make ordinary one-shot builds cheaper instead. Each
attacks a measured row of the S0 profile (`experiments/resident-server-s0-20261028/REPORT.md` §3).

| Package | Work | Exit | Estimate |
| --- | --- | --- | --- |
| **T1** | **The type-edit fallback.** The first type edit after some cache states retries the whole lowering eagerly (`lowering.fallbacks=1`): 31.7 s instead of about 10 s at 400k, with the memo off. Lane J fixed one cause (the optimizer's raw-layout gate) and left one site uninstrumented (J5). Find every producer of the retry, make the type edit take the incremental path, and keep the retry for real misses. | A test that reproduced the fallback before the fix passes. Ten type-edit cycles at 99k and three at 400k, each from a fresh cache state, report `fallbacks=0`, and their programs equal `--no-cache`. | 4–10 h |
| **K** | **Keys once.** Stop recomputing keys and digests of unchanged functions on every build: the lowering key's transitive declaration walk (12% of a 400k edit's CPU), stage keys (6%), canonical function digests (4%), record checksums (2%) and emission's unit lookups (8.5%). For example: one digest per declaration per build, memoized reach closures, and keys derived from digests already computed upstream. Keys must change exactly when they change today. | At 400k, a one-line edit's key, digest and lookup CPU is at least halved (LBR), and BLAKE3 is under 10% of CPU. Programs, diagnostics and reports equal `--no-cache` (`exact.sh`, both trees). A test shows that a declaration a function reaches still changes its key. | 10–20 h |
| **S2** | **Per-module whole-program passes**, as in §4: allocation contracts, origin passes, stand-in planning, the merge, warning derivation, symbolic templates and the ownership cache's whole-catalog validation keep per-module results with early cutoff. | These phases total under 0.15 s at 400k for a one-line edit (0.74 s today). Diagnostics, warnings and programs are unchanged on the gate's corpus and both trees. | 12–24 h |
| **D5** | **Stable type positions in lowering** (§6 D5), done with T1 in lane P (one cause; see Lanes). A type edit re-lowers only the functions that reach the changed type. | A 400k type edit under 4 s (10.3 s today) and a 99k one under 1.5 s (3.5 s today), with programs equal to `--no-cache`. | 12–24 h |
| **C** | **Use the cores** (added 2026-10-28), after T1, D5, K and S2 land, since it changes the same code. A 400k one-line edit uses about 3.4 s of CPU in 4.2 s of wall time: almost all of it on one core of a 20-thread machine. Emission and the native compiles already run in parallel. The per-function work does not depend on other functions' results, and neither do the per-module passes after S2. That covers keys, cache lookups and restores in lowering and the optimizer, and the front end's replay of unchanged bodies. Measure first, on the landed packages: which phases are serial, which can be split, and the contention points (store locks, arenas, the shared demand index). Then split them across a bounded pool that respects the build slot's CPU set and the 1 GiB compile budget. | Output is byte-identical whatever the thread count and order: programs, diagnostics, warnings and reports equal a one-thread build and `--no-cache` on both trees, and a test runs one build at 1 and N threads and compares. A 400k one-line edit's wall time is under 1.5 s on a quiet machine, with CPU no more than 10% above the one-thread build. At 99k, under 0.6 s. | 20–40 h |

**Expected result** (estimate): a one-line edit at 400k from about 3.5 s to about 2.3 s after T1, D5, K and S2, and to
about 1–1.5 s of wall time after C on a quiet machine; at 99k from about 1.0 s to about 0.7 s, then about 0.4–0.6 s.
C saves wall time, not CPU, so its gain shrinks when the machine is busy. Dependency tracking (each build visits only
what an edit reaches) stays the larger redesign, 80–150 h more, considered only if agents still wait on builds after C. Type edits drop to a small multiple of a one-line edit. Each package's exit measures its own share.

**Continued in `docs/audits/edit-cost-plan-2-2026-10-29.md`** (the state of lanes P, Q and R and what is left). **Paused 2026-10-28.** The user moved the compiler dev loop ahead of this work (`docs/audits/compiler-dev-loop-plan-2026-10-28.md`). Lanes P, Q and R stopped at committed checkpoints with handoff notes in their `status.md` and keep their worktrees.

**Lanes.** Claude coordinates Haiku lanes and lands their work, under the rules of
`docs/audits/frontend-edit-loop-plan-2026-10-26.md` §7 (autonomy, measurement, tests, hard stops, files, branches,
machine rules), with these changes:
- lane P runs T1 and D5 as one package, in `~/ai/canopy/mylang-fix` on branch `edit-cost/t1`. T1's cause (P
  DECISIONS T1-1): the lowering key's discovery guard is a running hash over every discovery delta, so a new layout
  shape changes every later function's key. An omitted body then has no artifact (`build.zig` `buildRootsCached`) and
  the whole tree is checked again. The fix is position-independent keys, which is D5's mechanism. Lane P therefore owns
  `src/core/lowering_cache.zig` (including the lowering key's own cost from K) and the optimizer's candidate and demand
  code. Its optimizer change, reuse of greens across a layout change by what each green reaches, is designed in
  DECISIONS.md and reviewed by Claude before it is built;
- lane Q runs S2, in `~/ai/canopy/mylang-w2-r` on branch `edit-cost/s2`;
- lane R runs the rest of K (stage keys, canonical digests, record checksums, emission lookups), in
  `~/ai/canopy/mylang-edit-k` on branch `edit-cost/k` (added once the disk was cleaned, 88 GB free);
- decisions and status go in `experiments/edit-cost-20261028/P/`, `Q/` and `R/` (`DECISIONS.md`, `status.md`), the report
  in `experiments/edit-cost-20261028/REPORT.md`, and evidence in the archive under the same path;
- iterate at 99k and measure 400k at each exit. Time inside `scripts/build-slot.sh timing`, and use CPU and P-core
  instructions as the primary numbers;
- the gate fails under load on per-test deadlines (the golden partitions). A failure that is only a `test deadline:`
  line is rerun once when the machine is quieter, and reported, never hidden.
