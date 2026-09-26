# RC local uniqueness integration slice

Generated local mutation checks now call `myl_qbe_rc_unique_local`, using the
physical slot's ownership guard and registered type. A borrowed slot adopts only
a newly detached owner; replacement of an owned slot releases the old edge through
the runtime's typed uniqueness transaction. Runtime failures retain their specific
status. Generated code performs no inline count or uniqueness operations, so the
same helper instrumentation covers the counting mode.

Semantic COW hoisting is disabled in this experimental lane: its proof does not
account for the temporary physical owners introduced by conservative RC operand
publication. Whole compiler receiver aliases borrow the prepared parent; ordinary
user bindings retain independent owners. GC lowering is unchanged.

Validation used a Debug compiler, SHA-256
`7fc6678db018b61af68e094dd1cf5d7c47bdcebccfc461a37fadfc7961560947`:

- The focused `RC-UNIQUE-LOWER-1` lowering test passed (one named test plus 11
  unconditional test blocks).
- All six `tests/lang/rc_owned_values.my` guests executed freshly and passed on
  QBE Debug and LLVM ReleaseFast with `--rc-runtime=stats`. Added cases cover list
  and dictionary snapshot mutation and a loop that publishes a new snapshot on
  every iteration.
- Whole-tree Guardian passed all 88 checks.

This is an integration slice. Nested receiver write-back, held/pinned callback
scopes, aggregate construction and branch cleanup still require RC lowering and
broader guest validation before WP-4 acceptance.

The following field slice uses the same typed transaction for owned list elements,
dictionary values, and record/box path edges. The compiler receiver local borrows
the prepared parent edge instead of manufacturing a second snapshot owner. The
root/parent lifetime remains live through the mutation. Identity casts are also
classified as borrowed results: an identity text cast does not return a fresh
runtime owner.

The follow-up Debug compiler has SHA-256
`30a6b2aa75668cda6538d169505096a57504402aa65ac983a54c8bda4ff739d5`.
All eight ownership guests passed freshly on QBE Debug and LLVM ReleaseFast in
counting mode, including independent outer/child snapshots of nested lists and
nested dictionary values. A separate `str(parts[0])` probe retained its text after
replacing the list on both backends. The focused lowering tests passed (two named
plus 11 unconditional blocks), and whole-tree Guardian passed 88 checks. Callback
receiver scopes remain the next integration step.
