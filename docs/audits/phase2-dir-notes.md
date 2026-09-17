# Phase 2 notes — `fs.dir(path) -> Filesystem` (`eaa2/dir`)

Status: complete (compiling, focused-test green). Guardian's `spec` check still
reports `FILESYSTEM-DIR-1` as unlinked because `SPEC.md` and `src/features.json`
are shared files this branch may not edit; every other Guardian check is clean.

## What landed

- `fs.dir(path) -> Filesystem` returns a derived filesystem whose root is
  `path` resolved under the receiver's root. Like `read_only()`, it is a
  Python-shaped qualified call (`owner = fs`, `name = dir`).
- Lazy and effect-free: the checker builds a typed `dir_resource` node; QBE
  lowers it to `myl_qbe_dir_resource`, which records the joined prefix in a
  bounded (64-entry) host-side scope table and returns a sentinel carrying a
  scope index. It performs no I/O and contributes no effect.
- Sentinel encoding: `bits = -16 - (scope*16 + kind*8 + permissions)`, so
  scope 0 stays byte-for-byte the historical grant/restrict encoding.
- Every acquisition through a scoped sentinel joins the prefix before the
  provider's existing checks (`myl_qbe_resource_new`). A request containing
  `..`, `.`, an empty component, a backslash or NUL is denied even when the
  provider root is a `direct` root that would otherwise follow it.
  `myl_qbe_restrict_resource` preserves the scope while intersecting
  permissions, so `fs.dir("x").read_only()` stays rooted at `x`.
- Checker: exactly one string-literal path argument; a dynamic path or a
  literal that escapes the root is rejected at check time with
  `E_FILESYSTEM_DIR`; a non-`Filesystem` receiver is rejected.
  `src/generic_bodies.zig` mirrors the same arm and validation.
- `fs.read_only()` and the `E_REMOVED_SPELLING` removal remain intact.

## Design detail

`authority()` decodes `(kind, permissions, scope)` for both
`myl_qbe_restrict_resource` and `myl_qbe_resource_new`. `myl_qbe_resource_new`
rejects an out-of-range scope, validates the relative request path with the
`scopedPath` rule, and builds `mode:prefix/path` before handing the request to
the provider. `resource_read`, `resource_write` and `resource_complete` operate
on the `myl_native_resource *` handle that was opened with the joined path, so
they decode no sentinel and need no scope. The scope table is freed by the
runtime's terminal `cleanup` hook, which `dir()` registers exactly as
`resource_new` does.

## SPEC.md bullet (proposed — do not apply from this branch)

```markdown
- [FILESYSTEM-DIR-1] `fs.dir(path) -> Filesystem` derives a filesystem rooted at
  the string-literal `path`, resolved under the receiver's root. It records the
  scope lazily in a bounded host-side table, performs no I/O, and contributes no
  effect. Every acquisition through the derived capability joins the prefix and
  rejects a request that could leave the root (`..`, `.`, empty components,
  backslashes or NUL); `restrict_resource` preserves the scope. A dynamic path
  or a literal that escapes the root is `E_FILESYSTEM_DIR` at check time.
```

## src/features.json entry (proposed — do not apply from this branch)

```json
"filesystem-dir": {
  "kind": "language",
  "summary": "`fs.dir(path)` derives a `Filesystem` rooted at a literal path under the receiver's root; it is lazy, effect-free, and confines every acquisition to that subtree.",
  "doc": "docs/effects.md#filesystem-dir"
}
```

## Doc example (proposed for docs/effects.md)

```mylang
resource File: filesystem

result Open:
    ok: File,
    err: int

def main(fs: Filesystem) -> int:
    scoped = fs.dir("data")
    request: [1]u8 = [42u8]
    match acquire_resource[Open](scoped, request):
        case Open.ok(file):
            _ = file
            return 0
        case Open.err(code):
            return -code
```

## Migration notes

- `test/fixtures/attenuation.my` now derives `fs.dir("nested")` before
  `read_only()`; the CLI bytecode dump therefore contains `DIR_RESOURCE`, and
  `test/integration.zig` asserts it.
- The unscoped sentinel encoding is unchanged, so no runtime golden needed
  regenerating; `tests/goldens/qbe_resource_parity.json` was left as-is.
- `tests/native_resources.py` still names `restrict_resource[...]` in a driver
  not referenced by `build.zig`; it remains untouched, as in wave 2.

## Verification (this branch)

```
zig build test-units -Dtest-filter=dir           # PASS 66/66
python3 scripts/focused_test.py units scoped     # PASS 26/26
python3 scripts/focused_test.py cli attenuation  # PASS 1/1
```

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree in this environment.
