# Additional core fixture migration

The coordinator transferred these eight sources from A10's additional 219-file
inventory to A03. `originals.json` preserves all original sources, hashes,
refusals and original owners. This set is separate from the original30 and
pinned81 census, and from the 36-file guest-test migration. All eight stay in the
denominator, including `v_narrow.my`, whose existing optional mutable parameter
operations remain unchanged and need a compiler fix.

Independent saved values and owned returns from borrowed parameters use explicit
copies. `f1_tbaa` snapshots the selected scalar union before replacing its slot;
its nested-list independence test uses explicit deep copies. `rc_alias_paths`
copies each borrowed input once and returns that local owner, including its early
return branches. Every expected output and assertion remains unchanged.

`i_live_place` has two distinct contracts. Four tests intentionally observe current
list values and growth as a loop proceeds. They now use an index loop with a fresh
scalar read each iteration; the index advances before the possible `continue`.
The saved comparison owner is copied. The root-replacement test instead iterates
an explicit snapshot, preserving its expected pre-replacement values. These source
shapes change the borrowing contract, even though they preserve observed results.
They are not compiler-only performance comparisons. The existing registered
`single owner iteration borrows prevent mutating the iterated root` regression in
`src/core/single_owner_test.zig` still requires `E_SINGLE_OWNER_OVERLAP` for mutation
under a borrowed iterator; A03's additional boundary tests likewise preserve
invalidating child/root and dictionary iteration refusals.

`v_trace` and `v_trap_set` gain same-line copies so trace/trap source locations
remain stable. The runner executes their existing main functions, checks both
successful and failing branches, and checks the full error creation/return/try
trace. `v_inline_loops` has an intentionally inert main in the original fixture;
the evidence mirror inserts an assertion calling its existing public test. Its
public test body and assertion predicate are unchanged. Core counter oracle changes
belong to A09; A03 changes only the explicit copies in `counters.my` and preserves
its output and bounds trap.

`additional-migrations.py` records compiler/source/harness/binary identities and
raw counters, performs structural LLVM/symbol checks, and uses bounded shared
admission. All normal and Result exits must have zero RC events and no managed
exit-live bytes. Intentional native bounds traps abort without managed unwinding:
their exit-live counts remain visible and are not claimed as cleanup passes.
The report retains rejected builds rather than replacing failing source contracts.

Support4 release qualification attempted all eight files: seven admitted, one
refused, and 11 executions passed their exact output/status/error contracts.
All nine nonfatal executions (including the propagated Result error) reported
zero RC and zero managed exit-live bytes; all seven emitted LLVM/symbol audits
passed. The two expected bounds traps recorded 1,192 and 160 exit-live bytes,
respectively, and are explicitly not cleanup qualifications. `v_narrow.my:4`
remains refused with `E_SINGLE_OWNER_MOVED`; A07 owns the optional-place fix.

The compiler was source `66890fbc5135a771e6a423724d13c30018ab717f`, binary
`4cc05e8799be27e86c5efa1083a24d53d36682e60358a9246d15596eb9aac375`.
`support4-results.json.gz` and `support4-raw.tar.gz` preserve exact source and
harness snapshots and all counter/command receipts. This is interim evidence,
not the final C1 qualification. The source burden is 42 added/29 removed lines
including comments, and explicit copy calls increase from 1 to 21.

A09 independently qualified the same counter source hash in eight modes, each
with normal and bounds-trap execution. All five checked-ownership modes recorded
11 list-copy events/880 bytes, 31 allocations/frees, 5,416 allocated bytes, peak
3,560 and zero normal-exit live bytes. Ordinary-mode controls still record one
list copy/800 bytes and 21 allocations/frees. This reflects explicit deep-copy
semantics and descriptor-driven child storage; it is not a zero-copy claim.
The exact native oracle and its durable raw evidence belong to A09.

Support5 resolves the unchanged `v_narrow.my` reproducer in all five required
modes. All five native executions match the full original output and exit0,
report zero RC and zero managed exit-live bytes, and pass LLVM/symbol audits.
The selected scope is one of the eight assigned files; no other Support4 results
are relabeled. `support5-narrow-qualification.json` pins source
`a1f19edf255c8c0886731d8d7cce450d5f657720` and compiler SHA-256
`8b1898be7ad2f95cf53bf709f9d468b3bcfbabcaab2aaa7b5aa48d0163b2a789`.
Adjacent compressed results/raw archives retain sources, harnesses and counters.
This is a targeted interim regression result; final C1 qualification remains due.
