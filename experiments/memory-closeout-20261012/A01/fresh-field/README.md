# Fresh whole-result field receivers

The prior compiler refuses `make().name.copy()` with E_SINGLE_OWNER_BORROW because
its generated collection receiver initializes directly from a field with no named
owner. Naming the whole `make()` result first passes; `baseline.json` preserves
that exact control and refusal. Initial fixture syntax/arity mistakes are recorded
separately by case, with exact original source bytes in `baseline-sources/`; they
are not compiler defects.

The implementation roots a fresh call/invoke result once before rebuilding
its field chain and borrowing the receiver. Existing source ownership and Core
parent tracking continue to govern the field; direct partial moves remain refused.
The walk is bounded to 64 fields. Writes, retained-view operations, move-only or
nonstorable whole results, pending Result owners and borrowed-view roots retain
their prior refusal path. No shared header, IR opcode, or lifetime inference is
introduced. A07 reviewed this contract and normalization.

The positive regression passes all five native modes (release, unoptimized,
verified release, optimized debug, release without facts), with exact output,
zero runtime RC events, zero managed exit-live bytes, direct cleanup, clean LLVM
and legacy-symbol absence. All six negative cases pass in the final focused check.
The initial combined run passed the native matrix but expected the wrong pending
sibling diagnostic: the existing frontend correctly refuses E_RESULT_OPERATION.
Only that test oracle changed before the negative-only rerun.

`results.json` pins source/compiler/test identities and exact commands. Compressed
logs preserve failures and final checks. A07 reviewed the bounded normalization;
Guardian passed 88 checks after extracting the helper to file scope. Queue wait
is recorded separately and is not guest or compiler performance evidence.

The frozen `../samples/fresh_field.my` prints `fresh-field 23`; the shared A01
harness accepts `--cases fresh_field`, and `--ordinary` omits the prototype flag
for later C2/C3 checks. This is intermediate worker qualification; final integrated
C1/C2/C3 and installed-package checks remain separate. No allocation, peak, RSS or
runtime saving is inferred from cleanup counters.
