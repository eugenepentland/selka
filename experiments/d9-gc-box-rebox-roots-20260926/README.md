# GC roots across recursive box replacement

`fillPlace` copied a shared collection child while frame roots were published,
restored those roots, then called the allocating `myl_native_cow_rebox` helper.
That helper protects the box being replaced and its new inline body. It cannot
protect other live frame values, such as a saved snapshot that still points to
an earlier box. The second rebox could therefore collect that snapshot.

The GC lowering now republishes the normal live frame roots around reboxing and
restores them after the call. Root records are reused after the preceding copy's
root scope ends; no frame shape, C ABI, runtime helper or RC path changes.

The failure predates the private ABI3 work. The frozen earlier Debug compiler
(`before` identity in `identity.json`) prints False for the repeated-write case
on both actual GC backends. Adding step accounting does not fix it. The real
trigger is prior heap activity: the helper alone, or repeated alone, passes;
calling a one-write helper first makes its saved snapshot change from `7` to `17`.
A numeric reduction returns `1717` instead of `1707`. Test cases running in isolated
native processes did not establish that same heap state.

The permanent Zig regression invokes an ordinary main program with step and
frame accounting disabled and GC stress enabled. It first warms the heap with
one boxed-write helper, then performs two writes while keeping a snapshot. Its
exact source is `permanent.my`: frozen before exits `2` on both backends, fixed
compiler exits `0`. This permanently covers the normal executable path.

Validation on `75802ff9` plus the four-line GC change:

- New standalone regression filter: 12/12 (one named and 11 root blocks).
- Existing copy-on-write filter: 32/32.
- Debug install: 12/12 steps, Guardian 88; whole-tree commit check also passes.
- Exact five-case standalone source: all five True under GC stress on actual
  QBE and LLVM after the fix, versus the same repeated-write False before it.
- Minimal permanent source: before exit `2`, after exit `0` on both actual backends.
- Zig formatting and `git diff --check` pass.

The initial runner used `all.my` for a source declaring `module rc_box_writeback`
and correctly received E_MODULE_NAME. Those rows remain in `before.json.gz`;
`before-corrected.json.gz` uses the proper filename. They are not runtime results.
All manifests, commands, stdout and stderr are preserved. LLVM commands use
`--release` without a QBE override. Joined RC validation with the parent's separate
RC rebox fix is recorded in a later supplement; this first commit stays on the
stable ABI2 ancestry and does not claim that existing RC boxed writes were fixed
by a GC-only change.
