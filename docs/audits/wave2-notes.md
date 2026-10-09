# Wave 2 notes — narrowing in Python spelling (`eaa/wave2`)

Status: **partial**, compiling and focused-test-green. `fs.read_only()` and the
removal of the bracket spelling landed; `env.only(...)` and `fs.dir(...)` are
precise WIP (below).

## What landed

- `fs.read_only() -> Filesystem` is a Python-shaped method on a `Filesystem`
  capability value. It reuses `Store.restrict` / `myl_qbe_restrict_resource`
  through the existing typed `restrict_resource` node, so the derived value is an
  ordinary typed value: passable, returnable, storable in records/classes, not
  storable in lists or `Cell`. It performs no I/O and contributes no effect
  (the effect mask is unchanged, exactly like the old spelling).
- `restrict_resource[...]` now fails with `E_REMOVED_SPELLING` and names the
  replacement: `` `restrict_resource[...]` was removed; use `fs.read_only()` ``.
  The parser keyword is retained so the diagnostic is precise; `acquire_resource`,
  `complete_resource`, `read_resource`, `write_resource` and `environment_get`
  are untouched.
- `Clock` / `Entropy` / `Network` are unchanged (nothing to narrow; the value
  route is the narrowing).

## Where the dispatch lives (for the follow-on work)

`fs.read_only()` parses as a **qualified call** (`.call` with `owner = fs`,
`name = read_only`), because the parser resolves `name.name(...)` through
`Parser.parseLeaf`/`methodSuffix`, not `parseMemberSuffix`. The arms added:

- `src/sema.zig` `queueExpression` `.call`: short-circuits `read_only` on a
  local `Filesystem` so `callDeclaration` never treats the receiver as a type.
- `src/sema.zig` `checkCall`: builds the typed `restrict_resource` node with a
  synthetic typed `.local` operand, checks arity, marks the receiver read.
- `src/sema.zig` `consumedTemporaries`: `read_only` consumes no temporary
  (the receiver is a local, not a queued sub-expression).
- `src/sema.zig` `checkedExpression` `.restrict_resource`: now requires exactly
  `.filesystem_cap` and reports `read_only requires a Filesystem capability`.
- `src/generic_bodies.zig` `specialCall`: mirrors the same arm for qualified
  calls inside generic function bodies (`narrow[G](cap: Filesystem)` in
  `src/resource_source_test.zig` exercises it).

## SPEC.md bullets (proposed — do not apply from this branch)

```markdown
- [CAPABILITY-METHOD-NARROWING-1] `fs.read_only() -> Filesystem` narrows a
  `Filesystem` capability to read authority by intersecting its permission mask.
  The derived capability is an ordinary typed value: it can be passed, returned,
  stored in records/classes, and cannot be stored in a list or `Cell`. It
  performs no I/O and contributes no effect.
- [CAPABILITY-METHOD-NARROWING-2] `restrict_resource[...]` is removed. It is
  `E_REMOVED_SPELLING`: `` `restrict_resource[...]` was removed; use
  `fs.read_only()` ``. `acquire_resource`, `complete_resource`,
  `read_resource`, `write_resource` and `environment_get` are unchanged.
```

## src/features.json entry (proposed — do not apply from this branch)

```json
"capability-method-narrowing": {
  "kind": "language",
  "summary": "`fs.read_only()` returns a read-only `Filesystem` capability; it intersects permissions, performs no I/O, and contributes no effect.",
  "doc": "docs/effects.md#capability-method-narrowing"
}
```

## Doc example (proposed for docs/effects.md)

```mylang
# doc: skip Historical pre-redesign syntax retained as audit evidence.
resource File: filesystem

result Open:
    ok: File,
    err: int

def main(fs: Filesystem) -> int:
    read_only_fs = fs.read_only()
    empty: [0]u8 = []
    match acquire_resource[Open](read_only_fs, empty):
        case Open.ok(file):
            _ = file
            return 0
        case Open.err(code):
            return -code
```

## Migration notes

- `test/fixtures/attenuation.my`, `src/resource_source_test.zig` and
  `src/nominal_providers_test.zig` were rewritten from
  `restrict_resource[read](x)` to `x.read_only()`.
- `tests/native_resources.py` still contains `restrict_resource[...]` in a
  driver that is not referenced by `build.zig`; it should be updated when that
  driver is next used.
- The runtime sentinel encoding is **unchanged**: `read_only()` lowers to the
  same `myl_qbe_restrict_resource` call, so
  `tests/goldens/qbe_resource_parity.json` needs no update.

## WIP: `env.only("HOME", "PATH") -> Environment`

Not landed. Design that fits the existing runtime:

1. Environment authority travels as the `UINT64_MAX - 2` sentinel in
   `src/qbe_providers.c`; the allow-list lives in the grant context
   (`MylangGrants.names`, `--allow-env=NAME,...`, checked by `allowed()` in
   `src/qbe_grants.c`). Per-value narrowing therefore needs host-side state.
2. Smallest route: add a bounded scope table to `MylQbeContext`, one entry per
   literal name tuple emitted by the backend, and encode a scope index in the
   sentinel high bits. `env.only(...)` registers/dedups `("HOME", "PATH")` in
   the table and returns the indexed sentinel; `myl_qbe_environment_get`
   intersects the index's names with the grant allow-list before `getenv`.
3. Checker side: `env.only(...)` is again a qualified call (`owner = env`).
   Accept only positional string literals (a literal tuple/list of names);
   reject dynamic/unknown names at check time with `E_ENVIRONMENT_NAME`.
4. Typed node: add an `environment_only` node (or reuse `environment_get` with a
   name-set operand) and lower it in `src/qbe_boundaries.zig`. Bump
   `cache_key.Contract.effects` if a new node kind is added.

## WIP: `fs.dir(path) -> Filesystem`

Not landed. Design that fits the existing runtime:

1. `dir(path)` records a `(root, prefix)` pair in a bounded host-side table and
   returns a sentinel with a scope index; it performs no I/O and contributes no
   effect. Every `myl_qbe_resource_*` call joins the prefix before the existing
   checks, and `src/scoped_providers.zig` rejects escapes with the existing
   `scopedPath` rule (`src/scoped_providers.zig:186-193`).
2. The `Resource` sentinel in `src/qbe_resources.c` (`authority()`, lines
   47-63) gains a scope index; every decode site (`resource_new`,
   `restrict_resource`, `resource_read`, `resource_write`, `resource_complete`)
   must mirror it.
3. Checker side: accept exactly one string-literal path argument; reject a
   dynamic path at check time.

## Verification run on this branch

```
zig build test-units -Dtest-filter=read_only     # PASS 11/11
zig build test-units -Dtest-filter=retry         # PASS 15/15
python3 scripts/focused_test.py units nominal    # PASS 97/97
python3 scripts/focused_test.py units scoped     # PASS 25/25
python3 scripts/focused_test.py cli attenuation  # PASS 1/1
zig fmt --check <changed files>                  # clean
```

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree in this environment; the
default `~/.cache/zig` is read-only under the workspace sandbox.

Not run: `python3 scripts/focused_test.py golden resource` and `zig build`
cannot install because the install step is gated on Guardian, which reports the
two tags above as unlinked (no SPEC.md bullet / features.json slug on this
branch). The sentinel encoding is unchanged, so no golden should move.
