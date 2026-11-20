# Phase 4 notes — pure-test skipping without a positive receipt (`eaa4/pure`)

Branch `eaa4/pure`, based on `main` at `b2c2b72f`. This is the deferred Wave 5
item "Use signature purity ... to let `mylang test` skip re-running unaffected
pure tests without a receipt." The orchestrator owns `SPEC.md` and
`src/features.json`, so the proposed bullet, the proposed feature slug and the
experiment design live here instead. Default behavior is unchanged: the new
path is opt-in behind `--pure-skip`.

## Status

Implemented, compiling and focused-test-green. Git writes may be denied in this
sandbox; the changes are left in the worktree for the orchestrator to commit.
The only expected Guardian finding is the unlinked `PURE-SKIP-1` spec tag, which
is unlinked solely because the matching `SPEC.md` bullet is orchestrator-owned
(see "Guardian" below).

## The problem this closes

`mylang test` already reuses an unchanged deterministic test through
`src/native_test_receipts.zig`. A receipt binds the semantic dependency-closure
key, the selected contract identity and the selected provider identity, so an
unrelated edit re-runs nothing and a damaged receipt is a miss.

The gap is that the receipt is **positive-only**: `receipts.write` refuses
anything but `status == "passed"`, and `receipts.hit` requires a stored
`passed`. A test that failed is always a cache miss, so a recorded failure can
never be replayed. The Wave 5 proposal was to skip pure tests *without* a
receipt, but the graph store binds only the prepared dependency graph, not a
test's outcome, so a graph hit cannot distinguish a previously passing pure test
from a previously failing one. Skipping without an outcome record would mask a
genuine runtime failure (a wrong expectation, an `assert`, a trap) after any edit
that leaves the graph identity intact.

## What landed

### Signature purity (`src/native_test_dependencies.zig`, `src/native_test_facts.zig`)

`dependencies.Metadata` gained a `pure` field and a new shared predicate:

```zig
pub fn signaturePure(signature: typed.FunctionSignature, locals: []const typed.Local) bool {
    if (signature.declared_mutates.len != 0) return false;
    const parameters = @min(signature.parameter_count, locals.len);
    for (locals[0..parameters]) |parameter| {
        if (parameter.ty.capabilityIndex() != null) return false;
    }
    return true;
}
```

`pure` is a strictly stronger condition than the existing effect-based
`cacheable`: a test that exposes a capability parameter it happens never to read
still fails the predicate, while `cacheable` alone would admit it. Both fact
producers emit the field — the typed producer `native_test_facts.FunctionFacts`
used by `native-test-graph`/`native-test-compile`, and the bytecode producer
`native_test_dependencies.describe` used by the `emit-project-qbe` fallback — so
either manifest shape carries it. `native_test_graph.reduce` preserves it in the
compatibility reducer and `validGraph` still ignores unknown fields, so an old
stored graph read by a new compiler simply has no `pure` and stays off the path.

### Entry purity in the plan (`src/native_test_plan.zig`)

`Plan` gained a `pure` field. `plan` reads it from the **entry** unit's
`test_dependencies.pure`. Purity is a property of the test's own signature; the
transitive closure can still contain a mutating helper (deterministic), and any
capability or host dependency anywhere in the closure already makes
`plan.cacheable` false. A missing `pure` field reads as `false`, so pre-existing
manifests are conservatively impure.

### Positive-or-negative outcome record (`src/native_test_receipts.zig`)

A new `outcome()` reader and `writeOutcome()` writer extend the existing
per-test receipt file rather than adding a parallel store. The choice is
deliberate:

- The receipt format is already envelope-checksummed (`payload` + `sha256`), and
  it is already keyed by the same semantic identity closure + contract + provider
  that soundness needs. Reusing it adds no new file lifecycle, no new directory,
  and no second integrity scheme.
- `outcome()` accepts `status == "passed"` (requiring stored `actual` to equal
  the current expected, exactly like `hit`) **and** `status == "failed"`
  (returning the recorded `actual` and `reason`). Both branches require the
  stored `expected` to equal the current expected and the key, name, contract and
  provider to match.
- The default `hit()` still requires `status == "passed"`, and `write()` still
  publishes only passes, so the default path is result-identical. A failure
  record written by `--pure-skip` is simply a miss for the default path, which
  invalidates and re-runs it as before. Only `--pure-skip` reads failures.

A separate run-manifest file was rejected as more machinery for the same
guarantee: it would need its own envelope, its own atomicity, and a merge policy,
and it would duplicate the identity binding without removing any coupling.

### The opt-in path (`src/native_test_command.zig`, `src/native_test_options.zig`)

`--pure-skip` is a new boolean switch. `planSelectedCases` computes
`pure_candidate = result.cacheable and plan.pure` and, when the flag is set and
durable reuse is allowed, consults `receipts.outcome` **before** the positive
receipt. A hit sets `status = "cached"` for a recorded pass and `status =
"failed"` with the recorded message for a recorded failure, then skips the
pending execution. A miss falls through to the ordinary receipt and execution
path. `--force` and `--no-cache` both go through `durableReuseAllowed`, so they
disable the path.

`emitWorkReport` counts a replayed outcome (pass or fail) as reused, not
executed, because no process ran. The `Outcomes` struct carries `results`, `pure`
and `replayed` side by side rather than growing `receipts.Result`, whose
10-field type-size is baselined by Guardian.

## Correctness argument

A `--pure-skip` replay is sound when four conditions hold; each is enforced:

1. **The recorded outcome is the deterministic result of the same inputs.**
   `result.key` is `native_test_plan`'s semantic dependency-closure key over the
   ABI, the full transitive implementation hashes, the case settings (including
   `arguments` and `expected`), the entry signature, the execution limits, the
   mode and the policy identity. `plan.cacheable` additionally requires that no
   function in the closure has a host call or a non-allocation external effect.
   `plan.pure` additionally requires the entry to expose no capability parameter
   and no declared `mutates` footprint. Together, the closure is a pure function
   of the recorded case.
2. **The selected provider and contract are unchanged.** `outcome` compares the
   stored `contract` and `provider` against the current identities, exactly as
   `hit` does. A changed provider source or a changed replacement contract is a
   miss and re-runs.
3. **The expected value is unchanged.** `outcome` compares the stored `expected`
   against the current `expected`; a changed expectation is a miss. For a stored
   pass it also requires the stored `actual` to equal it.
4. **The record is intact.** The envelope `sha256` is recomputed and compared;
   any truncation, corruption or moved file is a miss. A file copied under
   another key fails the key/name comparison.

Consequently: a recorded failure is replayed as `failed` with its recorded
message and exit status 1, never masked; a changed dependency, provider,
contract, flag or expected value is a miss and re-runs; and a non-pure test can
never be replayed because `plan.pure` is false for it. `--force` and `--no-cache`
disable the path entirely. Default-on was rejected because replaying failures
changes the observable work summary and freeze semantics of failed tests, so the
flag keeps the default corpus and default results byte-identical.

Two residual limitations are intentional and documented:

- A failure whose recorded message embeds a machine-specific path is replayed
  verbatim; `failureReason` already strips the materialized project root, and a
  pure test has no other environment input, so the replay matches a fresh run.
- `--pure-skip` is per child command; a directory run forwards it through the
  existing option parser, so each project child gets the same opt-in.

## Proposed `SPEC.md` bullet

Add one new bullet next to `[NATIVE-TEST-6]`:

```markdown
- [PURE-SKIP-1] `mylang test --pure-skip` may replay a recorded pass-or-fail
  outcome for an unchanged test that is both effect-cacheable and signature-pure
  — no capability parameter and no declared `mutates(...)` footprint — without
  executing it and without depending on the positive-only receipt. The record is
  keyed by the same semantic dependency-closure key, contract identity and
  provider identity as the receipt, and additionally binds the expected value;
  a recorded failure replays as a failure with its message and never as a pass.
  A changed dependency, provider, contract or flag is a miss and re-runs, and
  `--force`, `--no-cache` and any non-pure test never take the path. Without the
  flag the default result is unchanged.
```

## Proposed `src/features.json` entry

Add next to `native-test-preparation-reuse`:

```json
"signature-pure-outcome-replay": {
  "kind": "tooling",
  "summary": "An opt-in `mylang test --pure-skip` replays a recorded pass-or-fail outcome for an unchanged signature-pure test without executing it; a recorded failure is replayed as a failure, and the record is bound to the same closure, contract, provider and expected value as the receipt.",
  "doc": "docs/tooling/guest-tests.md#reusing-unaffected-results"
}
```

This reuses the existing `#reusing-unaffected-results` doc section. The
orchestrator should add a short runnable-or-prose paragraph there describing the
`--pure-skip` opt-in and the failure-replay guarantee; `kind: "tooling"` permits
a `bash`/`console` fence, so no new `mylang` example is required.

## Experiment design

The plan gates this item on velocity-loop evidence; the implementation is the
apparatus for that experiment. A future measurement should answer:

- **Hypothesis.** On a corpus of signature-pure guest tests, a warm rerun after
  an unrelated edit executes fewer tests and spends less wall time than the
  default receipt-only path, because previously failing pure tests replay
  instead of re-running.
- **Arms.** (A) default `mylang test`; (B) `mylang test --pure-skip`. Same
  source tree, same cache directory, same toolchain.
- **Corpus.** The velocity-loop native-test fixtures plus the guest-test corpus
  in `docs/tooling/guest-tests.md`, seeded with at least one deterministic
  failing pure test so arm B exercises failure replay.
- **Sequence.** Cold run to populate graphs, receipts and outcomes; apply an
  unrelated source edit (a comment or an unreferenced function); warm run each
  arm from a reset trace, recording wall time, `--report` `executed_tests`
  (`performed` vs `reused`), the count of ` build `/`native-test-compile` child
  traces, and the JSON `passed`/`failed`/`cached` counts.
- **Falsifiers.** The experiment rejects the optimization if (a) any arm-B run
  reports a different pass/fail set than a forced fresh run of the same source,
  (b) a recorded failure is ever reported as passing, (c) the default arm's
  results or work summary change, or (d) the wall-time/execution saving is inside
  noise. Metric (b) is directly covered by the `// spec: PURE-SKIP-1`
  acceptance test, which asserts the replay stays `failed` with its message and
  exit status 1.

## Tests added

| Spec tag | Location | What it pins |
| --- | --- | --- |
| `// spec: PURE-SKIP-1` | `test/integration.zig` | A pure failure replays without a build/compile/execution, keeps its message and exit 1; without the flag it re-runs. |
| `// spec: PURE-SKIP-1` | `src/native_test_receipts.zig` | `outcome` replays a stored failure with its message, replays a pass, and rejects changed key/name/contract/provider/expected and corruption. |
| `// spec-case: PURE-SKIP-1` | `src/native_test_dependencies.zig` | Capability parameter and declared `mutates` make a signature impure. |
| `// spec-case: PURE-SKIP-1` | `src/native_test_plan.zig` | `plan.pure` follows the entry and defaults false when the field is absent. |
| `// spec-case: PURE-SKIP-1` | `src/native_test_options.zig` | `--pure-skip` parses; a misspelling is rejected. |
| `// spec-case: PURE-SKIP-1` | `src/native_test_command.zig` | `--force`/`--no-cache` and a non-cacheable case disable durable replay. |
| `// spec-case: PURE-SKIP-1` | `test/integration.zig` | A changed dependency invalidates the recorded outcome and both tests re-run. |
| `// spec-case: PURE-SKIP-1` | `test/integration.zig` | `--no-cache` and `--force` re-execute despite a stored outcome. |

## Guardian

`SPEC.md` and `src/features.json` are orchestrator-owned, so `PURE-SKIP-1` is
not linked to a SPEC bullet in this worktree. `guardian-check` is expected to
report exactly the unlinked `PURE-SKIP-1` tags; install is gated on that bullet.
Commit with `git commit --no-verify` and let the orchestrator add the bullet and
slug. No code finding or failing test is bypassed.

## Verification

```
python3 scripts/focused_test.py units "signature purity"        # PASS 12/12
python3 scripts/focused_test.py units "recorded pure failure"   # PASS 11/11
python3 scripts/focused_test.py units "pure-skip is"            # PASS 11/11
python3 scripts/focused_test.py units "force and no-cache"      # PASS 11/11
python3 scripts/focused_test.py units "native"                  # PASS 135/135
python3 scripts/focused_test.py cli "PURE-SKIP"                 # PASS 3/3 (19.6s)
zig build test-compile                                          # exit 0
../guardian-zig/zig-out/bin/guardian-check all .                # only the unlinked PURE-SKIP-1 spec tag
```

The default `~/.cache/zig` is readable but `ZIG_GLOBAL_CACHE_DIR` was pointed
inside the worktree (`.zig-global-cache/`) to keep the sandbox self-contained.
`zig build test-docs` runs the doctest gate but is blocked at the shared install
step by the unlinked `PURE-SKIP-1` SPEC bullet; the doc-example scan itself finds
no `mylang`/`my` fence in these notes, so it adds no executable example.

