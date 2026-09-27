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

## Joined RC control

Real two-parent merge `10e9a577` joins the independently mergeable GC fix
`98c53c06` with the parent's RC rebox fix `fd7e8532`, including that branch's
private ABI3 ancestry. This supplement does not promote that private ancestry to
the accepted integration baseline. The joined Debug compiler SHA-256 is
`de468588b3aeb5f2684772fdd39a209a2e55223be6fb4c12921edd610d4a4d5b`.

All eight normal-program runs pass: the minimal warm-then-repeat regression and
the five-case standalone source, each on actual QBE and LLVM under GC stress and
counted RC. Both backends produce identical balanced RC counts:

| Program | Heap allocated / retired | O acquired / released | H acquired / released |
| --- | --- | --- | --- |
| Minimal warm then repeat | 25 / 25 | 26 / 51 | 12 / 12 |
| Five-case standalone | 55 / 55 | 42 / 97 | 16 / 16 |

The five-case source prints True for every case in all four backend/runtime
combinations. The minimal program exits zero in all four. The focused permanent
regression passes 12/12 again on the joined source; Debug install is 12/12 and
Guardian reports 88 checks passed. `joined.json.gz` retains commands, exact source,
exit codes, stdout, stderr, compiler hash and counts; `joined.py` is its runner.
