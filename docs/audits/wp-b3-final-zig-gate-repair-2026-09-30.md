# Final Zig gate assertion repair — 2026-09-30

The pre-final gate at `5535e5a3f0b67e23d0fc9f92f594d7b3feb12a3f` failed 14 assertions: ten pin-summary cases, one receiver scope ordering case, one inline glue branch case, one ABI5 increment case and one directory host-limit receipt case. Its original `test.log` is retained byte for byte (SHA256 `3de415a6fa205ce61b76f89e21b7a6a153cc38e88e6cd01645c0275d50da2709`). This repair changes test assertions and one integration-test module import; compiler and native runtime source are unchanged.

Pin-summary tests now count the emitted inline journal operations, while preserving the exact pinned/elided counts, list descriptor, bookkeeping and native refusal paths. The receiver test checks begin/pin/end ordering in those operations. The glue branch oracle requires an SSA `w` predicate and rejects raw long/high-bit predicates; native word mode flags can branch directly. The ABI5 test checks the full-width increment/carry refusal before count or token storage. The normalized-mode receipt test uses the shared runtime identity rather than the rejected `rc-v3` string, while retaining its 8G installed host guard, 12G guest budget and 300000-frame reservation.

## Focused verification

| Check | Passing tests |
| --- | ---: |
| Pin summaries | 25 |
| Receiver scope ordering | 13 |
| Glue, including four predicate oracle boundaries | 18 |
| ABI5 increment | 13 |
| Directory host receipt CLI | 3 |
| Inline scope journal | 16 |
| Carry admission | 13 |
| Native contract / hold / stats / fast paths | 13 each |

These eleven invocations pass 153 tests, comprising 31 selected cases and repeated harness tests. The four native cases execute 25, 12, 4 and 27 C scenarios (68 total), including full-width MAX refusal and unchanged ownership/hold state on failure. All 13 unchanged pin fixtures execute under RC, GC and RC stats with exact numeric result and exit checks (39 runs). The existing nested-scope guest suite passes all three tests in RC, RC stats, GC and release (12 passes), including snapshots, arena receivers and reused multi-pin journals.

The compiler is SHA256 `700f2a7179f0f591d6e2fbf1317877293ef1393bc24a335c3983a872454a2fc2`; QBE is `2fd151269a0d37b6689e4a0f8a3b7830ae01ce977894b5281e512071b114a792`. Both are built from the unchanged production source at the failed gate tip. All builds and guests use the owned worktree's caches/TMPDIR and build-slot admission. No instruction measurements were taken.

## Evidence and outstanding gate

The [focused receipt](../../experiments/wp-b3-layout-20260929/zig-gate-repair/receipt.json) identifies the [raw archive](../../experiments/wp-b3-layout-20260929/zig-gate-repair/focused-evidence.tar.gz); its root `manifest.json` records every member's byte length and SHA256. It includes the original failure inventory/log, focused logs, extracted fixture sources, exact commands/results, and driver inputs.

Two scratch-driver failures are preserved and excluded: unsupported two-argument run `--cache-dir` syntax produced usage errors that the initial driver mistakenly accepted; the corrected driver then caught a wrong expected first element for the deliberately partial recursive sort fixture. The final driver requires exact output and exit and refuses usage errors. Neither rejected attempt is semantic acceptance evidence. The separate 12 nested-scope guest results and all native suite results were unaffected.

Root independently verified all 40 archive payload lengths/hashes, all 13 extracted fixture source hashes, all 39 exact fixture results and all 12 nested guest passes. Its verification receipt is included in the follow-up archive; this is independent hash/result verification, not duplicate execution.

## Reviewed assertion follow-up and full gate

Review strengthened two assertions further. The ABI5 oracle follows the exact long load through add-one, zero comparison, the matching refusal/capacity branch and status-2 failure path, then checks the exact new value is stored to the loaded count address only after admission. Its valid fragment plus eight negative mutations cover wrong load width, unrelated add/compare/branch operands, wrong refusal target, wrong published value/address and a premature store. The receiver oracle requires physical initialization and journal fields, a guarded commit and pin/end fallback calls using the same frame, with the actual callee after pin completion and before scope end. It rejects comment-only scopes, removed writes and a different scope passed to pin.

The full `zig build test --summary all` run at frozen test tip `06706119a7d6f563c45f5e0a6d00dd50e4ac7423` returned **1**: 113/115 steps succeeded, 2800 tests passed, 28493 shard exclusions and one failure. All original 14 failures passed. The sole remaining failure was `CLI computes and traces the same from QBE and from LLVM without LTO, with ThinLTO and with --release`: its first LLVM build expected empty stderr, but cold Zig emitted its `ar rcs … libunwind.a …` toolchain command. The entire failed log is preserved. The exact CLI fixture then passed unchanged (3/3, including two harness tests) with the library cache populated; the strict stderr expectation was retained. This focused repeat does not turn the failed full run into an accepted gate.

The final strengthened count oracle, actual ABI5 emission, receiver operations and unchanged CLI fixture pass 13, 13, 14 and 3 focused tests respectively. The new count oracle first caught a delimiter bug in the test helper itself: the bounded refusal block omitted the final newline, so even its valid fixture failed. That failed log is retained separately; the corrected helper passed all positive/negative cases. No compiler or runtime behavior changed in either repair commit, and the compiler/QBE hashes above remain stable.

The follow-up commit gate caught `bool-ops-per-condition` (six operations against a cap of three) and `line-length` (a 259-character fixture against the 240-character hard limit). Sequential guard checks and a multiline fixture corrected both; count and ABI5 focused suites were rerun afterward. The rejected patch and structured hook findings are retained in the follow-up archive.

The [follow-up archive](../../experiments/wp-b3-layout-20260929/zig-gate-repair/followup-evidence.tar.gz) retains the failed full gate, unchanged CLI repeat, strengthened test outputs, actual emitted IL, root verification and final patch, with a root `manifest.json` of member lengths/hashes. Per root coordination, the strengthened test-only change does not repeat the twelve-minute whole lane; the root's final gate will run on the fully composed source. That final gate and Phase B landing remain outside this scoped assertion repair. Central Guardian feedback `382a155046f07bd10f9bf3e767d24df97984cbd1` records the original failure stage; root will append these repair outcomes centrally.
