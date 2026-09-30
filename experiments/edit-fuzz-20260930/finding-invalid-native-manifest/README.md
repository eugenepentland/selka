# Finding: incremental module build fails with `host failure: InvalidNativeManifest`

Found by `edit_fuzz.py` on compiler 4f97aa7a (ReleaseFast) in three of three Lox `--gc-runtime`
seeds, always at a `record-field-add` step. The incremental module-by-module build exits 2 with

```
mylang: host failure: InvalidNativeManifest
```

while `--whole-program` builds the same tree without error (verdict `incremental-failed`; nothing
is linked, so this is a loud failure, not a stale executable). It is **not** a regression of
`claude/symbol-invalidation`: a ReleaseFast compiler built before the symbol-cutoff commits
(`.tmp/rf-install`, 10:12 UTC; MODULE-SYMBOL-CUTOFF-1 landed at 11:01) fails identically.

## Reproducer (3 modules, RC or `--gc-runtime`)

```
./repro.sh COMPILER [WORKDIR] [--gc-runtime]
```

`main -> b -> a`. `a.Leaf` is a record with a managed field (`name: bytes`); `b.total` builds a
`Leaf` inside its body (its signature mentions no record); `main` calls `b.total`. A cold module
build compiles 3 modules. After adding `extra: int = 0` to `Leaf` the incremental build fails,
and so does the build after reverting the edit (the layout changed again); re-adding it, or
touching `b`/`main`, builds again. With only scalar fields (`x: int`) all three modules are
recompiled and nothing fails.

## Where it comes from

After the failing build the cache holds `a` and `b` freshly compiled and `main` untouched.
`main.shared.json` (a module's stored native descriptors) still carries the old `Leaf`
descriptor (`.size=` of the old layout), while `a`/`b` carry the new one;
`module_codecs.merge` (`src/module_codecs.zig`, `insert`) then rejects the second, different
definition of the same type identity with `InvalidNativeManifest`. So a reused module's
stored type descriptors go stale when a type it reaches only through a callee body it took
inlined changes layout; the reuse decision (early cutoff, and the symbol-level cutoff on top)
does not account for that. On the Lox port the stale module is `driver` (reused, descriptor of
`ast.ThisExpr` still 56 bytes, fresh 64) after a field is added to `ThisExpr`.

## Files

- `repro.sh`: the 3-module reproducer above.
- `lox-gc-minimal/`: the fuzzer's minimized reproducer for Lox seed 3 (`--minimize`, one patch):
  `original/` is the Lox port, `edits/001-edit-record-field-add.patch` adds `fz_f4: bool = False`
  to `ast.ThisExpr`. `sh lox-gc-minimal/replay.sh COMPILER WORKDIR --gc-runtime` prints
  `original: MATCH ...` then `001-...: MISMATCH (incremental exit 2, whole exit 0)`. The RC build
  of the same edit succeeds on the Lox port (compiled 6 of 18; the reused modules' stored descriptors
  equal a fresh build's there, so RC on Lox is simply not affected; the 3-module reproducer fails under RC).
- `lox-gc-seed{1,2,3}-full/`: the complete edit sequences the fuzzer ran before it hit the bug
  (steps 19, 18 and 15 respectively), `original` links to the minimal reproducer's copy of the
  Lox port. The bug does not need the earlier steps; the minimizer removed all of them.
