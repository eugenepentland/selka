# P7 owned list exchange — qualification in progress

`list.exchange(index, replacement)` evaluates each argument once, refreshes the writable receiver, normalizes signed negative indices once, checks bounds, publishes the replacement, and returns the old element. Unsigned indices keep unsigned semantics; u64 max traps rather than selecting the last element. Checked ownership consumes replacement argument 1, refuses borrowed donors and overlapping mutable argument evaluation, and treats a fresh exchange match as an owning temporary. Kind.exchange is appended to preserve existing operation ordinals.

Zero-RC lowers to place_read + one-use list_set without a runtime helper or parent copy. RC detaches a shared parent using the established place_copy protocol before taking the element. This is required for snapshot independence; the earlier ordinary-read RC experiment failed and remains preserved.

Remaining Result-bearing mutable list parameters return to the caller's obligation. Both concrete and symbolic `mut` call arguments borrow named pending lists, preserving that caller obligation. Only scope-exit checking exempts those declared writeback parameters; overwrite checking and caller/local old-element obligations remain active. Generic scalar/Result exchange remains covered; borrowed managed generic value parameters still need an explicit independent copy.

`src/core/transfers.zig` replaces the old function-wide matching read scan. A per-slot token flows through CFG edges; the first overlapping store consumes it. A merge accepts only the identical token on all incoming paths. Backedges cannot reuse a token from before the loop. Exact field paths and list/dictionary-value projections determine pairing; dictionary key reads never pair with value stores. Raw IR tests cover sibling branches, multiple writes, cross-block writeback, loop turns, and 512 distinct slots. Each incoming block state changes at most twice after initially absent; a conservative three visits per block bounds the CFG walk by O(keys × (instructions + CFG edges)). Normalized read/store event keys are computed once before that walk; including uncompressed forwarding-copy resolution, total work is O(instructions × maximum-copy-depth + keys × (instructions + CFG edges)). Functions without transferred reads return before allocating event tables. Per-key scratch is reset with retained capacity, bounding per-key auxiliary peak by O(blocks + edges), in addition to the O(instructions) event tables/output mask and unique-key map. The existing SSA owner/index identity is still required: consuming mutations version the receiver, while frontend borrow/overlap checks prohibit invalid aliases and argument mutations.

Cache identity already includes all compiler source bytes: build_identity.zig scans production src (excluding test-only Zig roots), frontend_reuse.compiler_identity supplies stage_store.Store.identity, and every stage key is scoped to that identity. No redundant lowering cache scope bump is needed for the new accepted behavior.

## Preserved failures and diagnostic installs

- install.log: duplicate primary spec annotation and generic collectionOperation complexity; fixed.
- install-2.log: green default component route, frozen green-install-002, diagnostic only.
- verification/ and verify.log: first verifier rejected generic remaining Result parameter and incorrect main capability/args order; fixed without dropping generic coverage.
- core-exchange.log: first source/relocation fixture failures; frontend overlapping calls correctly refuse E_MUTATION_OVERLAP in both ownership modes.
- install-3.log: Guardian allocator helper hygiene; fixed.
- install-4.log / install-4-cancelled.json: own queued waiter cancelled before admission to retain the qualified explicit component route.
- install-5.log / install-5-failed.json: Guardian flags/facts import cycle and repeated import string; replaced with separate transfers module.
- install-6.log: Guardian inferred public error set and test-loop shape; fixed.
- install-7.log: explicit-route green; frozen green-install-007 full inventory is green-install-007.json. Compiler SHA256 fc9175e25191212d27102826b24fcc99e47fdc9e3a91f5a5f8312ef9e69525a2. This snapshot is diagnostic and predates the RC detach fix.
- core-exchange-2.log: raw test capture shadowed module constant; fixed.
- core-exchange-3.log: 10/12 passed, including transfer raw/scaling and existing nested-list/dictionary tests. Exchange source shadowing and generic Ok inference fixture errors fixed. RC snapshot printed correct values but terminated abnormally.
- rc-audit-007/: exact RC builds/runs against frozen007. Release SIGSEGV (-11), debug SIGABRT (-6, invalid free), verified R_CORE_FACT (unique-free count0 at old.append). This motivated the RC place_copy/place_read fix; counters reporting zero at exit did not establish a successful process.
- sibling-audit-002/: 4 successful builds and 8 successful branch executions in RC/zero-RC, each live-at-exit zero. Public-source branch fixtures did not demonstrate the raw IR classification hazard.
- docs/: first RC documentation build succeeded; own waiting run was cancelled, receipts retained. Final document qualification must use one frozen final compiler in both ownership modes.

## Native route

All native commands source `/home/epentland/.config/mylang/dev-env.sh`, set private TMPDIR `.tmp/lox-eda-parity/P7/tmp`, and acquire one outer `scripts/build-slot.sh build` lease. Tests/verifiers execute direct child commands under that lease, without nested admission. Shared slot directory and other sessions are unchanged. Zig is `/home/epentland/zig-toolchains/0.17.0-dev.1683+5ceec001b/zig`; jobs4 and maxrss8589934592.

Exact explicit-route install command (attempt filename changes only):

```sh
source /home/epentland/.config/mylang/dev-env.sh
TMPDIR="$PWD/.tmp/lox-eda-parity/P7/tmp" scripts/build-slot.sh build zig build \
  --prefix .tmp/lox-eda-parity/P7/install -j4 --maxrss 8589934592 \
  -Dcomponent-owned-compiler-pin=/home/epentland/ai/canopy/mylang-memory-20261012-A10/experiments/memory-closeout-20261012/A10/packaging-support6-candidate/candidate-pin.json \
  -Dcomponent-seed-source=/home/epentland/ai/canopy/mylang-memory-20261012-A10/.tmp/memory-closeout/A10/owned-pin-support6-5167c588/source.tar
```

Qualified immutable route file: experiments/text-gaps-20261012/coordinator/component-route.json SHA256 8b46bf0ad1ad652c5c462fab175265af40dfb47e3439e5a46e9753ca702dde8f. Pin SHA256 32f37baa2509b01c231a104d7e9ba224a7193399201d0f87ec8a5db8fa6f039b. Seed archive SHA256 0557a645579881d54d3f4c493c8b07be38d42b0a21622ab712b84589ee212c27, 1517547520 bytes. Neither immutable input was edited or repinned. Full installed inventory includes bin, libexec manifest and executable versions (including retained versions), and tools/selka-components.

Explicit-route install8 passed Guardian88. Frozen prefix: `/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p7/.tmp/lox-eda-parity/P7/green-install-008`; compiler SHA256 `62b0d88701eee1f214bdf76548bc481857245eba36482eeaac518dbb1e0bc4a2`. Full8-file installation and all source hashes are in green-install-008.json. core-exchange-6.log reports12/12 passed, process0: checked exchange in all5 modes, RC snapshots release/debug/verified, raw token/scaling, and existing nested list/dictionary regressions. The512-slot scaling regression did not appear in the runner’s over50ms list; this is a smoke observation, not a benchmark. docs-008/commands.json reports RC+zeroRC builds0/runs42 with empty runtime stdout/stderr. Larger manual qualification and commit remain pending. No timing benchmark or external-session interruption was performed by P7.

Build input hashes: Zig executable SHA256 `1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f`; sourced dev-env.sh SHA256 `2731287ef088fd02d913b8123754afec1820c5f9d9c882edd31435d42db48e24`.

## Marked-read protocol and invalid raw SSA shapes

A transfer table is a classifier for compiler-produced linear place-update protocols; false is not a safe alternate ownership interpretation for arbitrary marked IR. `own.zig` separately treats a marked managed read as owned. Raw IR that joins two outstanding marked reads before one store, or consumes the same receiver SSA through an intervening dynamic-index write, is outside the lowering protocol and must not be supplied to emission.

The builder excludes those shapes structurally. build_list_methods.exchange evaluates arguments and signed normalization before emitting exactly one marked list_get immediately followed by its list_set. build.writableReceiverOf captures each parent and child once after arguments; storeInto recursively reconstructs those captured paths. Each listSet returns a new receiver SSA ref, writeOwner publishes it, and ir.Op.consumesOperand0 marks list_set/list_set_field/dict_set_value as consuming the old receiver. Subsequent source statements read the updated receiver; branch joins merge the replacement receivers, not outstanding place reads. Single-owner donor/borrow checks and frontend E_MUTATION_OVERLAP refuse mutation of the same owner during index/replacement evaluation, rather than trying to infer disjoint dynamic indices.

Store rewrites exclude transfer stores via the one-use table; elements.dropDeadReads removes only unmarked reads (data0), and slice/fusion helpers require unmarked sources where relevant. Existing nested-list/dictionary native tests and the same-owner repeated exchange→overwrite fixture exercise optimized/unoptimized versions. P7/fixtures/ssa-protocol.my additionally gives two distinct u64 index parameters the same runtime slot, performs exchange in either runtime branch, then overwrites twice through the joined receiver. It must return the independent old owner and destroy both intermediate replacements in all5 RC and zero-RC modes. This source case demonstrates the valid versioned protocol rather than admitting malformed joined-token IR. P3 reviews (6856bcee5, b8ba78398) reported static invariant questions, not public-source native failures.

Strict008 recovery: recovery-008/qualification.json validates exact statuses/stdout/stderr for all142 original commands, all72 counting runs, installation/source/fixture identities and zero-RC LLVM, then runs4 corrected/refusal tail commands. Original type diagnostic mismatch (expected E_CALL_ARGUMENT, actual correct E_TYPE) remains preserved, including verify-008-original.py. Full install009 qualification supersedes008 for the event-key precomputation change.

## Final qualified009

Final compiler: `/home/epentland/ai/canopy/mylang-lox-eda-parity-20261013-p7/.tmp/lox-eda-parity/P7/green-install-009/bin/mylang`, SHA256 `8c8a87b66f68f401948eb1b23685d82220152b27fe71510f9de85ddfa3b140eb`. Full8-file prefix and exact source manifest: green-install-009.json. Source patch against base2525a66f61838086f5327d74db7412926ce4a221: compiler-source.patch.gz (uncompressed patch), SHA256 `cdb05fe45d66a5f8f61c90c8d39b4a2961e2a7ad61f942519dc58ced645b3c4b`. Component route/pin/seed flags are exactly the install command above; install9 passed Guardian88.

Qualification-009.json pins all source/install/evidence/native artifacts. Fresh verification009 passed175 commands with92 counting runs. All5 checked modes passed nested/wide/recursive ownership, repeated exchange/ordinary overwrite, exactly-once ordering, i8/u8 indexing, all4 bounds traps, generic scalar/Result return transfer, and matched runtime behavior. All5 RC snapshots passed independent old/replacement/snapshot mutations. Four branch/wide/protocol sources each ran in all5 RC and zero-RC modes with both runtime selector values; every success exited0 with exact stdout and empty stderr. Every counting run ended live0. Checked runs had zero runtime/shared retain/release/share counts and zero retain/release/unique_test kinds. Native LLVM for all5 main checked modes had no legacy RC calls. Discarded active wide payloads and wildcard fresh-match early returns were included.

The fixed10/10000-iteration binary had equal allocs/reallocs/allocated bytes/reallocated bytes/peak live/live-at-exit totals; no per-exchange allocation slope was observed. This is a dynamic argument experiment with observable equal outputs, not a folded compile-time loop. No performance ratio or runtime/RSS parity result is claimed by P7.

All12 focused Core tests passed again with final source (core-exchange-9.log). Enclosing build exit0 is explicitly recorded in core-exchange-9.process.json, alongside parsed PASS12. The runner printed slow-test diagnostics to stderr and Zig rendered warning label w/command; this was not a process failure. All raw one-use, branch, cross-block, loop and512-slot scaling cases plus existing nested list/dictionary regressions passed.

Final doc fence against009: docs-009/commands.json, build0/run42 in RC and zero-RC, no runtime stdout/stderr; enclosing exit0 in verify-docs-009.process.json. verify-docs-009-original.py preserves the exact executed harness. Current verify-docs.py uses the portable pinned fixtures/doc-exchange.my copy for future explicit-root reuse.

Final native verifier enclosing exit0: verify-009.process.json. Refusal commands intentionally exited1 and matched their exact required diagnostics: borrowed/moved replacement, overlapping index/replacement argument mutation, bare pending Result result, arity, wrong replacement type E_TYPE, concrete/generic pending-list overwrite E_RESULT_OVERWRITE, and three caller/local remaining-Result obligations E_RESULT_UNHANDLED. These pending-list regressions prevent the new scope-exit exemption from acknowledging caller or ordinary-local obligations.

Final reusable command interfaces:

```sh
source /home/epentland/.config/mylang/dev-env.sh
TMPDIR="$PWD/.tmp/lox-eda-parity/P7/tmp" scripts/build-slot.sh build python3   experiments/lox-eda-parity-20261013/P7/verify.py --root "$PWD"   --compiler "$PWD/.tmp/lox-eda-parity/P7/green-install-009/bin/mylang"   --output "$PWD/experiments/lox-eda-parity-20261013/P7/verification-NEW"
TMPDIR="$PWD/.tmp/lox-eda-parity/P7/tmp" scripts/build-slot.sh build python3   experiments/lox-eda-parity-20261013/P7/verify-docs.py --root "$PWD"   --compiler "$PWD/.tmp/lox-eda-parity/P7/green-install-009/bin/mylang"   --output "$PWD/experiments/lox-eda-parity-20261013/P7/docs-NEW"   --work "$PWD/.tmp/lox-eda-parity/P7/docs-NEW"
```

No production changes remain pending. Coordinator full integration gate/application builds/60-case measurement are separate required work. P7 performed no full timing benchmark, no RC fallback for the checked application, no historical-root writes, no Guardian feedback entry, and no push.

Source implementation commit: `958f683a1db29b8e541bd179a7f39a667b5c5503`, normal Guardian whole-tree88 passed. This source commit is qualified by009; subsequent evidence-only commits do not alter compiler source. Raw build/verifier logs and compiler-source.patch are retained byte-for-byte as deterministic `.gz` archives for Git whitespace hygiene. raw-archives.json pins both uncompressed and archive SHA256; process log hashes refer to the uncompressed payload. Working-tree raw copies remain available, and `gzip -dc FILE.gz` recovers each original.
