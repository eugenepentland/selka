# Agent-usefulness session report — 2026-09-21

Branch `integration/agent-usefulness`, head `3731d312`. **The full gate is green
for the first time on this branch: 67/67 steps.**

| check | result |
| --- | --- |
| `zig build test` (whole gate) | **67/67 steps succeeded** |
| unit root `src/root_test.zig` | **1318 passed, 0 failed, 0 skipped** |
| boundary matrix, QBE vs LLVM | **68 cases agree** |
| Guardian | 88/88 whole-tree on every commit |
| doctest / doc-coverage | 0 mis-tagged, 0 failed |

## What was asked, and where it stands

### 1. Reconcile the main checkout, record the accepted commit — done

The main checkout was being edited concurrently, so the work moved into
`.worktrees/integration` built from a point-in-time snapshot. The accepted
baseline is `3c76c13d`, compiler `sha256 81a8a7125aa1d0fc…`, and the outstanding
Guardian feedback is committed in `guardian-zig` as `beb932a` (a trailing
`failed command:` banner printed after a PASS on piped focused runs — still
visible in this session's output, still cosmetic).

### 2. `by_address` compatibility, and the boundary matrix — done

The ABI moved to `mylang-qbe-native-v6`, `byAddress` refuses a manifest that
omits the fact rather than reading it as the pre-fix by-value answer, and the
inline fixtures reference a constant instead of respelling the tag.

The matrix now covers all four channels the objective names — `invoke`,
`--describe`, `test --cases` and **codec callbacks** — over both backends. It is
`tests/native_boundary_matrix.py`, wired as `zig build test-native-boundary` and
part of `test`:

| channel | cases |
| --- | ---: |
| `invoke`, including lists, composed records and helper calls | 25 |
| `--describe` | 19 |
| `test --cases` (schematic netlists) | 13 |
| codec callbacks (a domain whose codec takes a copyable aggregate by address) | 11 |
| **total** | **68** |

Each case carries its expected value as well as cross-backend agreement, because
a matrix that only compared the two backends would pass if both were wrong the
same way. The two backends get separate caches, because a shared one would let
the second reuse the first's object and make the comparison vacuous.

### 3. I2 — complete

* **`str`** crosses as one wire node per Unicode scalar: ASCII, two-byte, astral,
  combining, empty and embedded NUL all round-trip.
* **`list[T]`** is a second managed kind, decided by collection kind and never by
  shape. A list is admitted only once its element is, by a fixpoint, so
  `list[str]` and `list[list[i64]]` cross while a list of something the codec
  cannot carry is refused instead of producing a manifest the adapter cannot
  resolve.
* **Composed with records, `Option` and `Result`**: a record holding a text and a
  list, a list of those records, an optional scalar, and a result whose arms are
  a record and a text.
* **Rooting**: the pool was sized by argument count and is now argument count plus
  the nesting bound; an element's root is released once its container holds it, so
  live roots track nesting depth rather than element count.
* **GC-stress** on every shape above.
* **Allocation failure**: `QBE-TEXT-3` for text and `QBE-LIST-3` for a
  `list[list[i64]]` and a record holding a text and a list, driving the harness
  rather than inspecting the code, and asserting the decoded structure so a
  failure is the only way for the scenario to fail.
* **Bounded output**: 4000 elements complete, 70000 elements and 70 levels of
  nesting are both refused as `invalid-request` with the argument named.
* **Cyclic output** is unreachable rather than merely bounded — a cycle would need
  a record that contains a list, which is what the same fixpoint declines — and
  that is written down rather than assumed.
* **Two worked examples** under `examples/invoke/`, documented in
  `docs/tooling/invocation.md`, pinned on both backends.

### 4. `round` probe, divergence policy, E1 — verified, and blocked

`tests/lang/rounding.my` and `velocity/divergences.json` (policy
`divergence-policy-v1`, entry `round-half-away-from-zero`, consumed by
`velocity/score.py`) are present and working.

E1's harness works: the scripted reference workflow is accepted and a no-op solver
is rejected, against a frozen compiler and a frozen task pack. **The model-driven
arm cannot start**, and the reason is a credential rather than the code:

```
dsh: MISSING_CREDENTIAL: llm-deepseek: no API key for provider route "deepseek-official"
```

`DEEPSEEK_API_KEY` is unset and there is no entry in the credentials store.

### 5. I3 and P1 — not started

Both are meant to be selected by measured evidence. With the E1 model arm blocked
there is no such evidence yet, so nothing has been chosen.

## The two faults that mattered

**`mylang invoke` could not build an export that called another function.** The
selection file named only the target, so its callees were never lowered and the
emission referenced a function that did not exist. Any tool composed of helpers —
the ordinary shape — was un-invocable whatever its types were. The native-test
path never had this because its planner computes a transitive closure; `invoke`
reused the executor but not the closure. Fixed in `INVOKE-11`.

**The codec-entry fault, red for six rounds.** `invoke_test`'s "undersized codec
result buffer" test segfaulted on its first call through the loaded codec entry.
It was two things and neither was the codec: the Zig test binary is statically
linked and was loading a glibc-linked shared object into itself, so a second
independent glibc came up whose global state disagreed with the process. Linking
the tests dynamically fixed it and exposed two leaks the crash had been hiding.
The unit root went from `1317/1318, 1 crashed` to `1318/1318`.

## What I got wrong, and what it cost

Worth recording, because most of the wasted time was mine:

* **Four rounds of the wrong framing.** The test's name says "undersized buffer",
  so the fault was read as a capacity bug. Moving the roomy call first moved the
  fault with it, which settled it in one experiment — an experiment I could have
  run in round two.
* **A second wrong reading, from an earlier session and carried forward as
  established**: that the fault was "inside the codec entry". File-appending
  probes at the entry, at `co_read`, at `co_write` and at the always-taken
  epilogue produced no log at all.
* **The manifest's own tests had never run.** `src/qbe_wire.zig` was not in
  `src/root_test.zig`'s imports, so the `QBE-TEXT-1`, `QBE-LIST-1` and
  `QBE-LIST-2` checks that pin the manifest existed, satisfied the linkage check,
  and had never executed once — including ones I had added and reported as
  passing in earlier rounds. The unit root went from ~1113 to 1318 tests when the
  module was imported; all the newly reachable ones pass.
* **I broke the doctest gate myself** in round four by putting mylang source in a
  ```` ```python ```` fence, and did not notice for two rounds because my round-end
  checks ran `doc-coverage` (which does not read fences) rather than `doctest`.
* **Two measurement numbers were wrong before they were right**, in the backend
  charts: the Debug compiler inflated the mylang compile figures about tenfold,
  and the Zig arm reported its warm time as the cold one because the cache roots
  it deleted were not the ones it built into. Both are documented with the
  corrected figures.

## What is left

1. **E1's model-driven pilots** need `DEEPSEEK_API_KEY` written through the
   credentials service (the web Models page does it). Everything else about E1 is
   ready. Until then the held-out cohorts cannot run.
2. **I3 capability grants and P1 latency work** are waiting on that evidence.
3. **`bytes` and `dict[str,T]`** remain outside the boundary by design; the plan
   asks for their wire encodings to be specified before implementation.
4. **`zig build fmt-check`** is part of the gate and passes; the reports in
   `docs/audits/` are not in its scope.

## Reproducing the headline numbers

```console
$ ./zigw build test --summary all
Build Summary: 67/67 steps succeeded; 1480/16788 tests passed (15308 skipped)

$ ./zigw build test-units
guardian/test: PASS — 1318 passed
guardian/test: RESULT {"passed":1318,"failed":0,"skipped":0}

$ python3 tests/native_boundary_matrix.py --compiler ./zig-out/bin/mylang
native-boundary: 68 case(s) agree across QBE and LLVM
```
