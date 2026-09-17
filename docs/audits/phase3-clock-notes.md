# Phase 3 notes — trusted gate for `clock_now[...]` and `random_u64[...]` (`eaa3/clock`)

Branch `eaa3/clock`, based on `main` at `ece915f1`. This file collects the
orchestrator-owned changes a wave must not make directly: the `SPEC.md` bullet,
any `src/features.json` slug, prose, and the migration record. Runnable doc
examples may be edited in place; the prose version lives here.

## Status

Complete for the last Wave 0 item: `clock_now[...]` and `random_u64[...]` are now
accepted only in compiler-owned standard-library sources, exactly like
`environment_get[...]` and `__float_sqrt`. Compiling and focused-test-green.
Git writes were denied in this sandbox, so the changes are left in the worktree
for the orchestrator to commit.

## What landed

### The gate (`src/parser.zig`)

- The `.kw_clock_now, .kw_random_u64` expression arm now routes through a new
  `parseExternalGated`, mirroring `parseEnvironmentGated`: it calls
  `Parser.trustedStdlib()` and, on failure, reports `E_INTERNAL_NAME` with
  "`clock_now[...]` and `random_u64[...]` are reserved for compiler-internal
  standard-library sources; use the `time` or `random` standard module".
  The accepted arm moved verbatim into `parseExternalRead`.
- `trustedStdlib()` is unchanged and already accepts the exact embedded
  `@stdlib/time.my` and `@stdlib/random.my` bytes (or `trusted_intrinsics`), so
  `src/stdlib/time.my:110` and `src/stdlib/random.my:46` keep parsing.
- Extracted the file-scope `const eInternalName = "E_INTERNAL_NAME";` now shared
  by `__float_sqrt`, `environment_get` and the new gate, clearing the
  `repeated-string-literal` Guardian finding the third literal introduced.

### Unit tests that legitimately spell the raw reads

- `src/external_capabilities_test.zig`: every compilation that spells
  `clock_now`/`random_u64` now uses `Compilation.initTrusted`, matching how
  `environment_get` was handled. `src/generic_calls_test.zig` does the same for
  `helperScenario` and the two `effectful` compilations;
  `src/generic_providers_test.zig` already used `initTrusted`.
- New negative test `// spec: CLOCK-INTRINSIC-1` in
  `src/external_capabilities_test.zig` (`rejectRaw` helper): an ordinary
  `Compilation.init` source that spells either raw read gets
  `E_INTERNAL_NAME`, and the message names both `time` and `random`.

### Public/CLI surface

- `test/integration.zig` gained project-based helpers next to `runFixture`:
  `runProjectFixture` (writes `main.my`, since the declared module must match the
  file stem), `invokeProject`, `invokeProjectOptions`, and `checkProjectClean`.
  `check`/`run` auto-route a module-syntax entry to the project loader, so the
  public `time`/`random` modules are reachable through the plain CLI.
- `test/fixtures/external-capabilities.my` is now a `module main` entry that
  imports `time`/`random` and calls `time.now`/`random.from_entropy`.
- `examples/external-capabilities.my` became the project directory
  `examples/external-capabilities/main.my` (see the migration record for why the
  single-file path could not be kept).
- The capability tests migrated:
  - `clock_program` is now a `module main` + `import time` program.
  - The CAPABILITY-1 `entropy` fragment and the CAPABILITY-5 `seeded` fragment
    use `random.from_entropy`.
  - The invalid effect-bound fragment uses `time.now` and is exercised through
    the project commands `check`, `run`, `emit-project-qbe` and
    `discover-project-duplicates` (the project analogues of the removed raw
    spellings' commands).

## Proposed SPEC.md bullet

No existing bullet changes. Add one new bullet next to `[INTERNAL-NAME-1]`:

```markdown
- [CLOCK-INTRINSIC-1] The compiler-internal `clock_now[R](capability)` and
  `random_u64[R](capability)` provider reads are accepted only in embedded
  standard-library sources; ordinary source receives `E_INTERNAL_NAME` and is
  directed to the `time` and `random` standard modules. The standard
  `time.now` and `random.from_entropy` wrappers lower to the same provider
  boundary, so no bytecode or native lowering changes.
```

## src/features.json

No new slug. The public surface is already covered by the existing
`standard-time` and `standard-random` slugs; the gate removes a spelling rather
than adding a feature, the same way `[INTERNAL-NAME-1]` carries no slug.

## Docs

- `docs/standard-time-random.md` already documents the module surface with
  runnable `mylang` examples, so no runnable example changes are needed.
- `docs/experiments/external-capabilities.md` and `docs/legacy/semantics.md`
  still narrate the historical raw primitive in non-runnable `text` fences; they
  were left as history, as `environment_get` was.
- `docs/experiments/external-capabilities.md:56` names the old single-file
  example path. It is a historical text fence, not a runnable example; the
  orchestrator may point it at `examples/external-capabilities/main.my` if the
  history should stay navigable.

## Migration record

- `test/fixtures/external-capabilities.my` -> `module main` + `import
  time`/`import random`; `def main(clock, rng) -> int` returns the nanosecond
  count on success and the error message length otherwise. The CLI test only
  checks and lowers it (plus a `--restrict` refusal), so the exact value is
  irrelevant.
- `examples/external-capabilities.my` -> `examples/external-capabilities/main.my`.
  A module-syntax entry must be an identifier `.my` file whose stem matches its
  declared module name (`external-capabilities` has a hyphen and is not a valid
  module name), so the single-file path could not carry `module main`. The
  directory form matches `examples/standard-time-random/` and
  `examples/boundary-cli/`.
- `test/integration.zig` test "CLI checks external capabilities..." now uses
  `checkProjectClean`/`invokeProject`/`invokeProjectOptions`; the old
  `dump-bytecode` assertion over `EXTERNAL_clock`/`EXTERNAL_random` is replaced
  by `emit-project-qbe` asserting the emitted program carries
  `myl_qbe_external_read` (the same provider boundary). The bytecode-dump string
  assertions remain covered by the trusted unit tests in
  `src/external_capabilities_test.zig`.
- `[CAPABILITY-5]`'s seeded program now reads `random.from_entropy(rng)` and
  returns `int(generator.state[0] % 1000u64)`, which is the same raw entropy
  word the old `random_u64[Word](rng)` returned, so the determinism and
  status-from-printed-result expectations are unchanged.
- Pre-existing advisory discovered while migrating: `src/stdlib/random.my:82`
  (`below`) calls `next_word(generator)` without declaring `mutates(generator)`,
  so `mylang check`/`run-project` on any program that imports `random` prints
  `warning[W_MUTATES_MISSING]` to stderr. It predates this change and is outside
  the gate, so `checkProjectClean` tolerates a warning-only stderr instead of
  asserting it is empty. A small follow-on could add `mutates(generator)` to
  `below`; that would be a `src/stdlib/random.my` behavioral change needing its
  own spec handling, so it was left alone here.

## Verification

```
python3 scripts/focused_test.py units external      # PASS 36/36
python3 scripts/focused_test.py units generic_calls # PASS 15/15
python3 scripts/focused_test.py units generic_provider # PASS 13/13
python3 scripts/focused_test.py units stdlib        # PASS 29/29
python3 scripts/focused_test.py units float         # PASS 28/28
python3 scripts/focused_test.py units parser        # PASS 15/15
python3 scripts/focused_test.py units environment   # PASS 32/32
python3 scripts/focused_test.py units nominal       # PASS 97/97
python3 scripts/focused_test.py units bytecode      # PASS 20/20
python3 scripts/focused_test.py cli external        # PASS 1/1
python3 scripts/focused_test.py cli capability      # PASS 7/7
python3 scripts/focused_test.py cli grant           # PASS 8/8
python3 scripts/focused_test.py cli environment     # PASS 3/3
python3 scripts/focused_test.py cli boundary        # PASS 1/1
python3 scripts/focused_test.py cli stream          # PASS 1/1
zig-out/focus/mylang doc-coverage .                 # 0 failures
zig build test-compile                              # every test root compiles
```

`python3 scripts/focused_test.py golden golden` cannot run while `CLOCK-INTRINSIC-1`
is unlinked: the golden target pulls in the install graph, and Guardian gates
install on the missing `SPEC.md` bullet. The golden corpus does not include
`external-capabilities`, so this is only the shared install gate, not a golden
mismatch.

`guardian-check all .` now reports a single finding: the two unlinked
`CLOCK-INTRINSIC-1` spec tags (one in `src/external_capabilities_test.zig`, one
in `test/integration.zig`), which are unlinked only because the `SPEC.md` bullet
above is orchestrator-owned. `zig build`'s install step is therefore gated on
that same Guardian run; use `zig-out/focus/mylang` for manual probes. The
`repeated-string-literal` finding is resolved.

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree; the default
`~/.cache/zig` is read-only under the workspace sandbox. Git index writes are
denied in this sandbox (`git rm` and `git add` both fail to create
`.git/worktrees/eaa3-clock/index.lock`), so the deleted
`examples/external-capabilities.my` and the new files are left in the worktree
for the orchestrator to commit.
