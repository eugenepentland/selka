# Phase 3 notes — `fs.read_text(path)` whole-path helper methods (`eaa3/files`)

Status: complete (compiling, focused-test green). Guardian's `spec` check still
reports `FILE-METHOD-1` as unlinked because `SPEC.md` and `src/features.json`
are shared files this branch may not edit; every other Guardian check is clean.

## What landed

Every whole-path helper in `src/file_operations.zig` `Access` now has a
qualified method spelling on a `Filesystem` local, alongside the free function:

| Method | Free form |
| --- | --- |
| `fs.open(path, mode)` | `open(fs, path, mode)` |
| `fs.read_text(path)` | `read_text(fs, path)` |
| `fs.write_text(path, text)` | `write_text(fs, path, text)` |
| `fs.read_file(path)` | `read_file(fs, path)` |
| `fs.write_file(path, data)` | `write_file(fs, path, data)` |
| `fs.exists(path)` | `exists(fs, path)` |
| `fs.listdir(path)` | `listdir(fs, path)` |
| `fs.mkdir(path)` | `mkdir(fs, path)` |
| `fs.remove(path)` | `remove(fs, path)` |

The receiver is the capability operand, so `Access.methodArity()` is
`arity() - 1`. Both spellings build the same typed `.file_access` node with the
capability as `arguments[0]`, so lowering, effects, origins and bytecode
validation are shared unchanged.

- `src/sema.zig`: `checkFileAccess` now takes the receiver separately from the
  value arguments, and `checkFileAccessCall` / `checkFileAccessMethod` are thin
  arity-checking wrappers over it. `openMode` reads the mode from the value
  arguments, so the free and method forms cannot diverge.
- `checkCapabilityNarrowing` recognizes the method spelling on a local
  `Filesystem` (via `fileAccessMethodKind`) next to `read_only()` and `dir()`.
  `queueExpression` delegates to `queueFilesystemCall`, which queues a helper's
  value arguments (the receiver is a `Span` with no expression node, so the
  checker synthesizes that operand, exactly as the narrowing methods do);
  `consumedTemporaries` accounts for the synthesized receiver.
- `statementWithFile` recognizes the method `open` head, so
  `with fs.open(path, mode) as f:` binds a direct trapping handle just like
  `with open(fs, path, mode) as f:`.
- `src/generic_bodies.zig`: `capabilityMethodCall` rejects the method spelling in
  a generic body with the same `E_GENERIC_BODY_UNSUPPORTED` the free form gets,
  naming the reserved builtin instead of an unknown function.
- Shadowing is unchanged: `fileAccessBuiltin` still requires `owner == null` and
  no same-named local/function/import, so `read_text(fs, path)` keeps resolving
  to a declared `read_text`. The method form belongs to the receiver and is not
  shadowed by that name.

## SPEC.md bullet (proposed — do not apply from this branch)

```markdown
- [FILE-METHOD-1] Every whole-path file helper also accepts a qualified method
  spelling on a `Filesystem` value: `fs.open(path, mode)`, `fs.read_text(path)`,
  `fs.write_text(path, text)`, `fs.read_file(path)`, `fs.write_file(path, data)`,
  `fs.exists(path)`, `fs.listdir(path)`, `fs.mkdir(path)` and `fs.remove(path)`.
  The receiver is the capability operand, so the method form has one fewer
  argument than the free spelling, and both share the same arities, result
  types, `E_ARITY`, the literal-mode `E_FILE_ARGUMENT` rule and the trapping
  `with fs.open(...) as f:` head. The method belongs to the receiver, so a
  declared function or local named `read_text` still claims the free
  `read_text(fs, path)` spelling, and generic bodies keep rejecting the file
  builtins under either spelling.
```

## src/features.json entry (proposed — do not apply from this branch)

```json
"filesystem-methods": {
  "kind": "language",
  "summary": "Every whole-path file helper also accepts a qualified method spelling on a `Filesystem` value (`fs.read_text(path)`), sharing the free form's arities, result types, literal-mode rule and trapping `with fs.open(...)` head; the method stays the receiver's even when a same-named function or local exists.",
  "doc": "docs/io.md#files"
}
```

## Migration notes

- `docs/io.md` examples now show the method spelling; the free functions stay
  documented in the same section and in the helper table.
- `test/fixtures/file-methods.my` is a new guest fixture that checks cleanly and
  lowers every helper plus `with fs.open`. `test/integration.zig` asserts the
  fixture's `FILE_*` bytecode labels and that the method spelling reports
  `E_ARITY` at the CLI.
- No runtime or golden changes: the typed `.file_access` node, request
  encoding and lowering are byte-for-byte the free form's.

## Verification (this branch)

```
zig build                                                # compiles; only Guardian spec fails (shared SPEC.md)
zig build fmt-check                                      # PASS
python3 scripts/focused_test.py units FILE-METHOD        # PASS 15/15
python3 scripts/focused_test.py units IO-                # PASS 24/24
python3 scripts/focused_test.py units "generic function bodies"  # PASS 11/11
python3 scripts/focused_test.py units scoped             # PASS 26/26
python3 scripts/focused_test.py units dir                # PASS 67/67
python3 scripts/focused_test.py cli whole-path           # PASS 1/1
python3 scripts/focused_test.py cli attenuation          # PASS 1/1
./zig-out/focus/mylang doctest .                         # 125 run, 32 checked, 0 failed
```

`ZIG_GLOBAL_CACHE_DIR` must point inside the worktree in this environment.
Git writes are denied in this sandbox (the worktree's `.git` is read-only), so
the changes are left uncommitted for the orchestrator.
