# Resolved Unit value provider-store regression

Support4 source `66890fbc5135a771e6a423724d13c30018ab717f`, compiler SHA256
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`.
The source checker admits `set_add.my`, but checked `dump-ir` aborts at
`build.providerStore` after resolving a non-none reference to `Ref.none` and
indexing the instruction table. `record_set.my` also reproduces it; dictionary
assignment, a plain Unit-returning call and list append are passing controls.
The full migrated `ce_cow.my` showed the same failure. This is a compiler defect,
not an unsupported source contract. Coordinator owns the production guard and
registered regression; A09 only minimized and preserved this pre-fix evidence.
