# Wave 3 notes: the mutation footprint is mandatory (D2)

Worktree: `/home/epentland/ai/canopy/mylang-worktrees/eaa-wave3` (branch `eaa/wave3`).
Base: `aac7722f` ("capture in-flight dotted-module and dead-write work as the
effects-as-arguments base").

## What landed

- `src/origins.zig` grows `W_MUTATES_MISSING` (`missing_footprint_code`) as a
  **warning** (severity `.warning`, never `violated`). It fires for a function
  whose inferred summary is externally observable (`summary.external`) and whose
  declaration has no `mutates(...)` clause (`signature.declared_mutates` empty).
  Span is `summary.witness` when present, else `function.declaration`.
  - The message prints the inferred clause verbatim so the fix is a paste, e.g.
    ``this function writes `values` (parameter 1) reachable from the caller;
    declare `mutates(values)` ``. Every inferred position is listed in order,
    comma-separated; names come from the checked parameter locals and fall back
    to `p<N>`; an untraceable target (`mutates_unknown`) widens to every
    parameter exactly as the published inferred footprint does.
  - A declared ceiling keeps the existing `E_MUTATION_PERMISSION` path byte for
    byte (same code, span, related ceiling span). An omitted footprint on an
    *unbounded* declaration is the only case that warns: with a ceiling, the
    existing check already fires (an empty declared footprint cannot cover an
    external write), so the warning cannot double-report it.
- `src/parser.zig`: `mutates(...)` is accepted with **no** effect ceiling
  ("unbounded effects, this footprint"). The `E_MUTATES_EFFECT` rejection is
  unchanged when an explicit ceiling is present and lacks `mutation`.
  - Note: `noio` and `noalloc` both *include* `mutation` (they subtract `io` and
    `managed_allocation` from `effects.all`, and `mutation` is in neither
    subtraction), so `noio mutates(x)` and `noalloc mutates(x)` remain legal.
    Only an `effects(...)` enumeration that omits `mutation` rejects.
- `E_MUTATION_OVERLAP` already keys on `callee.signature.declared_mutates`
  independent of any ceiling (`origins.overlapForCall`), so a no-ceiling
  declared footprint is already an overlap contract. Pinned by a new test; no
  production change was needed for item (3).

## Proposed SPEC.md bullet (cannot edit SPEC.md in this wave)

Add, near the MUTATION-* bullets:

```
- [W-MUTATES-MISSING] A function with no effect ceiling whose body writes storage reachable from a caller argument is diagnosed with a warning when its declaration omits `mutates(...)`; the diagnostic prints the inferred clause verbatim so it can be pasted onto the declaration, listing every inferred parameter position by name. A `mutates(...)` clause without an effect ceiling means unbounded effects with that declared footprint, and an explicit ceiling that lacks `mutation` still rejects `E_MUTATES_EFFECT`. The warning is advisory for this version (ADR D7) and does not fail the build; a declared ceiling keeps the existing `E_MUTATION_PERMISSION` enforcement unchanged.
```

Also amend `[MUTATION-METADATA-1]` at `SPEC.md:104`, which currently says the
clause "requires the mutation bit": qualify it as requiring the mutation bit
**only when an effect ceiling is declared**.

## Proposed `src/features.json` entry (cannot edit features.json in this wave)

```json
"mandatory-mutation-footprint-warning": {
  "kind": "language",
  "summary": "A function with no effect ceiling that writes caller-reachable storage without a `mutates(...)` clause is warned with the inferred footprint printed verbatim; `mutates(...)` without a ceiling means unbounded effects with that footprint.",
  "doc": "docs/effects.md#mutation-contracts"
}
```

The `doc` anchor reuses the existing `docs/effects.md#mutation-contracts`
section (shared page, not edited here). The orchestrator may prefer a new
`#mandatory-mutation-footprint` section with a runnable example; the wave-3 doc
example to add there is:

```mylang notest
def touch(values: list[int]) -> None:
    values[0] = 1


def main() -> int:
    values = [1]
    touch(values)
    return 0
```

`mylang check` prints:
`warning[W_MUTATES_MISSING]: this function writes `values` (parameter 1) reachable from the caller; declare `mutates(values)``.

## Warning census (for the error flip)

Checked with the freshly built `zig-out/focus/mylang check` on every `.my` file:

- `examples/`: 87 files, 63 check clean, 24 are non-entry modules (`E_MAIN` /
  `E_MODULE_NAME`, expected). **3 `W_MUTATES_MISSING` warnings**:
  - `examples/gc-default/main.my:5` — writes `pins` (parameter 1).
  - `examples/standard-time-random/main.my` via `@stdlib/random.my:82` — writes
    `generator` (parameter 1); the bundled standard library itself carries one.
  - `examples/unit.my:2` — writes `values` (parameter 1).
- `tests/guest/`: 11 files, 0 warnings (42 guest tests still pass).
- `experiments/`: 319 files, 0 warnings (most are non-entry fragments that do
  not check standalone).

So the error flip would have to fix 3 corpus sites plus whatever the held-out
suites contain.

## Tests added (in `src/effects_test.zig`, all tagged where behavioral)

- `// spec: W-MUTATES-MISSING` "an unbounded external write warns with the
  inferred mutates clause verbatim" — asserts the exact message text.
- `// spec: W-MUTATES-MISSING` "every inferred position is listed in the warning
  clause" — asserts `mutates(first, second)`.
- `// spec: W-MUTATES-MISSING` "a declared mutates footprint without a ceiling is
  accepted and warns nothing".
- `// spec: W-MUTATES-MISSING` "an explicit ceiling lacking mutation still
  rejects a mutates clause" (`effects()` and `effects(output)`).
- `// spec: W-MUTATES-MISSING` "a function that writes only its own local storage
  is not warned".
- `// spec: MUTATION-OVERLAP-1` "a declared footprint without a ceiling still
  enforces overlap at call sites".

Two test helpers changed to select the first **error** diagnostic instead of
`diagnostics.items[0]`, because a warning now legitimately precedes an expected
error in the same program: `src/effects_test.zig` and
`src/managed_lists_test.zig` (one guarded test).

## Migration notes

- Warning is advisory: `check`, `build`, `run` and `test` still succeed with it
  present; only `mylang check` output is noisier.
- The error flip (a later version) becomes `E_MUTATES_MISSING` at the same span
  with the same message; the parser already accepts the suggested fix, so the
  corpus fixes are mechanical paste-ins.
- No analysis or encoding changed, so no `cache_key.Contract.effects` /
  `semantic_cache.mutation_contract_version` bump was made. If a persistent
  semantic cache is observed replaying a pre-warning body, bump the version.

## Verification in this worktree

- `zig build test-units --summary all` → **1137/1137 passed**.
- `zig build test-cli --summary all` → **126/126 passed**.
- `zig-out/focus/mylang test tests/guest` → **42 passed / 0 failed**.
- `zig-out/focus/mylang doctest .` → **0 failed** (464 blocks, 121 run, 24
  checked, 10 skipped).
- `zig-out/focus/mylang doc-coverage .` → **0 failures**.
- `zig build` and `zig build test-golden` compile every artifact but the install
  step fails **only** on Guardian's `spec` check: `unlinked tag:
  W-MUTATES-MISSING` findings, because the matching `SPEC.md` bullet and
  `verify.json` evidence may not be added in this wave. Per the wave rules the
  commit would use `--no-verify` for that sole finding. No
  `bool-ops-per-condition`, field/param-limit, doc, orphan-file, RNG, or
  type-size finding remains.
  - A throwaway experiment (add the SPEC bullet, run, revert) showed the bullet
    itself is then reported `unverified` and the tags stay `unlinked` until the
    shared `verify.json` links them, so `test-golden` cannot go green from a
    wave-3-only edit. `SPEC.md` was restored byte-for-byte (empty diff).

## Commit blocker (environment)

`git add`/`git commit` cannot write: the main checkout and its `.git` (where
this linked worktree's index, objects and refs live) are mounted **read-only**
(`/proc/self/mountinfo`: `/home/epentland/ai ... ro`; only
`.../mylang-worktrees/eaa-wave3` is the `rw` bind mount). The one permitted
escalation to `danger-full-access` was rejected because no approval channel is
available, so the changes live as a dirty (but compiling, test-green) working
tree on branch `eaa/wave3`, base `aac7722f0a8620e9fcc0c6311df3dd8cc3843beb`.
A unified patch of all four source edits plus this notes file is at
`.mylang-cache/wave3-changes.patch`.
