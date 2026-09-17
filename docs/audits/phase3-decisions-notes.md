# Phase 3 decisions: the two Wave 5 items gated on loop evidence

This note records why the last two Wave 5 items are not implemented in this
phase, what the current state is, and the experiment that would settle each.
Both are decisions the plan itself defers until the velocity loop has data.

## D3 — call-site `&` marker

Status: **decided — still deferred**, unchanged from the accepted D3 answer
("Defer; decide with loop evidence after D2").

The declaration side is live: an externally observable write without a
`mutates(...)` clause is `W_MUTATES_MISSING` (wave 3), the clause is required
before overlap checking, and `mutates(...)` is accepted with or without an
effect ceiling. A call-site marker would be a one-line addition to the call
checker: for each argument position named in the callee's declared `mutates`
footprint, require the source to write `&argument`. No syntax exists for it
today (`&` is a removed spelling, `src/removed_names.zig`).

It must not become a rule before an experiment, because it is the most
Python-hostile item in the sketch: `shuffle(&xs)` and `bump(&counter)` diverge
from Python and from the aliasing decision that made `class` behave like
Python. The experiment is to implement the marker behind a task pack, run the
velocity loop's Python-fidelity and idiom lanes with and without it, and adopt
it only if the fidelity cost is bought back by a measurable review benefit.
No velocity-loop run is available in this session, so the decision stays open.

## Pure-test skipping without a receipt

Status: **not implemented — the existing receipt mechanism already carries the
guarantee, and the proposed shortcut is not safe without more evidence.**

`mylang test` already reuses an unchanged test through
`native_test_receipts.zig`: a receipt binds the semantic dependency-closure key,
the selected provider identity and the contract identity, so an unrelated edit
re-runs nothing, and a missing or damaged receipt is a miss that re-executes.
`src/native_test_dependencies.zig` already classifies a function as `cacheable`
when it has no host call and no external effect.

The Wave 5 proposal is to use signature purity (no capability parameters, no
`mutates` footprint) to skip a pure test **without** a receipt. The graph store
binds the prepared dependency graph but not a test's outcome, so a graph-store
hit cannot tell a previously passing pure test from a previously failing one.
Skipping without the positive receipt would therefore mask a genuine runtime
failure (a wrong `expect*`, an `assert`, a trap) after any edit that leaves the
graph identity intact. Making it sound needs either

- a positive-outcome digest in the graph store (so "unchanged and previously
  passing" is reconstructible without the per-test receipt), or
- a rule that only pure tests with a stored positive outcome may skip, which is
  the receipt by another name.

The plan lists this item as "optional, after the loop has data" and asks for a
purity-based skip to let `mylang test` avoid re-running unaffected pure tests.
The prerequisite data is a measured warm-run profile showing receipt lookup or
storage as the bottleneck; without it the change would trade a real correctness
risk for an unmeasured gain. It stays deferred.

## What *is* implemented from Wave 5

- `fs.read_text(path)`-style method spellings for every whole-path file helper
  (keeping the free-function forms) — see `docs/audits/phase3-files-notes.md`.
- A Python-shaped `Network` surface and `net.host(name)` narrowing — see
  `docs/audits/phase3-net-notes.md`.
- The `clock_now[...]`/`random_u64[...]` trusted-standard-library gate — see
  `docs/audits/phase3-clock-notes.md`.
