# Phase 2 notes — Environment surface and narrowing (`eaa2/env`)

Branch `eaa2/env`, based on `main` at `b9372850`. This file collects the
orchestrator-owned changes a wave must not make directly: `SPEC.md` bullets,
`src/features.json` slugs, prose, and migration notes. Runnable doc examples may
be edited in place; the prose version lives here.

## Status

Complete for `env.get`, `env.only`, `env.names` and the `environment_get[...]`
gate, compiling and focused-test-green. Git writes were denied in this sandbox,
so the changes are staged in the worktree for the orchestrator to commit.

## What landed

### `env.get("NAME") -> Option[str]`

- New `myl_qbe_environment_text(context, authority, key, key_len, &present)` in
  `src/qbe_providers.c` calls the existing `environment_get` provider through a
  bounded 16 KiB host copy, validates UTF-8, and builds a rooted managed text
  with `myl_native_text_from_utf8`.
- `env.get` reuses the checked `environment_get` node/instruction. Its `ty` is
  `Option[str]`; the QBE boundary in `src/qbe_boundaries.zig` branches on
  `typed.environmentShape` (raw result record) versus `prelude.optionShape`
  (Python `Some`/`None`), mirroring `qbe_text.zig` `emitParse`.
- The checker resolves `env.get(...)` on a local `Environment` in `checkCall`,
  materializes the literal name bytes into a `[N]u8` request, and rejects a
  dynamic name with `E_ENVIRONMENT_NAME`. Absent values are `None`; a denied
  authority traps `R_CAPABILITY`.

### Raw `environment_get[...]` is trusted-stdlib only

- `src/parser.zig` `parseEnvironmentGated` accepts the spelling only when
  `Parser.trustedStdlib()` holds, exactly like `__float_sqrt`; ordinary source
  receives `E_INTERNAL_NAME` and is directed to `env.get`.
- To keep the compiler's raw-primitive coverage without exposing the spelling,
  `Source` gained a `trusted_intrinsics` flag and `Compilation.initTrusted`. Only
  the parser's own unit tests (`src/environment_test.zig`,
  `src/generic_providers_test.zig`, `src/nominal_environment_test.zig`,
  `src/nominal_provider_contracts_test.zig`) use it. Guest and embedder code
  goes through `Compilation.init`, which leaves the flag false.

### `env.only("HOME", "PATH") -> Environment`

- The runtime narrows over the existing `--allow-env=NAME,...` allowlist with a
  bounded host scope table appended to `MylQbeContext`
  (`environment_scopes[64]`, ≤16 names of ≤128 bytes). `myl_qbe_environment_only`
  registers/dedups a NUL-separated literal blob and returns a scope-index
  authority (`UINT64_MAX - 3 - index`); `myl_qbe_environment_get` and
  `myl_qbe_environment_text` intersect the scope with the grant allowlist before
  asking the host.
- The checker accepts only positional string literals and rejects a dynamic or
  empty/NUL-bearing name with `E_ENVIRONMENT_NAME`. The node performs no I/O and
  contributes no effect. `src/generic_bodies.zig` mirrors it symbolically.

### `env.names() -> list[str]`

- `myl_qbe_environment_names` publishes the visible names sorted: the narrowed
  scope intersected with the allowlist, the `--allow-env` allowlist itself, or
  the whole process environment when no allowlist is set (bounded to 64 names).
  It builds a managed `list[str]` the same way `listdir` does.
- The checker returns `list[str]` and rejects arguments with `E_ARITY`.

## SPEC.md bullets to add (proposed)

```markdown
- [ENVIRONMENT-GET-1] On a `Environment` capability value, `env.get("NAME")`
  returns `Option[str]`: `Some(value)` decoded as UTF-8 for a value the provider
  exposes and `None` when the name is absent. The name must be a literal `str`,
  and a dynamic name is `E_ENVIRONMENT_NAME`. A name outside the active
  `--allow-env` allowlist is a denied authority and traps `R_CAPABILITY` rather
  than answering `None`. `environment_get[...]` is accepted only in embedded
  standard-library sources, like the `__float_sqrt` intrinsic.
- [ENVIRONMENT-ONLY-1] `env.only("HOME", "PATH") -> Environment` narrows an
  `Environment` to a literal tuple of names by intersecting it with the runtime
  `--allow-env` allowlist. It performs no I/O and contributes no effect, and the
  derived capability is an ordinary typed value. Only positional string literals
  are accepted; a dynamic, empty or NUL-bearing name is `E_ENVIRONMENT_NAME`.
- [ENVIRONMENT-NAMES-1] `env.names() -> list[str]` returns the visible
  environment names as a fresh sorted managed list, honouring both the
  `--allow-env` allowlist and any `env.only(...)` narrowing. It takes no
  arguments and contributes the `environment` effect.
```

## Amendment to an existing SPEC bullet

`[CAPABILITY-METHOD-NARROWING-2]` currently ends "`acquire_resource`,
`complete_resource`, `read_resource`, `write_resource` and `environment_get` are
unchanged." The last clause is now false: `environment_get[...]` is gated behind
`trustedStdlib` (the raw provider contract is unchanged). The orchestrator should
drop `environment_get` from that list or reword it.

## src/features.json entries to add (proposed)

```json
"environment-python-surface": {
  "kind": "language",
  "summary": "`env.get(\"NAME\")` returns `Option[str]`, `env.only(...)` narrows an `Environment` to literal names, and `env.names()` lists the visible names as `list[str]`.",
  "doc": "docs/io.md#environment"
}
```

(`docs/io.md#environment` is prose-only today; point the slug at a new runnable
section if the doc-coverage gate wants a fenced example.)

## Doc example (proposed for `docs/io.md#environment`)

````markdown
```text
# doc: allow-env HOME
# doc: expect True False
def main(env: Environment) -> int effects(environment):
    home = env.get("HOME")
    print(home is not None, env.only("HOME").get("PATH") is not None)
    return 0
```
````

## Migration notes

- `test/fixtures/environment.my`, `examples/environment.my` and
  `examples/boundary-cli/main.my` now use `env.get`.
- `test/integration.zig` migrated its environment programs to `env.get`; the
  CAPABILITY-5 denial case now expects the `R_CAPABILITY` trap that the Python
  surface raises, instead of the raw error code `2`.
- `docs/io.md#environment` prose now describes `env.get`/`env.only`/`env.names`.
  `docs/experiments/environment.md` and `docs/legacy/semantics.md` still narrate
  the historical raw primitive in non-runnable `text` fences; they were left as
  history.
- No golden bytecode moved for the raw provider: `environment_get` lowers to the
  same `myl_qbe_environment_get` call. The Python surface adds new node kinds.

## Bounds and limitations

- `env.only` narrows only the **root** authority. Re-narrowing an already
  narrowed value (`narrowed.only(...)`) is type-correct but traps
  `R_CAPABILITY` at runtime; a follow-on can intersect scope chains instead.
- `env.get`/`env.only`/`env.names` resolve their receiver as a local
  `Environment` binding, matching `fs.read_only()`. A field receiver such as
  `auth.env.get("K")` needs a local binding first (`env = auth.env`) because the
  parser keeps only the receiver spelling for a qualified call.
- The scope table holds 64 deduplicated scopes of at most 16 names each
  (`MYL_QBE_ENVIRONMENT_SCOPES`/`_NAMES`); exceeding either is a bounded
  `CapacityLimit` trap, not silent widening.
- `env.get` copies the value through a 16 KiB host buffer; a larger value traps
  rather than truncating. `env.names()` publishes at most 64 names.

## WIP / deferred: `clock_now[...]` and `random_u64[...]`

The gate for the other two raw spellings was **not** applied. Their public
surface is the embedded `time`/`random` modules, but the compiler's
`src/external_capabilities_test.zig` (14 usages) and `src/generic_calls_test.zig`
walk the raw result schemas directly, and `test/integration.zig` compiles
`clock_now`/`random_u64` as single files. Gating them needs either those tests
migrated to the module surface (a project-based CLI harness) or a trusted-source
hook applied to them as well (`Compilation.initTrusted` already exists and would
cover the unit tests cheaply). This is the remaining piece of wave-0 item B.

## Verification

```
python3 scripts/focused_test.py units environment   # PASS 32/32
python3 scripts/focused_test.py units nominal       # PASS 97/97
python3 scripts/focused_test.py units generic_provider  # PASS 13/13
python3 scripts/focused_test.py units bytecode      # PASS 20/20
python3 scripts/focused_test.py units parser        # PASS 15/15
python3 scripts/focused_test.py cli environment     # PASS 3/3
python3 scripts/focused_test.py cli capability      # PASS 7/7
python3 scripts/focused_test.py cli grant           # PASS 8/8
python3 scripts/focused_test.py cli boundary        # PASS 1/1
zig build test-compile                              # clean
```

`guardian-check all .` fails only on the eight `ENVIRONMENT-*` spec tags, which
have no `SPEC.md` bullet or `features.json` slug yet; a commit must use
`--no-verify` for that reason alone. `zig build`/`test-docs` installs are gated
on that same Guardian run.

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree; the default
`~/.cache/zig` is read-only under the workspace sandbox.
