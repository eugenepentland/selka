# RC mutable-parameter uniqueness — 2026-09-26

An unchanged `mut list[T]` parameter with no counted or unique edges in `T`
uses the caller's existing uniqueness and pinning contract. Scalar writes do
not need another runtime uniqueness check. Any instruction that stores,
moves, drops or takes a reference to that parameter slot declines the shortcut;
rebinding therefore retains the normal check. The test applies to the exact
parameter slot, not an inferred alias.

The caller keeps the payload pinned throughout the activation. Publishing a
snapshot of that payload is already pin-aware and copies its finite protected
path, so it cannot create another snapshot owner of the mutation target. Nested
mutable calls preserve that pin. The receiver's original lifetime rules remain
in force.

A paired counted probe performs 1,000 writes through one mutable parameter.
On both QBE and actual LLVM O3/full-LTO, uniqueness checks fall from 1,003 to 3.
Other counters stay identical: one owner acquisition, three releases, two
allocations and retirements, two hold acquisitions and releases, no clones.
This is a focused traffic result, not a full-corpus performance claim.

The separate caller/callee snapshots, nested mutation and parameter-rebinding
fixture passes both compiler arms on both backends. After the change it keeps
22 allocations/retirements and three clones, while checks fall from 40 to 17.
The broader pending-receiver, aggregate, view, borrow and temporary-lifetime
fixtures pass 65 assertions per backend; counts balance and match across the
two backends. The structural unit selection passes 12 tests. Whole-tree Guardian
passes all 88 checks. Root integration owns the required full gate.

Both compiler installations are Debug. The control is the frozen `ff2bf4ef`
compiler; the candidate SHA256 is `09a3ecc6906f2002c59d2e55f544113d7d9daeb6826464c10c8f56515de775ca`. Exact commands, compiler/source
identities, counters and drivers are in
[evidence](evidence/d9-rc-mut-uniqueness.json.gz). No runner passes `--qbe`
after choosing LLVM. Guest fixtures and compiler proof are tagged
`RC-MUT-UNIQUE-1`.
