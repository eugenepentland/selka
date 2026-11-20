# The cache proof (`cache-proof`)

The build cache is meant to give one guarantee: **a warm build is byte-identical to a clean build of the same inputs**
(plan T1 to T5 of `docs/audits/provable-cache-plan-2026-10-26.md`). `proofs/cache` is a Lean 4 project (core Lean only, the
toolchain of `proofs/ownership`) that states that guarantee as a theorem about a model of the cache, says exactly what the
theorem assumes, and holds `cacheplan`, which runs the cache's decisions on recorded traces so that the Zig code can be
compared with the model on real builds. Lean is a developer and gate tool: it is never part of building or using selka.

## What is proved

`proofs/cache/Cache/Theorem.lean`. A **step** is a deterministic function of what it reads through the inputs handle
(`src/core/inputs.zig`): files by digest, probes for existence, directory listings, environment variables, and the outputs
of other steps. A **record** holds what a step read, each with its digest, and its output. The **build** verifies a record
(every recorded input still shows its digest or an unchanged settled stat tuple; every recorded step, built first, still
shows its output digest, which is *early cutoff*) and otherwise runs the step against the live world, building the steps it
demands (*dynamic dependencies*). `warm_eq_clean` and `session_eq_clean` say that any sequence of builds against any
sequence of worlds, from an empty or an out-of-date store, returns what the clean build of each world returns, if

- the content digest (BLAKE3) separates the contents the session shows (`CollisionFree`, assumption D0), and
- an unchanged stat tuple that was old enough when recorded stands for unchanged bytes (`Stable`, assumption E2).

E2 is derived, not assumed outright: `FsModel.stable` proves it from a model of the file-time clock and the age window of the
stat path (`src/core/racy.zig`: a tuple is recorded only if it is at least two seconds older than the clock), and
`racy_without_age_test` shows the model has a history with an equal tuple over different bytes when there is no window.
`Cache/Admit.lean` proves the test-receipt admission rule (`cache_plan_reference_v2`: reuse a receipt iff it was a candidate and no
root can reach a changed node) sound against the labelled call-graph closure a receipt depends on, and `Cache/Seal.lean`
that a handle that saw a path change underneath it (a torn handle) writes no record. `proofs/cache/AXIOMS.md` lists every
assumption and what would close it; the development declares no Lean `axiom` and has no `sorry`.

## The gate action `cache-proof`

```console
$ python3 scripts/cache_proof.py --compiler zig-out/bin/selka
cache-proof: lake build ok (no error, no sorry, axioms audited, 0.6 s); fixtures ok; planner: 52 recorded requests (29 with a retained index, 329 tests, 153 reused) from 25 tests/lang entries agree with the component; changed lists: 6 pairs ok, 5/5 controls caught; 400 random graphs (151515 nodes) agree; 13.7 s
$ cd proofs/cache && lake build && sh fixtures/check.sh
$ lake exe cacheplan diff REQUEST.req...
```

The action (`zig build test-cache-proof -Dproofs=true`, `scripts/cache_proof.py`; without the flag the step prints that it was
skipped and exits 0) does four things and fails, never skips, when it cannot:

1. `lake build` in `proofs/cache`, which includes the axiom audit (`Cache/Check.lean`): a `sorry`, or a theorem that uses an axiom other
   than `propext`, `Classical.choice` and `Quot.sound`, fails the build.
2. `proofs/cache/fixtures/check.sh`: seven planner requests (four recorded from `selka test`, one of them in the version-one protocol, and three random graphs) with the real component's replies, and the replay rule on a
   scratch directory changed five ways.
3. **The planner differential on real requests.** A sample of a copy of `tests/lang` runs `selka test` through a recording
   component directory (`SELKA_COMPONENT_DIR`) in four steps: cold, rerun, one integer literal raised, put back. Every request the
   test runner sends the planner and the component's reply are kept, and `cacheplan diff` must agree with the reply on the reuse
   decision, the batches, the strongly connected groups and the reverse index. `cacheplan changed` checks on the consecutive
   requests across an edit a necessary condition of the host's list of changed nodes (every node not listed has a body digest and
   callee count that some node of the previous graph has), and that dropping a genuinely new node from the list is caught.
4. **The planner differential on random graphs**: cyclic, acyclic and layered graphs with repeated edges and equal digests, one of
   100 000 nodes, sent to the component directly.

It declares the compiler (it runs `selka test`), `tests/lang/`, `proofs/cache/` and the two drivers, so an edit to any of them
reruns it and an unrelated edit does not. It does not wait for the language runs and runs beside the other actions.

## `cacheplan`

`lake exe cacheplan` runs the cache's decisions on recorded traces (`proofs/cache/README.md`): `plan` and `diff` are the test planner
of `src/cache_plan_reference_v2.zig` on the exact `SLKCP002` request the test runner sends (the dirty set is certified against the
proved rule before the decision is printed); `changed` is the check above; `replay` decides a record under `replay-v1/` against the
disk and the environment as they are now, by the specification (hash everything) and by the Zig rule with the stat fast path, and
reports `STALE` when a recorded stat tuple is unchanged while the bytes are not. `scripts/cache_replay_diff.py` drives the cases and edit
chains of `scripts/audit_cache_reads.py` and compares `replay` with what the compiler does before each warm build; it is not part of the
gate action until the record format of the K3 work settles.
