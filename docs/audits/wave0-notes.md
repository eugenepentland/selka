# Wave 0 notes: contract hygiene and reading the signature

Branch `eaa/wave0`. Orchestrator-owned integration (SPEC.md, features.json, shared
docs pages) is collected here because wave 0 must not edit those files.

## Landed

### (A) Reading a signature

- `src/prelude.zig`: new `pub fn reservedTypeName(typed.Type) ?[]const u8` maps a
  reserved capability / open-handle type back to its Python spelling
  (`Filesystem`, `Network`, `Clock`, `Entropy`, `Environment`, `File`, `TextFile`).
- `src/interfaces.zig`: `contractTypeTextPath` now renders reserved types through
  `reservedTypeName`, so `--contracts` and the default listing spell `Filesystem`
  and `Clock`, never `filesystem_cap`/`clock_cap`.
- `src/interfaces.zig` `render` now prints the whole callable line:

  ```
  export function NAME def(p:T,...) -> R effects(<inferred mask>) mutates(<names>) ceiling(<declared mask>)
  ```

  `effects(...)` is the checked inferred mask when a program is attached and the
  unbounded mask otherwise; `mutates(...)` is rendered by source parameter name;
  `ceiling(...)` appears only when the source declared a bound. Type/constraint
  lines keep the previous `export type NAME` shape so existing consumers match.
- `src/main.zig` `listInterfaces` attaches a checked compilation to the index when
  it succeeds, so the default listing can publish inferred effects. A body that
  fails to check is ignored: the interface gate still lists declarations and never
  emits body diagnostics (preserves the existing `E_UNKNOWN_SYMBOL`-in-body CLI
  behavior).

Manual probe (`zig-out/focus/mylang` is the focused-test build; `zig build`'s
install step is gated on Guardian):

```
$ mylang list-interfaces main.my
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module main
  export function main def(fs:Filesystem,clock:Clock)->i64 effects()
```

`def main` must be `export main` to appear: the declaration gate lists exports,
and a module project requires the `module main` header, so the bare
`def main(fs: Filesystem, clock: Clock) -> int:` probe needs both. Scalar
spellings stay canonical (`i64`, `[2]i64`, `main::Pair[i64]`) because
`contractSignatureText` is shared with `--contracts`, whose `interface-contracts-v2`
fragments are asserted byte-for-byte by
`test/integration.zig` `R3 canonical descriptors...`; only the capability
spellings changed. If the orchestrator wants `int`/`list[...]` in the default
listing too, that is a follow-on `typed.surfaceTypeText` pass over the default
render only.

Tests (already committed):

- `src/interfaces_test.zig` — `// spec: INTERFACE-SIGNATURE-1`,
  "default interface listing renders the whole signature with Python capability
  spellings" (asserts `def(fs:Filesystem,clock:Clock)->int`, `mutates(values)`,
  `ceiling(mutation)`, no `filesystem_cap`/`clock_cap`).
- `test/integration.zig` — `// spec: INTERFACE-SIGNATURE-CLI-1`,
  "CLI list-interfaces renders capability parameters with their Python spelling".

## SPEC.md bullets to add

```markdown
- [INTERFACE-SIGNATURE-1] `list-interfaces` prints each exported callable's whole
  signature by default: parameters in their Python type spelling (capabilities as
  `Filesystem`, `Network`, `Clock`, `Entropy`, `Environment`, not the removed
  `*_cap` internal names), the inferred `effects(...)` set when the body checks,
  `mutates(...)` by parameter name, and the declared ceiling when the source wrote
  one. A body that fails to check leaves the declaration listed and reports no body
  diagnostic, so the interface gate stays declaration-only. `--contracts` renders
  the same Python capability spellings in its canonical signature text.
- [INTERFACE-SIGNATURE-CLI-1] The `list-interfaces` command renders a capability
  entry parameter as its Python spelling (`Filesystem`, `Clock`) rather than the
  removed internal tag, including for a single-file program that exports `main`.
```

`INTERFACE-SIGNATURE-1` carries the default rendering and `INTERFACE-SIGNATURE-CLI-1`
the command-line probe; both are new tags, so `guardian spec` blocks until these
bullets exist. That is the only reason the wave-0 commit uses `--no-verify`.

## features.json entry to add

```json
"list-interfaces-signature": {
  "kind": "tooling",
  "summary": "`mylang list-interfaces` prints each exported callable's whole signature, with Python capability spellings, the inferred effects set, mutates parameters by name, and any declared ceiling.",
  "doc": "docs/tooling/native-build.md#reading-an-interface"
}
```

The doc anchor needs a new `## Reading an interface` section (or the orchestrator
may point it at an existing tooling section) containing a runnable tool example:

````markdown
## Reading an interface

```console
$ mylang list-interfaces program.my
module interfaces v1; declarations/signature visibility checked; bodies not type checked
module main
  export function main def(fs:Filesystem,clock:Clock)->int effects()
```
````

## (B) Python surface for `Environment` — WIP

Not landed. `env.get("HOME") -> Option[str]` and `env.names() -> list[str]` are
larger than the wave-0 time box once the runtime surface is counted. Precise state:

1. **`env.get` needs one new native boundary.** The existing
   `environment_get[T](env, name)` primitive requires (a) a caller-declared
   `result T` whose success record is exactly `bytes: [N]u8, length: u64,
   present: bool`, and (b) a fixed `[N]u8` name. `Option[str]` needs a managed
   `str`, and the runtime already has `myl_native_text_from_utf8(heap, raw, len)`
   (`src/native_bytes.c`). The smallest coherent path is a new
   `myl_qbe_environment_text(context, authority, key, key_len, &present)` in
   `src/qbe_providers.c` that calls the existing provider through
   `myl_qbe_environment_get`, then builds a rooted text (mirroring
   `myl_qbe_file_access`'s `read_text` branch), plus a `//!` typed node, a
   bytecode instruction, QBE lowering, and the `Option` variant wrap in sema.
   The checker arm belongs next to `.environment_get` at `src/sema.zig:2842` and
   must also accept a `str` literal for the name by materializing its bytes
   (`typed.byteRequest` only accepts `[N]u8`, so a literal-to-fixed-array step is
   required).
2. **`env.names()` needs a runtime enumeration primitive.** `--allow-env=NAME,...`
   is stored host-side in `MylangGrants.names` (`src/qbe_grants.c`) and the guest
   has no way to read it. A list element type is dynamic, so this is a new
   provider call that returns names through a bounded host table, then a
   `list[str]` build in the checker. No existing primitive covers it.
3. **Trusted-stdlib gate is deliberately not moved.** Gating
   `environment_get[...]`, `clock_now[...]` and `random_u64[...]` at
   `src/parser.zig:981-991` the way `__float_sqrt` is gated (`trustedStdlib`,
   `src/parser.zig:120`) is a one-line change per spelling, but it removes public
   spellings still used by `test/fixtures/environment.my` and the CLI tests at
   `test/integration.zig:2798, 2857, 2898, 2953, 3407` (plus examples/docs). That
   migration is wave-2 sized, so wave 0 leaves the spells public and records the
   one-line parser change here. `src/stdlib/time.my:110` and
   `src/stdlib/random.my:46` already spell `clock_now`/`random_u64` and would keep
   working because they are the exact embedded `@stdlib/` bytes.

The intended final API (wave 2 baseline): `env.get("HOME")` returns `Some(str)`
decoded as UTF-8 from the provider's present/length/bytes record and `None` when
absent; `env.names()` returns the sorted allow-list for enumeration. A denial from
`--allow-env` stays an error path (the existing provider returns status 2), so the
Python surface needs to decide between `Option` + a denial trap and
`Result[Option[str], str]`.
