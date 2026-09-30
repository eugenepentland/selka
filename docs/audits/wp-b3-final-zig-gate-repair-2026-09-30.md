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

The full `zig build test --summary all` gate is pending on the committed repair. Root owns final integration and performance acceptance. Central Guardian feedback `382a155046f07bd10f9bf3e767d24df97984cbd1` records the original failure stage; the repair gate outcomes will be appended centrally after completion.
