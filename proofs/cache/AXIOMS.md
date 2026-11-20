# What the cache theorem assumes

**The development declares no Lean `axiom`.** `Cache/Check.lean` runs `#assert_axioms` over the theorems in the build:
it fails unless each depends on nothing beyond `propext`, `Classical.choice` and `Quot.sound`. A `sorry` (`sorryAx`) and
`native_decide` (`Lean.ofReduceBool`) are therefore refused. There is no `sorry` in the project.

What the theorems assume is below, in four kinds. A **hypothesis** is an argument of the theorem. A **model clause**
is true of the Lean model by construction and is an assumption about the Zig code. A **clock clause** is a hypothesis
of `FsModel.stable`, which derives E2. A **host obligation** is what the admission rule asks of the code that
prepares its input.

The plan's text names the digest SHA-256. The code's content digest is **BLAKE3** (`src/core/fast_blake3.zig`, 32
bytes); SHA-256 appears only in the wire snapshot of the planner request and the component deployment digest. The
theorem is about "the digest", and BLAKE3 is its instance.

## Hypotheses of `warm_eq_clean` (`Cache/Theorem.lean`)

| # | Assumption | Where | What would close it |
| --- | --- | --- | --- |
| D0 | **Collision-freedom.** The digest separates any two contents the history shows: if two contents (an input in some world, or a step output in some clean build) have the same digest they are equal. Stated for the finite set a session sees, not as injectivity, because no function from byte strings to 32 bytes is injective; so it is a hypothesis and not a Lean `axiom` (a global injectivity axiom for a 256-bit digest would be inconsistent). For `n` distinct contents BLAKE3 gives a failure probability below `n² / 2^257`. | `CollisionFree` | Nothing in Lean: it is a cryptographic assumption. It can be tested but not proved. |
| E2 | **The stat fast path.** `Stable w₀ w`: for every input whose tuple was settled when recorded in `w₀`, an equal tuple in `w` means equal content. This is the only way the bytes are not compared: the record carries the tuple `(size, inode, mtime, ctime)` seen around a successful hash, and an equal tuple stands for unchanged bytes. | `Stable` | Hashing every input on every build: then no tuple is settled and `Stable.of_unsettled` removes the hypothesis (at the cost the plan's decision E2 declined). Or the clock clauses below. |
| H | **A faithful store.** Every record was written by the algorithm for a world of the history (`Faithful`); the theorem keeps it true. | `Faithful` | Records are checked against corruption (BLAKE3 checksum of the payload in `build_replay.zig`) but not against forgery: a hand-written record is outside the theorem. |
| A | **Acyclic steps**: a step demands only steps of lower rank. | `Sys.below` | Structural: the front end's steps form a DAG by construction. |

## Model clauses (true of the model by construction; assumptions about the code)

| # | Assumption | What would close it |
| --- | --- | --- |
| D1 | **A step reads only through the handle.** A `Task` can do nothing but `input` and `step`. For the Zig steps this is: every file, probe, listing and variable the step's result depends on is read through `src/core/inputs.zig`'s `Handle`. | The K5 rule (no raw file or environment access in the modules of a step). K1 left raw access in `driver.zig`, `unit_cache.zig`, `tool_identity.zig` and `build_replay.zig`; K3 and K5 convert them. K0's `trace` subcommand checks it on the corpus with `strace`. |
| D2 | **A step is a function of what it read.** Same reads, same output. Lean functions are deterministic, so the model has it; the Zig step has it only if nothing else (the clock, a thread schedule, an address, hash-map order, an uninitialised byte) reaches the output. | Not provable in Lean. T5's rotating determinism sample (K5) rebuilds served steps from scratch and compares bytes; `--verify-cache` does it for unit objects; the shared stores count mismatches. |
| D3 | **The toolchain is an input.** The compiler binary, the C runtime and the files `zig cc` reads are recorded (`tool_identity`, `tool_files.list`) so that a change of any of them is a change of an input. | K0's `toolchain` subcommand lists files `zig` opens that the tracked set lacks (`src/core/tool_files.list` was completed from it). The list is audited on the corpus, not proved complete. |
| K | **The key covers what the handle does not.** A record is looked for under a key (compiler identity, flags, entry, configuration, toolchain, keyed environment variables). The model makes the key part of the step's identity. | K0's mutation table (388 cases) found the gaps; each was fixed. The environment contract (`environment_identity.zon`) is tested. |
| Q | **Quiescence.** The world does not change during the build being compared with the clean build. A build under concurrent edits returns the clean build of the world *as it saw it* when its reads never contradict each other (`consistent_run`: a consistent run is a run in one static world), and stores no record when they do (a torn handle's `seal` returns nothing). | Nothing needs closing for correctness; a concurrent edit costs reuse only. `seal` also re-hashes every file at the end, a defence the model does not need. |
| O | **The output store returns the bytes its record names.** A record stores the program by path, digest and stat tuple; a replay copies it after the same stat-or-digest check. The model takes `Rec.out` as the stored content. | The program check uses E2 as well. `--verify-cache` recompiles served units and fails on a byte difference. |

## E2, derived (`Cache/Stamp.lean`: `FsModel.stable`)

The rule of the Zig code since the K3 fix (`src/core/racy.zig`, `unit_cache.observedAt`): read the wall clock `now`
before the first `stat` and before the hash; store the tuple only if `max(mtime, ctime) + W <= now`, with `W = 2 s`;
require the status equal before and after the hash. Before the fix the code trusted any equal tuple (`W = 0`).
`FsModel.stable` proves E2 from the following; `racy_without_age_test` shows the model has a history with equal
tuples over different bytes when `W < g`.

| # | Clock clause | What would close it |
| --- | --- | --- |
| K0 | The content of a path changes only at writes (a write, truncate, rename over the path, unlink and create). | The file system; a bind mount or network file system that changes content without a local write is outside. |
| K1 | A write at real time `t` is stamped `ts` with `ts <= t < ts + g`: the file-time clock lags real time by less than the granule. | Kernel property. `g` is a jiffy (4 ms at `HZ=250`) or finer with multigrain timestamps (kernel 6.13 and later). K0 measured 200 alternating same-size writes on kernel 7.0.0, ext4 and tmpfs: 0 stale. |
| K2 | A `stat` after a write shows a stamp at least as new as the write's. `ctime` cannot be set from user space; `utimensat` sets `mtime` only. | Kernel property. |
| W | `g <= W`: the file-time clock and the wall clock agree to within the window. | The window is 2 s; the granule is milliseconds. A clock stepped back by more than `W - g` between a record and a check breaks it. |

## The admission rule (`Cache/Admit.lean`, `Cache/Plan.lean`)

| # | Assumption | Where | What would close it |
| --- | --- | --- | --- |
| Wf | The graphs are well formed: node identities are unique, every callee has an identity, and a node's sorted callee identities are those of its callees. | `Wf` | `nodes` and `validNodes` in `test_runner_graph.zig` reject anything else. |
| C | **The host's `changed` list is complete** (`Complete`): a node not listed matches a node of the old graph in identity, body digest and callee identities. `prepare` lists exactly the nodes failing that comparison, so C holds of the code by its definition. | `Complete` | A proof of `prepare` (Zig) or moving its comparison into the checked part. The differential checks a consequence on real graphs (`cacheplan changed`: 0 violations; a control that drops a new node is caught every time). |
| T | **A test's outcome is a function of the labelled closure of its roots** (identity, body digest, callee identities of every node reachable), the test's settings, the compiler and the runtime, all of which are in the receipt's key. The graph includes calls and function references. | `admit_sound` | T5's determinism sample over test receipts; K3 puts receipts on records. |
| Idx | The reverse index, the strongly connected groups, the batches and the work counts are computed and compared, not proved. `reused` is proved to be the rule (`reused_iff`) and the dirty set is certified before it is used (`checkDirty_sound`). The retained (`prior`) index is checked by the Zig only structurally (`validateIndexes`: representatives are self-grouped, the reverse rows are the exact transpose) and the planner ignores its groups. | `Plan.lean` | The differential covers them: every reply agrees on `groups` and `reverse`, and the retained index equals the recomputed one in every request that carried one. |

## Not covered by this model

* **Stand-ins** (the checked bodies reused across a signature-preserving edit) and the front-end verdict and summary
  caches are not steps with handle-recorded inputs yet (K2). Plan decision E3 labels them "reuse not covered by the proof".
* **Shared stores** (units, foreign objects, programs, test receipts) hold content-addressed entries read and compared
  by digest every time. They are covered by D0 and D2 only; K3 puts them on records.
* **Diagnostics and side outputs of a step** (warnings, `--stats`, `N cached` lines) are part of a step's output only
  where K2 makes them so. K0 found and fixed the cases where a body was served without them.
* The multi-step dynamic-dependency algorithm of `Cache/Build.lean` describes what K2 and K3 build. Today's code is
  its flat instances: the replay record is one step whose inputs are files, listings and variables; the unit,
  program and foreign stores are single-input memos keyed by digest; test receipts are keyed by IR digests with the
  admission rule above.
