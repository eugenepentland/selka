# Isolated C3 owned-lowering draft

`owned-lowering-C3.patch` prepares four coordinator-reserved changes against the
exact integration revision in `manifest.json`. It passes a private
`git apply --check`; active production files remain unchanged.

- `build_borrow_selection.zig`: managed selected results always receive the
  validated two-parent marker. Logical string/Optional validation, affine/Result
  refusals and eager evaluation remain unchanged.
- `build_values.zig`: independent repeated elements always use `copyOwned`.
  Scalar copies remain trivial; managed children remain independent.
- `fuse_slice_key.zig`: the existing owned-only analysis becomes the public
  `updated()` implementation. Its parent/bidirectional-phi algorithm is
  byte-identical, and the manifest pins that implementation plus its following
  helper definitions. The legacy forward-phi-only
  alternative and mode checks disappear. Existing callers keep the same public
  API; only the private `ownedUpdated` name is removed. Complexity remains
  O(nodes + edges) per candidate query, not a whole-function linearity claim.
- `core_number_text.zig`: one comment no longer describes the retired counted
  header. The opaque eight-byte prefix and actual layout do not change.

This draft requires A07's mandatory OWN1 Module/Input ABI and A08's persisted
artifact invalidation. Apply only as part of coordinator C3 activation after
C2 qualifies. Re-run selection borrowing/refusals, repetition independence,
slice snapshot/fusion, numeric object/cache tests and final full verification.
Removing these selectors alone does not establish installed-package retirement.
