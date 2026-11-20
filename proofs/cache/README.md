# The build cache in Lean (package K4)

A Lake project, core Lean 4 only (no Mathlib), that holds **a model of the build cache**, **the proof that a warm
build equals the clean build under stated assumptions**, and **`cacheplan`**, which runs the cache's decisions on
recorded traces so that the Zig implementation can be compared with the model on real builds. Lean is a developer
and gate tool only: it is never in the install graph and never spawned from `src/`; building and using selka still
needs only Zig. The toolchain is the one of `proofs/ownership` and `proofs/facts` (`lean-toolchain`, Lean 4.35.0).
The design is `docs/audits/provable-cache-plan-2026-10-26.md` (T2, T4, T5, K4).

```sh
export PATH="$HOME/.elan/bin:$PATH"
cd proofs/cache
lake build                       # the model, the proofs, the examples, the axiom audit, and cacheplan
lake exe cacheplan selftest      # the BLAKE3 test vectors
sh fixtures/check.sh             # the planner on seven requests; the replay rule on a scratch directory
```

## What is proved

`Cache/Theorem.lean`, `warm_eq_clean`. Take

* a set of steps, each a deterministic function of what it reads (`Task`: a tree whose only effects are *read an
  input* and *demand a step*), acyclic (a rank);
* a history `H` of worlds (what the disk, the listings and the environment showed at each build) and a record store
  `σ` that is **faithful** to it: every record is the record running its step in some world of `H` wrote (so an
  empty, partial, stale or out-of-date store is fine);
* the current world `w ∈ H` and `o`, **the clean build of `w`** (the unique solution of the step equations;
  `IsClean.unique`, `IsClean.exists`).

If the digest separates the contents `H` shows (`CollisionFree`, assumption D0) and every earlier recording world
is stable against `w` (`Stable`, assumption E2), then `Sys.build w k σ` returns `o k` for every step `k` and leaves a
store that is again faithful. The build is the one of `Cache/Build.lean`: verify the record of `k` (every recorded
input still shows its digest, or an unchanged settled stat tuple; every recorded step, built first, still shows its
output digest: **early cutoff**), else run the step against the live world, building the steps it demands
(**dynamic dependencies**), and store the record. `cold_eq_clean` is the case of the empty store.

Beside it:

| Theorem | File | What it says |
| --- | --- | --- |
| `warm_eq_clean`, `cold_eq_clean`, `build_correct` | `Theorem.lean` | the above |
| `session_eq_clean` | `Theorem.lean` | **any session**: builds of any steps against any worlds, one after another with one store threaded through, equal the clean builds, if the digest separates what the session shows and each world is stable against every later one |
| `Stable.of_unsettled` | `Build.lean` | hashing every input (no settled tuple) needs no E2 |
| `Task.run_congr` | `Basic.lean` | a step is a function of what it read: a world that shows everything a run showed gives the same run |
| `IsClean.unique`, `IsClean.exists` | `Basic.lean` | the clean build exists (for an inhabited output type) and is unique |
| `FsModel.stable` | `Stamp.lean` | **E2 follows from a clock model plus the age test**: if the file-time clock lags real time by less than `g`, a `stat` shows every earlier write's stamp, and the age window `W` is at least `g`, then an equal settled stat tuple means unchanged bytes |
| `racy_without_age_test` | `Stamp.lean` | without the window (`W = 0`, `g = 5`) the same model has a history with equal tuples over different bytes: the unfixed Zig code's gap |
| `consistent_run` | `Seal.lean` | a run whose reads never contradict each other (the handle's `torn` flag is clear) is a run in one static world, so the record `seal` writes is the record of a world that existed; a torn run writes none |
| `dirty_iff`, `closure_labels_eq`, `admit_sound` | `Admit.lean` | **the test admission rule**: a test none of whose roots can reach a changed node has the same labelled closure (identity, body digest, callee identities of everything reachable), so anything that is a function of that closure is unchanged |
| `checkDirty_sound`, `reused_iff` | `Plan.lean` | a linear certificate that a dirty set is exactly the backward closure of `changed`, and the planner's decision `reused[i] = candidate[i] and no dirty root` |

`Cache/Examples.lean` runs the algorithm on a two-step system (`#guard`s), shows early cutoff, and shows the
algorithm returning a stale output when E2 or D0 is broken on purpose: the hypotheses are not decorative.

`Cache/Check.lean` runs `#assert_axioms` over every theorem above: the build fails unless each depends only on
`propext`, `Classical.choice` and `Quot.sound`. The development declares no `axiom` and has no `sorry`. What the
theorems assume is in `AXIOMS.md`, each assumption with what it would take to close it.

## `cacheplan`

```
cacheplan plan REQUEST [OUT]       the test planner on a recorded SLKCP002 request; writes the reply payload to OUT
cacheplan diff REQUEST...          plan each REQUEST and compare with the recorded reply beside it (X.req and X.rep)
cacheplan changed OLD NEW          a necessary condition of the host's `changed` list on two consecutive requests
cacheplan replay RECORD [--stdlib DIR]   the replay rule on a record under replay-v1/, against the disk now
cacheplan digest FILE | listing DIR [FILTER] | selftest
```

* `plan` and `diff` are `src/cache_plan_reference_v2.zig` (iterative Tarjan, breadth-first dirty propagation,
  per-test closure) on the exact bytes the test runner sends the planner. The dirty set is computed with a distance
  from the changed nodes and **certified** by `checkDirty` (`Plan.lean`) before the decision is printed: the
  decision is proved to be the rule, the indexes (reverse, groups, batches) are computed and compared.
* `replay` parses a replay record, observes the files, directories and environment itself (with its own BLAKE3,
  `Cache/Blake3.lean`, which reproduces the compiler's digests), and decides each input twice: by the
  specification (hash everything), and by the Zig rule with the stat fast path. An input whose stat tuple is
  unchanged while its bytes are not is reported `STALE` (exit 3): a counterexample to E2 on a real file system.

## The differential

`scripts/cache_plan_diff.py` and `scripts/cache_replay_diff.py` drive real builds and compare:

* **planner**: `capture` runs `selka test` through a recording component directory (`SELKA_COMPONENT_DIR`), which
  stores each request and the real component's reply and answers with it; `compare` runs `cacheplan diff` over them;
  `random` sends random graphs (cyclic, acyclic, layered, repeated edges, equal digests, up to 100 000 nodes) to the
  component directly; `changed` checks the host's `changed` lists on consecutive real requests, and a control that
  drops a genuinely new node from the list must be caught.
* **replay**: just before every warm `build`/`run` of the K0 table (`scripts/audit_cache_reads.py`) and of its edit
  chains, `cacheplan replay` is asked what the specification says about each record in the cache directory; afterwards
  the answer is compared with what the Zig compiler did.

The counts and timings are in `NOTES.md`; the gate action `cache-proof` runs the planner half of this differential (`docs/tooling/cache-proof.md`).

## Files

| File | Content |
| --- | --- |
| `Cache/Basic.lean` | `Task`, `Task.run`, `run_congr`, `Below` (acyclicity), `IsClean` and its uniqueness and existence |
| `Cache/Build.lean` | worlds, deps, records, the store, the build algorithm (`exec`, `check`, `rebuild`, `buildStep`, `buildAt`), `Faithful`, `CollisionFree`, `Stable`, `inpOk_sound` |
| `Cache/Theorem.lean` | `exec_spec`, `check_spec`, `rebuild_spec`, `buildStep_spec`, `build_correct`, `warm_eq_clean`, `cold_eq_clean` |
| `Cache/Stamp.lean` | the clock model, the age test, `FsModel.stable`, `racy_without_age_test` |
| `Cache/Seal.lean` | `Task.runT` (reads in a changing world), `Consistent`, `consistent_run` |
| `Cache/Admit.lean` | the call graph, `Dirty`, `Matches`, `Complete`, `closure_labels_eq`, `admit_sound` |
| `Cache/Plan.lean` | `checkDirty`, `checkDirty_sound`, `reusedAt`, `reused_iff` |
| `Cache/PlanRun.lean` | the planner program: request parser, transpose, Tarjan, breadth-first dirty set, closures, reply writer and reader |
| `Cache/Blake3.lean`, `Cache/Replay.lean` | BLAKE3; the replay record, the live disk, the two rules |
| `Cache/Examples.lean` | worked examples and counterexamples (`#guard`) |
| `Cache/Check.lean` | `#assert_axioms` |
| `Main.lean` | `cacheplan` |
| `AXIOMS.md` | what the theorems assume, and what would close each assumption |
| `NOTES.md` | how the model maps to the Zig, where it differs, the findings, the differential counts |
| `fixtures/` | seven planner requests (four recorded from `selka test`, one of them in the version-one protocol, and three random graphs), each with the component's reply; `check.sh` |
