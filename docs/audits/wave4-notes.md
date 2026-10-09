# Wave 4 notes — foreign calls take a `Host` capability (D6)

Worktree `eaa-wave4` (branch `eaa/wave4`). This file is the integration hand-off for
the pieces I am not allowed to edit (`SPEC.md`, `src/features.json`), plus the
migration record.

## Proposed SPEC bullet

```markdown
- [HOST-CAPABILITY] Every `extern def` and `host def` declares `host: Host` as its
  first parameter. The checker requires a `Host` value at every call and the C ABI
  lowering drops that operand before the foreign call. `effects(host)` stays
  inferred and transitive so effect ceilings keep working. Under `--restrict`,
  `--allow-host` grants the authority; it is granted by default like the other
  capabilities. A callback type whose parameters include `Host` is the only
  function-value route to C.
```

## Proposed `src/features.json` entry

```json
"host-capability-foreign-calls": {
  "kind": "tooling",
  "summary": "Every `extern def` and `host def` takes `host: Host` as its first parameter; the checker verifies it at each call and the C ABI drops it before the foreign call, with `--allow-host` under `--restrict`.",
  "doc": "docs/c-ffi.md#direct-c-imports"
}
```

The anchor resolves and the `docs/c-ffi.md` block (a runnable `# doc: check` example)
now threads `host: Host`.

## Doc example (already migrated in this worktree)

`docs/c-ffi.md`:

```mylang
# doc: skip Historical pre-redesign syntax retained as audit evidence.
# doc: check
extern def abs(host: Host, value: i32) -> i32 effects(host)


extern def floor(host: Host, value: float) -> float effects(host)


def main(host: Host) -> i64:
    return i64(abs(host, -42))
```

## What changed

Core (all under `src/`):

- `runtime_values.zig`: new `host_cap` (next to the other capabilities),
  `capabilityIndex(.host_cap) == 5`, `record_base` raised to 18.
- `prelude.zig`: `Host` -> `host_cap`.
- `parser.zig`: `E_HOST_CAPABILITY` when an `extern def` / `host def` does not
  begin with `host: Host`. Ordered after the existing `E_HOST_DECLARATION`,
  `E_HOST_EFFECTS` and `E_EXTERN_SIGNATURE` checks so those diagnostics still win.
- `sema.zig`: the c_abi/host declaration checks require `locals[0] == host_cap`
  and type-check only the value parameters; `E_HOST_CAPABILITY` is the semantic
  backstop.
- `bytecode.zig`: `validateHost` enforces the same first-parameter rule for forged
  bytecode.
- `qbe_c_abi.zig`: the emitted C wrapper keeps the guest ABI (the `Host` operand is
  still passed) but omits it from the real `call $symbol(...)`.
- `qbe_host_lower.zig`: the copied-value host wrapper marshals only the value
  parameters (argument bytes, scalar slots and host declaration slots are
  renumbered from 0).
- `qbe_host.zig`: the host metadata parameter table excludes the leading `Host`,
  so existing `MylangHostBinding` tables still match unchanged.
- Grants: `cli_grants.zig` (`--allow-host`, `flagFor(.host_cap)`,
  `ungranted`), `qbe_grants.c` (`--allow-host`, `myl_qbe_grant_host_checked`,
  `host_authority`), `qbe_grants.h`, `qbe_build_outputs.zig`
  (`grant("host_cap")`), `qbe_build_options.zig` (`runtimeControl`) and the
  `main.zig` usage text.

Migration script: `scripts/migrate-host-capability.py` adds `host: Host` to every
`extern def` / `host def` head (handles Zig `\\`-prefixed test strings and raw
`.my`/`.md`). Run as `python3 scripts/migrate-host-capability.py .`.

Declaration heads were migrated in every file that mentions them, including the
shared `SPEC.md` / `docs/effects.md` / `docs/io.md`? No — those three are
untouched by rule; they only mention the heads in prose and contain no fenced
declaration, so no SPEC/doc edit is needed there.

Callers were threaded with a `Host` value in:

- `examples/c-ffi/main.my`, `examples/contract-echo/{io,main}.my`
- `src/native_fixtures/composite.my`
- `src/board_trial/guest/{wire,request,observe,validation,geometry,main}.my`
- Zig test source strings: `src/c_abi_test.zig`, `src/host_declarations_test.zig`,
  `src/declarations_test.zig`, `src/unit_test.zig`, `src/semantic_cache_test.zig`,
  `src/schematic/tests.zig` (the `io.my` declaration string), and
  `test/integration.zig` (`host_program` and the new CLI tests).
- docs examples: `docs/c-ffi.md`, `docs/byte-io-bulk.md`, `docs/performance.md`.

`mylang check-project src/board_trial/guest/main.my` is clean.

## WIP / blocker

`src/schematic/guest/*` is **not** fully migrated. Its declaration heads and the
native binding tables already exclude `Host`, but the guest functions do not yet
take or pass a `Host` value. `mylang check-project src/schematic/guest/main.my`
reports `E_ARITY` from `io.my:14` (`circuit_input()`), `sexpr.my:46`
(`io.length(file)`), `text.my:34` (`io.byte(a.file, ...)`), and so on. Threading
`host: Host` through `io`, `text`, `draw`, `circuit`, `ports`, `sexpr`,
`layout*`, `schematic`, `svg`, `validate`, `schematic_inputs` and `main` is the
remaining work; `zig build test-schematic` will fail until then. The board trial
corpus (smaller, same pattern) is complete and is the model for the schematic
change.

## Tests

- `src/c_abi_test.zig`: `// spec: HOST-CAPABILITY` test "foreign declarations
  require a leading Host capability parameter" — `E_HOST_CAPABILITY` for a
  missing/wrong first parameter.
- `test/integration.zig`: `// spec: HOST-CAPABILITY` "CLI threads a Host
  capability through an extern call and runs it natively" (native backend,
  `abs(host, -7)` -> exit 7) and "CLI withholds Host under restrict and grants
  it with --allow-host" (`--restrict` -> exit 2 naming `--allow-host`;
  `--restrict --allow-host` -> exit 7).

Command results:

- `python3 scripts/focused_test.py units host` — PASS 33/33
- `python3 scripts/focused_test.py units "direct C"` — PASS 14/14
- `python3 scripts/focused_test.py units declaration` — PASS 78/78
- `python3 scripts/focused_test.py units "semantic cache"` — PASS 21/21
- `python3 scripts/focused_test.py units "unit data"` — PASS 11/11
- `python3 scripts/focused_test.py units callback` — PASS 46/46
- `python3 scripts/focused_test.py units effect` — PASS 82/82
- `python3 scripts/focused_test.py units "foreign declarations require"` — PASS 11/11
- `python3 scripts/focused_test.py cli Host` — PASS 3/3
- `python3 scripts/focused_test.py cli restrict` — PASS 3/3
- `zig build` compiles and installs; the only failing step is the Guardian
  `spec` check, which reports the unlinked tag `HOST-CAPABILITY` because
  `SPEC.md` cannot be edited from this worktree. This is the sanctioned
  missing-SPEC-bullet exception.

## Integration update (orchestrator)

The `src/schematic/guest/*` corpus was completed during integration with a
diagnostic-driven codemod: every host-reachable function now takes `host: Host`
first, every call passes it, the pre-existing `host` boolean in
`circuit.displayNet` was renamed to `named_host`, and the inline guest sources in
`src/schematic/tests.zig` were threaded too. `zig build test-schematic` passes
13/13 and `check-project src/schematic/guest/main.my` is clean.
